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
    @State private var selectedTab: Int = 0
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: AppConstants.hasCompletedOnboardingKey)

    var body: some View {
        Group {
            #if os(macOS)
            MacContentView()
            #else
            tabContent
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
    }

    #if os(iOS)
    @ViewBuilder
    private var tabContent: some View {
        // iOS tabs: Overview=0, Body=1, Blood=2, Substances=3, Lifestyle=4, Calendar=5, Genome=6, Settings=7
        if #available(iOS 18.0, *) {
            TabView(selection: $selectedTab) {
                Tab("Overview", systemImage: "heart.text.clipboard", value: 0) {
                    NavigationStack { OverviewView(selectedTab: $selectedTab) }
                }
                Tab("Body", systemImage: "figure.stand", value: 1) {
                    NavigationStack { BodyView() }
                }
                Tab("Blood", systemImage: "drop.fill", value: 2) {
                    NavigationStack { BloodView() }
                }
                Tab("Substances", systemImage: "flask", value: 3) {
                    NavigationStack { SubstancesView() }
                }
                Tab("Lifestyle", systemImage: "list.bullet.clipboard", value: 4) {
                    NavigationStack { LifestyleView() }
                }
                Tab("Calendar", systemImage: "calendar", value: 5) {
                    NavigationStack { LifeCalendarView() }
                }
                Tab("Genome", systemImage: "allergens", value: 6) {
                    NavigationStack { GenomeView() }
                }
                Tab("Settings", systemImage: "gear", value: 7) {
                    NavigationStack { SettingsView() }
                }
            }
        } else {
            TabView(selection: $selectedTab) {
                NavigationStack { OverviewView(selectedTab: $selectedTab) }
                    .tabItem { Label("Overview", systemImage: "heart.text.clipboard") }
                    .tag(0)
                NavigationStack { BodyView() }
                    .tabItem { Label("Body", systemImage: "figure.stand") }
                    .tag(1)
                NavigationStack { BloodView() }
                    .tabItem { Label("Blood", systemImage: "drop.fill") }
                    .tag(2)
                NavigationStack { SubstancesView() }
                    .tabItem { Label("Substances", systemImage: "flask") }
                    .tag(3)
                NavigationStack { LifestyleView() }
                    .tabItem { Label("Lifestyle", systemImage: "list.bullet.clipboard") }
                    .tag(4)
                NavigationStack { LifeCalendarView() }
                    .tabItem { Label("Calendar", systemImage: "calendar") }
                    .tag(5)
                NavigationStack { GenomeView() }
                    .tabItem { Label("Genome", systemImage: "allergens") }
                    .tag(6)
                NavigationStack { SettingsView() }
                    .tabItem { Label("Settings", systemImage: "gear") }
                    .tag(7)
            }
        }
    }
    #endif
}

#if os(macOS)
struct MacContentView: View {
    @State private var selectedNav: NavItem? = .overview

    enum NavItem: Hashable {
        case overview
        case body
        case substances
        case blood
        case lifeCalendar
        case genome
        case lifestyle
        case settings
    }

    // Convert NavItem selection to an Int binding for OverviewView
    private var selectedTabBinding: Binding<Int> {
        Binding<Int>(
            get: {
                switch selectedNav {
                case .overview, .none: return 0
                case .body: return 1
                case .blood: return 2
                case .substances: return 3
                case .lifestyle: return 4
                case .lifeCalendar: return 5
                case .genome: return 6
                case .settings: return 7
                }
            },
            set: { newValue in
                switch newValue {
                case 0: selectedNav = .overview
                case 1: selectedNav = .body
                case 2: selectedNav = .blood
                case 3: selectedNav = .substances
                case 4: selectedNav = .lifestyle
                case 5: selectedNav = .lifeCalendar
                case 6: selectedNav = .genome
                case 7: selectedNav = .settings
                default: selectedNav = .overview
                }
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedNav) {
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
                    Label("Overview", systemImage: "heart.text.clipboard")
                        .tag(NavItem.overview)
                    Label("Body", systemImage: "figure.stand")
                        .tag(NavItem.body)
                    Label("Blood", systemImage: "drop.fill")
                        .tag(NavItem.blood)
                    Label("Life Calendar", systemImage: "calendar")
                        .tag(NavItem.lifeCalendar)
                    Label("Genome", systemImage: "allergens")
                        .tag(NavItem.genome)
                }

                Section("Tracking") {
                    Label("Substances", systemImage: "flask")
                        .tag(NavItem.substances)
                    Label("Lifestyle", systemImage: "list.bullet.clipboard")
                        .tag(NavItem.lifestyle)
                }

                Section {
                    Label("Settings", systemImage: "gear")
                        .tag(NavItem.settings)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Color.bg)
        } detail: {
            Group {
                switch selectedNav {
                case .overview, .none:
                    OverviewView(selectedTab: selectedTabBinding)
                case .body:
                    BodyView()
                case .substances:
                    SubstancesView()
                case .blood:
                    BloodView()
                case .lifeCalendar:
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
