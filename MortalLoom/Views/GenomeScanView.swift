import SwiftUI

/// The "Genome" tab of the Genome screen: raw-file upload + variant preview,
/// the curated-marker scan summary, APOE haplotype card, prioritized findings,
/// and the per-category marker browse. Pure presentation backed by
/// `GenomeViewModel` (extracted from `GenomeView`, issue #24).
struct GenomeScanView: View {
    @Bindable var vm: GenomeViewModel
    @Binding var showingFileImporter: Bool

    var body: some View {
        genomeUploadSection
        if !vm.genomeVariants.isEmpty {
            if vm.isScanning { scanningIndicator }
            if let summary = vm.scanSummary {
                if !vm.topPriorities.isEmpty || vm.totalPriorityCandidates > 0 {
                    GenomePrioritiesCard(
                        priorities: vm.topPriorities,
                        totalCandidateCount: vm.totalPriorityCandidates,
                        onSelectFinding: { finding in vm.selectedFinding = finding },
                        onStartVisit: { vm.showingVisitMode = true },
                        onExportPDF: { vm.exportPrevisitPDF() }
                    )
                }
                apoeSection(summary.apoeResult)
                markerSummaryBar(summary)
                markerCategoryCards(summary)
            }
        }
    }

    // MARK: - Genome Upload Section

    private var genomeUploadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Genome Data")
                .font(.headline)
                .foregroundColor(.textPrimary)

            if vm.genomeVariants.isEmpty {
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
                            Text(vm.totalVariantCount > vm.genomeVariants.count
                                ? "Showing \(vm.genomeVariants.count) of \(vm.totalVariantCount) total variants"
                                : "\(vm.genomeVariants.count) variants loaded")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.textPrimary)
                            if let build = vm.genomeBuild {
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

                        ForEach(vm.genomeVariants.prefix(10)) { variant in
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

                        if vm.genomeVariants.count > 10 {
                            Text("... and \(vm.genomeVariants.count - 10) more variants")
                                .font(.caption)
                                .foregroundColor(.textMuted)
                                .padding(.top, 4)
                        }
                    }
                }
            }

            if let error = vm.importError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.danger)
            }
        }
        .padding()
        .cardStyle()
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
            Button(action: { vm.selectedFinding = .apoe(apoe) }) {
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
                        .foregroundColor(GenomeViewHelpers.colorForStatus(apoe.status))
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
                            .foregroundColor(GenomeViewHelpers.colorForStatus(apoe.status))
                    }

                    VStack(spacing: 4) {
                        Text("Risk Multiplier")
                            .font(.caption)
                            .foregroundColor(.textMuted)
                        Text(apoe.riskMultiplier)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(GenomeViewHelpers.colorForStatus(apoe.status))
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
            .background(GenomeViewHelpers.colorForStatus(apoe.status).opacity(0.08))
            .cardStyle()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("APOE Haplotype: \(apoe.haplotype), risk multiplier \(apoe.riskMultiplier), \(apoe.frequency) of population. \(apoe.implication)")
    }

    // MARK: - Summary Bar

    private func markerSummaryBar(_ summary: GenomeScanSummary) -> some View {
        // Polarity-aware bucketing — protective markers' "concern" is "no
        // beneficial variant", which is neutral, not a real concern.
        var beneficial = 0
        var typical = 0
        var concern = 0
        var notFoundCount = 0
        for result in summary.markerResults {
            switch result.status {
            case .beneficial: beneficial += 1
            case .typical: typical += 1
            case .concern, .majorConcern:
                if result.marker.polarity == .risk { concern += 1 } else { typical += 1 }
            case .notFound: notFoundCount += 1
            }
        }
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
                GenomeViewHelpers.summaryPill(count: beneficial, label: "Beneficial", color: .green)
                GenomeViewHelpers.summaryPill(count: typical, label: "Typical", color: .secondary)
                GenomeViewHelpers.summaryPill(count: concern, label: "Concern", color: .orange)
            }

            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                    SexFilterPicker(selected: vm.sexFilter) { vm.setSexFilter($0) }
                }
                Spacer()
                Button(action: { withAnimation { vm.showNotFound.toggle() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: vm.showNotFound ? "eye.slash" : "eye")
                            .font(.caption2)
                        Text(vm.showNotFound ? "Hide Not Found (\(notFoundCount))" : "Show Not Found (\(notFoundCount))")
                            .font(.caption)
                    }
                    .foregroundColor(.textMuted)
                }
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Category Cards

    @ViewBuilder
    private func markerCategoryCards(_ summary: GenomeScanSummary) -> some View {
        let hiddenCategories = vm.sexFilter.hiddenMarkerCategories
        let grouped = Dictionary(grouping: summary.markerResults, by: { $0.marker.category })
        let sortedCategories = grouped.keys.sorted().filter { !hiddenCategories.contains($0) }

        ForEach(sortedCategories, id: \.self) { category in
            let results = grouped[category] ?? []
            let foundResults = results.filter { $0.status != .notFound }
            let displayResults = vm.showNotFound ? results : foundResults

            if !foundResults.isEmpty || vm.showNotFound {
                categoryCard(category: category, results: results, displayResults: displayResults)
            }
        }
    }

    private func categoryCard(category: MarkerCategory, results: [MarkerResult], displayResults: [MarkerResult]) -> some View {
        let isExpanded = vm.expandedCategories.contains(category)
        let foundResults = results.filter { $0.status != .notFound }
        let worstStatus = GenomeViewHelpers.worstStatusIn(foundResults)
        let foundCount = foundResults.count
        // Polarity-aware: a "concern" on a protective marker means "lacks the
        // beneficial variant" — neutral, not a real worry. Only count concerns
        // on risk markers as actionable.
        let concernCount = foundResults.filter {
            ($0.status == .concern || $0.status == .majorConcern) && $0.marker.polarity == .risk
        }.count
        let beneficialCount = foundResults.filter { $0.status == .beneficial }.count

        return VStack(spacing: 0) {
            // Category header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if isExpanded {
                        vm.expandedCategories.remove(category)
                    } else {
                        vm.expandedCategories.insert(category)
                    }
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: category.icon)
                        .font(.body)
                        .foregroundColor(GenomeViewHelpers.colorForStatus(worstStatus))
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
                            if beneficialCount > 0 {
                                Text("\(beneficialCount) beneficial")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.success)
                            }
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
        Button(action: { vm.selectedFinding = .marker(result) }) {
            HStack(spacing: 10) {
                Circle()
                    .fill(GenomeViewHelpers.colorForStatus(result.status, polarity: result.marker.polarity))
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
                    GenomeViewHelpers.genotypePill(genotype, status: result.status, polarity: result.marker.polarity)
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
}
