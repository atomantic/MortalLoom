import XCTest
@testable import MortalLoom

/// CRUD + upsert coverage for the `DataStore` actor (issue #58). The existing
/// `DataStoreConcurrencyTests` only exercises the atomic `mutate` primitive;
/// these lock in the dozens of typed accessors (add/remove/update across every
/// domain, the per-date health-metric upsert merge, genome action-state
/// composition, and the visit-note auto-discuss flow) that the UI relies on.
///
/// Every test runs the shared store in sample-data mode + a fresh `.empty`
/// snapshot, so nothing here touches the local file or the iCloud container —
/// the same isolation pattern `DataStoreConcurrencyTests` uses.
///
/// `getData()` is actor-isolated and `async`, so results are bound to a local
/// before asserting — an `await` can't live inside an `XCTAssert` autoclosure.
final class DataStoreCRUDTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        await DataStore.shared.enableSampleDataMode()
        await DataStore.shared.setInMemory(.empty)
    }

    // MARK: - Alcohol

    func testAlcoholAddRemoveUpdate() async {
        let drink = AlcoholDrink(name: "IPA", oz: 12, abv: 6, count: 1, date: "2026-01-01")
        await DataStore.shared.addAlcoholDrink(drink)
        var data = await DataStore.shared.getData()
        XCTAssertEqual(data.alcoholDrinks.count, 1)

        var edited = drink
        edited.name = "Double IPA"
        edited.count = 2
        await DataStore.shared.updateAlcoholDrink(edited)
        data = await DataStore.shared.getData()
        XCTAssertEqual(data.alcoholDrinks.first?.name, "Double IPA")
        XCTAssertEqual(data.alcoholDrinks.first?.count, 2)

        await DataStore.shared.removeAlcoholDrink(id: drink.id)
        data = await DataStore.shared.getData()
        XCTAssertTrue(data.alcoholDrinks.isEmpty)
    }

    func testUpdateUnknownAlcoholDrinkIsNoOp() async {
        await DataStore.shared.addAlcoholDrink(AlcoholDrink(name: "IPA", oz: 12, abv: 6, date: "2026-01-01"))
        // An edit targeting an id that isn't present must not append a phantom row.
        await DataStore.shared.updateAlcoholDrink(AlcoholDrink(name: "Ghost", oz: 1, abv: 1, date: "2026-01-02"))
        let data = await DataStore.shared.getData()
        XCTAssertEqual(data.alcoholDrinks.count, 1)
        XCTAssertEqual(data.alcoholDrinks.first?.name, "IPA")
    }

    func testSetAlcoholPresets() async {
        await DataStore.shared.setAlcoholPresets(AlcoholPreset.defaults)
        let data = await DataStore.shared.getData()
        XCTAssertEqual(data.alcoholPresets.count, AlcoholPreset.defaults.count)
    }

    // MARK: - Nicotine

    func testNicotineAddRemoveUpdate() async {
        let entry = NicotineEntry(product: "Zyn 6mg", mgPerUnit: 6, count: 1, date: "2026-01-01")
        await DataStore.shared.addNicotineEntry(entry)
        var data = await DataStore.shared.getData()
        XCTAssertEqual(data.nicotineEntries.count, 1)

        var edited = entry
        edited.count = 3
        await DataStore.shared.updateNicotineEntry(edited)
        data = await DataStore.shared.getData()
        XCTAssertEqual(data.nicotineEntries.first?.count, 3)

        await DataStore.shared.removeNicotineEntry(id: entry.id)
        data = await DataStore.shared.getData()
        XCTAssertTrue(data.nicotineEntries.isEmpty)
    }

    func testSetNicotinePresets() async {
        await DataStore.shared.setNicotinePresets(NicotinePreset.defaults)
        let data = await DataStore.shared.getData()
        XCTAssertEqual(data.nicotinePresets.count, NicotinePreset.defaults.count)
    }

    // MARK: - Sauna

    func testSaunaAddRemoveUpdate() async {
        let session = SaunaSession(saunaType: .infrared, temperatureF: 140, durationMinutes: 25, date: "2026-01-01")
        await DataStore.shared.addSaunaSession(session)
        var data = await DataStore.shared.getData()
        XCTAssertEqual(data.saunaSessions.count, 1)

        var edited = session
        edited.durationMinutes = 30
        await DataStore.shared.updateSaunaSession(edited)
        data = await DataStore.shared.getData()
        XCTAssertEqual(data.saunaSessions.first?.durationMinutes, 30)

        await DataStore.shared.removeSaunaSession(id: session.id)
        data = await DataStore.shared.getData()
        XCTAssertTrue(data.saunaSessions.isEmpty)
    }

    func testSetSaunaPresets() async {
        await DataStore.shared.setSaunaPresets(SaunaPreset.defaults)
        let data = await DataStore.shared.getData()
        XCTAssertEqual(data.saunaPresets.count, SaunaPreset.defaults.count)
    }

    // MARK: - Blood / Eye / Body / Epigenetic

    func testBloodTestAddRemoveUpdate() async {
        let test = BloodTest(date: "2026-01-01", markers: ["ldl": 90])
        await DataStore.shared.addBloodTest(test)
        var data = await DataStore.shared.getData()
        XCTAssertEqual(data.bloodTests.count, 1)

        var edited = test
        edited.markers["hdl"] = 55
        await DataStore.shared.updateBloodTest(edited)
        data = await DataStore.shared.getData()
        XCTAssertEqual(data.bloodTests.first?.markers["hdl"], 55)

        await DataStore.shared.removeBloodTest(id: test.id)
        data = await DataStore.shared.getData()
        XCTAssertTrue(data.bloodTests.isEmpty)
    }

    func testEyeExamAddRemoveUpdate() async {
        let exam = EyeExam(date: "2026-01-01", leftSphere: -1.0, rightSphere: -1.25)
        await DataStore.shared.addEyeExam(exam)
        var data = await DataStore.shared.getData()
        XCTAssertEqual(data.eyeExams.count, 1)

        var edited = exam
        edited.leftSphere = -1.5
        await DataStore.shared.updateEyeExam(edited)
        data = await DataStore.shared.getData()
        XCTAssertEqual(data.eyeExams.first?.leftSphere, -1.5)

        await DataStore.shared.removeEyeExam(id: exam.id)
        data = await DataStore.shared.getData()
        XCTAssertTrue(data.eyeExams.isEmpty)
    }

    func testBodyEntryAddRemove() async {
        let entry = BodyEntry(date: "2026-01-01", weightLbs: 180)
        await DataStore.shared.addBodyEntry(entry)
        var data = await DataStore.shared.getData()
        XCTAssertEqual(data.bodyEntries.count, 1)

        await DataStore.shared.removeBodyEntry(id: entry.id)
        data = await DataStore.shared.getData()
        XCTAssertTrue(data.bodyEntries.isEmpty)
    }

    func testEpigeneticTestAddRemove() async {
        let test = EpigeneticTest(date: "2026-01-01", chronologicalAge: 40, biologicalAge: 36)
        await DataStore.shared.addEpigeneticTest(test)
        var data = await DataStore.shared.getData()
        XCTAssertEqual(data.epigeneticTests.count, 1)

        await DataStore.shared.removeEpigeneticTest(id: test.id)
        data = await DataStore.shared.getData()
        XCTAssertTrue(data.epigeneticTests.isEmpty)
    }

    // MARK: - Health metrics (upsert / field-merge)

    func testUpsertHealthMetricMergesFieldsForSameDate() async {
        await DataStore.shared.upsertHealthMetric(HealthMetricEntry(date: "2026-01-01", hrv: 55))
        // Second upsert for the same date carries a different field — the
        // existing row must gain `steps` while keeping `hrv`, not be replaced.
        await DataStore.shared.upsertHealthMetric(HealthMetricEntry(date: "2026-01-01", steps: 8000))

        let data = await DataStore.shared.getData()
        XCTAssertEqual(data.healthMetrics.count, 1, "same-date upsert must merge, not append")
        XCTAssertEqual(data.healthMetrics.first?.hrv, 55)
        XCTAssertEqual(data.healthMetrics.first?.steps, 8000)
    }

    func testUpsertHealthMetricAppendsDistinctDates() async {
        await DataStore.shared.upsertHealthMetric(HealthMetricEntry(date: "2026-01-01", hrv: 55))
        await DataStore.shared.upsertHealthMetric(HealthMetricEntry(date: "2026-01-02", hrv: 60))
        let data = await DataStore.shared.getData()
        XCTAssertEqual(data.healthMetrics.count, 2)
    }

    func testBulkUpsertHealthMetrics() async {
        await DataStore.shared.upsertHealthMetric(HealthMetricEntry(date: "2026-01-01", hrv: 55))
        // One new date + one merge into the existing date in a single bulk call.
        await DataStore.shared.upsertHealthMetrics([
            HealthMetricEntry(date: "2026-01-01", steps: 9000),
            HealthMetricEntry(date: "2026-01-02", hrv: 61),
        ])

        let data = await DataStore.shared.getData()
        XCTAssertEqual(data.healthMetrics.count, 2)
        let jan1 = data.healthMetrics.first { $0.date == "2026-01-01" }
        XCTAssertEqual(jan1?.hrv, 55, "existing field preserved across bulk merge")
        XCTAssertEqual(jan1?.steps, 9000, "bulk merge adds the new field")
    }

    func testBulkUpsertEmptyIsNoOp() async {
        await DataStore.shared.upsertHealthMetrics([])
        let data = await DataStore.shared.getData()
        XCTAssertTrue(data.healthMetrics.isEmpty)
    }

    // MARK: - Goals

    func testGoalAddUpdateRemove() async {
        let goal = Goal(title: "Run a 10k")
        await DataStore.shared.addGoal(goal)
        var data = await DataStore.shared.getData()
        XCTAssertEqual(data.goals.count, 1)

        var edited = goal
        edited.status = .completed
        await DataStore.shared.updateGoal(edited)
        data = await DataStore.shared.getData()
        XCTAssertEqual(data.goals.first?.status, .completed)

        await DataStore.shared.removeGoal(id: goal.id)
        data = await DataStore.shared.getData()
        XCTAssertTrue(data.goals.isEmpty)
    }

    // MARK: - Habits

    func testHabitAddUpdateRemove() async {
        let habit = Habit(name: "Meditate")
        await DataStore.shared.addHabit(habit)
        var data = await DataStore.shared.getData()
        XCTAssertEqual(data.habits.count, 1)

        var edited = habit
        edited.name = "Meditate 10m"
        await DataStore.shared.updateHabit(edited)
        data = await DataStore.shared.getData()
        XCTAssertEqual(data.habits.first?.name, "Meditate 10m")

        await DataStore.shared.removeHabit(id: habit.id)
        data = await DataStore.shared.getData()
        XCTAssertTrue(data.habits.isEmpty)
    }

    func testLogAndRemoveHabitCompletion() async {
        let habit = Habit(name: "Meditate")
        await DataStore.shared.addHabit(habit)

        let completion = HabitCompletion(date: "2026-01-01")
        await DataStore.shared.logHabitCompletion(habitId: habit.id, completion: completion)
        var data = await DataStore.shared.getData()
        XCTAssertEqual(data.habits.first?.completions.count, 1)

        await DataStore.shared.removeHabitCompletion(habitId: habit.id, completionId: completion.id)
        data = await DataStore.shared.getData()
        XCTAssertEqual(data.habits.first?.completions.count, 0)
    }

    func testLogHabitCompletionForUnknownHabitIsNoOp() async {
        // No habit exists — logging must be a safe no-op, not a crash or a
        // phantom habit.
        await DataStore.shared.logHabitCompletion(habitId: UUID(), completion: HabitCompletion(date: "2026-01-01"))
        let data = await DataStore.shared.getData()
        XCTAssertTrue(data.habits.isEmpty)
    }

    // MARK: - Profile

    func testUpdateProfileAndCountdownMode() async {
        let profile = HealthProfile(birthDate: "1990-05-01", biologicalSex: .male, lifestyle: .default)
        await DataStore.shared.updateProfile(profile)
        var data = await DataStore.shared.getData()
        XCTAssertEqual(data.profile.birthDate, "1990-05-01")

        await DataStore.shared.updateCountdownMode(.lev)
        data = await DataStore.shared.getData()
        XCTAssertEqual(data.profile.countdownMode, .lev)
        XCTAssertEqual(data.profile.birthDate, "1990-05-01",
                       "switching countdown mode must not clear the rest of the profile")
    }

    // MARK: - Genome action state

    func testGenomeActionStatusComposesAndPreservesOnReupdate() async {
        await DataStore.shared.setGenomeActionStatus(
            rsid: "rs123", actionId: "act1", status: .pending, note: "discuss with doc"
        )
        let key = GenomeActionState.key(rsid: "rs123", actionId: "act1")
        var states = await DataStore.shared.getData().genomeActionStates
        XCTAssertEqual(states[key]?.status, .pending)
        XCTAssertEqual(states[key]?.note, "discuss with doc")

        // Re-update status with nil note — the previously stored note must be
        // preserved (coalesced from the existing state), not overwritten to nil.
        await DataStore.shared.setGenomeActionStatus(rsid: "rs123", actionId: "act1", status: .done)
        states = await DataStore.shared.getData().genomeActionStates
        XCTAssertEqual(states[key]?.status, .done)
        XCTAssertEqual(states[key]?.note, "discuss with doc", "nil note must coalesce to the existing note")
    }

    func testSaveGenomeScanRecord() async {
        let record = GenomeScanRecord(
            scannedAt: Date(timeIntervalSince1970: 0),
            apoeHaplotype: "e3/e3",
            apoeStatus: nil,
            categoryRisks: [:]
        )
        await DataStore.shared.saveGenomeScanRecord(record)
        let data = await DataStore.shared.getData()
        XCTAssertEqual(data.genomeScanRecord?.apoeHaplotype, "e3/e3")
    }

    // MARK: - Visit notes (auto-discuss flow)

    func testAddVisitNoteAutoDiscussesPendingActions() async {
        await DataStore.shared.setGenomeActionStatus(rsid: "rs123", actionId: "act1", status: .pending)
        let note = VisitNote(findingKey: "rs123", body: "Discussed at annual physical")
        await DataStore.shared.addVisitNote(note) // autoDiscussPending defaults to true

        let data = await DataStore.shared.getData()
        XCTAssertEqual(data.genomeVisitNotes.count, 1)
        let key = GenomeActionState.key(rsid: "rs123", actionId: "act1")
        XCTAssertEqual(data.genomeActionStates[key]?.status, .discussed,
                       "pending actions on the same finding must flip to discussed")
        XCTAssertEqual(data.genomeActionStates[key]?.linkedVisitNoteId, note.id,
                       "the discussed action must link back to the note")
    }

    func testAddVisitNoteWithoutAutoDiscussLeavesPending() async {
        await DataStore.shared.setGenomeActionStatus(rsid: "rs123", actionId: "act1", status: .pending)
        await DataStore.shared.addVisitNote(
            VisitNote(findingKey: "rs123", body: "Visit Mode checklist note"),
            autoDiscussPending: false
        )

        let data = await DataStore.shared.getData()
        let key = GenomeActionState.key(rsid: "rs123", actionId: "act1")
        XCTAssertEqual(data.genomeActionStates[key]?.status, .pending,
                       "Visit Mode (autoDiscussPending:false) must not auto-complete a deliberately-pending action")
    }

    func testUpdateAndRemoveVisitNote() async {
        let note = VisitNote(findingKey: "rs123", body: "original")
        await DataStore.shared.addVisitNote(note, autoDiscussPending: false)

        var edited = note
        edited.body = "edited"
        await DataStore.shared.updateVisitNote(edited)
        var data = await DataStore.shared.getData()
        XCTAssertEqual(data.genomeVisitNotes.first?.body, "edited")

        await DataStore.shared.removeVisitNote(id: note.id)
        data = await DataStore.shared.getData()
        XCTAssertTrue(data.genomeVisitNotes.isEmpty)
    }

    // MARK: - Export / import serialization boundary

    func testExportRoundTrips() async throws {
        await DataStore.shared.addAlcoholDrink(AlcoholDrink(name: "IPA", oz: 12, abv: 6, date: "2026-01-01"))
        let exported = await DataStore.shared.exportData()
        let unwrapped = try XCTUnwrap(exported)
        let decoded = try JSONDecoder().decode(AppData.self, from: unwrapped)
        XCTAssertEqual(decoded.alcoholDrinks.first?.name, "IPA")
    }

    func testImportRejectsGarbage() async {
        let garbage = Data("not json".utf8)
        let ok = await DataStore.shared.importData(from: garbage)
        XCTAssertFalse(ok, "undecodable import data must be rejected")
    }
}
