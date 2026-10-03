import UIKit

// MARK: - Tabs

final class MainTabController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        viewControllers = [
            nav(TodayController(), "Today", ["sun.max.fill"], .today),
            nav(CategoryController(.tweaks), "Tweaks", ["puzzlepiece.fill", "gearshape.fill"], .tweaks),
            nav(CategoryController(.apps), "Apps", ["square.stack.3d.up.fill", "square.grid.2x2.fill"], .apps),
            nav(CategoryController(.themes), "Themes", ["paintbrush.fill", "paintpalette.fill"], .themes),
            nav(SearchController(), "Search", ["magnifyingglass"], .search),
        ]
        NotificationCenter.default.addObserver(self, selector: #selector(installFailed(_:)),
                                               name: .installFailed, object: nil)
    }

    /// `symbols` are tried in order (newer SF Symbols first); filled variants, like the App Store.
    private func nav(_ root: UIViewController, _ title: String, _ symbols: [String], _ kind: TabIcons.Kind) -> UINavigationController {
        let nav = UINavigationController(rootViewController: root)
        nav.setNavigationBarHidden(true, animated: false)
        var image: UIImage?
        if #available(iOS 13.0, *) {
            let config = UIImage.SymbolConfiguration(weight: .semibold)
            for name in symbols {
                if let found = UIImage(systemName: name, withConfiguration: config) { image = found; break }
            }
        } else {
            image = TabIcons.image(kind)
        }
        nav.tabBarItem = UITabBarItem(title: title, image: image, tag: 0)
        return nav
    }

    @objc private func installFailed(_ note: Notification) {
        var message = (note.userInfo?["message"] as? String) ?? "Something went wrong."
        if message.count > 400 { message = String(message.prefix(400)) + "…" }
        InstallFlow.alert(self, "Couldn't finish", message)
    }
}

// MARK: - Base page

/// A scrolling page made of blocks. Subclasses override `rebuild()`.
class BlockPageController: UIViewController {
    let scroll = BlockScrollView()
    var hidesNavBar: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        scroll.frame = view.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.contentInsetAdjustmentBehavior = .always
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .onDrag
        view.addSubview(scroll)

        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(pull), for: .valueChanged)
        scroll.refreshControl = refresh
        NotificationCenter.default.addObserver(self, selector: #selector(dataChanged), name: .storeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(dataChanged), name: .paymentChanged, object: nil)
        rebuild()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(hidesNavBar, animated: animated)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in self.scroll.setNeedsLayout() }, completion: nil)
    }

    func rebuild() {}

    @objc private func pull() { Store.shared.refresh() }

    @objc private func dataChanged() {
        if !Store.shared.isLoading { scroll.refreshControl?.endRefreshing() }
        rebuild()
    }
}

// MARK: - Today

final class TodayController: BlockPageController {
    override func rebuild() {
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMMM"
        var blocks: [BlockView] = [HeaderBlock(title: "Today", date: f.string(from: Date()).uppercased())]
        let all = Store.shared.index.allLatest
        if all.isEmpty {
            blocks.append(MessageBlock(Store.shared.statusText))
        } else {
            var picks = Store.shared.featuredPackages()
            for p in Store.dailyPicks(all, count: 13) where !picks.contains(where: { $0.identifier == p.identifier }) {
                picks.append(p)
            }
            picks = Array(picks.prefix(13))
            if let hero = picks.first {
                blocks.append(TodayHeroBlock(hero: hero, list: Array(picks.dropFirst().prefix(4)), listTitle: "Top picks today"))
            }
            var rest = Array(picks.dropFirst(5))
            while rest.count >= 2 {
                blocks.append(TwoUpCardsBlock(rest[0], rest[1]))
                rest.removeFirst(2)
            }
            if let last = rest.first { blocks.append(TwoUpCardsBlock(last, nil)) }
        }
        scroll.blocks = blocks
    }
}

// MARK: - Tweaks / Apps / Themes

final class CategoryController: BlockPageController {
    private let category: Category

