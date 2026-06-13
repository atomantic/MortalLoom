import SwiftUI

// MARK: - SubstancesView

/// Thin router for the alcohol / nicotine / sauna trackers. Each tab is an
/// independent view that owns only its own state, so switching tabs doesn't
/// allocate the other trackers' form/edit state. Embedded inside `HabitsPage`,
/// which owns the tab selection.
struct SubstancesView: View {
    let selectedTab: SubstanceTab

    var body: some View {
        switch selectedTab {
        case .alcohol:
            AlcoholView()
        case .nicotine:
            NicotineView()
        case .sauna:
            SaunaView()
        }
    }
}
