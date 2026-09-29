import Foundation

/// How the current jailbreak lays out the filesystem. Decides package architecture and path prefix.
public enum JailbreakScheme: String {
    case rootful    // classic: iphoneos-arm, paths from /
    case rootless   // Dopamine etc.: iphoneos-arm64, paths under /var/jb
    case roothide   // roothide: iphoneos-arm64e, randomized jbroot

    public var architectures: [String] {
        switch self {
        case .rootful:  return ["iphoneos-arm"]
        case .rootless: return ["iphoneos-arm64"]
        case .roothide: return ["iphoneos-arm64e"]
        }
    }
}

/// What this device is, so the UI can hide packages that can't work here.
public struct DeviceProfile {
    public var iOSVersion: DebianVersion
    public var scheme: JailbreakScheme
    public var machine: String

    public var architectures: [String] { scheme.architectures }

    public var pathPrefix: String { scheme == .rootless ? "/var/jb" : "" }

    public init(iOSVersion: DebianVersion, scheme: JailbreakScheme, machine: String) {
        self.iOSVersion = iOSVersion
        self.scheme = scheme
        self.machine = machine
    }

    /// Auto-detects rootful vs rootless. roothide can't be detected reliably this way; pass it explicitly.
    public static func current(schemeOverride: JailbreakScheme? = nil) -> DeviceProfile {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let version = DebianVersion("\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)")
        let scheme = schemeOverride
            ?? (FileManager.default.fileExists(atPath: "/var/jb") ? .rootless : .rootful)
        return DeviceProfile(iOSVersion: version, scheme: scheme, machine: hardwareMachine())
    }

    static func hardwareMachine() -> String {
        #if canImport(Darwin)
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &buf, &size, nil, 0)
        return String(cString: buf)
        #else
        return "unknown"
        #endif
    }
}
