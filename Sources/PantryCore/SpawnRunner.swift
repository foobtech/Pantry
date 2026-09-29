import Foundation

#if canImport(Darwin)
import Darwin

public enum SpawnError: Error { case pipe, spawn(Int32) }

/// Runs pantry-helper with posix_spawn (Process/NSTask isn't available in the public iOS SDK).
public final class SpawnRunner: PrivilegedRunner {
    public let helperPath: String

    public init(device: DeviceProfile) {
        helperPath = device.pathPrefix + "/usr/libexec/pantry/pantry-helper"
    }

    public func run(_ arguments: [String]) throws -> (status: Int32, output: String) {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { throw SpawnError.pipe }

        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_adddup2(&actions, fds[1], 1)
        posix_spawn_file_actions_adddup2(&actions, fds[1], 2)
        posix_spawn_file_actions_addclose(&actions, fds[0])
        defer { posix_spawn_file_actions_destroy(&actions) }

        var argv: [UnsafeMutablePointer<CChar>?] = ([helperPath] + arguments).map { strdup($0) }
        argv.append(nil)
        defer { for p in argv { free(p) } }
        var envp: [UnsafeMutablePointer<CChar>?] = [nil]   // the helper builds its own clean environment

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, helperPath, &actions, nil, &argv, &envp)
        close(fds[1])
        guard rc == 0 else { close(fds[0]); throw SpawnError.spawn(rc) }

        var out = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fds[0], &buf, buf.count)
            if n <= 0 { break }
            out.append(buf, count: n)
        }
        close(fds[0])

        var st: Int32 = 0
        waitpid(pid, &st, 0)
        let exited = (st & 0x7f) == 0
        return (exited ? (st >> 8) & 0xff : -1, String(decoding: out, as: UTF8.self))
    }
}
#endif
