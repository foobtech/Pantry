import UIKit

struct Screenshot {
    let url: String
    let aspect: CGFloat?   // width / height, when the depiction says
}

struct Depiction {
    var screenshots: [Screenshot] = []
    var headerImage: String?   // the package's banner
    var tint: UIColor?
}

/// Most repos describe a package with a Sileo "native depiction" JSON file.
/// We take its screenshots, its header banner image, and its accent colour.
/// Call from the main thread.
enum DepictionLoader {
    private static var cache: [String: Depiction] = [:]
    private static var waiting: [String: [(Depiction) -> Void]] = [:]

    static func depiction(for pkg: Package, completion: @escaping (Depiction) -> Void) {
        guard let text = pkg.sileoDepiction, let url = URL(string: text) else { completion(Depiction()); return }
        if let hit = cache[text] { completion(hit); return }
        if waiting[text] != nil { waiting[text]?.append(completion); return }
        waiting[text] = [completion]

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Pantry/0.1", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            var result = Depiction()
            if let data = data, let json = try? JSONSerialization.jsonObject(with: data) {
                if let root = json as? [String: Any] {
                    result.headerImage = root["headerImage"] as? String
                    result.tint = (root["tintColor"] as? String).flatMap { UIColor(css: $0) }
                }
                collect(json, into: &result.screenshots)
            }
            DispatchQueue.main.async {
                cache[text] = result
                let callbacks = waiting[text] ?? []
                waiting[text] = nil
                for cb in callbacks { cb(result) }
            }
        }.resume()
    }

    /// Walks the whole JSON tree (depictions nest views inside tabs and stacks) for screenshot lists.
    private static func collect(_ node: Any, into out: inout [Screenshot]) {
        if let dict = node as? [String: Any] {
            if dict["class"] as? String == "DepictionScreenshotsView",
               let items = dict["screenshots"] as? [[String: Any]] {
                let aspect = (dict["itemSize"] as? String).flatMap(parseAspect)
                for item in items {
                    if let u = item["url"] as? String, item["video"] as? Bool != true {
                        out.append(Screenshot(url: u, aspect: aspect))
                    }
                }
            }
            for value in dict.values { collect(value, into: &out) }
        } else if let array = node as? [Any] {
            for value in array { collect(value, into: &out) }
        }
    }

    /// "{160, 275.4}" -> 0.58
    private static func parseAspect(_ size: String) -> CGFloat? {
        let parts = size.trimmingCharacters(in: CharacterSet(charactersIn: "{} "))
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, parts[1] > 0 else { return nil }
        return CGFloat(parts[0] / parts[1])
    }
}
