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

    // MARK: - Genome Adjustment

    /// Category impact tiers for mortality-relevant genome markers.
    /// High-impact categories directly affect leading causes of death.
    /// Medium-impact categories contribute indirectly to mortality.
    /// Low-impact categories affect quality of life but have minimal mortality signal.
    private enum CategoryImpact {
        case high, medium, low

        static func forCategory(_ raw: String) -> CategoryImpact {
            switch raw {
            case "cardiovascular", "longevity", "diabetes",
                 "cognitive_decline", "tumor_suppression",
                 "cancer_breast", "cancer_prostate", "cancer_colorectal",
                 "cancer_lung", "cancer_melanoma", "cancer_bladder", "cancer_digestive":
                return .high
            case "inflammation", "autoimmune", "thyroid",
                 "methylation", "iron", "cognitive":
                return .medium
            default:
                return .low
            }
        }

        var beneficialWeight: Double {
            switch self { case .high: 0.15; case .medium: 0.1; case .low: 0.05 }
        }
        var concernWeight: Double {
            switch self { case .high: -0.2; case .medium: -0.15; case .low: -0.1 }
        }
        var majorConcernWeight: Double {
            switch self { case .high: -0.5; case .medium: -0.3; case .low: -0.15 }
        }
    }

    /// APOE-specific life expectancy adjustment (years).
    /// Based on published associations between APOE variants and all-cause mortality.
    private static func apoeAdjustment(haplotype: String?, status: GenomeMarkerStatus?) -> Double {
        guard let status else { return 0 }
        switch status {
        case .beneficial:    return 0.5   // ε2 carriers: modest longevity advantage
        case .typical:       return 0     // ε3/ε3: baseline
        case .concern:       return -1.5  // single ε4: elevated Alzheimer's + CVD risk
        case .majorConcern:  return -3.0  // ε4/ε4: substantial mortality impact
        case .notFound:      return 0
        }
    }

    /// Compute total genome-based life expectancy adjustment from a persisted scan record.
    /// Returns 0 when no genome data is available. Clamped to [-8, +4] years.
    static func genomeAdjustment(_ record: GenomeScanRecord?) -> Double {
        guard let record else { return 0 }

        var adjustment = 0.0

        for (category, risk) in record.categoryRisks {
            let impact = CategoryImpact.forCategory(category)
            adjustment += Double(risk.beneficial) * impact.beneficialWeight
            adjustment += Double(risk.concern) * impact.concernWeight
            adjustment += Double(risk.majorConcern) * impact.majorConcernWeight
            // typical markers contribute 0
        }

        adjustment += apoeAdjustment(haplotype: record.apoeHaplotype, status: record.apoeStatus)

        return min(4, max(-8, (adjustment * 10).rounded() / 10))
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

    static func calculate(birthDateStr: String, sex: BiologicalSex?, lifestyle: LifestyleData, genome: GenomeScanRecord? = nil, now: Date = Date()) -> DeathClockResult? {
        guard let birthDate = dateFromString(birthDateStr) else { return nil }

        let ageYears = Calendar.current.dateComponents([.year], from: birthDate, to: now).year ?? 0
        let ageFraction = now.timeIntervalSince(birthDate) / (365.25 * 24 * 3600)

        let baseline = ssaBaseline(sex: sex, ageYears: ageYears)
        let genomeAdj = genomeAdjustment(genome)
        let lifestyleAdj = lifestyleAdjustment(lifestyle)
        let total = baseline + genomeAdj + lifestyleAdj

        let le = LifeExpectancy(
            baseline: baseline,
            genomeAdjusted: baseline + genomeAdj,
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

    /// Calculate a LEV-extended death clock result (age 120 if on track for LEV).
    /// Accepts a pre-computed standard result to avoid duplicate calculation.
    static func calculateLEVResult(standardResult: DeathClockResult, birthDateStr: String, now: Date = Date()) -> DeathClockResult? {
        guard let birthDate = dateFromString(birthDateStr) else { return nil }

        let birthYear = Calendar.current.component(.year, from: birthDate)
        let ageAtLEV = 2045 - birthYear

        guard standardResult.lifeExpectancy.total >= Double(ageAtLEV) else { return nil }

        let levLE = 120.0
        let ageFraction = now.timeIntervalSince(birthDate) / (365.25 * 24 * 3600)
        let levDeathDate = Calendar.current.date(byAdding: .day, value: Int((levLE - ageFraction) * 365.25), to: now) ?? now
        let yearsRemaining = max(0, levLE - ageFraction)
        let healthyYearsRemaining = max(0, yearsRemaining - 5)
        let percentComplete = min(100, (ageFraction / levLE) * 100)

        let le = LifeExpectancy(
            baseline: standardResult.lifeExpectancy.baseline,
            genomeAdjusted: standardResult.lifeExpectancy.genomeAdjusted,
            lifestyleAdjustment: standardResult.lifeExpectancy.lifestyleAdjustment,
            total: levLE
        )

        return DeathClockResult(
            deathDate: levDeathDate,
            lifeExpectancy: le,
            ageYears: standardResult.ageYears,
            yearsRemaining: (yearsRemaining * 10).rounded() / 10,
            healthyYearsRemaining: (healthyYearsRemaining * 10).rounded() / 10,
            percentComplete: (percentComplete * 10).rounded() / 10
        )
    }

    // MARK: - Alcohol Risk (delegates to SubstanceEngine)

    static func alcoholRisk(drinks: [AlcoholDrink], sex: BiologicalSex?) -> AlcoholRisk {
        SubstanceEngine.alcoholRisk(drinks: drinks, sex: sex)
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

    // MARK: - Health Metrics Longevity Adjustment

    /// Additional life expectancy adjustment from Apple Health metrics.
    /// Returns years of life expectancy impact based on measured fitness data.
    static func healthMetricsAdjustment(_ metrics: [HealthMetricEntry], age: Int, sex: BiologicalSex?) -> Double {
        guard !metrics.isEmpty else { return 0 }
        var adj = 0.0

        // Cardio recovery impact
        let recoveries = metrics.compactMap(\.cardioRecovery)
        if !recoveries.isEmpty {
            let avgRecovery = recoveries.reduce(0, +) / Double(recoveries.count)
            adj += CardioFitnessEngine.recoveryLongevityImpact(avgRecovery)
        }

        // Walking speed / gait impact
        let speeds = metrics.compactMap(\.walkingSpeed)
        if !speeds.isEmpty {
            let avgSpeed = speeds.reduce(0, +) / Double(speeds.count)
            adj += GaitEngine.walkingSpeedLongevityImpact(avgSpeed, age: age)
        }

        // Breathing disturbances / apnea impact
        let bds = metrics.compactMap(\.breathingDisturbances)
        if !bds.isEmpty {
            let avgBD = bds.reduce(0, +) / Double(bds.count)
            adj += SleepEngine.apneaLongevityImpact(avgBD)
        }

        // Cap the total health metrics adjustment to reasonable bounds
        return min(4, max(-6, (adj * 10).rounded() / 10))
    }

    // MARK: - Health Score (0-100)

    /// Composite health score based on available metrics.
    /// Weighted factors scored out of 100. A healthy 46-year-old with
    /// good lifestyle and +2yr adjustment should score in the mid-80s.
    static func healthScore(
        lifestyle: LifestyleData,
        ageYears: Int,
        latestEpigeneticTest: EpigeneticTest?,
        alcoholRisk: AlcoholRisk,
        healthMetrics: [HealthMetricEntry] = []
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
            if pace < 0.85 { score += epiMax }
            else if pace <= 1.0 { score += epiMax * (0.95 - (pace - 0.85) * 0.5) }
            else if pace <= 1.15 { score += epiMax * (0.75 - (pace - 1.0) * 2.0) }
            else { score += epiMax * 0.3 }
        }

        // Cardio recovery (max 10 pts) — when measured
        let cardioMax = 10.0
        let recoveries = healthMetrics.compactMap(\.cardioRecovery)
        if !recoveries.isEmpty {
            let avgRecovery = recoveries.reduce(0, +) / Double(recoveries.count)
            weight += cardioMax
            let level = CardioFitnessEngine.classifyRecovery(avgRecovery)
            switch level {
            case .excellent: score += cardioMax
            case .good: score += cardioMax * 0.8
            case .normal: score += cardioMax * 0.6
            case .belowNormal: score += cardioMax * 0.3
            case .abnormal: score += cardioMax * 0.1
            }
        }

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
