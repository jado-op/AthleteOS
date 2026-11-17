import Foundation

/// One pillar's two sides, 0–100 each.
public struct TwinPillarScore: Equatable, Sendable {
    /// From quiz answers.
    public var knowledge: Int
    /// From self-reflection.
    public var habits: Int

    public init(knowledge: Int = 0, habits: Int = 0) {
        self.knowledge = knowledge
        self.habits = habits
    }

    /// The pillar's score: both sides count the same.
    public var total: Int { Int((Double(knowledge + habits) / 2).rounded()) }
}

/// The twin at one moment.
public struct TwinSnapshot: Equatable, Sendable {
    public var pillars: [TwinPillar: TwinPillarScore]
    /// Body region (RigMuscleRegion raw value) → glow 0…1.
    public var bodyAreas: [String: Double]
    /// Unlocked legend traits, in the order they were earned.
    public var traits: [String]
    /// −1 leans to confidence, +1 to humility, 0 balanced.
    public var egoBalance: Double

    public func score(_ pillar: TwinPillar) -> TwinPillarScore { pillars[pillar] ?? TwinPillarScore() }

    /// The pillar with the lowest score (ties: the order of TwinPillar.allCases).
    public var weakest: TwinPillar {
        TwinPillar.allCases.min { score($0).total < score($1).total } ?? .body
    }

    /// The whole twin, 0–100.
    public var overall: Int {
        Int((Double(TwinPillar.allCases.map { score($0).total }.reduce(0, +)) / Double(TwinPillar.allCases.count)).rounded())
    }
}

/// How one pillar changed.
public struct TwinDelta: Equatable, Sendable, Identifiable {
    public let pillar: TwinPillar
    public let change: Int
    public var id: TwinPillar { pillar }
}

/// Works the twin out of its effects. Pure, so the same list always gives
/// the same twin (and tests can check it).
public enum TwinScoring {
    public static let maximum = 100

    public static func snapshot(_ ledger: [TwinEffect], sportAreas: [String], until: Date? = nil) -> TwinSnapshot {
        let effects = until.map { cut in ledger.filter { $0.date <= cut } } ?? ledger
        var raw: [TwinPillar: (knowledge: Int, habits: Int)] = [:]
        var areaPoints: [String: Int] = [:]
        var traits: [String] = []
        var ego = 0
        for effect in effects {
            var sides = raw[effect.pillar] ?? (0, 0)
            switch effect.side {
            case .knowledge: sides.knowledge += effect.delta
            case .habits: sides.habits += effect.delta
            }
            raw[effect.pillar] = sides
            if let area = effect.area, effect.pillar == .body { areaPoints[area, default: 0] += effect.delta }
            if let trait = effect.trait, !traits.contains(trait) { traits.append(trait) }
            if let lean = effect.ego { ego += lean }
        }
        var pillars: [TwinPillar: TwinPillarScore] = [:]
        for pillar in TwinPillar.allCases {
            let sides = raw[pillar] ?? (0, 0)
            pillars[pillar] = TwinPillarScore(knowledge: clamp(sides.knowledge), habits: clamp(sides.habits))
        }
        let body = Double(pillars[.body]?.total ?? 0)
        var areas: [String: Double] = [:]
        // The sport's key muscles light up as Body grows, the first ones
        // first; a region a lesson was about glows on top of that.
        for (index, area) in sportAreas.enumerated() {
            let order = max(0.4, 1 - Double(index) * 0.12)
            areas[area] = min(1, body / 60 * order)
        }
        for (area, points) in areaPoints {
            areas[area] = min(1, (areas[area] ?? 0) + Double(points) / 25)
        }
        return TwinSnapshot(pillars: pillars, bodyAreas: areas.filter { $0.value > 0 }, traits: traits,
                            egoBalance: max(-1, min(1, Double(ego) / 6)))
    }

    /// The pillars that changed between two moments, biggest first.
    public static func deltas(from before: TwinSnapshot, to after: TwinSnapshot) -> [TwinDelta] {
        TwinPillar.allCases
            .map { TwinDelta(pillar: $0, change: after.score($0).total - before.score($0).total) }
            .filter { $0.change != 0 }
            .sorted { abs($0.change) > abs($1.change) }
    }

    /// The level-up line on a lesson's end screen ("+6 Recovery — your battery is charging").
    public static func line(for delta: TwinDelta) -> String {
        let sign = delta.change > 0 ? "+" : "−"
        let what: String
        switch delta.pillar {
        case .body: what = "your body map is lighting up"
        case .fuel: what = "your energy aura is brighter"
        case .recovery: what = "your battery is charging"
        case .mind: what = "your focus is sharper"
        case .legends: what = "your legend rings are growing"
        case .sportIQ: what = "your vision is widening"
        }
        return "\(sign)\(abs(delta.change)) \(delta.pillar.title) — \(what)"
    }

    static func clamp(_ points: Int) -> Int { max(0, min(maximum, points)) }
}
