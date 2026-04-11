import Foundation
import SwiftUI

// MARK: - StagnationSignal

/// A single stagnation signal raised by `StagnationEngine`. Each signal
/// identifies what is stalling, how serious it is, and a suggested prompt
/// the user can answer to unstick themselves.
///
/// `daysOverdue` is populated for missed-cadence signals so the UI can
/// escalate wording ("7 days overdue" vs. "45 days overdue") and so tests
/// can assert severity scales with time.
struct StagnationSignal: Identifiable, Sendable, Equatable {
    let id: UUID
    let severity: StagnationSeverity
    let goalId: UUID?
    let habitId: UUID?
    let title: String
    let detail: String
    let suggestedPrompt: String
    let daysOverdue: Int?

    init(
        id: UUID = UUID(),
        severity: StagnationSeverity,
        goalId: UUID? = nil,
        habitId: UUID? = nil,
        title: String,
        detail: String,
        suggestedPrompt: String,
        daysOverdue: Int? = nil
    ) {
        self.id = id
        self.severity = severity
        self.goalId = goalId
        self.habitId = habitId
        self.title = title
        self.detail = detail
        self.suggestedPrompt = suggestedPrompt
        self.daysOverdue = daysOverdue
    }
}

/// Scale a missed-cadence severity based on how many cadence intervals the
/// user has blown past. Tuned so:
/// - 1.0–1.5x cadence → `.info` (recent, recoverable)
/// - 1.5–3x cadence   → `.warn`
/// - >3x cadence      → `.alert`
///
/// Pure function, exposed for testing.
func stagnationSeverity(daysOverdue: Int, cadenceIntervalDays: Int) -> StagnationSeverity {
    guard cadenceIntervalDays > 0 else { return .warn }
    let ratio = Double(daysOverdue) / Double(cadenceIntervalDays)
    if ratio >= 3 { return .alert }
    if ratio >= 1.5 { return .warn }
    return .info
}

enum StagnationSeverity: String, Codable, Sendable, Comparable {
    case info, warn, alert

    var order: Int {
        switch self {
        case .info: 0
        case .warn: 1
        case .alert: 2
        }
    }

    static func < (lhs: StagnationSeverity, rhs: StagnationSeverity) -> Bool {
        lhs.order < rhs.order
    }

    /// SF Symbol name for this severity. Centralised so OverviewView,
    /// CheckInSheet, and ReportsView all render the same icon for a given
    /// signal without duplicating the mapping.
    var iconName: String {
        switch self {
        case .info: "info.circle"
        case .warn: "exclamationmark.triangle"
        case .alert: "exclamationmark.octagon.fill"
        }
    }

    /// Semantic tint color for this severity.
    var tintColor: Color {
        switch self {
        case .info: .accentColor
        case .warn: .warning
        case .alert: .danger
        }
    }
}

// MARK: - StagnationEngine

/// Pure function that walks the goal tree and habit list and surfaces any
/// stagnation signals. Inputs are immutable snapshots; output is a sorted
/// array (most severe first) that the UI can render as badges, lists, or
/// notification content.
///
/// Signals currently detected:
/// - A goal that has missed its check-in cadence.
/// - An apex with zero active supporting goals (structural gap).
/// - A sub-apex (life pillar) with zero active standard descendants.
/// - A positive habit that has missed its cadence 3+ periods in a row.
/// - A standard goal projected to slip past its deadline.
enum StagnationEngine {

