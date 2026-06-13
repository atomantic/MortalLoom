import SwiftUI

/// The "ClinVar" tab of the Genome screen: the NCBI ClinVar database
/// download/sync prompt, the matched-variant summary bar with review-star and
/// sex filters, and the per-theme variant browse. Pure presentation backed by
/// `GenomeViewModel` (extracted from `GenomeView`, issue #24).
struct ClinVarView: View {
    @Bindable var vm: GenomeViewModel

    var body: some View {
        let grouped = vm.clinvarGrouped

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
                        if vm.clinvarStatus.synced, let dateStr = vm.clinvarStatus.syncedAt {
                            let displayDate = formatClinVarDate(dateStr)
                            Text("Synced: \(displayDate) \u{2022} \(DateFormatting.formatLargeNumber(vm.clinvarStatus.variantCount ?? 0)) variants indexed")
                                .font(.caption)
                                .foregroundColor(.textMuted)
                        }
                    }
                    Spacer()
                }

                if !vm.clinvarStatus.synced {
                    clinvarDownloadPrompt
                } else if vm.isSyncingClinVar {
                    clinvarSyncingView
                } else if vm.clinvarHits.isEmpty && vm.clinvarStatus.synced {
                    clinvarNoHitsView
                } else {
                    clinvarSummaryBar(grouped: grouped)
                }

                if let error = vm.clinvarError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.danger)
                }
            }
            .padding()
            .cardStyle()
            .onAppear { vm.loadClinVarStatus() }

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

        let summaryText = vm.minimumStars > 0
            ? "\(filteredTotal) of \(vm.clinvarHits.count) variants (≥\(vm.minimumStars) star\(vm.minimumStars == 1 ? "" : "s"))"
            : "\(vm.clinvarHits.count) variants matched your genome"

        return VStack(alignment: .leading, spacing: 8) {
            Text(summaryText)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.textPrimary)

            HStack(spacing: 12) {
                if pathogenic > 0 {
                    GenomeViewHelpers.summaryPill(count: pathogenic, label: "Pathogenic", color: .red)
                }
                if riskFactor > 0 {
                    GenomeViewHelpers.summaryPill(count: riskFactor, label: "Risk", color: .orange)
                }
                if drugResponse > 0 {
                    GenomeViewHelpers.summaryPill(count: drugResponse, label: "Drug", color: .blue)
                }
                if protective > 0 {
                    GenomeViewHelpers.summaryPill(count: protective, label: "Protective", color: .green)
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
                                    vm.toggleMinimumStars(star)
                                }
                            }) {
                                Image(systemName: star == 0 ? "line.3.horizontal.decrease.circle" : (star <= vm.minimumStars ? "star.fill" : "star"))
                                    .font(.system(size: star == 0 ? 16 : 14))
                                    .foregroundColor(star == 0
                                        ? (vm.minimumStars == 0 ? .textMuted : .accentColor)
                                        : (star <= vm.minimumStars ? .orange : .textMuted))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(star == 0 ? "Show all" : "\(star) star\(star == 1 ? "" : "s") minimum")
                        }
                        if vm.minimumStars > 0 {
                            Text("≥\(vm.minimumStars)")
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
                    SexFilterPicker(selected: vm.sexFilter) { vm.setSexFilter($0) }
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

            if vm.isSyncingClinVar {
                clinvarSyncingView
            } else {
                Button(action: { vm.syncClinVar() }) {
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
            Text(vm.clinvarProgress.isEmpty ? "Syncing..." : vm.clinvarProgress)
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
        let isExpanded = vm.expandedThemes.contains(theme)
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
                        vm.expandedThemes.remove(theme)
                    } else {
                        vm.expandedThemes.insert(theme)
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

                let displayLimit = vm.themeDisplayLimits[theme] ?? GenomeViewModel.themePageSize
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
                                vm.themeDisplayLimits[theme] = displayLimit + GenomeViewModel.themePageSize
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
        Button(action: { vm.selectedFinding = .clinvar(hit) }) {
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

                    GenomeViewHelpers.genotypePill(hit.genotype, status: GenomeEngine.statusForSeverity(hit.entry.severity))

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
                    Text(GenomeViewHelpers.clinvarSeverityLabel(hit.entry.severity))
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

    // MARK: - Date formatting

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
}
