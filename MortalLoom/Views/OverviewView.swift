import SwiftUI

struct OverviewView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Death Clock
                VStack(spacing: 8) {
                    Text("Life Progress")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text("Configure your birth date and lifestyle in Settings to see your mortality countdown.")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .cardStyle()

                // Health Summary Grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    MetricCard(title: "Steps", value: "--", icon: "figure.walk", color: .success)
                    MetricCard(title: "Heart Rate", value: "--", icon: "heart.fill", color: .accent)
                    MetricCard(title: "Sleep", value: "--", icon: "bed.double.fill", color: .purple)
                    MetricCard(title: "Weight", value: "--", icon: "scalemass.fill", color: .blue)
                    MetricCard(title: "Alcohol", value: "--", icon: "wineglass.fill", color: .warning)
                    MetricCard(title: "Nicotine", value: "--", icon: "smoke.fill", color: .orange)
                }
            }
            .padding()
        }
        .background(Color.bg)
        .navigationTitle("Overview")
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Spacer()
            }
            Text(value)
                .font(.title2).fontWeight(.bold)
                .foregroundColor(.textPrimary)
            Text(title)
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .padding()
        .cardStyle()
    }
}
