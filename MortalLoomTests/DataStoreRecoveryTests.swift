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

    func testExplicitRecoveryCanOpenWhileItsOwnVerifiedUploadIsInFlight() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let local = dir.appendingPathComponent("local.json")
        let cloud = dir.appendingPathComponent("cloud.json")
        let uploading = dir.appendingPathComponent("uploading")
        let full = existingData()
        try malformedGoalFile(full).write(to: cloud)
        let store = DataStore(fixtureURLs: (local, cloud), fixtureCloudStatus: {
            FileManager.default.fileExists(atPath: uploading.path) ? .uploading : .current
        })
        guard case .needsRecovery = await store.ensureLoaded() else { return XCTFail("Expected recovery screen") }

        let didRestore = await store.recoverFromBackup(try JSONEncoder().encode(full))
        XCTAssertTrue(didRestore)
        try Data().write(to: uploading)

        guard case .ready(let result) = await store.ensureLoaded() else {
            return XCTFail("Do not return to the recovery screen while our exact recovered bytes are uploading")
        }
        XCTAssertEqual(result.goals.map(\.id), full.goals.map(\.id))
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

    func testLegacyLocalDivergenceIsArchivedEvenWhenCloudIsNewer() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let local = dir.appendingPathComponent("local.json")
        let cloud = dir.appendingPathComponent("cloud.json")
        let draft = existingData()
        var remote = draft
        remote.goals[0].title = "A different revision"
        let original = try JSONEncoder().encode(draft)
        try original.write(to: local)
        try JSONEncoder().encode(remote).write(to: cloud)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)],
                                              ofItemAtPath: local.path)
        let store = DataStore(fixtureURLs: (local, cloud))
        guard case .ready(let data) = await store.ensureLoaded() else { return XCTFail("Expected cloud revision") }
        XCTAssertEqual(data.goals.first?.title, "A different revision")
        let copies = await store.listSyncRecoveryCopies()
        let earlier = try XCTUnwrap(copies.first { $0.label == "Earlier local copy" })
        let preserved = await store.exportSyncRecoveryCopy(earlier.id)
        XCTAssertEqual(preserved, original)
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

    func testNativeEditsKeepOpaquePortOSFieldsButDeletionRemovesTheWholeGoal() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let local = dir.appendingPathComponent("local.json")
        let cloud = dir.appendingPathComponent("cloud.json")
        var full = existingData()
        full.goals[0].milestones = [GoalMilestone(title: "Shared milestone")]
        let value = try JSONEncoder().encode(full)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: value) as? [String: Any])
        var goals = try XCTUnwrap(raw["goals"] as? [[String: Any]])
        var milestones = try XCTUnwrap(goals[0]["milestones"] as? [[String: Any]])
        milestones[0]["futureNotes"] = ["origin": "PortOS"]
        goals[0]["milestones"] = milestones
        goals[0]["timeBlockConfig"] = ["minutes": 45]
        goals[0]["id"] = full.goals[0].id.uuidString.lowercased()
        raw["goals"] = goals
        raw["unknownFutureSection"] = ["remember": true, "counter": UInt64.max]
        try JSONSerialization.data(withJSONObject: raw).write(to: cloud)
        let writer = DataStore(fixtureURLs: (local, cloud))
        guard case .ready(let initial) = await writer.ensureLoaded() else { return XCTFail("Expected valid snapshot") }
        var changed = initial.goals[0]
        changed.title = "Edited from the native app"
        changed.milestones[0].completed = true
        await writer.updateGoal(changed, replacing: initial.goals[0])
        let edited = try Data(contentsOf: cloud)
        let doc = try XCTUnwrap(JSONSerialization.jsonObject(with: edited) as? [String: Any])
        let editedGoal = try XCTUnwrap((doc["goals"] as? [[String: Any]])?.first)
        XCTAssertEqual(editedGoal["timeBlockConfig"] as? [String: Int], ["minutes": 45])
        XCTAssertEqual(editedGoal["id"] as? String, full.goals[0].id.uuidString.lowercased())
        let milestone = try XCTUnwrap((editedGoal["milestones"] as? [[String: Any]])?.first)
        XCTAssertEqual(milestone["futureNotes"] as? [String: String], ["origin": "PortOS"])
        let future = try XCTUnwrap(doc["unknownFutureSection"] as? [String: Any])
        XCTAssertEqual(future["remember"] as? Bool, true)
        XCTAssertEqual((future["counter"] as? NSNumber)?.uint64Value, UInt64.max)
        await writer.removeGoal(id: full.goals[0].id)
        let removed = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: cloud))
        XCTAssertTrue(removed.goals.isEmpty)
        let reopened = DataStore(fixtureURLs: (local, cloud))
        guard case .ready(let afterReopen) = await reopened.ensureLoaded() else { return XCTFail("Legitimate delete must reopen") }
        XCTAssertTrue(afterReopen.goals.isEmpty)
    }

    func testPartialCurrentCloudAfterRestartCannotReplaceLastGood() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let local = dir.appendingPathComponent("local.json")
        let cloud = dir.appendingPathComponent("cloud.json")
        var full = existingData()
        full.goals += [Goal(title: "Second"), Goal(title: "Third")]
        full.healthMetrics = [HealthMetricEntry(date: "2026-11-26", steps: 80)]
        let good = try JSONEncoder().encode(full)
        try good.write(to: cloud)
        let first = DataStore(fixtureURLs: (local, cloud))
        guard case .ready = await first.ensureLoaded() else { return XCTFail("Expected valid snapshot") }

        var partial = AppData.empty
        partial.healthMetrics = full.healthMetrics
        let reduced = try JSONEncoder().encode(partial)
        try reduced.write(to: cloud)
        let restarted = DataStore(fixtureURLs: (local, cloud))
        guard case .needsRecovery = await restarted.ensureLoaded() else { return XCTFail("Unexpected shrink must block") }
        let reason = await restarted.currentRecoveryReason()
        XCTAssertEqual(reason, .unexpectedReduction)
        let attempted = await restarted.save(partial)
        XCTAssertFalse(attempted)
        XCTAssertEqual(try Data(contentsOf: local), good)
        XCTAssertEqual(try Data(contentsOf: cloud), reduced)
        let restored = await restarted.recoverLastKnownGood()
        XCTAssertTrue(restored)
        XCTAssertEqual(try Data(contentsOf: cloud), good)
    }

    func testConfirmedResetHasExactPreimageAndDoesNotReviveOldRows() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = dir.appendingPathComponent("cloud.json")
        let leftDir = dir.appendingPathComponent("left")
        let rightDir = dir.appendingPathComponent("right")
        for folder in [leftDir, rightDir] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        }
        let left = leftDir.appendingPathComponent("local.json")
        let right = rightDir.appendingPathComponent("local.json")
        var full = existingData()
        full.goals += [Goal(title: "Second"), Goal(title: "Third")]
        let good = try JSONEncoder().encode(full)
        try good.write(to: cloud)
        let one = DataStore(fixtureURLs: (left, cloud))
        let two = DataStore(fixtureURLs: (right, cloud))
        guard case .ready = await one.ensureLoaded(), case .ready = await two.ensureLoaded() else {
            return XCTFail("Both clients should have the same preimage")
        }
        let reset = await one.resetAllData()
        XCTAssertTrue(reset)
        let bytes = try Data(contentsOf: cloud)
        XCTAssertTrue(SharedStoreDocument.isExplicitReplacement(bytes, of: good))
        XCTAssertFalse(SharedStoreDocument.isExplicitReplacement(bytes, of: Data()))
        let reopened = DataStore(fixtureURLs: (right, cloud))
        guard case .ready(let afterReset) = await reopened.ensureLoaded() else { return XCTFail("Confirmed reset should converge") }
        XCTAssertFalse(afterReset.hasUserData)
        XCTAssertEqual(try Data(contentsOf: right), bytes)
    }

    func testGoalEditsMergeAcrossWritersAndDoNotResurrectDeletes() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let local = dir.appendingPathComponent("local.json")
        let cloud = dir.appendingPathComponent("cloud.json")
        let initial = Goal(title: "Original")
        let toDelete = Goal(title: "Delete from PortOS")
        var full = AppData.empty
        full.goals = [initial, toDelete]
        try JSONEncoder().encode(full).write(to: cloud)
        let native = DataStore(fixtureURLs: (local, cloud))
        guard case .ready = await native.ensureLoaded() else { return XCTFail("Expected readable store") }

        var portOS = full
        portOS.goals[0].title = "Edited from PortOS"
        portOS.goals.removeLast()
        let added = Goal(title: "Added from PortOS")
        portOS.goals.append(added)
        try JSONEncoder().encode(portOS).write(to: cloud, options: .atomic)

        var nativeDraft = initial
        nativeDraft.notes = "Edited from the native form"
        await native.updateGoal(nativeDraft, replacing: initial)
        let result = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: cloud))
        let merged = try XCTUnwrap(result.goals.first { $0.id == initial.id })
        XCTAssertEqual(merged.title, "Edited from PortOS")
        XCTAssertEqual(merged.notes, "Edited from the native form")
        XCTAssertEqual(Set(result.goals.map(\.id)), [initial.id, added.id])

        // If a form remains open while the watcher advances the actor
        // baseline, the form's own baseline still protects concurrent edits.
        var newest = result
        newest.goals[0].checkIns = [GoalCheckIn(progressPct: 75, note: "A newer check-in")]
        try JSONEncoder().encode(newest).write(to: cloud, options: .atomic)
        _ = await native.reloadIfNeeded()
        var staleForm = merged
        staleForm.notes = "A later note"
        await native.updateGoal(staleForm, replacing: merged)
        let later = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: cloud))
        let laterGoal = try XCTUnwrap(later.goals.first { $0.id == initial.id })
        XCTAssertEqual(laterGoal.checkIns.first?.note, "A newer check-in")
        XCTAssertEqual(laterGoal.notes, "A later note")
    }

    func testCompetingSameFieldEditsKeepBothCopiesAndRequireRecovery() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let local = dir.appendingPathComponent("local.json")
        let cloud = dir.appendingPathComponent("cloud.json")
        let full = existingData()
        let base = try JSONEncoder().encode(full)
        try base.write(to: cloud)
        let native = DataStore(fixtureURLs: (local, cloud))
        guard case .ready = await native.ensureLoaded() else { return XCTFail("Expected readable store") }
        var portOS = full
        portOS.goals[0].title = "PortOS title"
        let remote = try JSONEncoder().encode(portOS)
        try remote.write(to: cloud)
        var draft = full
        draft.goals[0].title = "Native title"
        let saved = await native.save(draft)
        XCTAssertFalse(saved)
        XCTAssertEqual(try Data(contentsOf: cloud), remote)
        XCTAssertEqual(try Data(contentsOf: local), base)
        let reason = await native.currentRecoveryReason()
        XCTAssertEqual(reason, .divergentEdits)
        let reviewed = await native.canAcceptCurrentCloudForRecovery()
        XCTAssertTrue(reviewed)
        let accepted = await native.acceptCurrentCloudForRecovery()
        XCTAssertTrue(accepted)
        let ready = await native.getData()
        XCTAssertEqual(ready.goals.first?.title, "PortOS title")
        let history = dir.appendingPathComponent("MortalLoomSyncHistory")
        let scope = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: history, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent != "LocalCopyOwner" })
        let pending = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: scope, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix("ConflictingEdit-") })
        let preserved = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: pending))
        XCTAssertEqual(preserved.goals.first?.title, "Native title")
        let recoveryCopies = await native.listSyncRecoveryCopies()
        XCTAssertTrue(recoveryCopies.contains { $0.id == pending && $0.label == "Conflicting local edit" })
        let exported = await native.exportSyncRecoveryCopy(pending)
        XCTAssertEqual(exported, try Data(contentsOf: pending))
        let cannotExportOthers = await native.exportSyncRecoveryCopy(cloud)
        XCTAssertNil(cannotExportOthers)
    }

}
