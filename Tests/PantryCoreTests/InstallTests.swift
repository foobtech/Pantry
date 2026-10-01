import XCTest
@testable import PantryCore

final class InstallTests: XCTestCase {
    func testSHA256() {
        XCTAssertEqual(SHA256.hash(Data()),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256.hash(Data("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        // Crosses a block boundary (56 bytes forces an extra padding block).
        XCTAssertEqual(SHA256.hash(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    func testRepoCodable() throws {
        let repo = Repo(url: URL(string: "https://apt.example.com")!, suite: "1900", components: ["main"])
        let data = try JSONEncoder().encode([repo])
        let back = try JSONDecoder().decode([Repo].self, from: data)
        XCTAssertEqual(back, [repo])
        XCTAssertFalse(back[0].isFlat)
        XCTAssertEqual(back[0].url.absoluteString, "https://apt.example.com/")
    }

    func testInstalledDatabase() {
        let status = """
        Package: libfoo
        Status: install ok installed
        Version: 2.1
        Provides: libfoo-abi (= 2)

        Package: gone
        Status: deinstall ok config-files
        Version: 1.0
        """
        let db = InstalledDatabase(statusText: status)
        XCTAssertEqual(db.version(of: "libfoo"), DebianVersion("2.1"))
        XCTAssertNil(db.version(of: "gone"))
        XCTAssertTrue(db.satisfies(Dependency.parseList("libfoo-abi")[0][0]))
    }

    func testResolverOrdersDependenciesFirst() {
        let device = DeviceProfile(iOSVersion: DebianVersion("16.6"), scheme: .rootless, machine: "iPad7,5")
        func pkg(_ name: String, _ version: String, depends: String = "") -> Package {
            var s: Stanza = ["package": name, "version": version, "architecture": "iphoneos-arm64"]
            if !depends.isEmpty { s["depends"] = depends }
            return Package(stanza: s, repoID: "r")!
        }
        let app = pkg("app", "1.0", depends: "libb (>= 1.0), libc | libd, firmware (>= 14.0)")
        let libb = pkg("libb", "1.5", depends: "liba")
        let liba = pkg("liba", "1.0")
        let libd = pkg("libd", "1.0")
        let index = PackageIndex(packages: [app, libb, liba, libd], device: device)

        let plan = Resolver.plan(installing: app, index: index, installed: InstalledDatabase())
        XCTAssertTrue(plan.isInstallable)
        XCTAssertEqual(plan.toInstall.map { $0.identifier }, ["liba", "libb", "libd", "app"])

        let missing = pkg("needs-missing", "1.0", depends: "nothing-here")
        let bad = Resolver.plan(installing: missing, index: index, installed: InstalledDatabase())
        XCTAssertFalse(bad.isInstallable)
    }
}
