import Foundation

/// Date-only history uses the Gregorian calendar in the user's local time
/// zone. Calendar arithmetic (not 24-hour offsets) preserves DST boundaries.
enum ReviewHistory {
    static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func dayFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        // A real day can begin after midnight during a DST change. The
        // round-trip in parseDay still rejects invalid or rolled-over dates.
        formatter.isLenient = true
        return formatter
    }

    /// Imported logs can contain unusually large positive counts.
    static func adding(_ count: Int, to total: Int) -> Int {
        let (sum, overflow) = total.addingReportingOverflow(count)
        return overflow ? Int.max : sum
    }

    static func parseDay(_ value: String, formatter: DateFormatter) -> Date? {
        guard let date = formatter.date(from: value),
              formatter.string(from: date) == value else { return nil }
        return date
    }
}

enum HabitStreakCalendar {
    struct Period: Identifiable, Equatable {
        let start: Date
        let count: Int
        let target: Int
        let isTracked: Bool

        var id: Date { start }
        var meetsTarget: Bool { isTracked && count >= target }
    }

    /// Daily and weekly habits use different cells. Weekly cells are Monday
    /// anchored, so three entries in one week can meet a three-per-week target.
    static func periods(for habit: Habit, now: Date = Date(),
                        calendar: Calendar = ReviewHistory.calendar()) -> [Period] {
        let formatter = ReviewHistory.dayFormatter(calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let todayKey = formatter.string(from: today)
        let weekly = habit.cadence.period == .weekly
        func start(_ date: Date) -> Date {
            weekly ? HabitEngine.startOfWeek(date, calendar: calendar) : calendar.startOfDay(for: date)
        }
        let current = start(today)
        let count = weekly ? 16 : 42
        let step = weekly ? 7 : 1
        let starts = (0..<count).reversed().compactMap {
            // Some local DST transitions skip midnight itself. Normalize
            // each date so an offset from a 1 a.m. start still matches logs.
            calendar.date(byAdding: .day, value: -$0 * step, to: current).map(start)
        }
        guard let earliest = starts.first else { return [] }
        let earliestKey = formatter.string(from: earliest)
        let created = ReviewHistory.parseDay(habit.createdDate, formatter: formatter)
        let archived = habit.archivedDate.flatMap { ReviewHistory.parseDay($0, formatter: formatter) }
        let createdPeriod = created.map(start)
        let archivedPeriod = archived.map(start)
        var counts: [Date: Int] = [:]
        for entry in habit.completions where entry.count > 0 && entry.date >= earliestKey && entry.date <= todayKey {
            guard let date = ReviewHistory.parseDay(entry.date, formatter: formatter),
                  created.map({ date >= $0 }) ?? true,
                  archived.map({ date <= $0 }) ?? true else { continue }
            let key = start(date)
            counts[key] = ReviewHistory.adding(entry.count, to: counts[key, default: 0])
        }
        return starts.map { date in
            Period(start: date, count: counts[date, default: 0], target: max(1, habit.cadence.target),
                   isTracked: (createdPeriod.map { date >= $0 } ?? true)
                       && (archivedPeriod.map { date <= $0 } ?? true))
        }
    }
}

enum YearlyReviewEngine {
    static func availableYears(from data: AppData, now: Date = Date(),
                               calendar: Calendar = ReviewHistory.calendar()) -> [Int] {
        let formatter = ReviewHistory.dayFormatter(calendar: calendar)
        let today = calendar.startOfDay(for: now)
        var years: Set<Int> = [calendar.component(.year, from: today)]
        func include(_ key: String) {
            if let day = ReviewHistory.parseDay(key, formatter: formatter), day <= today {
                years.insert(calendar.component(.year, from: day))
            }
        }
        for goal in data.goals {
            include(goal.createdDate)
            if let completedDate = goal.completedDate { include(completedDate) }
            for entry in goal.checkIns { include(entry.date) }
        }
        for habit in data.habits {
            for completion in habit.completions where completion.count > 0 { include(completion.date) }
        }
        return years.sorted(by: >)
    }

    /// Includes only historical facts from the selected calendar year. Today's
    /// progress/status and current streaks don't describe prior years.
    static func markdown(from data: AppData, year: Int, now: Date = Date(),
                         calendar: Calendar = ReviewHistory.calendar()) -> String {
        let formatter = ReviewHistory.dayFormatter(calendar: calendar)
        let today = calendar.startOfDay(for: now)
        func includes(_ key: String) -> Bool {
            guard let day = ReviewHistory.parseDay(key, formatter: formatter) else { return false }
            return day <= today && calendar.component(.year, from: day) == year
        }

        let goals = data.goals.map { goal in
            (goal: goal, entries: goal.checkIns.filter { includes($0.date) }.sorted { $0.date < $1.date })
        }
        let completed = goals.filter { $0.goal.completedDate.map(includes) ?? false }
        let created = goals.filter { includes($0.goal.createdDate) }
        let reflections = goals.flatMap { group in
            group.entries.filter(\.isReflection).map { (title: group.goal.title, entry: $0) }
        }.sorted { $0.entry.date < $1.entry.date }
        let checkIns = goals.reduce(0) { $0 + $1.entries.count }
        var lines = ["# Yearly Review — \(year)", ""]
        if year == calendar.component(.year, from: today) {
            lines += ["Year to date through \(formatter.string(from: today)).", ""]
        }
        lines += ["## Goals", "",
                  "- \(created.count) created · \(completed.count) completed · \(checkIns) check-ins"]
        for item in completed {
            if let date = item.goal.completedDate { lines.append("- Completed \(literal(item.goal.title)) on \(date)") }
        }
        for item in goals where !item.entries.isEmpty {
            let n = item.entries.count
            lines.append("- \(literal(item.goal.title)): \(n) check-in\(n == 1 ? "" : "s")")
        }

        lines += ["", "## Habits", ""]
        let habitLines = data.habits.compactMap { habit -> String? in
            let entries = habit.completions.filter { $0.count > 0 && includes($0.date) }
            guard !entries.isEmpty else { return nil }
            let total = entries.reduce(0) { ReviewHistory.adding($1.count, to: $0) }
            let days = Set(entries.map(\.date)).count
            return "- \(literal(habit.name)): \(total) completion\(total == 1 ? "" : "s") across \(days) day\(days == 1 ? "" : "s")"
        }
        lines += habitLines.isEmpty ? ["No habit completions recorded."] : habitLines

        lines += ["", "## Reflections", ""]
        if reflections.isEmpty { lines.append("No reflections recorded.") }
        for row in reflections {
            let entry = row.entry
            lines += ["### \(entry.date) · \(literal(row.title))", ""]
            if let rating = entry.alignmentRating { lines.append("- Alignment: \(rating)/10") }
            if let prompt = entry.promptAnswered, !prompt.isEmpty { lines.append("- Prompt: \(literal(prompt))") }
            if !entry.note.isEmpty { lines.append("- Note: \(literal(entry.note))") }
            for blocker in entry.blockers { lines.append("- Blocker: \(literal(blocker))") }
            for commitment in entry.commitments { lines.append("- Commitment: \(literal(commitment))") }
            lines.append("")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Render user-authored strings as text, not as Markdown headings, links,
    /// images or HTML that could access the network when the document opens.
    private static func literal(_ value: String) -> String {
        let punctuation = Set("\\`*_{}[]<>()#+-.!|~&")
        return value.split(whereSeparator: \.isNewline).joined(separator: " ").map {
            punctuation.contains($0) ? "\\\($0)" : String($0)
        }.joined()
    }
}
