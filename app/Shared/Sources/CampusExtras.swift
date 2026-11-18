import Foundation

/// Campus beyond single lessons: lessons per week (for the parent summary)
/// and spaced review of what's been learned. Everything lives under
/// `campus.` and is backed up with the athlete's settings.

// MARK: - Weekly log

public enum CampusLog {
    static let weekLessonsKey = "campus.weekLessons"
    /// Retired with Campus points, streaks and leagues (2026-11-18); cleared on the next lesson.
    static let retiredKeys = ["campus.weekXP", "campus.perfect", "campus.reviewsDone", "campus.bestStreak", "campus.xp",
                              "campus.streak", "campus.lastDay", "campus.badges"]

    /// The Monday that starts `date`'s week, YYYY-MM-DD.
    public static func weekKey(_ date: Date = .now, calendar: Calendar = .current) -> String {
        var cal = calendar
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let c = cal.dateComponents([.year, .month, .day], from: start)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// A new lesson learned (the parent summary shows the week's count).
    public static func recordLesson(on date: Date = .now, calendar: Calendar = .current, defaults: UserDefaults = .standard) {
        for key in retiredKeys where defaults.object(forKey: key) != nil { defaults.removeObject(forKey: key) }
        var lessons = dictionary(weekLessonsKey, defaults)
        lessons[weekKey(date, calendar: calendar), default: 0] += 1
        save(lessons, weekLessonsKey, defaults)
    }

    public static func lessons(inWeekOf date: Date = .now, calendar: Calendar = .current, defaults: UserDefaults = .standard) -> Int {
        dictionary(weekLessonsKey, defaults)[weekKey(date, calendar: calendar)] ?? 0
    }

    /// Stored as JSON so the backup (CloudSync) carries it.
    private static func dictionary(_ key: String, _ defaults: UserDefaults) -> [String: Int] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) } ?? [:]
    }

    /// Keeps the last 12 weeks.
    private static func save(_ value: [String: Int], _ key: String, _ defaults: UserDefaults) {
        let kept = Set(value.keys.sorted().suffix(12))
        defaults.set(try? JSONEncoder().encode(value.filter { kept.contains($0.key) }), forKey: key)
    }
}

// MARK: - Spaced review

/// Lessons come back for a quick review after 1, 3, 7, 14, 30 and 60 days
/// (a Leitner box): right answers push a lesson further out, a mistake
/// brings it back to tomorrow. That's what makes knowledge stick.
public enum CampusReview {
    static let key = "campus.review"
    public static let intervals = [1, 3, 7, 14, 30, 60]
    /// Lessons in one review session.
    public static let lessonsPerReview = 3

    struct Card: Codable, Equatable {
        var box: Int
        /// YYYY-MM-DD
        var due: String
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func cards(_ defaults: UserDefaults) -> [String: Card] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: Card].self, from: $0) } ?? [:]
    }

    private static func save(_ cards: [String: Card], _ defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(cards), forKey: key)
    }

    /// A lesson just finished for the first time: review it tomorrow.
    public static func schedule(_ lessonID: String, today: Date = .now, calendar: Calendar = .current, defaults: UserDefaults = .standard) {
        var all = cards(defaults)
        guard all[lessonID] == nil else { return }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        all[lessonID] = Card(box: 0, due: dayKey(tomorrow, calendar: calendar))
        save(all, defaults)
    }

    /// Learned lessons due today (the most overdue first). Lessons learned
    /// before reviews existed count as due.
    public static func due(learned: Set<String>, today: Date = .now, calendar: Calendar = .current,
                           defaults: UserDefaults = .standard) -> [String] {
        let all = cards(defaults)
        let todayKey = dayKey(today, calendar: calendar)
        var due: [(id: String, day: String)] = []
        for id in learned {
            let day: String = all[id]?.due ?? "0000-00-00"
            if day <= todayKey { due.append((id: id, day: day)) }
        }
        due.sort { a, b in a.day == b.day ? a.id < b.id : a.day < b.day }
        return due.map { $0.id }
    }

    /// Two questions from each lesson, different ones from day to day.
    public static func questions(for lessonIDs: [String], today: Date = .now, calendar: Calendar = .current) -> [CampusQuestion] {
        let day = calendar.ordinality(of: .day, in: .era, for: today) ?? 0
        return lessonIDs.flatMap { id -> [CampusQuestion] in
            let pool = campusQuestions[id] ?? campusQuestionsV6[id] ?? []
            guard !pool.isEmpty else { return [] }
            let first = pool[day % pool.count]
            let second = pool[(day + 1) % pool.count]
            return pool.count > 1 ? [first, second] : [first]
        }
    }

    /// Which lesson a question belongs to.
    public static func lesson(of question: CampusQuestion) -> String? {
        campusQuestions.first { $0.value.contains(question) }?.key
    }

    /// After a review: right → the next box, wrong → back to tomorrow.
    public static func record(reviewed: [String], wrong: Set<String>, today: Date = .now, calendar: Calendar = .current,
                              defaults: UserDefaults = .standard) {
        var all = cards(defaults)
        for id in reviewed {
            let box = wrong.contains(id) ? 0 : min((all[id]?.box ?? 0) + 1, intervals.count - 1)
            let next = calendar.date(byAdding: .day, value: intervals[box], to: today) ?? today
            all[id] = Card(box: box, due: dayKey(next, calendar: calendar))
        }
        save(all, defaults)
    }
}
