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
        case .hashMismatch(let e, let a): return "SHA-256 mismatch (expected \(e), got \(a))"
        case .missingHash: return "repo gave no SHA-256 for this package"
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

    public func download(_ pkg: Package, from repo: Repo, completion: @escaping (Result<URL, Error>) -> Void) {
        guard !pkg.filename.isEmpty, let url = URL(string: pkg.filename, relativeTo: repo.url)?.absoluteURL else {
            completion(.failure(DownloadError.badURL)); return
        }
        let safeVersion = pkg.version.raw.replacingOccurrences(of: ":", with: "%3a")
        let dest = cacheDir.appendingPathComponent("\(pkg.identifier)_\(safeVersion)_\(pkg.architecture).deb")

        var request = URLRequest(url: url)
        request.setValue("Pantry/0.1", forHTTPHeaderField: "User-Agent")
        session.downloadTask(with: request) { tmp, resp, err in
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard let tmp = tmp, status == 200 else {
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
        }.resume()
    }
}
