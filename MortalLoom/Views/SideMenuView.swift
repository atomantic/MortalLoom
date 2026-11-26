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
    case reflections = 10
    case reports = 11

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
        case .reflections: "bubble.left.and.bubble.right"
        case .reports: "chart.line.uptrend.xyaxis"
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
        case .reflections: "Reflections"
        case .reports: "Reports"
        }
    }

    static func from(tabIndex: Int) -> AppPage {
        AppPage(rawValue: tabIndex) ?? .overview
    }

}

// MARK: - Bottom tab shortcuts

/// Keep the two main destinations predictable. The remaining slots reflect
/// how someone uses MortalLoom, while every page remains available in More.
struct BottomTabShortcuts: Equatable {
    static let firstKey = "bottomTab.firstShortcut"
    static let secondKey = "bottomTab.secondShortcut"
    static let options: [AppPage] = [.habits, .reports, .calendar, .reflections]
    static let defaults = BottomTabShortcuts(first: .habits, second: .reports)

    enum Slot { case first, second }

    private(set) var first: AppPage
    private(set) var second: AppPage

    private init(first: AppPage, second: AppPage) {
        self.first = first
        self.second = second
    }

    init(firstRawValue: Int, secondRawValue: Int) {
        let savedFirst = AppPage(rawValue: firstRawValue)
        let savedSecond = AppPage(rawValue: secondRawValue)
        first = savedFirst.flatMap { Self.options.contains($0) ? $0 : nil } ?? Self.defaults.first
        second = savedSecond.flatMap { Self.options.contains($0) ? $0 : nil } ?? Self.defaults.second
        if second == first {
            second = Self.options.first(where: { $0 != first }) ?? Self.defaults.second
        }
    }

    var pages: [AppPage] { [.overview, .goals, first, second] }

    mutating func select(_ page: AppPage, for slot: Slot) {
        guard Self.options.contains(page) else { return }
        switch slot {
        case .first:
            if page == second { second = first }
            first = page
        case .second:
            if page == first { first = second }
            second = page
        }
    }
}

// MARK: - Side Menu Sections

private struct MenuSection {
    let title: String
    let pages: [AppPage]
}

// Section ordering reflects the app's primary purpose: aligning time with goals.
// Goals pages lead, including Habits — habits are the daily engagement loop that
// drives alignment (health habits AND custom goal-tied habits like writing or practice).
// Health pages follow as the "runway extender" surface area for longevity tracking.
private let menuSections: [MenuSection] = [
    MenuSection(title: "Goals", pages: [.overview, .goals, .calendar, .habits, .reflections, .reports]),
    MenuSection(title: "Health", pages: [.body, .sleep, .blood, .lifestyle, .genome]),
    MenuSection(title: "App", pages: [.settings]),
]

// MARK: - Side Menu View

#if os(iOS)
struct SideMenuView: View {
    @Binding var selectedPage: AppPage
    @Binding var isPresented: Bool
    /// Drives the slide-in/out. The panel is offset by its own width when
    /// hidden, so we never need the screen width — only `isShown`.
    @State private var isShown = false
    @State private var showShortcuts = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Read the window (not screen) width via GeometryReader. `UIScreen.main`
        // returns the full physical screen, which is wrong in iPad Split View /
        // Stage Manager where the app occupies only part of the screen.
        GeometryReader { geo in
            let menuWidth = min(geo.size.width * 0.8, 320)
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
                .offset(x: isShown ? 0 : -menuWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                isShown = true
            }
        }
        .sheet(isPresented: $showShortcuts) { BottomTabShortcutSettings() }
        .accessibilityAction(.escape) { dismiss() }
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
            if !AppConstants.useSampleData {
                DebugBuildBadge()
            }
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
                Button { showShortcuts = true } label: {
                    Label("Customize Tab Bar", systemImage: "rectangle.bottomthird.inset.filled")
                        .font(.body)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("customize-bottom-tab-bar")

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
        if reduceMotion {
            isPresented = false
            return
        }
        withAnimation(.easeIn(duration: 0.2)) {
            isShown = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }
}
#endif

// MARK: - Custom Tab Bar

#if os(iOS)
private struct BottomTabShortcutSettings: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(BottomTabShortcuts.firstKey) private var first = BottomTabShortcuts.defaults.first.rawValue
    @AppStorage(BottomTabShortcuts.secondKey) private var second = BottomTabShortcuts.defaults.second.rawValue

    private var shortcuts: BottomTabShortcuts {
        BottomTabShortcuts(firstRawValue: first, secondRawValue: second)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    picker("First shortcut", slot: .first)
                    picker("Second shortcut", slot: .second)
                } footer: {
                    Text("Overview and Goals stay in place. You can still find every page in More.")
                }
                Section {
                    Button("Reset to Default") { save(.defaults) }
                        .accessibilityIdentifier("reset-bottom-tab-shortcuts")
                }
            }
            .navigationTitle("Tab Bar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func picker(_ title: String, slot: BottomTabShortcuts.Slot) -> some View {
        Picker(title, selection: Binding(
            get: { slot == .first ? shortcuts.first : shortcuts.second },
            set: { page in
                var updated = shortcuts
                updated.select(page, for: slot)
                save(updated)
            }
        )) {
            ForEach(BottomTabShortcuts.options, id: \.self) { page in
                Label(page.title, systemImage: page.icon).tag(page)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier(slot == .first ? "first-bottom-tab-shortcut" : "second-bottom-tab-shortcut")
    }

    private func save(_ shortcuts: BottomTabShortcuts) {
        first = shortcuts.first.rawValue
        second = shortcuts.second.rawValue
    }
}

struct CustomTabBar: View {
    @Binding var selectedPage: AppPage
    @Binding var showSideMenu: Bool
    @AppStorage(BottomTabShortcuts.firstKey) private var first = BottomTabShortcuts.defaults.first.rawValue
    @AppStorage(BottomTabShortcuts.secondKey) private var second = BottomTabShortcuts.defaults.second.rawValue

    private var pages: [AppPage] {
        BottomTabShortcuts(firstRawValue: first, secondRawValue: second).pages
    }

    // "More" represents selection only when the current page isn't a primary
    // tab (e.g. Calendar/Blood opened via the side menu). When the side menu
    // is open we leave the underlying primary tab selected so VoiceOver and
    // visual state never report two simultaneously selected tabs.
    private var isMoreSelected: Bool {
        !pages.contains(selectedPage)
    }

    var body: some View {
        HStack {
            ForEach(pages, id: \.self) { page in
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
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("bottom-tab-\(page.rawValue)")
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
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("bottom-tab-more")
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
