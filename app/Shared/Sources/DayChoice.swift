import Foundation

/// What the athlete says today holds — answered in the morning check-in
/// ("What's on today?") or changed later from Home. The athlete decides; the
/// choice wins over the practice schedule for that day. Safety (pain,
/// illness, a head knock, readiness, a game tomorrow) still shapes the session.
public enum DayChoice: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Team practice today.
    case practice
    /// The athlete's own gym session.
    case gym
    /// A game or competition today.
    case game
    /// Something light: mobility and recovery, nothing that tires.
    case light
    /// A rest day.
    case rest
    /// "Let AthleteOS decide": the schedule and the engine, as usual.
    case auto

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .practice: "Team practice"
        case .gym: "Gym · my own session"
        case .game: "Game"
        case .light: "Something light"
        case .rest: "Rest day"
        case .auto: "Let AthleteOS decide"
        }
    }

    /// For "Today: gym" and "You said: …".
    public var shortTitle: String {
        switch self {
        case .practice: "practice"
        case .gym: "gym"
        case .game: "game"
        case .light: "something light"
        case .rest: "rest"
        case .auto: "your plan"
        }
    }

    public var systemImage: String {
        switch self {
        case .practice: "sportscourt.fill"
        case .gym: "dumbbell.fill"
        case .game: "trophy.fill"
        case .light: "figure.cooldown"
        case .rest: "bed.double.fill"
        case .auto: "sparkles"
        }
    }

    /// Choices that stand alone: picking one clears the others.
    public var standsAlone: Bool { self == .rest || self == .auto }

    /// The order choices are shown and said in.
    public static let order: [DayChoice] = [.practice, .gym, .game, .light, .rest, .auto]
}

extension PracticeIntensity {
    /// How hard today's team practice is, as the athlete says it.
    public var choiceTitle: String {
        switch self {
        case .light: "Short / easy"
        case .normal: "Normal"
        case .hard: "Hard"
        }
    }

    public static let choices: [PracticeIntensity] = [.light, .normal, .hard]
}

/// One day's answer: what's on, and how hard practice is when there is one.
public struct DayAnswer: Codable, Sendable, Equatable {
    public var choices: Set<DayChoice>
    /// Only with team practice (nil: not said).
    public var practice: PracticeIntensity?

    public init(choices: Set<DayChoice>, practice: PracticeIntensity? = nil) {
        self.choices = choices
        self.practice = choices.contains(.practice) ? practice : nil
    }

    /// "Let AthleteOS decide" (or nothing picked): the schedule decides.
    public var isAuto: Bool { choices.isEmpty || choices.contains(.auto) }

    /// What the engine reads (empty: decide as usual).
    public var engineChoices: Set<DayChoice> { isAuto ? [] : choices }

    /// The choices in display order.
    public var ordered: [DayChoice] { DayChoice.order.filter(choices.contains) }

    /// "gym", "practice + gym".
    public var label: String { ordered.map(\.shortTitle).joined(separator: " + ") }

    /// Tapping a choice: rest and "let AthleteOS decide" stand alone; the
    /// others combine (practice and gym, a game and something light).
    public func toggling(_ choice: DayChoice) -> DayAnswer {
        var next = choices
        if choice.standsAlone {
            next = [choice]
        } else {
            next.subtract(DayChoice.allCases.filter(\.standsAlone))
            if next.contains(choice) { next.remove(choice) } else { next.insert(choice) }
        }
        return DayAnswer(choices: next, practice: next.contains(.practice) ? (practice ?? .normal) : nil)
    }

    /// The one-tap starting point: what the schedule and the games already say.
    public static func suggested(practiceScheduled: Bool, gameScheduled: Bool) -> DayAnswer {
        var choices: Set<DayChoice> = []
        if practiceScheduled { choices.insert(.practice) }
        if gameScheduled { choices.insert(.game) }
        return choices.isEmpty ? DayAnswer(choices: [.auto]) : DayAnswer(choices: choices, practice: practiceScheduled ? .normal : nil)
    }

    // MARK: Stored form ("practice,gym;3")

    public var encoded: String {
        let list = ordered.map(\.rawValue).joined(separator: ",")
        return practice.map { "\(list);\($0.rawValue)" } ?? list
    }

    public init?(encoded: String) {
        let halves = encoded.split(separator: ";", omittingEmptySubsequences: false)
        guard let first = halves.first else { return nil }
        let choices = Set(first.split(separator: ",").compactMap { DayChoice(rawValue: String($0)) })
        guard !choices.isEmpty else { return nil }
        let practice = halves.count > 1 ? Int(halves[1]).flatMap(PracticeIntensity.init(rawValue:)) : nil
        self.init(choices: choices, practice: practice)
    }
}
