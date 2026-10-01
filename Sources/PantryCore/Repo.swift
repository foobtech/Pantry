import Foundation

public struct Repo: Hashable, Codable {
    public let url: URL            // base URL, always with a trailing slash
    public let suite: String       // "./" for flat (Cydia-style) repos
    public let components: [String]

    public var id: String { url.absoluteString + suite }
    public var isFlat: Bool { suite.hasSuffix("/") }

    public init(url: URL, suite: String = "./", components: [String] = ["main"]) {
        let s = url.absoluteString
        self.url = s.hasSuffix("/") ? url : URL(string: s + "/")!
        self.suite = suite
        self.components = components
    }

    /// Where the Packages index lives, minus the compression extension.
    public func indexBases(architectures: [String]) -> [URL] {
        if isFlat { return [url.appendingPathComponent("Packages")] }
        var bases: [URL] = []
        for c in components {
            for a in architectures {
                bases.append(url.appendingPathComponent("dists/\(suite)/\(c)/binary-\(a)/Packages"))
            }
        }
        return bases
    }
}
