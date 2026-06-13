import SwiftUI
import StoreKit
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if canImport(MessageUI)
import MessageUI
#endif

struct SettingsView: View {
    @Environment(StoreManager.self) private var store
    @State private var appearance = AppearanceManager.shared
    @State private var healthKit = HealthKitService.shared

    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportDocument: MortalLoomExportDocument? = nil
    @State private var exportFilename: String = "MortalLoom.json"
    @State private var isPreparingExport = false
    @State private var exportMessage: String? = nil
    /// UNIX epoch (seconds) of the last successful export. 0 means never.
    /// Surfaces a nag banner when stale.
    @AppStorage("lastExportEpoch") private var lastExportEpoch: Double = 0
    /// Days after which we consider the last export stale and nag the user.
    private let exportStaleAfterDays: Double = 14
    @State private var showResetConfirmation = false
    @State private var importMessage: String? = nil
    @State private var backups: [URL] = []
    @State private var selectedBackup: URL? = nil
    @State private var showRestoreConfirmation = false
    @State private var restoreMessage: String? = nil
    @State private var restoreSuccess = false
    @State private var importSuccess = false

    @State private var countdownMode: CountdownMode = .standard
    @State private var levTargetAge: Double = 120
    @State private var levTargetAgeText: String = "120"
    @FocusState private var levAgeFieldFocused: Bool

    @State private var showPaywall = false
    @State private var showCitations = false
    @State private var showingMailComposer = false
    @State private var showRedeemSheet = false

    private static let feedbackEmail = "mortalloom@shadowpuppet.net"

    // Default on — the entire goal-alignment loop depends on a weekly
    // review. Users who want silence can still turn it off here, but we
    // don't start them out silent.
    @AppStorage(NotificationService.weeklyReviewEnabledKey)
    private var weeklyReviewEnabled: Bool = true
    @AppStorage(NotificationService.weeklyReviewWeekdayKey)
    private var weeklyReviewWeekday: Int = 1  // Sunday
    @AppStorage(NotificationService.weeklyReviewHourKey)
    private var weeklyReviewHour: Int = 18
    @AppStorage(NotificationService.stagnationAlertsEnabledKey)
    private var stagnationAlertsEnabled: Bool = false

    @AppStorage(HabitTab.showAlcoholKey) private var habitsShowAlcohol: Bool = true
    @AppStorage(HabitTab.showNicotineKey) private var habitsShowNicotine: Bool = true
    @AppStorage(HabitTab.showSaunaKey) private var habitsShowSauna: Bool = true