    init(_ category: Category) {
        self.category = category
        super.init(nibName: nil, bundle: nil)
        title = category.rawValue
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func openList(_ title: String, _ pkgs: [Package]) {
        navigationController?.pushViewController(ListController(title, pkgs), animated: true)
    }

    override func rebuild() {
        var blocks: [BlockView] = [HeaderBlock(title: category.rawValue)]
        let pkgs = Store.shared.packages(in: category)
        if pkgs.isEmpty {
            blocks.append(MessageBlock(Store.shared.index.allLatest.isEmpty
                                       ? Store.shared.statusText : "Nothing in \(category.rawValue) yet."))
        } else {
            var featured = Store.shared.featuredPackages(in: category)
            for p in Store.dailyPicks(pkgs, count: 6) where !featured.contains(where: { $0.identifier == p.identifier }) {
                featured.append(p)
            }
            blocks.append(CardShelfBlock(Array(featured.prefix(6)), label: category == .themes ? "Theme" : "Featured"))
            let picks = Store.dailyPicks(pkgs, count: 12, salt: "shelf")
            blocks.append(SectionHeaderBlock(title: "Staff Picks", subtitle: "Fresh picks for today",
                                             seeAll: { [weak self] in self?.openList("Staff Picks", picks) }))
            blocks.append(RowShelfBlock(picks))
            for repo in Store.shared.repos {
                let items = pkgs.filter { $0.repoID == repo.id }.sorted { $0.name.lowercased() < $1.name.lowercased() }
                if items.isEmpty { continue }
                let title = "From " + Store.shared.host(of: repo)
                blocks.append(SectionHeaderBlock(title: title, seeAll: { [weak self] in self?.openList(title, items) }))
                blocks.append(RowShelfBlock(Array(items.prefix(12))))
            }
        }
        scroll.blocks = blocks
    }
}

// MARK: - See All

final class ListController: BlockPageController {
    override var hidesNavBar: Bool { false }
    private let packages: [Package]

    init(_ title: String, _ packages: [Package]) {
        self.packages = packages
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func rebuild() {
        scroll.blocks = [HeaderBlock(title: title ?? "", avatar: false), RowGridBlock(packages)]
    }
}

// MARK: - Search

final class SearchController: BlockPageController, UISearchBarDelegate {
    private let header = HeaderBlock(title: "Search")
    private let searchBlock = SearchBarBlock()
    private var query = ""

    override func viewDidLoad() {
        searchBlock.bar.delegate = self
        super.viewDidLoad()
    }

    override func rebuild() {
        var blocks: [BlockView] = [header, searchBlock]
        let all = Store.shared.index.allLatest
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if all.isEmpty {
            blocks.append(MessageBlock(Store.shared.statusText))
        } else if q.isEmpty {
            let picks = Store.dailyPicks(all, count: 18, salt: "search")
            blocks.append(SuggestionsBlock(terms: picks.prefix(6).map { $0.name }) { [weak self] term in self?.pick(term) })
            blocks.append(SectionHeaderBlock(title: "Suggested"))
            blocks.append(RowGridBlock(Array(picks.dropFirst(6).prefix(12))))
        } else {
            let hits = all.filter {
                $0.name.lowercased().contains(q) || $0.identifier.lowercased().contains(q)
                    || $0.shortDescription.lowercased().contains(q)
            }.sorted { a, b in
                let ap = a.name.lowercased().hasPrefix(q), bp = b.name.lowercased().hasPrefix(q)
                if ap != bp { return ap }
                return a.name.lowercased() < b.name.lowercased()
            }
            blocks.append(hits.isEmpty ? MessageBlock("No results for \u{201C}\(query)\u{201D}") : RowGridBlock(Array(hits.prefix(60))))
        }
        scroll.blocks = blocks
    }

    private func pick(_ term: String) {
        searchBlock.bar.text = term
        query = term
        searchBlock.bar.resignFirstResponder()
        rebuild()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        query = searchText
        rebuild()
    }

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) { searchBar.setShowsCancelButton(true, animated: true) }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = ""
        query = ""
        searchBar.setShowsCancelButton(false, animated: true)
        searchBar.resignFirstResponder()
        rebuild()
    }
}

// MARK: - Product page

final class ProductController: BlockPageController {
    override var hidesNavBar: Bool { false }
    private let pkg: Package
    private var shots: [Screenshot] = []

    init(_ pkg: Package) {
        self.pkg = pkg
        super.init(nibName: nil, bundle: nil)
        navigationItem.largeTitleDisplayMode = .never
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        DepictionLoader.depiction(for: pkg) { [weak self] depiction in
            guard let self = self, !depiction.screenshots.isEmpty else { return }
            self.shots = depiction.screenshots
            self.rebuild()
        }
    }

    private func developer(_ raw: String) -> String {
        var name = raw
        if let lt = name.firstIndex(of: "<") { name = String(name[name.startIndex..<lt]) }
        name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Unknown" : name
    }

