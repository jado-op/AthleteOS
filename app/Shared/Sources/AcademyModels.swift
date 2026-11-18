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
    /// Things that are working — no briefing needed.
    case consistentTraining, sleepBase, strengthRising
}

public struct BriefingBlock: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case p, h, quote, example, yourData, `protocol`
    }

    public let kind: Kind
    public let text: String?
    public let title: String?
    public let key: String?
    public let steps: [String]?
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

    /// `why` with the athlete's own numbers, or nil when one is missing.
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
    public let placeholder: String?
    public let options: [Option]
}

public struct AcademyContentPack: Codable, Sendable {
    public let briefings: [Briefing]
    public let intake: [IntakeQuestion]

    public static let empty = AcademyContentPack(briefings: [], intake: [])
}

public enum AcademyContent {
    public static let pack: AcademyContentPack = decode(academyContentJSON) ?? .empty

    public static func decode(_ json: String) -> AcademyContentPack? {
        try? JSONDecoder().decode(AcademyContentPack.self, from: Data(json.utf8))
    }

    public static var briefings: [Briefing] { pack.briefings }
    public static var intake: [IntakeQuestion] { pack.intake }

    public static func briefing(_ id: String) -> Briefing? { pack.briefings.first { $0.id == id } }

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

    public init() {}
}
