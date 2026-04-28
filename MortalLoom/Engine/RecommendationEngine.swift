import Foundation

enum RecommendationEngine {

    struct Recommendation: Identifiable, Sendable {
        let id: String
        let icon: String
        let title: String
        let detail: String
        let yearsGained: Double
        let targetPage: Int // AppPage rawValue for navigation
        /// IDs from `CitationLibrary` documenting the peer-reviewed / authoritative
        /// source behind this recommendation. Rendered as a `CitationBadge` in the UI.
        let citationIds: [String]
    }

    /// Conservative `yearsGained` heuristics for genome-derived recommendations.
    /// Attenuated 0.7× before being added to the main list so they don't outrank
    /// measured-lifestyle items. Values intentionally low — we'd rather under-promise.
    private enum GenomeImpact {
        static let apoeE4Cardio: Double = 1.5
        static let apoeE4Sleep: Double = 0.6
        static let mthfrFolate: Double = 0.5
        static let factorVDoctor: Double = 0.8   // mostly catastrophe-avoidance, not lifespan
        static let hfeIron: Double = 0.7
        static let cad9p21Lipids: Double = 1.0
        static let inflammation: Double = 0.4
        static let pathogenic: Double = 0.6      // confirmation gives information value
        static let drugResponse: Double = 0.3
        static let `default`: Double = 0.4
    }

    /// Map a `GenomeAction` to its conservative years-gained heuristic.
    private static func yearsGainedForAction(_ action: GenomeAction) -> Double {
        switch action.id {
        case "apoe-e4-cardio", "apoe-e4-lipid-panel": GenomeImpact.apoeE4Cardio
        case "apoe-e4-sleep": GenomeImpact.apoeE4Sleep
        case "mthfr-c677t-homocysteine-panel", "mthfr-c677t-methylfolate",
             "mthfr-c677t-tt-doctor", "mthfr-a1298c-homocysteine-panel": GenomeImpact.mthfrFolate
        case "f5-leiden-flag-providers", "f5-leiden-tt-anticoag-consult": GenomeImpact.factorVDoctor
        case "hfe-c282y-iron-panel", "hfe-c282y-aa-hematology", "hfe-h63d-ferritin": GenomeImpact.hfeIron
        case "9p21-cad-cardio", "9p21-cad-lipid-panel": GenomeImpact.cad9p21Lipids
        case "il6-anti-inflammatory-diet", "il6-crp-monitor",
             "tnf-autoimmune-awareness": GenomeImpact.inflammation
        case "clinvar-pathogenic-confirm-clia",
             "clinvar-pathogenic-genetic-counselor": GenomeImpact.pathogenic
        case "clinvar-drug-pharmacist-handoff": GenomeImpact.drugResponse
        default: GenomeImpact.default
        }
    }

