import SwiftUI
import os

private let appLogger = Logger(subsystem: "net.shadowpuppet.MeatSpaceTracker", category: "App")

enum AppConstants {
    static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
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

    /// Launch with -substance-tab <alcohol|nicotine|sauna> to open a specific
    /// tab inside the Substances page (for screenshot automation). Debug-only.
    static var startSubstanceTab: String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-substance-tab"),
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
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit MortalLoom") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        #endif
    }
}

struct ContentView: View {
    @State private var appearance = AppearanceManager.shared
    @State private var store = StoreManager.shared
    @State private var selectedPage: AppPage = .overview
    @State private var showSideMenu = false
    // Onboarding starts hidden and is only shown after the startup task
    // determines whether the user has data (local or iCloud). This prevents
    // the wizard from appearing on a new device that already has iCloud data.
    @State private var showOnboarding: Bool = false

    // Bridge for OverviewView's Int-based selectedTab binding
    private var selectedTabBinding: Binding<Int> {
        Binding<Int>(
            get: { selectedPage.rawValue },
            set: { selectedPage = AppPage.from(tabIndex: $0) }
        )
    }

    var body: some View {
        Group {
            #if os(macOS)
            MacContentView()
            #else
            iOSContent
            #endif
        }
        .preferredColorScheme(appearance.mode.colorScheme)
        .environment(store)
        #if os(iOS)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
        #else
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
                .frame(minWidth: 600, minHeight: 700)
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in
            showOnboarding = true
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
            if case .goalReflect(let id) = route {
                NotificationCenter.default.post(name: .openGoalReflect, object: id)
            }
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
                showOnboarding = true
                return
            }

            // Start iCloud file monitoring for cross-device sync
            ICloudMonitor.shared.start()
            // Ensure data is loaded from iCloud before any sync writes.
            // This prevents the race where HealthKit sync saves empty data
            // because the iCloud file hasn't been downloaded yet.
            let loaded = await DataStore.shared.ensureLoaded()

            // Decide onboarding AFTER iCloud data has loaded. If the user
            // already has data in iCloud (e.g. installing on a new device),
            // skip onboarding and mark it complete so it never shows.
            if loaded.hasUserData {
                appLogger.info("📦 existing user data found — skipping onboarding")
                UserDefaults.standard.set(true, forKey: AppConstants.hasCompletedOnboardingKey)
            } else if !UserDefaults.standard.bool(forKey: AppConstants.hasCompletedOnboardingKey) {
                showOnboarding = true
            }

            #if os(iOS)
            // Request HealthKit auth on every launch (prompt shows once; subsequent calls are no-ops)
            if HealthKitService.shared.isAvailable {
                await HealthKitService.shared.requestAuthorization()
            }
            if HealthKitService.shared.isAvailable && HealthKitService.shared.authorizationRequestCompleted {
                appLogger.info("🏃 syncing HealthKit data to iCloud…")
                async let body: Void = HealthKitSync.shared.syncBodyMetrics()
                async let metrics: Void = HealthKitSync.shared.syncHealthMetrics()
                _ = await (body, metrics)
                appLogger.info("✅ HealthKit sync complete")
            }
            #endif
        }
    }

    #if os(iOS)
    private var iOSContent: some View {
        ZStack {
            VStack(spacing: 0) {
                pageContent
                CustomTabBar(selectedPage: $selectedPage, showSideMenu: $showSideMenu)
            }

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
            BloodView()
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
        case .substances:
            SubstancesView()
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
                    ForEach([AppPage.body, .sleep, .substances, .blood, .lifestyle, .genome], id: \.self) { page in
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
                case .substances:
                    SubstancesView()
                case .blood:
                    BloodView()
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if case .goalReflect(let id) = route {
                NotificationCenter.default.post(name: .openGoalReflect, object: id)
            }
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
