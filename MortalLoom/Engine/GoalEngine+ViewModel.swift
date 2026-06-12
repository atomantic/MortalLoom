import Foundation

// MARK: - GoalsView View-Model

extension GoalEngine {

    /// A single node in the flattened goal hierarchy tree. Pure data — the
    /// SwiftUI tree-connector drawing lives in the view; this type only
    /// carries the layout facts (depth, sibling continuation, etc.) the view
    /// needs to render the connectors.
    struct HierarchyItem: Identifiable, Sendable, Equatable {
        let goal: Goal
        let depth: Int
        let isLastChild: Bool
        let continuingDepths: Set<Int>
        let hasChildren: Bool
        var id: UUID { goal.id }
    }

    /// Everything `GoalsView` needs to render, computed in one pure pass over
    /// `AppData`. Previously this was 100+ lines of business logic running on
    /// the main actor inside `loadData()` after every `.dataDidSync`; pulling
    /// it here makes the computation testable in isolation and keeps the view
    /// a thin presentation layer.
    struct GoalsViewModel: Sendable {
        var goals: [Goal] = []
        var habits: [Habit] = []
        var deathClock: DeathClockEngine.DeathClockResult?
        var levDeathClock: DeathClockEngine.DeathClockResult?
        var cognitiveDeadline: Date?
        var projections: [UUID: GoalProjection] = [:]
        var apexGoal: Goal?
        var childCounts: [UUID: Int] = [:]
        var doneGoals: [Goal] = []
        var activeCount = 0
        var completedCount = 0
        var attentionCount = 0
        var signalByGoalId: [UUID: StagnationSignal] = [:]
        var effectiveNeedsCheckInIds: Set<UUID> = []

        /// Roots + active-by-parent grouping, retained so the view can
        /// re-flatten the tree on collapse/expand without a full reload.
        var roots: [Goal] = []
        var activeByParent: [UUID?: [Goal]] = [:]
    }

    /// Stable sort order for sibling goals: apex first, then sub-apex, then
    /// standard, then untyped.
    private static func goalTypeOrder(_ goal: Goal) -> Int {
        switch goal.goalType {
        case .apex: 0
        case .subApex: 1
        case .standard: 2
        case nil: 3
        }
    }

