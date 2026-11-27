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

    func testReadablePartialDownloadCannotBeSavedAndRetryUsesCurrentCloud() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let local = dir.appendingPathComponent("local.json")
        let cloud = dir.appendingPathComponent("cloud.json")
        let isCurrent = dir.appendingPathComponent("current")
        var partial = AppData.empty
        partial.healthMetrics = [HealthMetricEntry(date: "2026-11-25", steps: 100)]
        XCTAssertTrue(partial.hasUserData, "HealthKit alone made the broken snapshot look populated")
        let old = try JSONEncoder().encode(partial)
        try old.write(to: local)
        try old.write(to: cloud)
        let store = DataStore(fixtureURLs: (local, cloud), fixtureCloudStatus: {
            FileManager.default.fileExists(atPath: isCurrent.path) ? .current : .downloaded
        })

        let saved: Bool? = await store.mutate { data in
            data.healthMetrics.append(HealthMetricEntry(date: "2026-11-26", steps: 200))
            return (true, true)
        }
        XCTAssertNil(saved, "The stale download must not report a successful HealthKit write")
        XCTAssertEqual(try Data(contentsOf: local), old)
        XCTAssertEqual(try Data(contentsOf: cloud), old)

        var full = existingData()
        full.healthMetrics = partial.healthMetrics
        try JSONEncoder().encode(full).write(to: cloud, options: .atomic)
        try Data().write(to: isCurrent)
        guard case .ready(let restored) = await store.ensureLoaded(retry: true) else {
            return XCTFail("Full data should load once the download is current")
        }
        XCTAssertEqual(restored.goals.map(\.id), full.goals.map(\.id))
        await store.upsertHealthMetric(HealthMetricEntry(date: "2026-11-26", steps: 200))
        let persisted = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: cloud))
        XCTAssertEqual(persisted.goals.map(\.id), full.goals.map(\.id))
        XCTAssertEqual(persisted.healthMetrics.count, 2)
    }

    func testHealthKitReappliesOnFullerCloudRevisionWithIdenticalTimestamp() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let local = dir.appendingPathComponent("local.json")
        let cloud = dir.appendingPathComponent("cloud.json")
        var partial = AppData.empty
        partial.healthMetrics = [HealthMetricEntry(date: "2026-11-25", steps: 10)]
        let old = try JSONEncoder().encode(partial)
        try old.write(to: local)
        try old.write(to: cloud)
        let stamp = Date(timeIntervalSince1970: 200)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: cloud.path)
        let store = DataStore(fixtureURLs: (local, cloud))
        guard case .ready(let current) = await store.ensureLoaded() else { return XCTFail("Expected readable store") }
        XCTAssertTrue(current.goals.isEmpty)

        var full = existingData()
        full.healthMetrics = partial.healthMetrics
        try JSONEncoder().encode(full).write(to: cloud, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: cloud.path)
        let savedGoalCount: Int? = await store.mutate { data in
            data.healthMetrics.append(HealthMetricEntry(date: "2026-11-26", steps: 99))
            return (true, data.goals.count)
        }
        XCTAssertEqual(savedGoalCount, 1, "The mutation must run on the reconciled revision")
        for url in [local, cloud] {
            let result = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: url))
            XCTAssertEqual(result.goals.map(\.id), full.goals.map(\.id))
            XCTAssertEqual(result.healthMetrics.map(\.date).sorted(), ["2026-11-25", "2026-11-26"])
        }
    }

    func testConflictAppearingAfterLoadBlocksBothWrites() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let local = dir.appendingPathComponent("local.json")
        let cloud = dir.appendingPathComponent("cloud.json")
        let conflict = dir.appendingPathComponent("conflict")
        let old = try JSONEncoder().encode(existingData())
        try old.write(to: local)
        try old.write(to: cloud)
        let store = DataStore(fixtureURLs: (local, cloud), fixtureCloudStatus: {
            FileManager.default.fileExists(atPath: conflict.path) ? .conflicted : .current
        })
        guard case .ready = await store.ensureLoaded() else { return XCTFail("Expected readable store") }

        try Data().write(to: conflict)
        let saved: Bool? = await store.mutate { data in
            data.goals.removeAll()
            return (true, true)
        }
        XCTAssertNil(saved)
        XCTAssertEqual(try Data(contentsOf: local), old)
        XCTAssertEqual(try Data(contentsOf: cloud), old)
        guard case .needsRecovery = await store.ensureLoaded() else { return XCTFail("Conflict must surface") }
    }

    func testFreshAndLocalOnlyStoresRemainWritable() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let goal = Goal(title: "New store")
        for hasCloud in [false, true] {
            let local = dir.appendingPathComponent("local-\(hasCloud).json")
            let cloud = hasCloud ? dir.appendingPathComponent("cloud.json") : nil
            let store = DataStore(fixtureURLs: (local, cloud))
            guard case .ready(let data) = await store.ensureLoaded() else { return XCTFail("Fresh store blocked") }
            XCTAssertFalse(data.hasUserData)
            await store.addGoal(goal)
            let localData = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: local))
            XCTAssertEqual(localData.goals.map(\.id), [goal.id])
            if let cloud { XCTAssertEqual(try Data(contentsOf: cloud), try Data(contentsOf: local)) }
        }
    }

    func testImportAndResetAreIntentionalReplacementsWithCloudBackup() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let local = dir.appendingPathComponent("local.json")
        let cloud = dir.appendingPathComponent("cloud.json")
        let old = try JSONEncoder().encode(existingData())
        try old.write(to: cloud)
        let store = DataStore(fixtureURLs: (local, cloud))
        guard case .ready = await store.ensureLoaded() else { return XCTFail("Expected readable store") }

        var imported = AppData.empty
        imported.goals = [Goal(title: "Imported goal")]
        let importedOK = await store.importData(from: try JSONEncoder().encode(imported))
        XCTAssertTrue(importedOK)
        let installed = try Data(contentsOf: cloud)
        XCTAssertEqual(try JSONDecoder().decode(AppData.self, from: installed).goals.map(\.id), imported.goals.map(\.id))
        let resetOK = await store.resetAllData()
        XCTAssertTrue(resetOK)
        XCTAssertFalse(try JSONDecoder().decode(AppData.self, from: Data(contentsOf: cloud)).hasUserData)
        let backups = await store.listBackups()
        let snapshots = try backups.map { try Data(contentsOf: $0) }
        XCTAssertTrue(snapshots.contains(old), "Import must preserve the old cloud bytes even without a local mirror")
        XCTAssertTrue(snapshots.contains(installed), "Reset must preserve the imported bytes")
    }
}
