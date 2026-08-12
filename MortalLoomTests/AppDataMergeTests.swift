import XCTest
@testable import MortalLoom

/// Tests for `AppData.merged(with:)`, the UUID-union/date-merge sync
/// conflict resolver that replaced wholesale last-writer-wins after the
/// 2026-04-09 data-loss incident. These tests lock in the behaviour so
/// future changes don't silently regress to the previous replacement
/// semantics.
final class AppDataMergeTests: XCTestCase {

    // MARK: - Helpers

    private func drink(_ name: String, date: String = "2026-04-01", id: UUID = UUID()) -> AlcoholDrink {
        AlcoholDrink(id: id, name: name, oz: 12, abv: 5, count: 1, date: date)
    }

    private func nicotine(_ product: String, date: String = "2026-04-01", id: UUID = UUID()) -> NicotineEntry {
        NicotineEntry(id: id, product: product, mgPerUnit: 6, count: 1, date: date)
    }

    private func metric(date: String, hrv: Double? = nil, steps: Double? = nil) -> HealthMetricEntry {
        var e = HealthMetricEntry(id: UUID(), date: date)
        e.hrv = hrv
        e.steps = steps
        return e
    }

    private func appData(
        drinks: [AlcoholDrink] = [],
        nic: [NicotineEntry] = [],
        metrics: [HealthMetricEntry] = [],
        profile: HealthProfile = HealthProfile(birthDate: nil, biologicalSex: nil, lifestyle: .default)
    ) -> AppData {
        var d = AppData.empty
        d.alcoholDrinks = drinks
        d.nicotineEntries = nic
        d.healthMetrics = metrics
        d.profile = profile
        return d
    }

    // MARK: - Disjoint merge

    func testMergeDisjointDrinksUnions() {
        let a = drink("IPA")
        let b = drink("Stout")
        let local = appData(drinks: [a])
        let remote = appData(drinks: [b])

        let merged = local.merged(with: remote)

        XCTAssertEqual(merged.alcoholDrinks.count, 2)
        XCTAssertTrue(merged.alcoholDrinks.contains { $0.id == a.id })
        XCTAssertTrue(merged.alcoholDrinks.contains { $0.id == b.id })
    }

    func testMergeDisjointNicotineUnions() {
        let a = nicotine("Zyn 6mg")
        let b = nicotine("Patch")
        let local = appData(nic: [a])
        let remote = appData(nic: [b])

        let merged = local.merged(with: remote)

        XCTAssertEqual(merged.nicotineEntries.count, 2)
        XCTAssertTrue(merged.nicotineEntries.contains { $0.id == a.id })
        XCTAssertTrue(merged.nicotineEntries.contains { $0.id == b.id })
    }

    // MARK: - ID-collision resolution

    func testMergeOverlappingDrinkIDRemoteWins() {
        let sharedID = UUID()
        let localVersion = AlcoholDrink(id: sharedID, name: "IPA", oz: 12, abv: 5, count: 1, date: "2026-04-01")
        let remoteVersion = AlcoholDrink(id: sharedID, name: "IPA DOUBLE", oz: 16, abv: 8, count: 2, date: "2026-04-01")

        let local = appData(drinks: [localVersion])
        let remote = appData(drinks: [remoteVersion])

        let merged = local.merged(with: remote)

        XCTAssertEqual(merged.alcoholDrinks.count, 1, "ID collision should produce single entry, not two")
        XCTAssertEqual(merged.alcoholDrinks.first?.name, "IPA DOUBLE", "remote should win on ID collision")
        XCTAssertEqual(merged.alcoholDrinks.first?.oz, 16)
        XCTAssertEqual(merged.alcoholDrinks.first?.count, 2)
    }

    // MARK: - Empty / full edge cases

    func testMergeEmptyLocalWithFullRemoteReturnsRemote() {
        let d1 = drink("IPA")
        let d2 = drink("Stout")
        let local = appData()
        let remote = appData(drinks: [d1, d2])

        let merged = local.merged(with: remote)

        XCTAssertEqual(merged.alcoholDrinks.count, 2)
    }

    func testMergeFullLocalWithEmptyRemotePreservesLocal() {
        let d1 = drink("IPA")
        let d2 = drink("Stout")
        let local = appData(drinks: [d1, d2])
        let remote = appData()

        let merged = local.merged(with: remote)

        XCTAssertEqual(merged.alcoholDrinks.count, 2, "empty remote should not erase local entries")
    }

    // MARK: - Anti-clobber regression (the incident case)

