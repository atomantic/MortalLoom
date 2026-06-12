import XCTest
@testable import MortalLoom

// MARK: - GoalEngine View-Model Tests
//
// Pure-function tests for the GoalsView view-model builder and tree-flatten
// algorithm extracted out of GoalsView.loadData(), plus the smart-cadence
// math that previously had no coverage. (Projection-path coverage lives in
// the GoalEngineTests class in MortalLoomTests.swift.)

final class GoalEngineViewModelTests: XCTestCase {

    // MARK: - Fixtures

    /// Build an AppData carrying just a goal list (and optional habits) —
    /// everything else empty. Enough to exercise buildGoalsViewModel without
    /// a full profile (no birth date → no DeathClock, which is fine for the
    /// hierarchy/counting assertions).
    private func appData(goals: [Goal], habits: [Habit] = []) -> AppData {
        var data = AppData.empty
        data.goals = goals
        data.habits = habits
        return data
    }

    private func goal(
        title: String,
        type: GoalType? = .standard,
        status: GoalStatus = .active,
        parent: UUID? = nil,
        priority: GoalPriority = .medium,
        progress: Double? = nil,
        id: UUID = UUID()
    ) -> Goal {
        var g = Goal(id: id, title: title, status: status, priority: priority, parentId: parent, goalType: type)
        if let progress {
            g.checkIns = [GoalCheckIn(progressPct: progress)]
        }
        return g
    }

    // Goal.id is `let`, so build with an explicit id when the test needs one.
    private func goalWithId(
        _ id: UUID,
        title: String,
        type: GoalType? = .standard,
        status: GoalStatus = .active,
        parent: UUID? = nil,
        priority: GoalPriority = .medium
    ) -> Goal {
        Goal(id: id, title: title, status: status, priority: priority, parentId: parent, goalType: type)
    }

    // MARK: - buildGoalsViewModel: counting

    func testViewModelCountsActiveCompletedAndAbandoned() {
        let goals = [
            goal(title: "Active A", status: .active),
            goal(title: "Active B", status: .active),
            goal(title: "Paused C", status: .paused),
            goal(title: "Done D", status: .completed),
            goal(title: "Gone E", status: .abandoned),
        ]
        let vm = GoalEngine.buildGoalsViewModel(from: appData(goals: goals))

        // active + paused count as "active" in the header.
        XCTAssertEqual(vm.activeCount, 3)
        XCTAssertEqual(vm.completedCount, 1)
        // doneGoals holds both completed and abandoned.
        XCTAssertEqual(vm.doneGoals.count, 2)
    }

    func testViewModelIdentifiesApex() {
        let apexId = UUID()
        let goals = [
            goalWithId(apexId, title: "North Star", type: .apex),
            goal(title: "Standard", type: .standard),
        ]
        let vm = GoalEngine.buildGoalsViewModel(from: appData(goals: goals))
        XCTAssertEqual(vm.apexGoal?.id, apexId)
    }

    func testViewModelChildCounts() {
        let parentId = UUID()
        let goals = [
            goalWithId(parentId, title: "Parent", type: .subApex),
            goal(title: "Child 1", parent: parentId),
            goal(title: "Child 2", parent: parentId),
            goal(title: "Orphan"),
        ]
        let vm = GoalEngine.buildGoalsViewModel(from: appData(goals: goals))
        XCTAssertEqual(vm.childCounts[parentId], 2)
    }

    // MARK: - buildGoalsViewModel: roots & ordering

    func testRootsExcludeApexAndPlaceApexChildrenFirst() {
        let apexId = UUID()
        let pillarId = UUID()
        let goals = [
            goalWithId(apexId, title: "Apex", type: .apex),
            goalWithId(pillarId, title: "Pillar", type: .subApex, parent: apexId),
            goal(title: "Top-level standard", type: .standard, parent: nil, priority: .low),
        ]
        let vm = GoalEngine.buildGoalsViewModel(from: appData(goals: goals))

        // Apex itself is rendered in its own section, never a root row.
        XCTAssertFalse(vm.roots.contains { $0.id == apexId })
        // Apex's direct child (the pillar) sorts ahead of unrelated top-level goals.
        XCTAssertEqual(vm.roots.first?.id, pillarId)
    }

