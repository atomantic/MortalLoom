import SwiftUI

/// Owns the Overview screen's data loading and the multi-engine orchestration
/// that derives every cached value the view renders. Extracted from
/// `OverviewView` (issue #23) so the view is pure presentation and the
/// application-layer coordination — DeathClock / Sleep / Recommendation /
/// Stagnation / Goal engines plus the async genome scan and the local
/// notification reconcile — lives in one place the view simply binds to.
///
/// Declared `@MainActor @Observable final class` to match the project's
/// service-object pattern (`AppearanceManager`, `HealthKitService`,
/// `ICloudMonitor`) — the "no classes" convention is for the data/engine
/// layer; observable coordinators are the established exception.
///
/// This is the *structural* extraction only. Threading/perf of these engine
/// calls (they still run synchronously on the main actor) is tracked
/// separately in the perf issue (#31) — moving them here doesn't change when
/// or on which thread they run.
@MainActor
@Observable
final class OverviewViewModel {
    /// A point on one of the lifetime health trajectories. `id` is precomputed
    /// (year, offset for the LEV series) so `Chart`/`ForEach` don't hash on the
    /// fly in the render path.
    struct TrajectoryPoint: Identifiable {
        let year: Int
        let health: Double
        let series: TrajectorySeries
        let id: Int
    }

    enum TrajectorySeries: String { case normal = "Expected", lev = "LEV" }

    // Loaded application data.
    private(set) var data: AppData = .empty

    // Death-clock / LEV results.
    private(set) var deathClock: DeathClockEngine.DeathClockResult?
    private(set) var levDeathClock: DeathClockEngine.DeathClockResult?
    private(set) var lev: DeathClockEngine.LEVResult?
    private(set) var countdownMode: CountdownMode = .standard

    // Date strings, refreshed on each recalculate so a day boundary crossed
    // while the app was backgrounded is reflected on the next data load.
    private(set) var todayStr: String = DateFormatting.todayString()
    private(set) var weekAgoStr: String = DateFormatting.dateString(daysAgo: 7)

    // Pre-sorted arrays to avoid sorting in the render path.
    private(set) var sortedBloodTests: [BloodTest] = []
    private(set) var sortedEpigeneticTests: [EpigeneticTest] = []
    private(set) var sortedEyeExams: [EyeExam] = []

    // Cached derived values — recomputed in recalculate(), not on every render.
    private(set) var cachedAlcoholRisk: AlcoholRisk = .low
    private(set) var cachedHealthScore: Double = 0
    private(set) var cachedNormalPoints: [TrajectoryPoint] = []
    private(set) var cachedLevPoints: [TrajectoryPoint] = []
    private(set) var cachedRecommendations: [RecommendationEngine.Recommendation] = []
    /// Top genome priorities used to seed DNA-derived recommendations alongside
    /// the lifestyle ones. Computed lazily off the main thread by parsing the
    /// persisted genome file and re-running the curated marker scan + ClinVar
    /// match. Empty until that work finishes — `recalculate()` re-runs the
    /// recommendation engine once it lands.
    private(set) var cachedGenomePriorities: [PriorityFinding] = []
    private(set) var cachedSleepImpact: Double = 0
    private(set) var cachedStagnationSignals: [StagnationSignal] = []
    private(set) var cachedReflectionStreak: Int = 0
    private(set) var cachedApexAlignment: Double?

    /// Guards against re-running the genome scan on every recalculate(); only
    /// resets when the underlying scan record changes (or the user clears it).
    private var lastScannedAt: Date?

    // MARK: - Derived convenience

    var apexGoal: Goal? { data.goals.activeApex }
    var activeGoalCount: Int { data.goals.activeCount }

    /// The death-clock result the UI should currently surface — the LEV
    /// variant when the user has switched the countdown to LEV mode, otherwise
    /// the standard estimate.
    var activeDC: DeathClockEngine.DeathClockResult? {
        if countdownMode == .lev, let levDC = levDeathClock { return levDC }
        return deathClock
    }

    // MARK: - Data Loading

    /// Loads the latest app data, refreshes the pre-sorted arrays, and re-runs
    /// the engine orchestration. The single entry point the view's `.task` and
    /// sync/profile-change handlers call.
    func load() async {
        let loaded = await DataStore.shared.getData()
        data = loaded
        sortedBloodTests = loaded.bloodTests.sorted(by: { $0.date > $1.date })
        sortedEpigeneticTests = loaded.epigeneticTests.sorted(by: { $0.date > $1.date })
        sortedEyeExams = loaded.eyeExams.sorted(by: { $0.date > $1.date })
        recalculate()
    }

