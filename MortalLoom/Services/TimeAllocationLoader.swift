import Foundation

// MARK: - TimeAllocationLoader

/// Bridges `CalendarService`'s EventKit reads to `TimeAllocationEngine` for
/// every surface that shows "TIME ALLOCATED" (Pillar Dashboard, Reports,
/// eventually the Weekly Review). Owns the platform guard and the shared
/// lookback window so consumers can't drift apart.
@MainActor
enum TimeAllocationLoader {

    /// Days of calendar history each TIME ALLOCATED surface analyzes.
    static let lookbackDays = 30

    /// Allocation over the last `lookbackDays`, or nil when Calendar access
    /// is unavailable (macOS, or iOS without authorization) — consumers hide
    /// their card on nil.
    static func recentAllocation(goals: [Goal], now: Date = Date()) -> TimeAllocationEngine.Allocation? {
        #if os(iOS)
        guard CalendarService.shared.isAuthorized else { return nil }
        let from = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: now) ?? now
        let events = CalendarService.shared.tagged(from: from, to: now)
        return TimeAllocationEngine.allocate(goals: goals, events: events)
        #else
        return nil
        #endif
    }
}
