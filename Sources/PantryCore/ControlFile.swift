import Foundation

/// One paragraph of a Debian control-style file (Packages, Release). Keys are lowercased.
public typealias Stanza = [String: String]

public enum ControlFile {
    public static func parse(_ text: String) -> [Stanza] {
        var stanzas: [Stanza] = []
        var current: Stanza = [:]
        var lastKey: String?

        func flush() {
            if !current.isEmpty { stanzas.append(current) }
            current = [:]
            lastKey = nil
        }

        for sub in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = sub
            if line.hasSuffix("\r") { line = line.dropLast() }

            if line.allSatisfy({ $0 == " " || $0 == "\t" }) {
                if line.isEmpty { flush() }   // whitespace-only lines are ignored
                continue
            }
            if line.hasPrefix("#") { continue }

            if line.first == " " || line.first == "\t" {
                // Continuation line; " ." stands for an empty line.
                guard let key = lastKey else { continue }
                var extra = line.trimmingCharacters(in: .whitespaces)
                if extra == "." { extra = "" }
                current[key, default: ""] += "\n" + extra
            } else if let colon = line.firstIndex(of: ":") {
                let key = line[line.startIndex..<colon].lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                current[key] = value
                lastKey = key
            }
        }
        flush()
        return stanzas
    }
}