    // MARK: - buildHierarchy

    func testBuildHierarchyFlattensDepthFirst() {
        let rootId = UUID()
        let childId = UUID()
        let grandchildId = UUID()
        let root = goalWithId(rootId, title: "Root")
        let child = goalWithId(childId, title: "Child", parent: rootId)
        let grandchild = goalWithId(grandchildId, title: "Grandchild", parent: childId)

        let byParent: [UUID?: [Goal]] = [
            rootId: [child],
            childId: [grandchild],
        ]
        let items = GoalEngine.buildHierarchy(roots: [root], activeByParent: byParent, collapsedIds: [])

        XCTAssertEqual(items.map(\.goal.id), [rootId, childId, grandchildId])
        XCTAssertEqual(items.map(\.depth), [0, 1, 2])
        XCTAssertTrue(items[0].hasChildren)
        XCTAssertTrue(items[1].hasChildren)
        XCTAssertFalse(items[2].hasChildren)
    }

    func testBuildHierarchyCollapseHidesDescendants() {
        let rootId = UUID()
        let childId = UUID()
        let root = goalWithId(rootId, title: "Root")
        let child = goalWithId(childId, title: "Child", parent: rootId)
        let byParent: [UUID?: [Goal]] = [rootId: [child]]

        let collapsed = GoalEngine.buildHierarchy(roots: [root], activeByParent: byParent, collapsedIds: [rootId])
        XCTAssertEqual(collapsed.map(\.goal.id), [rootId])
        // Root still reports it has children so the expand affordance shows.
        XCTAssertTrue(collapsed[0].hasChildren)
    }

    func testBuildHierarchyIsCycleSafe() {
        // A malformed parent cycle must not infinite-loop.
        let aId = UUID()
        let bId = UUID()
        let a = goalWithId(aId, title: "A", parent: bId)
        let b = goalWithId(bId, title: "B", parent: aId)
        let byParent: [UUID?: [Goal]] = [aId: [b], bId: [a]]

        let items = GoalEngine.buildHierarchy(roots: [a], activeByParent: byParent, collapsedIds: [])
        // Each goal appears at most once thanks to the visited set.
        XCTAssertEqual(Set(items.map(\.goal.id)).count, items.count)
    }

    // MARK: - defaultCheckInIntervalDays

    func testDefaultCadenceNoTargetIsBiweekly() {
        let g = Goal(title: "Lifelong", goalType: .apex)
        XCTAssertEqual(GoalEngine.defaultCheckInIntervalDays(for: g), 14)
    }

    func testDefaultCadenceShortGoalIsFrequent() {
        // Pin `now` to midnight so the date-only target parses to an exact
        // whole-day delta (a wall-clock `now` would shave a partial day off).
        let now = Calendar.current.startOfDay(for: Date())
        let target = Calendar.current.date(byAdding: .day, value: 6, to: now)!
        let g = Goal(title: "Sprint", targetDate: DateFormatting.dateString(target))
        // 6 days / 3 = 2 — a week-long goal gets a couple-day cadence.
        XCTAssertEqual(GoalEngine.defaultCheckInIntervalDays(for: g, now: now), 2)
    }

    func testDefaultCadenceLongGoalIsWeekly() {
        let now = Date()
        let target = Calendar.current.date(byAdding: .day, value: 200, to: now)!
        let g = Goal(title: "Marathon", targetDate: DateFormatting.dateString(target))
        XCTAssertEqual(GoalEngine.defaultCheckInIntervalDays(for: g, now: now), 7)
    }

    func testDefaultCadencePastTargetClampsToOne() {
        let now = Date()
        let target = Calendar.current.date(byAdding: .day, value: -3, to: now)!
        let g = Goal(title: "Overdue", targetDate: DateFormatting.dateString(target))
        XCTAssertEqual(GoalEngine.defaultCheckInIntervalDays(for: g, now: now), 1)
    }
}
