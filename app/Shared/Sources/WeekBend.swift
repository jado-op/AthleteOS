import Foundation

/// "A plan you can see bend" (owner, 2026-11-27): the athlete changes the
/// week (a game moves, a day they can't train) and sees every day that
/// changed, labelled in words. This only compares two weeks the planner
/// already built; it never plans anything itself.
public enum WeekBend {
    /// One day of the week as the athlete sees it.
    public struct Day: Equatable, Sendable {
        public enum Kind: String, Sendable { case gym, practice, game, rest, blocked }
        public var date: Date
        public var kind: Kind
        /// The workout on top of the day (a practice day can carry a short one).
        public var workout: String?
        public var minutes: Int?

        public init(date: Date, kind: Kind, workout: String? = nil, minutes: Int? = nil) {
            self.date = date
            self.kind = kind
            self.workout = workout
            self.minutes = minutes
        }

        var hasWorkout: Bool { workout != nil }
    }

    /// The label for each day that changed, by day index. `event` is the
    /// athlete's word for a game ("Match", "Race").
    public static func changes(before: [Day], after: [Day], event: String = "Game", calendar: Calendar = .current) -> [Int: String] {
        var out: [Int: String] = [:]
        let count = min(before.count, after.count)
        let lost = (0..<count).filter { before[$0].hasWorkout && !after[$0].hasWorkout }
        let gained = (0..<count).filter { !before[$0].hasWorkout && after[$0].hasWorkout }
        func weekday(_ index: Int) -> String {
            after[index].date.formatted(.dateTime.weekday(.abbreviated))
        }
        for i in 0..<count {
            let b = before[i], a = after[i]
            if a.kind == .blocked && b.kind != .blocked { out[i] = "You can't train"; continue }
            if b.kind == .blocked && a.kind != .blocked { out[i] = "Free again"; continue }
            if a.kind == .game && b.kind != .game { out[i] = "\(event) added"; continue }
            if b.kind == .game && a.kind != .game { out[i] = "\(event) removed" }
            if gained.contains(i) {
                // The nearest day that lost one is where it came from.
                if let from = lost.min(by: { abs($0 - i) < abs($1 - i) }) {
                    out[i] = "Moved here from \(weekday(from))"
                } else {
                    out[i] = "Workout added"
                }
                continue
            }
            if lost.contains(i) {
                if let to = gained.min(by: { abs($0 - i) < abs($1 - i) }) {
                    out[i] = out[i].map { "\($0) · moved to \(weekday(to))" } ?? "Moved to \(weekday(to))"
                } else {
                    out[i] = out[i].map { "\($0) · rest instead" } ?? "Rest instead"
                }
                continue
            }
            if let before = b.minutes, let after = a.minutes, a.hasWorkout, b.hasWorkout, before != after {
                let text = after < before ? "Shorter: \(before) → \(after) min" : "Longer: \(before) → \(after) min"
                out[i] = out[i].map { "\($0) · \(text)" } ?? text
                continue
            }
            if a.hasWorkout, b.hasWorkout, a.workout != b.workout, let title = a.workout {
                out[i] = out[i].map { "\($0) · now \(title)" } ?? "Now: \(title)"
            }
        }
        return out
    }
}
