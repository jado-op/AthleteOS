import Foundation

// The Academy (docs/ACADEMY-PLAN.md): lessons about the athlete's sport in six
// pillars, and the Digital Twin those lessons and reflections build. The
// lessons are data — content/src/academy → Generated/AcademyContent.swift —
// decoded here. Foundation only, so tools/engine-harness.sh can test it.

/// The six things the twin is made of.
public enum TwinPillar: String, Codable, CaseIterable, Identifiable, Sendable {
    case body, fuel, recovery, mind, legends, sportIQ

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .body: "Body"
        case .fuel: "Fuel"
        case .recovery: "Recovery"
        case .mind: "Mind"
        case .legends: "Legends"
        case .sportIQ: "Sport IQ"
        }
    }

    /// What the pillar is about, in a few words.
    public var subtitle: String {
        switch self {
        case .body: "How your muscles work together in your sport"
        case .fuel: "Food and drink that carry training and growth"
        case .recovery: "Sleep and the hours after hard work"
        case .mind: "Focus, resets, confidence and humility"
        case .legends: "How great athletes got better"
        case .sportIQ: "Reading the game before it happens"
        }
    }

    /// How the pillar shows on the twin.
    public var onTheTwin: String {
        switch self {
        case .body: "Your sport's key muscles light up."
        case .fuel: "Your energy aura grows brighter."
        case .recovery: "Your recovery battery charges."
        case .mind: "Your focus glow, and the confidence–humility balance."
        case .legends: "Legend traits orbit your twin."
        case .sportIQ: "Your vision scan widens."
        }
    }

    public var systemImage: String {
        switch self {
        case .body: "figure.run"
        case .fuel: "flame.fill"
        case .recovery: "battery.75percent"
        case .mind: "brain.head.profile"
        case .legends: "star.circle.fill"
        case .sportIQ: "scope"
        }
    }

    /// The one-line reason shown next to the twin when this pillar is the weakest.
    public var weakestReason: String {
        switch self {
        case .body: "Your body map has the most room to grow"
        case .fuel: "Your energy aura is lowest"
        case .recovery: "Your recovery battery is lowest"
        case .mind: "Your focus glow is lowest"
        case .legends: "Your legend traits are just starting"
        case .sportIQ: "Your game vision has the most room to grow"
        }
    }
}

/// Knowledge comes from quiz answers, habits & mindset from self-reflection.
public enum TwinSide: String, Codable, Sendable {
    case knowledge, habits
}

/// What an answer (or finishing a lesson) does to the twin.
public struct TwinEffectSpec: Codable, Hashable, Sendable {
    public var pillar: TwinPillar
    public var side: TwinSide
    public var delta: Int
    /// A body region that glows (RigMuscleRegion raw value), Body only.
    public var area: String?
    /// A legend trait it unlocks.
    public var trait: String?
    /// < 0 leans towards confidence, > 0 towards humility.
    public var ego: Int?

    public init(pillar: TwinPillar, side: TwinSide, delta: Int, area: String? = nil, trait: String? = nil, ego: Int? = nil) {
        self.pillar = pillar
        self.side = side
        self.delta = delta
        self.area = area
        self.trait = trait
        self.ego = ego
    }
}

public struct AcademySection: Codable, Hashable, Sendable {
    public let heading: String
    public let body: String
}

/// How a great athlete did it: habits, thinking, a turning point.
public struct AcademyLegend: Codable, Hashable, Sendable {
    public let athlete: String
    public let title: String
    public let body: String
}

public struct AcademyOption: Codable, Hashable, Sendable {
    public let text: String
    public let correct: Bool
    public let effects: [TwinEffectSpec]
}

public enum AcademyQuestionKind: String, Codable, Sendable {
    /// Scored: one right answer.
    case knowledge
    /// Never right or wrong: how the athlete really does it.
    case reflection
}

public struct AcademyQuestion: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: AcademyQuestionKind
    public let prompt: String
    public let explain: String?
    public let options: [AcademyOption]

    public var correctIndex: Int? { options.firstIndex { $0.correct } }
}

public struct AcademySource: Codable, Hashable, Sendable {
    public let title: String
    public let detail: String
    public let url: String
}

public struct AcademyLesson: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let pillar: TwinPillar
    /// Sport slugs, or ["all"].
    public let sports: [String]
    public let minAge: Int
    public let maxAge: Int
    /// "all", "offSeason", "preSeason", "inSeason", "postSeason".
    public let phases: [String]
    public let requires: [String]
    public let minutes: Int
    /// Mind lessons show "Need to talk to someone?".
    public let support: Bool
    public let sections: [AcademySection]
    public let legend: AcademyLegend?
    public let questions: [AcademyQuestion]
    public let completion: [TwinEffectSpec]
    public let sources: [AcademySource]

    public var isForAllSports: Bool { sports.contains("all") }

    public func fits(sport: String?) -> Bool {
        isForAllSports || sport.map { sports.contains($0) } == true
    }

    public func fits(age: Int?) -> Bool {
        guard let age else { return true }
        return age >= minAge && age <= maxAge
    }

    /// nil: the athlete's phase isn't known (no season set).
    public func phaseMatch(_ phase: SeasonPhase?) -> PhaseMatch {
        if phases.contains("all") { return .anyTime }
        guard let phase else { return .anyTime }
        return phases.contains(AcademyLesson.phaseKey(phase)) ? .thisPhase : .otherPhase
    }

    public enum PhaseMatch: Sendable { case thisPhase, anyTime, otherPhase }

    static func phaseKey(_ phase: SeasonPhase) -> String {
        switch phase {
        case .offSeason: "offSeason"
        case .preSeason: "preSeason"
        case .inSeason: "inSeason"
        case .postSeason: "postSeason"
        }
    }
}