    var body: some View {
        settingsContent
            .background(Color.bg)
            .task { await loadCountdownMode() }
            .onReceive(NotificationCenter.default.publisher(for: .profileDidChange)) { _ in
                Task { await loadCountdownMode() }
            }
            // An iCloud sync now posts only `.dataDidSync` (#31); observe it too
            // so a countdown-mode change synced from another device still
            // refreshes this screen.
            .onReceive(NotificationCenter.default.publisher(for: .dataDidSync)) { _ in
                Task { await loadCountdownMode() }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(isPresented: $showCitations) { CitationsView() }
            #if os(iOS)
            .sheet(isPresented: $showingMailComposer) {
                MailComposer(
                    recipient: Self.feedbackEmail,
                    subject: "MortalLoom Feedback",
                    body: feedbackBody,
                    onDismiss: { showingMailComposer = false }
                )
                .ignoresSafeArea()
            }
            #endif
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
    }

    // MARK: - Layout

    @ViewBuilder
    private var settingsContent: some View {
        #if os(iOS)
        iOSTabbedSettings
        #else
        macOSColumnsSettings
        #endif
    }

    // iOS: tabbed so each group fits one screen without scrolling
    #if os(iOS)
    private var iOSTabbedSettings: some View {
        TabView {
            ScrollView {
                VStack(spacing: 16) {
                    // Setup Guide lives at the top of General so users who
                    // bailed partway through onboarding can finish setup in
                    // one tap rather than hunting through a sub-tab.
                    setupGuideSection
                    proSection
                    appearanceSection
                    countdownSection
                    habitsTrackersSection
                    notificationsSection
                }
                .padding()
            }
            .tabItem { Label("General", systemImage: "gearshape") }

            ScrollView {
                VStack(spacing: 16) {
                    iCloudSyncSection
                    healthKitSection
                    dataExportSection
                    dataImportSection
                    dataRestoreSection
                    dangerZoneSection
                }
                .padding()
            }
            .tabItem { Label("Data", systemImage: "externaldrive") }

            ScrollView {
                VStack(spacing: 16) {
                    aboutSection
                    supportSection
                }
                .padding()
            }
            // Sub-tab is labelled "About" — the bottom nav already has a
            // "More" tab, and the duplicate label was confusing.
            .tabItem { Label("About", systemImage: "info.circle") }
        }
    }
    #endif

    // macOS: responsive columns via GeometryReader (like CSS media queries)
    // ≥ 860pt → 3 columns  |  ≥ 540pt → 2 columns  |  < 540pt → 1 column
    #if os(macOS)
    private var macOSColumnsSettings: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ScrollView {
                Group {
                    if w >= 860 {
                        HStack(alignment: .top, spacing: 16) {
                            col1.frame(maxWidth: .infinity)
                            col2.frame(maxWidth: .infinity)
                            col3.frame(maxWidth: .infinity)
                        }
                    } else if w >= 540 {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(spacing: 16) { col1; col3 }.frame(maxWidth: .infinity)
                            col2.frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(spacing: 16) { col1; col2; col3 }
                    }
                }
                .padding()
            }
        }
    }

    private var col1: some View {
        VStack(spacing: 16) {
            setupGuideSection
            countdownSection
            habitsTrackersSection
            notificationsSection
        }
    }

    private var col2: some View {
        VStack(spacing: 16) {
            iCloudSyncSection
            dataExportSection
            dataImportSection
            dataRestoreSection
            dangerZoneSection
        }
    }

    private var col3: some View {
        VStack(spacing: 16) {
            appearanceSection
            aboutSection
            supportSection
            proSection
        }
    }
    #endif

    // MARK: - Pro

    @ViewBuilder
    private var proSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "MORTALLOOM PRO")

            if store.isPro {
                HStack(spacing: 12) {
                    Image(systemName: "star.circle.fill")
                        .font(.title2)
                        .foregroundStyle(LinearGradient.proBrand)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pro Unlocked")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.textPrimary)
                        Text("All features are available")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                }
            } else {
                Text("Unlock genome analysis, blood marker trend insights, epigenetic age tracking, and eye prescription history.")
                    .font(.caption)
                    .foregroundColor(.textSecondary)

                Button {
                    showPaywall = true
                } label: {
                    HStack {
                        Image(systemName: "star.circle.fill")
                        Text("Unlock Pro")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }

                redeemCodeButton
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // Offer code redemption. On iOS/iPadOS/visionOS we present the built-in
    // sheet via the SwiftUI modifier. macOS has no in-app sheet API for this
    // — Apple routes users through the App Store app, so we open that
    // directly via the macappstore:// redeem URL.
    @ViewBuilder
    private var redeemCodeButton: some View {
        #if os(macOS)
        Button {
            if let url = URL(string: "macappstore://apps.apple.com/redeem") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            redeemLabel
        }
        .buttonStyle(.plain)
        #else
        Button {
            showRedeemSheet = true
        } label: {
            redeemLabel
        }
        .buttonStyle(.plain)
        .offerCodeRedemption(isPresented: $showRedeemSheet) { result in
            if case .success = result {
                Task { await store.restorePurchases() }
            }
        }
        #endif
    }

    private var redeemLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "gift")
            Text("Redeem Code")
                .fontWeight(.medium)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
        }
        .font(.subheadline)
        .foregroundColor(.accentColor)
        .padding(.vertical, 8)
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

    // MARK: - Notifications

    @ViewBuilder
    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "NOTIFICATIONS")

            Text("Local reminders only — nothing leaves your device.")
                .font(.caption)
                .foregroundColor(.textSecondary)

            Toggle("Weekly review reminder", isOn: $weeklyReviewEnabled)
                .onChange(of: weeklyReviewEnabled) { _, enabled in
                    Task { await NotificationService.shared.setWeeklyReviewEnabled(enabled) }
                }

            if weeklyReviewEnabled {
                HStack {
                    Text("Day")
                        .font(.subheadline)
                    Spacer()
                    Picker("Day", selection: $weeklyReviewWeekday) {
                        Text("Sunday").tag(1)
                        Text("Monday").tag(2)
                        Text("Tuesday").tag(3)
                        Text("Wednesday").tag(4)
                        Text("Thursday").tag(5)
                        Text("Friday").tag(6)
                        Text("Saturday").tag(7)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                HStack {
                    Text("Hour")
                        .font(.subheadline)
                    Spacer()
                    Stepper(value: $weeklyReviewHour, in: 0...23) {
                        Text("\(formatHour(weeklyReviewHour))")
                            .monospacedDigit()
                    }
                }
                .onChange(of: weeklyReviewWeekday) { _, _ in
                    Task { await NotificationService.shared.scheduleWeeklyReviewReminder() }
                }
                .onChange(of: weeklyReviewHour) { _, _ in
                    Task { await NotificationService.shared.scheduleWeeklyReviewReminder() }
                }
            }

            Toggle("Stagnation alerts", isOn: $stagnationAlertsEnabled)
                .onChange(of: stagnationAlertsEnabled) { _, enabled in
                    Task { await NotificationService.shared.setStagnationAlertsEnabled(enabled) }
                }

            Text("Fires ~15 minutes after the app detects a stalling goal or habit. Mute specific alerts per goal in the Goal editor.")
                .font(.caption2)
                .foregroundColor(.textMuted)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func formatHour(_ hour: Int) -> String {
        let h = hour % 24
        let period = h < 12 ? "AM" : "PM"
        let display = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return "\(display):00 \(period)"
    }

    // MARK: - Countdown Mode

    @ViewBuilder
    private var habitsTrackersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "HABITS TRACKERS")

            Text("Choose which built-in trackers appear as tabs on the Habits page. Hiding a tracker keeps your logged data — it just stops showing up in the picker.")
                .font(.caption)
                .foregroundColor(.textSecondary)

            Toggle("Show Alcohol", isOn: $habitsShowAlcohol)
            Toggle("Show Nicotine", isOn: $habitsShowNicotine)
            Toggle("Show Sauna", isOn: $habitsShowSauna)
        }
        .padding()
        .cardStyle()
    }

    @ViewBuilder
    private var countdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "DEFAULT COUNTDOWN")

            Text("Choose which countdown to display by default on the Overview and Calendar.")
                .font(.caption)
                .foregroundColor(.textSecondary)

            Picker("Countdown Mode", selection: $countdownMode) {
                ForEach(CountdownMode.allCases, id: \.self) { mode in
                    Text(mode.pickerLabel).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: countdownMode) { _, newMode in
                Task {
                    var data = await DataStore.shared.getData()
                    data.profile.countdownMode = newMode
                    await DataStore.shared.save(data)
                    NotificationCenter.default.post(name: .profileDidChange, object: nil)
                }
            }

            if countdownMode == .lev {
                HStack {
                    Text("LEV target lifespan")
                        .font(.subheadline)
                    Spacer()
                    Stepper(value: $levTargetAge, in: 100...500, step: 5) {
                        HStack(spacing: 4) {
                            TextField("", text: $levTargetAgeText)
                                .textFieldStyle(.plain)
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(.textPrimary)
                                .frame(width: 48)
                                .multilineTextAlignment(.trailing)
                                .focused($levAgeFieldFocused)
                                .onSubmit { commitLEVAge() }
                                .onChange(of: levAgeFieldFocused) { _, focused in
                                    if !focused { commitLEVAge() }
                                }
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .accessibilityLabel("LEV target lifespan in years")
                            Text("yr")
                                .font(.subheadline)
                                .foregroundColor(.textPrimary)
                        }
                    }
                    .onChange(of: levTargetAge) { oldAge, newAge in
                        guard newAge != oldAge else { return }
                        levTargetAgeText = "\(Int(newAge))"
                        Task {
                            var data = await DataStore.shared.getData()
                            data.profile.levTargetAge = newAge
                            await DataStore.shared.save(data)
                            NotificationCenter.default.post(name: .profileDidChange, object: nil)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.textMuted)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 2) {
                    Text(CountdownMode.standardBlurb)
                        .font(.system(size: 10))
                        .foregroundColor(.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(CountdownMode.levBlurb)
                        .font(.system(size: 10))
                        .foregroundColor(.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func loadCountdownMode() async {
        let data = await DataStore.shared.getData()
        countdownMode = data.profile.countdownMode
        levTargetAge = data.profile.levTargetAge
        levTargetAgeText = "\(Int(data.profile.levTargetAge))"
    }

    private func commitLEVAge() {
        let parsed = Double(levTargetAgeText.trimmingCharacters(in: .whitespaces)) ?? levTargetAge
        let clamped = min(max(parsed, 100), 500)
        levTargetAgeText = "\(Int(clamped))"  // always correct display (handles out-of-range input)
        levTargetAge = clamped                 // triggers save via onChange if value actually changed
    }

    // MARK: - Apple Health

    @ViewBuilder
    private var healthKitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "APPLE HEALTH")

            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundColor(healthKit.authorizationRequestCompleted ? .success : .textMuted)

                VStack(alignment: .leading, spacing: 2) {
                    Text("HealthKit")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.textPrimary)
                    Text(healthKit.authorizationRequestCompleted ? "Access requested" : "Not requested")
                        .font(.caption)
                        .foregroundColor(healthKit.authorizationRequestCompleted ? .success : .textMuted)
                }

                Spacer()

                if !healthKit.authorizationRequestCompleted {
                    Button {
                        Task { await healthKit.requestAuthorization() }
                    } label: {
                        Text("Connect")
                            .font(.subheadline).fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .accessibilityLabel("Connect Apple Health")
                    .accessibilityHint("Request permission to read health data")
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.success)
                        .font(.title3)
                        .accessibilityLabel("Apple Health connected")
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

    // MARK: - iCloud Sync

    @ViewBuilder
    private var iCloudSyncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "ICLOUD SYNC")

            HStack(spacing: 12) {
                Image(systemName: ICloudMonitor.shared.isICloud ? "icloud.fill" : "icloud.slash")
                    .font(.title2)
                    .foregroundColor(ICloudMonitor.shared.isICloud ? .accentColor : .textMuted)

                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.textPrimary)
                    Text(ICloudMonitor.shared.isICloud ? "Syncing across devices" : "Not available — sign in to iCloud in Settings")
                        .font(.caption)
                        .foregroundColor(ICloudMonitor.shared.isICloud ? .success : .textMuted)
                }

                Spacer()

                if ICloudMonitor.shared.isICloud {
                    Button {
                        Task { await ICloudMonitor.shared.syncNow() }
                    } label: {
                        if ICloudMonitor.shared.isSyncing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath.icloud")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .disabled(ICloudMonitor.shared.isSyncing)
                    .accessibilityLabel("Sync with iCloud")
                }
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

            if isExportStale {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.warning)
                    Text(exportStaleMessage)
                        .font(.caption)
                        .foregroundColor(.textPrimary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.warning.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.warning.opacity(0.4), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Button {
                Task { await prepareExport() }
            } label: {
                HStack {
                    if isPreparingExport {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                    Text(isPreparingExport ? "Preparing…" : "Save Export…")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .disabled(isPreparingExport)

            if let msg = exportMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success(let url):
                exportMessage = "Saved to \(url.lastPathComponent)"
                lastExportEpoch = Date().timeIntervalSince1970
            case .failure(let error):
                exportMessage = "Export failed: \(error.localizedDescription)"
            }
            exportDocument = nil
        }
    }

    /// True when the user either has never exported, or the last export is
    /// older than `exportStaleAfterDays`.
    private var isExportStale: Bool {
        guard lastExportEpoch > 0 else { return true }
        let last = Date(timeIntervalSince1970: lastExportEpoch)
        let staleInterval = exportStaleAfterDays * 24 * 60 * 60
        return Date().timeIntervalSince(last) > staleInterval
    }

    /// Human-readable message for the staleness banner.
    private var exportStaleMessage: String {
        guard lastExportEpoch > 0 else {
            return "No export on file yet — save one now as a backup."
        }
        let last = Date(timeIntervalSince1970: lastExportEpoch)
        let days = Int(Date().timeIntervalSince(last) / (24 * 60 * 60))
        return "Last export was \(days) days ago — consider saving a fresh backup."
    }

    private func prepareExport() async {
        isPreparingExport = true
        defer { isPreparingExport = false }
        guard let data = await DataStore.shared.exportData() else {
            exportMessage = "No data to export."
            return
        }
        let stamp = Self.exportTimestamp()
        exportFilename = "MortalLoom-\(stamp).json"
        exportDocument = MortalLoomExportDocument(data: data)
        exportMessage = nil
        showExporter = true
    }

    private static func exportTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
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
                .accessibilityElement(children: .combine)
                .accessibilityLabel(importSuccess ? "Import succeeded: \(message)" : "Import failed: \(message)")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Restore from Backup

    @ViewBuilder
    private var dataRestoreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "RESTORE FROM BACKUP")

            Text("MortalLoom keeps the last 10 automatic backups — one before every reset or import. Restoring will replace your current data with the chosen backup; the current data is first snapshotted as \"pre-restore\" so you can undo if you pick the wrong one.")
                .font(.caption)
                .foregroundColor(.textSecondary)

            if backups.isEmpty {
                Text("No backups yet. Backups are created automatically before resets and imports.")
                    .font(.caption)
                    .foregroundColor(.textMuted)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 4) {
                    ForEach(backups, id: \.self) { url in
                        backupRow(url)
                    }
                }
            }

            if let msg = restoreMessage {
                HStack(spacing: 6) {
                    Image(systemName: restoreSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(restoreSuccess ? .success : .danger)
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(restoreSuccess ? .success : .danger)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .task { await refreshBackups() }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidSync)) { _ in
            Task { await refreshBackups() }
        }
        .alert("Restore from backup?", isPresented: $showRestoreConfirmation, presenting: selectedBackup) { url in
            Button("Restore", role: .destructive) {
                Task { await performRestore(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { url in
            Text("This will replace your current data with the contents of \(url.lastPathComponent). Your current state will be snapshotted as a pre-restore backup first.")
        }
    }

    private func backupRow(_ url: URL) -> some View {
        let meta = backupMetadata(url)
        return Button {
            selectedBackup = url
            showRestoreConfirmation = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(meta.displayDate)
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.textPrimary)
                    HStack(spacing: 6) {
                        Text(meta.reasonLabel)
                            .font(.caption2).fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(meta.reasonColor.opacity(0.2))
                            .foregroundColor(meta.reasonColor)
                            .clipShape(Capsule())
                        Text(meta.sizeString)
                            .font(.caption)
                            .foregroundColor(.textMuted)
                    }
                }
                Spacer()
                Image(systemName: "arrow.counterclockwise")
                    .foregroundColor(.accentColor)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Color.bgCard.opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    /// Metadata parsed from a backup filename + filesystem.
    /// Filenames are "MortalLoom-YYYYMMDD-HHMMSS-<reason>.json".
    private struct BackupMetadata {
        let displayDate: String
        let reasonLabel: String
        let reasonColor: Color
        let sizeString: String
    }

    private func backupMetadata(_ url: URL) -> BackupMetadata {
        let fm = FileManager.default
        let attrs = try? fm.attributesOfItem(atPath: url.path)
        let mtime = fm.modificationDate(at: url) ?? .distantPast
        let size = (attrs?[.size] as? Int) ?? 0

        let name = url.deletingPathExtension().lastPathComponent
        let parts = name.split(separator: "-")
        // Expected: ["MortalLoom", "YYYYMMDD", "HHMMSS", "<reason>"]
        let reason: String = parts.count >= 4 ? String(parts[3...].joined(separator: "-")) : "backup"

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let displayDate = formatter.string(from: mtime)

        let formatter2 = ByteCountFormatter()
        formatter2.countStyle = .file
        let sizeString = formatter2.string(fromByteCount: Int64(size))

        let (label, color) = backupReasonStyle(reason)
        return BackupMetadata(
            displayDate: displayDate,
            reasonLabel: label,
            reasonColor: color,
            sizeString: sizeString
        )
    }

    private func backupReasonStyle(_ reason: String) -> (label: String, color: Color) {
        switch reason {
        case "reset":       return ("before reset", .danger)
        case "import":      return ("before import", .warning)
        case "pre-restore": return ("before restore", .accentColor)
        default:            return (reason, .textMuted)
        }
    }

    private func refreshBackups() async {
        backups = await DataStore.shared.listBackups()
    }

    private func performRestore(_ url: URL) async {
        let success = await DataStore.shared.restoreFromBackup(url)
        restoreSuccess = success
        restoreMessage = success
            ? "Restored from \(url.lastPathComponent)"
            : "Restore failed — backup file could not be decoded."
        await refreshBackups()
        if success {
            NotificationCenter.default.post(name: .dataDidSync, object: nil)
        }
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
                HStack(spacing: 16) {
                    Link("Privacy Policy", destination: URL(string: "https://mortalloom.shadowpuppet.net/privacy.html")!)
                    Link("Terms of Use", destination: URL(string: "https://mortalloom.shadowpuppet.net/terms.html")!)
                }
                .font(.caption)
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

            Divider()
                .background(Color.cardBorder)

            Button {
                showCitations = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "book.closed.fill")
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sources & Citations")
                            .font(.subheadline).fontWeight(.medium)
                            .foregroundColor(.textPrimary)
                        Text("View research and data sources used in health calculations")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.textMuted)
                }
            }
            .buttonStyle(.plain)
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

            Text("Finish or re-run the onboarding wizard to update your North Star, lifestyle profile, or life expectancy baseline.")
                .font(.caption)
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                UserDefaults.standard.set(false, forKey: AppConstants.hasCompletedOnboardingKey)
                NotificationCenter.default.post(name: .showOnboarding, object: nil)
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Run Setup Wizard")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)

            // Fast path for users who only want to tweak their lifestyle
            // answers (birth date, smoking, exercise, sleep, diet, stress)
            // without re-running the full 13-step onboarding flow.
            Button {
                NotificationCenter.default.post(name: .navigateToPage, object: AppPage.lifestyle)
            } label: {
                HStack {
                    Image(systemName: "list.bullet.clipboard")
                    Text("Edit Health Profile")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Color.accentColor.opacity(0.12))
                .foregroundColor(.accentColor)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
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
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        // Use the standard destructive-confirmation pattern (a
        // confirmationDialog with a role: .destructive button), matching
        // every other delete in the app, instead of a bespoke inline
        // expand-in-place.
        .confirmationDialog(
            "Reset all data?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                Task { await resetAllData() }
            }
            .accessibilityLabel("Confirm delete all data")
            .accessibilityHint("This will permanently delete all your MortalLoom data")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all your MortalLoom data and can't be undone.")
        }
    }

    // MARK: - Support

    private var feedbackBody: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        #if os(iOS)
        let device = UIDevice.current
        let deviceInfo = "\(device.model), iOS \(device.systemVersion)"
        #else
        let deviceInfo = "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        #endif
        return """

        ---
        App: MortalLoom v\(version) (\(build))
        Device: \(deviceInfo)
        """
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "SUPPORT")

            #if os(iOS)
            if MFMailComposeViewController.canSendMail() {
                Button {
                    showingMailComposer = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Send Feedback")
                                .font(.subheadline).fontWeight(.medium)
                                .foregroundColor(.textPrimary)
                            Text("Email mortalloom@shadowpuppet.net")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.textMuted)
                    }
                }
                .buttonStyle(.plain)
            } else if let url = URL(string: "mailto:\(Self.feedbackEmail)?subject=MortalLoom%20Feedback") {
                Link(destination: url) {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Send Feedback")
                                .font(.subheadline).fontWeight(.medium)
                                .foregroundColor(.textPrimary)
                            Text("Email mortalloom@shadowpuppet.net")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.textMuted)
                    }
                }
            }
            #else
            if let url = URL(string: "mailto:\(Self.feedbackEmail)?subject=MortalLoom%20Feedback") {
                Link(destination: url) {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Send Feedback")
                                .font(.subheadline).fontWeight(.medium)
                                .foregroundColor(.textPrimary)
                            Text("Email mortalloom@shadowpuppet.net")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.textMuted)
                    }
                }
            }
            #endif
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
                exportDocument = nil
            }

        case .failure:
            importMessage = "Import cancelled."
            importSuccess = false
        }
    }

    private func resetAllData() async {
        // Snapshot the current file before wiping so the user can undo via
        // the rolling backup in ~/Library/Containers/.../Data/Documents/backups/
        await DataStore.shared.backupCurrentFile(reason: "reset")
        await DataStore.shared.save(.empty)
        exportDocument = nil
        importMessage = nil
        UserDefaults.standard.set(false, forKey: AppConstants.hasCompletedOnboardingKey)
        NotificationCenter.default.post(name: .showOnboarding, object: nil)
    }
}

// MARK: - Export Helper

struct MortalLoomExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
