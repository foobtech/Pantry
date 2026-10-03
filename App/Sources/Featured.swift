import UIKit

struct Banner {
    let repoID: String
    let packageID: String
    let imageURL: String   // 16:9 artwork, per the Sileo featured spec
    let title: String
}

/// A repo's `sileo-featured.json` (at the repo's top level) lists banner art for its featured packages.
enum FeaturedLoader {
    static func load(_ repo: Repo, completion: @escaping ([Banner]) -> Void) {
        var request = URLRequest(url: repo.url.appendingPathComponent("sileo-featured.json"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Pantry/0.1", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, resp, _ in
            var found: [Banner] = []
            if (resp as? HTTPURLResponse)?.statusCode == 200, let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) {
                collect(json, repo.id, &found)
            }
            DispatchQueue.main.async { completion(found) }
        }.resume()
    }

    private static func collect(_ node: Any, _ repoID: String, _ out: inout [Banner]) {
        if let dict = node as? [String: Any] {
            if let items = dict["banners"] as? [[String: Any]] {
                for item in items {
                    if let url = item["url"] as? String, let package = item["package"] as? String {
                        out.append(Banner(repoID: repoID, packageID: package, imageURL: url,
                                          title: (item["title"] as? String) ?? ""))
                    }
                }
            }
            for value in dict.values { collect(value, repoID, &out) }
        } else if let array = node as? [Any] {
            for value in array { collect(value, repoID, &out) }
        }
    }
}

struct CardArt {
    var bannerURL: String?
    var tint: UIColor?
}

enum CardArtLoader {
    /// Banner art for a package's card: the repo's featured banner first, then the depiction's header image.
    static func art(for pkg: Package, completion: @escaping (CardArt) -> Void) {
        if let banner = Store.shared.bannerByPackage[pkg.identifier] {
            completion(CardArt(bannerURL: banner.imageURL, tint: nil))
            return
        }
        DepictionLoader.depiction(for: pkg) { d in
            completion(CardArt(bannerURL: d.headerImage, tint: d.tint))
        }
    }
}
