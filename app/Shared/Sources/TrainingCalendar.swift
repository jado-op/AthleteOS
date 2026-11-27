import Foundation

/// What the training calendar shows on a day (owner, 2026-11-27: "rework the
/// whole calendar feed and what it shows on what days — it is pretty
/// confusing"). One model for the month grid, the agenda and the day sheet,
/// so they can never disagree. Rules, in plain words:
/// - The past shows only what happened. Nothing on a past day is "planned".
///   A practice on the schedule that wasn't logged still happened as far as
///   the app knows: it shows as practice, marked "from your schedule".
/// - Today shows what's done plus the one workout every screen shows today.
/// - Ahead: games, scheduled practice, this week's planned workouts, and days
///   the athlete can't train (or is sick or away).
/// - Four kinds, four colours: workout, practice, game, mobility.
public enum TrainingCalendar {
    public struct Item: Equatable, Sendable, Identifiable {
        public enum Kind: String, Sendable, CaseIterable { case game, workout, practice, mobility, off }
        public enum State: String, Sendable {
            /// It happened (logged, recorded or played).
            case done
            /// Still to come.
            case planned
            /// A past practice from the team schedule, not logged.
            case fromSchedule
        }

        public var kind: Kind
        public var state: State
        public var title: String
        public var detail: String?

        public init(kind: Kind, state: State, title: String, detail: String? = nil) {
            self.kind = kind
            self.state = state
            self.title = title
            self.detail = detail
        }

        public var id: String { "\(kind.rawValue)-\(state.rawValue)-\(title)-\(detail ?? "")" }
    }

    /// Everything the app knows about one day, gathered by the screen.
    public struct Facts: Sendable {
        public enum When: Sendable { case past, today, future }

        public var when: When
        /// Finished workouts: title, detail line, whether it was mobility.
        public var workoutsDone: [(title: String, detail: String?, mobility: Bool)] = []
        /// The logged practice, summarised.
        public var practiceLogged: String?
        /// Practice on the schedule ("4:00–6:00 pm", or "" with no time).
        public var practiceScheduled: String?
        /// Games that day: "Match · 3:00 pm", home or away.
        public var games: [(title: String, detail: String?)] = []
        /// The workout planned for the day (today: the one every screen shows).
        public var plannedWorkout: (title: String, minutes: Int)?
        /// Why nothing can happen: "Can't train", "Sick", "Away".
        public var off: String?

        public init(when: When) { self.when = when }
    }

    /// The day's items, most important first: game, workouts, practice, mobility, off.
    public static func items(_ facts: Facts) -> [Item] {
        var items: [Item] = []
        let past = facts.when == .past
        for game in facts.games {
            items.append(Item(kind: .game, state: past ? .done : .planned, title: game.title, detail: game.detail))
        }
        let workouts = facts.workoutsDone.filter { !$0.mobility }
        for workout in workouts {
            items.append(Item(kind: .workout, state: .done, title: workout.title, detail: workout.detail))
        }
        // A plan never shows on a past day, nor once a workout is done that day.
        if !past, workouts.isEmpty, facts.off == nil, let planned = facts.plannedWorkout {
            items.append(Item(kind: .workout, state: .planned, title: planned.title, detail: "About \(planned.minutes) min"))
        }
        if let logged = facts.practiceLogged {
            items.append(Item(kind: .practice, state: .done, title: "Team practice", detail: logged.isEmpty ? nil : logged))
        } else if let scheduled = facts.practiceScheduled {
            let time = scheduled.isEmpty ? nil : scheduled
            items.append(past
                ? Item(kind: .practice, state: .fromSchedule, title: "Team practice", detail: [time, "from your schedule"].compactMap { $0 }.joined(separator: " · "))
                : Item(kind: .practice, state: .planned, title: "Team practice", detail: time))
        }
        for mobility in facts.workoutsDone.filter(\.mobility) {
            items.append(Item(kind: .mobility, state: .done, title: mobility.title, detail: mobility.detail))
        }
        if let off = facts.off, items.allSatisfy({ $0.state != .done }) {
            items.append(Item(kind: .off, state: past ? .done : .planned, title: off))
        }
        return items
    }

    /// The marks under a day number: at most three, one per kind, done before planned.
    public static func marks(_ items: [Item]) -> [Item] {
        var seen = Set<Item.Kind>()
        var marks: [Item] = []
        for item in items where !seen.contains(item.kind) {
            seen.insert(item.kind)
            marks.append(item)
            if marks.count == 3 { break }
        }
        return marks
    }

    /// One line for the agenda: "Match · 3:00 pm, then 20 min after practice".
    public static func line(_ items: [Item]) -> String {
        guard !items.isEmpty else { return "Rest" }
        return items.map { item in
            switch item.kind {
            case .practice: return item.state == .fromSchedule ? "Practice" : (item.detail.map { "Practice \($0)" } ?? "Practice")
            case .workout where item.state == .planned: return item.detail.map { "\(item.title) · \($0.replacingOccurrences(of: "About ", with: ""))" } ?? item.title
            case .game: return item.detail.map { "\(item.title) · \($0)" } ?? item.title
            default: return item.title
            }
        }.joined(separator: " + ")
    }
}
