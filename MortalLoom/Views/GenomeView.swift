import SwiftUI

struct GenomeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Genome Analysis")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text("Upload raw genome data from 23andMe, AncestryDNA, or MyHeritage. Cross-reference against ClinVar for pathogenicity assessment.")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
            .padding()
        }
        .background(Color.bg)
        .navigationTitle("Genome")
    }
}