    /// Generate personalized recommendations based on current lifestyle and health data.
    /// Returns recommendations sorted by potential years gained (highest first).
    /// Only includes actionable items where there's room for improvement.
    ///
    /// `genomePriorities` (optional, default `[]`) injects up to 3 unaccepted DNA
    /// findings as recommendations alongside the lifestyle ones. Items already
    /// `inProgress` (linked to an existing habit/goal) are skipped to avoid
    /// double-prompting.
    static func generate(
        lifestyle: LifestyleData,
        alcoholRisk: AlcoholRisk,
        hasGenomeData: Bool,
        hasEpigeneticData: Bool,
        hasBloodTests: Bool,
        genomePriorities: [PriorityFinding] = []
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
                targetPage: 4, // lifestyle
                citationIds: [
                    CitationLibrary.dollSmoking2004.id,
                    CitationLibrary.jhaSmoking2013.id,
                ]
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
                targetPage: 4,
                citationIds: [
                    CitationLibrary.whoPhysicalActivity.id,
                    CitationLibrary.arem2015Exercise.id,
                ]
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
                targetPage: 4,
                citationIds: [
                    CitationLibrary.whoPhysicalActivity.id,
                    CitationLibrary.arem2015Exercise.id,
                ]
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
                    targetPage: 4,
                    citationIds: [
                        CitationLibrary.cappuccioSleep2010.id,
                        CitationLibrary.nsfSleepDuration.id,
                    ]
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
                targetPage: 4,
                citationIds: [
                    CitationLibrary.predimedMedDiet.id,
                    CitationLibrary.gbdDiet2019.id,
                ]
            ))
        case .fair:
            let gain = DeathClockEngine.dietImpact(.good) - DeathClockEngine.dietImpact(.fair)
            recs.append(Recommendation(
                id: "improve-diet",
                icon: "fork.knife",
                title: "Upgrade diet to Good",
                detail: "Small improvements — more vegetables, less processed food — add up.",
                yearsGained: gain,
                targetPage: 4,
                citationIds: [
                    CitationLibrary.predimedMedDiet.id,
                    CitationLibrary.gbdDiet2019.id,
                ]
            ))
        case .good:
            let gain = DeathClockEngine.dietImpact(.excellent) - DeathClockEngine.dietImpact(.good)
            recs.append(Recommendation(
                id: "improve-diet",
                icon: "fork.knife",
                title: "Aim for excellent diet",
                detail: "Mediterranean or plant-rich diets are linked to the highest longevity gains.",
                yearsGained: gain,
                targetPage: 4,
                citationIds: [
                    CitationLibrary.predimedMedDiet.id,
                    CitationLibrary.gbdDiet2019.id,
                ]
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
                targetPage: 4,
                citationIds: [
                    CitationLibrary.epelTelomere2004.id,
                    CitationLibrary.kivimakiStress2018.id,
                ]
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
                    targetPage: 4,
                    citationIds: [
                        CitationLibrary.epelTelomere2004.id,
                        CitationLibrary.kivimakiStress2018.id,
                    ]
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
                    targetPage: 1, // body
                    citationIds: [
                        CitationLibrary.whoBmi.id,
                        CitationLibrary.bmiMortality2016.id,
                    ]
                ))
            } else if bmi >= 25 {
                let gain = DeathClockEngine.bmiImpact(24.0) - DeathClockEngine.bmiImpact(bmi)
                recs.append(Recommendation(
                    id: "improve-bmi",
                    icon: "scalemass.fill",
                    title: "Optimize body composition",
                    detail: "BMI \(String(format: "%.1f", bmi)) is overweight. Targeting 18.5-25 removes the penalty.",
                    yearsGained: gain,
                    targetPage: 1,
                    citationIds: [
                        CitationLibrary.whoBmi.id,
                        CitationLibrary.bmiMortality2016.id,
                    ]
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
                targetPage: 12, // substances
                citationIds: [
                    CitationLibrary.niaaaLimits.id,
                    CitationLibrary.gbdAlcohol2018.id,
                ]
            ))
        case .moderate:
            recs.append(Recommendation(
                id: "reduce-alcohol",
                icon: "wineglass.fill",
                title: "Cut back on alcohol",
                detail: "Moderate risk — reducing to low-risk levels benefits heart and liver health.",
                yearsGained: 1.0,
                targetPage: 12, // substances
                citationIds: [
                    CitationLibrary.niaaaLimits.id,
                    CitationLibrary.gbdAlcohol2018.id,
                ]
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
                targetPage: 6, // genome
                citationIds: [
                    CitationLibrary.clinvar.id,
                    CitationLibrary.deelenApoe2019.id,
                ]
            ))
        }

        if !hasEpigeneticData {
            recs.append(Recommendation(
                id: "add-epigenetic",
                icon: "clock.badge.checkmark",
                title: "Add epigenetic test",
                detail: "Track your biological age vs chronological age with tests like TruDiagnostic or GrimAge.",
                yearsGained: 0,
                targetPage: 1, // body
                citationIds: [
                    CitationLibrary.horvathClock2013.id,
                    CitationLibrary.dunedinPace2022.id,
                ]
            ))
        }

        if !hasBloodTests {
            recs.append(Recommendation(
                id: "add-blood-test",
                icon: "drop.fill",
                title: "Log blood test results",
                detail: "Track 50+ biomarkers to catch issues early and monitor your health trajectory.",
                yearsGained: 0,
                targetPage: 2, // blood
                citationIds: [
                    CitationLibrary.clinicalLabRanges.id,
                ]
            ))
        }

        // Genome-derived recommendations — capped at 3, attenuated 0.7×, and
        // skipping any priority whose top action is already linked to a habit/goal.
        let attenuation = 0.7
        var genomeRecs: [Recommendation] = []
        for priority in genomePriorities {
            if genomeRecs.count >= 3 { break }
            guard let action = priority.topAction else { continue }
            // Skip findings where any action is already accepted (in_progress).
            if priority.stateCounts.inProgress > 0 { continue }
            let geneLabel: String = {
                switch priority.source {
                case .marker(let r): r.marker.gene
                case .clinvar(let h): h.entry.gene
                case .apoe(let a): "APOE \(a.haplotype)"
                }
            }()
            let yearsGained = yearsGainedForAction(action) * attenuation
            genomeRecs.append(Recommendation(
                id: "genome-\(action.id)",
                icon: action.kind.icon,
                title: action.title,
                detail: "Your DNA: \(geneLabel). \(action.detail)",
                yearsGained: yearsGained,
                targetPage: 6, // genome
                citationIds: action.citationIds
            ))
        }
        recs.append(contentsOf: genomeRecs)

        return recs.sorted { $0.yearsGained > $1.yearsGained }
    }
}
