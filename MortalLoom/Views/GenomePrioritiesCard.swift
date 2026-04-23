import SwiftUI

/// Pinned-top synthesis card for the Genome tab. Shows the top N priority
/// findings ranked by `GenomePriorityEngine`. Each row's subtitle is the
/// top action — that's what makes this not a duplicate of the categories.
///
/// Tapping a row opens the same `GenomeDetailSheet` used by category browse.
struct GenomePrioritiesCard: View {
    let priorities: [PriorityFinding]
    let totalCandidateCount: Int
    let onSelectFinding: (GenomeFinding) -> Void
    let onStartVisit: () -> Void
    let onExportPDF: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if priorities.isEmpty {
                emptyState
            } else {
                ForEach(priorities, id: \.id) { priority in
                    priorityRow(priority)
                    if priority.id != priorities.last?.id {
                        Divider().padding(.leading, 22)
                    }
                }
                actionFooter
            }
        }
        .padding()
        .cardStyle()
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.subheadline)
                .foregroundColor(.orange)
            Text("Your Top Priorities")
                .font(.headline)
                .foregroundColor(.textPrimary)
            Spacer()
            if totalCandidateCount > 0 {
                Text("\(priorities.count) of \(totalCandidateCount)")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.success)
                Text("No urgent priorities right now.")
                    .font(.subheadline)
                    .foregroundColor(.textPrimary)
            }
            Text("Browse categories below to explore your variants. As we expand the curated action library, more findings will surface here.")
                .font(.caption)
                .foregroundColor(.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func priorityRow(_ priority: PriorityFinding) -> some View {
        Button(action: { onSelectFinding(toFinding(priority)) }) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(severityColor(priority))
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(priority.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        statusPill(priority)
                    }
                    if let action = priority.topAction {
                        Text(action.title)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Tap for details")
                            .font(.caption)
                            .foregroundColor(.textMuted)
                    }
                    if priority.actionCount > 0 {
                        actionStateLine(priority.stateCounts, total: priority.actionCount)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.textMuted)
                    .padding(.top, 4)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func actionStateLine(_ counts: ActionStateCounts, total: Int) -> some View {
        HStack(spacing: 6) {
            if counts.pending > 0 {
                Text("\(counts.pending) pending")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            if counts.inProgress > 0 {
                Text("\(counts.inProgress) in progress")
                    .font(.caption2)
                    .foregroundColor(.accentColor)
            }
            if counts.discussed > 0 {
                Text("\(counts.discussed) discussed")
                    .font(.caption2)
                    .foregroundColor(.success)
            }
            if counts.done > 0 {
                Text("\(counts.done) done")
                    .font(.caption2)
                    .foregroundColor(.success)
            }
            if counts.total < total {
                Text("· \(total - counts.total) untouched")
                    .font(.caption2)
                    .foregroundColor(.textMuted)
            }
        }
    }

    private func statusPill(_ priority: PriorityFinding) -> some View {
        Text(priority.statusLabel)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(severityColor(priority))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(severityColor(priority).opacity(0.12))
            .cornerRadius(4)
    }

    private var actionFooter: some View {
        HStack(spacing: 10) {
            Button(action: onStartVisit) {
                Label("Start Doctor Visit", systemImage: "stethoscope")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Button(action: onExportPDF) {
                Label("Export PDF", systemImage: "square.and.arrow.up")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func severityColor(_ priority: PriorityFinding) -> Color {
        switch priority.source {
        case .marker(let r):
            switch r.status {
            case .majorConcern: .red
            case .concern: .orange
            case .beneficial: .green
            default: .secondary
            }
        case .clinvar(let h):
            switch h.entry.severity {
            case "pathogenic": .red
            case "risk_factor", "drug_response": .orange
            case "protective": .green
            default: .secondary
            }
        case .apoe(let a):
            switch a.status {
            case .majorConcern: .red
            case .concern: .orange
            case .beneficial: .green
            default: .secondary
            }
        }
    }

    private func toFinding(_ priority: PriorityFinding) -> GenomeFinding {
        switch priority.source {
        case .marker(let r): .marker(r)
        case .clinvar(let h): .clinvar(h)
        case .apoe(let a): .apoe(a)
        }
    }
}
