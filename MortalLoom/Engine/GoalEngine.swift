import Foundation

enum GoalEngine {

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
    static func project(
        goal: Goal,
        deathDate: Date?,
        healthyCognitiveDate: Date?,
        now: Date = Date()
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

        // Missed check-ins extend the effective timeline
        let daysSinceLastCheckIn = goal.daysSinceLastCheckIn
        let totalElapsed = effectiveDays + max(0, daysSinceLastCheckIn - goal.checkInIntervalDays)

        let ratePerDay = max(0.001, effectiveProgress / Double(totalElapsed))
        let daysToComplete = Int(ceil(remaining / ratePerDay))
        let projectedDate = Calendar.current.date(byAdding: .day, value: daysToComplete, to: now)

        let weeklyRate = ratePerDay * 7

        let slippage = slippageDays(goal: goal, projectedDate: projectedDate, now: now)
        let exceedsCognitive = healthyCognitiveDate.map { projectedDate ?? now > $0 } ?? false
        let exceedsLife = deathDate.map { projectedDate ?? now > $0 } ?? false

        let urgency: UrgencyLevel
        if exceedsLife {
            urgency = .impossible
        } else if exceedsCognitive {
            urgency = .critical
        } else if slippage > 0 {
            urgency = .atRisk
        } else if goal.needsCheckIn {
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

        for goal in goals where goal.status == .active {
            if let targetStr = goal.targetDate,
               let targetDate = DateFormatting.dateFromString(targetStr) {
                let days = Calendar.current.dateComponents([.day], from: birthDate, to: targetDate).day ?? 0
                markers.append(GoalMarker(title: goal.title, weekIndex: max(0, days / 7), isProjected: false, priority: goal.priority))
            }

            let projection = project(goal: goal, deathDate: deathDate, healthyCognitiveDate: healthyCognitiveDate)
            if let projDate = projection.projectedCompletionDate {
                let days = Calendar.current.dateComponents([.day], from: birthDate, to: projDate).day ?? 0
                markers.append(GoalMarker(title: goal.title, weekIndex: max(0, days / 7), isProjected: true, priority: goal.priority))
            }
        }

        return markers
    }
}

struct GoalMarker: Sendable {
    let title: String
    let weekIndex: Int
    let isProjected: Bool
    let priority: GoalPriority
}

// MARK: - Goal Tree

struct GoalTreeNode: Sendable {
    let goal: Goal
    var children: [GoalTreeNode]
}

extension GoalEngine {

    /// Build a tree of goals from a flat list.
    /// Top-level nodes are goals with no parentId or whose parentId doesn't match any goal in the list.
    /// Children are sorted by priority then creation date.
    static func buildTree(from goals: [Goal]) -> [GoalTreeNode] {
        let idSet = Set(goals.map(\.id))
        var childrenMap: [UUID: [Goal]] = [:]

        for goal in goals {
            if let pid = goal.parentId, idSet.contains(pid) {
                childrenMap[pid, default: []].append(goal)
            }
        }

        func buildNode(_ goal: Goal) -> GoalTreeNode {
            let kids = (childrenMap[goal.id] ?? [])
                .sorted { ($0.priority, $0.createdDate) < ($1.priority, $1.createdDate) }
                .map { buildNode($0) }
            return GoalTreeNode(goal: goal, children: kids)
        }

        let topLevel = goals.filter { $0.parentId == nil || !idSet.contains($0.parentId!) }
        return topLevel.map { buildNode($0) }
    }
}
