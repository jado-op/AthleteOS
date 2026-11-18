import Foundation

/// What is left of §12's coach engine: muscle balance from the sets actually
/// logged, mapped through each item's own muscle weights — the original app
/// idea's "lately you've only trained arms — try core or legs" (Trends, Me).
/// The weekly coach report (headline, findings, template bank) was cut; the
/// twin is the one analyst now.

// MARK: - Inputs

public struct CoachSet: Sendable {
    public let itemSlug: String
    public let reps: Int?
    public let weightKg: Double?

    public init(itemSlug: String, reps: Int? = nil, weightKg: Double? = nil) {
        self.itemSlug = itemSlug
        self.reps = reps
        self.weightKg = weightKg
    }
}

public struct CoachSession: Sendable {
    public let date: Date
    public let minutes: Int
    public let rpe: Int?
    public let sets: [CoachSet]

    public init(date: Date, minutes: Int, rpe: Int?, sets: [CoachSet]) {
        self.date = date
        self.minutes = minutes
        self.rpe = rpe
        self.sets = sets
    }
}

// MARK: - The engine

public enum CoachEngine {
    /// The big regions a balanced programme should touch every fortnight.
    static let majorRegions: [MuscleRegion] = [.chest, .upperBack, .shoulder, .arm, .trunk, .hip, .quadriceps, .hamstrings, .calf]

    // MARK: Muscle balance

    /// Share of logged volume per region over the last 14 days. Each set
    /// contributes its item's muscle weights, so a trap-bar deadlift counts
    /// mostly toward hips and hamstrings, a little toward the back.
    public static func muscleBalance(sessions: [CoachSession], catalogue: Catalogue, now: Date = .now, days: Int = 14) -> [MuscleRegion: Double] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) ?? now
        var totals: [MuscleRegion: Double] = [:]
        for session in sessions where session.date >= cutoff {
            for set in session.sets {
                guard let item = catalogue.item(set.itemSlug) else { continue }
                for (muscle, weight) in item.muscles {
                    guard let region = musclesBySlug[muscle]?.region else { continue }
                    totals[region, default: 0] += weight
                }
            }
        }
        let sum = totals.values.reduce(0, +)
        guard sum > 0 else { return [:] }
        return totals.mapValues { $0 / sum }
    }
}

extension MuscleRegion {
    /// How the coach says it in a sentence: "your quads", "your core".
    var coachName: String {
        switch self {
        case .neck: "neck"
        case .shoulder: "shoulders"
        case .upperBack: "upper back"
        case .chest: "chest"
        case .lowerBack: "lower back"
        case .arm: "arms"
        case .forearm: "forearms"
        case .trunk: "core"
        case .hip: "hips"
        case .quadriceps: "quads"
        case .hamstrings: "hamstrings"
        case .calf: "calves"
        case .foot: "feet"
        }
    }
}
