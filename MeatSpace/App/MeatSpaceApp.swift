import SwiftUI

@main
struct MeatSpaceApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit MeatSpace Tracker") {
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

    var body: some View {
        Group {
            #if os(macOS)
            MacContentView()
                .tint(.accent)
            #else
            tabContent
                .tint(.accent)
            #endif
        }
        .preferredColorScheme(.dark)
    }

    #if os(iOS)
    @ViewBuilder
    private var tabContent: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $selectedTab) {
                Tab("Overview", systemImage: "heart.text.clipboard", value: 0) {
                    NavigationStack { OverviewView() }
                }
                Tab("Body", systemImage: "figure.stand", value: 1) {
                    NavigationStack { BodyView() }
                }
                Tab("Substances", systemImage: "flask", value: 2) {
                    NavigationStack { SubstancesView() }
                }
                Tab("Genome", systemImage: "allergens", value: 3) {
                    NavigationStack { GenomeView() }
                }
                Tab("Settings", systemImage: "gear", value: 4) {
                    NavigationStack { SettingsView() }
                }
            }
        } else {
            TabView(selection: $selectedTab) {
                NavigationStack { OverviewView() }
                    .tabItem { Label("Overview", systemImage: "heart.text.clipboard") }
                    .tag(0)
                NavigationStack { BodyView() }
                    .tabItem { Label("Body", systemImage: "figure.stand") }
                    .tag(1)
                NavigationStack { SubstancesView() }
                    .tabItem { Label("Substances", systemImage: "flask") }
                    .tag(2)
                NavigationStack { GenomeView() }
                    .tabItem { Label("Genome", systemImage: "allergens") }
                    .tag(3)
                NavigationStack { SettingsView() }
                    .tabItem { Label("Settings", systemImage: "gear") }
                    .tag(4)
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
        case genome
        case lifestyle
        case settings
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedNav) {
                HStack(spacing: 8) {
                    Image(systemName: "heart.text.clipboard")
                        .foregroundColor(.accent)
                        .font(.title2)
                    Text("MeatSpace")
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
                    OverviewView()
                case .body:
                    BodyView()
                case .substances:
                    SubstancesView()
                case .blood:
                    BloodView()
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
