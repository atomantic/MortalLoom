import XCTest
@testable import MortalLoom

// Free functions (not methods) so the @Sendable closures below don't capture
// the non-Sendable XCTestCase `self` — required under Swift 6 strict concurrency.
private func bodyEntry(_ i: Int) -> BodyEntry {
    BodyEntry(date: "body-\(i)", weightLbs: Double(i))
}

private func metric(_ i: Int) -> HealthMetricEntry {
    HealthMetricEntry(date: "metric-\(i)", hrv: Double(i))
}

/// Regression tests for issue #28: HealthKitSync ran `syncBodyMetrics()` and
/// `syncHealthMetrics()` concurrently, and each did a
/// `getData()` → await(HealthKit) → `save(wholeStruct)` round trip. Because
/// `save()` replaces the entire `AppData`, whichever sync finished last
/// discarded the other's mutations — on a fresh install with 90 days of
/// HealthKit data, ~half the synced output was silently dropped every launch.
///
/// The fix routes each sync's writes through `DataStore.mutate`, an atomic
/// read-modify-write that runs without a suspension point, so the actor
/// serializes whole cycles. These tests exercise that primitive under real
/// concurrency at the DataStore level (mocking the concrete
/// `HealthKitService.shared` singleton is impractical, so we test the storage
/// invariant the sync now relies on).
final class DataStoreConcurrencyTests: XCTestCase {

    /// Concurrent appends per array — high enough that a racy (non-atomic)
    /// write would reliably lose entries.
    private let iterations = 200

    override func setUp() async throws {
        try await super.setUp()
        // In-memory only: never touches the local file or iCloud container.
        // Irreversible for the process, which is fine — no other test relies on
        // DataStore persistence.
        await DataStore.shared.enableSampleDataMode()
        await DataStore.shared.setInMemory(.empty)
    }

    // MARK: - The fix: concurrent atomic mutations all survive

    /// Pre-populate bodyEntries, then concurrently append to bodyEntries (the
    /// body sync's domain) AND healthMetrics (the health-metrics sync's domain)
    /// many times. With the atomic `mutate`, every append from BOTH sides must
    /// survive — neither sync clobbers the other. Under the old
    /// getData/await/save pattern this would lose roughly half the writes.
    func testConcurrentMutationsDoNotLoseEachOthersWrites() async {
        let n = iterations
        // Seed bodyEntries to mirror the issue's scenario (existing body data
        // present before the sync runs).
        await DataStore.shared.mutate { data -> (persist: Bool, result: Void) in
            data.bodyEntries.append(bodyEntry(-1))
            return (true, ())
        }

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<n {
                // "Body sync" writers
                group.addTask {
                    await DataStore.shared.mutate { data -> (persist: Bool, result: Void) in
                        data.bodyEntries.append(bodyEntry(i))
                        return (true, ())
                    }
                }
                // "Health metrics sync" writers
                group.addTask {
                    await DataStore.shared.mutate { data -> (persist: Bool, result: Void) in
                        data.healthMetrics.append(metric(i))
                        return (true, ())
                    }
                }
            }
        }

        let final = await DataStore.shared.getData()
        XCTAssertEqual(final.bodyEntries.count, n + 1,
                       "every concurrent bodyEntry append (plus the seed) must survive")
        XCTAssertEqual(final.healthMetrics.count, n,
                       "every concurrent healthMetric append must survive — the body sync must not clobber it")
        XCTAssertTrue(final.bodyEntries.contains { $0.date == "body--1" },
                      "pre-existing body data must not be lost")
    }

    /// `persist: false` must skip the write so a no-op sync doesn't trigger a
    /// redundant save + iCloud broadcast.
    func testMutateRespectsPersistFlag() async {
        let changed: Bool = await DataStore.shared.mutate { data -> (persist: Bool, result: Bool) in
            data.bodyEntries.append(bodyEntry(0)) // mutate the copy…
            return (false, false)                  // …but ask NOT to persist
        }
        XCTAssertFalse(changed)
        let final = await DataStore.shared.getData()
        XCTAssertTrue(final.bodyEntries.isEmpty,
                      "a mutate that returns persist:false must not commit its changes")
    }

    /// `mutate` returns the closure's `result` to the caller — HealthKitSync
    /// uses this to decide which change notifications to post.
    func testMutateReturnsResultToCaller() async {
        let returned: Int = await DataStore.shared.mutate { data -> (persist: Bool, result: Int) in
            data.bodyEntries.append(bodyEntry(7))
            return (true, 42)
        }
        XCTAssertEqual(returned, 42)
        let final = await DataStore.shared.getData()
        XCTAssertEqual(final.bodyEntries.count, 1, "a persist:true mutate must commit its changes")
    }
}
