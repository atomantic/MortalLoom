import SwiftUI

/// Full list of every source that backs a health claim in the app. Rendered from
/// `CitationLibrary.sections` so that adding a citation in one place (the library)
/// automatically updates this screen and any inline `CitationBadge` that references it.
struct CitationsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Sources & Citations")
                    .font(.title2).fontWeight(.bold)
                    .foregroundColor(.textPrimary)
                    .padding(.bottom, 4)

                Text("MortalLoom's health calculations, recommendations, and reference ranges are based on peer-reviewed research, government health databases, and established clinical guidelines. Every claim the app makes about your health links back to one of these sources. Tap the info badge next to any recommendation, risk level, or reference range to jump directly to the source behind it.")
                    .font(.caption)
                    .foregroundColor(.textSecondary)

                ForEach(CitationLibrary.sections) { section in
                    citationSection(section)
                }

                // Disclaimer
                VStack(alignment: .leading, spacing: 8) {
                    Divider().background(Color.cardBorder)
                    Text("Disclaimer")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.textSecondary)
                    Text("MortalLoom provides informational health estimates based on published research and is not a substitute for professional medical advice, diagnosis, or treatment. Life expectancy calculations are statistical estimates, not individual predictions. Always consult a qualified healthcare provider for medical decisions.")
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .background(Color.bg)
        .macSheetFrame()
    }

    // MARK: - Components

    private func citationSection(_ section: CitationLibrary.Section) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .foregroundColor(.accentColor)
                    .font(.subheadline)
                Text(section.title)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.textPrimary)
            }

            ForEach(CitationLibrary.resolve(section.citationIds)) { citation in
                citationCard(citation)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func citationCard(_ citation: Citation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(citation.title)
                .font(.caption).fontWeight(.medium)
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
                        Text("View Source")
                            .font(.caption2)
                    }
                    .foregroundColor(.accentColor)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard.opacity(0.5))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
