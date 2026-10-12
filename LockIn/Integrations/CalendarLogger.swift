import Foundation
import EventKit
import Observation

/// Writes completed focus blocks to an Apple Calendar (one-way). Notion Calendar, Fantastical,
/// and the rest of the ecosystem can subscribe to that calendar, so this is the bridge.
@Observable
@MainActor
final class CalendarLogger {
    static let shared = CalendarLogger()

    let store = EKEventStore()
    private(set) var authorized = false

    private init() {
        authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestAccess() async -> Bool {
        do {
            authorized = try await store.requestFullAccessToEvents()
        } catch {
            authorized = false
        }
        return authorized
    }

    var writableCalendars: [EKCalendar] {
        guard authorized else { return [] }
        return store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func log(session: FocusSession, subjectName: String?) {
        Task {
            if !self.authorized { _ = await self.requestAccess() }
            guard self.authorized else { return }
            let settings = AppSettings.shared
            let calendar = self.store.calendar(withIdentifier: settings.calendarIdentifier)
                ?? self.store.defaultCalendarForNewEvents
            guard let calendar else { return }

            let event = EKEvent(eventStore: self.store)
            event.calendar = calendar
            var title = "Focus"
            if let subjectName, !subjectName.isEmpty { title += ": \(subjectName)" }
            if !session.intention.isEmpty { title += " — \(session.intention)" }
            event.title = title
            event.startDate = session.startedAt
            event.endDate = session.endedAt
            event.notes = "Logged by LockIn. \(Fmt.duration(session.focusedSeconds)) focused."
            try? self.store.save(event, span: .thisEvent, commit: true)
        }
    }
}
