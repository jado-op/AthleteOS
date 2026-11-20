import Foundation

/// A workout another app or device wrote to Apple Health (owner, 2026-11-20):
/// it counts as the day's training straight away, and the next time the
/// athlete opens the app they say how hard it was and what it trained.
///
/// Evidence (docs/WORKOUT-CHECK-RESEARCH.md):
/// - Session effort on Foster's CR-10 × minutes is the validated load
///   measure, in adolescents too; recalled up to 24 h later it stays valid
///   (Scantlebury 2018: r = 0.98), a recall after 72 h does not.
/// - Rating regions separately (differential RPE: legs vs upper body) adds
///   information (McLaren 2015, 2017), so it is offered, never required, on
///   three words instead of 0–10.
/// - Recovery by region and effort: hard sets cost 24–48 h, hard or
///   eccentric leg work up to 72 h (Morán-Navarro 2017).
public enum WorkoutTagging {
    /// What kind of workout Health says it was.
    public enum Kind: String, Codable, Sendable {
        case strength, cardio, sport, light
    }

    public static func kind(ofActivity activity: String) -> Kind {
        switch activity {
        case "Strength training", "Core", "HIIT", "Cross training": .strength
        case "Run", "Ride", "Swim", "Row", "Elliptical", "Stairs", "Jump rope", "Hike", "Cross-country ski", "Climb": .cardio
        case "Walk", "Yoga", "Pilates", "Mobility", "Golf", "Workout": .light
        default: .sport
        }
    }

    /// Whether it is the day's training: a short walk or a stretch isn't.
    public static func countsAsTraining(activity: String, minutes: Int) -> Bool {
        switch kind(ofActivity: activity) {
        case .light: minutes >= 45
        default: minutes >= 15
        }
    }

    /// What it probably trained, ticked before the athlete answers.
    public static func guessedRegions(activity: String) -> Set<GymRegion> {
        switch activity {
        case "Swim", "Row", "Cross-country ski", "Climb": [.upper, .lower]
        case "Core": [.core]
        default:
            switch kind(ofActivity: activity) {
            case .cardio, .sport: [.lower]
            case .strength, .light: []
            }
        }
    }

    /// Foster's CR-10 with its validated words (0–10; the gaps have none).
    public static let scale: [(value: Int, word: String?)] = [
        (0, "Rest"), (1, "Very, very easy"), (2, "Easy"), (3, "Moderate"), (4, "Somewhat hard"), (5, "Hard"),
        (6, nil), (7, "Very hard"), (8, nil), (9, nil), (10, "Maximal"),
    ]

    /// The nearest word at or below a rating ("Hard" for 6).
    public static func word(_ rating: Int) -> String {
        scale.filter { $0.value <= rating }.last { $0.word != nil }?.word ?? "Rest"
    }

    /// How hard one part of the body worked, in three words.
    public enum Band: String, Codable, Sendable, CaseIterable, Comparable {
        case light, solid, veryHard

        public var title: String {
            switch self {
            case .light: "Light"
            case .solid: "Solid"
            case .veryHard: "Very hard"
            }
        }

        public static func < (lhs: Band, rhs: Band) -> Bool { lhs.order < rhs.order }
        private var order: Int { Band.allCases.firstIndex(of: self) ?? 0 }

        var harder: Band { self == .light ? .solid : .veryHard }
        var easier: Band { self == .veryHard ? .solid : .light }
    }

    /// The band an overall rating stands for: 0–3 light, 4–6 solid, 7–10 very hard.
    public static func band(forRating rating: Int) -> Band {
        rating <= 3 ? .light : rating <= 6 ? .solid : .veryHard
    }

    /// The athlete's answer for one workout.
    public struct Answer: Codable, Sendable, Equatable {
        /// Overall effort, 0–10 (nil: skipped).
        public var rating: Int?
        /// Region → band (stored by raw values so the JSON stays a plain object).
        public var regions: [String: String]
        /// "Mostly running or cardio": legs, one band easier unless it was very hard.
        public var cardio: Bool
        /// "Anything hurt?" (nil: not asked or skipped).
        public var hurt: Bool?
        /// Exercises picked instead of (or as well as) regions.
        public var exercises: [String]

        public init(rating: Int? = nil, regions: [GymRegion: Band] = [:], cardio: Bool = false, hurt: Bool? = nil,
                    exercises: [String] = []) {
            self.rating = rating
            self.regions = Dictionary(uniqueKeysWithValues: regions.map { ($0.key.rawValue, $0.value.rawValue) })
            self.cardio = cardio
            self.hurt = hurt
            self.exercises = exercises
        }

        public var bands: [GymRegion: Band] {
            Dictionary(uniqueKeysWithValues: regions.compactMap { key, value in
                GymRegion(rawValue: key).flatMap { region in Band(rawValue: value).map { (region, $0) } }
            })
        }
    }

    /// The bands the planner uses: the athlete's per-region words, otherwise
    /// the overall rating's band for every region they ticked; cardio means
    /// legs one band easier unless the whole thing was very hard; long
    /// sessions (over 90 min) and anything that hurt count one band harder.
    public static func effectiveBands(_ answer: Answer, minutes: Int) -> [GymRegion: Band] {
        let overall = answer.rating.map(band(forRating:)) ?? .solid
        var bands = answer.bands
        if answer.cardio, bands[.lower] == nil {
            bands[.lower] = (answer.rating ?? 0) >= 7 ? .veryHard : overall.easier
        }
        if minutes > 90 || answer.hurt == true {
            bands = bands.mapValues { $0.harder }
        }
        return bands
    }

    /// Days a region wants before its next hard session after this band
    /// (legs 24 / 48 / 72 h, upper body 24 / 48 / 48 h, core 0 / 24 / 48 h).
    public static func recoveryDays(_ region: GymRegion, after band: Band) -> Int {
        switch (region, band) {
        case (.lower, .light), (.upper, .light): 1
        case (.lower, .solid), (.upper, .solid), (.upper, .veryHard): 2
        case (.lower, .veryHard): 3
        case (.core, .light): 0
        case (.core, .solid): 1
        case (.core, .veryHard): 2
        }
    }

    /// Ask only on the day of the workout or the day after: a recall after
    /// 24 h is no longer trustworthy.
    public static func stillAskable(workoutEnd: Date, now: Date) -> Bool {
        now.timeIntervalSince(workoutEnd) <= 24 * 3600 && now >= workoutEnd
    }
}
