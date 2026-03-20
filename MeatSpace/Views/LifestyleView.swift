import SwiftUI

struct LifestyleView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lifestyle Profile")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text("Configure your health profile: sex, smoking status, exercise minutes, sleep hours, diet quality, stress level, BMI, and chronic conditions.")
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
        .navigationTitle("Lifestyle")
    }
}
