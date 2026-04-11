import Foundation

// MARK: - HabitEngine

/// Pure functions over `Habit` and `HabitCompletion`. No side effects, all
/// testable in isolation. Handles streak math, target-hit-rate, and the
/// alignment contribution a habit makes to its parent goal or pillar.
enum HabitEngine {

    // MARK: Period bucketing

    /// Today's calendar start (local timezone). Used as the anchor for
    /// all period calculations.
    private static func startOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Start of the ISO week containing `date` (Monday-anchored by default).
    private static func startOfWeek(_ date: Date, calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: components) ?? startOfDay(date, calendar: calendar)
    }

    /// Return the count of completions bucketed into the single period containing `date`.
    /// For daily cadence: all completions on that date.
    /// For weekly cadence: all completions in that ISO week.
    static func completionsInPeriod(
        _ habit: Habit,
        containing date: Date,
        calendar: Calendar = .current
    ) -> Int {
        switch habit.cadence.period {
        case .daily:
            let dateStr = DateFormatting.dateString(date)
            return habit.completions
                .filter { $0.date == dateStr }
                .reduce(0) { $0 + $1.count }
        case .weekly:
            let weekStart = startOfWeek(date, calendar: calendar)
            guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
                return 0
            }
            return habit.completions
                .compactMap { c -> Int? in
                    guard let d = DateFormatting.dateFromString(c.date) else { return nil }
                    return (d >= weekStart && d < weekEnd) ? c.count : nil
                }
                .reduce(0, +)
        }
    }

    // MARK: Streaks

    /// Current streak: how many consecutive periods (ending today or this week)
    /// the habit has hit its target. A period that exactly hits or exceeds
    /// the target counts. A missed period breaks the streak immediately.
    ///
    /// Returns 0 if today/this-period hasn't been hit yet — this is
    /// intentional so the streak reflects committed progress, not hope.
    static func currentStreak(
        _ habit: Habit,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let target = habit.cadence.target
        var streak = 0
        var cursor = now
        let maxLookback = 365 // hard cap to keep the loop bounded

        for _ in 0..<maxLookback {
            let count = completionsInPeriod(habit, containing: cursor, calendar: calendar)
            if count >= target {
                streak += 1
                // Step back one period
                guard let previous = steppedBackPeriod(
                    from: cursor, period: habit.cadence.period, calendar: calendar
                ) else { break }
                cursor = previous
            } else {
                break
            }
        }
        return streak
    }

    /// Move the cursor back by one period (1 day or 7 days).
    private static func steppedBackPeriod(
        from date: Date,
        period: HabitCadencePeriod,
        calendar: Calendar
    ) -> Date? {
        switch period {
        case .daily:
            return calendar.date(byAdding: .day, value: -1, to: date)
        case .weekly:
            return calendar.date(byAdding: .day, value: -7, to: date)
        }
    }

    // MARK: Target-hit rate

    /// Percentage of expected periods hit over the last `windowDays`.
    /// Returns 0.0–100.0. Used as the habit's alignment contribution.
    ///
    /// Example: a daily habit (target 1) over 14 days with 10 hits → ~71%.
    /// A 3×/week habit over 28 days = 4 weeks × target 3 = 12 expected; if
    /// the user completed 9, the rate is 75%.
    static func targetHitRate(
        _ habit: Habit,
        windowDays: Int = 30,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double {
        guard windowDays > 0 else { return 0 }
        let target = habit.cadence.target
        guard target > 0 else { return 0 }

        switch habit.cadence.period {
        case .daily:
            var hit = 0
            var total = 0
            for offset in 0..<windowDays {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
                let count = completionsInPeriod(habit, containing: day, calendar: calendar)
                total += 1
                if count >= target { hit += 1 }
            }
            return total > 0 ? (Double(hit) / Double(total)) * 100 : 0

        case .weekly:
            var hit = 0
            var total = 0
            // Walk week-by-week back from the current week
            var weekCursor = now
            let minDate = calendar.date(byAdding: .day, value: -windowDays, to: now) ?? now
            while weekCursor >= minDate {
                let count = completionsInPeriod(habit, containing: weekCursor, calendar: calendar)
                total += 1
                if count >= target { hit += 1 }
                guard let previous = calendar.date(byAdding: .day, value: -7, to: weekCursor) else { break }
                weekCursor = previous
            }
            return total > 0 ? (Double(hit) / Double(total)) * 100 : 0
        }
    }

    // MARK: Alignment contribution

    /// A habit's contribution to its parent goal/pillar's alignment score.
    /// For positive habits, this is the target-hit rate over a 30-day window.
    /// For negative habits (break a bad habit), a completion means a successful
    /// avoidance period, so the same calculation applies symmetrically.
    ///
    /// Returns 0–100.
    static func alignmentContribution(
        _ habit: Habit,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Double {
        guard habit.isActive else { return 0 }
        return targetHitRate(habit, windowDays: 30, now: now, calendar: calendar)
    }

    // MARK: Stagnation

    /// True when the habit has missed its cadence for at least `consecutiveMisses`
    /// periods in a row. Used by StagnationEngine to raise habit-level alerts.
    static func isStagnant(
        _ habit: Habit,
        consecutiveMisses: Int = 3,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard habit.isActive, consecutiveMisses > 0 else { return false }
        let target = habit.cadence.target

        var misses = 0
        var cursor = now
        // Skip today's period if it isn't over yet for daily habits — missing
        // "today" before the day is over isn't really stagnation.
        // For simplicity we always start the check from today/this-week; if it
        // was hit, streak is already > 0 and we return false immediately.
        for _ in 0..<consecutiveMisses {
            let count = completionsInPeriod(habit, containing: cursor, calendar: calendar)
            if count < target {
                misses += 1
            } else {
                return false
            }
            guard let previous = steppedBackPeriod(
                from: cursor, period: habit.cadence.period, calendar: calendar
            ) else { break }
            cursor = previous
        }
        return misses >= consecutiveMisses
    }
}