    override func rebuild() {
        let store = Store.shared
        let size = pkg.size > 0 ? ByteCountFormatter.string(fromByteCount: Int64(pkg.size), countStyle: .file) : "\u{2014}"
        let dev = developer(pkg.author.isEmpty ? pkg.maintainer : pkg.author)
        let source = store.sourceName(for: pkg)
        let deps = pkg.depends.compactMap { $0.first?.name }.filter { $0 != "firmware" }

        var blocks: [BlockView] = [
            ProductHeaderBlock(pkg),
            StatsBlock([
                (caption: "Size", value: size),
                (caption: "Version", value: pkg.version.raw),
                (caption: "Category", value: pkg.section),
                (caption: "Developer", value: dev),
                (caption: "Source", value: source),
            ]),
        ]
        if !shots.isEmpty { blocks.append(ScreenshotsBlock(shots)) }
        let body = pkg.longDescription.isEmpty ? pkg.shortDescription : pkg.longDescription
        blocks.append(TextBlock(title: "Description", body: body))
        blocks.append(InfoBlock(title: "Information", rows: [
            ("Source", source),
            ("Identifier", pkg.identifier),
            ("Architecture", pkg.architecture),
            ("Depends", deps.isEmpty ? "None" : deps.joined(separator: ", ")),
        ]))
        scroll.blocks = blocks
    }
}

// MARK: - Source page

/// One source: its banners, its payment sign-in prompt, a few packages, and Remove.
final class RepoController: BlockPageController {
    override var hidesNavBar: Bool { false }
    private let repo: Repo

    init(_ repo: Repo) {
        self.repo = repo
        super.init(nibName: nil, bundle: nil)
        title = Store.shared.host(of: repo)
        navigationItem.largeTitleDisplayMode = .never
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func rebuild() {
        let store = Store.shared
        var blocks: [BlockView] = [HeaderBlock(title: store.host(of: repo), avatar: false)]
        if let st = store.status[repo.id] {
            blocks.append(SectionHeaderBlock(title: st.error == nil ? "\(st.count) packages" : "Couldn't load this source",
                                             subtitle: st.error))
        }
        let banners = store.banners[repo.id] ?? []
        if !banners.isEmpty { blocks.append(BannerStripBlock(banners)) }
        if let provider = PaymentManager.shared.providers[repo.id], !PaymentManager.shared.isSignedIn(provider),
           let message = provider.bannerMessage {
            blocks.append(PaymentBannerBlock(provider, message: message))
        }
        let pkgs = store.index.allLatest.filter { $0.repoID == repo.id }.sorted { $0.name.lowercased() < $1.name.lowercased() }
        if !pkgs.isEmpty {
            blocks.append(SectionHeaderBlock(title: "Packages", seeAll: { [weak self] in
                self?.navigationController?.pushViewController(ListController(self?.title ?? "Packages", pkgs), animated: true)
            }))
            blocks.append(RowShelfBlock(Array(pkgs.prefix(12))))
        }
        blocks.append(ButtonBlock(title: "Remove Source", destructive: true) { [weak self] in self?.confirmRemove() })
        scroll.blocks = blocks
    }

    private func confirmRemove() {
        let alert = UIAlertController(title: "Remove \(Store.shared.host(of: repo))?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            Store.shared.removeRepo(id: self.repo.id)
            self.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }
}

// MARK: - Account (updates, sources, payment providers)

/// The App Store keeps updates and account settings behind the profile button; Pantry does the same,
/// plus sources and payment providers (like Sileo's settings).
final class AccountController: UITableViewController {
    private var updates: [Package] = []
    private var providers: [PaymentProvider] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Account"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "plain")
        tableView.register(RowCell.self, forCellReuseIdentifier: "row")
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .storeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .paymentChanged, object: nil)
        reload()
    }

    @objc private func done() { dismiss(animated: true) }

    @objc private func reload() {
        let store = Store.shared
        updates = store.installed.versions.compactMap { id, have -> Package? in
            guard let latest = store.index.latest(id), latest.version > have else { return nil }
            return latest
        }.sorted { $0.name.lowercased() < $1.name.lowercased() }
        providers = PaymentManager.shared.uniqueProviders
        tableView.reloadData()
    }

