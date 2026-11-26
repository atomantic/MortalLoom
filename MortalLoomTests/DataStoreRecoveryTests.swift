import XCTest
@testable import MortalLoom

final class DataStoreRecoveryTests: XCTestCase {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func existingData() -> AppData {
        var value = AppData.empty
        value.goals = [Goal(title: "Keep my history")]
        return value
    }

    private func malformedGoalFile(_ value: AppData) throws -> Data {
        let encoded = try JSONEncoder().encode(value)
        var doc = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var goals = try XCTUnwrap(doc["goals"] as? [[String: Any]])
        goals[0]["id"] = "not-a-uuid"
        doc["goals"] = goals
        return try JSONSerialization.data(withJSONObject: doc)
    }

    func testMalformedExistingStoreNeverStartsFreshOrAcceptsWrites() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let local = dir.appendingPathComponent("local.json")
        let cloud = dir.appendingPathComponent("cloud.json")
        let corrupt = try malformedGoalFile(existingData())
        try corrupt.write(to: cloud)
        let store = DataStore(fixtureURLs: (local, cloud))

        // Other code may ask for data before the startup view does.
        _ = await store.getData()
        guard case .needsRecovery = await store.ensureLoaded() else {
            return XCTFail("An existing unreadable file must not start onboarding")
        }
        await store.upsertHealthMetric(HealthMetricEntry(date: "2026-11-26", steps: 80))
        let resetSaved = await store.save(.empty)
        XCTAssertFalse(resetSaved)
        XCTAssertEqual(try Data(contentsOf: cloud), corrupt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.path))

        try JSONEncoder().encode(existingData()).write(to: cloud, options: .atomic)
        guard case .ready(let restored) = await store.ensureLoaded(retry: true) else {
            return XCTFail("Retry should succeed after the shared file is repaired")
        }
        XCTAssertEqual(restored.goals.first?.title, "Keep my history")
        XCTAssertTrue(restored.healthMetrics.isEmpty)
    }

    func testExplicitRecoveryValidatesBackupAndPreservesBothOriginals() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let local = dir.appendingPathComponent("local.json")
        let cloud = dir.appendingPathComponent("cloud.json")
        let good = try JSONEncoder().encode(existingData())
        let corrupt = try malformedGoalFile(existingData())
        try good.write(to: local)
        try corrupt.write(to: cloud)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)],
                                              ofItemAtPath: local.path)
        let store = DataStore(fixtureURLs: (local, cloud))
        guard case .needsRecovery = await store.ensureLoaded() else { return XCTFail("Expected recovery screen") }
        let invalidRestore = await store.recoverFromBackup(corrupt)
        XCTAssertFalse(invalidRestore)
        XCTAssertEqual(try Data(contentsOf: local), good)
        XCTAssertEqual(try Data(contentsOf: cloud), corrupt)

        let successfulRestore = await store.recoverFromBackup(good)
        XCTAssertTrue(successfulRestore)
        let folder = try XCTUnwrap(FileManager.default.contentsOfDirectory(
            at: dir.appendingPathComponent("Recovery Backups"), includingPropertiesForKeys: nil
        ).first)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("Local.json")), good)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("iCloud.json")), corrupt)
        XCTAssertEqual(try Data(contentsOf: cloud), good)
        guard case .ready(let data) = await store.ensureLoaded() else { return XCTFail("Expected restored data") }
        XCTAssertEqual(data.goals.first?.title, "Keep my history")
    }

    func testFreshStoreCanStartWithoutExistingFiles() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = DataStore(fixtureURLs: (dir.appendingPathComponent("local.json"),
                                           dir.appendingPathComponent("cloud.json")))
        guard case .ready(let empty) = await store.ensureLoaded() else {
            return XCTFail("Missing files on a fresh install are not a recovery error")
        }
        XCTAssertFalse(empty.hasUserData)
    }

    func testChangedMalformedCloudCannotBeOverwrittenBeforeWatcherRuns() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let local = dir.appendingPathComponent("local.json")
        let cloud = dir.appendingPathComponent("cloud.json")
        let good = try JSONEncoder().encode(existingData())
        try good.write(to: local)
        try good.write(to: cloud)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)],
                                              ofItemAtPath: local.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)],
                                              ofItemAtPath: cloud.path)
        let store = DataStore(fixtureURLs: (local, cloud))
        guard case .ready = await store.ensureLoaded() else { return XCTFail("Valid data should load") }

        let corrupt = try malformedGoalFile(existingData())
        try corrupt.write(to: cloud, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 300)],
                                              ofItemAtPath: cloud.path)
        await store.upsertHealthMetric(HealthMetricEntry(date: "2026-11-26", steps: 80))
        guard case .needsRecovery = await store.ensureLoaded() else { return XCTFail("Expected write barrier") }
        XCTAssertEqual(try Data(contentsOf: cloud), corrupt)
        XCTAssertEqual(try Data(contentsOf: local), good)
        let inMemory = await store.getData()
        XCTAssertEqual(inMemory.goals.count, 1)
        XCTAssertTrue(inMemory.healthMetrics.isEmpty)
    }
}
