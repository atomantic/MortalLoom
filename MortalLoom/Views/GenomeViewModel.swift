import SwiftUI

/// Owns the Genome screen's data loading, scan orchestration, ClinVar sync,
/// genome-action state, and the filter/priority derivation the three tabs
/// render. Extracted from `GenomeView` (issue #24) so each tab —
/// `EpigeneticAgeView`, `GenomeScanView`, `ClinVarView` — is pure presentation
/// and the application-layer coordination (genome-file parse, curated marker
/// scan, ClinVar match, priority ranking, and the genome-action/visit-note
/// persistence) lives in one place the views simply bind to.
///
/// Declared `@MainActor @Observable final class` to match the project's
/// service-object pattern (`AppearanceManager`, `HealthKitService`,
/// `ICloudMonitor`) and the sibling `OverviewViewModel` (#23) — the "no
/// classes" convention is for the data/engine layer; observable coordinators
/// are the established exception.
///
/// This is the *structural* extraction only. The scan-cancellation race on
/// rapid re-import is tracked separately in the perf issue (#30); moving the
/// orchestration here doesn't change its threading.
@MainActor
@Observable
final class GenomeViewModel {
    // MARK: - Epigenetic age
    private(set) var epigeneticTests: [EpigeneticTest] = []
    private(set) var sortedEpigeneticTests: [EpigeneticTest] = []

    // MARK: - Genome upload
    private(set) var genomeVariants: [GenomeVariant] = []
    private(set) var allGenomeVariants: [GenomeVariant] = []
    private(set) var totalVariantCount: Int = 0
    private(set) var genomeBuild: String?
    var importError: String?

    // MARK: - Marker scan
    private(set) var scanSummary: GenomeScanSummary?
    private(set) var isScanning = false
    var expandedCategories: Set<MarkerCategory> = []
    var showNotFound = false

    // MARK: - Sex filter
    private(set) var sexFilter: SexFilter = .all
    private var hasInitializedSexFilter = false

    // MARK: - ClinVar
    private(set) var clinvarHits: [ClinVarHit] = []
    private(set) var clinvarStatus: ClinVarService.SyncStatus = ClinVarService.SyncStatus(synced: false)
    private(set) var isSyncingClinVar = false
    private(set) var clinvarProgress: String = ""
    var clinvarError: String?
    var minimumStars: Int = 4
    var themeDisplayLimits: [ClinVarTheme: Int] = [:]
    var expandedThemes: Set<ClinVarTheme> = []

    // MARK: - Detail sheet + action state
    /// The finding whose detail sheet/inspector is currently presented. Set by
    /// row taps in the tabs and resolved asynchronously after a scan finishes
    /// (see `tryResolvePendingFinding`) — lives here, not in the view, so a
    /// cold-launch `.openGenomeFinding` tap-back can open the right finding
    /// once data lands.
    var selectedFinding: PriorityFindingSource?
    private(set) var actionStates: [String: GenomeActionState] = [:]
    private(set) var visitNotes: [VisitNote] = []
    private(set) var allGoals: [Goal] = []
    private(set) var allHabits: [Habit] = []

    // MARK: - Bridge presentations
    var pendingHabitTemplate: HabitTemplate?
    private(set) var pendingHabitEvidence: GeneticEvidence?
    var pendingGoalTemplate: GoalTemplate?
    private(set) var pendingGoalEvidence: GeneticEvidence?

    /// rsid / findingKey requested via `.openGenomeFinding` (banner tap-back
    /// from a Habit/Goal edit sheet) before this view's scan data loaded.
    /// Resolved at the end of `load()`/scan completion so a cold-launch
    /// tap-back still opens the right finding.
    private var pendingFindingKey: String?

    // MARK: - Priority engine output
    private(set) var topPriorities: [PriorityFinding] = []
    private(set) var totalPriorityCandidates: Int = 0
    private(set) var lifestyle: LifestyleData?

    static let themePageSize = 20

    // MARK: - Derived ClinVar grouping

    var filteredClinvarHits: [ClinVarHit] {
        let hiddenThemes = sexFilter.hiddenClinVarThemes
        return clinvarHits.filter { hit in
            (minimumStars == 0 || hit.entry.reviewStars >= minimumStars)
                && !hiddenThemes.contains(GenomeEngine.classifyTheme(hit))
        }
    }

