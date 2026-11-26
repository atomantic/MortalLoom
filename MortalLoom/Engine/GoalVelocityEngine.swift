import Foundation

/// Normalizes self-reported progress changes to percentage points per week
/// so intervals of different lengths can be compared without inventing data.
enum GoalVelocityEngine {
    struct Interval: Identifiable, Equatable {
        let start: Date
        let end: Date
        let pointsPerWeek: Double
        var id: Date { end }
    }

    struct Series: Identifiable {
        let id: UUID
        let title: String
        let intervals: [Interval]
    }

    static func series(goals: [Goal], now: Date = Date()) -> [Series] {
        // Progress is only meaningful for standard goals, including older goals
        // without an explicit type. Retain the history of completed goals.
        goals.compactMap { goal in
            guard goal.goalType == nil || goal.goalType == .standard else { return nil }
            let points = intervals(checkIns: goal.checkIns, now: now)
            guard !points.isEmpty else { return nil }
            return Series(id: goal.id, title: goal.title, intervals: points)
        }
        .sorted {
            if $0.intervals.last?.end != $1.intervals.last?.end {
                return ($0.intervals.last?.end ?? .distantPast) > ($1.intervals.last?.end ?? .distantPast)
            }
            let titleOrder = $0.title.localizedStandardCompare($1.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func intervals(checkIns: [GoalCheckIn], now: Date = Date()) -> [Interval] {
        // Date-only records follow local calendar days, not elapsed 24-hour
        // chunks (which would mismeasure intervals around DST changes).
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: now)
        var daily: [Date: Double] = [:]
        for checkIn in checkIns where checkIn.progressPct.isFinite {
            guard let date = DateFormatting.dateFromString(checkIn.date),
                  DateFormatting.dateString(date) == checkIn.date,
                  date <= today else { continue }
            // Edits/additions append to the saved array. The last reading for
            // each day wins; multiple readings that day cannot define a rate.
            daily[date] = min(100, max(0, checkIn.progressPct))
        }
        let dates = daily.keys.sorted().suffix(13)
        return zip(dates, dates.dropFirst()).compactMap { start, end in
            guard let days = calendar.dateComponents([.day], from: start, to: end).day,
                  days > 0, let previous = daily[start], let current = daily[end] else { return nil }
            return Interval(start: start, end: end, pointsPerWeek: (current - previous) * 7 / Double(days))
        }
    }
}
