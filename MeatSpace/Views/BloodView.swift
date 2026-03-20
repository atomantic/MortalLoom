import SwiftUI

struct BloodView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Blood Tests")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text("Track metabolic panels, lipid panels, CBC, and 50+ lab markers with reference ranges.")
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
        .navigationTitle("Blood")
    }
}
