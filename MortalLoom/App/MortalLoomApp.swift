import SwiftUI

enum AppConstants {
    static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
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
            // Start iCloud file monitoring for cross-device sync
            ICloudMonitor.shared.start()
            #if os(iOS)
            // Sync HealthKit data into shared storage so macOS can see it
            if HealthKitService.shared.isAvailable && HealthKitService.shared.authorized {
                await HealthKitSync.shared.syncBodyMetrics()
            }
            #endif
        }
    }

    #if os(iOS)
    private var iOSContent: some View {
        ZStack {
            VStack(spacing: 0) {
                NavigationStack {
                    pageContent
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button { showSideMenu = true } label: {
                                    Image(systemName: "line.3.horizontal")
                                        .font(.title3)
                                        .foregroundColor(.textPrimary)
                                }
                            }
                        }
                }

                CustomTabBar(selectedPage: $selectedPage)
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
        }
    }
    #endif
}

#if os(macOS)
struct MacContentView: View {
    @State private var selectedPage: AppPage? = .overview

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
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .padding(.vertical, 4)

                Section("Health") {
                    ForEach([AppPage.overview, .body, .blood, .calendar, .genome], id: \.self) { page in
                        Label(page.title, systemImage: page.icon).tag(page)
                    }
                }

                Section("Tracking") {
                    ForEach([AppPage.habits, .lifestyle], id: \.self) { page in
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
