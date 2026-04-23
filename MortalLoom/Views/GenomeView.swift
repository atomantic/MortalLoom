import SwiftUI
import UniformTypeIdentifiers

// MARK: - GenomeView

private enum GenomeTab: String, CaseIterable {
    case bioAge = "Bio Age"
    case genome = "Genome"
    case clinvar = "ClinVar"
}

private enum SexFilter: String, CaseIterable {
    case all = "All"
    case female = "Female"
    case male = "Male"

    /// Categories hidden when this filter is active
    var hiddenMarkerCategories: Set<MarkerCategory> {
        switch self {
        case .all: []
        case .female: [.cancerProstate]
        case .male: [.cancerBreast]
        }
    }

    /// ClinVar themes hidden when this filter is active
    var hiddenClinVarThemes: Set<ClinVarTheme> {
        switch self {
        case .all: []
        case .female: [.cancerProstate]
        case .male: [.cancerBreast]
        }
    }
}

struct GenomeView: View {
    @State private var activeTab: GenomeTab = .bioAge
    @State private var epigeneticTests: [EpigeneticTest] = []
    @State private var sortedEpigeneticTests: [EpigeneticTest] = []
    @State private var showingAddTest = false
    @State private var isLoading = true

    // Genome upload
    @State private var genomeVariants: [GenomeVariant] = []
    @State private var allGenomeVariants: [GenomeVariant] = []
    @State private var totalVariantCount: Int = 0
    @State private var genomeBuild: String?
    @State private var showingFileImporter = false
    @State private var importError: String?

    // Marker scan
    @State private var scanSummary: GenomeScanSummary?
    @State private var isScanning = false
    @State private var expandedCategories: Set<MarkerCategory> = []
    @State private var expandedMarkers: Set<String> = []
    @State private var showNotFound = false

    // Sex filter
    @State private var sexFilter: SexFilter = .all
    @State private var hasInitializedSexFilter = false

    // ClinVar
    @State private var clinvarHits: [ClinVarHit] = []
    @State private var clinvarStatus: ClinVarService.SyncStatus = ClinVarService.SyncStatus(synced: false)
    @State private var isSyncingClinVar = false
    @State private var clinvarProgress: String = ""
    @State private var clinvarError: String?
    @State private var expandedThemes: Set<ClinVarTheme> = []
    @State private var minimumStars: Int = 4
    @State private var themeDisplayLimits: [ClinVarTheme: Int] = [:]

    // Detail sheet + action state
    @State private var selectedFinding: GenomeFinding?
    @State private var actionStates: [String: GenomeActionState] = [:]
    @State private var visitNotes: [VisitNote] = []
    @State private var allGoals: [Goal] = []
    @State private var allHabits: [Habit] = []

    // Bridge presentations
    @State private var pendingHabitTemplate: HabitTemplate?
    @State private var pendingHabitEvidence: GeneticEvidence?
    @State private var pendingVisitNoteFinding: GenomeFinding?
    @State private var navigationPage: AppPage?

    private static let themePageSize = 20

    private var filteredClinvarHits: [ClinVarHit] {
        let hiddenThemes = sexFilter.hiddenClinVarThemes
        return clinvarHits.filter { hit in
            (minimumStars == 0 || hit.entry.reviewStars >= minimumStars)
                && !hiddenThemes.contains(GenomeEngine.classifyTheme(hit))
        }
    }

