import SwiftUI

struct SubstancesView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Alcohol Tracking")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text("Log drinks with name, ounces, ABV%, and quantity. View rolling averages and NIAAA risk levels.")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Nicotine Tracking")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text("Log nicotine products with mg per unit and quantity. View daily summaries and health correlations.")
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
        .navigationTitle("Substances")
    }
}
