import UIKit

// Reusable App Store-style pieces: a list row, a feature card, and a "Top picks" list card.

/// Icon, name, one-line description and the GET pill.
final class PackageRowView: UIView {
    static let height: CGFloat = 76

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let separator = CALayer()
    let button = GetButton()
    private(set) var package: Package?
    private var iconURL: String?

    var showsSeparator = true { didSet { separator.isHidden = !showsSeparator } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        iconView.layer.cornerRadius = 14
        iconView.clipsToBounds = true
        iconView.backgroundColor = Theme.fill
        iconView.contentMode = .scaleAspectFill
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = Theme.label
        titleLabel.numberOfLines = 2
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = Theme.secondaryText
        separator.backgroundColor = Theme.separator.cgColor
        layer.addSublayer(separator)
        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(button)

        button.onTap = { [weak self] in
            guard let self = self, let pkg = self.package else { return }
            InstallFlow.install(pkg, from: self.owningViewController)
        }
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openProduct)))
        NotificationCenter.default.addObserver(self, selector: #selector(refreshState), name: .stateChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshState), name: .storeChanged, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(_ pkg: Package) {
        package = pkg
        titleLabel.text = pkg.name
        subtitleLabel.text = pkg.shortDescription
        iconView.image = nil
        iconURL = pkg.icon
        if let url = pkg.icon {
            ImageLoader.load(url) { [weak self] image in
                if self?.iconURL == url { self?.iconView.image = image }
            }
        }
        refreshState()
    }

    @objc private func refreshState() {
        guard let pkg = package else { return }
        button.set(Store.shared.state(for: pkg))
    }

    @objc private func openProduct() {
        guard let pkg = package else { return }
        owningViewController?.navigationController?.pushViewController(ProductController(pkg), animated: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        let bw = button.sizeThatFits(.zero).width
        let bh = GetButton.size.height
        iconView.frame = CGRect(x: 0, y: (h - 60) / 2, width: 60, height: 60)
        button.frame = CGRect(x: bounds.width - bw, y: (h - bh) / 2, width: bw, height: bh)
        let textX: CGFloat = 74
        let textW = max(40, bounds.width - textX - bw - 12)
        let th = min(titleLabel.sizeThatFits(CGSize(width: textW, height: 100)).height, 42)
        let sh: CGFloat = 18
        let top = (h - th - sh - 2) / 2
        titleLabel.frame = CGRect(x: textX, y: top, width: textW, height: th)
        subtitleLabel.frame = CGRect(x: textX, y: top + th + 2, width: textW, height: sh)
        separator.frame = CGRect(x: textX, y: h - 0.5, width: max(0, bounds.width - textX), height: 0.5)
    }
}

/// Big rounded artwork card. `.above` puts the text over the card (Games/Apps pages); `.inside` overlays it (Today).
final class FeatureCardView: UIView {
    enum Style { case above, inside }

    static func height(forWidth w: CGFloat, style: Style) -> CGFloat {
        switch style {
        case .above: return 88 + max(230, min(w * 0.72, 340))
        case .inside: return max(300, min(w * 0.85, 440))
        }
    }

    private let pkg: Package
    private let style: Style
    private let labelLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let art = GradientView()
    private let bannerView = UIImageView()
    private let scrim = GradientView()
    private let bigIcon = UIImageView()
    private let bar = UIView()
    private let smallIcon = UIImageView()
    private let nameLabel = UILabel()
    private let descLabel = UILabel()
    private let button = GetButton()

    init(_ pkg: Package, style: Style, label: String) {
        self.pkg = pkg
        self.style = style
        super.init(frame: .zero)

        art.gradient.colors = Theme.gradientColors(for: pkg.identifier)
        art.gradient.startPoint = CGPoint(x: 0.1, y: 0)
        art.gradient.endPoint = CGPoint(x: 0.9, y: 1)
        art.layer.cornerRadius = 20
        art.clipsToBounds = true
        addSubview(art)
        // Banner art (from the repo's featured list or the package's depiction) sits under the text, over the gradient.
        bannerView.contentMode = .scaleAspectFill
        bannerView.clipsToBounds = true
        bannerView.isHidden = true
        art.addSubview(bannerView)
        scrim.gradient.colors = [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0.55).cgColor]
        scrim.isUserInteractionEnabled = false
        scrim.isHidden = true
        art.addSubview(scrim)

        let textParent: UIView = style == .above ? self : art
        let onArt = style == .inside
        labelLabel.text = label.uppercased()
        labelLabel.font = .systemFont(ofSize: 12, weight: .bold)
        labelLabel.textColor = onArt ? UIColor(white: 1, alpha: 0.85) : Theme.accent
        titleLabel.text = pkg.name
        titleLabel.font = .systemFont(ofSize: onArt ? 26 : 22, weight: .bold)
        titleLabel.textColor = onArt ? .white : Theme.label
        subtitleLabel.text = pkg.shortDescription
        subtitleLabel.font = .systemFont(ofSize: onArt ? 15 : 19)
        subtitleLabel.textColor = onArt ? UIColor(white: 1, alpha: 0.85) : Theme.secondaryText
        subtitleLabel.numberOfLines = onArt ? 2 : 1
        for l in [labelLabel, titleLabel, subtitleLabel] { textParent.addSubview(l) }

        bigIcon.contentMode = .scaleAspectFill
        bigIcon.clipsToBounds = true
        bigIcon.backgroundColor = UIColor(white: 1, alpha: 0.18)
        art.addSubview(bigIcon)