    var clinvarGrouped: [(theme: ClinVarTheme, hits: [ClinVarHit])] {
        GenomeEngine.groupByTheme(filteredClinvarHits)
    }

    // MARK: - Data Loading

    func load() async {
        let data = await DataStore.shared.getData()
        epigeneticTests = data.epigeneticTests
        sortedEpigeneticTests = data.epigeneticTests.sorted(by: { $0.date > $1.date })
        actionStates = data.genomeActionStates
        visitNotes = data.genomeVisitNotes
        allGoals = data.goals
        allHabits = data.habits
        lifestyle = data.profile.lifestyle
        recomputePriorities()

        // Default sex filter from profile on first load
        if !hasInitializedSexFilter, let sex = data.profile.biologicalSex {
            hasInitializedSexFilter = true
            sexFilter = sex == .male ? .male : .female
        }

        // Restore genome variants from persisted file (survives app updates + syncs via iCloud)
        if allGenomeVariants.isEmpty, let rawContent = await DataStore.shared.loadGenomeFile() {
            let parseResult = await Task.detached(priority: .userInitiated) {
                GenomeParser.parse(rawContent)
            }.value
            if !parseResult.variants.isEmpty {
                totalVariantCount = parseResult.variants.count
                genomeBuild = parseResult.build
                allGenomeVariants = parseResult.variants
                genomeVariants = Array(parseResult.variants.prefix(1000))
                runMarkerScan()
            }
        }
    }

    // MARK: - Filters

    func setSexFilter(_ filter: SexFilter) {
        sexFilter = filter
        themeDisplayLimits = [:]
        recomputePriorities()
    }

    func toggleMinimumStars(_ star: Int) {
        minimumStars = minimumStars == star ? 0 : star
        themeDisplayLimits = [:]
    }

    // MARK: - Priorities

    func recomputePriorities() {
        guard let summary = scanSummary else {
            topPriorities = []
            totalPriorityCandidates = 0
            return
        }
        // Apply the same sex filter the category browse uses, so priorities
        // never surface findings that don't apply (e.g. breast/ovarian on a
        // male profile).
        let hiddenCategories = sexFilter.hiddenMarkerCategories
        let hiddenThemes = sexFilter.hiddenClinVarThemes
        let filteredSummary = GenomeScanSummary(
            markerResults: summary.markerResults.filter { !hiddenCategories.contains($0.marker.category) },
            apoeResult: summary.apoeResult,
            scannedAt: summary.scannedAt,
            statusCounts: summary.statusCounts
        )
        let filteredClinvar = clinvarHits.filter { !hiddenThemes.contains(GenomeEngine.classifyTheme($0)) }

        topPriorities = GenomePriorityEngine.rank(
            summary: filteredSummary,
            clinvarHits: filteredClinvar,
            library: GenomeActionLibrary.all,
            states: actionStates,
            lifestyle: lifestyle
        )
        var total = 0
        for r in filteredSummary.markerResults where r.status != .notFound && r.status != .typical {
            total += 1
        }
        if let a = summary.apoeResult, a.status != .typical { total += 1 }
        for h in filteredClinvar where ["pathogenic", "risk_factor", "drug_response"].contains(h.entry.severity) {
            total += 1
        }
        totalPriorityCandidates = total
    }

    func actionsForFinding(_ finding: PriorityFindingSource) -> [GenomeAction] {
        GenomePriorityEngine.actions(for: finding)
    }

    // MARK: - Finding resolution

    /// Look up a `PriorityFindingSource` by `findingKey` (rsid or
    /// "<rsid>:<condition>") across the loaded scan + ClinVar data so the
    /// `.openGenomeFinding` notification can open the correct detail sheet.
    func resolveFinding(forKey key: String) -> PriorityFindingSource? {
        if key == "apoe", let apoe = scanSummary?.apoeResult {
            return .apoe(apoe)
        }
        if let marker = scanSummary?.markerResults.first(where: { $0.marker.rsid == key }) {
            return .marker(marker)
        }
        if let hit = clinvarHits.first(where: { hit in
            let candidate = PriorityFindingSource.clinvar(hit).findingKey
            return candidate == key || hit.rsid == key
        }) {
            return .clinvar(hit)
        }
        return nil
    }

    /// Record a deferred `.openGenomeFinding` request and try to satisfy it
    /// immediately; falls back to resolving it once scan/ClinVar data lands.
    func requestFinding(forKey key: String) {
        if let finding = resolveFinding(forKey: key) {
            selectedFinding = finding
        } else {
            pendingFindingKey = key
        }
    }

