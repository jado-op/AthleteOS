import Foundation

/// Who is learning: what the Academy's recommendations are fitted to.
public struct AcademyLearner: Sendable {
    public var sportSlug: String?
    public var sportName: String?
    public var age: Int?
    public var phase: SeasonPhase?
    public var goals: [TwinPillar]
    public var completed: Set<String>

    public init(sportSlug: String? = nil, sportName: String? = nil, age: Int? = nil, phase: SeasonPhase? = nil,
                goals: [TwinPillar] = [], completed: Set<String> = []) {
        self.sportSlug = sportSlug
        self.sportName = sportName
        self.age = age
        self.phase = phase
        self.goals = goals
        self.completed = completed
    }
}

public struct AcademyRecommendation: Equatable, Sendable, Identifiable {
    public let lesson: AcademyLesson
    /// One line shown next to the twin ("Your recovery battery is lowest").
    public let reason: String
    public let score: Double
    public var id: String { lesson.id }
}

/// Rule-based: what to learn next, in this order of weight — the twin's
/// weakest dimension, the athlete's goals, their sport, the season phase.
/// Only lessons not done yet whose prerequisites are done.
public enum AcademyRecommender {
    public enum Weight {
        public static let weakness = 3.0
        public static let goal = 1.5
        public static let ownSport = 1.0
        public static let allSports = 0.3
        public static let thisPhase = 0.6
        public static let anyTime = 0.2
        public static let otherPhase = -0.8
    }

    /// Lessons the athlete can take now.
    public static func available(_ lessons: [AcademyLesson], for learner: AcademyLearner) -> [AcademyLesson] {
        lessons.filter { lesson in
            !learner.completed.contains(lesson.id)
                && lesson.requires.allSatisfy { learner.completed.contains($0) }
                && lesson.fits(sport: learner.sportSlug)
                && lesson.fits(age: learner.age)
        }
    }

    public static func score(_ lesson: AcademyLesson, snapshot: TwinSnapshot, learner: AcademyLearner) -> Double {
        let weakness = Double(TwinScoring.maximum - snapshot.score(lesson.pillar).total) / Double(TwinScoring.maximum)
        var total = Weight.weakness * weakness
        if learner.goals.contains(lesson.pillar) { total += Weight.goal }
        total += lesson.isForAllSports ? Weight.allSports : Weight.ownSport
        switch lesson.phaseMatch(learner.phase) {
        case .thisPhase: total += Weight.thisPhase
        case .anyTime: total += Weight.anyTime
        case .otherPhase: total += Weight.otherPhase
        }
        return total
    }

    /// The top lessons, at most two from one pillar so the list isn't one-note.
    public static func recommend(_ lessons: [AcademyLesson], snapshot: TwinSnapshot, learner: AcademyLearner,
                                 limit: Int = 3) -> [AcademyRecommendation] {
        let ranked = available(lessons, for: learner).enumerated()
            .map { (index: $0.offset, lesson: $0.element, score: score($0.element, snapshot: snapshot, learner: learner)) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
        var picked: [AcademyRecommendation] = []
        var perPillar: [TwinPillar: Int] = [:]
        for entry in ranked where picked.count < limit {
            guard perPillar[entry.lesson.pillar, default: 0] < 2 else { continue }
            perPillar[entry.lesson.pillar, default: 0] += 1
            picked.append(AcademyRecommendation(lesson: entry.lesson, reason: reason(entry.lesson, snapshot: snapshot, learner: learner),
                                                score: entry.score))
        }
        return picked
    }

    /// The single strongest reason, as one line.
    public static func reason(_ lesson: AcademyLesson, snapshot: TwinSnapshot, learner: AcademyLearner) -> String {
        if lesson.pillar == snapshot.weakest { return lesson.pillar.weakestReason }
        if learner.goals.contains(lesson.pillar) { return "You chose \(lesson.pillar.title) as a goal" }
        if !lesson.isForAllSports, let name = learner.sportName { return "Made for \(name)" }
        if lesson.phaseMatch(learner.phase) == .thisPhase, let phase = learner.phase { return "Fits your \(phaseName(phase))" }
        return "Builds your \(lesson.pillar.title.lowercased())"
    }

    /// The best next lesson for one pillar (the area sheet's "next lesson").
    public static func next(for pillar: TwinPillar, _ lessons: [AcademyLesson], snapshot: TwinSnapshot,
                            learner: AcademyLearner) -> AcademyLesson? {
        available(lessons, for: learner)
            .filter { $0.pillar == pillar }
            .max { score($0, snapshot: snapshot, learner: learner) < score($1, snapshot: snapshot, learner: learner) }
    }

    static func phaseName(_ phase: SeasonPhase) -> String {
        switch phase {
        case .offSeason: "off-season"
        case .preSeason: "pre-season"
        case .inSeason: "season"
        case .postSeason: "post-season"
        }
    }
}
