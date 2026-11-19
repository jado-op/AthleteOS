import Foundation

/// How a competition went, in the athlete's own words.
public struct CompetitionResult: Codable, Equatable, Sendable, Identifiable {
    public enum Outcome: String, Codable, CaseIterable, Sendable {
        case win, draw, loss, placed

        public var title: String {
            switch self {
            case .win: "Won"
            case .draw: "Draw"
            case .loss: "Lost"
            case .placed: "Placed"
            }
        }
    }

    /// The Competition's id.
    public var id: String
    public var outcome: Outcome
    /// 1st, 2nd… for races, meets and tournaments.
    public var placement: Int?
    /// "2–1", "6–4 3–6 7–5", "11.84 s".
    public var score: String?
    /// How the athlete played: 1 (poorly) … 5 (great).
    public var rating: Int
    public var wentWell: [String]
    public var toImprove: [String]
    public var note: String?
    public var savedAt: Date

    public init(id: String, outcome: Outcome, placement: Int? = nil, score: String? = nil, rating: Int, wentWell: [String] = [],
                toImprove: [String] = [], note: String? = nil, savedAt: Date = .now) {
        self.id = id
        self.outcome = outcome
        self.placement = placement
        self.score = score
        self.rating = rating
        self.wentWell = wentWell
        self.toImprove = toImprove
        self.note = note
        self.savedAt = savedAt
    }

    /// "Won 2–1", "Placed 3rd · 11.84 s".
    public var summary: String {
        var text = outcome == .placed ? "Placed \(placement.map(CompetitionCoach.ordinal) ?? "")" : outcome.title
        if let score, !score.isEmpty { text += outcome == .placed ? " · \(score)" : " \(score)" }
        return text.trimmingCharacters(in: .whitespaces)
    }
}

/// The athlete's own read of the next competition: their chance, 0–100.
public struct CompetitionOutlook: Codable, Equatable, Sendable {
    public var id: String
    public var chance: Int
    public var savedAt: Date

    public init(id: String, chance: Int, savedAt: Date = .now) {
        self.id = id
        self.chance = chance
        self.savedAt = savedAt
    }
}

/// Results and outlooks. Results hold the athlete's own words (notes, what
/// went well), so they live in the sealed `mindset.` group (encrypted before
/// backup); outlooks are just numbers.
public enum CompetitionStore {
    static let resultsKey = "mindset.competitionResults"
    static let oldResultsKey = "progress.competitionResults"
    static let outlooksKey = "progress.competitionOutlooks"

    public static func results(_ defaults: UserDefaults = .standard) -> [String: CompetitionResult] {
        if let old = defaults.data(forKey: oldResultsKey) {
            if defaults.data(forKey: resultsKey) == nil { defaults.set(old, forKey: resultsKey) }
            defaults.removeObject(forKey: oldResultsKey)
        }
        return defaults.data(forKey: resultsKey).flatMap { try? JSONDecoder().decode([String: CompetitionResult].self, from: $0) } ?? [:]
    }

    public static func save(_ result: CompetitionResult, _ defaults: UserDefaults = .standard) {
        var all = results(defaults)
        all[result.id] = result
        defaults.set(try? JSONEncoder().encode(all), forKey: resultsKey)
    }

    public static func outlooks(_ defaults: UserDefaults = .standard) -> [String: CompetitionOutlook] {
        defaults.data(forKey: outlooksKey).flatMap { try? JSONDecoder().decode([String: CompetitionOutlook].self, from: $0) } ?? [:]
    }

    public static func save(_ outlook: CompetitionOutlook, _ defaults: UserDefaults = .standard) {
        var all = outlooks(defaults)
        all[outlook.id] = outlook
        defaults.set(try? JSONEncoder().encode(all), forKey: outlooksKey)
    }

    /// A deleted competition takes its result and outlook with it.
    public static func forget(_ id: String, _ defaults: UserDefaults = .standard) {
        var all = results(defaults)
        if all.removeValue(forKey: id) != nil { defaults.set(try? JSONEncoder().encode(all), forKey: resultsKey) }
        var looks = outlooks(defaults)
        if looks.removeValue(forKey: id) != nil { defaults.set(try? JSONEncoder().encode(looks), forKey: outlooksKey) }
    }
}

/// One thing to work on before the next competition.
public struct CompetitionFocus: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    /// A briefing that goes deeper.
    public var briefingID: String?
    /// A development goal (Struggle raw value) the training can lean towards.
    public var goal: String?
}