    /// Try to satisfy a deferred `.openGenomeFinding` request now that more
    /// scan/ClinVar data is available. Clears the pending key on success.
    private func tryResolvePendingFinding() {
        guard let key = pendingFindingKey,
              let finding = resolveFinding(forKey: key) else { return }
        pendingFindingKey = nil
        selectedFinding = finding
    }

    // MARK: - Bridge handling

    func handleBridge(finding: PriorityFindingSource, action: GenomeAction, bridge: GenomeActionBridge) {
        let evidence = GeneticEvidence(
            rsid: finding.findingKey,
            gene: geneLabel(for: finding),
            reason: action.detail,
            actionId: action.id
        )
        switch bridge {
        case .habitTemplate(let template):
            pendingHabitEvidence = evidence
            pendingHabitTemplate = template
        case .goalTemplate(let template):
            pendingGoalEvidence = evidence
            pendingGoalTemplate = template
        case .bloodMarkerKey:
            markActionStatus(finding: finding, action: action, status: .inProgress)
            selectedFinding = nil
            NotificationCenter.default.post(name: .navigateToPage, object: AppPage.blood)
        case .lifestyleField:
            markActionStatus(finding: finding, action: action, status: .inProgress)
            selectedFinding = nil
            NotificationCenter.default.post(name: .navigateToPage, object: AppPage.lifestyle)
        case .external(let url):
            #if os(iOS)
            UIApplication.shared.open(url)
            #elseif os(macOS)
            NSWorkspace.shared.open(url)
            #endif
        }
    }

    private func geneLabel(for finding: PriorityFindingSource) -> String {
        switch finding {
        case .marker(let r): r.marker.gene
        case .clinvar(let h): h.entry.gene.isEmpty ? h.rsid : h.entry.gene
        case .apoe(let a): "APOE \(a.haplotype)"
        }
    }

    func prefilledHabit(from template: HabitTemplate) -> Habit {
        Habit(
            name: template.title,
            detail: template.detail,
            icon: template.icon,
            colorHex: "#4C8BF5",
            category: template.category,
            kind: template.kind,
            cadence: template.cadence
        )
    }

    func prefilledGoal(from template: GoalTemplate) -> Goal {
        Goal(
            title: template.title,
            notes: template.notes,
            horizon: template.horizon,
            category: template.category,
            goalType: .standard
        )
    }

    /// Persist a habit created from a genome-action bridge, link it to the
    /// originating evidence, and reload.
    func completeHabitBridge(_ newHabit: Habit) async {
        await DataStore.shared.addHabit(newHabit)
        if let evidence = pendingHabitEvidence {
            await DataStore.shared.setGenomeActionStatus(
                rsid: evidence.rsid,
                actionId: evidence.actionId,
                status: .inProgress,
                linkedHabitId: newHabit.id
            )
        }
        pendingHabitEvidence = nil
        await load()
    }

    /// Persist a goal created from a genome-action bridge, link it to the
    /// originating evidence, and reload.
    func completeGoalBridge(_ newGoal: Goal) async {
        await DataStore.shared.addGoal(newGoal)
        if let evidence = pendingGoalEvidence {
            await DataStore.shared.setGenomeActionStatus(
                rsid: evidence.rsid,
                actionId: evidence.actionId,
                status: .inProgress,
                linkedGoalId: newGoal.id
            )
        }
        pendingGoalEvidence = nil
        await load()
    }

    func linkedHabits(for finding: PriorityFindingSource) -> [Habit] {
        let key = finding.findingKey
        return allHabits.filter { $0.geneticEvidence?.rsid == key && $0.isActive }
    }

    func linkedGoals(for finding: PriorityFindingSource) -> [Goal] {
        let key = finding.findingKey
        return allGoals.filter { $0.geneticEvidence?.rsid == key && $0.status == .active }
    }

    // MARK: - Action status mutations

    func markActionStatus(finding: PriorityFindingSource, action: GenomeAction, status: GenomeActionStatus) {
        Task {
            await DataStore.shared.setGenomeActionStatus(
                rsid: finding.findingKey,
                actionId: action.id,
                status: status
            )
            await load()
        }
    }

