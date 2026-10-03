import UIKit

/// SF Symbols arrive in iOS 13; on iOS 12 these drawn, filled stand-ins are used instead.
enum TabIcons {
    enum Kind { case today, tweaks, apps, themes, search }

    static func image(_ kind: Kind) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 26, height: 26))
        let image = renderer.image { ctx in
            let c = ctx.cgContext
            UIColor.black.setFill()
            UIColor.black.setStroke()
            switch kind {
            case .today:
                UIBezierPath(roundedRect: CGRect(x: 3, y: 2, width: 20, height: 22), cornerRadius: 5).fill()
                c.setBlendMode(.clear)
                for y: CGFloat in [8, 13, 18] {
                    UIBezierPath(roundedRect: CGRect(x: 7, y: y, width: 12, height: 2), cornerRadius: 1).fill()
                }
            case .tweaks:
                let knobs: [CGFloat] = [8, 17, 11]
                for (i, x) in knobs.enumerated() {
                    let y = 5 + CGFloat(i) * 8
                    UIBezierPath(roundedRect: CGRect(x: 2, y: y - 1.2, width: 22, height: 2.5), cornerRadius: 1.2).fill()
                    UIBezierPath(ovalIn: CGRect(x: x - 4.5, y: y - 4.5, width: 9, height: 9)).fill()
                }
            case .apps:
                for i in 0..<3 {
                    UIBezierPath(roundedRect: CGRect(x: 3, y: 3 + CGFloat(i) * 7.5, width: 20, height: 6), cornerRadius: 3).fill()
                }
            case .themes:
                UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 22, height: 22)).fill()
                c.setBlendMode(.clear)
                for p in [CGPoint(x: 9, y: 9), CGPoint(x: 17, y: 9), CGPoint(x: 8, y: 16)] {
                    UIBezierPath(ovalIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)).fill()
                }
            case .search:
                let ring = UIBezierPath(ovalIn: CGRect(x: 3, y: 3, width: 14, height: 14))
                ring.lineWidth = 3
                ring.stroke()
                let handle = UIBezierPath()
                handle.move(to: CGPoint(x: 15, y: 15))
                handle.addLine(to: CGPoint(x: 23, y: 23))
                handle.lineWidth = 3.4
                handle.lineCapStyle = .round
                handle.stroke()
            }
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}
