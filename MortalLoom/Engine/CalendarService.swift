import Foundation
import EventKit
import os

private let calendarLogger = Logger(subsystem: "net.shadowpuppet.MeatSpaceTracker", category: "Calendar")

@MainActor
@Observable
final class CalendarService {
    static let shared = CalendarService()

    private let store = EKEventStore()
    var authorizationStatus: EKAuthorizationStatus

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

    /// Schedule a single work block for a goal.
    /// Returns the EKEvent's eventIdentifier on success.
    func scheduleWorkBlock(
        goalTitle: String,
        notes: String,
        startDate: Date,
        durationMinutes: Int
    ) -> String? {
        guard isAuthorized else { return nil }
        let event = EKEvent(eventStore: store)
        event.title = "🎯 \(goalTitle)"
        event.notes = notes.isEmpty ? "MortalLoom goal work block" : "\(notes)\n\n— Scheduled by MortalLoom"
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(TimeInterval(durationMinutes * 60))
        event.calendar = store.defaultCalendarForNewEvents

        // Add a 10-minute reminder
        event.addAlarm(EKAlarm(relativeOffset: -600))

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
        goalTitle: String,
        notes: String,
        startDate: Date,
        durationMinutes: Int,
        recurrence: RecurrenceFrequency,
        endDate: Date?
    ) -> String? {
        guard isAuthorized else { return nil }
        let event = EKEvent(eventStore: store)
        event.title = "🎯 \(goalTitle)"
        event.notes = notes.isEmpty ? "MortalLoom goal work block" : "\(notes)\n\n— Scheduled by MortalLoom"
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(TimeInterval(durationMinutes * 60))
        event.calendar = store.defaultCalendarForNewEvents

        // Build recurrence rule
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
        event.addAlarm(EKAlarm(relativeOffset: -600))

        do {
            try store.save(event, span: .futureEvents)
            calendarLogger.info("📅 Scheduled recurring \(recurrence.label, privacy: .public) work block for '\(goalTitle, privacy: .public)'")
            return event.eventIdentifier
        } catch {
            calendarLogger.error("⚠️ Failed to schedule recurring work block: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    /// Count the number of events scheduled for this goal in the next 30 days.
    func upcomingEventCount(goalTitle: String, days: Int = 30) -> Int {
        guard isAuthorized else { return 0 }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        return events.filter { $0.title?.contains(goalTitle) ?? false }.count
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
