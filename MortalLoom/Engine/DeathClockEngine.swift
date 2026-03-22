import Foundation

enum DeathClockEngine {

    // MARK: - Life Expectancy Calculation

    struct LifeExpectancy: Sendable {
        let baseline: Double        // SSA actuarial baseline
        let genomeAdjusted: Double  // After genome adjustments
        let lifestyleAdjustment: Double // Total lifestyle year adjustment
        let total: Double           // Final life expectancy in years
    }

    struct DeathClockResult: Sendable {
        let deathDate: Date
        let lifeExpectancy: LifeExpectancy
        let ageYears: Int
        let yearsRemaining: Double
        let healthyYearsRemaining: Double
        let percentComplete: Double
    }

    struct Countdown: Sendable, Equatable {
        let expired: Bool
        let years: Int
        let months: Int
        let weeks: Int
        let days: Int
        let hours: Int
        let minutes: Int
        let seconds: Int
        let totalDays: Int
    }

    // SSA actuarial table (simplified, male/female baseline at current age)
    // Based on SSA Period Life Table 2021
    static func ssaBaseline(sex: BiologicalSex?, ageYears: Int) -> Double {
        // Simplified: average life expectancy at various ages
        // Male baseline ~76, Female baseline ~81, unspecified uses average ~78.5
        let base: Double
        switch sex {
        case .female: base = 81.0
        case .male: base = 76.0
        case nil: base = 78.5
        }
        // Conditional LE increases as you age (survived selection)
        let bonus: Double
        switch ageYears {
        case 0..<30: bonus = 0
        case 30..<40: bonus = 0.5
        case 40..<50: bonus = 1.0
        case 50..<60: bonus = 1.5
        case 60..<70: bonus = 2.5
        case 70..<80: bonus = 4.0
        case 80..<90: bonus = 6.0
        default: bonus = 8.0
        }
        return base + bonus
    }

    // Lifestyle adjustments (match PortOS constants.js exactly)
    static func lifestyleAdjustment(_ lifestyle: LifestyleData) -> Double {
        smokingImpact(lifestyle.smokingStatus)
        + exerciseImpact(lifestyle.exerciseMinutesPerWeek)
        + sleepImpact(lifestyle.sleepHoursPerNight)
        + dietImpact(lifestyle.dietQuality)
        + stressImpact(lifestyle.stressLevel)
        + bmiImpact(lifestyle.bmi)
    }

    static func calculate(birthDateStr: String, sex: BiologicalSex?, lifestyle: LifestyleData, now: Date = Date()) -> DeathClockResult? {
        guard let birthDate = dateFromString(birthDateStr) else { return nil }

        let ageYears = Calendar.current.dateComponents([.year], from: birthDate, to: now).year ?? 0
        let ageFraction = now.timeIntervalSince(birthDate) / (365.25 * 24 * 3600)

        let baseline = ssaBaseline(sex: sex, ageYears: ageYears)
        let lifestyleAdj = lifestyleAdjustment(lifestyle)
        let total = baseline + lifestyleAdj

        let le = LifeExpectancy(
            baseline: baseline,
            genomeAdjusted: baseline, // TODO: add genome adjustment
            lifestyleAdjustment: lifestyleAdj,
            total: total
        )

        let deathDate = Calendar.current.date(byAdding: .day, value: Int((total - ageFraction) * 365.25), to: now) ?? now
        let yearsRemaining = max(0, total - ageFraction)
        let healthyYearsRemaining = max(0, yearsRemaining - 10) // Rough estimate: last 10 years may have declining health
        let percentComplete = min(100, (ageFraction / total) * 100)

        return DeathClockResult(
            deathDate: deathDate,
            lifeExpectancy: le,
            ageYears: ageYears,
            yearsRemaining: (yearsRemaining * 10).rounded() / 10,
            healthyYearsRemaining: (healthyYearsRemaining * 10).rounded() / 10,
            percentComplete: (percentComplete * 10).rounded() / 10
        )
    }

    // MARK: - Live Countdown