    private var clinvarGrouped: [(theme: ClinVarTheme, hits: [ClinVarHit])] {
        GenomeEngine.groupByTheme(filteredClinvarHits)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $activeTab) {
                ForEach(GenomeTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.bgCard)

            ScrollView {
                VStack(spacing: 16) {
                    switch activeTab {
                    case .bioAge:
                        epigeneticAgeSection
                    case .genome:
                        genomeUploadSection
                        if !genomeVariants.isEmpty {
                            if isScanning { scanningIndicator }
                            if let summary = scanSummary {
                                apoeSection(summary.apoeResult)
                                markerSummaryBar(summary)
                                markerCategoryCards(summary)
                            }
                        }
                    case .clinvar:
                        clinvarSection
                    }
                }
                .padding()
            }
        }
        .background(Color.bg)
        .proGated()
        .sheet(isPresented: $showingAddTest) {
            EpigeneticTestFormView(onSave: { test in
                Task {
                    await DataStore.shared.addEpigeneticTest(test)
                    await loadData()
                }
            })
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.plainText, .commaSeparatedText, .tabSeparatedText, .text, .data, .item],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(item: $selectedFinding) { finding in
            NavigationStack {
                GenomeDetailSheet(
                    finding: finding,
                    actionStates: actionStates,
                    visitNotes: visitNotes,
                    linkedHabits: linkedHabits(for: finding),
                    linkedGoals: linkedGoals(for: finding),
                    embedded: false,
                    onBridge: { action, bridge in handleBridge(finding: finding, action: action, bridge: bridge) },
                    onMarkDiscussed: { action in markActionStatus(finding: finding, action: action, status: .discussed) },
                    onMarkDone: { action in markActionStatus(finding: finding, action: action, status: .done) },
                    onSnooze: { snoozeAllActions(for: finding) },
                    onDismiss: { dismissAllActions(for: finding) },
                    onAddVisitNote: { _ in pendingVisitNoteFinding = finding },
                    onCloseSheet: { selectedFinding = nil }
                )
            }
            .presentationDetents([.large])
        }
        .sheet(item: $pendingHabitTemplate) { template in
            HabitEditSheet(
                habit: prefilledHabit(from: template),
                goals: allGoals,
                prefillEvidence: pendingHabitEvidence
            ) { newHabit in
                Task {
                    await DataStore.shared.addHabit(newHabit)
                    if let evidence = pendingHabitEvidence {
                        await DataStore.shared.setGenomeActionStatus(
                            rsid: evidence.rsid == "apoe" ? "apoe" : evidence.rsid,
                            actionId: evidence.actionId,
                            status: .inProgress,
                            linkedHabitId: newHabit.id
                        )
                    }
                    pendingHabitEvidence = nil
                    await loadData()
                }
            }
        }
        .sheet(item: $pendingVisitNoteFinding) { finding in
            VisitNoteSheet(finding: finding) { note in
                Task {
                    await DataStore.shared.addVisitNote(note)
                    await loadData()
                }
            }
        }
        .task { await loadData() }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidSync)) { _ in
            Task { await loadData() }
        }
    }

    // MARK: - Bridge handling

    private func handleBridge(finding: GenomeFinding, action: GenomeAction, bridge: GenomeActionBridge) {
        let evidence = GeneticEvidence(
            rsid: finding.lookupRsid,
            gene: geneLabel(for: finding),
            reason: action.detail,
            actionId: action.id
        )
        switch bridge {
        case .habitTemplate(let template):
            pendingHabitEvidence = evidence
            pendingHabitTemplate = template
        case .goalTemplate:
            // Goal flow lands in a follow-up phase — for now, just acknowledge
            // the action so the user gets a clear outcome.
            markActionStatus(finding: finding, action: action, status: .inProgress)
        case .bloodMarkerKey:
            markActionStatus(finding: finding, action: action, status: .inProgress)
            navigationPage = .blood
            selectedFinding = nil
        case .lifestyleField:
            markActionStatus(finding: finding, action: action, status: .inProgress)
            navigationPage = .lifestyle
            selectedFinding = nil
        case .external(let url):
            #if os(iOS)
            UIApplication.shared.open(url)
            #elseif os(macOS)
            NSWorkspace.shared.open(url)
            #endif
        }
    }

    private func geneLabel(for finding: GenomeFinding) -> String {
        switch finding {
        case .marker(let r): r.marker.gene
        case .clinvar(let h): h.entry.gene.isEmpty ? h.rsid : h.entry.gene
        case .apoe(let a): "APOE \(a.haplotype)"
        }
    }

    private func prefilledHabit(from template: HabitTemplate) -> Habit {
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

    private func linkedHabits(for finding: GenomeFinding) -> [Habit] {
        let key = finding.lookupRsid
        return allHabits.filter { $0.geneticEvidence?.rsid == key && $0.isActive }
    }

    private func linkedGoals(for finding: GenomeFinding) -> [Goal] {
        let key = finding.lookupRsid
        return allGoals.filter { $0.geneticEvidence?.rsid == key && $0.status == .active }
    }

    private func markActionStatus(finding: GenomeFinding, action: GenomeAction, status: GenomeActionStatus) {
        Task {
            await DataStore.shared.setGenomeActionStatus(
                rsid: finding.findingKey,
                actionId: action.id,
                status: status
            )
            await loadData()
        }
    }

    private func snoozeAllActions(for finding: GenomeFinding) {
        Task {
            for action in actionsForFinding(finding) {
                await DataStore.shared.setGenomeActionStatus(
                    rsid: finding.findingKey,
                    actionId: action.id,
                    status: .snoozed
                )
            }
            selectedFinding = nil
            await loadData()
        }
    }

    private func dismissAllActions(for finding: GenomeFinding) {
        Task {
            for action in actionsForFinding(finding) {
                await DataStore.shared.setGenomeActionStatus(
                    rsid: finding.findingKey,
                    actionId: action.id,
                    status: .dismissed
                )
            }
            selectedFinding = nil
            await loadData()
        }
    }

    private func actionsForFinding(_ finding: GenomeFinding) -> [GenomeAction] {
        switch finding {
        case .marker(let r):
            GenomePriorityEngine.matchingActions(
                forRsid: r.marker.rsid, genotype: r.genotype,
                status: r.status, in: GenomeActionLibrary.all
            )
        case .apoe(let a):
            GenomeActionLibrary.all.filter { action in
                action.conditions.contains { $0.rsid == "apoe"
                    && ($0.genotypes?.contains(a.haplotype) ?? true) }
            }
        case .clinvar(let h):
            GenomeActionLibrary.all.filter { action in
                action.conditions.contains { $0.rsid == h.rsid || $0.rsid == "clinvar:\(h.entry.severity)" }
            }
        }
    }

    // MARK: - Epigenetic Age Section

    private var epigeneticAgeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Epigenetic Age")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                CitationBadge(
                    ids: [
                        CitationLibrary.horvathClock2013.id,
                        CitationLibrary.dunedinPace2022.id,
                    ],
                    claim: "DNA-methylation biological age and pace-of-aging"
                )
                if epigeneticTests.count > 1 {
                    Text("\(epigeneticTests.count) tests")
                        .font(.caption)
                        .foregroundColor(.textMuted)
                }
                Spacer()
                Button(action: { showingAddTest = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
                .accessibilityLabel("Add epigenetic age test")
            }

            if epigeneticTests.isEmpty {
                epigeneticEmptyState
            } else {
                latestEpigeneticCard
                epigeneticHistory
            }
        }
        .padding()
        .cardStyle()
    }

    private var epigeneticEmptyState: some View {
        EmptyStateView(
            icon: "dna",
            title: "No epigenetic age tests recorded.",
            subtitle: "Tap + to add results from TruDiagnostic, GlycanAge, or similar services."
        )
    }

    @ViewBuilder
    private var latestEpigeneticCard: some View {
        if let latest = sortedEpigeneticTests.first {
            VStack(spacing: 12) {
                Text("Latest Test — \(DateFormatting.displayDate(latest.date))")
                    .font(.caption)
                    .foregroundColor(.textMuted)

                HStack(spacing: 24) {
                    ageDisplay(label: "Chronological", age: latest.chronologicalAge)
                    ageDisplay(
                        label: "Biological",
                        age: latest.biologicalAge,
                        color: latest.biologicalAge < latest.chronologicalAge ? .success : .danger
                    )
                }

                if let pace = latest.paceOfAging {
                    HStack(spacing: 4) {
                        Text("Pace of Aging:")
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                        Text(String(format: "%.2f", pace))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(pace < 1.0 ? .success : .danger)
                        Text(pace < 1.0 ? "(slower than average)" : "(faster than average)")
                            .font(.caption)
                            .foregroundColor(.textMuted)
                    }
                }

                if let scores = latest.organScores, !scores.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Organ Age Scores")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.textMuted)
                            .textCase(.uppercase)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                        ], spacing: 6) {
                            ForEach(scores.sorted(by: { $0.key < $1.key }), id: \.key) { organ, age in
                                VStack(spacing: 2) {
                                    Text(organ)
                                        .font(.caption2)
                                        .foregroundColor(.textMuted)
                                    Text(String(format: "%.1f", age))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(age < latest.chronologicalAge ? .success : .danger)
                                }
                                .padding(6)
                                .frame(maxWidth: .infinity)
                                .background(Color.bgInput)
                                .cornerRadius(6)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(organ) age: \(String(format: "%.1f", age)) years, \(age < latest.chronologicalAge ? "younger than chronological" : "older than chronological")")
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color.bgInput)
            .cornerRadius(8)
        }
    }

    private func ageDisplay(label: String, age: Double, color: Color = .textPrimary) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.textMuted)
            Text(String(format: "%.1f", age))
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text("years")
                .font(.caption2)
                .foregroundColor(.textMuted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) age: \(String(format: "%.1f", age)) years")
    }

    @ViewBuilder
    private var epigeneticHistory: some View {
        if sortedEpigeneticTests.count > 1 {
            VStack(alignment: .leading, spacing: 6) {
                Text("History")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.textMuted)
                    .textCase(.uppercase)

                ForEach(sortedEpigeneticTests.dropFirst()) { test in
                    HStack {
                        Text(DateFormatting.displayDate(test.date))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        Spacer()
                        Text("Chrono: \(String(format: "%.1f", test.chronologicalAge))")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        Text("Bio: \(String(format: "%.1f", test.biologicalAge))")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(test.biologicalAge < test.chronologicalAge ? .success : .danger)
                        if let pace = test.paceOfAging {
                            Text("Pace: \(String(format: "%.2f", pace))")
                                .font(.caption)
                                .foregroundColor(pace < 1.0 ? .success : .danger)
                        }
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button(role: .destructive, action: {
                            Task {
                                await DataStore.shared.removeEpigeneticTest(id: test.id)
                                await loadData()
                            }
                        }) {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Genome Upload Section

    private var genomeUploadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Genome Data")
                .font(.headline)
                .foregroundColor(.textPrimary)

            if genomeVariants.isEmpty {
                VStack(spacing: 12) {
                    EmptyStateView(
                        icon: "doc.text",
                        title: "Upload raw genome data from 23andMe or AncestryDNA",
                        subtitle: "Supports .txt files with rsID, chromosome, position, and genotype columns. Data stays on your device."
                    )

                    Button(action: { showingFileImporter = true }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import Genome File")
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .cornerRadius(8)
                    }
                    .accessibilityLabel("Import genome file")
                    .accessibilityHint("Upload raw genome data from 23andMe or AncestryDNA")
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(totalVariantCount > genomeVariants.count
                                ? "Showing \(genomeVariants.count) of \(totalVariantCount) total variants"
                                : "\(genomeVariants.count) variants loaded")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.textPrimary)
                            if let build = genomeBuild {
                                Text("Reference: \(build)")
                                    .font(.caption)
                                    .foregroundColor(.textMuted)
                            }
                        }
                        Spacer()
                        Button(action: { showingFileImporter = true }) {
                            Text("Re-import")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                    }

                    // Show first few variants as preview
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Text("rsID").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Chr").frame(width: 40, alignment: .center)
                            Text("Pos").frame(width: 80, alignment: .trailing)
                            Text("Genotype").frame(width: 70, alignment: .trailing)
                        }
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.textMuted)
                        .textCase(.uppercase)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)

                        Divider()

                        ForEach(genomeVariants.prefix(10)) { variant in
                            HStack(spacing: 0) {
                                Text(variant.rsID)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(variant.chromosome)
                                    .frame(width: 40, alignment: .center)
                                Text(variant.position)
                                    .frame(width: 80, alignment: .trailing)
                                Text(variant.genotype)
                                    .frame(width: 70, alignment: .trailing)
                                    .fontWeight(.medium)
                            }
                            .font(.caption)
                            .foregroundColor(.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        }

                        if genomeVariants.count > 10 {
                            Text("... and \(genomeVariants.count - 10) more variants")
                                .font(.caption)
                                .foregroundColor(.textMuted)
                                .padding(.top, 4)
                        }
                    }
                }
            }

            if let error = importError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.danger)
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - File Import

    private func handleFileImport(_ result: Result<[URL], Error>) {
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

    // MARK: - Scanning Indicator

    private var scanningIndicator: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Scanning your genome markers...")
                .font(.subheadline)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .cardStyle()
    }

    // MARK: - APOE Section

    @ViewBuilder
    private func apoeSection(_ apoe: APOEResult?) -> some View {
        if let apoe {
            Button(action: { selectedFinding = .apoe(apoe) }) {
                apoeContent(apoe)
            }
            .buttonStyle(.plain)
        }
    }

    private func apoeContent(_ apoe: APOEResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.title2)
                        .foregroundColor(colorForStatus(apoe.status))
                    Text("APOE Haplotype")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    CitationBadge(
                        ids: [
                            CitationLibrary.deelenApoe2019.id,
                            CitationLibrary.farrerApoeAlz1997.id,
                            CitationLibrary.clinvar.id,
                        ],
                        claim: "APOE longevity and Alzheimer's risk multipliers"
                    )
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.textMuted)
                }

                HStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text("Your Type")
                            .font(.caption)
                            .foregroundColor(.textMuted)
                        Text("APOE \(apoe.haplotype)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(colorForStatus(apoe.status))
                    }

                    VStack(spacing: 4) {
                        Text("Risk Multiplier")
                            .font(.caption)
                            .foregroundColor(.textMuted)
                        Text(apoe.riskMultiplier)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(colorForStatus(apoe.status))
                    }

                    VStack(spacing: 4) {
                        Text("Population")
                            .font(.caption)
                            .foregroundColor(.textMuted)
                        Text(apoe.frequency)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)

                Text(apoe.implication)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(colorForStatus(apoe.status).opacity(0.08))
            .cardStyle()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("APOE Haplotype: \(apoe.haplotype), risk multiplier \(apoe.riskMultiplier), \(apoe.frequency) of population. \(apoe.implication)")
    }

    // MARK: - Summary Bar

    private func markerSummaryBar(_ summary: GenomeScanSummary) -> some View {
        let beneficial = summary.statusCounts[.beneficial] ?? 0
        let typical = summary.statusCounts[.typical] ?? 0
        let concern = (summary.statusCounts[.concern] ?? 0) + (summary.statusCounts[.majorConcern] ?? 0)
        let notFoundCount = summary.statusCounts[.notFound] ?? 0
        let foundCount = summary.markerResults.count - notFoundCount

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "dna")
                    .font(.headline)
                    .foregroundColor(.accentColor)
                Text("Your Genetic Markers")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(foundCount) of \(summary.markerResults.count) found")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }

            HStack(spacing: 16) {
                summaryPill(count: beneficial, label: "Beneficial", color: .green)
                summaryPill(count: typical, label: "Typical", color: .secondary)
                summaryPill(count: concern, label: "Concern", color: .orange)
            }

            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                    sexFilterPicker
                }
                Spacer()
                Button(action: { withAnimation { showNotFound.toggle() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: showNotFound ? "eye.slash" : "eye")
                            .font(.caption2)
                        Text(showNotFound ? "Hide Not Found (\(notFoundCount))" : "Show Not Found (\(notFoundCount))")
                            .font(.caption)
                    }
                    .foregroundColor(.textMuted)
                }
            }
        }
        .padding()
        .cardStyle()
    }

    private func summaryPill(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text("\(count)")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) \(label) markers")
    }

    // MARK: - Category Cards

    @ViewBuilder
    private func markerCategoryCards(_ summary: GenomeScanSummary) -> some View {
        let hiddenCategories = sexFilter.hiddenMarkerCategories
        let grouped = Dictionary(grouping: summary.markerResults, by: { $0.marker.category })
        let sortedCategories = grouped.keys.sorted().filter { !hiddenCategories.contains($0) }

        ForEach(sortedCategories, id: \.self) { category in
            let results = grouped[category] ?? []
            let foundResults = results.filter { $0.status != .notFound }
            let displayResults = showNotFound ? results : foundResults

            if !foundResults.isEmpty || showNotFound {
                categoryCard(category: category, results: results, displayResults: displayResults)
            }
        }
    }

    private func categoryCard(category: MarkerCategory, results: [MarkerResult], displayResults: [MarkerResult]) -> some View {
        let isExpanded = expandedCategories.contains(category)
        let foundResults = results.filter { $0.status != .notFound }
        let worstStatus = worstStatusIn(foundResults)
        let foundCount = foundResults.count
        let concernCount = foundResults.filter { $0.status == .concern || $0.status == .majorConcern }.count

        return VStack(spacing: 0) {
            // Category header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if isExpanded {
                        expandedCategories.remove(category)
                    } else {
                        expandedCategories.insert(category)
                    }
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: category.icon)
                        .font(.body)
                        .foregroundColor(colorForStatus(worstStatus))
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.label)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.textPrimary)

                        HStack(spacing: 6) {
                            Text("\(foundCount) found")
                                .font(.caption)
                                .foregroundColor(.textMuted)
                            if concernCount > 0 {
                                Text("\(concernCount) concern")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.horizontal)

                VStack(spacing: 0) {
                    ForEach(displayResults, id: \.marker.rsid) { result in
                        markerRow(result)
                        if result.marker.rsid != displayResults.last?.marker.rsid {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardStyle()
    }

    // MARK: - Individual Marker Row

    private func markerRow(_ result: MarkerResult) -> some View {
        Button(action: { selectedFinding = .marker(result) }) {
            HStack(spacing: 10) {
                Circle()
                    .fill(colorForStatus(result.status, polarity: result.marker.polarity))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 1) {
                    Text(result.marker.gene)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                    Text(result.marker.name)
                        .font(.caption)
                        .foregroundColor(.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                if let genotype = result.genotype {
                    genotypePill(genotype, status: result.status, polarity: result.marker.polarity)
                } else {
                    Text("N/A")
                        .font(.caption)
                        .foregroundColor(.textMuted)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.textMuted)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func genotypePill(_ genotype: String, status: GenomeMarkerStatus, polarity: MarkerPolarity = .risk) -> some View {
        Text(genotype)
            .font(.caption)
            .fontWeight(.bold)
            .monospacedDigit()
            .foregroundColor(colorForStatus(status, polarity: polarity))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(colorForStatus(status, polarity: polarity).opacity(0.12))
            .cornerRadius(6)
    }

    private func markerDetail(_ result: MarkerResult) -> some View {
        let polarity = result.marker.polarity
        return VStack(alignment: .leading, spacing: 8) {
            Text(result.marker.description)
                .font(.caption)
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !result.implication.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: iconForStatus(result.status, polarity: polarity))
                        .font(.caption)
                        .foregroundColor(colorForStatus(result.status, polarity: polarity))
                        .frame(width: 14, alignment: .center)
                    Text(result.implication)
                        .font(.caption)
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colorForStatus(result.status, polarity: polarity).opacity(0.06))
                .cornerRadius(6)
            }

            HStack {
                Text(result.marker.rsid)
                    .font(.caption2)
                    .foregroundColor(.textMuted)
                    .monospacedDigit()
                Spacer()
                Text(statusLabel(result.status, polarity: polarity))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(colorForStatus(result.status, polarity: polarity))
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    // MARK: - ClinVar Section

    private var clinvarSection: some View {
        let grouped = clinvarGrouped

        return VStack(spacing: 12) {
            // Header card
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "building.columns.fill")
                        .font(.headline)
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("ClinVar Database")
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                            CitationBadge(
                                ids: [CitationLibrary.clinvar.id],
                                claim: "NCBI ClinVar is the source for all variant pathogenicity classifications shown below."
                            )
                        }
                        if clinvarStatus.synced, let dateStr = clinvarStatus.syncedAt {
                            let displayDate = formatClinVarDate(dateStr)
                            Text("Synced: \(displayDate) \u{2022} \(DateFormatting.formatLargeNumber(clinvarStatus.variantCount ?? 0)) variants indexed")
                                .font(.caption)
                                .foregroundColor(.textMuted)
                        }
                    }
                    Spacer()
                }

                if !clinvarStatus.synced {
                    clinvarDownloadPrompt
                } else if isSyncingClinVar {
                    clinvarSyncingView
                } else if clinvarHits.isEmpty && clinvarStatus.synced {
                    clinvarNoHitsView
                } else {
                    clinvarSummaryBar(grouped: grouped)
                }

                if let error = clinvarError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.danger)
                }
            }
            .padding()
            .cardStyle()
            .onAppear { loadClinVarStatus() }

            // Theme cards (outside the header card)
            if !grouped.isEmpty {
                ForEach(grouped, id: \.theme) { group in
                    clinvarThemeCard(theme: group.theme, hits: group.hits)
                }
            }
        }
    }

    private func clinvarSummaryBar(grouped: [(theme: ClinVarTheme, hits: [ClinVarHit])]) -> some View {
        var pathogenic = 0, riskFactor = 0, drugResponse = 0, protective = 0, filteredTotal = 0
        for group in grouped {
            for hit in group.hits {
                filteredTotal += 1
                switch hit.entry.severity {
                case "pathogenic": pathogenic += 1
                case "risk_factor": riskFactor += 1
                case "drug_response": drugResponse += 1
                case "protective": protective += 1
                default: break
                }
            }
        }

        let summaryText = minimumStars > 0
            ? "\(filteredTotal) of \(clinvarHits.count) variants (≥\(minimumStars) star\(minimumStars == 1 ? "" : "s"))"
            : "\(clinvarHits.count) variants matched your genome"

        return VStack(alignment: .leading, spacing: 8) {
            Text(summaryText)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.textPrimary)

            HStack(spacing: 12) {
                if pathogenic > 0 {
                    summaryPill(count: pathogenic, label: "Pathogenic", color: .red)
                }
                if riskFactor > 0 {
                    summaryPill(count: riskFactor, label: "Risk", color: .orange)
                }
                if drugResponse > 0 {
                    summaryPill(count: drugResponse, label: "Drug", color: .blue)
                }
                if protective > 0 {
                    summaryPill(count: protective, label: "Protective", color: .green)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Minimum Review Stars")
                        .font(.caption)
                        .foregroundColor(.textMuted)
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { star in
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    minimumStars = minimumStars == star ? 0 : star
                                    themeDisplayLimits = [:]
                                }
                            }) {
                                Image(systemName: star == 0 ? "line.3.horizontal.decrease.circle" : (star <= minimumStars ? "star.fill" : "star"))
                                    .font(.system(size: star == 0 ? 16 : 14))
                                    .foregroundColor(star == 0
                                        ? (minimumStars == 0 ? .textMuted : .accentColor)
                                        : (star <= minimumStars ? .orange : .textMuted))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(star == 0 ? "Show all" : "\(star) star\(star == 1 ? "" : "s") minimum")
                        }
                        if minimumStars > 0 {
                            Text("≥\(minimumStars)")
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .padding(.leading, 4)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Sex Filter")
                        .font(.caption)
                        .foregroundColor(.textMuted)
                    sexFilterPicker
                }
            }
            .padding(.top, 4)

            Text("Organized by health theme below. Tap a category to see details.")
                .font(.caption)
                .foregroundColor(.textMuted)
        }
    }

    private var clinvarDownloadPrompt: some View {
        VStack(spacing: 10) {
            Text("Download the ClinVar database from NCBI to cross-reference your genome against known pathogenic variants, drug responses, and protective factors.")
                .font(.caption)
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if isSyncingClinVar {
                clinvarSyncingView
            } else {
                Button(action: { syncClinVar() }) {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                        Text("Download ClinVar Database")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .cornerRadius(8)
                }
            }
        }
    }

    private var clinvarSyncingView: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(clinvarProgress.isEmpty ? "Syncing..." : clinvarProgress)
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var clinvarNoHitsView: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundColor(.success)
            Text("No pathogenic variants found in your genome data.")
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
    }

    // MARK: - ClinVar Theme Card

    private func clinvarThemeCard(theme: ClinVarTheme, hits: [ClinVarHit]) -> some View {
        let isExpanded = expandedThemes.contains(theme)
        var pathogenicCount = 0
        var worstOrder = 99
        for hit in hits {
            let order = GenomeEngine.severityOrder[hit.entry.severity] ?? 99
            if order < worstOrder { worstOrder = order }
            if hit.entry.severity == "pathogenic" { pathogenicCount += 1 }
        }
        let worstSeverity = GenomeEngine.severityOrder.first { $0.value == worstOrder }?.key ?? "protective"

        return VStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if isExpanded {
                        expandedThemes.remove(theme)
                    } else {
                        expandedThemes.insert(theme)
                    }
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: theme.icon)
                        .font(.body)
                        .foregroundColor(clinvarSeverityColor(worstSeverity))
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(theme.label)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.textPrimary)

                        HStack(spacing: 6) {
                            Text("\(hits.count) variant\(hits.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.textMuted)
                            if pathogenicCount > 0 {
                                Text("\(pathogenicCount) pathogenic")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.red)
                            }
                        }
                    }

                    Spacer()

                    // Severity dots summary
                    HStack(spacing: 3) {
                        ForEach(severityDots(hits), id: \.self) { color in
                            Circle()
                                .fill(color)
                                .frame(width: 6, height: 6)
                        }
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.horizontal)

                let displayLimit = themeDisplayLimits[theme] ?? Self.themePageSize
                let visibleHits = Array(hits.prefix(displayLimit))
                let hasMore = hits.count > displayLimit

                LazyVStack(spacing: 0) {
                    ForEach(0..<visibleHits.count, id: \.self) { idx in
                        clinvarHitRow(visibleHits[idx])
                        if idx < visibleHits.count - 1 {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }

                    if hasMore {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                themeDisplayLimits[theme] = displayLimit + Self.themePageSize
                            }
                        }) {
                            Text("Show more (\(hits.count - displayLimit) remaining)")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardStyle()
    }

    private func severityDots(_ hits: [ClinVarHit]) -> [Color] {
        let severities = Set(hits.map(\.entry.severity))
        var dots: [Color] = []
        if severities.contains("pathogenic") { dots.append(.red) }
        if severities.contains("risk_factor") { dots.append(.orange) }
        if severities.contains("drug_response") { dots.append(.blue) }
        if severities.contains("protective") { dots.append(.green) }
        return dots
    }

    private func clinvarHitRow(_ hit: ClinVarHit) -> some View {
        Button(action: { selectedFinding = .clinvar(hit) }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(clinvarSeverityColor(hit.entry.severity))
                        .frame(width: 8, height: 8)

                    if !hit.entry.gene.isEmpty {
                        Text(hit.entry.gene)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.accentColor)
                    }

                    Text(hit.rsid)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(.textMuted)

                    Spacer()

                    genotypePill(hit.genotype, status: GenomeEngine.statusForSeverity(hit.entry.severity))

                    reviewStars(hit.entry.reviewStars)

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                }

                if !hit.entry.conditions.isEmpty {
                    Text(hit.entry.conditions.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                        .lineLimit(2)
                        .padding(.leading, 18)
                }

                HStack(spacing: 6) {
                    Text(clinvarSeverityLabel(hit.entry.severity))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(clinvarSeverityColor(hit.entry.severity))
                    if hit.entry.submissions > 1 {
                        Text("\(hit.entry.submissions) submissions")
                            .font(.caption2)
                            .foregroundColor(.textMuted)
                    }
                    Spacer()
                    Text("Tap for details")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
                .padding(.leading, 18)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func reviewStars(_ count: Int) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<4, id: \.self) { i in
                Image(systemName: i < count ? "star.fill" : "star")
                    .font(.system(size: 8))
                    .foregroundColor(i < count ? .orange : .textMuted)
            }
        }
    }

    // MARK: - Marker Scan Logic

    private func runMarkerScan() {
        isScanning = true
        scanSummary = nil
        expandedCategories = []
        expandedMarkers = []

        let variants = allGenomeVariants
        let markers = GenomeEngine.allCuratedMarkers
        Task.detached(priority: .userInitiated) {
            let summary = GenomeEngine.fullScan(variants: variants, markers: markers)
            let record = GenomeScanRecord.from(summary)
            await DataStore.shared.saveGenomeScanRecord(record)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    scanSummary = summary
                    isScanning = false
                }
                runClinVarScan()
            }
        }
    }

    // MARK: - ClinVar Logic

    private func loadClinVarStatus() {
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
                    clinvarHits = hits
                    clinvarStatus = ClinVarService.getStatus()
                }
            }
        }
    }

    private func syncClinVar() {
        isSyncingClinVar = true
        clinvarError = nil
        clinvarProgress = ""

        Task {
            do {
                let status = try await ClinVarService.syncClinVar { progress in
                    Task { @MainActor in
                        clinvarProgress = progress
                    }
                }
                await MainActor.run {
                    clinvarStatus = status
                    isSyncingClinVar = false
                    runClinVarScan()
                }
            } catch {
                await MainActor.run {
                    clinvarError = "ClinVar sync failed: \(error.localizedDescription)"
                    isSyncingClinVar = false
                }
            }
        }
    }

    // MARK: - Sex Filter Picker

    private var sexFilterPicker: some View {
        HStack(spacing: 4) {
            ForEach(SexFilter.allCases, id: \.self) { filter in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        sexFilter = filter
                        themeDisplayLimits = [:]
                    }
                }) {
                    Text(filter.rawValue)
                        .font(.caption)
                        .fontWeight(sexFilter == filter ? .semibold : .regular)
                        .foregroundColor(sexFilter == filter ? .white : .textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(sexFilter == filter ? Color.accentColor : Color.bgInput)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(filter.rawValue) sex filter")
                .accessibilityAddTraits(sexFilter == filter ? .isSelected : [])
            }
        }
    }

    // MARK: - Status Helpers

    // For protective markers (rare variant is desirable, e.g. FOXO3A longevity),
    // `.concern` just means "lacks the beneficial variant" — a neutral typical
    // outcome, not an elevated risk. Risk markers keep their original warning
    // colors/icons/labels.

    private func colorForStatus(_ status: GenomeMarkerStatus, polarity: MarkerPolarity = .risk) -> Color {
        switch (status, polarity) {
        case (.beneficial, _): .green
        case (.typical, _): .secondary
        case (.concern, .protective), (.majorConcern, .protective): .secondary
        case (.concern, .risk): .orange
        case (.majorConcern, .risk): .red
        case (.notFound, _): .gray
        }
    }

    private func iconForStatus(_ status: GenomeMarkerStatus, polarity: MarkerPolarity = .risk) -> String {
        switch (status, polarity) {
        case (.beneficial, _): "checkmark.circle.fill"
        case (.typical, _): "minus.circle.fill"
        case (.concern, .protective), (.majorConcern, .protective): "minus.circle.fill"
        case (.concern, .risk): "exclamationmark.triangle.fill"
        case (.majorConcern, .risk): "exclamationmark.octagon.fill"
        case (.notFound, _): "questionmark.circle"
        }
    }

    private func statusLabel(_ status: GenomeMarkerStatus, polarity: MarkerPolarity = .risk) -> String {
        switch (status, polarity) {
        case (.beneficial, .protective): "Beneficial Variant"
        case (.beneficial, .risk): "No Risk Variant"
        case (.typical, _): "Typical"
        case (.concern, .protective), (.majorConcern, .protective): "No Benefit Variant"
        case (.concern, .risk): "Carrier"
        case (.majorConcern, .risk): "Risk Variant"
        case (.notFound, _): "Not Found"
        }
    }

    private func worstStatusIn(_ results: [MarkerResult]) -> GenomeMarkerStatus {
        if results.contains(where: { $0.status == .majorConcern }) { return .majorConcern }
        if results.contains(where: { $0.status == .concern }) { return .concern }
        if results.contains(where: { $0.status == .beneficial }) { return .beneficial }
        return .typical
    }

    private func clinvarSeverityColor(_ severity: String) -> Color {
        switch severity {
        case "pathogenic": .red
        case "drug_response": .orange
        case "risk_factor": .orange
        case "protective": .green
        default: .secondary
        }
    }

    private func clinvarSeverityLabel(_ severity: String) -> String {
        switch severity {
        case "pathogenic": "Pathogenic"
        case "drug_response": "Drug Response"
        case "risk_factor": "Risk Factor"
        case "protective": "Protective"
        default: severity.capitalized
        }
    }

    private static let isoFormatter = ISO8601DateFormatter()
    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private func formatClinVarDate(_ iso: String) -> String {
        guard let date = Self.isoFormatter.date(from: iso) else { return iso }
        return Self.displayFormatter.string(from: date)
    }

    // MARK: - Data Loading

    private func loadData() async {
        let data = await DataStore.shared.getData()
        epigeneticTests = data.epigeneticTests
        sortedEpigeneticTests = data.epigeneticTests.sorted(by: { $0.date > $1.date })
        actionStates = data.genomeActionStates
        visitNotes = data.genomeVisitNotes
        allGoals = data.goals
        allHabits = data.habits

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

        isLoading = false
    }
}

