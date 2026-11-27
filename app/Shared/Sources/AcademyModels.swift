import Foundation

// The Academy (docs/ACADEMY-PLAN.md, v3): the Digital Twin is an analysis of
// the athlete — built from their own check-ins, training, games, tests,
// reflections and an intake interview. It finds insights; the coach assigns
// a briefing (a long read) for each. The briefings and the interview are data
// (content/src/academy → Generated/AcademyContent.swift), decoded here.
// Foundation only, so tools/engine-harness.sh can test it.

/// What a briefing is about.
public enum BriefingTopic: String, Codable, CaseIterable, Sendable {
    case recovery, strength, mind, fuel

    public var title: String {
        switch self {
        case .recovery: "Recovery"
        case .strength: "Strength & speed"
        case .mind: "Mindset"
        case .fuel: "Fuel"
        }
    }
}

/// The insights the twin can find. Each has a briefing that answers it.
public enum TwinInsightKind: String, Codable, CaseIterable, Sendable {
    case sleepBeforeGames, recoveryAfterGames, gameDayFuel, strengthNotSpeed, mistakeReplay, pressureConfidence
    /// Patterns the coach explains without a briefing (yet).
    case loadSpike, irregularSleep, sleepAffectsPractice, stressAndSleep
    /// Things that are working — no briefing needed.
    case consistentTraining, sleepBase, strengthRising
}

public struct BriefingBlock: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case p, h, quote, example, yourData, `protocol`
    }

    public struct Variant: Codable, Hashable, Sendable {
        public let title: String?
        public let text: String
    }

    public let kind: Kind
    public let text: String?
    public let title: String?
    public let key: String?
    public let steps: [String]?
    /// The same paragraph or example for another sport family.
    public let variants: [String: Variant]?

    /// The block as an athlete of this sport family reads it.
    public func resolved(for family: String) -> (title: String?, text: String?) {
        if let variant = variants?[family] { return (variant.title ?? title, variant.text) }
        return (title, text)
    }
}

public struct BriefingChapter: Codable, Hashable, Sendable {
    public let title: String
    public let blocks: [BriefingBlock]
}

public struct BriefingSource: Codable, Hashable, Sendable {
    public let title: String
    public let detail: String
    public let url: String
}

/// A long read for athletes who want the real thing.
public struct Briefing: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let topic: BriefingTopic
    public let title: String
    public let dek: String
    /// The insight that makes the coach assign it.
    public let insight: TwinInsightKind
    /// "Why your coach gave you this", with {placeholders} the insight fills.
    public let why: String
    public let minutes: Int
    public let chapters: [BriefingChapter]
    public let sources: [BriefingSource]

    /// `why` with the athlete's own numbers and words, or nil when one is missing.
    public func why(filling values: [String: String]) -> String? {
        var out = why
        for (key, value) in values { out = out.replacingOccurrences(of: "{\(key)}", with: value) }
        return out.contains("{") ? nil : out
    }
}

/// One question of the intake interview — about the athlete, never right or wrong.
public struct IntakeQuestion: Codable, Hashable, Sendable, Identifiable {
    public struct Option: Codable, Hashable, Sendable, Identifiable {
        public let id: String
        public let text: String
        /// How the answer reads under "Who you are as an athlete".
        public let summary: String
    }

    public let id: String
    /// "Under pressure"
    public let label: String
    public let prompt: String
    public let freeText: Bool
    /// Only asked in team sports.
    public let teamOnly: Bool
    public let placeholder: String?
    public let options: [Option]
}

/// How a family of sports talks: a tennis player plays matches, a swimmer races.
public struct SportFamily: Codable, Hashable, Sendable {
    public let event: String
    public let events: String
    public let team: Bool
    /// Speed decides (the strength-into-speed insight runs).
    public let speed: Bool

    public static let general = SportFamily(event: "game", events: "games", team: true, speed: true)

    /// {event}, {events}, {Event}, {Events} in the athlete's own words.
    public var tokens: [String: String] {
        ["event": event, "events": events, "Event": event.prefix(1).uppercased() + event.dropFirst(),
         "Events": events.prefix(1).uppercased() + events.dropFirst()]
    }

