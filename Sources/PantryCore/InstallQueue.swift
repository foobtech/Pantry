import Foundation

/// Runs pantry-helper. Kept as a protocol so the queue can be tested without a device.
public protocol PrivilegedRunner {
    func run(_ arguments: [String]) throws -> (status: Int32, output: String)
}

public enum InstallEvent {
    case downloading(Package)
    case installing(Package)
    case refreshingIcons
    case finished
    case failed(String)
}

public final class InstallQueue {
    private let downloader: DebDownloader
    private let runner: PrivilegedRunner
    private let queue = DispatchQueue(label: "com.foobtech.pantry.install")
    public var onEvent: ((InstallEvent) -> Void)?

    public init(downloader: DebDownloader, runner: PrivilegedRunner) {
        self.downloader = downloader
        self.runner = runner
    }

    /// Downloads and verifies everything first, then installs in plan order, so a bad download never leaves a half-applied plan.
    public func install(_ plan: InstallPlan, repos: [String: Repo]) {
        queue.async {
            guard plan.isInstallable else {
                self.emit(.failed("Unmet dependencies: " + plan.unmet.joined(separator: ", ")))
                return
            }
            var files: [(Package, URL)] = []
            for pkg in plan.toInstall {
                guard let repo = repos[pkg.repoID] else {
                    self.emit(.failed("Unknown repo for \(pkg.name)")); return
                }
                self.emit(.downloading(pkg))
                let sem = DispatchSemaphore(value: 0)
                var outcome: Result<URL, Error> = .failure(DownloadError.badURL)
                self.downloader.download(pkg, from: repo) { outcome = $0; sem.signal() }
                sem.wait()
                switch outcome {
                case .success(let url): files.append((pkg, url))
                case .failure(let error): self.emit(.failed("\(pkg.name): \(error)")); return
                }
            }
            for (pkg, file) in files {
                self.emit(.installing(pkg))
                do {
                    let result = try self.runner.run(["install", file.path])
                    if result.status != 0 {
                        self.emit(.failed("\(pkg.name): dpkg exited \(result.status)\n\(result.output)")); return
                    }
                } catch {
                    self.emit(.failed("\(pkg.name): \(error)")); return
                }
            }
            self.emit(.refreshingIcons)
            _ = try? self.runner.run(["uicache"])
            self.emit(.finished)
        }
    }

    public func remove(identifier: String) {
        queue.async {
            do {
                let result = try self.runner.run(["remove", identifier])
                if result.status != 0 {
                    self.emit(.failed("\(identifier): dpkg exited \(result.status)\n\(result.output)")); return
                }
                self.emit(.refreshingIcons)
                _ = try? self.runner.run(["uicache"])
                self.emit(.finished)
            } catch {
                self.emit(.failed("\(identifier): \(error)"))
            }
        }
    }

    private func emit(_ event: InstallEvent) {
        DispatchQueue.main.async { self.onEvent?(event) }
    }
}