    private func recalculate() {
        todayStr = DateFormatting.todayString()
        weekAgoStr = DateFormatting.dateString(daysAgo: 7)

        guard let birthDate = data.profile.birthDate else {
            deathClock = nil
            levDeathClock = nil
            lev = nil
            return
        }
        countdownMode = data.profile.countdownMode
        let sleepStages = SleepEngine.stageBreakdown(metrics: data.healthMetrics)
        deathClock = DeathClockEngine.calculate(
            birthDateStr: birthDate,
            sex: data.profile.biologicalSex,
            lifestyle: data.profile.lifestyle,
            genome: data.genomeScanRecord,
            sleepStages: sleepStages,
            locationProfile: data.profile.locationProfile,
            socioeconomic: data.profile.socioeconomic,
            healthMetrics: data.healthMetrics
        )
        cachedSleepImpact = SleepEngine.enhancedLongevityImpact(
            averageHours: data.profile.lifestyle.sleepHoursPerNight,
            stageBreakdown: sleepStages
        )
        cachedAlcoholRisk = DeathClockEngine.alcoholRisk(drinks: data.alcoholDrinks, sex: data.profile.biologicalSex)
        cachedRecommendations = RecommendationEngine.generate(
            lifestyle: data.profile.lifestyle,
            alcoholRisk: cachedAlcoholRisk,
            hasGenomeData: data.genomeScanRecord != nil,
            hasEpigeneticData: !data.epigeneticTests.isEmpty,
            hasBloodTests: !data.bloodTests.isEmpty,
            genomePriorities: cachedGenomePriorities
        )
        Task { await loadGenomePrioritiesIfNeeded() }
        cachedStagnationSignals = StagnationEngine.signals(
            goals: data.goals,
            habits: data.habits,
            deathDate: deathClock?.deathDate,
            healthyCognitiveDate: GoalEngine.cognitiveDeadline(from: deathClock)
        )
        cachedReflectionStreak = apexGoal.map { GoalEngine.dailyReflectionStreak(for: $0) } ?? 0
        cachedApexAlignment = apexGoal.flatMap {
            GoalEngine.alignmentScore(for: $0, in: data.goals, habits: data.habits)
        }
        // Reconcile local notifications against the latest signals so the
        // user isn't nagged about stagnation that no longer exists.
        let signalsSnapshot = cachedStagnationSignals
        Task { @MainActor in
            await NotificationService.shared.reconcileStagnationAlerts(signalsSnapshot)
        }
        if let dc = deathClock {
            levDeathClock = DeathClockEngine.calculateLEVResult(standardResult: dc, birthDateStr: birthDate, levTargetAge: data.profile.levTargetAge)
            lev = DeathClockEngine.calculateLEV(
                birthDateStr: birthDate,
                lifeExpectancy: dc.lifeExpectancy.total
            )
            recomputeChartData(dc)
        }
    }

    private func recomputeChartData(_ dc: DeathClockEngine.DeathClockResult) {
        let currentYear = Calendar.current.component(.year, from: Date())
        let birthYear = currentYear - dc.ageYears
        let deathYear = birthYear + Int(dc.lifeExpectancy.total)
        let levYear = DeathClockEngine.Constants.levTargetYear
        let levDeathYear = birthYear + Int(DeathClockEngine.Constants.levTargetAge)

        cachedHealthScore = DeathClockEngine.healthScore(
            lifestyle: data.profile.lifestyle,
            ageYears: dc.ageYears,
            latestEpigeneticTest: sortedEpigeneticTests.first,
            alcoholRisk: cachedAlcoholRisk,
            healthMetrics: data.healthMetrics
        )

        cachedNormalPoints = normalTrajectory(currentYear: currentYear, deathYear: deathYear, currentHealth: cachedHealthScore)
        cachedLevPoints = levTrajectory(currentYear: currentYear, levYear: levYear, levDeathYear: levDeathYear, currentHealth: cachedHealthScore, normalPoints: cachedNormalPoints)
    }

    /// Refresh the cached genome priorities by reading the persisted genome
    /// file and re-running the curated marker scan + ClinVar match (when an
    /// index is already on disk). Skips entirely when the user has no scan
    /// record. Once finished, replays the recommendation engine so DNA-derived
    /// recs surface alongside the lifestyle ones.
    private func loadGenomePrioritiesIfNeeded() async {
        guard let record = data.genomeScanRecord else {
            // User cleared their genome data — drop any stale priorities.
            if !cachedGenomePriorities.isEmpty {
                cachedGenomePriorities = []
                replayLifestyleRecs()
            }
            lastScannedAt = nil
            return
        }
        // Skip the scan if we already have priorities for this exact record.
        // The scan record updates only when the user re-runs the marker scan,
        // so a matching `scannedAt` means our cache is current.
        if lastScannedAt == record.scannedAt, !cachedGenomePriorities.isEmpty { return }

        guard let rawContent = await DataStore.shared.loadGenomeFile() else { return }
        let actionStates = data.genomeActionStates
        let lifestyle = data.profile.lifestyle
        let priorities: [PriorityFinding] = await Task.detached(priority: .utility) {
            let parsed = GenomeParser.parse(rawContent)
            guard !parsed.variants.isEmpty else { return [] }
            let summary = GenomeEngine.fullScan(
                variants: parsed.variants,
                markers: GenomeEngine.allCuratedMarkers
            )
            let clinvarHits: [ClinVarHit] = {
                guard let index = ClinVarService.loadIndex() else { return [] }
                return GenomeEngine.scanClinVar(variants: parsed.variants, index: index)
            }()
            return GenomePriorityEngine.rank(
                summary: summary,
                clinvarHits: clinvarHits,
                library: GenomeActionLibrary.all,
                states: actionStates,
                lifestyle: lifestyle
            )
        }.value

        cachedGenomePriorities = priorities
        lastScannedAt = record.scannedAt
        replayLifestyleRecs()
    }

