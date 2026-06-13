import SwiftUI

// MARK: - Genome tab + filter types

/// The three Genome tabs. Shared between `GenomeView` (the host) and the
/// individual tab views so the `.openGenomeFinding` handler can switch tabs.
enum GenomeTab: String, CaseIterable {
    case bioAge = "Bio Age"
    case genome = "Genome"
    case clinvar = "ClinVar"
}

/// Sex-based filtering for marker categories and ClinVar themes. Owned by
/// `GenomeViewModel`; the picker lives in `GenomeViewHelpers.sexFilterPicker`.
enum SexFilter: String, CaseIterable {
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

// MARK: - Shared genome view helpers

/// Status → color/icon/label mapping and the small reusable pill/picker views
/// shared between `GenomeScanView` and `ClinVarView` so the marker and ClinVar
/// presentations don't drift.
///
/// For protective markers (rare variant is desirable, e.g. FOXO3A longevity),
/// `.concern` just means "lacks the beneficial variant" — a neutral typical
/// outcome, not an elevated risk. Risk markers keep their original warning
/// colors/icons/labels.
enum GenomeViewHelpers {
    static func colorForStatus(_ status: GenomeMarkerStatus, polarity: MarkerPolarity = .risk) -> Color {
        switch (status, polarity) {
        case (.beneficial, _): .green
        case (.typical, _): .secondary
        case (.concern, .protective), (.majorConcern, .protective): .secondary
        case (.concern, .risk): .orange
        case (.majorConcern, .risk): .red
        case (.notFound, _): .gray
        }
    }

    static func iconForStatus(_ status: GenomeMarkerStatus, polarity: MarkerPolarity = .risk) -> String {
        switch (status, polarity) {
        case (.beneficial, _): "checkmark.circle.fill"
        case (.typical, _): "minus.circle.fill"
        case (.concern, .protective), (.majorConcern, .protective): "minus.circle.fill"
        case (.concern, .risk): "exclamationmark.triangle.fill"
        case (.majorConcern, .risk): "exclamationmark.octagon.fill"
        case (.notFound, _): "questionmark.circle"
        }
    }

    static func statusLabel(_ status: GenomeMarkerStatus, polarity: MarkerPolarity = .risk) -> String {
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

    static func worstStatusIn(_ results: [MarkerResult]) -> GenomeMarkerStatus {
        // Polarity-aware: only count concerns on risk markers as worsening
        // the category. A protective marker's `.concern` (= "no benefit
        // variant") shouldn't paint the whole category orange.
        if results.contains(where: { $0.status == .majorConcern && $0.marker.polarity == .risk }) { return .majorConcern }
        if results.contains(where: { $0.status == .concern && $0.marker.polarity == .risk }) { return .concern }
        if results.contains(where: { $0.status == .beneficial }) { return .beneficial }
        return .typical
    }

    static func clinvarSeverityLabel(_ severity: String) -> String {
        switch severity {
        case "pathogenic": "Pathogenic"
        case "drug_response": "Drug Response"
        case "risk_factor": "Risk Factor"
        case "protective": "Protective"
        default: severity.capitalized
        }
    }

    // MARK: - Reusable views

    static func summaryPill(count: Int, label: String, color: Color) -> some View {
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

    static func genotypePill(_ genotype: String, status: GenomeMarkerStatus, polarity: MarkerPolarity = .risk) -> some View {
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
}

// MARK: - Sex filter picker

/// Pill-style sex filter picker shared between the marker summary bar and the
/// ClinVar summary bar. Calls back into the view model so changing the filter
/// re-derives priorities and resets per-theme paging.
struct SexFilterPicker: View {
    let selected: SexFilter
    let onSelect: (SexFilter) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SexFilter.allCases, id: \.self) { filter in
                Button(action: { onSelect(filter) }) {
                    Text(filter.rawValue)
                        .font(.caption)
                        .fontWeight(selected == filter ? .semibold : .regular)
                        .foregroundColor(selected == filter ? .white : .textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(selected == filter ? Color.accentColor : Color.bgInput)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(filter.rawValue) sex filter")
                .accessibilityAddTraits(selected == filter ? .isSelected : [])
            }
        }
    }
}
