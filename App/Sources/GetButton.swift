import UIKit

enum GetState: Equatable {
    case get, update, installed
    case working(Double)   // 0...1
}

/// The App Store's pill: GET / UPDATE / INSTALLED, turning into a progress ring while working.
final class GetButton: UIControl {
    static let size = CGSize(width: 84, height: 30)

    private let label = UILabel()
    private let track = CAShapeLayer()
    private let ring = CAShapeLayer()
    private(set) var state: GetState = .get
    var onDark = false { didSet { apply() } }
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 13, weight: .bold)
        label.textAlignment = .center
        addSubview(label)
        for l in [track, ring] {
            l.fillColor = UIColor.clear.cgColor
            l.lineWidth = 3
            layer.addSublayer(l)
        }
        ring.lineCap = .round
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        apply()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: CGSize { GetButton.size }
    override func sizeThatFits(_ size: CGSize) -> CGSize { GetButton.size }

    func set(_ new: GetState) {
        guard new != state else { return }
        state = new
        apply()
    }

    private func apply() {
        var working = false
        var fraction: CGFloat = 0
        if case .working(let f) = state {
            working = true
            fraction = CGFloat(min(max(f, 0), 1))
        }
        label.isHidden = working
        track.isHidden = !working
        ring.isHidden = !working
        backgroundColor = working ? .clear : (onDark ? UIColor(white: 1, alpha: 0.28) : Theme.fill)

        switch state {
        case .get: label.text = "GET"
        case .update: label.text = "UPDATE"
        case .installed: label.text = "INSTALLED"
        case .working: break
        }
        let tint = onDark ? UIColor.white : Theme.accent
        if state == .installed {
            label.textColor = onDark ? UIColor(white: 1, alpha: 0.75) : Theme.secondaryText
        } else {
            label.textColor = tint
        }
        track.strokeColor = (onDark ? UIColor(white: 1, alpha: 0.3) : Theme.fill).cgColor
        ring.strokeColor = tint.cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.strokeEnd = fraction
        CATransaction.commit()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        label.frame = bounds
        track.frame = bounds
        ring.frame = bounds
        let d = min(bounds.height, 28)
        let path = UIBezierPath(arcCenter: CGPoint(x: bounds.midX, y: bounds.midY), radius: d / 2 - 2,
                                startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: true).cgPath
        track.path = path
        ring.path = path
    }

    @objc private func tapped() {
        if state == .get || state == .update { onTap?() }
    }
}
