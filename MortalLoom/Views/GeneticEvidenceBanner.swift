import SwiftUI

/// Renders the "🧬 Suggested by your DNA" provenance banner on Habit and
/// Goal edit sheets. Tapping the banner closes the current sheet, navigates
/// to the Genome page, and opens the originating finding's detail sheet via
/// the `.openGenomeFinding` notification.
struct GeneticEvidenceBanner: View {
    let evidence: GeneticEvidence
    let dismiss: DismissAction

    var body: some View {
        Button(action: tapBack) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "allergens")
                        .foregroundColor(.accentColor)
                    Text("Suggested by your DNA: \(evidence.gene)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                    Spacer()
                    HStack(spacing: 2) {
                        Text("View finding")
                            .font(.caption2)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundColor(.accentColor.opacity(0.8))
                }
                Text(evidence.reason)
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the originating genome finding")
    }

    private func tapBack() {
        dismiss()
        // Defer the navigation so (a) the dismissing sheet has a chance to
        // release its presentation state and (b) GenomeView has time to mount
        // and subscribe to `.openGenomeFinding` before we fire it. Without
        // this gap SwiftUI silently drops the second `.sheet(item:)` update.
        let rsid = evidence.rsid
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NotificationCenter.default.post(name: .navigateToPage, object: AppPage.genome)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(name: .openGenomeFinding, object: rsid)
        }
    }
}
