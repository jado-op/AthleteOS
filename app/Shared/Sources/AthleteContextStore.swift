import Foundation

/// The athlete's context events on the phone (`AthleteContext`). Body
/// feedback is sensitive, so it lives in the sealed `safety.` group: backed up
/// only encrypted with the athlete's own key (CloudSeal), never readable on
/// our server, never shown to coaches or parents.
@MainActor
enum AthleteContextStore {
    private static let key = "safety.athleteContext"
    private static let revisionKey = "context.revision"

    static var all: [AthleteContextEvent] {
        get {
            let events = UserDefaults.standard.data(forKey: key)
                .flatMap { try? JSONDecoder().decode([AthleteContextEvent].self, from: $0) } ?? []
            return AthleteContext.expire(events, now: .now)
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key)
            UserDefaults.standard.set(revision + 1, forKey: revisionKey)
        }
    }

    /// Changes whenever an event is added or answered (plans cache by it).
    static var revision: Int { UserDefaults.standard.integer(forKey: revisionKey) }

    static func add(_ event: AthleteContextEvent) {
        all = AthleteContext.adding(event, to: all)
    }

    static func answer(_ answer: ContextQuestion.Answer, to question: ContextQuestion, now: Date = .now) {
        var events = all
        if let target = events.first(where: { $0.id == question.id }) {
            if target.kind == .fatigue {
                events = AthleteContext.answering(answer, to: target.id, in: events, now: now)
            } else if let fatigue = AthleteContext.fatigueFromAnswer(answer, to: target, now: now) {
                events = AthleteContext.adding(fatigue, to: events)
            } else {
                // Fresh after the hard session: remembered, so it isn't asked again.
                var noted = AthleteContextEvent(from: now, kind: .fatigue, source: .morningCheckIn, reported: ["Legs fresh this morning"],
                                                regions: [.legs], level: 0, status: .resolved, relatedID: target.id)
                noted.checks = [.init(day: Calendar.current.startOfDay(for: now), level: 0)]
                events = AthleteContext.adding(noted, to: events)
            }
        }
        all = events
    }

    static func signals(on date: Date) -> ContextSignals {
        var s = AthleteContext.signals(all, on: date)
        // How the body feels is about now: a later day of the week plan doesn't inherit it.
        if !Calendar.current.isDateInToday(date) {
            s.fatigue = [:]
            s.fatigueRegions = []
        }
        return s
    }

    static func questions(now: Date = .now) -> [ContextQuestion] {
        AthleteContext.questions(all, now: now)
    }

    /// Forgets every context event on this phone.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.set(revision + 1, forKey: revisionKey)
    }
}
