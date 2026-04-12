import SwiftUI

/// A small tappable "info" icon that surfaces the primary source(s) behind a health
/// claim shown to the user. Tapping presents a popover listing each linked
/// `Citation` with title, authors, detail, and a link to the source.
///
/// Usage:
/// ```
/// HStack {
///     Text("7-9 hours of sleep")
///     CitationBadge(ids: [CitationLibrary.cappuccioSleep2010.id,
///                         CitationLibrary.nsfSleepDuration.id])
/// }
/// ```
struct CitationBadge: View {
    let ids: [String]
    /// Optional label shown above the citation list (e.g. "Source for 150 min/week").
    var claim: String? = nil
    /// Visual size — defaults to a small inline badge.
    var size: Size = .small

    enum Size {
        case small, medium
        var font: Font {
            switch self {
            case .small: return .caption2
            case .medium: return .caption
            }
        }
        var iconFont: Font {
            switch self {
            case .small: return .caption2
            case .medium: return .footnote
            }
        }
    }

    @State private var showPopover = false

    private var citations: [Citation] {
        CitationLibrary.resolve(ids)
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(size.iconFont)
                .foregroundColor(.accentColor)
                .accessibilityLabel("View source citations")
                .accessibilityHint("Shows the peer-reviewed sources behind this claim")
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            CitationPopoverContent(citations: citations, claim: claim)
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 420)
                .presentationCompactAdaptation(.popover)
        }
        .disabled(citations.isEmpty)
        .opacity(citations.isEmpty ? 0 : 1)
    }
}

// MARK: - Popover Content

private struct CitationPopoverContent: View {
    let citations: [Citation]
    let claim: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "book.closed.fill")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Text(citations.count > 1 ? "Sources" : "Source")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.textPrimary)
                }

                if let claim, !claim.isEmpty {
                    Text(claim)
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .italic()
                }

                ForEach(citations) { citation in
                    citationRow(citation)
                }

                if !citations.isEmpty {
                    Divider().background(Color.cardBorder)
                    Text("MortalLoom provides informational estimates — not medical advice. Always consult a qualified healthcare provider for medical decisions.")
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                }
            }
            .padding(16)
        }
        .background(Color.bgCard)
    }

    @ViewBuilder
    private func citationRow(_ citation: Citation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(citation.title)
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(citation.authors)
                .font(.caption2)
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(citation.detail)
                .font(.caption2)
                .foregroundColor(.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let url = URL(string: citation.url) {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.caption2)
                        Text("View source")
                            .font(.caption2).fontWeight(.medium)
                    }
                    .foregroundColor(.accentColor)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bg.opacity(0.5))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Convenience: "Source: NIAAA ⓘ" inline row

/// A single-line attribution row: `book icon + "Source: <label>" + info badge`.
/// Shows up under cards where the claim is a whole threshold/reference (e.g.
/// alcohol risk, BMI categories).
struct CitationSourceRow: View {
    let label: String
    let ids: [String]
    var claim: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "book.closed.fill")
                .font(.caption2)
            Text(label)
                .font(.caption2)
            CitationBadge(ids: ids, claim: claim)
        }
        .foregroundColor(.accentColor)
    }
}
