import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import os

private let appLogger = Logger(subsystem: "net.shadowpuppet.MeatSpaceTracker", category: "App")

enum AppConstants {
    static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    static let appearanceModeKey = "appearanceMode"
    /// Launch with -sample-data to load realistic test data for screenshots.
    /// Debug-only — Release builds ignore this flag so a shipped binary cannot
    /// be coerced into wiping a real user's data via launch arguments.
    static var useSampleData: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-sample-data")
        #else
        return false
        #endif
    }
    /// Launch with -start-page <name> to open a specific page (for macOS screenshots).
    /// Debug-only.
    static var startPage: AppPage? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-start-page"),
              idx + 1 < args.count else { return nil }
        return AppPage.allCases.first { $0.title.lowercased() == args[idx + 1].lowercased() }
        #else
        return nil
        #endif
    }

    /// Launch with -habits-tab <my habits|alcohol|nicotine|sauna> to open a
    /// specific tab inside the Habits page (for screenshot automation).
    /// Debug-only.
    static var startHabitTab: String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-habits-tab"),
              idx + 1 < args.count else { return nil }
        return args[idx + 1].lowercased()
        #else
        return nil
        #endif
    }

    /// Launch with -fresh-start to simulate a brand-new install in the
    /// simulator without touching the real iCloud container. In this mode:
    /// - DataStore enters sample-data mode (nothing written to disk/iCloud)
    /// - In-memory state starts at `AppData.empty`
    /// - Onboarding flag is forced to false so onboarding runs
    /// - HealthKit sync is skipped
    /// Debug-only — shipped binaries ignore the flag so a user's real device
    /// can't be coerced into throwing away their data via launch arguments.
    static var useFreshStart: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-fresh-start")
        #else
        return false
        #endif
    }
}

extension Notification.Name {
    static let showOnboarding = Notification.Name("showOnboarding")
    static let profileDidChange = Notification.Name("profileDidChange")
}

@main
struct MortalLoomApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        // Set the notification delegate before any scene mounts so a tap that
        // cold-launches the app still routes through its embedded deep link.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        // Stable `id` so macOS can restore the single main window across launches
        // and on Dock-icon reopen rather than spawning an anonymous duplicate.
        WindowGroup(id: "main") {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        // Drive the window's minimum size from the content's, so it can't shrink
        // below the wide-layout threshold and overlap the sidebar (the detail
        // column carries a minWidth in MacContentView).
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit MortalLoom") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            // Suppress the default Cmd+N "New Window" — a second window is just a
            // duplicate of this single-window app.
            CommandGroup(replacing: .newItem) {}
        }
        #endif

        #if os(macOS)
        // A real Settings scene gives the HIG-expected Cmd+, (SwiftUI wires the
        // menu item automatically) and works even when the main window has been
        // closed — unlike routing a notification into the main window, which has
        // no observer in that state.
        Settings {
            SettingsView()
        }
        #endif
    }
}

#if os(macOS)
/// Keeps the app running when the last window is closed (so Dock-icon reopen
/// restores the window instead of relaunching — App Store Guideline 4.2) and
/// brings the window back on reopen.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // No visible window: order any existing (e.g. minimized) window
            // forward. If none remain, returning true lets AppKit recreate the
            // WindowGroup's window.
            for window in sender.windows {
                window.makeKeyAndOrderFront(self)
            }
        }
        return true
    }
}
#endif

struct ContentView: View {
    @State private var appearance = AppearanceManager.shared
    @State private var store = StoreManager.shared
    @State private var selectedPage: AppPage = .overview
    @State private var showSideMenu = false
    // Onboarding starts hidden and is only shown after the startup task
    // determines whether the user has data (local or iCloud). This prevents
    // the wizard from appearing on a new device that already has iCloud data.
    @State private var showOnboarding: Bool = false
    // One-time banner shown when DataStore detects the iCloud container is
    // unreachable — data is still saved locally, but the user has no iCloud
    // copy, so we tell them rather than failing silently.
    @State private var iCloudWarning: String?
    private enum StartupScreen { case checking, waiting, ready, recovery }
    @State private var startupScreen: StartupScreen = .checking
    @State private var showRecoveryConfirmation = false
    @State private var showRecoveryPicker = false
    @State private var recoveryMessage: String?
    @State private var recoveryReason: DataStore.RecoveryReason = .unreadable
    @State private var hasVerifiedRecoveryCopy = false
    @State private var showVerifiedRecoveryConfirmation = false
    @State private var canUseCurrentCloud = false
    @State private var showCurrentCloudConfirmation = false
    @State private var showSyncRecoveryCopies = false

