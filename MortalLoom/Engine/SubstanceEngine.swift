import Foundation

// MARK: - Alcohol Risk Level

enum AlcoholRisk: String, Sendable {
    case low, moderate, high
}

// MARK: - SubstanceEngine

enum SubstanceEngine {

    // MARK: - Generic helpers

    /// Average per-day value across the entire history of an items collection.
    /// Each item must expose a `"YYYY-MM-DD"` date string and a numeric value.
    /// Returns 0 for an empty collection. Used by alcohol/nicotine/sauna stats
    /// to share the date-bucket arithmetic that previously appeared three times.
    static func allTimeAverage<T>(
        items: [T],
        date: KeyPath<T, String>,
        value: (T) -> Double,
        now: Date = Date()
    ) -> Double {
        guard !items.isEmpty else { return 0 }
        var earliest = items[0][keyPath: date]
        var total = 0.0
        for item in items {
            total += value(item)
            let d = item[keyPath: date]
            if d < earliest { earliest = d }
        }
        guard let firstDate = DateFormatting.dateFromString(earliest) else { return 0 }
        let dayCount = max(1, Calendar.current.dateComponents([.day], from: firstDate, to: now).day ?? 1)
        return total / Double(dayCount)
    }

    // MARK: - Alcohol

    static func rollingAverageGrams(drinks: [AlcoholDrink], days: Int, now: Date = Date()) -> Double {
        let cutoff = DateFormatting.dateString(daysAgo: days, from: now)
        let total = drinks.filter { $0.date >= cutoff }.reduce(0.0) { $0 + $1.gramsAlcohol }
        return total / Double(max(1, days))
    }

    static func weeklyTotalStandardDrinks(drinks: [AlcoholDrink], now: Date = Date()) -> Double {
        let cutoff = DateFormatting.dateString(daysAgo: 7, from: now)
        return drinks.filter { $0.date >= cutoff }.reduce(0.0) { $0 + $1.standardDrinks }
    }

    static func allTimeAverageGrams(drinks: [AlcoholDrink], now: Date = Date()) -> Double {
        allTimeAverage(items: drinks, date: \.date, value: { $0.gramsAlcohol }, now: now)
    }

    static func dailyMaxStandardDrinks(drinks: [AlcoholDrink], days: Int, now: Date = Date()) -> Double {
        let cutoff = DateFormatting.dateString(daysAgo: days, from: now)
        let recent = drinks.filter { $0.date >= cutoff }
        let grouped = Dictionary(grouping: recent, by: \.date)
        return grouped.values.map { dayDrinks in
            dayDrinks.reduce(0.0) { $0 + $1.standardDrinks }
        }.max() ?? 0
    }

    static func alcoholRisk(drinks: [AlcoholDrink], sex: BiologicalSex?, now: Date = Date()) -> AlcoholRisk {
        let cutoff = DateFormatting.dateString(daysAgo: 7, from: now)
        let recentDrinks = drinks.filter { $0.date >= cutoff }

        let weeklyStd = recentDrinks.reduce(0.0) { $0 + $1.standardDrinks }
        let grouped = Dictionary(grouping: recentDrinks, by: \.date)
        let dailyMax = grouped.values.map { dayDrinks in
            dayDrinks.reduce(0.0) { $0 + $1.standardDrinks }
        }.max() ?? 0

        let isFemale = sex == .female
        let dailyThreshold: Double = isFemale ? 1.0 : 2.0
        let weeklyThreshold: Double = isFemale ? 7.0 : 14.0

        if weeklyStd > weeklyThreshold || dailyMax > (dailyThreshold * 2) {
            return .high
        } else if weeklyStd > weeklyThreshold * 0.7 || dailyMax > dailyThreshold {
            return .moderate
        }
        return .low
    }

    // MARK: - Nicotine

    static func rollingAverageMg(entries: [NicotineEntry], days: Int, now: Date = Date()) -> Double {
        let cutoff = DateFormatting.dateString(daysAgo: days, from: now)
        let total = entries.filter { $0.date >= cutoff }.reduce(0.0) { $0 + $1.totalMg }
        return total / Double(max(1, days))
    }

    static func weeklyTotalMg(entries: [NicotineEntry], now: Date = Date()) -> Double {
        let cutoff = DateFormatting.dateString(daysAgo: 7, from: now)
        return entries.filter { $0.date >= cutoff }.reduce(0.0) { $0 + $1.totalMg }
    }

    static func allTimeAverageMg(entries: [NicotineEntry], now: Date = Date()) -> Double {
        allTimeAverage(items: entries, date: \.date, value: { $0.totalMg }, now: now)
    }

    // MARK: - Sauna

    static func rollingAverageMinutes(sessions: [SaunaSession], days: Int, now: Date = Date()) -> Double {
        let cutoff = DateFormatting.dateString(daysAgo: days, from: now)
        let total = sessions.filter { $0.date >= cutoff }.reduce(0) { $0 + $1.durationMinutes }
        return Double(total) / Double(max(1, days))
    }

    static func weeklyTotalMinutes(sessions: [SaunaSession], now: Date = Date()) -> Int {
        let cutoff = DateFormatting.dateString(daysAgo: 7, from: now)
        return sessions.filter { $0.date >= cutoff }.reduce(0) { $0 + $1.durationMinutes }
    }

    static func weeklySessionCount(sessions: [SaunaSession], now: Date = Date()) -> Int {
        let cutoff = DateFormatting.dateString(daysAgo: 7, from: now)
        return sessions.filter { $0.date >= cutoff }.count
    }

    static func allTimeAverageMinutes(sessions: [SaunaSession], now: Date = Date()) -> Double {
        allTimeAverage(items: sessions, date: \.date, value: { Double($0.durationMinutes) }, now: now)
    }
}
