import SwiftUI

struct SettingsView: View {
    @State private var appearance = AppearanceManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Birth Date")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text("Set your birth date to enable life progress and death clock calculations.")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Data Import")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text("Import health data from Apple Health exports (JSON or XML format).")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                VStack(alignment: .leading, spacing: 12) {
                    Text("About")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    HStack {
                        Text("Version")
                            .foregroundColor(.textSecondary)
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.textMuted)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
            .padding()
        }
        .background(Color.bg)
        .navigationTitle("Settings")
    }
}
