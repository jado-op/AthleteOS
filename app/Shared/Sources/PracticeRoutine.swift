import Foundation

/// Better practice data (owner, 2026-11-27; docs/PLAN-CHANGES-RESEARCH.md
/// P14–P17). The plan is only as good as the practice schedule, so:
/// - **Propose, don't assume** (P14): a weekday with logged practice in at
///   least 3 of the last 4 full weeks, that the schedule doesn't have, is
///   offered once as "Practice on Tuesday and Thursday?" — Yes / Not quite /
///   No. A "No" keeps that offer away for 6 weeks (P16). Never with a team
///   calendar connected: the calendar decides.
/// - **One tap for yesterday** (P17): a scheduled practice with nothing
///   logged is asked about the next day only ("Went · normal / Went · hard /
///   Didn't go"). Later it stays "not said" — never guessed.
public enum PracticeRoutine {
    public static let weeksLooked = 4
    public static let weeksNeeded = 3
    public static let declineDays = 42

    /// Weekdays (1 = Sunday … 7 = Saturday) with a logged practice in at
    /// least 3 of the last 4 full weeks before `now`'s week.
    public static func inferredWeekdays(_ practiceDays: [Date], now: Date, calendar: Calendar = .current) -> Set<Int> {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        var weeksByWeekday: [Int: Set<Date>] = [:]
        for day in practiceDays {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: day), week.start < thisWeek.start,
                  let weeksBack = calendar.dateComponents([.weekOfYear], from: week.start, to: thisWeek.start).weekOfYear,
                  weeksBack <= weeksLooked else { continue }
            weeksByWeekday[calendar.component(.weekday, from: day), default: []].insert(week.start)
        }
        return Set(weeksByWeekday.filter { $0.value.count >= weeksNeeded }.keys)
    }

    /// The weekdays worth offering, or nothing.
    public static func proposal(inferred: Set<Int>, current: Set<Int>, hasCalendar: Bool, declinedUntil: Date?, now: Date) -> Set<Int> {
        guard !hasCalendar, declinedUntil.map({ now >= $0 }) ?? true else { return [] }
        return inferred.subtracting(current)
    }

    /// "Tuesday and Thursday".
    public static func names(_ weekdays: Set<Int>, calendar: Calendar = .current) -> String {
        // Monday first, Sunday last.
        let order = weekdays.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }
        let english = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let names = order.map { english[($0 - 1) % 7] }
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
    }

    /// The day before `now`, if its scheduled practice should be asked about:
    /// practice was on the schedule, nothing is logged, nobody answered.
    public static func dayToAsk(now: Date, hadPractice: (Date) -> Bool, logged: (Date) -> Bool, answered: (Date) -> Bool,
                                calendar: Calendar = .current) -> Date? {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
              hadPractice(yesterday), !logged(yesterday), !answered(yesterday) else { return nil }
        return yesterday
    }

    /// The one-tap answers: how hard it was (1–5), or that there was no practice.
    public enum Answer: CaseIterable, Sendable {
        case normal, hard, didntGo

        public var title: String {
            switch self {
            case .normal: "Went · normal"
            case .hard: "Went · hard"
            case .didntGo: "Didn't go"
            }
        }

        /// The practice log's "how hard" (1 easy … 5 exhausting); nil: no practice.
        public var hard: Int? {
            switch self {
            case .normal: 3
            case .hard: 4
            case .didntGo: nil
            }
        }
    }
}
