import XCTest
@testable import MortalLoom

// MARK: - TimeAllocationEngine Tests
//
// Pure-function tests for the goal-time roll-up engine. Verifies per-goal
// minute aggregation, ancestor cascading up the parent chain, depth safety,
// and the human-readable formatter.

final class TimeAllocationEngineTests: XCTestCase {

    private func goal(_ title: String = "G", parent: UUID? = nil) -> Goal {
        Goal(title: title, parentId: parent)
    }

    private func event(goal: UUID, minutes: Int) -> (goalId: UUID, startDate: Date, durationMinutes: Int) {
        (goalId: goal, startDate: Date(), durationMinutes: minutes)
    }

    // MARK: - allocate

    func testAllocateEmpty() {
        let result = TimeAllocationEngine.allocate(goals: [], events: [])
        XCTAssertEqual(result.minutesByGoal, [:])
        XCTAssertEqual(result.minutesByAncestor, [:])
        XCTAssertEqual(result.totalMinutes, 0)
    }

    func testAllocateSingleEventSingleGoal() {
        let g = goal()
        let result = TimeAllocationEngine.allocate(goals: [g], events: [event(goal: g.id, minutes: 30)])
        XCTAssertEqual(result.minutesByGoal[g.id], 30)
        XCTAssertEqual(result.minutesByAncestor[g.id], 30)
        XCTAssertEqual(result.totalMinutes, 30)
    }

    func testAllocateMultipleEventsSameGoalAccumulate() {
        let g = goal()
        let events = [
            event(goal: g.id, minutes: 25),
            event(goal: g.id, minutes: 35)
        ]
        let result = TimeAllocationEngine.allocate(goals: [g], events: events)
        XCTAssertEqual(result.minutesByGoal[g.id], 60)
        XCTAssertEqual(result.totalMinutes, 60)
    }

    func testAllocateRollsMinutesUpToParent() {
        let parent = goal("Parent")
        let child = goal("Child", parent: parent.id)
        let events = [event(goal: child.id, minutes: 45)]
        let result = TimeAllocationEngine.allocate(goals: [parent, child], events: events)
        XCTAssertEqual(result.minutesByGoal[child.id], 45)
        XCTAssertNil(result.minutesByGoal[parent.id])
        XCTAssertEqual(result.minutesByAncestor[parent.id], 45)
        XCTAssertEqual(result.minutesByAncestor[child.id], 45)
    }

    func testAllocateRollsThroughGrandparentChain() {
        let north = goal("North Star")
        let pillar = goal("Pillar", parent: north.id)
        let leaf = goal("Leaf", parent: pillar.id)
        let events = [event(goal: leaf.id, minutes: 60)]
        let result = TimeAllocationEngine.allocate(goals: [north, pillar, leaf], events: events)
        XCTAssertEqual(result.minutesByAncestor[leaf.id], 60)
        XCTAssertEqual(result.minutesByAncestor[pillar.id], 60)
        XCTAssertEqual(result.minutesByAncestor[north.id], 60)
        XCTAssertEqual(result.totalMinutes, 60)
    }

    func testAllocateAggregatesSiblingsIntoSharedAncestor() {
        let parent = goal("Parent")
        let a = goal("A", parent: parent.id)
        let b = goal("B", parent: parent.id)
        let events = [
            event(goal: a.id, minutes: 30),
            event(goal: b.id, minutes: 20)
        ]
        let result = TimeAllocationEngine.allocate(goals: [parent, a, b], events: events)
        XCTAssertEqual(result.minutesByAncestor[parent.id], 50)
        XCTAssertEqual(result.minutesByAncestor[a.id], 30)
        XCTAssertEqual(result.minutesByAncestor[b.id], 20)
        XCTAssertEqual(result.totalMinutes, 50)
    }

    func testAllocateIgnoresOrphanGoalsAtRoot() {
        // Goal with no parent chain — the goal itself still gets credit
        let solo = goal("Solo")
        let events = [event(goal: solo.id, minutes: 15)]
        let result = TimeAllocationEngine.allocate(goals: [solo], events: events)
        XCTAssertEqual(result.minutesByAncestor.count, 1)
        XCTAssertEqual(result.minutesByAncestor[solo.id], 15)
    }

    func testAllocateEventForUnknownGoalStillCountsButHasNoChain() {
        // Unknown goal id is not in the goals list — it still counts to its own bucket
        // but has no parents to roll up to.
        let stranger = UUID()
        let events = [event(goal: stranger, minutes: 10)]
        let result = TimeAllocationEngine.allocate(goals: [], events: events)
        XCTAssertEqual(result.minutesByGoal[stranger], 10)
        XCTAssertEqual(result.minutesByAncestor[stranger], 10)
        XCTAssertEqual(result.totalMinutes, 10)
    }

    func testAllocateDepthSafetyClampsCycle() {
        // Build a cycle: A -> B -> A. The safety counter should bail out at depth 16
        // and not crash.
        let aId = UUID()
        let bId = UUID()
        let a = Goal(id: aId, title: "A", parentId: bId)
        let b = Goal(id: bId, title: "B", parentId: aId)
        let events = [event(goal: a.id, minutes: 5)]
        let result = TimeAllocationEngine.allocate(goals: [a, b], events: events)
        // Both ancestors should accumulate from the safety-limited walk
        XCTAssertGreaterThan(result.minutesByAncestor[a.id] ?? 0, 0)
        XCTAssertGreaterThan(result.minutesByAncestor[b.id] ?? 0, 0)
    }

    // MARK: - formatMinutes

    func testFormatMinutesUnderHour() {
        XCTAssertEqual(TimeAllocationEngine.formatMinutes(0), "0m")
        XCTAssertEqual(TimeAllocationEngine.formatMinutes(1), "1m")
        XCTAssertEqual(TimeAllocationEngine.formatMinutes(45), "45m")
        XCTAssertEqual(TimeAllocationEngine.formatMinutes(59), "59m")
    }

    func testFormatMinutesExactHours() {
        XCTAssertEqual(TimeAllocationEngine.formatMinutes(60), "1h")
        XCTAssertEqual(TimeAllocationEngine.formatMinutes(120), "2h")
        XCTAssertEqual(TimeAllocationEngine.formatMinutes(600), "10h")
    }

    func testFormatMinutesHoursAndMinutes() {
        XCTAssertEqual(TimeAllocationEngine.formatMinutes(75), "1h 15m")
        XCTAssertEqual(TimeAllocationEngine.formatMinutes(150), "2h 30m")
        XCTAssertEqual(TimeAllocationEngine.formatMinutes(125), "2h 5m")
    }
}
