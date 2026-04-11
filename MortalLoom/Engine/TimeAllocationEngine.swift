import Foundation

// MARK: - TimeAllocationEngine

/// Maps MortalLoom-tagged calendar events to goals and pillars so the app
/// can answer: "How am I actually spending my scheduled time?"
///
/// This engine is a thin layer over `CalendarService.tagged(from:to:)`. It
/// takes the raw (goalId, startDate, durationMinutes) tuples and aggregates
/// them up the goal hierarchy — so scheduling a work block for a concrete
/// goal also shows up as minutes on its parent life pillar and ultimately
/// on the North Star.
///
/// Used by Pillar Dashboards, Reports, and (eventually) the Weekly Review
/// to surface whether the user's calendar reflects their stated priorities.
enum TimeAllocationEngine {

    // MARK: Allocation result

    struct Allocation: Sendable {
        /// Minutes scheduled per goal id over the requested window.
        let minutesByGoal: [UUID: Int]
        /// Rolled-up minutes per ancestor in the goal tree (each goal's
        /// total is its own minutes plus the minutes of all its descendants).
        let minutesByAncestor: [UUID: Int]
        /// Total MortalLoom-tagged minutes across all goals.
        let totalMinutes: Int
    }

    // MARK: Public API

    /// Compute the allocation from a list of goals and a window.
    /// `events` is the raw output from `CalendarService.tagged(from:to:)`
    /// so we stay testable without touching EventKit.
    static func allocate(
        goals: [Goal],
        events: [(goalId: UUID, startDate: Date, durationMinutes: Int)]
    ) -> Allocation {
        var minutesByGoal: [UUID: Int] = [:]
        for event in events {
            minutesByGoal[event.goalId, default: 0] += event.durationMinutes
        }

        // Roll minutes up the parent chain. Each ancestor gets the sum of
        // its subtree. We walk ancestors once per goal to keep this O(N*depth).
        let parents: [UUID: UUID] = Dictionary(
            uniqueKeysWithValues: goals.compactMap { g in
                g.parentId.map { (g.id, $0) }
            }
        )
        var minutesByAncestor: [UUID: Int] = [:]
        for (goalId, minutes) in minutesByGoal {
            var current: UUID? = goalId
            var safetyDepth = 0
            while let id = current, safetyDepth < 16 {
                minutesByAncestor[id, default: 0] += minutes
                current = parents[id]
                safetyDepth += 1
            }
        }
        let total = minutesByGoal.values.reduce(0, +)
        return Allocation(
            minutesByGoal: minutesByGoal,
            minutesByAncestor: minutesByAncestor,
            totalMinutes: total
        )
    }

    /// Format minutes as "2h 30m" / "45m". Used in UI rendering.
    static func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }
}
