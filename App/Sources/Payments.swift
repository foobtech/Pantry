import UIKit
import AuthenticationServices
import Security
import Darwin

// Paid tweaks, following the Payment Provider API that Sileo and Zebra both use
// (https://developer.getsileo.app/payment-providers).
//  - A repo serves /payment_endpoint: plain text, the provider's HTTPS base URL.
//  - The provider answers GET /info, POST /user_info, /package/<id>/info, /purchase, /authorize_download, /sign_out.
//  - Sign-in and checkout happen on the provider's own web pages (ASWebAuthenticationSession).

struct PaymentProvider {
    let endpoint: URL          // always ends with "/"
    var name: String
    var iconURL: String?
    var details: String
    var bannerMessage: String?
    var bannerButton: String?
}

struct PaymentInfo {
    var price: String?
    var purchased: Bool
    var available: Bool
    var error: String?
    var recoveryURL: String?
}

struct PaymentCredentials: Codable {
    var token: String
    var secret: String?
}

enum PaymentError: LocalizedError {
    case message(String)
    case signedOut(String)

    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        case .signedOut(let provider): return "Sign in to \(provider) from your account, then try again."
        }
    }
}

enum DeviceID {
    /// The UDID, which payment providers use to tie a purchase to a device.
    /// Read from MobileGestalt at runtime; may come back empty if the entitlement isn't honoured.
    static let udid: String = {
        typealias Fn = @convention(c) (CFString) -> Unmanaged<CFTypeRef>?
        guard let lib = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_NOW),
              let symbol = dlsym(lib, "MGCopyAnswer") else { return "" }
        let fn = unsafeBitCast(symbol, to: Fn.self)
        if let value = fn("UniqueDeviceID" as CFString)?.takeRetainedValue() as? String { return value }
        return ""
    }()
}

/// Tokens go in the keychain; if the keychain refuses (missing entitlement), a preferences entry is the fallback.
enum CredentialStore {
    private static let service = "com.foobtech.pantry.payments"

    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    static func load(_ key: String) -> PaymentCredentials? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data,
           let creds = try? JSONDecoder().decode(PaymentCredentials.self, from: data) { return creds }
        if let data = UserDefaults.standard.data(forKey: "pantry.payment." + key) {
            return try? JSONDecoder().decode(PaymentCredentials.self, from: data)
        }
        return nil
    }

    static func save(_ creds: PaymentCredentials, key: String) {
        guard let data = try? JSONEncoder().encode(creds) else { return }
        delete(key)
        var q = query(key)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        if SecItemAdd(q as CFDictionary, nil) != errSecSuccess {
            UserDefaults.standard.set(data, forKey: "pantry.payment." + key)
        }
    }

    static func delete(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "pantry.payment." + key)
    }
}

/// Main-thread only.
final class PaymentManager: NSObject {
    static let shared = PaymentManager()

    private(set) var providers: [String: PaymentProvider] = [:]   // by repo id
    private(set) var userNames: [String: String] = [:]            // by provider endpoint
    private var discovered = Set<String>()
    private var infos: [String: PaymentInfo] = [:]
    private var inFlight = Set<String>()
    private var authSession: Any?

    var uniqueProviders: [PaymentProvider] {
        var seen = Set<String>()
        var out: [PaymentProvider] = []
        for repo in Store.shared.repos {
            if let p = providers[repo.id], seen.insert(p.endpoint.absoluteString).inserted { out.append(p) }
        }
        return out
    }

    func provider(for pkg: Package) -> PaymentProvider? { providers[pkg.repoID] }
    func isDiscovered(_ repoID: String) -> Bool { discovered.contains(repoID) }
    func isSignedIn(_ p: PaymentProvider) -> Bool { CredentialStore.load(p.endpoint.absoluteString) != nil }
    func signedInName(_ p: PaymentProvider) -> String? { userNames[p.endpoint.absoluteString] }

    // MARK: Discovery