/// Unlocked by Legends lessons; rings around the twin.
public struct LegendTrait: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
}

public struct AcademyContentPack: Codable, Sendable {
    public let lessons: [AcademyLesson]
    /// Sport slug (or "default") → the body regions that matter most, in order.
    public let sportAreas: [String: [String]]
    public let traits: [LegendTrait]

    public static let empty = AcademyContentPack(lessons: [], sportAreas: [:], traits: [])
}

public enum AcademyContent {
    public static let pack: AcademyContentPack = decode(academyContentJSON) ?? .empty

    public static func decode(_ json: String) -> AcademyContentPack? {
        try? JSONDecoder().decode(AcademyContentPack.self, from: Data(json.utf8))
    }

    public static var lessons: [AcademyLesson] { pack.lessons }

    public static func lesson(_ id: String) -> AcademyLesson? {
        pack.lessons.first { $0.id == id }
    }

    public static func trait(_ id: String) -> LegendTrait? {
        pack.traits.first { $0.id == id }
    }

    /// The body regions the twin lights up first for this sport.
    public static func areas(forSport slug: String?, pack: AcademyContentPack = AcademyContent.pack) -> [String] {
        slug.flatMap { pack.sportAreas[$0] } ?? pack.sportAreas["default"] ?? []
    }
}

// MARK: - The twin's own data

/// How the twin looks — chosen when it is born, changeable later.
public struct TwinAppearance: Codable, Hashable, Sendable {
    public enum Build: String, Codable, CaseIterable, Sendable {
        case lean, athletic, strong

        public var title: String {
            switch self {
            case .lean: "Lean"
            case .athletic: "Athletic"
            case .strong: "Strong"
            }
        }

        /// Horizontal scale of the figure.
        public var width: Double {
            switch self {
            case .lean: 0.92
            case .athletic: 1
            case .strong: 1.09
            }
        }
    }

    public var build: Build
    /// Hex colours.
    public var skin: String
    public var hair: String
    public var kit: String
    public var kitSecondary: String

    public init(build: Build = .athletic, skin: String = TwinAppearance.skinTones[2], hair: String = TwinAppearance.hairColours[0],
                kit: String = TwinAppearance.kitColours[0], kitSecondary: String = TwinAppearance.kitColours[1]) {
        self.build = build
        self.skin = skin
        self.hair = hair
        self.kit = kit
        self.kitSecondary = kitSecondary
    }

    public static let skinTones = ["#F3D2B3", "#E5B48C", "#C99167", "#A26C45", "#7A4B2C", "#4E2F1C"]
    public static let hairColours = ["#1E1712", "#4A3222", "#8A5A35", "#C9A16B", "#9A2F1E", "#D8D8DC"]
    public static let kitColours = ["#6D28D9", "#2A2E38", "#1D4ED8", "#B91C1C", "#047857", "#F8FAFC", "#F59E0B", "#111827"]

    public static let standard = TwinAppearance()
}

/// One change to the twin. The twin's scores are always worked out from the
/// list of these (TwinScoring), never stored, so they can't drift and
/// "before vs now" is the list cut at a date.
public struct TwinEffect: Codable, Hashable, Sendable {
    public var date: Date
    /// "lesson:<id>", "lesson:<id>/<question>", "reflection:<day>", "baseline".
    public var source: String
    public var pillar: TwinPillar
    public var side: TwinSide
    public var delta: Int
    public var area: String?
    public var trait: String?
    public var ego: Int?

    public init(date: Date, source: String, spec: TwinEffectSpec) {
        self.date = date
        self.source = source
        pillar = spec.pillar
        side = spec.side
        delta = spec.delta
        area = spec.area
        trait = spec.trait
        ego = spec.ego
    }
}

/// Everything the Academy keeps for the athlete. Private to them.
public struct AcademyState: Codable, Equatable, Sendable {
    public var version = 1
    /// nil until the twin is born.
    public var appearance: TwinAppearance?
    public var bornAt: Date?
    /// Pillars the athlete wants to grow first.
    public var goals: [TwinPillar] = []
    public var ledger: [TwinEffect] = []
    /// Finished lessons and when.
    public var completed: [String: Date] = [:]

    public init() {}

    public var completedIDs: Set<String> { Set(completed.keys) }
    public var look: TwinAppearance { appearance ?? .standard }
}

/// Names for the body regions the twin can light up.
public enum TwinBodyAreas {
    public static func name(_ area: String) -> String {
        switch area {
        case "thighFront": "Quads"
        case "thighBack": "Hamstrings"
        case "thigh": "Adductors"
        case "shinFront": "Shins"
        case "shinBack": "Calves"
        case "chest": "Chest"
        case "abs": "Core"
        case "upperBack": "Upper back"
        case "lowerBack": "Lower back"
        case "glutes": "Glutes"
        case "shoulderCap": "Shoulders"
        case "upperArmFront": "Biceps"
        case "upperArmBack": "Triceps"
        case "forearm": "Forearms"
        case "neck": "Neck"
        case "foot": "Feet"
        default: "Body"
        }
    }
}
