import UIKit

// MARK: - Tabs

final class MainTabController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        viewControllers = [
            nav(TodayController(), "Today", "sun.max"),
            nav(SearchController(), "Search", "magnifyingglass"),
            nav(UpdatesController(), "Updates", "arrow.down.circle"),
        ]
    }

    private func nav(_ root: UIViewController, _ title: String, _ symbol: String) -> UINavigationController {
        let nav = UINavigationController(rootViewController: root)
        nav.navigationBar.prefersLargeTitles = true
        var image: UIImage?
        if #available(iOS 13.0, *) { image = UIImage(systemName: symbol) }
        nav.tabBarItem = UITabBarItem(title: title, image: image, tag: 0)
        return nav
    }
}

// MARK: - Shared list

class PackageListController: UITableViewController {
    var items: [Package] = []
    var emptyMessage: String { "Nothing here yet" }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(PackageCell.self, forCellReuseIdentifier: PackageCell.reuseID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 84
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(pull), for: .valueChanged)
        refreshControl = refresh
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged),
                                               name: .storeChanged, object: nil)
        rebuild()
    }

    /// Subclasses set `items` here, then call `reloadTable()`.
    func rebuild() { reloadTable() }

    final func reloadTable() {
        tableView.reloadData()
        guard items.isEmpty else { tableView.backgroundView = nil; return }
        let label = UILabel()
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = Theme.secondaryText
        let store = Store.shared
        label.text = store.isLoading ? "Loading repos…" : (store.lastError ?? emptyMessage)
        tableView.backgroundView = label
    }

    @objc private func pull() { Store.shared.refresh() }

    @objc private func storeChanged() {
        if !Store.shared.isLoading { refreshControl?.endRefreshing() }
        rebuild()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: PackageCell.reuseID, for: indexPath) as! PackageCell
        let pkg = items[indexPath.row]
        cell.configure(pkg, buttonTitle: Store.shared.actionTitle(for: pkg)) { [weak self] in
            guard let self = self else { return }
            InstallFlow.install(pkg, from: self)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(PackageDetailController(items[indexPath.row]), animated: true)
    }
}

// MARK: - Today

final class TodayController: PackageListController {
    override func viewDidLoad() {
        title = "Today"
        super.viewDidLoad()
    }

    override var emptyMessage: String { "No packages for this device yet" }

    override func rebuild() {
        // A different, stable-for-the-day selection each day.
        let day = UInt64(Date().timeIntervalSince1970 / 86400)
        func score(_ s: String) -> UInt64 {
            var h: UInt64 = 5381 &+ day
            for b in s.utf8 { h = (h &* 33) &+ UInt64(b) }
            return h
        }
        items = Array(Store.shared.index.allLatest.sorted { score($0.identifier) < score($1.identifier) }.prefix(15))
        reloadTable()
    }
}

// MARK: - Search

final class SearchController: PackageListController, UISearchResultsUpdating {
    private let search = UISearchController(searchResultsController: nil)
    private var query = ""

    override var emptyMessage: String { query.isEmpty ? "Search tweaks and apps" : "No results" }

    override func viewDidLoad() {
        title = "Search"
        super.viewDidLoad()
        search.searchResultsUpdater = self
        if #available(iOS 9.1, *) { search.obscuresBackgroundDuringPresentation = false }
        navigationItem.searchController = search
        definesPresentationContext = true
    }

    func updateSearchResults(for searchController: UISearchController) {
        query = (searchController.searchBar.text ?? "").lowercased()
        rebuild()
    }

    override func rebuild() {
        if query.isEmpty {
            items = []
        } else {
            items = Array(Store.shared.index.allLatest
                .filter { $0.name.lowercased().contains(query)
                    || $0.identifier.lowercased().contains(query)
                    || $0.shortDescription.lowercased().contains(query) }
                .sorted { $0.name.lowercased() < $1.name.lowercased() }
                .prefix(100))
        }
        reloadTable()
    }
}

// MARK: - Updates

final class UpdatesController: PackageListController {
    override var emptyMessage: String { "Everything is up to date" }

    override func viewDidLoad() {
        title = "Updates"
        super.viewDidLoad()
    }

    override func rebuild() {
        let store = Store.shared
        items = store.installed.versions.compactMap { id, have -> Package? in
            guard let latest = store.index.latest(id), latest.version > have else { return nil }
            return latest
        }.sorted { $0.name.lowercased() < $1.name.lowercased() }
        reloadTable()
    }
}

// MARK: - Detail

final class PackageDetailController: UIViewController {
    private let pkg: Package

    init(_ pkg: Package) {
        self.pkg = pkg
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .never

        let title = UILabel()
        title.font = .systemFont(ofSize: 28, weight: .bold)
        title.numberOfLines = 0
        title.text = pkg.name

        let meta = UILabel()
        meta.font = .systemFont(ofSize: 14)
        meta.textColor = Theme.secondaryText
        meta.numberOfLines = 0
        var line = "\(pkg.version) · \(pkg.section)"
        let by = pkg.author.isEmpty ? pkg.maintainer : pkg.author
        if !by.isEmpty { line += "\nby " + by }
        meta.text = line

        let summary = UILabel()
        summary.font = .systemFont(ofSize: 17, weight: .medium)
        summary.numberOfLines = 0
        summary.text = pkg.shortDescription

        let details = UILabel()
        details.font = .systemFont(ofSize: 15)
        details.numberOfLines = 0
        details.text = pkg.longDescription

        let action = UIButton(type: .system)
        let actionTitle = Store.shared.actionTitle(for: pkg)
        action.setTitle(actionTitle, for: .normal)
        action.isEnabled = actionTitle != "INSTALLED"
        action.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        action.setTitleColor(.white, for: .normal)
        action.setTitleColor(Theme.secondaryText, for: .disabled)
        action.backgroundColor = action.isEnabled ? Theme.accent : Theme.fill
        action.layer.cornerRadius = 14
        action.heightAnchor.constraint(equalToConstant: 48).isActive = true
        action.addTarget(self, action: #selector(installTapped), for: .touchUpInside)

        var views: [UIView] = [title, meta, action, summary, details]
        if Store.shared.installed.version(of: pkg.identifier) != nil {
            let remove = UIButton(type: .system)
            remove.setTitle("Remove", for: .normal)
            remove.setTitleColor(.red, for: .normal)
            remove.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
            views.insert(remove, at: 3)
        }

        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        view.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),
        ])
    }

    @objc private func installTapped() { InstallFlow.install(pkg, from: self) }
    @objc private func removeTapped() { InstallFlow.remove(pkg, from: self) }
}
