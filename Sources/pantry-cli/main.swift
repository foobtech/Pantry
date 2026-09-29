import Foundation
import PantryCore

// Usage: swift run pantry-cli <repo-url> [--ios 16.5] [--scheme rootful|rootless|roothide] [--search text]
// Fetches a real repo with PantryCore and prints what it found. Dev harness for Linux/macOS only.

/// Runs a system tool (`gzip -dc`, `bzip2 -dc`, `xz -dc`) so the harness works on Linux and macOS.
struct ShellDecompressor: Decompressor {
    let tool: String
    func decompress(_ data: Data) throws -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [tool, "-dc"]
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        try p.run()
        DispatchQueue.global().async {
            inPipe.fileHandleForWriting.write(data)
            inPipe.fileHandleForWriting.closeFile()
        }
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw DecompressError.failed }
        return out
    }
}

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}

let ios = option("--ios") ?? "16.5"
let scheme = JailbreakScheme(rawValue: option("--scheme") ?? "rootless") ?? .rootless
let search = option("--search")?.lowercased()

guard let urlString = args.first, let url = URL(string: urlString) else {
    print("usage: pantry-cli <repo-url> [--ios 16.5] [--scheme rootful|rootless|roothide] [--search text]")
    exit(1)
}

let device = DeviceProfile(iOSVersion: DebianVersion(ios), scheme: scheme, machine: "iPhone12,1")
var decompressors = Decompressors(bzip2: ShellDecompressor(tool: "bzip2"), xz: ShellDecompressor(tool: "xz"))
#if !canImport(Compression)
decompressors.gzip = ShellDecompressor(tool: "gzip")   // no Compression framework on Linux
#endif

let fetcher = RepoFetcher(device: device, decompressors: decompressors)
let done = DispatchSemaphore(value: 0)

fetcher.fetchPackages(from: Repo(url: url)) { result in
    switch result {
    case .failure(let error):
        print("fetch failed: \(error)")
    case .success(let all):
        let latest = latestVersions(all)
        let compatible = latest.filter { $0.isCompatible(with: device) }
        print("device: iOS \(ios), \(scheme.rawValue) (\(device.architectures.joined(separator: ", ")))")
        print("packages: \(all.count) total, \(latest.count) unique, \(compatible.count) compatible\n")

        var shown = compatible.sorted { $0.name.lowercased() < $1.name.lowercased() }
        if let q = search {
            shown = shown.filter { $0.name.lowercased().contains(q) || $0.identifier.lowercased().contains(q) }
        }
        for p in shown.prefix(25) {
            print("\(p.name)  \(p.version)  [\(p.identifier)]  \(p.shortDescription)")
        }
        if shown.count > 25 { print("… and \(shown.count - 25) more") }
    }
    done.signal()
}
done.wait()