        bar.backgroundColor = UIColor(white: 0, alpha: 0.35)
        art.addSubview(bar)
        smallIcon.contentMode = .scaleAspectFill
        smallIcon.clipsToBounds = true
        smallIcon.layer.cornerRadius = 10
        smallIcon.backgroundColor = UIColor(white: 1, alpha: 0.18)
        nameLabel.text = pkg.name
        nameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = .white
        descLabel.text = pkg.shortDescription
        descLabel.font = .systemFont(ofSize: 13)
        descLabel.textColor = UIColor(white: 1, alpha: 0.8)
        button.onDark = true
        button.onTap = { [weak self] in
            guard let self = self else { return }
            InstallFlow.install(self.pkg, from: self.owningViewController)
        }
        for v in [smallIcon, nameLabel, descLabel, button] as [UIView] { bar.addSubview(v) }

        if let url = pkg.icon {
            ImageLoader.load(url) { [weak self] image in
                self?.bigIcon.image = image
                self?.smallIcon.image = image
            }
        }
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openProduct)))
        NotificationCenter.default.addObserver(self, selector: #selector(refreshState), name: .stateChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshState), name: .storeChanged, object: nil)
        refreshState()
        CardArtLoader.art(for: pkg) { [weak self] found in self?.applyArt(found) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func refreshState() { button.set(Store.shared.state(for: pkg)) }

    private func applyArt(_ found: CardArt) {
        if let tint = found.tint { art.gradient.colors = Theme.gradientColors(from: tint) }
        guard let url = found.bannerURL else { return }
        ImageLoader.load(url) { [weak self] image in
            guard let self = self, let image = image else { return }
            self.bannerView.image = image
            self.bannerView.isHidden = false
            self.scrim.isHidden = false
            self.bigIcon.isHidden = true
        }
    }

    @objc private func openProduct() {
        owningViewController?.navigationController?.pushViewController(ProductController(pkg), animated: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        switch style {
        case .above:
            labelLabel.frame = CGRect(x: 0, y: 0, width: w, height: 16)
            titleLabel.frame = CGRect(x: 0, y: 18, width: w, height: 28)
            subtitleLabel.frame = CGRect(x: 0, y: 48, width: w, height: 26)
            art.frame = CGRect(x: 0, y: 88, width: w, height: h - 88)
        case .inside:
            art.frame = bounds
            labelLabel.frame = CGRect(x: 20, y: 18, width: w - 40, height: 16)
        }
        let aw = art.bounds.width, ah = art.bounds.height
        bannerView.frame = art.bounds
        scrim.frame = art.bounds
        bar.frame = CGRect(x: 0, y: ah - 68, width: aw, height: 68)

        let reserved: CGFloat = style == .inside ? 150 : 50
        let iconSize = min(120, max(60, ah - 68 - reserved))
        let iconY: CGFloat = style == .inside ? 52 : (ah - 68 - iconSize) / 2
        bigIcon.frame = CGRect(x: (aw - iconSize) / 2, y: iconY, width: iconSize, height: iconSize)
        bigIcon.layer.cornerRadius = iconSize * 0.225

        if style == .inside {
            titleLabel.frame = CGRect(x: 20, y: ah - 68 - 78, width: aw - 40, height: 30)
            subtitleLabel.frame = CGRect(x: 20, y: ah - 68 - 46, width: aw - 40, height: 38)
        }
        let bw = button.sizeThatFits(.zero).width
        smallIcon.frame = CGRect(x: 14, y: 12, width: 44, height: 44)
        button.frame = CGRect(x: aw - 14 - bw, y: 20, width: bw, height: GetButton.size.height)
        let tw = max(40, aw - 68 - 14 - bw - 8)
        nameLabel.frame = CGRect(x: 68, y: 12, width: tw, height: 22)
        descLabel.frame = CGRect(x: 68, y: 34, width: tw, height: 20)
    }
}

/// The rounded "OUR FAVOURITES / Top picks" card with a few rows inside.
final class ListCardView: UIView {
    static func height(rows: Int) -> CGFloat { 76 + CGFloat(rows) * PackageRowView.height + 12 }

    private let labelLabel = UILabel()
    private let titleLabel = UILabel()
    private var rows: [PackageRowView] = []

    init(label: String, title: String, packages: [Package]) {
        super.init(frame: .zero)
        backgroundColor = Theme.secondaryBackground
        layer.cornerRadius = 20
        clipsToBounds = true
        labelLabel.text = label.uppercased()
        labelLabel.font = .systemFont(ofSize: 12, weight: .bold)
        labelLabel.textColor = Theme.secondaryText
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textColor = Theme.label
        titleLabel.numberOfLines = 2
        addSubview(labelLabel)
        addSubview(titleLabel)
        for (i, p) in packages.enumerated() {
            let row = PackageRowView()
            row.configure(p)
            row.showsSeparator = i != packages.count - 1
            rows.append(row)
            addSubview(row)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        labelLabel.frame = CGRect(x: 20, y: 16, width: w - 40, height: 16)
        titleLabel.frame = CGRect(x: 20, y: 34, width: w - 40, height: 30)
        for (i, row) in rows.enumerated() {
            row.frame = CGRect(x: 20, y: 76 + CGFloat(i) * PackageRowView.height, width: w - 40, height: PackageRowView.height)
        }
    }
}
