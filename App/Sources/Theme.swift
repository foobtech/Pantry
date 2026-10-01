import UIKit

enum Theme {
    static let accent = UIColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1)

    static var background: UIColor {
        if #available(iOS 13.0, *) { return .systemBackground }
        return .white
    }
    static var secondaryBackground: UIColor {
        if #available(iOS 13.0, *) { return .secondarySystemBackground }
        return UIColor(white: 0.95, alpha: 1)
    }
    static var label: UIColor {
        if #available(iOS 13.0, *) { return .label }
        return .black
    }
    static var secondaryText: UIColor {
        if #available(iOS 13.0, *) { return .secondaryLabel }
        return .gray
    }
    static var separator: UIColor {
        if #available(iOS 13.0, *) { return .separator }
        return UIColor(white: 0.8, alpha: 1)
    }
    static var fill: UIColor {
        if #available(iOS 13.0, *) { return .secondarySystemFill }
        return UIColor(white: 0.94, alpha: 1)
    }

    static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 5381
        for b in s.utf8 { h = (h &* 33) &+ UInt64(b) }
        return h
    }

    /// Card artwork colours: a stable hue per package (we have icons, not hero art).
    static func gradientColors(for key: String) -> [CGColor] {
        let hue = CGFloat(hash(key) % 360) / 360
        let top = UIColor(hue: hue, saturation: 0.45, brightness: 0.85, alpha: 1)
        let bottom = UIColor(hue: hue, saturation: 0.75, brightness: 0.42, alpha: 1)
        return [top.cgColor, bottom.cgColor]
    }

    static func avatarImage() -> UIImage? {
        if #available(iOS 13.0, *),
           let img = UIImage(systemName: "person.crop.circle.fill",
                             withConfiguration: UIImage.SymbolConfiguration(pointSize: 32)) {
            return img
        }
        UIGraphicsBeginImageContextWithOptions(CGSize(width: 32, height: 32), false, 0)
        defer { UIGraphicsEndImageContext() }
        accent.setFill()
        UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 32, height: 32)).fill()
        ("P" as NSString).draw(at: CGPoint(x: 10, y: 6),
                               withAttributes: [.font: UIFont.boldSystemFont(ofSize: 18), .foregroundColor: UIColor.white])
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

final class GradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    var gradient: CAGradientLayer { layer as! CAGradientLayer }
}

enum ImageLoader {
    private static let cache = NSCache<NSString, UIImage>()

    static func load(_ string: String, completion: @escaping (UIImage?) -> Void) {
        if let hit = cache.object(forKey: string as NSString) { completion(hit); return }
        guard let url = URL(string: string), url.scheme == "https" || url.scheme == "http" else {
            completion(nil); return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let image = data.flatMap { UIImage(data: $0) }
            if let image = image { cache.setObject(image, forKey: string as NSString) }
            DispatchQueue.main.async { completion(image) }
        }.resume()
    }
}

extension UIView {
    var owningViewController: UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController { return vc }
            responder = next
        }
        return nil
    }
}

func sideMargin(for width: CGFloat) -> CGFloat { width >= 700 ? 28 : 20 }
func columnCount(for width: CGFloat) -> Int { width >= 900 ? 3 : (width >= 600 ? 2 : 1) }

func textHeight(_ text: String, font: UIFont, width: CGFloat, maxLines: Int = 0) -> CGFloat {
    guard !text.isEmpty, width > 0 else { return 0 }
    let rect = (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                               options: [.usesLineFragmentOrigin],
                                               attributes: [.font: font], context: nil)
    var h = ceil(rect.height)
    if maxLines > 0 { h = min(h, ceil(font.lineHeight) * CGFloat(maxLines)) }
    return h
}
