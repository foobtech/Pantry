import UIKit

enum GetState: Equatable {
    case get, update, installed
    case working(Double)   // 0...1
}

/// The App Store's pill: GET / UPDATE / INSTALLED, turning into a progress ring while working.
final class GetButton: UIControl {
    static let size = CGSize(width: 72, height: 28)
    private static let font = UIFont.systemFont(ofSize: 12, weight: .bold)

    private let label = UILabel()
    private let track = CAShapeLayer()
    private let ring = CAShapeLayer()
    // Not called `state`: UIControl already has a read-only `state`.
    private(set) var buttonState: GetState = .get
    var onDark = false { didSet { apply() } }
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = GetButton.font
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

    /// GET stays compact like the App Store; longer words get just enough room.
    var preferredWidth: CGFloat {
        func fit(_ text: String) -> CGFloat {
            max(GetButton.size.width, ceil((text as NSString).size(withAttributes: [.font: GetButton.font]).width) + 24)
        }
        switch buttonState {
        case .installed: return fit("INSTALLED")
        case .update: return fit("UPDATE")
        default: return GetButton.size.width
        }
    }

    override var intrinsicContentSize: CGSize { CGSize(width: preferredWidth, height: GetButton.size.height) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }

    func set(_ new: GetState) {
        guard new != buttonState else { return }
        buttonState = new
        apply()
    }

    private func apply() {
        var working = false
        var fraction: CGFloat = 0
        if case .working(let f) = buttonState {
            working = true
            fraction = CGFloat(min(max(f, 0), 1))
        }
        label.isHidden = working
        track.isHidden = !working
        ring.isHidden = !working
        backgroundColor = working ? .clear : (onDark ? UIColor(white: 1, alpha: 0.28) : Theme.fill)

        switch buttonState {
        case .get: label.text = "GET"
        case .update: label.text = "UPDATE"
        case .installed: label.text = "INSTALLED"
        case .working: break
        }
        let tint = onDark ? UIColor.white : Theme.accent
        if buttonState == .installed {
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

        invalidateIntrinsicContentSize()
        setNeedsLayout()
        // Our width depends on the state, so the views that position us need to re-lay out.
        var ancestor = superview
        for _ in 0..<3 {
            ancestor?.setNeedsLayout()
            ancestor = ancestor?.superview
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        label.frame = bounds
        track.frame = bounds
        ring.frame = bounds
        let d = min(bounds.height, 26)
        let path = UIBezierPath(arcCenter: CGPoint(x: bounds.midX, y: bounds.midY), radius: d / 2 - 2,
                                startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: true).cgPath
        track.path = path
        ring.path = path
    }

    @objc private func tapped() {
        if buttonState == .get || buttonState == .update { onTap?() }
    }
}
