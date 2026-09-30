import UIKit

final class PackageCell: UITableViewCell {
    static let reuseID = "PackageCell"

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let button = UIButton(type: .system)
    private var onTap: (() -> Void)?
    private var iconURL: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        accessoryType = .none

        iconView.layer.cornerRadius = 13
        iconView.clipsToBounds = true
        iconView.backgroundColor = Theme.fill
        iconView.contentMode = .scaleAspectFill

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = Theme.secondaryText
        subtitleLabel.numberOfLines = 2

        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        button.setTitleColor(Theme.accent, for: .normal)
        button.setTitleColor(Theme.secondaryText, for: .disabled)
        button.backgroundColor = Theme.fill
        button.layer.cornerRadius = 15
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 18, bottom: 6, right: 18)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addTarget(self, action: #selector(tapped), for: .touchUpInside)

        let text = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        text.axis = .vertical
        text.spacing = 2

        let row = UIStackView(arrangedSubviews: [iconView, text, button])
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 60),
            iconView.heightAnchor.constraint(equalToConstant: 60),
            row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(_ pkg: Package, buttonTitle: String, onTap: @escaping () -> Void) {
        titleLabel.text = pkg.name
        subtitleLabel.text = pkg.shortDescription
        button.setTitle(buttonTitle, for: .normal)
        button.isEnabled = buttonTitle != "INSTALLED"
        self.onTap = onTap

        iconView.image = nil
        iconURL = pkg.icon
        if let url = pkg.icon {
            ImageLoader.load(url) { [weak self] image in
                if self?.iconURL == url { self?.iconView.image = image }
            }
        }
    }

    @objc private func tapped() { onTap?() }
}
