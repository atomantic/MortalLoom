import SwiftUI

// MARK: - Genome Severity Colors
//
// SwiftUI `Color` mappings for genome priority findings. These live in the
// Theme layer (not the pure GenomePriorityEngine) so the engine stays free of
// framework coupling — it imports only Foundation and computes scores/labels,
// while presentation concerns like color live here.

/// Polarity-aware color for marker findings — `concern` on a protective marker
/// is "no benefit variant", not an elevated risk, so it stays neutral.
func severityColor(for source: PriorityFindingSource) -> Color {
    switch source {
    case .marker(let r):
        switch (r.status, r.marker.polarity) {
        case (.majorConcern, .risk): return .red
        case (.concern, .risk): return .orange
        case (.beneficial, _): return .green
        case (.concern, .protective), (.majorConcern, .protective): return .secondary
        case (.typical, _), (.notFound, _): return .secondary
        }
    case .clinvar(let h):
        return clinvarSeverityColor(h.entry.severity)
    case .apoe(let a):
        switch a.status {
        case .majorConcern: return .red
        case .concern: return .orange
        case .beneficial: return .green
        default: return .secondary
        }
    }
}

func clinvarSeverityColor(_ severity: String) -> Color {
    switch severity {
    case "pathogenic": .red
    case "drug_response", "risk_factor": .orange
    case "protective": .green
    default: .secondary
    }
}
