import UIKit

enum Theme {
    static let accent = UIColor(red: 0, green: 0.478, blue: 1, alpha: 1)

    static var background: UIColor {
        if #available(iOS 13.0, *) { return .systemBackground }
        return .white
    }
    static var secondaryText: UIColor {
        if #available(iOS 13.0, *) { return .secondaryLabel }
        return .gray
    }
    static var fill: UIColor {
        if #available(iOS 13.0, *) { return .secondarySystemFill }
        return UIColor(white: 0.94, alpha: 1)
    }
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