    /// Compute the full `GoalsView` view-model from app data. Pure: no side
    /// effects, no main-actor dependency. `now` is injectable for tests.
    static func buildGoalsViewModel(from data: AppData, now: Date = Date()) -> GoalsViewModel {
        var vm = GoalsViewModel()
        vm.goals = data.goals
        vm.habits = data.habits

        let dc = DeathClockEngine.calculate(
            birthDateStr: data.profile.birthDate ?? "",
            sex: data.profile.biologicalSex,
            lifestyle: data.profile.lifestyle,
            genome: data.genomeScanRecord,
            locationProfile: data.profile.locationProfile,
            socioeconomic: data.profile.socioeconomic,
            healthMetrics: data.healthMetrics
        )
        let levDc: DeathClockEngine.DeathClockResult? = dc.flatMap {
            DeathClockEngine.calculateLEVResult(
                standardResult: $0,
                birthDateStr: data.profile.birthDate ?? "",
                levTargetAge: data.profile.levTargetAge
            )
        }
        let cogDate = cognitiveDeadline(from: dc, now: now)
        vm.deathClock = dc
        vm.levDeathClock = levDc
        vm.cognitiveDeadline = cogDate

        // Precompute effective latest activity dates once so parent goals
        // inherit freshness from sub-goal activity AND linked-habit
        // completions in both the projection math (slippage) and the
        // overdue nags (attention count, chips).
        let effectiveLatestDates = data.goals.effectiveLatestCheckInDates(habits: data.habits)

        var projs: [UUID: GoalProjection] = [:]
        for goal in data.goals {
            let days = DateFormatting.daysSince(
                effectiveLatestDates[goal.id] ?? goal.createdDate
            )
            projs[goal.id] = project(
                goal: goal,
                deathDate: dc?.deathDate,
                healthyCognitiveDate: cogDate,
                now: now,
                daysSinceLastCheckInOverride: days
            )
        }
        vm.projections = projs

        let activeGoals = data.goals.filter { $0.status == .active || $0.status == .paused }
        let done = data.goals.filter { $0.status == .completed || $0.status == .abandoned }
            .sorted { $0.completedDate ?? $0.createdDate > $1.completedDate ?? $1.createdDate }

        let apex = activeGoals.first { $0.goalType == .apex }
        let activeIds = Set(activeGoals.map(\.id))
        let activeByParent = Dictionary(grouping: activeGoals, by: \.parentId)

        // Precompute active child counts for all goals
        var counts: [UUID: Int] = [:]
        for goal in data.goals {
            counts[goal.id] = (activeByParent[goal.id] ?? []).count
        }

        var roots = activeGoals.filter { g in
            g.id != apex?.id &&
            (g.parentId == nil || !activeIds.contains(g.parentId!))
        }

        if let apex {
            let apexChildren = (activeByParent[apex.id] ?? [])
                .sorted { goalTypeOrder($0) < goalTypeOrder($1) }
            let otherRoots = roots.filter { $0.parentId != apex.id }
                .sorted { $0.priority < $1.priority }
            roots = apexChildren + otherRoots
        } else {
            roots.sort { goalTypeOrder($0) < goalTypeOrder($1) }
        }

        // StagnationEngine sorts most-severe first, so taking the first
        // hit per goalId naturally keeps the highest-severity signal.
        let signals = StagnationEngine.signals(
            goals: data.goals,
            habits: data.habits,
            deathDate: dc?.deathDate,
            healthyCognitiveDate: cogDate,
            now: now
        )
        var byGoal: [UUID: StagnationSignal] = [:]
        for s in signals {
            if let gid = s.goalId, byGoal[gid] == nil {
                byGoal[gid] = s
            }
        }

        vm.apexGoal = apex
        vm.childCounts = counts
        vm.doneGoals = done
        vm.activeCount = activeGoals.count
        vm.completedCount = done.count { $0.status == .completed }

        var needsIds = Set<UUID>()
        for g in data.goals where g.status == .active {
            let days = DateFormatting.daysSince(effectiveLatestDates[g.id] ?? g.createdDate)
            if days >= g.checkInIntervalDays { needsIds.insert(g.id) }
        }
        vm.effectiveNeedsCheckInIds = needsIds
        vm.attentionCount = activeGoals.count { needsIds.contains($0.id) || $0.isOverdue }
        vm.signalByGoalId = byGoal
        vm.roots = roots
        vm.activeByParent = activeByParent

        return vm
    }

    /// Flatten the goal tree into an ordered, depth-annotated list for
    /// rendering. `collapsedIds` prunes children of collapsed nodes. Pure —
    /// the view calls this both on load and on every collapse toggle.
    static func buildHierarchy(
        roots: [Goal],
        activeByParent: [UUID?: [Goal]],
        collapsedIds: Set<UUID>
    ) -> [HierarchyItem] {
        var items: [HierarchyItem] = []
        var visited = Set<UUID>()
        func flatten(_ goal: Goal, depth: Int, isLast: Bool, continuing: Set<Int>) {
            guard visited.insert(goal.id).inserted else { return }
            let children = (activeByParent[goal.id] ?? [])
                .sorted { $0.priority < $1.priority }
            items.append(HierarchyItem(
                goal: goal, depth: depth, isLastChild: isLast,
                continuingDepths: continuing, hasChildren: !children.isEmpty
            ))
            guard !collapsedIds.contains(goal.id) else { return }
            for (i, child) in children.enumerated() {
                let childIsLast = i == children.count - 1
                var childContinuing = continuing
                if childIsLast {
                    childContinuing.remove(depth + 1)
                } else {
                    childContinuing.insert(depth + 1)
                }
                flatten(child, depth: depth + 1, isLast: childIsLast, continuing: childContinuing)
            }
        }
        for (i, root) in roots.enumerated() {
            flatten(root, depth: 0, isLast: i == roots.count - 1, continuing: i < roots.count - 1 ? [0] : [])
        }
        return items
    }
}