    func snoozeAllActions(for finding: PriorityFindingSource) {
        Task {
            for action in actionsForFinding(finding) {
                await DataStore.shared.setGenomeActionStatus(
                    rsid: finding.findingKey,
                    actionId: action.id,
                    status: .snoozed
                )
            }
            selectedFinding = nil
            await load()
        }
    }

    func dismissAllActions(for finding: PriorityFindingSource) {
        Task {
            for action in actionsForFinding(finding) {
                await DataStore.shared.setGenomeActionStatus(
                    rsid: finding.findingKey,
                    actionId: action.id,
                    status: .dismissed
                )
            }
            selectedFinding = nil
            await load()
        }
    }

    // MARK: - Epigenetic test + visit note persistence

    func addEpigeneticTest(_ test: EpigeneticTest) async {
        await DataStore.shared.addEpigeneticTest(test)
        await load()
    }

    func removeEpigeneticTest(id: UUID) async {
        await DataStore.shared.removeEpigeneticTest(id: id)
        await load()
    }

    func addVisitNote(_ note: VisitNote) async {
        await DataStore.shared.addVisitNote(note)
        await load()
    }

    // MARK: - File Import

    func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importError = "Could not access the selected file. Check file permissions."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                importError = "Could not read file: \(error.localizedDescription)"
                return
            }

            if GenomeParser.isZipFile(data) {
                importError = "This appears to be a .zip file. Please extract it first, then import the .txt file inside."
                return
            }

            guard let content = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .ascii) else {
                importError = "Could not decode file contents. Expected a UTF-8 text file."
                return
            }

            // Strip BOM if present
            let cleaned = content.hasPrefix("\u{FEFF}") ? String(content.dropFirst()) : content

            let parseResult = GenomeParser.parse(cleaned)

            if parseResult.variants.isEmpty {
                importError = "No valid variants found. Expected tab-separated 23andMe or AncestryDNA format with rsID, chromosome, position, and genotype columns."
            } else {
                totalVariantCount = parseResult.variants.count
                genomeBuild = parseResult.build
                allGenomeVariants = parseResult.variants
                genomeVariants = Array(parseResult.variants.prefix(1000))
                importError = nil
                Task.detached(priority: .background) {
                    await DataStore.shared.saveGenomeFile(cleaned)
                }
                runMarkerScan()
            }

        case .failure(let error):
            importError = "Failed to select file: \(error.localizedDescription)"
        }
    }

    // MARK: - Marker Scan Logic

    private func runMarkerScan() {
        isScanning = true
        scanSummary = nil
        expandedCategories = []

        let variants = allGenomeVariants
        let markers = GenomeEngine.allCuratedMarkers
        Task.detached(priority: .userInitiated) {
            let summary = GenomeEngine.fullScan(variants: variants, markers: markers)
            let record = GenomeScanRecord.from(summary)
            await DataStore.shared.saveGenomeScanRecord(record)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.scanSummary = summary
                    self.isScanning = false
                }
                self.recomputePriorities()
                self.tryResolvePendingFinding()
                self.runClinVarScan()
            }
        }
    }

    // MARK: - ClinVar Logic

    func loadClinVarStatus() {
        clinvarStatus = ClinVarService.getStatus()
        if clinvarStatus.synced {
            runClinVarScan()
        }
    }

    private func runClinVarScan() {
        guard !allGenomeVariants.isEmpty else { return }
        guard let index = ClinVarService.loadIndex() else { return }

        let variants = allGenomeVariants
        Task.detached(priority: .userInitiated) {
            let hits = GenomeEngine.scanClinVar(variants: variants, index: index)
            await MainActor.run {
                withAnimation {
                    self.clinvarHits = hits
                    self.clinvarStatus = ClinVarService.getStatus()
                }
                self.recomputePriorities()
                self.tryResolvePendingFinding()
            }
        }
    }

    func syncClinVar() {
        isSyncingClinVar = true
        clinvarError = nil
        clinvarProgress = ""

        Task {
            do {
                let status = try await ClinVarService.syncClinVar { progress in
                    Task { @MainActor in
                        self.clinvarProgress = progress
                    }
                }
                await MainActor.run {
                    self.clinvarStatus = status
                    self.isSyncingClinVar = false
                    self.runClinVarScan()
                }
            } catch {
                await MainActor.run {
                    self.clinvarError = "ClinVar sync failed: \(error.localizedDescription)"
                    self.isSyncingClinVar = false
                }
            }
        }
    }
}
