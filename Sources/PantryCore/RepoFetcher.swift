import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLSession lives here on Linux
#endif

public enum FetchError: Error { case notFound, http(Int) }

public final class RepoFetcher {
    public var decompressors: Decompressors
    private let session: URLSession
    private let device: DeviceProfile
    private let lock = NSLock()

    public init(device: DeviceProfile = .current(), decompressors: Decompressors = Decompressors(),
                session: URLSession = .shared) {
        self.device = device
        self.decompressors = decompressors
        self.session = session
    }

    private enum Encoding: String { case gz = ".gz", bz2 = ".bz2", xz = ".xz", none = "" }

    private var encodings: [Encoding] {
        var e: [Encoding] = [.gz]
        if decompressors.bzip2 != nil { e.append(.bz2) }
        if decompressors.xz != nil { e.append(.xz) }
        e.append(.none)
        return e
    }

    /// Fetches every index for the repo and returns all packages (not filtered by compatibility).
    public func fetchPackages(from repo: Repo, completion: @escaping (Result<[Package], Error>) -> Void) {
        let bases = repo.indexBases(architectures: device.architectures)
        let group = DispatchGroup()
        var all: [Package] = []
        var lastError: Error?

        for base in bases {
            group.enter()
            let candidates = encodings.map { (URL(string: base.absoluteString + $0.rawValue)!, $0) }
            attempt(candidates, 0, repoID: repo.id) { result in
                self.lock.lock()
                switch result {
                case .success(let pkgs): all += pkgs
                case .failure(let err): lastError = err
                }
                self.lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .global()) {
            if all.isEmpty, let err = lastError { completion(.failure(err)) } else { completion(.success(all)) }
        }
    }

    private func attempt(_ list: [(URL, Encoding)], _ i: Int, repoID: String, lastError: Error? = nil,
                         completion: @escaping (Result<[Package], Error>) -> Void) {
        guard i < list.count else { completion(.failure(lastError ?? FetchError.notFound)); return }
        var req = URLRequest(url: list[i].0)
        req.setValue("Pantry/0.1", forHTTPHeaderField: "User-Agent")
        req.setValue(device.iOSVersion.raw, forHTTPHeaderField: "X-Firmware")   // some repos gate on these
        req.setValue(device.machine, forHTTPHeaderField: "X-Machine")

        session.dataTask(with: req) { data, resp, err in
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard status == 200, let data = data else {
                self.attempt(list, i + 1, repoID: repoID, lastError: err ?? FetchError.http(status), completion: completion)
                return
            }
            do {
                let raw = try self.decode(data, list[i].1)
                let pkgs = Package.parseIndex(String(decoding: raw, as: UTF8.self), repoID: repoID)
                completion(.success(pkgs))
            } catch {
                self.attempt(list, i + 1, repoID: repoID, lastError: error, completion: completion)
            }
        }.resume()
    }

    private func decode(_ data: Data, _ enc: Encoding) throws -> Data {
        switch enc {
        case .gz:  return try decompressors.gzip?.decompress(data) ?? Gzip.decompress(data)
        case .bz2: guard let d = decompressors.bzip2 else { throw DecompressError.unsupported }; return try d.decompress(data)
        case .xz:  guard let d = decompressors.xz else { throw DecompressError.unsupported }; return try d.decompress(data)
        case .none: return data
        }
    }
}
