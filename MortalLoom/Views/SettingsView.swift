import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

struct SettingsView: View {
    @State private var appearance = AppearanceManager.shared
    @StateObject private var healthKit = HealthKitService.shared

    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportData: Data? = nil
    @State private var showResetConfirmation = false
    @State private var importMessage: String? = nil
    @State private var importSuccess = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                appearanceSection
                healthKitSection
                dataExportSection
                dataImportSection
                aboutSection
                setupGuideSection
                dangerZoneSection
            }
            .padding()
        }
        .background(Color.bg)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
    }

    // MARK: - Appearance

    @ViewBuilder
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "APPEARANCE")

            Text("Theme")
                .font(.subheadline).fontWeight(.medium)
                .foregroundColor(.textSecondary)

            Picker("Appearance", selection: $appearance.mode) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Apple Health

    @ViewBuilder
    private var healthKitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "APPLE HEALTH")

            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundColor(healthKit.authorized ? .success : .textMuted)

                VStack(alignment: .leading, spacing: 2) {
                    Text("HealthKit")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.textPrimary)
                    Text(healthKit.authorized ? "Connected" : "Not connected")
                        .font(.caption)
                        .foregroundColor(healthKit.authorized ? .success : .textMuted)
                }

                Spacer()

                if !healthKit.authorized {
                    Button {
                        Task { await healthKit.requestAuthorization() }
                    } label: {
                        Text("Connect")
                            .font(.subheadline).fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.success)
                        .font(.title3)
                }
            }

            if !healthKit.isAvailable {
                Text("HealthKit is not available on this device.")
                    .font(.caption)
                    .foregroundColor(.warning)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Data Export

    @ViewBuilder
    private var dataExportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "DATA EXPORT")

            Text("Export all your MortalLoom data as a JSON file. This includes your profile, lifestyle, blood tests, substance logs, and more.")
                .font(.caption)
                .foregroundColor(.textSecondary)

            if let data = exportData {
                ShareLink(
                    item: ExportedJSON(data: data),
                    preview: SharePreview("MortalLoom Data", image: Image(systemName: "doc.text"))
                ) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share Export")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
            } else {
                Button {
                    Task {
                        exportData = await DataStore.shared.exportData()
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.doc")
                        Text("Prepare Export")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Data Import

    @ViewBuilder
    private var dataImportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "DATA IMPORT")

            Text("Import a previously exported MortalLoom JSON file. This will replace all current data.")
                .font(.caption)
                .foregroundColor(.textSecondary)

            Button {
                showImporter = true
            } label: {
                HStack {
                    Image(systemName: "arrow.up.doc")
                    Text("Import JSON")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)

            if let message = importMessage {
                HStack(spacing: 6) {
                    Image(systemName: importSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(importSuccess ? .success : .danger)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(importSuccess ? .success : .danger)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - About

    @ViewBuilder
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "ABOUT")

            HStack {
                Text("Version")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                Spacer()
                Text(appVersion)
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundColor(.textMuted)
            }

            Divider()
                .background(Color.cardBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("Privacy")
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundColor(.textPrimary)
                Text("Your data stays on your device and in your iCloud — never on our servers.")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }

            Divider()
                .background(Color.cardBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("MortalLoom")
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundColor(.textPrimary)
                Text("Privacy-first longevity tracking. No accounts, no logins, no data collection, no telemetry, no third-party tracking.")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Setup Guide

    @ViewBuilder
    private var setupGuideSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "SETUP")

            Button {
                UserDefaults.standard.set(false, forKey: AppConstants.hasCompletedOnboardingKey)
                NotificationCenter.default.post(name: .showOnboarding, object: nil)
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Show Setup Guide")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)

            Text("Re-run the onboarding wizard to update your profile data.")
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Danger Zone

    @ViewBuilder
    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "DANGER ZONE")

            if showResetConfirmation {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Are you sure? This will permanently delete all your data.")
                        .font(.caption)
                        .foregroundColor(.danger)

                    HStack(spacing: 12) {
                        Button {
                            showResetConfirmation = false
                        } label: {
                            Text("Cancel")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            Task { await resetAllData() }
                        } label: {
                            Text("Yes, Delete Everything")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.danger)
                    }
                }
            } else {
                Button {
                    showResetConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Reset All Data")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.danger)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Helpers

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                importMessage = "No file selected."
                importSuccess = false
                return
            }
            guard url.startAccessingSecurityScopedResource() else {
                importMessage = "Unable to access the file."
                importSuccess = false
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            guard let data = try? Data(contentsOf: url) else {
                importMessage = "Failed to read file."
                importSuccess = false
                return
            }

            Task {
                let success = await DataStore.shared.importData(from: data)
                importSuccess = success
                importMessage = success
                    ? "Data imported successfully."
                    : "Invalid MortalLoom data file."
                exportData = nil
            }

        case .failure:
            importMessage = "Import cancelled."
            importSuccess = false
        }
    }

    private func resetAllData() async {
        await DataStore.shared.save(.empty)
        exportData = nil
        showResetConfirmation = false
        importMessage = nil
        UserDefaults.standard.set(false, forKey: AppConstants.hasCompletedOnboardingKey)
        NotificationCenter.default.post(name: .showOnboarding, object: nil)
    }
}

// MARK: - Export Helper

struct ExportedJSON: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { item in
            item.data
        }
    }
}