    /// Re-run `RecommendationEngine.generate` after the genome priorities
    /// change so the DNA-derived recommendations land in the same list as the
    /// lifestyle ones (and resort by years gained).
    private func replayLifestyleRecs() {
        cachedRecommendations = RecommendationEngine.generate(
            lifestyle: data.profile.lifestyle,
            alcoholRisk: cachedAlcoholRisk,
            hasGenomeData: data.genomeScanRecord != nil,
            hasEpigeneticData: !data.epigeneticTests.isEmpty,
            hasBloodTests: !data.bloodTests.isEmpty,
            genomePriorities: cachedGenomePriorities
        )
    }

    // MARK: - Trajectory math

    /// Now → LE: flat/improving for ~10 years, gentle decline mid-life, steeper only in final 5 years
    private func normalTrajectory(currentYear: Int, deathYear: Int, currentHealth: Double) -> [TrajectoryPoint] {
        var points: [TrajectoryPoint] = []
        // Three phases: improvement (10yr), slow decline, steep final (5yr)
        let improvementEndYear = currentYear + 10
        let steepDeclineYear = deathYear - 5
        let peakHealth = min(95, currentHealth + 5) // slight improvement from active health work
        // Health at start of steep decline — gradual loss over the middle years
        let atSteepStart = peakHealth * 0.55

        for year in stride(from: currentYear, through: deathYear, by: 1) {
            let health: Double
            if year <= improvementEndYear {
                // Flat to slightly improving — active health optimization
                let t = Double(year - currentYear) / Double(max(1, improvementEndYear - currentYear))
                health = currentHealth + (peakHealth - currentHealth) * t
            } else if year <= steepDeclineYear {
                // Gradual age-related decline
                let t = Double(year - improvementEndYear) / Double(max(1, steepDeclineYear - improvementEndYear))
                health = peakHealth + (atSteepStart - peakHealth) * t
            } else {
                // Steep final decline
                let t = Double(year - steepDeclineYear) / Double(max(1, deathYear - steepDeclineYear))
                health = atSteepStart * (1.0 - t * t)
            }
            points.append(TrajectoryPoint(year: year, health: max(0, health), series: .normal, id: year))
        }
        return points
    }

    /// Same as normal until LEV year, then therapies maintain/improve health far longer
    private func levTrajectory(currentYear: Int, levYear: Int, levDeathYear: Int, currentHealth: Double, normalPoints: [TrajectoryPoint]) -> [TrajectoryPoint] {
        var points: [TrajectoryPoint] = []
        // Find health at LEV year from normal trajectory
        let healthAtLEV = normalPoints.first(where: { $0.year == levYear })?.health ?? currentHealth
        let peakHealth = min(98, healthAtLEV + 8) // LEV therapies recover + improve
        let declineStart = levDeathYear - 10

        for year in stride(from: levYear, through: levDeathYear, by: 1) {
            let health: Double
            let yearsAfterLEV = Double(year - levYear)
            let rampUpYears = 10.0 // takes ~10 years for full LEV therapies to kick in
            if yearsAfterLEV <= rampUpYears {
                // Recovery and improvement as therapies take effect
                let t = yearsAfterLEV / rampUpYears
                health = healthAtLEV + (peakHealth - healthAtLEV) * t
            } else if year <= declineStart {
                // Maintained near-peak with very slow aging
                let t = Double(year - levYear - Int(rampUpYears)) / Double(max(1, declineStart - levYear - Int(rampUpYears)))
                health = peakHealth - (peakHealth * 0.08 * t)
            } else {
                // Gentle decline at end
                let t = Double(year - declineStart) / Double(max(1, levDeathYear - declineStart))
                let atDecline = peakHealth * 0.92
                health = atDecline * (1.0 - 0.6 * t * t)
            }
            points.append(TrajectoryPoint(year: year, health: max(0, health), series: .lev, id: year + 10000))
        }
        return points
    }
}
