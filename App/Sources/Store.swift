import UIKit

extension Notification.Name {
    static let storeChanged = Notification.Name("PantryStoreChanged")     // packages, repos, banners or installed set changed
    static let stateChanged = Notification.Name("PantryStateChanged")     // install progress or prices changed
    static let paymentChanged = Notification.Name("PantryPaymentChanged") // a payment provider appeared or sign-in changed
    static let installFailed = Notification.Name("PantryInstallFailed")
}

enum Category: String, CaseIterable {
    case tweaks = "Tweaks", apps = "Apps", themes = "Themes"

    static func of(_ pkg: Package) -> Category {
        let s = pkg.section.lowercased()
        if s.contains("theme") { return .themes }
        if s.contains("tweak") || s.contains("addon") { return .tweaks }
        return .apps
    }
}

struct RepoStatus {
    var count: Int
    var error: String?
}

enum AddRepoResult { case added, invalid, duplicate }

/// App-wide state: sources, the package index, banners, what's installed, and install progress.
final class Store {
    static let shared = Store()

    let device = DeviceProfile.current()
    private(set) var repos: [Repo] = []
    private(set) var repoByID: [String: Repo] = [:]
    private(set) var status: [String: RepoStatus] = [:]
    private(set) var index: PackageIndex
    private(set) var installed = InstalledDatabase()
    private(set) var isLoading = false
    private(set) var progress: [String: Double] = [:]
    private(set) var banners: [String: [Banner]] = [:]          // by repo id
    private(set) var bannerByPackage: [String: Banner] = [:]    // by package identifier

    private var packages: [Package] = []
    private var needsRefresh = false
    private let defaultsKey = "com.foobtech.pantry.repos.v1"

    lazy var downloader = DebDownloader(cacheDir: URL(fileURLWithPath: "/var/mobile/Library/Caches/com.foobtech.pantry"))
    lazy var queue = InstallQueue(downloader: downloader, runner: SpawnRunner(device: device))

    private init() {
        index = PackageIndex(packages: [], device: device)
        repos = loadRepos()
        for r in repos { repoByID[r.id] = r }
        queue.onEvent = { [weak self] event in self?.handle(event) }
        // Paid packages: the payment provider issues the download link.
        queue.urlResolver = { pkg, done in
            DispatchQueue.main.async {
                guard pkg.isPaid, PaymentManager.shared.provider(for: pkg) != nil else { done(.success(nil)); return }
                PaymentManager.shared.authorizeDownload(pkg) { result in done(result.map { Optional($0) }) }
            }
        }
    }

    // MARK: Sources

    static func defaultRepos(scheme: JailbreakScheme) -> [Repo] {
        // Procursus suites are numbered by CoreFoundation version: iOS 12 = 1500, 15 = 1800, 16 = 1900, 17 = 2000.
        let cf = ProcessInfo.processInfo.operatingSystemVersion.majorVersion * 100 + 300
        var list: [Repo] = []
        switch scheme {
        case .rootful:
            list.append(Repo(url: URL(string: "https://apt.procurs.us/")!, suite: "iphoneos-arm/\(cf)", components: ["main"]))
        case .rootless, .roothide:
            list.append(Repo(url: URL(string: "https://apt.procurs.us/")!, suite: "\(cf)", components: ["main"]))
        }
        list.append(Repo(url: URL(string: "https://repo.chariz.com/")!))
        return list
    }

    private func loadRepos() -> [Repo] {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([Repo].self, from: data) { return saved }
        return Store.defaultRepos(scheme: device.scheme)
    }

    private func saveRepos() {
        if let data = try? JSONEncoder().encode(repos) { UserDefaults.standard.set(data, forKey: defaultsKey) }
    }

    /// Accepts "https://repo.example.com/" or the sources.list style "https://repo.example.com/ suite component".
    static func parseRepo(_ text: String) -> Repo? {
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
        guard var first = parts.first else { return nil }
        if !first.contains("://") { first = "https://" + first }
        guard let url = URL(string: first), url.host != nil else { return nil }
        if parts.count >= 2 {
            return Repo(url: url, suite: parts[1], components: parts.count > 2 ? Array(parts[2...]) : ["main"])
        }
        return Repo(url: url)
    }

