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
    /// tab inside the Habits page (for screenshot automation). Debug-only.
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
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: AppConstants.hasCompletedOnboardingKey)

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
        .task {
            if AppConstants.useSampleData {
                await DataStore.shared.save(SampleData.fullAppData)
                UserDefaults.standard.set(true, forKey: AppConstants.hasCompletedOnboardingKey)
            }
            // Start iCloud file monitoring for cross-device sync
            ICloudMonitor.shared.start()
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
            SubstancesView()
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

                Section("Health") {
                    ForEach([AppPage.overview, .body, .sleep, .blood, .calendar, .genome], id: \.self) { page in
                        Label(page.title, systemImage: page.icon).tag(page)
                    }
                }

                Section("Tracking") {
                    ForEach([AppPage.goals, .habits, .lifestyle], id: \.self) { page in
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
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.bg)
        }
    }
}
#endif