    static func signals(
        goals: [Goal],
        habits: [Habit],
        deathDate: Date? = nil,
        healthyCognitiveDate: Date? = nil,
        now: Date = Date()
    ) -> [StagnationSignal] {
        var signals: [StagnationSignal] = []

        // Index children by parent for quick lookups.
        var childrenByParent: [UUID: [Goal]] = [:]
        for g in goals where g.status == .active {
            guard let pid = g.parentId else { continue }
            childrenByParent[pid, default: []].append(g)
        }

        // Precompute effective latest check-in dates once so every goal
        // loop below can reuse it (parent goals inherit descendant credit).
        let effectiveLatestDates = goals.effectiveLatestCheckInDates()

        // 1. Apex with no active supporting goals.
        for apex in goals where apex.goalType == .apex && apex.status == .active {
            let children = childrenByParent[apex.id] ?? []
            if children.isEmpty {
                signals.append(StagnationSignal(
                    severity: .warn,
                    goalId: apex.id,
                    title: "No supporting goals",
                    detail: "Your North Star has no active supporting goals yet. Add a life pillar or concrete goal that feeds into it.",
                    suggestedPrompt: "What would make progress toward '\(apex.title)' feel real this month?"
                ))
            }
        }

        // 2. Sub-apex (life pillar) with no active standard descendants.
        for pillar in goals where pillar.goalType == .subApex && pillar.status == .active {
            let leaves = GoalEngine.standardDescendants(of: pillar, in: goals)
            if leaves.isEmpty {
                signals.append(StagnationSignal(
                    severity: .info,
                    goalId: pillar.id,
                    title: "Pillar has no concrete goals",
                    detail: "Life pillar '\(pillar.title)' has no active standard goals feeding into it.",
                    suggestedPrompt: "What's one concrete goal that would move '\(pillar.title)' forward?"
                ))
            }
        }

        // 3. Goals that have missed their check-in cadence. Severity scales
        // with how many cadence intervals the user has missed, so a 3-day
        // miss and a 45-day miss don't raise identical alerts. Parent goals
        // inherit check-in credit from their descendants — if the user has
        // been checking in on sub-goals, the parent isn't considered stale.
        for g in goals where g.status == .active && g.goalType != .apex && g.goalType != .subApex {
            let days = DateFormatting.daysSince(effectiveLatestDates[g.id] ?? g.createdDate, now: now)
            if days >= g.checkInIntervalDays {
                let overdue = max(0, days - g.checkInIntervalDays)
                let severity = stagnationSeverity(
                    daysOverdue: overdue,
                    cadenceIntervalDays: g.checkInIntervalDays
                )
                signals.append(StagnationSignal(
                    severity: severity,
                    goalId: g.id,
                    title: "Check-in overdue",
                    detail: "'\(g.title)' hasn't been checked in for \(days) day\(days == 1 ? "" : "s").",
                    suggestedPrompt: ReflectionPrompts.pick(from: ReflectionPrompts.stagnation),
                    daysOverdue: overdue
                ))
            }
        }

        // 4. Standard goals projected to slip past their deadline. Pass
        // the effective days-since-last-check-in so sub-goal activity
        // shortens the "missed check-in" penalty on parents too.
        for g in goals where g.status == .active && g.goalType != .apex && g.goalType != .subApex {
            let effectiveDays = DateFormatting.daysSince(
                effectiveLatestDates[g.id] ?? g.createdDate, now: now
            )
            let projection = GoalEngine.project(
                goal: g,
                deathDate: deathDate,
                healthyCognitiveDate: healthyCognitiveDate,
                now: now,
                daysSinceLastCheckInOverride: effectiveDays
            )
            if projection.slippageDays > 0 {
                signals.append(StagnationSignal(
                    severity: projection.exceedsLifespan ? .alert : .warn,
                    goalId: g.id,
                    title: projection.exceedsLifespan
                        ? "Beyond expected lifespan"
                        : "Slipping past deadline",
                    detail: projection.exceedsLifespan
                        ? "At your current pace, '\(g.title)' extends beyond your expected lifespan."
                        : "'\(g.title)' is trending \(projection.slippageDays) day\(projection.slippageDays == 1 ? "" : "s") past its target.",
                    suggestedPrompt: "What could you clear from your calendar to accelerate '\(g.title)'?"
                ))
            }
        }

        // 5. Habits that have missed their cadence 3+ periods in a row.
        for habit in habits where habit.isActive && habit.kind == .positive {
            if HabitEngine.isStagnant(habit, consecutiveMisses: 3, now: now) {
                signals.append(StagnationSignal(
                    severity: .warn,
                    goalId: habit.parentGoalId,
                    habitId: habit.id,
                    title: "Habit is slipping",
                    detail: "'\(habit.name)' has missed its \(habit.cadence.label.lowercased()) cadence for the last few periods.",
                    suggestedPrompt: "What got in the way of '\(habit.name)' this week?"
                ))
            }
        }

        // Filter out signals the user has explicitly muted per-goal. A goal's
        // `mutedSignals` set contains signal titles that should never fire
        // for that specific goal. Global signals (those without a goalId)
        // are not affected.
        let mutedByGoal: [UUID: Set<String>] = Dictionary(
            uniqueKeysWithValues: goals.compactMap { g in
                g.mutedSignals.isEmpty ? nil : (g.id, Set(g.mutedSignals))
            }
        )
        let visible = signals.filter { signal in
            guard let goalId = signal.goalId,
                  let muted = mutedByGoal[goalId] else { return true }
            return !muted.contains(signal.title)
        }

        // Sort most severe first, then alphabetically by title for stable order.
        return visible.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return lhs.title < rhs.title
        }
    }
}
