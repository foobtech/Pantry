import Foundation

/// What dpkg says is installed, read from the dpkg status file.
public struct InstalledDatabase {
    public private(set) var versions: [String: DebianVersion] = [:]
    public private(set) var provided: Set<String> = []

    public init() {}

    public init(statusText: String) {
        for stanza in ControlFile.parse(statusText) {
            guard let name = stanza["package"],
                  let status = stanza["status"],
                  status.split(separator: " ").last == "installed" else { continue }
            versions[name] = DebianVersion(stanza["version"] ?? "0")
            for group in Dependency.parseList(stanza["provides"] ?? "") {
                for p in group { provided.insert(p.name) }
            }
        }
    }

    public static func load(for device: DeviceProfile) -> InstalledDatabase {
        let path = device.pathPrefix + "/var/lib/dpkg/status"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return InstalledDatabase() }
        return InstalledDatabase(statusText: text)
    }

    public func version(of identifier: String) -> DebianVersion? { versions[identifier] }

    public func satisfies(_ dep: Dependency) -> Bool {
        if let v = versions[dep.name] { return dep.isSatisfied(by: v) }
        return provided.contains(dep.name)
    }
}

/// Packages from all repos that this device can actually run, indexed for dependency lookup.
public struct PackageIndex {
    private var byName: [String: [Package]] = [:]
    private var providers: [String: [Package]] = [:]

    public init(packages: [Package], device: DeviceProfile) {
        for p in packages where p.isCompatible(with: device) {
            byName[p.identifier, default: []].append(p)
            for provided in p.provides { providers[provided.name, default: []].append(p) }
        }
        for key in Array(byName.keys) {
            byName[key] = byName[key]!.sorted { $0.version > $1.version }
        }
    }

    public func candidates(for dep: Dependency) -> [Package] {
        let direct = (byName[dep.name] ?? []).filter { dep.isSatisfied(by: $0.version) }
        return direct + (providers[dep.name] ?? [])
    }
}

public struct InstallPlan {
    public var toInstall: [Package]   // dependencies first
    public var unmet: [String]        // human-readable, e.g. "libfoo (>= 2.0) | libbar"
    public var isInstallable: Bool { unmet.isEmpty }
}

public enum Resolver {
    /// Builds an install order for `root`. `firmware` constraints are handled by compatibility filtering.
    public static func plan(installing root: Package, index: PackageIndex, installed: InstalledDatabase) -> InstallPlan {
        var ordered: [Package] = []
        var visiting = Set<String>()
        var done = Set<String>()
        var unmet: [String] = []

        func visit(_ pkg: Package) {
            if done.contains(pkg.identifier) || visiting.contains(pkg.identifier) { return }
            visiting.insert(pkg.identifier)
            for group in pkg.depends {
                if group.contains(where: { $0.name == "firmware" }) { continue }
                if group.contains(where: { installed.satisfies($0) }) { continue }
                var chosen: Package?
                for alt in group {
                    if let c = index.candidates(for: alt).first { chosen = c; break }
                }
                if let dep = chosen {
                    visit(dep)
                } else {
                    unmet.append(group.map { $0.name }.joined(separator: " | "))
                }
            }
            visiting.remove(pkg.identifier)
            done.insert(pkg.identifier)
            ordered.append(pkg)
        }

        visit(root)
        return InstallPlan(toInstall: ordered, unmet: unmet)
    }
}
