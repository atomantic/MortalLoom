import SwiftUI

// MARK: - Stagnation Severity Colors
//
// SwiftUI `Color` mapping for stagnation signals. This lives in the Theme layer
// (not the pure StagnationEngine) so the engine stays free of framework
// coupling — it imports only Foundation and computes signals/severities, while
// presentation concerns like color live here. Mirrors Theme/GenomeSeverityColors.swift.

extension StagnationSeverity {
    /// Semantic tint color for this severity. Centralised here so OverviewView,
    /// CheckInSheet, and ReportsView all render the same color for a given
    /// signal without duplicating the mapping.
    var tintColor: Color {
        switch self {
        case .info: .accentColor
        case .warn: .warning
        case .alert: .danger
        }
    }
}
