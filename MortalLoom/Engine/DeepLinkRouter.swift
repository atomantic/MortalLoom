import Foundation

// MARK: - DeepLinkRoute

/// Typed routes the app can deep-link to from notifications, widget taps,
/// and `mortalloom://` URLs. Pure value type — parsing is handled by
/// `DeepLinkRouter.parse(_:)`.
///
/// Sheet-presenting routes (goal edit, goal reflect, weekly review, monthly
/// rethink) navigate to the owning page AND post a request the destination
/// view observes to open the target sheet — see `applySideEffects()`.
enum DeepLinkRoute: Equatable, Sendable {
    /// Navigate to the given page without opening any sheet.
    case page(AppPage)
    /// Open the goal-edit sheet for a specific goal (or the pillar dashboard
    /// if the goal is a sub-apex — decided by the view layer which has the
    /// full goal list).
    case goalEdit(UUID)
    /// Open the check-in / reflect sheet for a specific goal.
    case goalReflect(UUID)
    /// Trigger the weekly review sheet.
    case weeklyReview
    /// Trigger the monthly rethink sheet.
    case monthlyRethink
    /// Legacy `mortalloom://substances` alias — navigate to Habits with the
    /// alcohol tab pre-selected. Kept as a distinct case (rather than a plain
    /// `.page(.habits)`) so `parse(_:)` stays pure: the tab-selection side
    /// effect is applied by the call site, the same way `.goalReflect` posts
    /// its notification there.
    case substancesAlias

    var targetPage: AppPage {
        switch self {
        case .page(let page): page
        case .goalEdit, .goalReflect: .goals
        case .weeklyReview, .monthlyRethink: .overview
        case .substancesAlias: .habits
        }
    }

    /// Apply the non-navigation side effects a route implies — posting the
    /// sheet-open requests the destination views observe (goal edit, goal
    /// reflect, weekly review, monthly rethink) and pre-selecting the Habits
    /// alcohol tab. Keeps the dispatch in one place so the iOS and macOS
    /// `onOpenURL` handlers and the notification-tap handler stay identical:
    /// they navigate via `targetPage`, then call this. `parse(_:)` itself stays
    /// pure; the effects live here, at the call site.
    @MainActor
    func applySideEffects() {
        switch self {
        case .goalEdit(let id):
            NotificationCenter.default.post(name: .openGoalEdit, object: id)
        case .goalReflect(let id):
            NotificationCenter.default.post(name: .openGoalReflect, object: id)
        case .weeklyReview:
            NotificationCenter.default.post(name: .openWeeklyReview, object: nil)
        case .monthlyRethink:
            NotificationCenter.default.post(name: .openMonthlyRethink, object: nil)
        case .substancesAlias:
            // Legacy mortalloom://substances alias — land on the alcohol tab.
            UserDefaults.standard.set(HabitTab.alcohol.rawValue, forKey: HabitTab.selectedKey)
        case .page:
            break
        }
    }
}

// MARK: - DeepLinkRouter

/// Maps `mortalloom://` URLs to typed `DeepLinkRoute` values. Invalid URLs
/// return nil. Pure — no side effects. The legacy `mortalloom://substances`
/// alias maps to `.substancesAlias`; the call site is responsible for
/// pre-selecting the Habits alcohol tab. Supported URL shapes:
///
/// - `mortalloom://overview` / `mortalloom://goals` / `mortalloom://reflections`
///   / `mortalloom://reports` / `mortalloom://calendar` / `mortalloom://habits`
///   / `mortalloom://body` / `mortalloom://sleep` / `mortalloom://blood`
///   / `mortalloom://lifestyle` / `mortalloom://genome` / `mortalloom://settings`
/// - `mortalloom://goal/<uuid>` — open goal edit sheet
/// - `mortalloom://goal/<uuid>/reflect` — open reflection / check-in sheet
/// - `mortalloom://review/weekly` — open weekly review flow
/// - `mortalloom://review/monthly` — open monthly rethink flow
enum DeepLinkRouter {
    static func parse(_ url: URL) -> DeepLinkRoute? {
        guard url.scheme?.lowercased() == "mortalloom" else { return nil }
        // URL.host is the first segment after `//`; pathComponents starts
        // with "/". Normalise into a single lowercase segment list so the
        // match order below doesn't care where the first word lands.
        var segments: [String] = []
        if let host = url.host, !host.isEmpty { segments.append(host.lowercased()) }
        for component in url.pathComponents where component != "/" {
            segments.append(component.lowercased())
        }
        guard let head = segments.first else { return nil }

        switch head {
        case "review":
            if segments.count > 1 {
                if segments[1] == "weekly" { return .weeklyReview }
                if segments[1] == "monthly" { return .monthlyRethink }
            }
            return nil

        case "goal":
            guard segments.count >= 2, let id = UUID(uuidString: segments[1]) else {
                return nil
            }
            if segments.count >= 3, segments[2] == "reflect" {
                return .goalReflect(id)
            }
            return .goalEdit(id)

        default:
            // Legacy alias for widgets / shortcuts still using
            // mortalloom://substances — land on the alcohol tab in Habits.
            // The tab-selection side effect lives at the call site.
            if head == "substances" {
                return .substancesAlias
            }
            if let page = AppPage.allCases.first(where: { $0.title.lowercased() == head }) {
                return .page(page)
            }
            return nil
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let navigateToPage = Notification.Name("navigateToPage")
    /// Posted with a `UUID` object to request the edit sheet (or pillar
    /// dashboard, for a life-pillar sub-apex) for a specific goal. GoalsView
    /// observes this and opens the target once data has loaded. Used by the
    /// `mortalloom://goal/<uuid>` deep link from notifications and widgets.
    static let openGoalEdit = Notification.Name("openGoalEdit")
    /// Posted with a `UUID` object to request the check-in / reflect sheet
    /// for a specific goal. GoalsView observes this and opens the sheet once
    /// data has loaded. Used by the widget tap-through flow.
    static let openGoalReflect = Notification.Name("openGoalReflect")
    /// Posted (no object) to request the weekly review sheet. OverviewView
    /// observes this and opens the sheet. Used by the weekly-review reminder
    /// notification (`mortalloom://review/weekly`).
    static let openWeeklyReview = Notification.Name("openWeeklyReview")
    /// Posted (no object) to request the monthly rethink sheet. OverviewView
    /// observes this and opens the sheet. Used by the monthly-rethink reminder
    /// notification (`mortalloom://review/monthly`).
    static let openMonthlyRethink = Notification.Name("openMonthlyRethink")
    /// Posted with a `String` object (rsid / findingKey) to request the
    /// `GenomeDetailSheet` for a specific finding. GenomeView observes this
    /// and opens the matching marker / ClinVar hit / APOE result once its
    /// scan data has loaded. Used by the "🧬 Suggested by your DNA" banner
    /// on Habit/Goal edit sheets to tap back to the originating finding.
    static let openGenomeFinding = Notification.Name("openGenomeFinding")
}