    public func fill(_ text: String) -> String {
        var out = text
        for (key, value) in tokens { out = out.replacingOccurrences(of: "{\(key)}", with: value) }
        return out
    }
}

public struct AcademyContentPack: Codable, Sendable {
    public let briefings: [Briefing]
    public let intake: [IntakeQuestion]
    public let families: [String: SportFamily]
    /// Sport slug → family id.
    public let sportFamilies: [String: String]
    public let defaultFamily: String

    public static let empty = AcademyContentPack(briefings: [], intake: [], families: [:], sportFamilies: [:], defaultFamily: "field")
}

public enum AcademyContent {
    public static let pack: AcademyContentPack = decode(academyContentJSON) ?? .empty

    public static func decode(_ json: String) -> AcademyContentPack? {
        try? JSONDecoder().decode(AcademyContentPack.self, from: Data(json.utf8))
    }

    public static var briefings: [Briefing] { pack.briefings }
    public static var intake: [IntakeQuestion] { pack.intake }

    public static func briefing(_ id: String) -> Briefing? { pack.briefings.first { $0.id == id } }

    /// The sport family id for a sport ("racket" for tennis).
    public static func familyID(forSport slug: String?, pack: AcademyContentPack = AcademyContent.pack) -> String {
        slug.flatMap { pack.sportFamilies[$0] } ?? pack.defaultFamily
    }

    public static func family(forSport slug: String?, pack: AcademyContentPack = AcademyContent.pack) -> SportFamily {
        pack.families[familyID(forSport: slug, pack: pack)] ?? .general
    }

    /// The interview for this sport: team-only questions left out, words filled in.
    public static func intake(forSport slug: String?) -> [IntakeQuestion] {
        let family = family(forSport: slug)
        return pack.intake.filter { family.team || !$0.teamOnly }
    }

    public static func briefing(for insight: TwinInsightKind) -> Briefing? { pack.briefings.first { $0.insight == insight } }
}

// MARK: - The athlete's own Academy data

/// A performance the athlete tracks by hand (anything the app doesn't log itself).
public struct CustomPerformance: Codable, Hashable, Sendable, Identifiable {
    public struct Entry: Codable, Hashable, Sendable {
        public var date: Date
        public var value: Double

        public init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    public var id: String
    public var name: String
    /// "kg", "s", "cm", "m", "reps", "level" or anything the athlete types.
    public var unit: String
    public var higherIsBetter: Bool
    public var entries: [Entry]

    public init(id: String = UUID().uuidString, name: String, unit: String, higherIsBetter: Bool, entries: [Entry]) {
        self.id = id
        self.name = name
        self.unit = unit
        self.higherIsBetter = higherIsBetter
        self.entries = entries
    }
}

/// Everything the Academy keeps for the athlete. Private to them.
public struct AcademyState: Codable, Equatable, Sendable {
    public var version = 3
    /// Intake answers: question id → option id, or the athlete's own words.
    public var intake: [String: String] = [:]
    public var intakeDoneAt: Date?
    /// Briefings read to the end, and when.
    public var read: [String: Date] = [:]
    public var performances: [CustomPerformance] = []
    /// A first interview left half-way: the answers so far and where to pick
    /// up. The twin is only "born" (intakeDoneAt) once the interview is done.
    public var intakeDraft: IntakeDraft?
    /// "What I know about you" lines the athlete said weren't right (T13),
    /// and when. Optional so older saved states still decode.
    public var knowledgeHidden: [String: Date]?
    /// When each line was first known: the monthly letter's "what I learned".
    public var knowledgeFirstSeen: [String: Date]?
    /// The month ("2026-11") whose letter the athlete closed.
    public var letterClosed: String?

    public init() {}
}

/// The interview so far, kept when the athlete closes it before the end.
public struct IntakeDraft: Codable, Equatable, Sendable {
    public var answers: [String: String]
    /// The question to open on next time.
    public var questionID: String?
    public var savedAt: Date

    public init(answers: [String: String], questionID: String?, savedAt: Date) {
        self.answers = answers
        self.questionID = questionID
        self.savedAt = savedAt
    }
}
