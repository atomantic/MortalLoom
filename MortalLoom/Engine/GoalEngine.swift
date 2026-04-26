import Foundation

enum GoalEngine {

    // MARK: - Tree walking

    /// All active descendants of `root` in the goal list, collected via BFS.
    /// Walks through any goal type (apex, sub-apex, standard) and returns
    /// only the nodes that are themselves active. `root` itself is not
    /// included in the result.
    static func activeDescendants(of root: Goal, in goals: [Goal]) -> [Goal] {
        var result: [Goal] = []
        var queue: [UUID] = [root.id]
        while let id = queue.popLast() {
            for g in goals where g.parentId == id && g.status == .active {
                queue.append(g.id)
                result.append(g)
            }
        }
        return result
    }

    /// Active standard-goal descendants of `root` (leaf nodes with real
    /// progress). Used for alignment rollups where only concrete goals
    /// contribute. Apex and sub-apex descendants are traversed but not
    /// included in the result since they don't have meaningful `progressPercent`.
    static func standardDescendants(of root: Goal, in goals: [Goal]) -> [Goal] {
        var leaves: [Goal] = []
        var queue: [UUID] = [root.id]
        while let id = queue.popLast() {
            for g in goals where g.parentId == id && g.status == .active {
                queue.append(g.id)
                if g.goalType == .standard || g.goalType == nil {
                    leaves.append(g)
                }
            }
        }
        return leaves
    }

    // MARK: - Alignment Score

    /// Alignment Score = average `progressPercent` across active standard
    /// descendants of `root`. Returns nil when there are no descendants so
    /// callers can show an empty-state CTA instead of a misleading 0%.
    ///
    /// This is the canonical definition — Overview, Widget, Reports, and
    /// Weekly Review all call it so the number is consistent across the app.
    static func alignmentScore(for root: Goal, in goals: [Goal]) -> Double? {
        let leaves = standardDescendants(of: root, in: goals)
        guard !leaves.isEmpty else { return nil }
        return leaves.reduce(0.0) { $0 + $1.progressPercent } / Double(leaves.count)
    }

    /// Weighted alignment score combining goal progress (70%) with habit
    /// streak health (30%). Used by Pillar Dashboards and other surfaces
    /// that want to reflect both tracked progress and daily engagement.
    ///
    /// If no standard descendants exist, returns habit-only score.
    /// If no habits are linked, returns goal-only score.
    /// If neither is present, returns nil.
    static func alignmentScore(
        for root: Goal,
        in goals: [Goal],
        habits: [Habit],
        habitWeight: Double = 0.3
    ) -> Double? {
        let goalScore = alignmentScore(for: root, in: goals)
        let descendantIds: Set<UUID> = Set([root.id] + activeDescendants(of: root, in: goals).map(\.id))
        let linkedHabits = habits.filter { h in
            guard h.isActive, let parent = h.parentGoalId else { return false }
            return descendantIds.contains(parent)
        }
        guard !linkedHabits.isEmpty else { return goalScore }
        let habitAvg = linkedHabits
            .reduce(0.0) { $0 + HabitEngine.alignmentContribution($1) }
            / Double(linkedHabits.count)
        guard let goalScore else { return habitAvg }
        let goalWeight = 1.0 - habitWeight
        return goalScore * goalWeight + habitAvg * habitWeight
    }

    // MARK: - Reflection Streak

