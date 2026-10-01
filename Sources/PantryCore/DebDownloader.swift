import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum DownloadError: Error, CustomStringConvertible {
    case badURL, http(Int), hashMismatch(expected: String, actual: String), missingHash

    public var description: String {
        switch self {
        case .badURL: return "bad package URL"
        case .http(let c): return "download failed (HTTP \(c))"
        case .hashMismatch: return "the download didn't match the repo's SHA-256, so it was discarded"
        case .missingHash: return "the repo gave no SHA-256 for this package"
        }
    }
}

public final class DebDownloader {
    private let session: URLSession
    private let cacheDir: URL
    public var allowUnverified = false   // keep false; only for repos that publish no SHA256

    /// On device, cacheDir must be the directory pantry-helper allows: /var/mobile/Library/Caches/com.foobtech.pantry
    public init(cacheDir: URL, session: URLSession = .shared) {
        self.cacheDir = cacheDir
        self.session = session
    }

    /// `progress` reports 0...1 for this one download (Apple platforms only).
    public func download(_ pkg: Package, from repo: Repo, progress: ((Double) -> Void)? = nil,
                         completion: @escaping (Result<URL, Error>) -> Void) {
        guard !pkg.filename.isEmpty, let url = URL(string: pkg.filename, relativeTo: repo.url)?.absoluteURL else {
            completion(.failure(DownloadError.badURL)); return
        }
        let safeVersion = pkg.version.raw.replacingOccurrences(of: ":", with: "%3a")
        let dest = cacheDir.appendingPathComponent("\(pkg.identifier)_\(safeVersion)_\(pkg.architecture).deb")
        start(pkg, url, dest, attemptsLeft: 3, progress, completion)
    }

    private static func isTransient(_ error: Error?) -> Bool {
        guard let error = error else { return false }
        let ns = error as NSError
        // -1005 connection lost, -1001 timed out, -1004 couldn't connect, -1200 TLS failure
        return ns.domain == NSURLErrorDomain && [-1005, -1001, -1004, -1200].contains(ns.code)
    }

    private func start(_ pkg: Package, _ url: URL, _ dest: URL, attemptsLeft: Int,
                       _ progress: ((Double) -> Void)?, _ completion: @escaping (Result<URL, Error>) -> Void) {
        var request = URLRequest(url: url)
        request.setValue("Pantry/0.1", forHTTPHeaderField: "User-Agent")

        #if canImport(Darwin)
        var observation: NSKeyValueObservation?
        #endif

        let task = session.downloadTask(with: request) { tmp, resp, err in
            #if canImport(Darwin)
            observation?.invalidate()
            observation = nil
            #endif
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard let tmp = tmp, status == 200 else {
                if attemptsLeft > 1, DebDownloader.isTransient(err) {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                        self.start(pkg, url, dest, attemptsLeft: attemptsLeft - 1, progress, completion)
                    }
                    return
                }
                completion(.failure(err ?? DownloadError.http(status))); return
            }
            do {
                let digest = try SHA256.hashOfFile(at: tmp)
                if pkg.sha256.isEmpty {
                    if !self.allowUnverified { throw DownloadError.missingHash }
                } else if digest != pkg.sha256.lowercased() {
                    throw DownloadError.hashMismatch(expected: pkg.sha256, actual: digest)
                }
                let fm = FileManager.default
                try fm.createDirectory(at: self.cacheDir, withIntermediateDirectories: true, attributes: nil)
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try fm.moveItem(at: tmp, to: dest)
                completion(.success(dest))
            } catch {
                completion(.failure(error))
            }
        }

        #if canImport(Darwin)
        if let progress = progress {
            observation = task.progress.observe(\.fractionCompleted, options: [.new]) { p, _ in
                progress(p.fractionCompleted)
            }
        }
        #endif
        task.resume()
    }
}
