import Foundation

/// Runs pantry-helper. Kept as a protocol so the queue can be tested without a device.
public protocol PrivilegedRunner {
    func run(_ arguments: [String]) throws -> (status: Int32, output: String)
}

public enum InstallEvent {
    case downloading(Package)
    case installing(Package)
    case progress(Double)      // overall 0...1 across every download and install in the plan
    case refreshingIcons
    case finished
    case failed(String)
}

public final class InstallQueue {
    private let downloader: DebDownloader
    private let runner: PrivilegedRunner
    private let queue = DispatchQueue(label: "com.foobtech.pantry.install")
    public var onEvent: ((InstallEvent) -> Void)?
    /// Lets the app swap a package's download URL right before it is fetched (paid packages).
    public var urlResolver: ((Package, @escaping (Result<URL?, Error>) -> Void) -> Void)?

    public init(downloader: DebDownloader, runner: PrivilegedRunner) {
        self.downloader = downloader
        self.runner = runner
    }

    /// Downloads and verifies everything first, then installs in plan order, so a bad download never leaves a half-applied plan.
    public func install(_ plan: InstallPlan, repos: [String: Repo]) {
        queue.async {
            guard plan.isInstallable else {
                self.emit(.failed("Missing dependencies: " + plan.unmet.joined(separator: ", ")))
                return
            }
            let n = max(plan.toInstall.count, 1)
            var lastReported = -1.0
            func report(_ value: Double) {
                if value - lastReported >= 0.01 || value >= 1 {
                    lastReported = value
                    self.emit(.progress(value))
                }
            }

            var files: [(Package, URL)] = []
            for (i, pkg) in plan.toInstall.enumerated() {
                guard let repo = repos[pkg.repoID] else {
                    self.emit(.failed("\(pkg.name): its source was removed")); return
                }
                self.emit(.downloading(pkg))
                var override: URL?
                if let resolver = self.urlResolver {
                    let resolveWait = DispatchSemaphore(value: 0)
                    var resolved: Result<URL?, Error> = .success(nil)
                    resolver(pkg) { resolved = $0; resolveWait.signal() }
                    resolveWait.wait()
                    switch resolved {
                    case .success(let url): override = url
                    case .failure(let error): self.emit(.failed("\(pkg.name): \(describe(error))")); return
                    }
                }
                let sem = DispatchSemaphore(value: 0)
                var outcome: Result<URL, Error> = .failure(DownloadError.badURL)
                self.downloader.download(pkg, from: repo, urlOverride: override, progress: { f in
                    report((Double(i) + f) / Double(2 * n))
                }, completion: { outcome = $0; sem.signal() })
                sem.wait()
                switch outcome {
                case .success(let url): files.append((pkg, url))
                case .failure(let error): self.emit(.failed("\(pkg.name): \(describe(error))")); return
                }
                report(Double(i + 1) / Double(2 * n))
            }
            for (j, (pkg, file)) in files.enumerated() {
                self.emit(.installing(pkg))
                do {
                    let result = try self.runner.run(["install", file.path])
                    if result.status != 0 {
                        self.emit(.failed("\(pkg.name): \(InstallQueue.tail(result.output, fallback: "install failed (code \(result.status))"))")); return
                    }
                } catch {
                    self.emit(.failed("\(pkg.name): \(describe(error))")); return
                }
                report(Double(n + j + 1) / Double(2 * n))
            }
            self.emit(.refreshingIcons)
            _ = try? self.runner.run(["uicache"])
            report(1)
            self.emit(.finished)
        }
    }

    public func remove(identifier: String) {
        queue.async {
            do {
                let result = try self.runner.run(["remove", identifier])
                if result.status != 0 {
                    self.emit(.failed("\(identifier): \(InstallQueue.tail(result.output, fallback: "remove failed (code \(result.status))"))")); return
                }
                self.emit(.refreshingIcons)
                _ = try? self.runner.run(["uicache"])
                self.emit(.finished)
            } catch {
                self.emit(.failed("\(identifier): \(describe(error))"))
            }
        }
    }

    /// The end of dpkg's output is where the actual complaint is.
    private static func tail(_ output: String, fallback: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return fallback }
        return trimmed.count > 300 ? "…" + String(trimmed.suffix(300)) : trimmed
    }

    private func emit(_ event: InstallEvent) {
        DispatchQueue.main.async { self.onEvent?(event) }
    }
}