/// From the last result to the next competition: what to work on, in order.
/// Rule-based. Texts use {event} words, filled with the athlete's sport.
public enum CompetitionCoach {
    public static func focus(last: CompetitionResult?, insights: [TwinInsightKind], daysToNext: Int?, team: Bool) -> [CompetitionFocus] {
        var out: [CompetitionFocus] = []
        func add(_ point: CompetitionFocus) {
            guard out.count < 3, !out.contains(where: { $0.id == point.id || ($0.briefingID != nil && $0.briefingID == point.briefingID) }) else { return }
            out.append(point)
        }
        let close = (daysToNext ?? 99) <= 2
        if close {
            add(CompetitionFocus(id: "sharpen", title: "Sharpen, don't build",
                           detail: "Too close to build anything new. Short and sharp in training, sleep long, eat a proper meal before the {event}.",
                           briefingID: "sleep-before-games", goal: nil))
        }
        for area in last?.toImprove ?? [] {
            switch area {
            case "Focus", "Decisions":
                add(CompetitionFocus(id: "reset", title: "A reset for the next mistake",
                               detail: "Pick a cue word. In two practices before the next {event}, use the breath-out reset after every error.",
                               briefingID: "reset-after-mistakes", goal: "focus"))
            case "Confidence":
                add(CompetitionFocus(id: "evidence", title: "Build evidence, not hope",
                               detail: "Write down three moments from training this week that went well — that's what you stand on when it matters.",
                               briefingID: "confidence-under-pressure", goal: "confidence"))
            case "Speed":
                if !close {
                    add(CompetitionFocus(id: "speed", title: "Speed work while fresh",
                                   detail: "Short, fast efforts at the start of two sessions, with full rest in between. Fast only counts when you're fresh.",
                                   briefingID: "strength-into-speed", goal: "acceleration"))
                }
            case "Strength":
                if !close {
                    add(CompetitionFocus(id: "strength", title: "Keep the strength work",
                                   detail: "Two strength sessions before the next {event}, the last one at least two days out.",
                                   briefingID: nil, goal: "strength"))
                }
            case "Technique":
                add(CompetitionFocus(id: "technique", title: "One skill, focused minutes",
                               detail: "Ten focused minutes on the skill that let you down, after two practices this week — one clear target each time.",
                               briefingID: nil, goal: "sportSkill"))
            case "Effort", "Recovery":
                add(CompetitionFocus(id: "fresh", title: "Arrive fresh",
                               detail: "Protect the three nights before the next {event}, and eat a proper meal three to four hours before it.",
                               briefingID: "fuel-on-game-day", goal: "recovery"))
            case "Communication":
                add(CompetitionFocus(id: "talk", title: team ? "Talk more" : "Plan it with your coach",
                               detail: team ? "Agree one call with your team before the next {event} and use it early."
                                   : "Before the next {event}, agree one clear plan with your coach and say it out loud on the day.",
                               briefingID: nil, goal: nil))
            default:
                break
            }
        }
        for insight in insights {
            switch insight {
            case .sleepBeforeGames:
                add(CompetitionFocus(id: "sleep", title: "Bank sleep before the {event}",
                               detail: "Your twin sees short nights before {events}. Bed 30 minutes earlier on the three nights before.",
                               briefingID: "sleep-before-games", goal: nil))
            case .gameDayFuel:
                add(CompetitionFocus(id: "fuel", title: "Fuel the day",
                               detail: "Your energy dips on {event} days. A proper meal three to four hours out, a small top-up later.",
                               briefingID: "fuel-on-game-day", goal: nil))
            case .recoveryAfterGames:
                add(CompetitionFocus(id: "recover", title: "Recover between {events}",
                               detail: "Light movement the day after, real food within an hour, an early night.",
                               briefingID: "recovery-after-games", goal: nil))
            case .pressureConfidence:
                add(CompetitionFocus(id: "moment", title: "Want the moment",
                               detail: "Practise your pre-performance routine until it runs by itself.",
                               briefingID: "confidence-under-pressure", goal: "confidence"))
            case .mistakeReplay:
                add(CompetitionFocus(id: "reset", title: "A reset for the next mistake",
                               detail: "Breath out, cue word, next job — practise it in training first.",
                               briefingID: "reset-after-mistakes", goal: "focus"))
            case .loadSpike:
                add(CompetitionFocus(id: "load", title: "Keep the week steady",
                               detail: "Your load jumped. Don't cram before the {event} — steady sessions, longer sleep.",
                               briefingID: nil, goal: nil))
            default:
                break
            }
        }
        if out.isEmpty {
            add(CompetitionFocus(id: "routine", title: "Keep what works",
                           detail: "Same sleep, same meal, same warm-up as your best {events}. Consistency is a skill.",
                           briefingID: "sleep-before-games", goal: nil))
        }
        return out
    }

    /// The athlete's chance in words.
    public static func chanceWord(_ chance: Int) -> String {
        switch chance {
        case ..<31: "Underdog"
        case 31..<46: "A tough one"
        case 46..<56: "Even"
        case 56..<76: "Good chance"
        default: "Favourite"
        }
    }

    /// Wins, draws, losses over the results.
    public static func record(_ results: [CompetitionResult]) -> (wins: Int, draws: Int, losses: Int) {
        (results.filter { $0.outcome == .win }.count, results.filter { $0.outcome == .draw }.count, results.filter { $0.outcome == .loss }.count)
    }

    public static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }
}
