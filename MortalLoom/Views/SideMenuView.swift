import SwiftUI

// MARK: - App Page Enum

enum AppPage: Int, CaseIterable, Hashable {
    case overview = 0
    case body = 1
    case blood = 2
    case habits = 3
    case lifestyle = 4
    case calendar = 5
    case genome = 6
    case settings = 7
    case goals = 8
    case sleep = 9

    var icon: String {
        switch self {
        case .overview: "heart.text.clipboard"
        case .body: "figure.stand"
        case .blood: "drop.fill"
        case .habits: "repeat.circle"
        case .lifestyle: "list.bullet.clipboard"
        case .calendar: "calendar"
        case .genome: "allergens"
        case .settings: "gear"
        case .goals: "target"
        case .sleep: "bed.double.fill"
        }
    }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .body: "Body"
        case .blood: "Blood"
        case .habits: "Habits"
        case .lifestyle: "Lifestyle"
        case .calendar: "Calendar"
        case .genome: "Genome"
        case .settings: "Settings"
        case .goals: "Goals"
        case .sleep: "Sleep"
        }
    }

    static func from(tabIndex: Int) -> AppPage {
        AppPage(rawValue: tabIndex) ?? .overview
    }

    // Pages shown in the bottom tab bar; the "More" button is rendered separately.
    static let tabBarPages: [AppPage] = [.overview, .goals, .calendar, .habits]
}

// MARK: - Side Menu Sections

private struct MenuSection {
    let title: String
    let pages: [AppPage]
}

private let menuSections: [MenuSection] = [
    MenuSection(title: "Health", pages: [.overview, .body, .sleep, .blood, .calendar, .genome]),
    MenuSection(title: "Tracking", pages: [.goals, .habits, .lifestyle]),
    MenuSection(title: "App", pages: [.settings]),
]

// MARK: - Side Menu View

#if os(iOS)
struct SideMenuView: View {
    @Binding var selectedPage: AppPage
    @Binding var isPresented: Bool
    @State private var menuOffset: CGFloat = -UIScreen.main.bounds.width
    private let menuWidth: CGFloat = min(UIScreen.main.bounds.width * 0.8, 320)

    var body: some View {
        ZStack(alignment: .leading) {
            // Dimmed backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
                .accessibilityLabel("Close menu")
                .accessibilityAddTraits(.isButton)

            // Menu panel
            VStack(alignment: .leading, spacing: 0) {
                menuHeader
                Divider().background(Color.cardBorder)
                menuContent
            }
            .frame(width: menuWidth)
            .frame(maxHeight: .infinity)
            .background(Color.bgCard)
            .offset(x: menuOffset)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) {
                menuOffset = 0
            }
        }
    }

    private var menuHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.text.clipboard")
                .font(.title2)
                .foregroundColor(.accentColor)
            Text("MortalLoom")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.textPrimary)
            #if DEBUG
            DebugBuildBadge()
            #endif
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body)
                    .foregroundColor(.textSecondary)
            }
            .accessibilityLabel("Close menu")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    private var menuContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(menuSections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title.uppercased())
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.textMuted)
                            .tracking(1)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 4)

                        ForEach(section.pages, id: \.self) { page in
                            menuRow(page)
                        }
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
    }

    private func menuRow(_ page: AppPage) -> some View {
        Button {
            selectedPage = page
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: page.icon)
                    .font(.body)
                    .frame(width: 24)
                    .foregroundColor(selectedPage == page ? .accentColor : .textSecondary)
                Text(page.title)
                    .font(.body)
                    .foregroundColor(selectedPage == page ? .textPrimary : .textSecondary)
                Spacer()
                if selectedPage == page {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(selectedPage == page ? Color.accentColor.opacity(0.1) : Color.clear)
        }
        .accessibilityLabel(page.title)
        .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.2)) {
            menuOffset = -UIScreen.main.bounds.width
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }
}
#endif

// MARK: - Custom Tab Bar

#if os(iOS)
struct CustomTabBar: View {
    @Binding var selectedPage: AppPage
    @Binding var showSideMenu: Bool

    // "More" represents selection only when the current page isn't a primary
    // tab (e.g. Calendar/Blood opened via the side menu). When the side menu
    // is open we leave the underlying primary tab selected so VoiceOver and
    // visual state never report two simultaneously selected tabs.
    private var isMoreSelected: Bool {
        !AppPage.tabBarPages.contains(selectedPage)
    }

    var body: some View {
        HStack {
            ForEach(AppPage.tabBarPages, id: \.self) { page in
                let isSelected = selectedPage == page && !isMoreSelected
                Button {
                    selectedPage = page
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: page.icon)
                            .font(.system(size: 20))
                        Text(page.title)
                            .font(.caption2)
                    }
                    .foregroundColor(isSelected ? .accentColor : .textMuted)
                    .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(page.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }

            Button {
                showSideMenu = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                    Text("More")
                        .font(.caption2)
                }
                .foregroundColor(isMoreSelected ? .accentColor : .textMuted)
                .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("More")
            .accessibilityHint("Opens side menu with additional pages")
            .accessibilityAddTraits(isMoreSelected ? .isSelected : [])
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(
            Color.bgCard
                .shadow(color: .black.opacity(0.1), radius: 4, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
#endif
