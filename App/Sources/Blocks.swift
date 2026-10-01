import UIKit

// Pages are vertical stacks of blocks. Each block knows its height for a given width and lays itself out,
// so the same pages adapt from iPhone to iPad (1, 2 or 3 columns) without Auto Layout.

class BlockView: UIView {
    func height(forWidth width: CGFloat) -> CGFloat { 0 }
}

final class BlockScrollView: UIScrollView {
    var blocks: [BlockView] = [] {
        didSet {
            for old in oldValue where !blocks.contains(where: { $0 === old }) { old.removeFromSuperview() }
            for b in blocks where b.superview !== self { addSubview(b) }
            setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var y: CGFloat = 8
        for b in blocks {
            let h = b.height(forWidth: bounds.width)
            b.frame = CGRect(x: 0, y: y, width: bounds.width, height: h)
            y += h + 10
        }
        let size = CGSize(width: bounds.width, height: y + 30)
        if contentSize != size { contentSize = size }
    }
}

// MARK: - Headers

final class HeaderBlock: BlockView {
    private let dateLabel = UILabel()
    private let titleLabel = UILabel()
    private let avatar = UIButton(type: .system)
    private let hasDate: Bool
    private let hasAvatar: Bool

    init(title: String, date: String? = nil, avatar showsAvatar: Bool = true) {
        hasDate = date != nil
        hasAvatar = showsAvatar
        super.init(frame: .zero)
        dateLabel.text = date
        dateLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        dateLabel.textColor = Theme.secondaryText
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 34, weight: .bold)
        titleLabel.textColor = Theme.label
        addSubview(dateLabel)
        addSubview(titleLabel)
        if showsAvatar {
            avatar.setImage(Theme.avatarImage(), for: .normal)
            avatar.addTarget(self, action: #selector(openAccount), for: .touchUpInside)
            addSubview(avatar)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func height(forWidth width: CGFloat) -> CGFloat { (hasDate ? 20 : 0) + 50 }

    @objc private func openAccount() {
        guard let vc = owningViewController else { return }
        let nav = UINavigationController(rootViewController: AccountController(style: .grouped))
        nav.modalPresentationStyle = .formSheet
        vc.present(nav, animated: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, m = sideMargin(for: w)
        var y: CGFloat = 4
        if hasDate {
            dateLabel.frame = CGRect(x: m, y: y, width: w - 2 * m - 50, height: 18)
            y += 20
        }
        titleLabel.frame = CGRect(x: m, y: y, width: w - 2 * m - 50, height: 42)
        if hasAvatar { avatar.frame = CGRect(x: w - m - 34, y: y + 4, width: 34, height: 34) }
    }
}

final class SectionHeaderBlock: BlockView {
    private let line = CALayer()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let seeAll = UIButton(type: .system)
    private let hasSubtitle: Bool
    private let onSeeAll: (() -> Void)?

    init(title: String, subtitle: String? = nil, seeAll onSeeAll: (() -> Void)? = nil) {
        hasSubtitle = subtitle != nil
        self.onSeeAll = onSeeAll
        super.init(frame: .zero)
        line.backgroundColor = Theme.separator.cgColor
        layer.addSublayer(line)
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = Theme.label
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = Theme.secondaryText
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        if onSeeAll != nil {
            seeAll.setTitle("See All", for: .normal)
            seeAll.titleLabel?.font = .systemFont(ofSize: 17)
            seeAll.addTarget(self, action: #selector(seeAllTapped), for: .touchUpInside)
            addSubview(seeAll)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func height(forWidth width: CGFloat) -> CGFloat { hasSubtitle ? 76 : 52 }

    @objc private func seeAllTapped() { onSeeAll?() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, m = sideMargin(for: w)
        line.frame = CGRect(x: m, y: 0, width: w - 2 * m, height: 0.5)
        titleLabel.frame = CGRect(x: m, y: 14, width: w - 2 * m - 70, height: 28)
        subtitleLabel.frame = CGRect(x: m, y: 44, width: w - 2 * m, height: 20)
        seeAll.frame = CGRect(x: w - m - 70, y: 14, width: 70, height: 28)
        seeAll.contentHorizontalAlignment = .right
    }
}

final class MessageBlock: BlockView {
    private let label = UILabel()

    init(_ text: String) {
        super.init(frame: .zero)
        label.text = text
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = Theme.secondaryText
        label.font = .systemFont(ofSize: 17)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func height(forWidth width: CGFloat) -> CGFloat { 240 }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 40, dy: 20)
    }
}

// MARK: - Shelves

/// Horizontal strip of big cards.
final class CardShelfBlock: BlockView {
    private let scroll = UIScrollView()
    private var cards: [FeatureCardView] = []

    init(_ packages: [Package], label: String) {
        super.init(frame: .zero)
        scroll.showsHorizontalScrollIndicator = false
        addSubview(scroll)
        for p in packages {
            let card = FeatureCardView(p, style: .above, label: label)
            cards.append(card)
            scroll.addSubview(card)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func cardWidth(_ w: CGFloat) -> CGFloat {
        let m = sideMargin(for: w), v = columnCount(for: w), gap: CGFloat = 16
        let peek: CGFloat = cards.count > v ? 34 : 0
        return (w - 2 * m - gap * CGFloat(v - 1) - peek) / CGFloat(v)
    }

    override func height(forWidth width: CGFloat) -> CGFloat {
        FeatureCardView.height(forWidth: cardWidth(width), style: .above)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        let w = bounds.width, m = sideMargin(for: w), gap: CGFloat = 16, cw = cardWidth(w)
        for (i, c) in cards.enumerated() {
            c.frame = CGRect(x: m + CGFloat(i) * (cw + gap), y: 0, width: cw, height: bounds.height)
        }
        scroll.contentSize = CGSize(width: 2 * m + CGFloat(cards.count) * cw + CGFloat(max(0, cards.count - 1)) * gap,
                                    height: bounds.height)
    }
}

/// Horizontal strip of columns, three rows per column, like the App Store's "What We're Playing".
final class RowShelfBlock: BlockView {
    private let scroll = UIScrollView()
    private var rows: [PackageRowView] = []
    private let count: Int

    init(_ packages: [Package]) {
        count = packages.count
        super.init(frame: .zero)
        scroll.showsHorizontalScrollIndicator = false
        addSubview(scroll)
        for (i, p) in packages.enumerated() {
            let row = PackageRowView()
            row.configure(p)
            row.showsSeparator = (i % 3) != 2 && i != packages.count - 1
            rows.append(row)
            scroll.addSubview(row)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func columnWidth(_ w: CGFloat) -> CGFloat {
        let m = sideMargin(for: w), v = columnCount(for: w), gap: CGFloat = 24
        let columns = (count + 2) / 3
        let peek: CGFloat = columns > v ? 30 : 0
        return (w - 2 * m - gap * CGFloat(v - 1) - peek) / CGFloat(v)
    }

    override func height(forWidth width: CGFloat) -> CGFloat { CGFloat(min(3, count)) * PackageRowView.height }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        let w = bounds.width, m = sideMargin(for: w), gap: CGFloat = 24, cw = columnWidth(w)
        for (i, r) in rows.enumerated() {
            r.frame = CGRect(x: m + CGFloat(i / 3) * (cw + gap), y: CGFloat(i % 3) * PackageRowView.height,
                             width: cw, height: PackageRowView.height)
        }
        let columns = (count + 2) / 3
        scroll.contentSize = CGSize(width: 2 * m + CGFloat(columns) * cw + CGFloat(max(0, columns - 1)) * gap,
                                    height: bounds.height)
    }
}

/// Vertical grid of rows (search results, See All pages).
final class RowGridBlock: BlockView {
    private var rows: [PackageRowView] = []

    init(_ packages: [Package]) {
        super.init(frame: .zero)
        for p in packages {
            let row = PackageRowView()
            row.configure(p)
            rows.append(row)
            addSubview(row)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func height(forWidth width: CGFloat) -> CGFloat {
        let c = columnCount(for: width)
        return CGFloat((rows.count + c - 1) / c) * PackageRowView.height
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, m = sideMargin(for: w), c = columnCount(for: w), gap: CGFloat = 24
        let cw = (w - 2 * m - gap * CGFloat(c - 1)) / CGFloat(c)
        for (i, r) in rows.enumerated() {
            r.frame = CGRect(x: m + CGFloat(i % c) * (cw + gap), y: CGFloat(i / c) * PackageRowView.height,
                             width: cw, height: PackageRowView.height)
        }
    }
}

// MARK: - Today

final class TodayHeroBlock: BlockView {
    private let hero: FeatureCardView
    private let listCard: ListCardView
    private let rowCount: Int

    init(hero: Package, list: [Package], listTitle: String) {
        self.hero = FeatureCardView(hero, style: .inside, label: "Featured")
        self.listCard = ListCardView(label: "Our favourites", title: listTitle, packages: list)
        rowCount = list.count
        super.init(frame: .zero)
        addSubview(self.hero)
        if rowCount > 0 { addSubview(listCard) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func metrics(_ w: CGFloat) -> (wide: Bool, heroW: CGFloat, listW: CGFloat, heroH: CGFloat, listH: CGFloat) {
        let m = sideMargin(for: w), gap: CGFloat = 20
        let wide = w >= 700
        let heroW = wide ? (w - 2 * m - gap) * 0.62 : w - 2 * m
        let listW = wide ? (w - 2 * m - gap) - heroW : w - 2 * m
        let heroH = FeatureCardView.height(forWidth: heroW, style: .inside)
        let listH = rowCount > 0 ? ListCardView.height(rows: rowCount) : 0
        return (wide, heroW, listW, wide ? max(heroH, listH) : heroH, listH)
    }

    override func height(forWidth width: CGFloat) -> CGFloat {
        let k = metrics(width)
        return k.wide ? k.heroH : k.heroH + (k.listH > 0 ? 20 + k.listH : 0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, m = sideMargin(for: w), gap: CGFloat = 20
        let k = metrics(w)
        hero.frame = CGRect(x: m, y: 0, width: k.heroW, height: k.heroH)
        if k.wide {
            listCard.frame = CGRect(x: m + k.heroW + gap, y: 0, width: k.listW, height: k.heroH)
        } else {
            listCard.frame = CGRect(x: m, y: k.heroH + gap, width: k.listW, height: k.listH)
        }
    }
}

final class TwoUpCardsBlock: BlockView {
    private let a: FeatureCardView
    private let b: FeatureCardView?

    init(_ first: Package, _ second: Package?) {
        a = FeatureCardView(first, style: .inside, label: first.section)
        b = second.map { FeatureCardView($0, style: .inside, label: $0.section) }
        super.init(frame: .zero)
        addSubview(a)
        if let b = b { addSubview(b) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func cardWidth(_ w: CGFloat) -> CGFloat {
        let m = sideMargin(for: w)
        return w >= 700 ? (w - 2 * m - 20) / 2 : w - 2 * m
    }

    override func height(forWidth width: CGFloat) -> CGFloat {
        let ch = FeatureCardView.height(forWidth: cardWidth(width), style: .inside)
        return (width >= 700 || b == nil) ? ch : ch * 2 + 20
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, m = sideMargin(for: w), cw = cardWidth(w)
        let ch = FeatureCardView.height(forWidth: cw, style: .inside)
        a.frame = CGRect(x: m, y: 0, width: cw, height: ch)
        if w >= 700 {
            b?.frame = CGRect(x: m + cw + 20, y: 0, width: cw, height: ch)
        } else {
            b?.frame = CGRect(x: m, y: ch + 20, width: cw, height: ch)
        }
    }
}

// MARK: - Search

final class SearchBarBlock: BlockView {
    let bar = UISearchBar()

    override init(frame: CGRect) {
        super.init(frame: frame)
        bar.searchBarStyle = .minimal
        bar.placeholder = "Tweaks, Apps, Themes and More"
        bar.autocapitalizationType = .none
        bar.autocorrectionType = .no
        addSubview(bar)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func height(forWidth width: CGFloat) -> CGFloat { 56 }

    override func layoutSubviews() {
        super.layoutSubviews()
        let m = sideMargin(for: bounds.width) - 8
        bar.frame = CGRect(x: m, y: 0, width: bounds.width - 2 * m, height: 56)
    }
}

final class SuggestionsBlock: BlockView {
    private let titleLabel = UILabel()
    private var buttons: [UIButton] = []
    private let onPick: (String) -> Void

    init(terms: [String], onPick: @escaping (String) -> Void) {
        self.onPick = onPick
        super.init(frame: .zero)
        titleLabel.text = "Discover"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = Theme.label
        addSubview(titleLabel)
        for term in terms {
            let b = UIButton(type: .system)
            b.setTitle("  " + term, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 17)
            b.titleLabel?.lineBreakMode = .byTruncatingTail
            b.contentHorizontalAlignment = .left
            if #available(iOS 13.0, *) { b.setImage(UIImage(systemName: "magnifyingglass"), for: .normal) }
            b.addTarget(self, action: #selector(picked(_:)), for: .touchUpInside)
            buttons.append(b)
            addSubview(b)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func height(forWidth width: CGFloat) -> CGFloat {
        let c = columnCount(for: width)
        return 44 + CGFloat((buttons.count + c - 1) / c) * 44 + 8
    }

    @objc private func picked(_ sender: UIButton) {
        guard let i = buttons.firstIndex(of: sender) else { return }
        onPick(buttons[i].title(for: .normal)?.trimmingCharacters(in: .whitespaces) ?? "")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, m = sideMargin(for: w), c = columnCount(for: w), gap: CGFloat = 24
        titleLabel.frame = CGRect(x: m, y: 4, width: w - 2 * m, height: 30)
        let cw = (w - 2 * m - gap * CGFloat(c - 1)) / CGFloat(c)
        for (i, b) in buttons.enumerated() {
            b.frame = CGRect(x: m + CGFloat(i % c) * (cw + gap), y: 44 + CGFloat(i / c) * 44, width: cw, height: 44)
        }
    }
}

// MARK: - Product page

final class ProductHeaderBlock: BlockView {
    private let pkg: Package
    private let icon = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let button = GetButton()
    private let removeButton = UIButton(type: .system)

    init(_ pkg: Package) {
        self.pkg = pkg
        super.init(frame: .zero)
        icon.layer.cornerRadius = 27
        icon.clipsToBounds = true
        icon.contentMode = .scaleAspectFill
        icon.backgroundColor = Theme.fill
        titleLabel.text = pkg.name
        titleLabel.font = .systemFont(ofSize: 30, weight: .bold)
        titleLabel.textColor = Theme.label
        titleLabel.numberOfLines = 2
        subtitleLabel.text = pkg.shortDescription
        subtitleLabel.font = .systemFont(ofSize: 17)
        subtitleLabel.textColor = Theme.secondaryText
        subtitleLabel.numberOfLines = 2
        removeButton.setTitle("Remove", for: .normal)
        removeButton.setTitleColor(.red, for: .normal)
        removeButton.titleLabel?.font = .systemFont(ofSize: 15)
        removeButton.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
        button.onTap = { [weak self] in
            guard let self = self else { return }
            InstallFlow.install(self.pkg, from: self.owningViewController)
        }
        for v in [icon, titleLabel, subtitleLabel, button, removeButton] as [UIView] { addSubview(v) }
        if let url = pkg.icon { ImageLoader.load(url) { [weak self] in self?.icon.image = $0 } }
        NotificationCenter.default.addObserver(self, selector: #selector(refreshState), name: .stateChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshState), name: .storeChanged, object: nil)
        refreshState()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func refreshState() {
        let state = Store.shared.state(for: pkg)
        button.set(state)
        removeButton.isHidden = Store.shared.installed.version(of: pkg.identifier) == nil || Store.shared.progress[pkg.identifier] != nil
    }

    @objc private func removeTapped() { InstallFlow.remove(pkg, from: owningViewController) }

    override func height(forWidth width: CGFloat) -> CGFloat { 152 }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, m = sideMargin(for: w)
        icon.frame = CGRect(x: m, y: 16, width: 120, height: 120)
        let x = m + 136, tw = max(60, w - x - m)
        let th = min(titleLabel.sizeThatFits(CGSize(width: tw, height: 100)).height, 74)
        titleLabel.frame = CGRect(x: x, y: 18, width: tw, height: th)
        let sh = min(subtitleLabel.sizeThatFits(CGSize(width: tw, height: 100)).height, 44)
        subtitleLabel.frame = CGRect(x: x, y: 18 + th + 2, width: tw, height: sh)
        button.frame = CGRect(x: x, y: 106, width: GetButton.size.width, height: 30)
        removeButton.frame = CGRect(x: x + GetButton.size.width + 12, y: 106, width: 80, height: 30)
    }
}

final class StatsBlock: BlockView {
    private var cells: [(UILabel, UILabel, UILabel)] = []
    private var lines: [CALayer] = []

    init(_ items: [(caption: String, value: String, note: String)]) {
        super.init(frame: .zero)
        for item in items {
            let cap = UILabel(), val = UILabel(), note = UILabel()
            cap.text = item.caption.uppercased()
            cap.font = .systemFont(ofSize: 11, weight: .bold)
            cap.textColor = Theme.secondaryText
            val.text = item.value
            val.font = .systemFont(ofSize: 19, weight: .semibold)
            val.textColor = Theme.label
            val.adjustsFontSizeToFitWidth = true
            val.minimumScaleFactor = 0.6
            note.text = item.note
            note.font = .systemFont(ofSize: 12)
            note.textColor = Theme.secondaryText
            for l in [cap, val, note] { l.textAlignment = .center; addSubview(l) }
            cells.append((cap, val, note))
        }
        for _ in 0..<max(0, items.count - 1) {
            let line = CALayer()
            line.backgroundColor = Theme.separator.cgColor
            layer.addSublayer(line)
            lines.append(line)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func height(forWidth width: CGFloat) -> CGFloat { 84 }

    override func layoutSubviews() {
        super.layoutSubviews()
        let m = sideMargin(for: bounds.width)
        let cw = (bounds.width - 2 * m) / CGFloat(max(cells.count, 1))
        for (i, c) in cells.enumerated() {
            let x = m + CGFloat(i) * cw
            c.0.frame = CGRect(x: x + 4, y: 12, width: cw - 8, height: 14)
            c.1.frame = CGRect(x: x + 6, y: 30, width: cw - 12, height: 26)
            c.2.frame = CGRect(x: x + 4, y: 58, width: cw - 8, height: 16)
            if i < lines.count { lines[i].frame = CGRect(x: x + cw, y: 14, width: 0.5, height: 56) }
        }
    }
}

final class TextBlock: BlockView {
    private let line = CALayer()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let text: String

    init(title: String, body: String) {
        text = body
        super.init(frame: .zero)
        line.backgroundColor = Theme.separator.cgColor
        layer.addSublayer(line)
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = Theme.label
        bodyLabel.text = body
        bodyLabel.font = .systemFont(ofSize: 16)
        bodyLabel.textColor = Theme.label
        bodyLabel.numberOfLines = 0
        addSubview(titleLabel)
        addSubview(bodyLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func height(forWidth width: CGFloat) -> CGFloat {
        let m = sideMargin(for: width)
        return 52 + textHeight(text, font: bodyLabel.font, width: width - 2 * m) + 8
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, m = sideMargin(for: w)
        line.frame = CGRect(x: m, y: 0, width: w - 2 * m, height: 0.5)
        titleLabel.frame = CGRect(x: m, y: 14, width: w - 2 * m, height: 28)
        bodyLabel.frame = CGRect(x: m, y: 50, width: w - 2 * m, height: bounds.height - 54)
    }
}

final class InfoBlock: BlockView {
    private let line = CALayer()
    private let titleLabel = UILabel()
    private var rows: [(UILabel, UILabel, CALayer)] = []

    init(title: String, rows items: [(String, String)]) {
        super.init(frame: .zero)
        line.backgroundColor = Theme.separator.cgColor
        layer.addSublayer(line)
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = Theme.label
        addSubview(titleLabel)
        for (key, value) in items {
            let k = UILabel(), v = UILabel()
            k.text = key
            k.font = .systemFont(ofSize: 15)
            k.textColor = Theme.secondaryText
            v.text = value
            v.font = .systemFont(ofSize: 15)
            v.textColor = Theme.label
            v.textAlignment = .right
            v.lineBreakMode = .byTruncatingMiddle
            let sep = CALayer()
            sep.backgroundColor = Theme.separator.cgColor
            addSubview(k)
            addSubview(v)
            layer.addSublayer(sep)
            rows.append((k, v, sep))
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func height(forWidth width: CGFloat) -> CGFloat { 52 + CGFloat(rows.count) * 44 }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, m = sideMargin(for: w)
        line.frame = CGRect(x: m, y: 0, width: w - 2 * m, height: 0.5)
        titleLabel.frame = CGRect(x: m, y: 14, width: w - 2 * m, height: 28)
        for (i, r) in rows.enumerated() {
            let y = 52 + CGFloat(i) * 44
            r.0.frame = CGRect(x: m, y: y, width: 110, height: 44)
            r.1.frame = CGRect(x: m + 118, y: y, width: w - 2 * m - 118, height: 44)
            r.2.frame = CGRect(x: m, y: y + 43.5, width: w - 2 * m, height: 0.5)
        }
    }
}
