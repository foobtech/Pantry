import Foundation

/// Debian version: [epoch:]upstream[-revision], compared with dpkg's algorithm.
public struct DebianVersion: Comparable, Hashable, CustomStringConvertible {
    public let epoch: Int
    public let upstream: String
    public let revision: String
    public let raw: String

    public init(_ string: String) {
        raw = string
        var rest = string.trimmingCharacters(in: .whitespaces)
        var epoch = 0
        if let colon = rest.firstIndex(of: ":"), let e = Int(rest[rest.startIndex..<colon]) {
            epoch = e
            rest = String(rest[rest.index(after: colon)...])
        }
        var upstream = rest
        var revision = ""
        if let dash = rest.lastIndex(of: "-") {
            upstream = String(rest[rest.startIndex..<dash])
            revision = String(rest[rest.index(after: dash)...])
        }
        self.epoch = epoch
        self.upstream = upstream
        self.revision = revision
    }

    public var description: String { raw }

    public static func == (a: DebianVersion, b: DebianVersion) -> Bool { compare(a, b) == 0 }
    public static func < (a: DebianVersion, b: DebianVersion) -> Bool { compare(a, b) < 0 }
    public func hash(into h: inout Hasher) { h.combine(epoch); h.combine(upstream); h.combine(revision) }

    public static func compare(_ a: DebianVersion, _ b: DebianVersion) -> Int {
        if a.epoch != b.epoch { return a.epoch < b.epoch ? -1 : 1 }
        let u = verrevcmp(a.upstream, b.upstream)
        if u != 0 { return u < 0 ? -1 : 1 }
        let r = verrevcmp(a.revision, b.revision)
        return r == 0 ? 0 : (r < 0 ? -1 : 1)
    }

    private static func isDigit(_ c: UInt8) -> Bool { c >= 48 && c <= 57 }
    private static func isAlpha(_ c: UInt8) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) }

    private static func order(_ c: UInt8?) -> Int {
        guard let c = c else { return 0 }
        if isDigit(c) { return 0 }
        if isAlpha(c) { return Int(c) }
        if c == 126 { return -1 } // "~" sorts before everything, even the end
        return Int(c) + 256
    }

    private static func verrevcmp(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1.utf8), b = Array(s2.utf8)
        var i = 0, j = 0
        while i < a.count || j < b.count {
            var firstDiff = 0
            while (i < a.count && !isDigit(a[i])) || (j < b.count && !isDigit(b[j])) {
                let ac = order(i < a.count ? a[i] : nil)
                let bc = order(j < b.count ? b[j] : nil)
                if ac != bc { return ac - bc }
                i += 1; j += 1
            }
            while i < a.count && a[i] == 48 { i += 1 }
            while j < b.count && b[j] == 48 { j += 1 }
            while i < a.count && isDigit(a[i]) && j < b.count && isDigit(b[j]) {
                if firstDiff == 0 { firstDiff = Int(a[i]) - Int(b[j]) }
                i += 1; j += 1
            }
            if i < a.count && isDigit(a[i]) { return 1 }
            if j < b.count && isDigit(b[j]) { return -1 }
            if firstDiff != 0 { return firstDiff }
        }
        return 0
    }
}
