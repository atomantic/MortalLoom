#if os(iOS)
import Foundation
import EventKit
import os

private let calendarLogger = Logger(subsystem: "net.shadowpuppet.MeatSpaceTracker", category: "Calendar")

@MainActor
@Observable
final class CalendarService {
    static let shared = CalendarService()

    /// EKAlarm.relativeOffset is in seconds before the event — negative values.
    private static let tenMinutesBeforeStart: TimeInterval = -600

    private let store = EKEventStore()
    private(set) var authorizationStatus: EKAuthorizationStatus

    private init() {
        self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    var isAuthorized: Bool {
        if #available(iOS 17.0, macOS 14.0, *) {
            return authorizationStatus == .fullAccess
        } else {
            return authorizationStatus == .authorized
        }
    }

    func requestAccess() async -> Bool {
        if #available(iOS 17.0, macOS 14.0, *) {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            return granted
        } else {
            let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                store.requestAccess(to: .event) { granted, _ in
                    cont.resume(returning: granted)
                }
            }
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            return granted
        }
    }

    /// URL scheme used to tag events with a MortalLoom goal id. Storing the
    /// goal id in `event.url` keeps the event round-trippable — we can read
    /// any calendar event back later and know which goal it was scheduled
    /// for (see `TimeAllocationEngine`).
    static let goalURLScheme = "mortalloom"
    static func goalURL(for goalId: UUID) -> URL? {
        URL(string: "\(goalURLScheme)://goal/\(goalId.uuidString)")
    }
    static func goalId(from url: URL?) -> UUID? {
        guard let url, url.scheme == goalURLScheme,
              url.host == "goal" else { return nil }
        let component = url.pathComponents.first(where: { $0 != "/" }) ?? ""
        return UUID(uuidString: component)
    }

    private func makeBaseEvent(
        goalId: UUID?,
        goalTitle: String,
        notes: String,
        startDate: Date,
        durationMinutes: Int
    ) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = "🎯 \(goalTitle)"
        event.notes = notes.isEmpty ? "MortalLoom goal work block" : "\(notes)\n\n— Scheduled by MortalLoom"
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(TimeInterval(durationMinutes * 60))
        event.calendar = store.defaultCalendarForNewEvents
        event.addAlarm(EKAlarm(relativeOffset: Self.tenMinutesBeforeStart))
        if let goalId {
            event.url = Self.goalURL(for: goalId)
        }
        return event
    }

    /// Schedule a single work block for a goal.
    /// Returns the EKEvent's eventIdentifier on success.
    func scheduleWorkBlock(
        goalId: UUID?,
        goalTitle: String,
        notes: String,
        startDate: Date,
        durationMinutes: Int
    ) -> String? {
        guard isAuthorized else { return nil }
        let event = makeBaseEvent(
            goalId: goalId,
            goalTitle: goalTitle,
            notes: notes,
            startDate: startDate,
            durationMinutes: durationMinutes
        )

        do {
            try store.save(event, span: .thisEvent)
            calendarLogger.info("📅 Scheduled work block for '\(goalTitle, privacy: .public)' at \(startDate)")
            return event.eventIdentifier
        } catch {
            calendarLogger.error("⚠️ Failed to schedule work block: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    /// Schedule a recurring work block for a goal over a date range.
    /// Returns the EKEvent's eventIdentifier on success.
    func scheduleRecurringWorkBlock(
        goalId: UUID?,
        goalTitle: String,
        notes: String,
        startDate: Date,
        durationMinutes: Int,
        recurrence: RecurrenceFrequency,
        endDate: Date?
    ) -> String? {
        guard isAuthorized else { return nil }
        let event = makeBaseEvent(
            goalId: goalId,
            goalTitle: goalTitle,
            notes: notes,
            startDate: startDate,
            durationMinutes: durationMinutes
        )

        let frequency: EKRecurrenceFrequency = switch recurrence {
        case .daily: .daily
        case .weekly: .weekly
        case .weekdays: .weekly
        }

        let recurrenceEnd: EKRecurrenceEnd? = endDate.map { EKRecurrenceEnd(end: $0) }

        let rule: EKRecurrenceRule
        if recurrence == .weekdays {
            let weekdays = [EKWeekday.monday, .tuesday, .wednesday, .thursday, .friday].map {
                EKRecurrenceDayOfWeek($0)
            }
            rule = EKRecurrenceRule(
                recurrenceWith: frequency,
                interval: 1,
                daysOfTheWeek: weekdays,
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: recurrenceEnd
            )
        } else {
            rule = EKRecurrenceRule(
                recurrenceWith: frequency,
                interval: 1,
                end: recurrenceEnd
            )
        }
        event.addRecurrenceRule(rule)

        do {
            try store.save(event, span: .futureEvents)
            calendarLogger.info("📅 Scheduled recurring \(recurrence.label, privacy: .public) work block for '\(goalTitle, privacy: .public)'")
            return event.eventIdentifier
        } catch {
            calendarLogger.error("⚠️ Failed to schedule recurring work block: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    /// Read MortalLoom-tagged events from the calendar over a date range.
    /// Returns lightweight `(goalId, startDate, durationMinutes)` tuples so
    /// the engine layer doesn't depend on EventKit types.
    func tagged(from: Date, to: Date) -> [(goalId: UUID, startDate: Date, durationMinutes: Int)] {
        guard isAuthorized else { return [] }
        let calendars = store.calendars(for: .event)
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: calendars)
        let events = store.events(matching: predicate)
        var result: [(goalId: UUID, startDate: Date, durationMinutes: Int)] = []
        for e in events {
            guard let id = Self.goalId(from: e.url) else { continue }
            let minutes = Int(e.endDate.timeIntervalSince(e.startDate) / 60)
            result.append((id, e.startDate, max(0, minutes)))
        }
        return result
    }
}

enum RecurrenceFrequency: String, CaseIterable, Sendable {
    case daily
    case weekly
    case weekdays

    var label: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .weekdays: "Weekdays"
        }
    }
}
#endif
