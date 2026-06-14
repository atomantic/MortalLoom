import XCTest
@testable import MortalLoom

/// Coverage for the `FileManager` extension in `DataStore.swift` — the
/// `modificationDate(at:)` helper and the `newerOf(cloud:local:)` selection
/// that decides which file (local sandbox vs. iCloud) `DataStore` loads from.
/// This is the load-path's conflict tiebreaker, so its edge cases (nil cloud,
/// evicted cloud placeholder, equal mtimes) are worth pinning.
final class FileManagerNewerOfTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("newerof-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
        try super.tearDownWithError()
    }

    /// Write `name` with the given modification date and return its URL.
    private func writeFile(_ name: String, modified: Date) throws -> URL {
        let url = tmpDir.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }

    // MARK: - modificationDate(at:)

    func testModificationDateReadsExistingFile() throws {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let url = try writeFile("a.json", modified: when)
        let read = FileManager.default.modificationDate(at: url)
        XCTAssertNotNil(read)
        // File systems can round sub-second precision — compare at whole seconds.
        XCTAssertEqual(read!.timeIntervalSince1970, when.timeIntervalSince1970, accuracy: 1.0)
    }

    func testModificationDateNilForMissingFile() {
        let missing = tmpDir.appendingPathComponent("does-not-exist.json")
        XCTAssertNil(FileManager.default.modificationDate(at: missing))
    }

    // MARK: - newerOf(cloud:local:)

    func testNewerOfReturnsLocalWhenCloudNil() throws {
        let local = try writeFile("local.json", modified: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(FileManager.default.newerOf(cloud: nil, local: local), local)
    }

    func testNewerOfReturnsLocalWhenCloudMissing() throws {
        let local = try writeFile("local.json", modified: Date(timeIntervalSince1970: 1000))
        let cloud = tmpDir.appendingPathComponent("evicted-cloud.json") // never written
        XCTAssertEqual(FileManager.default.newerOf(cloud: cloud, local: local), local,
                       "an evicted/absent cloud placeholder must fall back to local")
    }

    func testNewerOfPrefersNewerCloud() throws {
        let local = try writeFile("local.json", modified: Date(timeIntervalSince1970: 1000))
        let cloud = try writeFile("cloud.json", modified: Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(FileManager.default.newerOf(cloud: cloud, local: local), cloud)
    }

    func testNewerOfPrefersNewerLocal() throws {
        let local = try writeFile("local.json", modified: Date(timeIntervalSince1970: 3000))
        let cloud = try writeFile("cloud.json", modified: Date(timeIntervalSince1970: 2000))
        XCTAssertEqual(FileManager.default.newerOf(cloud: cloud, local: local), local)
    }

    func testNewerOfBreaksTieTowardCloud() throws {
        let when = Date(timeIntervalSince1970: 2000)
        let local = try writeFile("local.json", modified: when)
        let cloud = try writeFile("cloud.json", modified: when)
        // `cloudDate >= localDate` → equal mtimes resolve to cloud.
        XCTAssertEqual(FileManager.default.newerOf(cloud: cloud, local: local), cloud)
    }
}