    func discover(repos: [Repo]) {
        for repo in repos where !discovered.contains(repo.id) {
            discovered.insert(repo.id)
            fetch(repo.url.appendingPathComponent("payment_endpoint")) { [weak self] data in
                guard let self = self else { return }
                guard let data = data,
                      let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      text.hasPrefix("https://"), !text.contains(" "), let endpoint = URL(string: text) else {
                    self.notifyProviders()   // "no provider" is an answer too: paid-looking packages stop waiting
                    return
                }
                let base = text.hasSuffix("/") ? endpoint : (URL(string: text + "/") ?? endpoint)
                self.fetch(base.appendingPathComponent("info")) { data in
                    var provider = PaymentProvider(endpoint: base, name: base.host ?? "Payment provider", iconURL: nil,
                                                   details: "", bannerMessage: nil, bannerButton: nil)
                    if let data = data, let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                        provider.name = (json["name"] as? String) ?? provider.name
                        provider.iconURL = json["icon"] as? String
                        provider.details = (json["description"] as? String) ?? ""
                        if let banner = json["authentication_banner"] as? [String: Any] {
                            provider.bannerMessage = banner["message"] as? String
                            provider.bannerButton = banner["button"] as? String
                        }
                    }
                    self.providers[repo.id] = provider
                    self.refreshUserName(provider)
                    self.notifyProviders()
                }
            }
        }
    }

    // MARK: Package info

    private func packageURL(_ p: PaymentProvider, _ pkg: Package, _ action: String) -> URL? {
        let id = pkg.identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pkg.identifier
        return URL(string: p.endpoint.absoluteString + "package/\(id)/\(action)")
    }

    private func infoKey(_ p: PaymentProvider, _ pkg: Package) -> String { p.endpoint.absoluteString + "|" + pkg.identifier }

    /// Cached price / purchased status; starts a request the first time and returns nil until it arrives.
    func info(for pkg: Package) -> PaymentInfo? {
        guard let p = providers[pkg.repoID] else { return nil }
        let key = infoKey(p, pkg)
        if let hit = infos[key] { return hit }
        if !inFlight.contains(key), let url = packageURL(p, pkg, "info") {
            inFlight.insert(key)
            post(url, body(p)) { [weak self] json in
                guard let self = self else { return }
                var info = PaymentInfo(price: nil, purchased: false, available: true, error: nil, recoveryURL: nil)
                if let json = json {
                    if json["invalidate"] as? Bool == true { self.signedOutLocally(p) }
                    if let error = json["error"] as? String {
                        info.available = false
                        info.error = error
                        info.recoveryURL = json["recovery_url"] as? String
                    } else {
                        info.price = json["price"] as? String
                        info.purchased = (json["purchased"] as? Bool) ?? false
                        info.available = (json["available"] as? Bool) ?? true
                    }
                } else {
                    info.available = false
                    info.error = "\(p.name) didn't answer."
                }
                self.infos[key] = info
                self.inFlight.remove(key)
                self.notifyRows()
            }
        }
        return nil
    }

    /// True when installing needs a purchase first (or we're still finding out).
    func needsPurchase(_ pkg: Package) -> Bool {
        guard pkg.isPaid, providers[pkg.repoID] != nil else { return false }
        guard let info = info(for: pkg) else { return true }
        return !info.purchased
    }

    private func refreshInfo(for pkg: Package) {
        guard let p = providers[pkg.repoID] else { return }
        infos[infoKey(p, pkg)] = nil
        _ = info(for: pkg)
        notifyRows()
    }

    // MARK: Sign in / out

    func signIn(_ p: PaymentProvider, from vc: UIViewController?, completion: @escaping (Bool) -> Void) {
        var comps = URLComponents(url: p.endpoint.appendingPathComponent("authenticate"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "udid", value: DeviceID.udid),
                             URLQueryItem(name: "model", value: Store.shared.device.machine)]
        guard let url = comps?.url else { completion(false); return }
        // Providers redirect to sileo://authentication_success?token=...&payment_secret=...
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "sileo") { [weak self] callback, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.authSession = nil
                guard let callback = callback,
                      let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
                      let token = items.first(where: { $0.name == "token" })?.value else { completion(false); return }
                let secret = items.first(where: { $0.name == "payment_secret" })?.value
                CredentialStore.save(PaymentCredentials(token: token, secret: secret), key: p.endpoint.absoluteString)
                self.infos.removeAll()
                self.inFlight.removeAll()
                self.refreshUserName(p)
                self.notifyProviders()
                completion(true)
            }
        }
        if #available(iOS 13.0, *) { session.presentationContextProvider = self }
        authSession = session
        session.start()
    }

    func signOut(_ p: PaymentProvider) {
        let key = p.endpoint.absoluteString
        if let creds = CredentialStore.load(key), let url = URL(string: key + "sign_out") {
            post(url, ["token": creds.token]) { _ in }
        }
        signedOutLocally(p)
    }

    private func signedOutLocally(_ p: PaymentProvider) {
        let key = p.endpoint.absoluteString
        CredentialStore.delete(key)
        userNames[key] = nil
        infos.removeAll()
        inFlight.removeAll()
        notifyProviders()
    }

    private func refreshUserName(_ p: PaymentProvider) {
        let key = p.endpoint.absoluteString
        guard CredentialStore.load(key) != nil, let url = URL(string: key + "user_info") else { return }
        post(url, body(p)) { [weak self] json in
            guard let self = self else { return }
            if json?["invalidate"] as? Bool == true { self.signedOutLocally(p); return }
            if let user = json?["user"] as? [String: Any], let name = user["name"] as? String {
                self.userNames[key] = name
                self.notifyProviders()
            }
        }
    }

    // MARK: Buying and downloading

    func purchase(_ pkg: Package, from vc: UIViewController?) {
        guard let p = providers[pkg.repoID], let vc = vc else { return }
        guard let info = info(for: pkg) else {
            InstallFlow.alert(vc, "One moment", "Still checking this package with \(p.name).")
            return
        }
        if !info.available {
            InstallFlow.alert(vc, "Not available", info.error ?? "This package can't be bought right now.")
            return
        }
        guard CredentialStore.load(p.endpoint.absoluteString) != nil else {
            signIn(p, from: vc) { [weak self] ok in
                if ok { self?.purchase(pkg, from: vc) }
            }
            return
        }
        let price = info.price ?? ""
        let confirm = UIAlertController(title: "Buy \(pkg.name)?",
                                        message: price.isEmpty ? "Purchase through \(p.name)." : "\(price) through \(p.name).",
                                        preferredStyle: .alert)
        confirm.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        confirm.addAction(UIAlertAction(title: price.isEmpty ? "Buy" : "Buy \(price)", style: .default) { [weak self] _ in
            self?.startPurchase(pkg, p, from: vc)
        })
        (vc.presentedViewController ?? vc).present(confirm, animated: true)
    }

    private func startPurchase(_ pkg: Package, _ p: PaymentProvider, from vc: UIViewController) {
        guard let url = packageURL(p, pkg, "purchase"), let creds = CredentialStore.load(p.endpoint.absoluteString) else { return }
        let secret: Any = creds.secret ?? NSNull()
        post(url, ["token": creds.token, "payment_secret": secret]) { [weak self] json in
            guard let self = self else { return }
            if json?["invalidate"] as? Bool == true { self.signedOutLocally(p) }
            if let error = json?["error"] as? String {
                InstallFlow.alert(vc, "Couldn't buy \(pkg.name)", error)
                return
            }
            switch json?["status"] as? Int {
            case .some(0):
                self.refreshInfo(for: pkg)
            case .some(1):
                // The provider needs the user to finish checkout on its own page.
                if let s = json?["url"] as? String, let u = URL(string: s) {
                    self.openCheckout(u) { self.refreshInfo(for: pkg) }
                } else {
                    InstallFlow.alert(vc, "Couldn't buy \(pkg.name)", "\(p.name) didn't say how to finish the purchase.")
                }
            default:
                InstallFlow.alert(vc, "Couldn't buy \(pkg.name)", "\(p.name) declined the purchase.")
            }
        }
    }

    private func openCheckout(_ url: URL, done: @escaping () -> Void) {
        // The checkout page ends by redirecting to sileo://payment_completed.
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "sileo") { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.authSession = nil
                done()
            }
        }
        if #available(iOS 13.0, *) { session.presentationContextProvider = self }
        authSession = session
        session.start()
    }

    /// Paid downloads don't use the repo's link: the provider hands out a one-time HTTPS URL.
    func authorizeDownload(_ pkg: Package, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let p = providers[pkg.repoID] else { completion(.failure(PaymentError.message("No payment provider for this source."))); return }
        guard CredentialStore.load(p.endpoint.absoluteString) != nil, let url = packageURL(p, pkg, "authorize_download") else {
            completion(.failure(PaymentError.signedOut(p.name)))
            return
        }
        var repoString = Store.shared.repoByID[pkg.repoID]?.url.absoluteString ?? ""
        if repoString.hasSuffix("/") { repoString.removeLast() }
        let extra: [String: Any] = ["version": pkg.version.raw, "repo": repoString, "architecture": pkg.architecture]
        post(url, body(p, extra)) { json in
            if let error = json?["error"] as? String {
                completion(.failure(PaymentError.message(error)))
                return
            }
            guard let s = json?["url"] as? String, s.hasPrefix("https://"), let u = URL(string: s) else {
                completion(.failure(PaymentError.message("\(p.name) didn't give a download link.")))
                return
            }
            completion(.success(u))
        }
    }

    // MARK: Networking

    private func body(_ p: PaymentProvider, _ extra: [String: Any] = [:]) -> [String: Any] {
        var b: [String: Any] = ["udid": DeviceID.udid, "device": Store.shared.device.machine]
        if let creds = CredentialStore.load(p.endpoint.absoluteString) { b["token"] = creds.token }
        for (k, v) in extra { b[k] = v }
        return b
    }

    private func fetch(_ url: URL, completion: @escaping (Data?) -> Void) {
        var request = URLRequest(url: url)
        request.setValue("Pantry/0.1", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, resp, _ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(ok ? data : nil) }
        }.resume()
    }

    private func post(_ url: URL, _ json: [String: Any], completion: @escaping ([String: Any]?) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Pantry/0.1", forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: json)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let parsed = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            DispatchQueue.main.async { completion(parsed) }
        }.resume()
    }

    private func notifyRows() {
        NotificationCenter.default.post(name: .stateChanged, object: nil)
    }

    private func notifyProviders() {
        NotificationCenter.default.post(name: .paymentChanged, object: nil)
        NotificationCenter.default.post(name: .stateChanged, object: nil)
    }
}

@available(iOS 13.0, *)
extension PaymentManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.keyWindow ?? ASPresentationAnchor()
    }
}
