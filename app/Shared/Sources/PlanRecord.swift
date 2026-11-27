import Foundation

/// The plan of record (owner, 2026-11-27: "make the ecosystem way better"):
/// today and the next seven days, decided once whenever an input changes and
/// saved. Home's Tomorrow, the week strip, Edit week, the Lock Screen card and
/// the evening message all read these days instead of working a day out
/// themselves, so two screens can never say different things.
public struct PlannedDay: Codable, Equatable, Sendable {
    /// Start of the day.
    public var date: Date
    /// The day in the training calendar's words, most important first.
    public var items: [TrainingCalendar.Item]
    /// The planned workout's length, when the day has one still to come.
    public var minutes: Int?
    /// Why the day looks like this, short: "Game in 2 days · legs tired".
    public var because: String?
    /// The same without body, health or mood words, for the Lock Screen.
    public var publicBecause: String?

    public init(date: Date, items: [TrainingCalendar.Item], minutes: Int? = nil, because: String? = nil, publicBecause: String? = nil) {
        self.date = date
        self.items = items
        self.minutes = minutes
        self.because = because
        self.publicBecause = publicBecause
    }

    /// What the day is about: a game, else a day off (sick, paused, away —
    /// a practice on the schedule doesn't make it a practice day), else the
    /// calendar's first item.
    public var main: TrainingCalendar.Item? {
        items.first { $0.kind == .game } ?? items.first { $0.kind == .off && $0.state == .planned } ?? items.first
    }

    /// The one thing the day is about ("Match", "Strength after practice", "Rest day").
    public var title: String { main?.title ?? "Rest day" }

    /// The rest of the day in one line, or the main item's own detail.
    public var detail: String? {
        guard let main else { return "Recovery is part of the plan." }
        if main.kind == .off { return nil }
        let rest = items.filter { $0 != main }
        return rest.isEmpty ? main.detail : TrainingCalendar.line(rest)
    }

    /// What kind of day it is; nil for a plain rest day.
    public var kind: TrainingCalendar.Item.Kind? { main?.kind }

    /// A day built around a game.
    public var isGame: Bool { kind == .game }
}

public struct PlanRecord: Codable, Equatable, Sendable {
    /// The calendar's word for a day the athlete said they can't train.
    public static let cantTrain = "Can't train"

    public var builtAt: Date
    /// Today first, then the next seven days.
    public var days: [PlannedDay]

    public init(builtAt: Date, days: [PlannedDay]) {
        self.builtAt = builtAt
        self.days = days
    }

    /// The planned day for `date`, if this record covers it.
    public func day(on date: Date, calendar: Calendar = .current) -> PlannedDay? {
        days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// Why a day with nothing planned or only practice looks the way it does
    /// (the words the Lock Screen card always used).
    public static func because(for items: [TrainingCalendar.Item], workoutBecause: String?) -> String? {
        guard let main = PlannedDay(date: .distantPast, items: items).main else { return "Recovery is part of the plan" }
        switch main.kind {
        case .game: return main.detail.map { "\($0) · save everything for it" } ?? "Save everything for it"
        case .workout: return main.state == .planned ? workoutBecause : nil
        case .practice: return main.state == .planned ? "Practice day" : nil
        case .mobility: return nil
        case .off: return main.state == .planned && main.title == cantTrain ? "You said you can't train" : nil
        }
    }
}
