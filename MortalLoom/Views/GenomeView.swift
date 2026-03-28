import SwiftUI
import UniformTypeIdentifiers

// MARK: - GenomeView

struct GenomeView: View {
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

    // ClinVar
    @State private var clinvarHits: [ClinVarHit] = []
    @State private var clinvarStatus: ClinVarService.SyncStatus = ClinVarService.SyncStatus(synced: false)
    @State private var isSyncingClinVar = false
    @State private var clinvarProgress: String = ""
    @State private var clinvarError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                epigeneticAgeSection
                genomeUploadSection

                if !genomeVariants.isEmpty {
                    if isScanning {
                        scanningIndicator
                    }
                    if let summary = scanSummary {
                        apoeSection(summary.apoeResult)
                        markerSummaryBar(summary)
                        markerCategoryCards(summary)
                        clinvarSection
                    }
                }
            }
            .padding()
        }
        .background(Color.bg)
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
        .task { await loadData() }
    }

    // MARK: - Epigenetic Age Section

    private var epigeneticAgeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Epigenetic Age (\(epigeneticTests.count))")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.title2)
                        .foregroundColor(colorForStatus(apoe.status))
                    Text("APOE Haplotype")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Spacer()
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
        }
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
            Text("\(count)")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
    }

    // MARK: - Category Cards

    @ViewBuilder
    private func markerCategoryCards(_ summary: GenomeScanSummary) -> some View {
        let grouped = Dictionary(grouping: summary.markerResults, by: { $0.marker.category })
        let sortedCategories = grouped.keys.sorted()

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
        let isExpanded = expandedMarkers.contains(result.marker.rsid)

        return VStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedMarkers.remove(result.marker.rsid)
                    } else {
                        expandedMarkers.insert(result.marker.rsid)
                    }
                }
            }) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(colorForStatus(result.status))
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
                        genotypePill(genotype, status: result.status)
                    } else {
                        Text("N/A")
                            .font(.caption)
                            .foregroundColor(.textMuted)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                markerDetail(result)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func genotypePill(_ genotype: String, status: GenomeMarkerStatus) -> some View {
        Text(genotype)
            .font(.caption)
            .fontWeight(.bold)
            .monospacedDigit()
            .foregroundColor(colorForStatus(status))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(colorForStatus(status).opacity(0.12))
            .cornerRadius(6)
    }

    private func markerDetail(_ result: MarkerResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.marker.description)
                .font(.caption)
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !result.implication.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: iconForStatus(result.status))
                        .font(.caption)
                        .foregroundColor(colorForStatus(result.status))
                        .frame(width: 14, alignment: .center)
                    Text(result.implication)
                        .font(.caption)
                        .foregroundColor(.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colorForStatus(result.status).opacity(0.06))
                .cornerRadius(6)
            }

            HStack {
                Text(result.marker.rsid)
                    .font(.caption2)
                    .foregroundColor(.textMuted)
                    .monospacedDigit()
                Spacer()
                Text(statusLabel(result.status))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(colorForStatus(result.status))
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    // MARK: - ClinVar Section

    private var clinvarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "building.columns.fill")
                    .font(.headline)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ClinVar Pathogenic Variants")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    if clinvarStatus.synced, let dateStr = clinvarStatus.syncedAt {
                        let displayDate = formatClinVarDate(dateStr)
                        Text("Last synced: \(displayDate) \u{2022} \(DateFormatting.formatLargeNumber(clinvarStatus.variantCount ?? 0)) variants")
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
                clinvarHitsList
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

    @ViewBuilder
    private var clinvarHitsList: some View {
        let grouped = Dictionary(grouping: clinvarHits, by: { $0.entry.severity })
        let severityOrder = ["pathogenic", "drug_response", "risk_factor", "protective"]
        let orderedKeys = severityOrder.filter { grouped[$0] != nil }

        ForEach(orderedKeys, id: \.self) { severity in
            let hits = grouped[severity] ?? []
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(clinvarSeverityColor(severity))
                        .frame(width: 8, height: 8)
                    Text(clinvarSeverityLabel(severity))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.textSecondary)
                        .textCase(.uppercase)
                    Text("(\(hits.count))")
                        .font(.caption)
                        .foregroundColor(.textMuted)
                }

                ForEach(hits.prefix(20), id: \.rsid) { hit in
                    clinvarHitRow(hit)
                }

                if hits.count > 20 {
                    Text("... and \(hits.count - 20) more")
                        .font(.caption)
                        .foregroundColor(.textMuted)
                        .padding(.leading, 18)
                }
            }
        }
    }

    private func clinvarHitRow(_ hit: ClinVarHit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(hit.rsid)
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundColor(.textPrimary)

                if !hit.entry.gene.isEmpty {
                    Text(hit.entry.gene)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                }

                Spacer()

                genotypePill(hit.genotype, status: GenomeEngine.statusForSeverity(hit.entry.severity))

                reviewStars(hit.entry.reviewStars)
            }

            if !hit.entry.conditions.isEmpty {
                Text(hit.entry.conditions.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundColor(.textMuted)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
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

    // MARK: - Status Helpers

    private func colorForStatus(_ status: GenomeMarkerStatus) -> Color {
        switch status {
        case .beneficial: .green
        case .typical: .secondary
        case .concern: .orange
        case .majorConcern: .red
        case .notFound: .gray
        }
    }

    private func iconForStatus(_ status: GenomeMarkerStatus) -> String {
        switch status {
        case .beneficial: "checkmark.circle.fill"
        case .typical: "minus.circle.fill"
        case .concern: "exclamationmark.triangle.fill"
        case .majorConcern: "exclamationmark.octagon.fill"
        case .notFound: "questionmark.circle"
        }
    }

    private func statusLabel(_ status: GenomeMarkerStatus) -> String {
        switch status {
        case .beneficial: "Beneficial"
        case .typical: "Typical"
        case .concern: "Concern"
        case .majorConcern: "Major Concern"
        case .notFound: "Not Found"
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
            .navigationTitle("Add Epigenetic Test")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