    static func countdown(to deathDate: Date, from now: Date = Date()) -> Countdown {
        let diff = deathDate.timeIntervalSince(now)

        if diff <= 0 {
            return Countdown(expired: true, years: 0, months: 0, weeks: 0, days: 0, hours: 0, minutes: 0, seconds: 0, totalDays: 0)
        }

        let totalSeconds = Int(diff)
        let totalMinutes = totalSeconds / 60
        let totalHours = totalMinutes / 60
        let totalDays = totalHours / 24

        let years = Int(Double(totalDays) / 365.25)
        let remainingDaysAfterYears = totalDays - Int(Double(years) * 365.25)
        let months = Int(Double(remainingDaysAfterYears) / 30.44)
        let remainingDaysAfterMonths = remainingDaysAfterYears - Int(Double(months) * 30.44)
        let weeks = remainingDaysAfterMonths / 7
        let days = remainingDaysAfterMonths - weeks * 7
        let hours = totalHours % 24
        let minutes = totalMinutes % 60
        let seconds = totalSeconds % 60

        return Countdown(
            expired: false,
            years: years, months: months, weeks: weeks, days: days,
            hours: hours, minutes: minutes, seconds: seconds,
            totalDays: totalDays
        )
    }

    // MARK: - LEV (Longevity Escape Velocity)

    struct LEVResult: Sendable {
        let targetYear: Int        // 2045
        let ageAtLEV: Int
        let yearsToLEV: Int
        let researchProgress: Double  // 0-100
        let onTrack: Bool
        let adjustedLifeExpectancy: Double
    }

    static func calculateLEV(birthDateStr: String, lifeExpectancy: Double, now: Date = Date()) -> LEVResult? {
        guard let birthDate = dateFromString(birthDateStr) else { return nil }
        let birthYear = Calendar.current.component(.year, from: birthDate)
        let currentYear = Calendar.current.component(.year, from: now)
        let targetYear = 2045
        let ageAtLEV = targetYear - birthYear
        let yearsToLEV = max(0, targetYear - currentYear)

        // Research timeline 2000-2045
        let startYear = 2000
        let elapsed = Double(currentYear - startYear)
        let total = Double(targetYear - startYear)
        let progress = min(100, max(0, (elapsed / total) * 100))

        let onTrack = lifeExpectancy >= Double(ageAtLEV)

        return LEVResult(
            targetYear: targetYear,
            ageAtLEV: ageAtLEV,
            yearsToLEV: yearsToLEV,
            researchProgress: (progress * 10).rounded() / 10,
            onTrack: onTrack,
            adjustedLifeExpectancy: lifeExpectancy
        )
    }

    // MARK: - Alcohol Risk

    enum AlcoholRisk: String, Sendable {
        case low, moderate, high
    }

    static func alcoholRisk(drinks: [AlcoholDrink], sex: BiologicalSex?) -> AlcoholRisk {
        let today = todayString()
        let todayDrinks = drinks.filter { $0.date == today }
        let todayStd = todayDrinks.reduce(0.0) { $0 + $1.standardDrinks }

        let dailyMax: Double = (sex == .female) ? 1 : 2
        let weeklyMax: Double = (sex == .female) ? 7 : 14

        // Weekly total
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let weekStr = dateString(weekAgo)
        let weekDrinks = drinks.filter { $0.date >= weekStr }
        let weeklyStd = weekDrinks.reduce(0.0) { $0 + $1.standardDrinks }

        if todayStd > dailyMax * 2 || weeklyStd > weeklyMax * 1.5 { return .high }
        if todayStd > dailyMax || weeklyStd > weeklyMax { return .moderate }
        return .low
    }

    // MARK: - Helpers (delegate to shared DateFormatting)

    static func todayString() -> String { DateFormatting.todayString() }
    static func dateString(_ date: Date) -> String { DateFormatting.dateString(date) }
    static func dateFromString(_ str: String) -> Date? { DateFormatting.dateFromString(str) }

    // MARK: - Per-Factor Impact (used by LifestyleView impact preview)

    static func smokingImpact(_ status: SmokingStatus) -> Double {
        switch status { case .never: 0; case .former: -2; case .current: -10 }
    }

    static func exerciseImpact(_ minutes: Int) -> Double {
        if minutes > 150 { return 2 } else if minutes >= 75 { return 0.5 } else { return -2 }
    }

    static func sleepImpact(_ hours: Double) -> Double {
        if hours >= 7 && hours <= 9 { return 1 } else if hours >= 6 { return 0 } else { return -1.5 }
    }

    static func dietImpact(_ quality: DietQuality) -> Double {
        switch quality { case .excellent: 2; case .good: 0.5; case .fair: 0; case .poor: -3 }
    }