    /// Consecutive-calendar-day reflection streak on a goal. Walks
    /// backwards from `now` and counts days with at least one
    /// reflection-shaped check-in. Stops at the first gap.
    ///
    /// "Today counts" is optional: if the user hasn't reflected today yet
    /// we still want to show the current run length, so we also accept a
    /// streak that starts yesterday.
    ///
    /// Returns 0 when the goal has no reflection check-ins.
    static func dailyReflectionStreak(for goal: Goal, now: Date = Date()) -> Int {
        let reflectionDays: Set<String> = Set(
            goal.checkIns.filter(\.isReflection).map(\.date)
        )
        guard !reflectionDays.isEmpty else { return 0 }
        let calendar = Calendar.current
        var probe = now
        if !reflectionDays.contains(DateFormatting.dateString(probe)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: probe) else { return 0 }
            probe = yesterday
        }
        var count = 0
        while reflectionDays.contains(DateFormatting.dateString(probe)) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: probe) else { break }
            probe = prev
        }
        return count
    }

    // MARK: - Smart Cadence

    /// Derive a sensible default check-in cadence (in days) for a goal based
    /// on its timeline. A 7-day goal should be checked in every couple days,
    /// not every two weeks. A multi-month goal can check in weekly.
    ///
    /// - Returns: an integer number of days, minimum 1.
    ///
    /// Rules:
    /// - No target date (apex/sub-apex): 14 days (biweekly reflection default).
    /// - Target within 7 days: every 2 days.
    /// - Target within 30 days: every duration / 6, min 3 days.
    /// - Longer: weekly.
    static func defaultCheckInIntervalDays(for goal: Goal, now: Date = Date()) -> Int {
        guard let targetStr = goal.targetDate,
              let targetDate = DateFormatting.dateFromString(targetStr) else {
            return 14
        }
        let days = Calendar.current.dateComponents([.day], from: now, to: targetDate).day ?? 7
        if days <= 0 { return 1 }
        if days <= 7 { return max(1, days / 3) }
        if days <= 30 { return max(3, days / 6) }
        return 7
    }

    struct GoalProjection: Sendable {
        let projectedCompletionDate: Date?
        let daysToCompletion: Int?
        let slippageDays: Int
        let exceedsCognitiveYears: Bool
        let exceedsLifespan: Bool
        let urgencyLevel: UrgencyLevel
        let weeklyProgressRate: Double
    }

    enum UrgencyLevel: String, Sendable {
        case onTrack
        case slipping
        case atRisk
        case critical
        case impossible
    }

    /// Project when a goal will be completed based on progress velocity.
    /// If check-ins are missed, the projection automatically extends.
    ///
    /// `daysSinceLastCheckInOverride` lets callers substitute the goal's
    /// direct check-in freshness with a hierarchy-aware value — when the
    /// user is checking in on sub-goals, the parent's projection shouldn't
    /// be penalized for missed parent check-ins. Callers without a tree
    /// context can leave this nil and the strict per-goal value is used.
    static func project(
        goal: Goal,
        deathDate: Date?,
        healthyCognitiveDate: Date?,
        now: Date = Date(),
        daysSinceLastCheckInOverride: Int? = nil
    ) -> GoalProjection {
        let progress = goal.progressPercent
        let remaining = 100.0 - progress

        guard progress > 0, !goal.checkIns.isEmpty else {
            return noProjection(goal: goal, now: now)
        }

        let sorted = goal.checkIns.sorted { $0.date < $1.date }
        guard let firstDate = DateFormatting.dateFromString(sorted.first?.date ?? ""),
              let lastDate = DateFormatting.dateFromString(sorted.last?.date ?? "") else {
            return noProjection(goal: goal, now: now)
        }

        let daysBetween = max(1, Calendar.current.dateComponents([.day], from: firstDate, to: lastDate).day ?? 1)

        let effectiveDays: Int
        let effectiveProgress: Double
        if sorted.count == 1 {
            guard let created = DateFormatting.dateFromString(goal.createdDate) else {
                return noProjection(goal: goal, now: now)
            }
            effectiveDays = max(1, Calendar.current.dateComponents([.day], from: created, to: lastDate).day ?? 1)
            effectiveProgress = progress
        } else {
            effectiveDays = daysBetween
            effectiveProgress = (sorted.last?.progressPct ?? 0) - (sorted.first?.progressPct ?? 0)
        }

        // Missed check-ins extend the effective timeline. Callers that know
        // the hierarchy pass in an override so parent goals inherit credit
        // from recent sub-goal check-ins.
        let daysSinceLastCheckIn = daysSinceLastCheckInOverride ?? goal.daysSinceLastCheckIn
        let totalElapsed = effectiveDays + max(0, daysSinceLastCheckIn - goal.checkInIntervalDays)

        let ratePerDay = max(0.001, effectiveProgress / Double(totalElapsed))
        let daysToComplete = Int(ceil(remaining / ratePerDay))
        let projectedDate = Calendar.current.date(byAdding: .day, value: daysToComplete, to: now)

        let weeklyRate = ratePerDay * 7

        let slippage = slippageDays(goal: goal, projectedDate: projectedDate, now: now)
        let exceedsCognitive = healthyCognitiveDate.map { projectedDate ?? now > $0 } ?? false
        let exceedsLife = deathDate.map { projectedDate ?? now > $0 } ?? false

        let effectiveNeedsCheckIn = goal.status == .active
            && daysSinceLastCheckIn >= goal.checkInIntervalDays
        let urgency: UrgencyLevel
        if exceedsLife {
            urgency = .impossible
        } else if exceedsCognitive {
            urgency = .critical
        } else if slippage > 0 {
            urgency = .atRisk
        } else if effectiveNeedsCheckIn {
            urgency = .slipping
        } else {
            urgency = .onTrack
        }

        return GoalProjection(
            projectedCompletionDate: projectedDate,
            daysToCompletion: daysToComplete,
            slippageDays: slippage,
            exceedsCognitiveYears: exceedsCognitive,
            exceedsLifespan: exceedsLife,
            urgencyLevel: urgency,
            weeklyProgressRate: (weeklyRate * 10).rounded() / 10
        )
    }

    private static func slippageDays(goal: Goal, projectedDate: Date?, now: Date) -> Int {
        guard let targetStr = goal.targetDate,
              let targetDate = DateFormatting.dateFromString(targetStr) else { return 0 }
        let compareDate = projectedDate ?? now
        if compareDate <= targetDate { return 0 }
        return Calendar.current.dateComponents([.day], from: targetDate, to: compareDate).day ?? 0
    }

    private static func noProjection(goal: Goal, now: Date) -> GoalProjection {
        GoalProjection(
            projectedCompletionDate: nil,
            daysToCompletion: nil,
            slippageDays: slippageDays(goal: goal, projectedDate: nil, now: now),
            exceedsCognitiveYears: false,
            exceedsLifespan: false,
            urgencyLevel: goal.needsCheckIn ? .slipping : .onTrack,
            weeklyProgressRate: 0
        )
    }

    static func cognitiveDeadline(from deathClock: DeathClockEngine.DeathClockResult?, now: Date = Date()) -> Date? {
        guard let dc = deathClock else { return nil }
        let cognitiveYears = dc.healthyYearsRemaining
        return Calendar.current.date(byAdding: .day, value: Int(cognitiveYears * 365.25), to: now)
    }

    /// Convert active goals into week-index markers relative to a birth date.
    static func goalMarkers(
        goals: [Goal],
        birthDate: Date,
        deathDate: Date?,
        healthyCognitiveDate: Date?
    ) -> [GoalMarker] {
        var markers: [GoalMarker] = []
        let byId = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0) })

        for goal in goals where goal.status == .active {
            let parentPath = parentPathString(for: goal, byId: byId)

            if let targetStr = goal.targetDate,
               let targetDate = DateFormatting.dateFromString(targetStr) {
                let days = Calendar.current.dateComponents([.day], from: birthDate, to: targetDate).day ?? 0
                markers.append(GoalMarker(
                    title: goal.title,
                    weekIndex: max(0, days / 7),
                    isProjected: false,
                    priority: goal.priority,
                    parentPath: parentPath
                ))
            }

            let projection = project(goal: goal, deathDate: deathDate, healthyCognitiveDate: healthyCognitiveDate)
            if let projDate = projection.projectedCompletionDate {
                let days = Calendar.current.dateComponents([.day], from: birthDate, to: projDate).day ?? 0
                markers.append(GoalMarker(
                    title: goal.title,
                    weekIndex: max(0, days / 7),
                    isProjected: true,
                    priority: goal.priority,
                    parentPath: parentPath
                ))
            }
        }

        return markers
    }

    private static func parentPathString(for goal: Goal, byId: [UUID: Goal]) -> String {
        var chain: [String] = []
        var cursor = goal.parentId
        var seen = Set<UUID>()
        while let pid = cursor, !seen.contains(pid), let parent = byId[pid] {
            chain.append(parent.title)
            seen.insert(pid)
            cursor = parent.parentId
        }
        return chain.reversed().joined(separator: " › ")
    }
}

struct GoalMarker: Sendable {
    let title: String
    let weekIndex: Int
    let isProjected: Bool
    let priority: GoalPriority
    /// Parent chain from the top-level apex down to the direct parent,
    /// joined like "Apex › Sub-apex › Parent". Empty when the goal has no
    /// parent. Used in the Life Calendar tooltip to disambiguate repeated
    /// sub-goal titles across different branches.
    var parentPath: String = ""

    /// Stable identity for SwiftUI ForEach. Using title alone collapses
    /// distinct sub-goals that share a name (e.g. "Finish design" under
    /// two different pillars).
    var compositeId: String {
        "\(title)|\(parentPath)|\(weekIndex)|\(isProjected)"
    }
}
