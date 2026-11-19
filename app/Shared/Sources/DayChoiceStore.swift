import Foundation

/// The athlete's "What's on today?" answers, one per day (the last 60 days).
/// Under "schedule." so it is backed up with the practice days (CloudSync's
/// settings prefixes; not a sealed group — it holds no private words).
public enum DayChoiceStore {
    static let key = "schedule.dayChoices"

    /// The answer for that day (nil: none given, the schedule decides).
    public static func answer(on date: Date = .now, calendar: Calendar = .current, _ defaults: UserDefaults = .standard) -> DayAnswer? {
        answer(forDay: DayKey.of(date, calendar: calendar), defaults)
    }

    public static func answer(forDay day: String, _ defaults: UserDefaults = .standard) -> DayAnswer? {
        let entries = defaults.stringArray(forKey: key) ?? []
        guard let entry = entries.last(where: { $0.hasPrefix(day + "=") }) else { return nil }
        return DayAnswer(encoded: String(entry.dropFirst(day.count + 1)))
    }

    /// Stores the answer for that day ("let AthleteOS decide" or nil clears
    /// it). Team practice said or not said also becomes that day's practice
    /// override (PracticeOverride), so every screen that asks "practice
    /// today?" follows the athlete's word, not only the planner.
    public static func set(_ answer: DayAnswer?, on date: Date = .now, calendar: Calendar = .current, _ defaults: UserDefaults = .standard) {
        let day = DayKey.of(date, calendar: calendar)
        var entries = (defaults.stringArray(forKey: key) ?? []).filter { !$0.hasPrefix(day + "=") }
        if let answer, !answer.isAuto { entries.append("\(day)=\(answer.encoded)") }
        defaults.set(Array(entries.sorted().suffix(60)), forKey: key)

        // Only a day that differs from the schedule is remembered as an override.
        PracticeOverride.set(nil, on: day, defaults)
        if let answer, !answer.isAuto {
            let wantsPractice = answer.choices.contains(.practice)
            if wantsPractice != PracticeSchedule.hasPractice(on: date, calendar: calendar) {
                PracticeOverride.set(wantsPractice, on: day, defaults)
            }
        }
    }

    /// The athlete's word on a game today: nil when they left it to the
    /// schedule (then the competitions list decides).
    public static func saysGame(on date: Date = .now, calendar: Calendar = .current) -> Bool? {
        guard let answer = answer(on: date, calendar: calendar), !answer.isAuto else { return nil }
        return answer.choices.contains(.game)
    }
}
