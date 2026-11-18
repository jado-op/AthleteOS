import XCTest
#if canImport(Engine)
@testable import Engine
#endif

/// The evidence-based rules of docs/TRAINING-RESEARCH.md ("Rules the engine
/// now follows"), checked against the real content packs.
final class TrainingRulesTests: XCTestCase {
    private static let catalogue: Catalogue = {
        let dist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "content/dist")
        let fallback = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AOS_CONTENT_DIST"] ?? "/root/fitness/content/dist")
        return CatalogueLoader.load(from: FileManager.default.fileExists(atPath: dist.path) ? dist : fallback)
    }()

    private let fullGym: Set<String> = ["dumbbell", "barbell", "rack", "bench", "pull-up-bar", "band", "box", "med-ball", "wall", "cones",
                                        "kettlebell", "weight-plate", "trap-bar", "low-bar", "step", "mini-band", "slider", "cable-machine",
                                        "lat-pulldown", "foam-roller", "jump-rope", "bumper-plates", "landmine", "hurdle", "ball", "stick", "partner"]
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    private func day(_ sport: String, phase: SeasonPhase, age: Int = 16, experience: TrainingExperience = .intermediate,
                     practice: PracticeIntensity? = nil, nextGame: Int? = nil, readiness: ReadinessLevel = .normal,
                     gymDay: Bool = true, goals: [Capacity] = []) -> TrainingDay {
        TrainingDay(date: date, phase: phase, age: age, experience: experience,
                    demands: SportDemandsTable.demands(sport: Self.catalogue.sportsBySlug[sport], position: nil),
                    goals: goals, practice: practice, daysToNextGame: nextGame, readiness: readiness, plannedGymDay: gymDay)
    }

    private func build(_ day: TrainingDay, sport: String, requested: SessionType? = nil, contacts: Int = 100) -> GeneratedSession {
        let decision = SessionPlanner.decide(day, requested: requested)
        let kit = AthleteKit(catalogue: Self.catalogue, sport: Self.catalogue.sportsBySlug[sport], equipment: fullGym,
                             contactsLeft: contacts, seed: "rules")
        return SessionBuilder.build(decision, day: day, kit: kit)
    }

    private func profile(_ item: GeneratedPlannedItem) -> ExerciseProfile? { Self.catalogue.item(item.itemSlug)?.planProfile }

    private func landings(_ session: GeneratedSession) -> Int {
        session.items.reduce(0) { total, item in
            if item.dose.kind == plyometricDoseKind { return total + item.dose.sets * (item.dose.contacts ?? 0) }
            if profile(item)?.group.hasPrefix("jump") == true, item.dose.kind == "reps" { return total + item.dose.sets * (item.dose.reps ?? 0) }
            return total
        }
    }

    // B: every item ships what it trains, and the muscle words resolve to the body map.
    func testEveryItemSaysWhatItTrains() {
        for item in Self.catalogue.itemsBySlug.values {
            let p = item.planProfile
            XCTAssertNotNil(p.quality.flatMap(TrainingQuality.init(rawValue:)), "\(item.slug): quality \(p.quality ?? "nil")")
            XCTAssertFalse(p.primaryMuscles.isEmpty, "\(item.slug): primary muscles")
        }
        let squat = Self.catalogue.item("barbell-back-squat")!.planProfile
        XCTAssertEqual(squat.trains, .maxStrength)
        XCTAssertEqual(squat.primaryMuscles, ["quads", "glutes"])
        XCTAssertEqual(squat.trainsLabel, "Strength · quads, glutes")
        XCTAssertTrue(squat.works(.quads, primaryOnly: true))
        XCTAssertEqual(Self.catalogue.item("depth-jump")?.planProfile.trains, .reactive)
        XCTAssertEqual(Self.catalogue.item("depth-jump")?.planProfile.energySystem, .alactic)
        XCTAssertEqual(Self.catalogue.item("continuous-easy-run")?.planProfile.energySystem, .aerobic)
        XCTAssertEqual(Self.catalogue.item("bulgarian-split-squat")?.planProfile.buildsPhrase, "single-leg strength")
        for focus in focusMuscleOrder where focus != "neck" { XCTAssertNotNil(FocusMuscle.group(focus), focus) }
    }

    // An old pack without the new fields still decodes and gets a sensible quality.
    func testOldProfilesStillDecode() throws {
        let json = #"{"pattern":"jump","role":"power","regions":["lower"],"fatigue":2,"impact":3,"technique":1,"legLoad":2,"group":"reactive-hop"}"#
        let profile = try JSONDecoder().decode(ExerciseProfile.self, from: Data(json.utf8))
        XCTAssertNil(profile.quality)
        XCTAssertEqual(profile.trains, .reactive)
        XCTAssertTrue(profile.primaryMuscles.isEmpty)
    }

    // §1: stage from age and training age.
    func testTrainingStage() {
        XCTAssertEqual(TrainingStage.of(age: 13, experience: .experienced), .foundation)
        XCTAssertEqual(TrainingStage.of(age: 17, experience: .beginner), .foundation)
        XCTAssertEqual(TrainingStage.of(age: 15, experience: .experienced), .development)
        XCTAssertEqual(TrainingStage.of(age: 17, experience: .experienced), .performance)
        XCTAssertTrue(SessionPlanner.decide(day("basketball", phase: .offSeason, age: 13)).reasons.contains(.stageFoundation))
        XCTAssertTrue(SessionPlanner.decide(day("basketball", phase: .offSeason, age: 17, experience: .experienced)).reasons.contains(.stagePerformance))
    }

    // §3: the fast block comes first and, inside it, landing and sprints come before jumps and throws.
    func testFastWorkIsOrderedAndDosedForSpeed() {
        for sport in ["basketball", "soccer", "volleyball", "track-and-field"] {
            let session = build(day(sport, phase: .preSeason, age: 17, experience: .experienced), sport: sport)
            let power = session.items.filter { $0.block == .power }
            let ranks = power.compactMap(profile).map { ExerciseRankProbe.rank($0) }
            XCTAssertEqual(ranks, ranks.sorted(), "\(sport): fast block order \(power.map(\.itemSlug))")
            for item in power {
                XCTAssertGreaterThanOrEqual(item.restSec, 60, "\(item.itemSlug): fast work needs real rest")
                XCTAssertNotNil(item.effort, "\(item.itemSlug): says how it should feel")
                if item.dose.kind == "reps" { XCTAssertLessThanOrEqual(item.dose.reps ?? 0, 5, "\(item.itemSlug): few reps") }
            }
        }
    }

    // §3: landings per session by stage — foundation 40, never above the weekly budget.
    func testLandingsPerSessionFollowTheStage() {
        let young = build(day("volleyball", phase: .offSeason, age: 13, experience: .beginner), sport: "volleyball")
        XCTAssertLessThanOrEqual(landings(young), TrainingStage.foundation.sessionLandingCap)
        let tight = build(day("volleyball", phase: .offSeason, age: 17, experience: .experienced), sport: "volleyball", contacts: 10)
        XCTAssertLessThanOrEqual(landings(tight), 10)
    }

    // §1: foundation athletes learn to land first; the strength sets stay far from failure.
    func testFoundationLearnsToLandAndStaysFarFromFailure() {
        let session = build(day("basketball", phase: .offSeason, age: 13, experience: .beginner), sport: "basketball")
        if let first = session.items.first(where: { $0.block == .power }) {
            XCTAssertEqual(profile(first)?.trains, .deceleration, "landing first: \(first.itemSlug)")
        }
        for item in session.items where item.block == .primaryStrength {
            XCTAssertTrue(item.effort?.contains("3–4 reps left") ?? false, "\(item.itemSlug): \(item.effort ?? "nil")")
        }
        // Never a maximal or near-failure set for under-18s.
        let older = build(day("basketball", phase: .offSeason, age: 17, experience: .experienced), sport: "basketball")
        for item in older.items where item.block == .primaryStrength {
            XCTAssertFalse(item.effort?.contains("1–2 reps") ?? false, "under 18: \(item.effort ?? "nil")")
        }
    }

    // §5: a sport with a known, preventable injury gets the exercise that prevents it.
    func testSportInjuryRiskGetsItsStaple() {
        let soccer = build(day("soccer", phase: .offSeason), sport: "soccer")
        XCTAssertTrue(soccer.items.contains { profile($0)?.group == "hamstring-eccentric" }, "soccer: Nordics, \(soccer.items.map(\.itemSlug))")
        XCTAssertTrue(soccer.decision?.reasons.contains(.sportInjuryRisk) ?? false)
        XCTAssertTrue(soccer.explanation?.parts.contains { $0.question == "What's behind it?" } ?? false)
        let baseball = build(day("baseball", phase: .offSeason), sport: "baseball")
        XCTAssertTrue(baseball.items.contains { profile($0)?.group == "shoulder-health" }, "baseball: shoulder work")
        XCTAssertEqual(InjuryPrevention.risks(sport: "soccer", demands: nil).first, .hamstring)
    }

    // §4: at least as much pulling as pressing in the upper body.
    func testPullingAtLeastMatchesPressing() {
        for sport in ["basketball", "swimming-diving", "football", "tennis"] {
            let session = build(day(sport, phase: .offSeason), sport: sport)
            var push = 0, pull = 0
            for item in session.items where ![.prep, .mobility, .cooldown].contains(item.block) {
                guard let p = profile(item), p.isUpper else { continue }
                let main = Set(p.primaryMuscles)
                if !main.isDisjoint(with: ["chest", "front-delts", "triceps"]) { push += 1 }
                if !main.isDisjoint(with: ["lats", "upper-back", "rear-delts", "rotator-cuff"]) { pull += 1 }
            }
            XCTAssertGreaterThanOrEqual(pull, push, "\(sport): \(session.items.map(\.itemSlug))")
        }
    }

    // §6: in season the sets drop but the main lifts stay heavy.
    func testInSeasonKeepsIntensity() {
        let session = build(day("soccer", phase: .inSeason, nextGame: 4), sport: "soccer")
        XCTAssertTrue(session.decision?.reasons.contains(.inSeasonKeepIntensity) ?? false)
        for item in session.items where item.block == .primaryStrength && item.dose.kind == "reps" {
            guard Self.catalogue.item(item.itemSlug)?.defaultDose.load?.hasPrefix("bodyweight") != true else { continue }
            XCTAssertLessThanOrEqual(item.dose.reps ?? 0, 6, "\(item.itemSlug): heavy, few reps in season")
            XCTAssertLessThanOrEqual(item.dose.sets, 2)
        }
    }

    // §7: conditioning on a lifting day comes after the lifting, and not as running when there's a choice.
    func testConditioningAfterLiftingAvoidsRunning() {
        let rx = ConditioningEngine.prescribe(.aerobicBase, minutes: 20, lowImpact: false, age: 16, experience: .intermediate,
                                              afterLifting: true, usable: { _ in true })
        XCTAssertEqual(rx?.itemSlug, "easy-bike-ride")
        let normal = ConditioningEngine.prescribe(.aerobicBase, minutes: 20, lowImpact: false, age: 16, experience: .intermediate,
                                                  usable: { _ in true })
        XCTAssertEqual(normal?.itemSlug, "continuous-easy-run")
    }

    // D: what a session builds, in words.
    func testSessionSaysWhatItBuilds() {
        let session = build(day("basketball", phase: .offSeason), sport: "basketball")
        let builds = SessionTrains.builds(session.items, catalogue: Self.catalogue)
        XCTAssertFalse(builds.isEmpty)
        XCTAssertLessThanOrEqual(builds.count, 3)
        XCTAssertTrue(session.explanation?.parts.contains { $0.question == "What does it build?" } ?? false)
        XCTAssertTrue(session.explanation?.parts.contains { $0.question == "How hard should it feel?" } ?? false)
        XCTAssertFalse(SessionTrains.sets(session.items, catalogue: Self.catalogue).isEmpty)
    }
}

/// The fast-block order, as the builder ranks it (landing, sprint, reactive, heavy power, jumps, throws).
private enum ExerciseRankProbe {
    static func rank(_ p: ExerciseProfile) -> Int {
        switch p.trains {
        case .deceleration: 0
        case .acceleration, .maxVelocity, .changeOfDirection: 1
        case .reactive: 2
        case .strengthSpeed: 3
        default: p.pattern == "throw" ? 5 : 4
        }
    }
}