    func addRepo(_ text: String) -> AddRepoResult {
        guard let repo = Store.parseRepo(text) else { return .invalid }
        if repoByID[repo.id] != nil { return .duplicate }
        repos.append(repo)
        repoByID[repo.id] = repo
        saveRepos()
        notifyData()
        refresh()
        return .added
    }

    func removeRepo(id: String) {
        repos.removeAll { $0.id == id }
        repoByID[id] = nil
        status[id] = nil
        banners[id] = nil
        rebuildBannerMap()
        packages.removeAll { $0.repoID == id }
        saveRepos()
        rebuildIndex()
        notifyData()
    }

    func host(of repo: Repo) -> String { repo.url.host ?? repo.url.absoluteString }
    func sourceName(for pkg: Package) -> String { repoByID[pkg.repoID].map { host(of: $0) } ?? "Unknown source" }

    // MARK: Packages

    func refresh() {
        if isLoading { needsRefresh = true; return }
        isLoading = true
        notifyData()

        let fetcher = RepoFetcher(device: device, decompressors: Decompressors(bzip2: Bzip2Decompressor()))
        let group = DispatchGroup()
        let lock = NSLock()
        var all: [Package] = []
        var newStatus: [String: RepoStatus] = [:]

        for repo in repos {
            group.enter()
            fetcher.fetchPackages(from: repo) { result in
                lock.lock()
                switch result {
                case .success(let pkgs):
                    all += pkgs
                    newStatus[repo.id] = RepoStatus(count: pkgs.count, error: nil)
                case .failure(let error):
                    newStatus[repo.id] = RepoStatus(count: 0, error: describe(error))
                }
                lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) {
            self.packages = all
            self.status = newStatus
            self.installed = InstalledDatabase.load(for: self.device)
            self.rebuildIndex()
            self.isLoading = false
            self.notifyData()
            self.loadBanners()
            PaymentManager.shared.discover(repos: self.repos)
            if self.needsRefresh { self.needsRefresh = false; self.refresh() }
        }
    }

    private func loadBanners() {
        for repo in repos {
            FeaturedLoader.load(repo) { [weak self] list in
                guard let self = self, self.repoByID[repo.id] != nil else { return }
                self.banners[repo.id] = list
                self.rebuildBannerMap()
                if !list.isEmpty { self.notifyData() }
            }
        }
    }

    private func rebuildBannerMap() {
        bannerByPackage = [:]
        for repo in repos {
            for b in banners[repo.id] ?? [] where bannerByPackage[b.packageID] == nil { bannerByPackage[b.packageID] = b }
        }
    }

    private func rebuildIndex() { index = PackageIndex(packages: packages, device: device) }

    func reloadInstalled() {
        installed = InstalledDatabase.load(for: device)
        notifyData()
    }

    func packages(in category: Category) -> [Package] {
        index.allLatest.filter { Category.of($0) == category }
    }

    /// Packages the repos feature with banner art, in repo order, that this device can use.
    func featuredPackages() -> [Package] {
        var seen = Set<String>()
        var out: [Package] = []
        for repo in repos {
            for b in banners[repo.id] ?? [] where seen.insert(b.packageID).inserted {
                if let p = index.latest(b.packageID) { out.append(p) }
            }
        }
        return out
    }

    func featuredPackages(in category: Category) -> [Package] {
        featuredPackages().filter { Category.of($0) == category }
    }

    /// A different, stable-for-the-day selection; packages with icons come first.
    static func dailyPicks(_ pkgs: [Package], count: Int, salt: String = "") -> [Package] {
        let day = String(Int(Date().timeIntervalSince1970 / 86400))
        func score(_ p: Package) -> (Int, UInt64) {
            (p.icon == nil ? 1 : 0, Theme.hash(p.identifier + day + salt))
        }
        return Array(pkgs.sorted { score($0) < score($1) }.prefix(count))
    }

    var statusText: String {
        if isLoading { return "Loading sources…" }
        if repos.isEmpty { return "No sources yet.\nTap the profile button (top right) to add one." }
        let errors = repos.compactMap { r in status[r.id]?.error.map { "\(host(of: r)): \($0)" } }
        if !errors.isEmpty { return errors.joined(separator: "\n") }
        return "No packages for this device yet."
    }

    // MARK: Install state

    func state(for pkg: Package) -> GetState {
        if let p = progress[pkg.identifier] { return .working(p) }
        if let have = installed.version(of: pkg.identifier) { return have < pkg.version ? .update : .installed }
        if pkg.isPaid {
            let pay = PaymentManager.shared
            if pay.provider(for: pkg) != nil {
                guard let info = pay.info(for: pkg) else { return .price("…") }
                if info.purchased { return .get }
                return .price(info.price ?? (info.available ? "BUY" : "N/A"))
            }
            if !pay.isDiscovered(pkg.repoID) { return .price("…") }
        }
        return .get
    }

    func beginInstall(_ plan: InstallPlan) {
        for p in plan.toInstall { progress[p.identifier] = 0.03 }
        notifyState()
        queue.install(plan, repos: repoByID)
    }

    func remove(_ pkg: Package) {
        progress[pkg.identifier] = 0.5
        notifyState()
        queue.remove(identifier: pkg.identifier)
    }

    private func handle(_ event: InstallEvent) {
        switch event {
        case .progress(let v):
            for k in Array(progress.keys) { progress[k] = max(v, 0.03) }
            notifyState()
        case .finished:
            progress = [:]
            notifyState()
            reloadInstalled()
        case .failed(let message):
            progress = [:]
            notifyState()
            NotificationCenter.default.post(name: .installFailed, object: nil, userInfo: ["message": message])
        default:
            break
        }
    }

    private func notifyData() { DispatchQueue.main.async { NotificationCenter.default.post(name: .storeChanged, object: nil) } }
    private func notifyState() { DispatchQueue.main.async { NotificationCenter.default.post(name: .stateChanged, object: nil) } }
}

enum InstallFlow {
    static func alert(_ vc: UIViewController?, _ title: String, _ message: String) {
        guard let vc = vc else { return }
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        (vc.presentedViewController ?? vc).present(a, animated: true)
    }