    func testMergePreventsStaleRemoteFromErasingFreshLocal() {
        // Simulates: Mac has the freshly-restored real data (many entries);
        // iPhone pushes a stale file with only a subset. Wholesale replace
        // would lose the entries that only existed on the Mac. Merge must
        // preserve all of them.
        let freshLocal = (0..<10).map { drink("drink \($0)", id: UUID()) }
        let staleRemote = [freshLocal[0], freshLocal[1]] // iPhone only has 2

        let local = appData(drinks: freshLocal)
        let remote = appData(drinks: staleRemote)

        let merged = local.merged(with: remote)

        XCTAssertEqual(merged.alcoholDrinks.count, 10, "merge must not lose local entries that are missing from remote")
        for d in freshLocal {
            XCTAssertTrue(merged.alcoholDrinks.contains { $0.id == d.id }, "drink \(d.name) was lost")
        }
    }

    // MARK: - HealthMetrics per-date merge

    func testMergeHealthMetricsByDateFieldMerged() {
        // Local has HRV for 2026-04-01, remote has steps for the same date.
        // Merge should produce one row with BOTH fields populated.
        let localMetric = metric(date: "2026-04-01", hrv: 55.0, steps: nil)
        let remoteMetric = metric(date: "2026-04-01", hrv: nil, steps: 8000.0)

        let local = appData(metrics: [localMetric])
        let remote = appData(metrics: [remoteMetric])

        let merged = local.merged(with: remote)

        XCTAssertEqual(merged.healthMetrics.count, 1, "same-date rows should collapse to one")
        let row = merged.healthMetrics.first
        XCTAssertEqual(row?.hrv, 55.0, "local HRV should be preserved when remote field is nil")
        XCTAssertEqual(row?.steps, 8000.0, "remote steps should be adopted when local field is nil")
    }

    func testMergeHealthMetricsDifferentDatesKeepsBoth() {
        let d1 = metric(date: "2026-04-01", hrv: 50)
        let d2 = metric(date: "2026-04-02", hrv: 55)

        let local = appData(metrics: [d1])
        let remote = appData(metrics: [d2])

        let merged = local.merged(with: remote)

        XCTAssertEqual(merged.healthMetrics.count, 2)
    }

    // MARK: - Profile

    func testMergeProfileRemoteOverridesBirthDate() {
        let local = appData(profile: HealthProfile(birthDate: "1980-01-01", biologicalSex: .male, lifestyle: .default))
        let remote = appData(profile: HealthProfile(birthDate: "1979-07-31", biologicalSex: .male, lifestyle: .default))

        let merged = local.merged(with: remote)

        XCTAssertEqual(merged.profile.birthDate, "1979-07-31", "non-nil remote birthDate should override local")
    }

    func testMergeProfilePreservesLocalWhenRemoteNil() {
        let local = appData(profile: HealthProfile(birthDate: "1979-07-31", biologicalSex: .male, lifestyle: .default))
        let remote = appData(profile: HealthProfile(birthDate: nil, biologicalSex: nil, lifestyle: .default))

        let merged = local.merged(with: remote)

        XCTAssertEqual(merged.profile.birthDate, "1979-07-31", "nil remote should not wipe local birthDate")
        XCTAssertEqual(merged.profile.biologicalSex, .male)
    }

    // MARK: - Blood donations

    func testMergeDisjointBloodDonationsUnions() {
        var local = AppData.empty
        local.bloodDonations = [BloodDonation(donationType: .wholeBlood, volumeML: 500, date: "2026-03-01")]
        var remote = AppData.empty
        remote.bloodDonations = [BloodDonation(donationType: .plasma, volumeML: 700, date: "2026-04-01")]

        let merged = local.merged(with: remote)

        XCTAssertEqual(merged.bloodDonations.count, 2)
    }

    func testMergeOverlappingBloodDonationIDRemoteWins() {
        let id = UUID()
        var local = AppData.empty
        local.bloodDonations = [BloodDonation(id: id, donationType: .wholeBlood, volumeML: 500, date: "2026-03-01")]
        var remote = AppData.empty
        remote.bloodDonations = [BloodDonation(id: id, donationType: .wholeBlood, volumeML: 480, date: "2026-03-01", location: "Community Blood Drive")]

        let merged = local.merged(with: remote)

        XCTAssertEqual(merged.bloodDonations.count, 1)
        XCTAssertEqual(merged.bloodDonations.first?.volumeML, 480)
        XCTAssertEqual(merged.bloodDonations.first?.location, "Community Blood Drive")
    }

    // MARK: - Deletion caveat (documented limitation)

    func testMergeResurrectsDeletedEntryBecauseNoTombstones() {
        // If local deletes an entry that remote still has, merge brings it
        // back. This is the known tradeoff documented on AppData.merged.
        let shared = drink("IPA")
        let local = appData()             // deleted locally
        let remote = appData(drinks: [shared])

        let merged = local.merged(with: remote)

        XCTAssertEqual(merged.alcoholDrinks.count, 1, "resurrection is the documented behavior — add tombstones to fix")
        XCTAssertEqual(merged.alcoholDrinks.first?.id, shared.id)
    }
}
