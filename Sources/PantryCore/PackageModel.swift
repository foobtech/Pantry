import Foundation

public struct Package: Hashable {
    public let identifier: String
    public let name: String
    public let version: DebianVersion
    public let architecture: String
    public let shortDescription: String
    public let longDescription: String
    public let section: String
    public let author: String
    public let maintainer: String
    public let depends: [[Dependency]]
    public let filename: String
    public let size: Int
    public let sha256: String
    public let icon: String?
    public let depiction: String?
    public let sileoDepiction: String?
    public let isPaid: Bool
    public let repoID: String

    public init?(stanza s: Stanza, repoID: String) {
        guard let id = s["package"], !id.isEmpty, let ver = s["version"] else { return nil }
        identifier = id
        name = s["name"] ?? id
        version = DebianVersion(ver)
        architecture = s["architecture"] ?? "all"
        let desc = s["description"] ?? ""
        let parts = desc.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        shortDescription = parts.first.map(String.init) ?? ""
        longDescription = parts.count > 1 ? String(parts[1]) : ""
        section = s["section"] ?? "Miscellaneous"
        author = s["author"] ?? ""
        maintainer = s["maintainer"] ?? ""
        depends = Dependency.parseList((s["depends"] ?? "") + (s["pre-depends"].map { "," + $0 } ?? ""))
        filename = s["filename"] ?? ""
        size = Int(s["size"] ?? "") ?? 0
        sha256 = s["sha256"] ?? ""
        icon = s["icon"]
        depiction = s["depiction"]
        sileoDepiction = s["sileodepiction"]
        isPaid = (s["tag"] ?? "").contains("cydia::commercial")
        self.repoID = repoID
    }

    public static func parseIndex(_ text: String, repoID: String) -> [Package] {
        ControlFile.parse(text).compactMap { Package(stanza: $0, repoID: repoID) }
    }

    /// True if this package can run on the given device (architecture + `firmware` constraints).
    public func isCompatible(with device: DeviceProfile) -> Bool {
        guard architecture == "all" || device.architectures.contains(architecture) else { return false }
        for group in depends {
            let fw = group.filter { $0.name == "firmware" }
            if !fw.isEmpty && !fw.contains(where: { $0.isSatisfied(by: device.iOSVersion) }) { return false }
        }
        return true
    }
}

/// Keeps only the newest version of each package identifier.
public func latestVersions(_ packages: [Package]) -> [Package] {
    var best: [String: Package] = [:]
    for p in packages {
        if let existing = best[p.identifier], existing.version >= p.version { continue }
        best[p.identifier] = p
    }
    return Array(best.values)
}