    static func stressImpact(_ level: StressLevel) -> Double {
        switch level { case .low: 1; case .moderate: 0; case .high: -2 }
    }

    static func bmiImpact(_ bmi: Double?) -> Double {
        guard let bmi else { return 0 }
        if bmi >= 18.5 && bmi < 25 { return 0.5 }
        else if bmi >= 25 && bmi < 30 { return -0.5 }
        else if bmi >= 30 { return -3 }
        return 0
    }

    // MARK: - Health Score (0-100)

    /// Composite health score based on available metrics.
    /// Weighted factors scored out of 100. A healthy 46-year-old with
    /// good lifestyle and +2yr adjustment should score in the mid-80s.
    static func healthScore(
        lifestyle: LifestyleData,
        ageYears: Int,
        latestEpigeneticTest: EpigeneticTest?,
        alcoholRisk: AlcoholRisk
    ) -> Double {
        var score = 0.0
        var weight = 0.0

        // Lifestyle factors (max 40 pts)
        let lifestyleMax = 40.0
        weight += lifestyleMax
        var lifestylePts = lifestyleMax
        switch lifestyle.smokingStatus {
        case .never: break
        case .former: lifestylePts -= 8
        case .current: lifestylePts -= 30
        }
        // 150+ is the recommendation threshold — full credit at 150
        if lifestyle.exerciseMinutesPerWeek >= 150 { /* full */ }
        else if lifestyle.exerciseMinutesPerWeek >= 75 { lifestylePts -= 3 }
        else { lifestylePts -= 10 }
        if lifestyle.sleepHoursPerNight >= 7 && lifestyle.sleepHoursPerNight <= 9 { /* full */ }
        else if lifestyle.sleepHoursPerNight >= 6 { lifestylePts -= 2 }
        else { lifestylePts -= 6 }
        switch lifestyle.dietQuality {
        case .excellent: break
        case .good: lifestylePts -= 1
        case .fair: lifestylePts -= 5
        case .poor: lifestylePts -= 12
        }
        switch lifestyle.stressLevel {
        case .low: break
        case .moderate: lifestylePts -= 1
        case .high: lifestylePts -= 8
        }
        score += max(0, lifestylePts)

        // BMI (max 15 pts) — no data = exclude from scoring
        let bmiMax = 15.0
        if let bmi = lifestyle.bmi {
            weight += bmiMax
            if bmi >= 18.5 && bmi < 25 { score += bmiMax }
            else if bmi >= 25 && bmi < 30 { score += bmiMax * 0.7 }
            else if bmi >= 30 && bmi < 35 { score += bmiMax * 0.4 }
            else { score += bmiMax * 0.2 }
        }

        // Alcohol risk (max 15 pts)
        let alcoholMax = 15.0
        weight += alcoholMax
        switch alcoholRisk {
        case .low: score += alcoholMax
        case .moderate: score += alcoholMax * 0.6
        case .high: score += alcoholMax * 0.2
        }

        // Epigenetic pace of aging (max 20 pts)
        let epiMax = 20.0
        if let latest = latestEpigeneticTest,
           let pace = latest.paceOfAging {
            weight += epiMax
            // 1.0 = aging at normal rate (should be ~80% credit, not a harsh penalty)
            // < 0.85 = excellent, 0.85-1.0 = great, 1.0-1.1 = normal, > 1.1 = concerning
            if pace < 0.85 { score += epiMax }
            else if pace <= 1.0 { score += epiMax * (0.95 - (pace - 0.85) * 0.5) }
            else if pace <= 1.15 { score += epiMax * (0.75 - (pace - 1.0) * 2.0) }
            else { score += epiMax * 0.3 }
        }
        // No epigenetic data — just exclude from scoring

        // Age-based natural decline — only penalize meaningfully after 60
        let agePenalty: Double
        if ageYears < 50 { agePenalty = 0 }
        else if ageYears < 65 { agePenalty = Double(ageYears - 50) * 0.2 }
        else if ageYears < 80 { agePenalty = 3.0 + Double(ageYears - 65) * 0.4 }
        else { agePenalty = 9.0 + Double(ageYears - 80) * 0.6 }

        let raw = (score / max(1, weight)) * 100.0 - agePenalty
        return min(100, max(5, (raw * 10).rounded() / 10))
    }
}
