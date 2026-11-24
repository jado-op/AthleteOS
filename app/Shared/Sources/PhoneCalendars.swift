import Foundation
#if os(iOS) && !APP_EXTENSION
import EventKit
#endif

/// Calendars already on the athlete's phone (owner, 2026-11-24: "the calendar
/// import is a smart idea"). TeamSnap, GameChanger, a school's subscribed
/// calendar or a Google account usually sync into the iPhone's Calendar
/// already, so no link has to be found and pasted: pick it, and its games,
/// practices and exams are read exactly like a linked calendar's
/// (`ScheduleClassifier`). Read only, never written; the events stay on the phone.
public enum PhoneCalendars {
    /// A phone calendar is kept as a feed whose url is "phone:<calendar id>".
    public static let prefix = "phone:"

    public struct Choice: Identifiable, Hashable, Sendable {
        public var id: String
        public var title: String
        public var account: String
    }

    public static func isPhone(_ feed: CalendarFeed) -> Bool { feed.url.hasPrefix(prefix) }

    #if os(iOS) && !APP_EXTENSION
    @MainActor private static let store = EKEventStore()

    /// Asks once; true when the app may read the calendars.
    @MainActor
    public static func requestAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                return try await store.requestFullAccessToEvents()
            }
            return try await store.requestAccess(to: .event)
        } catch {
            return false
        }
    }

    /// The phone's event calendars, by account, birthdays and holidays left out.
    @MainActor
    public static func choices() -> [Choice] {
        store.calendars(for: .event)
            .filter { $0.type != .birthday }
            .map { Choice(id: $0.calendarIdentifier, title: $0.title, account: $0.source?.title ?? "") }
            .sorted { $0.account == $1.account ? $0.title < $1.title : $0.account < $1.account }
    }

    /// The calendar's events from a week ago to half a year ahead.
    @MainActor
    public static func events(for feed: CalendarFeed, now: Date = .now, calendar: Calendar = .current) throws -> [ScheduleEvent] {
        let id = String(feed.url.dropFirst(prefix.count))
        guard let source = store.calendar(withIdentifier: id) else { throw URLError(.fileDoesNotExist) }
        let start = now.addingTimeInterval(-7 * 86_400)
        let end = now.addingTimeInterval(183 * 86_400)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [source])
        let school = feed.role == .school
        return store.events(matching: predicate).map { event in
            let title = event.title ?? ""
            let kind = ScheduleClassifier.kind(title: title, categories: event.notes.map { String($0.prefix(200)) }, schoolCalendar: school)
            let begin: Date = event.isAllDay ? calendar.startOfDay(for: event.startDate) : event.startDate
            return ScheduleEvent(
                id: "\(feed.id)|\(event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? title)|\(Int(begin.timeIntervalSince1970))",
                title: title, location: event.location.flatMap { $0.isEmpty ? nil : $0 },
                start: begin, end: event.endDate, allDay: event.isAllDay, kind: kind,
                cancelled: event.status == .canceled || ScheduleClassifier.isCancelled(title: title, status: nil),
                isAway: ScheduleClassifier.isAway(title: title),
                competitionKind: ScheduleClassifier.competitionKind(title: title))
        }
        .sorted { $0.start < $1.start }
    }
    #else
    @MainActor public static func requestAccess() async -> Bool { false }
    @MainActor public static func choices() -> [Choice] { [] }
    @MainActor public static func events(for feed: CalendarFeed, now: Date = .now, calendar: Calendar = .current) throws -> [ScheduleEvent] {
        throw URLError(.unsupportedURL)
    }
    #endif
}