    // Bridge for OverviewView's Int-based selectedTab binding
    private var selectedTabBinding: Binding<Int> {
        Binding<Int>(
            get: { selectedPage.rawValue },
            set: { selectedPage = AppPage.from(tabIndex: $0) }
        )
    }

    var body: some View {
        Group {
            switch startupScreen {
            case .checking:
                ProgressView("Opening MortalLoom…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .waiting:
                ContentUnavailableView {
                    Label("Waiting for iCloud", systemImage: "icloud.and.arrow.down")
                } description: {
                    Text("iCloud hasn’t made your current data available yet. No edits or imports will run while MortalLoom waits.")
                } actions: {
                    Button("Check Again") {
                        startupScreen = .checking
                        Task { await openDataStore() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .recovery:
                ContentUnavailableView {
                    Label("Can’t open your data", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(recoveryExplanation)
                    if let recoveryMessage { Text(recoveryMessage) }
                } actions: {
                    Button("Try Again") {
                        startupScreen = .checking
                        Task { await openDataStore(retry: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    if hasVerifiedRecoveryCopy {
                        Button("Restore Last Verified Copy…") { showVerifiedRecoveryConfirmation = true }
                    }
                    Button("Restore from File…") { showRecoveryConfirmation = true }
                    Button("Browse Recovery Copies…") { showSyncRecoveryCopies = true }
                    if canUseCurrentCloud {
                        Button("Use Current iCloud Copy…") { showCurrentCloudConfirmation = true }
                    }
                }
            case .ready:
                #if os(macOS)
                MacContentView()
                #else
                iOSContent
                #endif
            }
        }
        .sheet(isPresented: $showSyncRecoveryCopies) {
            SyncRecoveryCopiesView(archiveCloudConflicts: true)
        }
        .preferredColorScheme(appearance.mode.colorScheme)
        .environment(store)
        .confirmationDialog("Restore from a backup?", isPresented: $showRecoveryConfirmation, titleVisibility: .visible) {
            Button("Choose Backup…") { showRecoveryPicker = true }
        } message: {
            Text("This replaces your data with the selected backup. MortalLoom saves a separate copy of the current files before replacing them.")
        }
        .confirmationDialog("Restore the last verified copy?", isPresented: $showVerifiedRecoveryConfirmation, titleVisibility: .visible) {
            Button("Restore Last Verified Copy") {
                startupScreen = .checking
                Task {
                    guard await DataStore.shared.recoverLastKnownGood() else {
                        recoveryMessage = "Couldn’t restore the verified copy. Check that iCloud is available, then try again."
                        await showSyncRecovery()
                        return
                    }
                    recoveryMessage = nil
                    await openDataStore()
                }
            }
        } message: {
            Text("MortalLoom keeps the existing files separately before replacing them.")
        }
        .confirmationDialog("Use the current iCloud copy?", isPresented: $showCurrentCloudConfirmation, titleVisibility: .visible) {
            Button("Use Current Copy") {
                startupScreen = .checking
                Task {
                    guard await DataStore.shared.acceptCurrentCloudForRecovery() else {
                        recoveryMessage = "The iCloud copy changed or couldn’t be opened. Review it again before continuing."
                        await showSyncRecovery()
                        return
                    }
                    recoveryMessage = nil
                    await openDataStore()
                }
            }
        } message: {
            Text("This doesn’t change the iCloud file. MortalLoom keeps your earlier local copy separately.")
        }
        .fileImporter(isPresented: $showRecoveryPicker, allowedContentTypes: [.json]) { result in
            guard let url = try? result.get() else { return }
            startupScreen = .checking
            Task {
                let bytes = await Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    return try? Data(contentsOf: url)
                }.value
                guard let bytes else {
                    recoveryMessage = "Couldn’t read the selected backup."
                    startupScreen = .recovery
                    return
                }
                guard await DataStore.shared.recoverFromBackup(bytes) else {
                    recoveryMessage = "Couldn’t restore this backup. Check the file and make sure iCloud is available."
                    startupScreen = .recovery
                    return
                }
                recoveryMessage = nil
                await openDataStore()
            }
        }
        .toast($iCloudWarning, icon: "icloud.slash", tint: .warning)
        .onReceive(NotificationCenter.default.publisher(for: .iCloudWriteUnavailable)) { _ in
            showToast($iCloudWarning,
                      message: "iCloud is unavailable. Changes may not sync.",
                      duration: 5.0)
        }
        .onReceive(NotificationCenter.default.publisher(for: .iCloudWriteDeferred)) { _ in
            showToast($iCloudWarning,
                      message: "iCloud data is updating. Try your edit again after it syncs.",
                      duration: 5.0)
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showOnboarding, onDismiss: {
            // Onboarding made its own HealthKit request (step 5); now that the
            // cover has dismissed, run the import the root .task skipped while it
            // was presenting — so first-launch metrics land without a relaunch.
            if startupScreen == .ready { Task { await requestHealthKitAndSync() } }
        }) {
            OnboardingView(isPresented: $showOnboarding)
        }
        #else
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
                .frame(minWidth: 600, minHeight: 700)
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .dataStoreNeedsRecovery)) { _ in
            Task { await showSyncRecovery() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dataDidSync)) { _ in
            if startupScreen == .waiting {
                startupScreen = .checking
                Task { await openDataStore() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in
            if startupScreen == .ready { showOnboarding = true }
        }
        #if os(iOS)
        // macOS routes through MacContentView's own selectedPage state —
        // only iOS uses ContentView.selectedPage as the source of truth.
        .onReceive(NotificationCenter.default.publisher(for: .navigateToPage)) { notif in
            if let page = notif.object as? AppPage {
                selectedPage = page
            }
        }
        .onOpenURL { url in
            guard let route = DeepLinkRouter.parse(url) else {
                appLogger.warning("🔗 unrecognised URL: \(url.absoluteString, privacy: .public)")
                return
            }
            selectedPage = route.targetPage
            route.applySideEffects()
        }
        #endif
        .task {
            if AppConstants.useSampleData {
                // Sample-data mode: load fake data in-memory only, and skip
                // every side-effecting subsystem so nothing ever writes to
                // disk or the iCloud container. This is the root-cause fix
                // for the 2026-04-09 sample-data-clobbers-iCloud incident.
                appLogger.warning("⚠️ -sample-data flag present: entering in-memory-only mode — iCloud & HealthKit disabled")
                await DataStore.shared.enableSampleDataMode()
                await DataStore.shared.setInMemory(SampleData.fullAppData)
                UserDefaults.standard.set(true, forKey: AppConstants.hasCompletedOnboardingKey)
                startupScreen = .ready
                return
            }

            if AppConstants.useFreshStart {
                // Fresh-start mode: simulate a brand-new install. Uses the
                // same no-persistence guarantee as sample-data mode, but
                // seeds empty data and forces onboarding to run. Used in
                // the simulator when the developer wants to test the full
                // new-user flow without touching their real iCloud container.
                appLogger.warning("⚠️ -fresh-start flag present: empty in-memory state, onboarding forced, iCloud & HealthKit disabled")
                await DataStore.shared.enableSampleDataMode()
                await DataStore.shared.setInMemory(AppData.empty)
                UserDefaults.standard.set(false, forKey: AppConstants.hasCompletedOnboardingKey)
                startupScreen = .ready
                showOnboarding = true
                return
            }

            await openDataStore()
        }
    }

    private var recoveryExplanation: String {
        switch recoveryReason {
        case .unreadable:
            "MortalLoom couldn’t read or reconcile the saved files. Editing and automatic imports are paused to protect your data."
        case .unexpectedReduction:
            "The latest iCloud copy is missing a substantial part of your saved history. MortalLoom kept the earlier copy and paused writes."
        case .divergentEdits:
            "Two copies contain overlapping changes and couldn’t be combined safely. MortalLoom kept the copies and paused writes."
        case .accountChanged:
            "The local copy belongs to a different iCloud account. MortalLoom won’t upload it to this account automatically."
        case .historyUnavailable:
            "MortalLoom couldn’t save a verified recovery copy. Check your available storage before trying again."
        }
    }

    private func showSyncRecovery() async {
        showOnboarding = false
        recoveryReason = await DataStore.shared.currentRecoveryReason()
        hasVerifiedRecoveryCopy = await DataStore.shared.canRecoverLastKnownGood()
        canUseCurrentCloud = await DataStore.shared.canAcceptCurrentCloudForRecovery()
        startupScreen = .recovery
    }

    private func openDataStore(retry: Bool = false) async {
        let loaded: AppData
        switch await DataStore.shared.ensureLoaded(retry: retry) {
        case .ready(let value):
            loaded = value
        case .waitingForCloud:
            startupScreen = .waiting
            ICloudMonitor.shared.start()
            return
        case .needsRecovery:
            await showSyncRecovery()
            return
        }
        startupScreen = .ready
        // Start only after validation: a monitor callback must not race the
        // initial read and bypass the startup recovery screen.
        ICloudMonitor.shared.start()
        if loaded.hasUserData {
            UserDefaults.standard.set(true, forKey: AppConstants.hasCompletedOnboardingKey)
        } else if !UserDefaults.standard.bool(forKey: AppConstants.hasCompletedOnboardingKey) {
            showOnboarding = true
        }

        await NotificationService.shared.scheduleReflectionPlan()
        #if os(iOS)
        if !showOnboarding && startupScreen == .ready {
            await requestHealthKitAndSync()
        }
        #endif
    }

    #if os(iOS)
    /// Requests HealthKit authorization (a no-op once already requested — the
    /// system prompt only shows once) and, if the request has completed, imports
    /// body + health metrics into iCloud. Called from the root `.task` on normal
    /// launches and from the onboarding cover's `onDismiss` on first launch, so
    /// the import isn't deferred to the next run when onboarding owns the prompt.
    private func requestHealthKitAndSync() async {
        // Never touch HealthKit in the isolated debug modes. Sample-data and
        // fresh-start runs stay in-memory so screenshot / new-user flows can't
        // pull real health samples into the supposedly empty store. The startup
        // .task enforces this by returning before HealthKit, but the onboarding
        // onDismiss path also lands here in fresh-start mode (which presents
        // onboarding), so guard it here too.
        guard !AppConstants.useSampleData, !AppConstants.useFreshStart else { return }
        guard HealthKitService.shared.isAvailable else { return }
        await HealthKitService.shared.requestAuthorization()
        guard HealthKitService.shared.authorizationRequestCompleted else { return }
        appLogger.info("🏃 syncing HealthKit data to iCloud…")
        // Run sequentially, NOT concurrently. Both syncs read-modify-write
        // the same AppData; running them with `async let` let whichever
        // finished last clobber the other's mutations, silently dropping
        // ~half the synced data each launch (issue #28).
        await HealthKitSync.shared.syncBodyMetrics()
        await HealthKitSync.shared.syncHealthMetrics()
        appLogger.info("✅ HealthKit sync complete")
    }

    private var iOSContent: some View {
        ZStack {
            VStack(spacing: 0) {
                pageContent
                CustomTabBar(selectedPage: $selectedPage, showSideMenu: $showSideMenu)
            }
            .accessibilityHidden(showSideMenu)

            if showSideMenu {
                SideMenuView(selectedPage: $selectedPage, isPresented: $showSideMenu)
                    .transition(.opacity)
            }

            // Blur behind the status bar so scrolled content doesn't collide
            // with the system time/signal/battery indicators.
            GeometryReader { geo in
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(height: geo.safeAreaInsets.top)
                    .ignoresSafeArea(edges: .top)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch selectedPage {
        case .overview:
            OverviewView(selectedTab: selectedTabBinding)
        case .body:
            BodyView()
        case .blood:
            BloodPage()
        case .habits:
            HabitsPage()
        case .lifestyle:
            LifestyleView()
        case .calendar:
            LifeCalendarView()
        case .genome:
            GenomeView()
        case .settings:
            SettingsView()
        case .goals:
            GoalsView()
        case .sleep:
            SleepView()
        case .reflections:
            ReflectionsView()
        case .reports:
            ReportsView()
        }
    }
    #endif
}

#if os(macOS)
struct MacContentView: View {
    @State private var selectedPage: AppPage? = AppConstants.startPage ?? .overview

    private var selectedTabBinding: Binding<Int> {
        Binding<Int>(
            get: { (selectedPage ?? .overview).rawValue },
            set: { selectedPage = AppPage.from(tabIndex: $0) }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPage) {
                HStack(spacing: 8) {
                    Image(systemName: "heart.text.clipboard")
                        .foregroundColor(.accentColor)
                        .font(.title2)
                    Text("MortalLoom")
                        .font(.title3).fontWeight(.bold)
                        .foregroundColor(.textPrimary)
                    #if DEBUG
                    // Hidden in -sample-data mode so App Store screenshots
                    // captured via the automation flow don't include the
                    // DEBUG pill. The badge is a safety cue for real-data
                    // debug sessions; sample-data mode is hard-isolated from
                    // iCloud/HealthKit so the warning isn't load-bearing.
                    if !AppConstants.useSampleData {
                        DebugBuildBadge()
                    }
                    #endif
                    Spacer()
                    if ICloudMonitor.shared.isICloud {
                        Button {
                            Task { await ICloudMonitor.shared.syncNow() }
                        } label: {
                            if ICloudMonitor.shared.isSyncing {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath.icloud")
                                    .foregroundColor(.textMuted)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Sync with iCloud")
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .padding(.vertical, 4)

                Section("Goals") {
                    ForEach([AppPage.overview, .goals, .calendar, .habits, .reflections, .reports], id: \.self) { page in
                        Label(page.title, systemImage: page.icon).tag(page)
                    }
                }

                Section("Health") {
                    ForEach([AppPage.body, .sleep, .blood, .lifestyle, .genome], id: \.self) { page in
                        Label(page.title, systemImage: page.icon).tag(page)
                    }
                }

                Section {
                    Label(AppPage.settings.title, systemImage: AppPage.settings.icon)
                        .tag(AppPage.settings)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.bg)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            Group {
                switch selectedPage {
                case .overview, .none:
                    OverviewView(selectedTab: selectedTabBinding)
                case .body:
                    BodyView()
                case .habits:
                    HabitsPage()
                case .blood:
                    BloodPage()
                case .calendar:
                    LifeCalendarView()
                case .genome:
                    GenomeView()
                case .lifestyle:
                    LifestyleView()
                case .goals:
                    GoalsView()
                case .sleep:
                    SleepView()
                case .settings:
                    SettingsView()
                case .reflections:
                    ReflectionsView()
                case .reports:
                    ReportsView()
                }
            }
            // Keep the detail pane above the wide-layout threshold (700) so the
            // content stays in its two-column layout and the window (sized via
            // .windowResizability(.contentMinSize)) can't shrink small enough to
            // overlap the sidebar.
            .frame(minWidth: 720, maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.bg)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToPage)) { notif in
            if let page = notif.object as? AppPage {
                selectedPage = page
            }
        }
        .onOpenURL { url in
            guard let route = DeepLinkRouter.parse(url) else { return }
            selectedPage = route.targetPage
            route.applySideEffects()
        }
    }
}
#endif

#if DEBUG
/// Small red pill shown on DEBUG builds only. Makes it obvious when the user
/// is looking at a developer build versus the shipped Release build — helps
/// avoid "is this the fixed binary?" confusion after an incident. Defined in
/// a #if DEBUG block so it's physically absent from Release.
struct DebugBuildBadge: View {
    var body: some View {
        Text("DEBUG")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.red.opacity(0.85))
            .clipShape(Capsule())
            .accessibilityLabel("Debug build")
    }
}
#endif
