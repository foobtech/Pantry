import XCTest
@testable import PantryCore

final class PantryCoreTests: XCTestCase {
    func testVersionOrdering() {
        XCTAssertTrue(DebianVersion("1.0") < DebianVersion("1.0.1"))
        XCTAssertTrue(DebianVersion("1.0~beta") < DebianVersion("1.0"))
        XCTAssertTrue(DebianVersion("1.9") < DebianVersion("1.10"))
        XCTAssertTrue(DebianVersion("1:0.1") > DebianVersion("9.9"))
        XCTAssertTrue(DebianVersion("1.0-2") > DebianVersion("1.0-1"))
        XCTAssertEqual(DebianVersion("1.0"), DebianVersion("1.00"))
    }

    func testParseAndCompat() {
        let text = """
        Package: com.example.tweak
        Name: Example
        Version: 1.2
        Architecture: iphoneos-arm64
        Depends: firmware (>= 14.0), firmware (<< 17.0), mobilesubstrate
        Description: Short line
         Long line one
         .
         Long line two

        Package: com.example.old
        Version: 0.1
        Architecture: iphoneos-arm
        Depends: firmware (<< 12.0)
        Description: Old
        """
        let pkgs = Package.parseIndex(text, repoID: "r")
        XCTAssertEqual(pkgs.count, 2)
        XCTAssertEqual(pkgs[0].shortDescription, "Short line")
        XCTAssertEqual(pkgs[0].longDescription, "Long line one\n\nLong line two")

        let dev = DeviceProfile(iOSVersion: DebianVersion("16.5"), scheme: .rootless, machine: "iPhone12,1")
        XCTAssertTrue(pkgs[0].isCompatible(with: dev))
        XCTAssertFalse(pkgs[1].isCompatible(with: dev))
    }

    func testLatestVersions() {
        let a = Package(stanza: ["package": "x", "version": "1.0"], repoID: "r")!
        let b = Package(stanza: ["package": "x", "version": "1.1"], repoID: "r")!
        XCTAssertEqual(latestVersions([a, b]).first?.version, DebianVersion("1.1"))
    }
}