    static func install(_ pkg: Package, from vc: UIViewController?) {
        if PaymentManager.shared.needsPurchase(pkg) {
            PaymentManager.shared.purchase(pkg, from: vc)
            return
        }
        let store = Store.shared
        let plan = Resolver.plan(installing: pkg, index: store.index, installed: store.installed)
        guard plan.isInstallable else {
            alert(vc, "Can't install \(pkg.name)", "Missing dependencies:\n" + plan.unmet.joined(separator: "\n"))
            return
        }
        let others = plan.toInstall.filter { $0.identifier != pkg.identifier }.map { $0.name }
        if others.isEmpty || vc == nil {
            store.beginInstall(plan)
            return
        }
        let confirm = UIAlertController(title: "Install \(pkg.name)?",
                                        message: "This also installs: " + others.joined(separator: ", "),
                                        preferredStyle: .alert)
        confirm.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        confirm.addAction(UIAlertAction(title: "Install", style: .default) { _ in store.beginInstall(plan) })
        (vc?.presentedViewController ?? vc)?.present(confirm, animated: true)
    }

    static func updateAll(_ pkgs: [Package], from vc: UIViewController?) {
        let store = Store.shared
        var merged = InstallPlan(toInstall: [], unmet: [])
        var seen = Set<String>()
        for pkg in pkgs {
            let plan = Resolver.plan(installing: pkg, index: store.index, installed: store.installed)
            merged.unmet += plan.unmet
            for p in plan.toInstall where seen.insert(p.identifier).inserted { merged.toInstall.append(p) }
        }
        guard merged.isInstallable else {
            alert(vc, "Can't update", "Missing dependencies:\n" + merged.unmet.joined(separator: "\n"))
            return
        }
        store.beginInstall(merged)
    }

    static func remove(_ pkg: Package, from vc: UIViewController?) {
        guard let vc = vc else { return }
        let confirm = UIAlertController(title: "Remove \(pkg.name)?", message: nil, preferredStyle: .alert)
        confirm.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        confirm.addAction(UIAlertAction(title: "Remove", style: .destructive) { _ in Store.shared.remove(pkg) })
        (vc.presentedViewController ?? vc).present(confirm, animated: true)
    }
}
