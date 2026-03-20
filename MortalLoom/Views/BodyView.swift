import SwiftUI

struct BodyView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Body Composition")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text("Track weight, body fat percentage, and eye prescriptions.")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Eye Prescriptions")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text("No eye exams recorded yet.")
                        .font(.subheadline)
                        .foregroundColor(.textMuted)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
            .padding()
        }
        .background(Color.bg)
        .navigationTitle("Body")
    }
}