// MARK: - Epigenetic Test Form

private struct EpigeneticTestFormView: View {
    let onSave: (EpigeneticTest) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var testDate = Date()
    @State private var chronoAge = ""
    @State private var bioAge = ""
    @State private var paceOfAging = ""

    // Common organ scores
    private let organNames = [
        "Heart", "Liver", "Kidney", "Lung", "Brain",
        "Immune", "Metabolic", "Musculoskeletal", "Hormone", "Inflammation",
    ]
    @State private var organScoreValues: [String: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section("Test Date") {
                    DatePicker("Date", selection: $testDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }

                Section("Age Results") {
                    HStack {
                        Text("Chronological Age")
                            .foregroundColor(.textPrimary)
                        Spacer()
                        TextField("e.g. 40.0", text: $chronoAge)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("Biological Age")
                            .foregroundColor(.textPrimary)
                        Spacer()
                        TextField("e.g. 35.0", text: $bioAge)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("Pace of Aging")
                            .foregroundColor(.textPrimary)
                        Spacer()
                        TextField("e.g. 0.85", text: $paceOfAging)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }

                Section("Organ Age Scores (Optional)") {
                    ForEach(organNames, id: \.self) { organ in
                        HStack {
                            Text(organ)
                                .foregroundColor(.textPrimary)
                            Spacer()
                            TextField("—", text: organBinding(for: organ))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }
                }
            }
            .macGroupedFormStyle()
            .navigationTitle("Add Epigenetic Test")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .macSheetFrame()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveTest() }
                        .disabled(Double(chronoAge) == nil || Double(bioAge) == nil)
                }
            }
        }
    }

    private func organBinding(for organ: String) -> Binding<String> {
        Binding(
            get: { organScoreValues[organ] ?? "" },
            set: { organScoreValues[organ] = $0 }
        )
    }

    private func saveTest() {
        guard let chrono = Double(chronoAge), let bio = Double(bioAge) else { return }
        let dateStr = DateFormatting.dateString( testDate)

        var scores: [String: Double]?
        let parsedScores = organScoreValues.compactMapValues { Double($0) }
        if !parsedScores.isEmpty {
            scores = parsedScores
        }

        let test = EpigeneticTest(
            date: dateStr,
            chronologicalAge: chrono,
            biologicalAge: bio,
            paceOfAging: Double(paceOfAging),
            organScores: scores
        )
        onSave(test)
        dismiss()
    }
}
