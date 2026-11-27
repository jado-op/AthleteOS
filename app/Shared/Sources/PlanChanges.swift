import Foundation

/// What changed between two plans of record, in words worth telling
/// (owner, 2026-11-27: the plan adapted silently, so it looked random).
/// Rules from `docs/PLAN-CHANGES-RESEARCH.md`:
/// - Only changes the athlete would act on and can see a cause for (P2): a
///   day gains or loses a workout, a practice, a game or a day off. The
///   engine re-deciding a workout's focus or length after a session, a
///   check-in or a Health import stays silent (a second review found those
///   told every week without a cause); the strip and "Why?" still show them.
/// - One line per day, before → after, then the cause the app knows (P3):
///   "Thursday: Legs → Strength after practice · practice added".
/// - Changes within one batch merge per day, and a day that went back to how
///   it was drops out (P4). More than three days become one summary line.
/// - Today is never told here: the now slot already shows today with its why
///   (a check-in or the after-practice pick reshapes today every morning).
public struct PlanChange: Codable, Equatable, Sendable, Identifiable {
    public var date: Date
    /// The day as it was first planned in this batch.
    public var before: PlannedDay
    public var after: PlannedDay
    public var id: Date { date }

    public init(date: Date, before: PlannedDay, after: PlannedDay) {
        self.date = date
        self.before = before
        self.after = after
    }
}

public enum PlanChanges {
    /// More changed days than this become one summary line (P4).
    public static let summaryAfter = 3

    /// Days after today whose plan changed in a way worth telling, oldest first.
    public static func compare(_ old: PlanRecord?, _ new: PlanRecord, calendar: Calendar = .current, now: Date = .now) -> [PlanChange] {
        guard let old else { return [] }
        let today = calendar.startOfDay(for: now)
        return new.days.compactMap { after -> PlanChange? in
            let day = calendar.startOfDay(for: after.date)
            guard day > today, let before = old.day(on: day, calendar: calendar), worthTelling(before, after) else { return nil }
            return PlanChange(date: day, before: before, after: after)
        }
    }

    /// Whether the athlete would do something different because of the change.
    public static func worthTelling(_ before: PlannedDay, _ after: PlannedDay) -> Bool {
        // Doing the workout isn't a change of plan.
        if before.items.contains(where: { $0.state == .done }) || after.items.contains(where: { $0.state == .done }) { return false }
        return signature(before) != signature(after)
    }

    /// What kinds the day holds (game, workout, practice, off), ignoring titles.
    static func signature(_ day: PlannedDay) -> Set<TrainingCalendar.Item.Kind> {
        Set(day.items.filter { $0.kind != .mobility }.map(\.kind))
    }

    /// Adds a new batch to changes not yet seen: per day the first "before"
    /// stays, the newest "after" wins, and a day back where it started drops out.
    public static func merge(_ pending: [PlanChange], with fresh: [PlanChange], calendar: Calendar = .current, now: Date = .now) -> [PlanChange] {
        let today = calendar.startOfDay(for: now)
        var byDay: [Date: PlanChange] = [:]
        for change in pending where change.date > today { byDay[change.date] = change }
        for change in fresh {
            if let earlier = byDay[change.date] {
                byDay[change.date] = PlanChange(date: change.date, before: earlier.before, after: change.after)
            } else {
                byDay[change.date] = change
            }
        }
        return byDay.values
            .filter { $0.date > today && worthTelling($0.before, $0.after) }
            .sorted { $0.date < $1.date }
    }

    /// The cause the app can see by comparing the two days (P3: say what the
    /// app knew). Nil when nothing around the workout changed.
    public static func cause(_ change: PlanChange, event: String = "Game") -> String? {
        let was = signature(change.before), now = signature(change.after)
        // A day off names itself ("Away", "Sick"): no second word for it.
        if now.contains(.off), !was.contains(.off) { return nil }
        if was.contains(.off), !now.contains(.off) { return "free to train again" }
        if now.contains(.game), !was.contains(.game) { return "\(event.lowercased()) added" }
        if was.contains(.game), !now.contains(.game) { return "\(event.lowercased()) removed" }
        if now.contains(.practice), !was.contains(.practice) { return "practice added" }
        if was.contains(.practice), !now.contains(.practice) { return "no practice now" }
        return nil
    }

    /// "Thursday: Legs → Strength after practice · practice added".
    public static func line(_ change: PlanChange, event: String = "Game", calendar: Calendar = .current, now: Date = .now) -> String {
        let name = dayName(change.date, calendar: calendar, now: now)
        let what = change.before.title == change.after.title
            ? "\(change.after.title) \(change.before.minutes.map { "\($0)" } ?? "?") → \(change.after.minutes.map { "\($0) min" } ?? "?")"
            : "\(change.before.title) → \(change.after.title)"
        let why = cause(change, event: event) ?? (change.after.kind == .off ? nil : change.after.because)
        return [ "\(name): \(what)", why ].compactMap { $0 }.joined(separator: " · ")
    }

    /// One headline for a batch: the line itself, or a summary past three days (P4).
    public static func headline(_ changes: [PlanChange], event: String = "Game", calendar: Calendar = .current, now: Date = .now) -> String? {
        guard let first = changes.first else { return nil }
        if changes.count == 1 { return line(first, event: event, calendar: calendar, now: now) }
        if changes.count <= summaryAfter {
            let names = changes.map { change -> String in
                let name = dayName(change.date, calendar: calendar, now: now)
                return name == "Today" || name == "Tomorrow" ? name.lowercased() : name
            }
            return "Your plan changed for " + names.formattedList()
        }
        return "Your plan changed on \(changes.count) days"
    }

    /// "Today", "Tomorrow" or the weekday.
    public static func dayName(_ date: Date, calendar: Calendar = .current, now: Date = .now) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
}

private extension Array where Element == String {
    /// "Tuesday and Thursday", "Monday, Tuesday and Friday".
    func formattedList() -> String {
        guard count > 1 else { return first ?? "" }
        return dropLast().joined(separator: ", ") + " and " + (last ?? "")
    }
}
