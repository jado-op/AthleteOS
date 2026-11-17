import Foundation

/// The athlete's Academy data on this phone. Private to the athlete: it is
/// never part of the parent summary, coach or team data. (The encrypted
/// backup to their own account is docs/ACADEMY-PLAN.md step 3; until then
/// it stays on the phone — its key is outside every CloudSync group.)
public enum AcademyStore {
    static let key = "academyTwin.state.v1"

    public static func load(_ defaults: UserDefaults = .standard) -> AcademyState {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(AcademyState.self, from: data) else { return AcademyState() }
        return state
    }

    public static func save(_ state: AcademyState, _ defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }

    /// Deletes the twin and every answer on this phone.
    public static func delete(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    /// The state after finishing `lesson` with `answers` (question id → chosen
    /// option). Each answer's effects plus the lesson's own completion move the
    /// twin; a lesson that was already finished moves it no further.
    public static func completing(_ lesson: AcademyLesson, answers: [String: Int], in state: AcademyState,
                                  at date: Date) -> AcademyState {
        guard state.completed[lesson.id] == nil else { return state }
        var next = state
        for question in lesson.questions {
            guard let chosen = answers[question.id], question.options.indices.contains(chosen) else { continue }
            for spec in question.options[chosen].effects {
                next.ledger.append(TwinEffect(date: date, source: "lesson:\(lesson.id)/\(question.id)", spec: spec))
            }
        }
        for spec in lesson.completion {
            next.ledger.append(TwinEffect(date: date, source: "lesson:\(lesson.id)", spec: spec))
        }
        next.completed[lesson.id] = date
        return next
    }

    /// Lessons finished on the day of `date` (for a future daily limit).
    public static func finished(on date: Date, in state: AcademyState, calendar: Calendar = .current) -> Int {
        state.completed.values.filter { calendar.isDate($0, inSameDayAs: date) }.count
    }
}

/// Privacy-friendly usage events: counted on this phone only (UsageCounts),
/// never uploaded, never with an answer, a reflection text or an identifier.
public enum AcademyEvent: String, CaseIterable, Sendable {
    case twinViewed = "twin_viewed"
    case bodyZoneTapped = "body_zone_tapped"
    case lessonCompleted = "lesson_completed"
    case reflectionSubmitted = "reflection_submitted"
    case twinBorn = "twin_born"

    public static func log(_ event: AcademyEvent, _ defaults: UserDefaults = .standard) {
        UsageCounts.count("academy.\(event.rawValue)", defaults)
    }
}

/// Who may take Academy lessons, and how many. The beta is free and
/// unlimited for everyone; a daily limit for free accounts can be switched on
/// here later without touching the screens. Separate from Campus's limit.
public enum AcademyAccess {
    /// nil = unlimited (the beta).
    public static let freeLessonsPerDay: Int? = nil

    public static func canStartLesson(finishedToday: Int, isPro: Bool, limit: Int? = freeLessonsPerDay) -> Bool {
        guard let limit, !isPro else { return true }
        return finishedToday < limit
    }
}
