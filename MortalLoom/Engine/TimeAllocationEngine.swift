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

    // MARK: Pillar breakdown

    struct PillarSlice: Sendable, Equatable {
        /// The pillar's goal id, or nil for time tagged to goals outside
        /// every pillar's subtree (e.g. standard goals parented straight
        /// to the North Star).
        let pillarId: UUID?
        let minutes: Int
    }

    /// Split an allocation's total minutes across life pillars for
    /// side-by-side comparison ("is my calendar aligned with my stated
    /// priorities?"). Pillars with zero minutes are dropped; whatever
    /// isn't inside any pillar's subtree lands in a trailing nil-id slice.
    static func pillarBreakdown(allocation: Allocation, pillars: [Goal]) -> [PillarSlice] {
        var slices = pillars.compactMap { pillar -> PillarSlice? in
            guard let minutes = allocation.minutesByAncestor[pillar.id], minutes > 0 else { return nil }
            return PillarSlice(pillarId: pillar.id, minutes: minutes)
        }
        slices.sort { $0.minutes > $1.minutes }
        let pillarTotal = slices.reduce(0) { $0 + $1.minutes }
        let remainder = allocation.totalMinutes - pillarTotal
        if remainder > 0 {
            slices.append(PillarSlice(pillarId: nil, minutes: remainder))
        }
        return slices
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
