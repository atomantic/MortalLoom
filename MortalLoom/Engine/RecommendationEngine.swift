import Foundation

enum RecommendationEngine {

    struct Recommendation: Identifiable, Sendable {
        let id: String
        let icon: String
        let title: String
        let detail: String
        let yearsGained: Double
        let targetPage: Int // AppPage rawValue for navigation
    }

    /// Generate personalized recommendations based on current lifestyle and health data.
    /// Returns recommendations sorted by potential years gained (highest first).
    /// Only includes actionable items where there's room for improvement.
    static func generate(
        lifestyle: LifestyleData,
        alcoholRisk: AlcoholRisk,
        hasGenomeData: Bool,
        hasEpigeneticData: Bool,
        hasBloodTests: Bool
    ) -> [Recommendation] {
        var recs: [Recommendation] = []

        // Smoking — biggest single factor
        switch lifestyle.smokingStatus {
        case .current:
            recs.append(Recommendation(
                id: "quit-smoking",
                icon: "nosign",
                title: "Quit Smoking",
                detail: "Quitting could add up to 10 years. Even becoming a former smoker gains +8 years over current.",
                yearsGained: 10.0,
                targetPage: 4 // lifestyle
            ))
        case .former:
            // Already quit — no further action, but acknowledge
            break
        case .never:
            break
        }

        // Exercise
        if lifestyle.exerciseMinutesPerWeek < 75 {
            let currentImpact = DeathClockEngine.exerciseImpact(lifestyle.exerciseMinutesPerWeek)
            let targetImpact = DeathClockEngine.exerciseImpact(151)
            let gain = targetImpact - currentImpact
            recs.append(Recommendation(
                id: "increase-exercise",
                icon: "figure.run",
                title: "Exercise 150+ min/week",
                detail: "You're at \(lifestyle.exerciseMinutesPerWeek) min/week. Reaching 150 meets WHO guidelines.",
                yearsGained: gain,
                targetPage: 4
            ))
        } else if lifestyle.exerciseMinutesPerWeek < 150 {
            let currentImpact = DeathClockEngine.exerciseImpact(lifestyle.exerciseMinutesPerWeek)
            let targetImpact = DeathClockEngine.exerciseImpact(151)
            let gain = targetImpact - currentImpact
            recs.append(Recommendation(
                id: "increase-exercise",
                icon: "figure.run",
                title: "Reach 150 min/week",
                detail: "You're at \(lifestyle.exerciseMinutesPerWeek) min/week — close to the WHO target.",
                yearsGained: gain,
                targetPage: 4
            ))
        }

        // Sleep
        let sleepH = lifestyle.sleepHoursPerNight
        if sleepH < 7 || sleepH > 9 {
            let currentImpact = DeathClockEngine.sleepImpact(sleepH)
            let optimalImpact = DeathClockEngine.sleepImpact(7.5)
            let gain = optimalImpact - currentImpact
            if gain > 0 {
                let direction = sleepH < 7 ? "more" : "less"
                recs.append(Recommendation(
                    id: "optimize-sleep",
                    icon: "bed.double.fill",
                    title: "Get 7-9 hours of sleep",
                    detail: "At \(String(format: "%.1f", sleepH))h/night, try sleeping \(direction). Optimal is 7-9 hours.",
                    yearsGained: gain,
                    targetPage: 4
                ))
            }
        }

        // Diet
        switch lifestyle.dietQuality {
        case .poor:
            let gain = DeathClockEngine.dietImpact(.good) - DeathClockEngine.dietImpact(.poor)
            recs.append(Recommendation(
                id: "improve-diet",
                icon: "fork.knife",
                title: "Improve your diet",
                detail: "Moving from poor to good diet quality adds years. Focus on whole foods and vegetables.",
                yearsGained: gain,
                targetPage: 4
            ))
        case .fair:
            let gain = DeathClockEngine.dietImpact(.good) - DeathClockEngine.dietImpact(.fair)
            recs.append(Recommendation(
                id: "improve-diet",
                icon: "fork.knife",
                title: "Upgrade diet to Good",
                detail: "Small improvements — more vegetables, less processed food — add up.",
                yearsGained: gain,
                targetPage: 4
            ))
        case .good:
            let gain = DeathClockEngine.dietImpact(.excellent) - DeathClockEngine.dietImpact(.good)
            recs.append(Recommendation(
                id: "improve-diet",
                icon: "fork.knife",
                title: "Aim for excellent diet",
                detail: "Mediterranean or plant-rich diets are linked to the highest longevity gains.",
                yearsGained: gain,
                targetPage: 4
            ))
        case .excellent:
            break
        }

        // Stress
        switch lifestyle.stressLevel {
        case .high:
            let gain = DeathClockEngine.stressImpact(.low) - DeathClockEngine.stressImpact(.high)
            recs.append(Recommendation(
                id: "reduce-stress",
                icon: "brain.head.profile",
                title: "Reduce stress levels",
                detail: "Chronic stress shortens telomeres. Meditation, exercise, and sleep all help.",
                yearsGained: gain,
                targetPage: 4
            ))
        case .moderate:
            let gain = DeathClockEngine.stressImpact(.low) - DeathClockEngine.stressImpact(.moderate)
            if gain > 0 {
                recs.append(Recommendation(
                    id: "reduce-stress",
                    icon: "brain.head.profile",
                    title: "Lower stress to low",
                    detail: "Even moderate stress has a cost. Regular mindfulness practice can help.",
                    yearsGained: gain,
                    targetPage: 4
                ))
            }
        case .low:
            break
        }

        // BMI
        if let bmi = lifestyle.bmi {
            if bmi >= 30 {
                let gain = DeathClockEngine.bmiImpact(24.0) - DeathClockEngine.bmiImpact(bmi)
                recs.append(Recommendation(
                    id: "improve-bmi",
                    icon: "scalemass.fill",
                    title: "Reach a healthy BMI",
                    detail: "BMI \(String(format: "%.1f", bmi)) is in the obese range. Even small reductions improve outcomes.",
                    yearsGained: gain,
                    targetPage: 1 // body
                ))
            } else if bmi >= 25 {
                let gain = DeathClockEngine.bmiImpact(24.0) - DeathClockEngine.bmiImpact(bmi)
                recs.append(Recommendation(
                    id: "improve-bmi",
                    icon: "scalemass.fill",
                    title: "Optimize body composition",
                    detail: "BMI \(String(format: "%.1f", bmi)) is overweight. Targeting 18.5-25 removes the penalty.",
                    yearsGained: gain,
                    targetPage: 1
                ))
            }
        }

        // Alcohol
        switch alcoholRisk {
        case .high:
            recs.append(Recommendation(
                id: "reduce-alcohol",
                icon: "wineglass.fill",
                title: "Reduce alcohol intake",
                detail: "High-risk drinking significantly impacts longevity. Aim for NIAAA low-risk limits.",
                yearsGained: 2.0,
                targetPage: 3 // habits
            ))
        case .moderate:
            recs.append(Recommendation(
                id: "reduce-alcohol",
                icon: "wineglass.fill",
                title: "Cut back on alcohol",
                detail: "Moderate risk — reducing to low-risk levels benefits heart and liver health.",
                yearsGained: 1.0,
                targetPage: 3
            ))
        case .low:
            break
        }

        // Data completeness recommendations
        if !hasGenomeData {
            recs.append(Recommendation(
                id: "upload-genome",
                icon: "dna",
                title: "Upload genome data",
                detail: "Import 23andMe or AncestryDNA results to refine your life expectancy with genetic risk factors.",
                yearsGained: 0,
                targetPage: 6 // genome
            ))
        }

        if !hasEpigeneticData {
            recs.append(Recommendation(
                id: "add-epigenetic",
                icon: "clock.badge.checkmark",
                title: "Add epigenetic test",
                detail: "Track your biological age vs chronological age with tests like TruDiagnostic or GrimAge.",
                yearsGained: 0,
                targetPage: 1 // body
            ))
        }

        if !hasBloodTests {
            recs.append(Recommendation(
                id: "add-blood-test",
                icon: "drop.fill",
                title: "Log blood test results",
                detail: "Track 50+ biomarkers to catch issues early and monitor your health trajectory.",
                yearsGained: 0,
                targetPage: 2 // blood
            ))
        }

        return recs.sorted { $0.yearsGained > $1.yearsGained }
    }
}
