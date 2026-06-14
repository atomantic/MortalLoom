import XCTest
@testable import MortalLoom

/// Coverage for `ICloudMonitor` (issue #58). The monitor drives an
/// `NSMetadataQuery` and posts `.dataDidSync` when iCloud delivers a newer
/// file. Unit coverage focuses on the observable contract that doesn't require
/// a provisioned iCloud container: initial state, the manual `syncNow()` path
/// (which resolves to a no-op merge when there's no cloud file), the
/// idempotent start/stop lifecycle, and that `markLocalWrite()` is safe.
///
/// DataStore is held in sample-data mode, which `reloadIfNeeded()` (reached via
/// `syncNow()`, and via the metadata query's gather callback in the lifecycle
/// test) short-circuits on — so nothing here reads from or writes to disk or the
/// iCloud container even on an iCloud-provisioned machine.
@MainActor
final class ICloudMonitorTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        await DataStore.shared.enableSampleDataMode()
        await DataStore.shared.setInMemory(.empty)
    }

    override func tearDown() async throws {
        // Tear down any live query a lifecycle test left running so it can't
        // post callbacks into a later, unrelated test, and reset the shared
        // store so no merge could leak into another suite.
        ICloudMonitor.shared.stop()
        await DataStore.shared.setInMemory(.empty)
        try await super.tearDown()
    }

    func testNotSyncingInitially() {
        XCTAssertFalse(ICloudMonitor.shared.isSyncing)
    }

    func testMarkLocalWriteIsSafe() {
        // No observable return value — this just must not crash, and must leave
        // the monitor idle.
        ICloudMonitor.shared.markLocalWrite()
        XCTAssertFalse(ICloudMonitor.shared.isSyncing)
    }

    func testSyncNowResetsSyncingFlag() async {
        await ICloudMonitor.shared.syncNow()
        XCTAssertFalse(ICloudMonitor.shared.isSyncing,
                       "syncNow must clear isSyncing once the reload attempt finishes")
    }

    func testStartIsIdempotentAndStopResets() {
        ICloudMonitor.shared.start()
        XCTAssertTrue(ICloudMonitor.shared.isMonitoring, "start() must arm the monitor")

        // A second start() must be a guarded no-op — still monitoring, no crash.
        ICloudMonitor.shared.start()
        XCTAssertTrue(ICloudMonitor.shared.isMonitoring, "a redundant start() must leave the monitor armed")

        ICloudMonitor.shared.stop()
        XCTAssertFalse(ICloudMonitor.shared.isMonitoring, "stop() must disarm the monitor")

        // After stop, start() re-arms — proves stop() cleared the query handle.
        ICloudMonitor.shared.start()
        XCTAssertTrue(ICloudMonitor.shared.isMonitoring, "start() after stop() must re-arm the monitor")

        ICloudMonitor.shared.stop()
        XCTAssertFalse(ICloudMonitor.shared.isMonitoring)
    }
}
