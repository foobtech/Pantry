import Foundation

public struct Dependency: Hashable {
    public enum Op: String { case lt = "<<", le = "<=", eq = "=", ge = ">=", gt = ">>" }

    public let name: String
    public let op: Op?
    public let version: DebianVersion?

    public func isSatisfied(by v: DebianVersion) -> Bool {
        guard let op = op, let version = version else { return true }
        let c = DebianVersion.compare(v, version)
        switch op {
        case .lt: return c < 0
        case .le: return c <= 0
        case .eq: return c == 0
        case .ge: return c >= 0
        case .gt: return c > 0
        }
    }

    /// Parses "a (>= 1.0), b | c" into AND-groups of OR-alternatives.
    public static func parseList(_ s: String) -> [[Dependency]] {
        s.split(separator: ",").compactMap { group in
            let alts = group.split(separator: "|").compactMap { parseOne(String($0)) }
            return alts.isEmpty ? nil : alts
        }
    }

    private static func parseOne(_ s: String) -> Dependency? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        guard let open = t.firstIndex(of: "("), let close = t.lastIndex(of: ")"), open < close else {
            return Dependency(name: t, op: nil, version: nil)
        }
        let name = t[t.startIndex..<open].trimmingCharacters(in: .whitespaces)
        var inner = t[t.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
        let ops: [(String, Op)] = [(">=", .ge), ("<=", .le), ("<<", .lt), (">>", .gt), ("=", .eq), ("<", .le), (">", .ge)]
        for (token, op) in ops where inner.hasPrefix(token) {
            inner = String(inner.dropFirst(token.count)).trimmingCharacters(in: .whitespaces)
            return Dependency(name: name, op: op, version: DebianVersion(inner))
        }
        return Dependency(name: name, op: nil, version: nil)
    }
}