    // Sections: 0 updates, 1 sources, 2 payment providers, 3 about
    override func numberOfSections(in tableView: UITableView) -> Int { 4 }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["Updates", "Sources", "Payment Providers", "About"][section]
    }

    private var updateRowCount: Int { updates.isEmpty ? 1 : updates.count + (updates.count > 1 ? 1 : 0) }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return updateRowCount
        case 1: return Store.shared.repos.count + 1
        case 2: return max(providers.count, 1)
        default: return 3
        }
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == 0, !updates.isEmpty, !(updates.count > 1 && indexPath.row == 0) { return PackageRowView.height }
        return 52
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let store = Store.shared
        switch indexPath.section {
        case 0:
            if updates.isEmpty {
                let cell = tableView.dequeueReusableCell(withIdentifier: "plain", for: indexPath)
                cell.textLabel?.text = store.isLoading ? "Checking for updates…" : "Everything is up to date"
                cell.textLabel?.textColor = Theme.secondaryText
                cell.selectionStyle = .none
                return cell
            }
            if updates.count > 1 && indexPath.row == 0 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "plain", for: indexPath)
                cell.textLabel?.text = "Update All (\(updates.count))"
                cell.textLabel?.textColor = Theme.accent
                return cell
            }
            let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath) as! RowCell
            cell.configure(updates[indexPath.row - (updates.count > 1 ? 1 : 0)])
            return cell
        case 1:
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            if indexPath.row < store.repos.count {
                let repo = store.repos[indexPath.row]
                cell.textLabel?.text = store.host(of: repo) + (repo.isFlat ? "" : "  \(repo.suite)")
                if let st = store.status[repo.id] {
                    if let error = st.error {
                        cell.detailTextLabel?.text = error
                        cell.detailTextLabel?.textColor = .red
                    } else {
                        cell.detailTextLabel?.text = "\(st.count) packages"
                        cell.detailTextLabel?.textColor = Theme.secondaryText
                    }
                } else {
                    cell.detailTextLabel?.text = store.isLoading ? "Loading…" : "Not loaded yet"
                    cell.detailTextLabel?.textColor = Theme.secondaryText
                }
                cell.accessoryType = .disclosureIndicator
            } else {
                cell.textLabel?.text = "Add Source\u{2026}"
                cell.textLabel?.textColor = Theme.accent
            }
            return cell
        case 2:
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
            if providers.isEmpty {
                cell.textLabel?.text = "None found"
                cell.textLabel?.textColor = Theme.secondaryText
                cell.detailTextLabel?.text = "Sources that sell tweaks list their payment provider here."
                cell.detailTextLabel?.textColor = Theme.secondaryText
                cell.selectionStyle = .none
            } else {
                let p = providers[indexPath.row]
                cell.textLabel?.text = p.name
                if PaymentManager.shared.isSignedIn(p) {
                    let name = PaymentManager.shared.signedInName(p)
                    cell.detailTextLabel?.text = name.map { "Signed in as \($0)" } ?? "Signed in"
                    cell.detailTextLabel?.textColor = Theme.accent
                } else {
                    cell.detailTextLabel?.text = p.details.isEmpty ? "Sign in to buy and download" : p.details
                    cell.detailTextLabel?.textColor = Theme.secondaryText
                }
                cell.accessoryType = .disclosureIndicator
            }
            return cell
        default:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.selectionStyle = .none
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "Device"
                cell.detailTextLabel?.text = "\(store.device.machine), iOS \(store.device.iOSVersion.raw)"
            case 1:
                cell.textLabel?.text = "Jailbreak"
                cell.detailTextLabel?.text = "\(store.device.scheme.rawValue) (\(store.device.architectures.joined(separator: ", ")))"
            default:
                cell.textLabel?.text = "Installed packages"
                cell.detailTextLabel?.text = "\(store.installed.versions.count)"
            }
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let store = Store.shared
        switch indexPath.section {
        case 0:
            if updates.count > 1, indexPath.row == 0 { InstallFlow.updateAll(updates, from: self) }
        case 1:
            if indexPath.row < store.repos.count {
                navigationController?.pushViewController(RepoController(store.repos[indexPath.row]), animated: true)
            } else {
                promptAddSource()
            }
        case 2:
            guard !providers.isEmpty else { return }
            let p = providers[indexPath.row]
            if PaymentManager.shared.isSignedIn(p) {
                let sheet = UIAlertController(title: p.name, message: "Sign out of this payment provider?", preferredStyle: .alert)
                sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                sheet.addAction(UIAlertAction(title: "Sign Out", style: .destructive) { _ in PaymentManager.shared.signOut(p) })
                present(sheet, animated: true)
            } else {
                PaymentManager.shared.signIn(p, from: self) { _ in }
            }
        default:
            break
        }
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        indexPath.section == 1 && indexPath.row < Store.shared.repos.count
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle,
                            forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete, indexPath.section == 1, indexPath.row < Store.shared.repos.count else { return }
        Store.shared.removeRepo(id: Store.shared.repos[indexPath.row].id)
    }

    private func promptAddSource() {
        let alert = UIAlertController(title: "Add Source",
                                      message: "Enter a repo URL, or \u{201C}URL suite component\u{201D} for a Debian-style repo.",
                                      preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "https://repo.example.com/"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            let text = alert.textFields?.first?.text ?? ""
            switch Store.shared.addRepo(text) {
            case .added: break
            case .invalid: InstallFlow.alert(self, "Not a repo URL", "Try something like https://repo.example.com/")
            case .duplicate: InstallFlow.alert(self, "Already added", "That source is already in your list.")
            }
        })
        present(alert, animated: true)
    }
}

/// Table cell that hosts a PackageRowView.
final class RowCell: UITableViewCell {
    private let row = PackageRowView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        row.showsSeparator = false
        contentView.addSubview(row)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(_ pkg: Package) { row.configure(pkg) }

    override func layoutSubviews() {
        super.layoutSubviews()
        row.frame = contentView.bounds.insetBy(dx: 20, dy: 0)
    }
}
