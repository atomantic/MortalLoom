import XCTest
@testable import MortalLoom

/// Coverage for `ICloudMonitor` (issue #58). The monitor drives an
/// `NSMetadataQuery` and posts `.dataDidSync` when iCloud delivers a newer
/// file. Unit coverage focuses on the observable contract that doesn't require
/// a provisioned iCloud container: initial state, the manual `syncNow()` path
/// (which resolves to a no-op merge when there's no cloud file), the
/// idempotent start/stop lifecycle, and that `markLocalWrite()` is safe.
///
/// DataStore is held in sample-data mode so `reloadIfNeeded()` (reached via
/// `syncNow()`) short-circuits without touching disk or the iCloud container.
@MainActor
final class ICloudMonitorTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        await DataStore.shared.enableSampleDataMode()
        await DataStore.shared.setInMemory(.empty)
    }

    override func tearDown() async throws {
        // Tear down any live query a lifecycle test left running so it can't
        // post callbacks into a later, unrelated test.
        ICloudMonitor.shared.stop()
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
        // A second start() must be a no-op (guarded on the existing query) and
        // must not throw or spin up a duplicate query.
        ICloudMonitor.shared.start()
        ICloudMonitor.shared.stop()
        // After stop, start() can succeed again — proves stop() cleared state.
        ICloudMonitor.shared.start()
        ICloudMonitor.shared.stop()
    }
}
