import UIKit

extension Notification.Name {
    static let storeChanged = Notification.Name("PantryStoreChanged")
}

/// App-wide state: repos, the package index, what's installed, and the install queue.
final class Store {
    static let shared = Store()

    let device = DeviceProfile.current()
    private(set) var repos: [Repo] = []
    private(set) var repoByID: [String: Repo] = [:]
    private(set) var index: PackageIndex
    private(set) var installed = InstalledDatabase()
    private(set) var isLoading = false
    private(set) var lastError: String?

    lazy var downloader = DebDownloader(cacheDir: URL(fileURLWithPath: "/var/mobile/Library/Caches/com.foobtech.pantry"))
    lazy var queue = InstallQueue(downloader: downloader, runner: SpawnRunner(device: device))

    private init() {
        index = PackageIndex(packages: [], device: device)
        // Procursus suites are numbered by CoreFoundation version: iOS 15 = 1800, 16 = 1900, 17 = 2000.
        let cf = ProcessInfo.processInfo.operatingSystemVersion.majorVersion * 100 + 300
        let arch = device.scheme == .rootful ? "iphoneos-arm" : "iphoneos-arm64"
        repos = [
            Repo(url: URL(string: "https://apt.procurs.us/")!, suite: "\(arch)/\(cf)", components: ["main"]),
            Repo(url: URL(string: "https://repo.chariz.com/")!),
        ]
        for r in repos { repoByID[r.id] = r }
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        lastError = nil
        notify()

        let fetcher = RepoFetcher(device: device)
        let group = DispatchGroup()
        let lock = NSLock()
        var all: [Package] = []
        var errors: [String] = []

        for repo in repos {
            group.enter()
            fetcher.fetchPackages(from: repo) { result in
                lock.lock()
                switch result {
                case .success(let packages): all += packages
                case .failure(let error): errors.append("\(repo.url.host ?? repo.url.absoluteString): \(error)")
                }
                lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) {
            self.index = PackageIndex(packages: all, device: self.device)
            self.installed = InstalledDatabase.load(for: self.device)
            self.lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
            self.isLoading = false
            self.notify()
        }
    }

    func reloadInstalled() {
        installed = InstalledDatabase.load(for: device)
        notify()
    }

    func actionTitle(for pkg: Package) -> String {
        guard let have = installed.version(of: pkg.identifier) else { return "GET" }
        return have < pkg.version ? "UPDATE" : "INSTALLED"
    }

    private func notify() {
        NotificationCenter.default.post(name: .storeChanged, object: nil)
    }
}

enum InstallFlow {
    static func alert(_ vc: UIViewController, _ title: String, _ message: String) {
        let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        vc.present(a, animated: true)
    }

    static func install(_ pkg: Package, from vc: UIViewController) {
        let store = Store.shared
        let plan = Resolver.plan(installing: pkg, index: store.index, installed: store.installed)
        guard plan.isInstallable else {
            alert(vc, "Can't install", "Missing dependencies:\n" + plan.unmet.joined(separator: "\n"))
            return
        }
        let others = plan.toInstall.filter { $0.identifier != pkg.identifier }.map { $0.name }
        var message = "\(pkg.name) \(pkg.version)"
        if !others.isEmpty { message += "\n\nAlso installing: " + others.joined(separator: ", ") }

        let confirm = UIAlertController(title: "Install?", message: message, preferredStyle: .alert)
        confirm.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        confirm.addAction(UIAlertAction(title: "Install", style: .default) { _ in
            _ = progress(from: vc)
            store.queue.install(plan, repos: store.repoByID)
        })
        vc.present(confirm, animated: true)
    }

    static func remove(_ pkg: Package, from vc: UIViewController) {
        let confirm = UIAlertController(title: "Remove \(pkg.name)?", message: nil, preferredStyle: .alert)
        confirm.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        confirm.addAction(UIAlertAction(title: "Remove", style: .destructive) { _ in
            _ = progress(from: vc)
            Store.shared.queue.remove(identifier: pkg.identifier)
        })
        vc.present(confirm, animated: true)
    }

    private static func progress(from vc: UIViewController) -> UIAlertController {
        let a = UIAlertController(title: "Working…", message: nil, preferredStyle: .alert)
        vc.present(a, animated: true)
        Store.shared.queue.onEvent = { [weak a] event in
            guard let a = a else { return }
            switch event {
            case .downloading(let p): a.message = "Downloading \(p.name)…"
            case .installing(let p): a.message = "Installing \(p.name)…"
            case .refreshingIcons: a.message = "Refreshing icons…"
            case .finished:
                Store.shared.reloadInstalled()
                a.dismiss(animated: true)
            case .failed(let text):
                Store.shared.reloadInstalled()
                a.title = "Failed"
                a.message = text
                a.addAction(UIAlertAction(title: "OK", style: .default))
            }
        }
        return a
    }
}
