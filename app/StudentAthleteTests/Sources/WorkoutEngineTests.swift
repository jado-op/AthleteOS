import XCTest
#if canImport(Engine)
@testable import Engine
#endif

/// The V6 workout engine against the real content packs (docs/VERSION-6.md
/// §4–§9, §24): the rules a coach would check, written as assertions.
final class WorkoutEngineTests: XCTestCase {
    private static let catalogue: Catalogue = {
        let dist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "content/dist")
        // Local runs from a linked copy of this file: the repo checkout.
        let fallback = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AOS_CONTENT_DIST"] ?? "/root/fitness/content/dist")
        return CatalogueLoader.load(from: FileManager.default.fileExists(atPath: dist.path) ? dist : fallback)
    }()

    private let fullGym: Set<String> = ["dumbbell", "barbell", "rack", "bench", "pull-up-bar", "band", "box", "med-ball", "wall", "cones",
                                        "kettlebell", "weight-plate", "trap-bar", "low-bar", "step", "mini-band", "slider", "cable-machine",
                                        "lat-pulldown", "foam-roller", "jump-rope", "bumper-plates", "landmine", "hurdle", "ball", "stick", "partner"]
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    private func day(_ sport: String, position: String? = nil, phase: SeasonPhase, age: Int = 16, experience: TrainingExperience = .intermediate,
                     practice: PracticeIntensity? = nil, nextGame: Int? = nil, lastGame: Int? = nil, readiness: ReadinessLevel = .normal,
                     gymDay: Bool = true, recent: RecentLoad = RecentLoad(), goals: [Capacity] = []) -> TrainingDay {
        TrainingDay(date: date, phase: phase, age: age, experience: experience,
                    demands: SportDemandsTable.demands(sport: Self.catalogue.sportsBySlug[sport], position: position),
                    goals: goals, practice: practice, daysToNextGame: nextGame, daysSinceLastGame: lastGame, readiness: readiness,
                    recent: recent, plannedGymDay: gymDay)
    }

    private func build(_ day: TrainingDay, sport: String, position: String? = nil, requested: SessionType? = nil,
                       equipment: Set<String>? = nil) -> (SessionDecision, GeneratedSession) {
        let decision = SessionPlanner.decide(day, requested: requested)
        let kit = AthleteKit(catalogue: Self.catalogue, sport: Self.catalogue.sportsBySlug[sport], positionSlug: position,
                             equipment: equipment ?? fullGym, seed: "test")
        return (decision, SessionBuilder.build(decision, day: day, kit: kit))
    }

    private func profile(_ item: GeneratedPlannedItem) -> ExerciseProfile? { Self.catalogue.item(item.itemSlug)?.planProfile }

    private func mainWork(_ session: GeneratedSession) -> [GeneratedPlannedItem] {
        session.items.filter { ![.prep, .mobility, .cooldown].contains($0.block) }
    }

    func testThePacksCarryExerciseProfiles() {
        XCTAssertGreaterThan(Self.catalogue.itemsBySlug.count, 500)
        XCTAssertTrue(Self.catalogue.itemsBySlug.values.allSatisfy { $0.profile != nil }, "every item ships a V6 profile")
    }

    // §6 + §8: after practice — short, upper body and trunk, nothing that tires the legs again.
    func testAfterPracticeInAFieldSportAddsNoLegFatigueOrConditioning() {
        let (decision, session) = build(day("soccer", position: "midfielder", phase: .inSeason, practice: .normal, nextGame: 3), sport: "soccer", position: "midfielder")
        XCTAssertEqual(decision.sessionType, .afterPractice)
        XCTAssertTrue((15...35).contains(decision.durationTarget))
        XCTAssertTrue(decision.avoidToday.contains(.hardConditioning))
        XCTAssertNil(decision.conditioning)
        for item in mainWork(session) {
            XCTAssertLessThan(profile(item)?.legLoad ?? 0, 2, "\(item.itemSlug) loads tired legs")
        }
        XCTAssertTrue(decision.primaryTargets.contains(.upperStrength))
        XCTAssertLessThanOrEqual(mainWork(session).count, 7, "quality over exercise count (§7)")
    }

    // In season, practice every day: one short, heavy leg lift once the legs
    // have gone a week without one (Rønnestad 2011) — never close to a game.
    func testDailyPracticeStillGetsAWeeklyLegLift() {
        let practices = RecentLoad(days: (1...7).map { DayLoad(daysAgo: $0, practice: .normal, game: $0 == 3) })
        let (decision, session) = build(day("soccer", position: "midfielder", phase: .inSeason, practice: .normal, nextGame: 4, recent: practices),
                                        sport: "soccer", position: "midfielder")
        XCTAssertEqual(decision.sessionType, .afterPractice)
        XCTAssertTrue(decision.reasons.contains(.weeklyHeavyLegs))
        XCTAssertGreaterThanOrEqual(decision.legBudget, 2)
        XCTAssertTrue(decision.primaryTargets.contains(.strength))
        XCTAssertTrue(decision.avoidToday.contains(.highVolumeLowerBody), "low volume")
        XCTAssertTrue(session.items.contains { profile($0)?.isLower ?? false && [.primaryStrength, .secondaryStrength].contains($0.block) })
        XCTAssertTrue(session.explanation?.summary.contains("heavy leg lift") ?? false)
        // A leg lift 3 days ago, a game in 2 days, or a low check-in: not today.
        var lifted = practices
        lifted.days[2].lowerPattern = "squat"
        XCTAssertFalse(SessionPlanner.decide(day("soccer", phase: .inSeason, practice: .normal, nextGame: 4, recent: lifted)).reasons.contains(.weeklyHeavyLegs))
        XCTAssertFalse(SessionPlanner.decide(day("soccer", phase: .inSeason, practice: .normal, nextGame: 2, recent: practices)).reasons.contains(.weeklyHeavyLegs))
        XCTAssertFalse(SessionPlanner.decide(day("soccer", phase: .inSeason, practice: .normal, nextGame: 4, readiness: .belowNormal,
                                                 recent: practices)).reasons.contains(.weeklyHeavyLegs))
    }

    // §8's example: hard practice today, game tomorrow, tired legs → upper body + trunk.
    func testHardPracticeBeforeAGameMeansNoHeavyLowerBody() {
        let (decision, session) = build(day("basketball", phase: .inSeason, practice: .hard, nextGame: 1), sport: "basketball")
        XCTAssertEqual(decision.legBudget, 0)
        XCTAssertTrue(decision.avoidToday.contains(.heavyLowerBody))
        XCTAssertTrue(decision.reasons.contains(.hardTeamPractice))
        XCTAssertTrue(decision.reasons.contains(.gameTomorrow))
        XCTAssertFalse(session.items.contains { ($0.block == .primaryStrength || $0.block == .secondaryStrength) && (profile($0)?.isLower ?? false) })
    }

    // §6: a development day is a real session — 45–75 minutes, built in blocks.
    func testAnOffSeasonDevelopmentDayHasRealStructureAndLength() {
        let (decision, session) = build(day("basketball", position: "guard", phase: .offSeason), sport: "basketball", position: "guard")
        XCTAssertEqual(decision.sessionType, .gymDevelopment)
        XCTAssertTrue((45...75).contains(decision.durationTarget))
        XCTAssertGreaterThanOrEqual(session.estimatedMinutes, decision.durationTarget - 15)
        XCTAssertLessThanOrEqual(session.estimatedMinutes, decision.durationTarget + 8)
        let blocks = session.items.compactMap(\.block)
        XCTAssertEqual(blocks.first, .prep)
        XCTAssertTrue(blocks.contains(.primaryStrength))
        // Fast and explosive work before strength, conditioning last (§10 ordering).
        if let power = blocks.lastIndex(of: .power), let strength = blocks.firstIndex(of: .primaryStrength) { XCTAssertLessThan(power, strength) }
        if let conditioning = blocks.firstIndex(of: .conditioning), let strength = blocks.lastIndex(of: .primaryStrength) { XCTAssertGreaterThan(conditioning, strength) }
        let main = session.items.filter { $0.block == .primaryStrength }.compactMap(profile)
        XCTAssertTrue(main.contains { $0.isLower }, "a lower-body main lift")
        XCTAssertTrue(main.contains { $0.isUpper && !$0.isLower }, "an upper-body main lift")
        XCTAssertLessThanOrEqual(mainWork(session).count, 10)
    }

    // §6: an in-season development day is a real session too, filled with sets before exercises.
    func testAnInSeasonDevelopmentDayFillsItsTime() {
        let (decision, session) = build(day("soccer", position: "midfielder", phase: .inSeason, nextGame: 3), sport: "soccer", position: "midfielder")
        XCTAssertEqual(decision.sessionType, .gymDevelopment)
        XCTAssertGreaterThanOrEqual(session.estimatedMinutes, decision.durationTarget - 10, "\(session.estimatedMinutes) of \(decision.durationTarget)")
        XCTAssertLessThanOrEqual(mainWork(session).count, 10)
    }

    // §5: cardio is programmed from what the sport already gives.
    func testCrossCountryGetsNoExtraRunning() {
        let recent = RecentLoad(days: (1...5).map { DayLoad(daysAgo: $0, practice: .normal) })
        let rest = SessionPlanner.decide(day("cross-country", phase: .inSeason, gymDay: false, recent: recent))
        XCTAssertEqual(rest.sessionType, .rest)
        let gym = SessionPlanner.decide(day("cross-country", phase: .inSeason, recent: recent))
        XCTAssertEqual(gym.conditioningMinutes, 0)
        XCTAssertNil(gym.conditioning)
    }

    func testGolfGetsProgrammedAerobicWork() {
        let decision = SessionPlanner.decide(day("golf", phase: .offSeason, gymDay: false))
        XCTAssertEqual(decision.sessionType, .conditioning)
        XCTAssertEqual(decision.conditioning, .aerobicBase)
        XCTAssertGreaterThanOrEqual(decision.conditioningMinutes, 20)
    }

    func testTheDayBeforeAGameIsAShortPrimer() {
        let (decision, session) = build(day("lacrosse", position: "midfield", phase: .inSeason, nextGame: 1), sport: "lacrosse", position: "midfield")
        XCTAssertEqual(decision.sessionType, .primer)
        XCTAssertLessThanOrEqual(decision.durationTarget, 30)
        XCTAssertNil(decision.conditioning)
        XCTAssertFalse(session.items.contains { (profile($0)?.isLower ?? false) && (profile($0)?.fatigue ?? 0) >= 4 })
    }

    func testTheDayAfterAGameIsRecovery() {
        XCTAssertEqual(SessionPlanner.decide(day("basketball", phase: .inSeason, lastGame: 1)).sessionType, .recovery)
    }

    func testALowCheckInTurnsAGymDayIntoRecovery() {
        let decision = SessionPlanner.decide(day("tennis", phase: .offSeason, readiness: .low))
        XCTAssertEqual(decision.sessionType, .recovery)
        XCTAssertTrue(decision.reasons.contains(.lowReadiness))
    }

    // Lower-body patterns alternate through the week.
    func testMainLowerPatternAlternates() {
        let afterSquat = RecentLoad(days: [DayLoad(daysAgo: 2, lowerPattern: "squat", upperPattern: "push", sessionType: .gymDevelopment)])
        let decision = SessionPlanner.decide(day("soccer", phase: .offSeason, recent: afterSquat))
        XCTAssertEqual(decision.lowerPattern, "hinge")
        XCTAssertEqual(decision.upperPattern, "pull")
    }

    // §2 youth envelope: under-18s never get more than 3 sets of a rep exercise.
    func testYouthEnvelopeHolds() {
        for experience in TrainingExperience.allCases {
            let (_, session) = build(day("football", position: "lineman", phase: .offSeason, age: 16, experience: experience), sport: "football", position: "lineman")
            for item in session.items where item.dose.kind == "reps" {
                XCTAssertLessThanOrEqual(item.dose.sets, 3, "\(item.itemSlug) for a 16-year-old (\(experience))")
            }
        }
    }

    func testTheSameDayAlwaysGivesTheSameSession() {
        let a = build(day("volleyball", phase: .preSeason), sport: "volleyball").1
        let b = build(day("volleyball", phase: .preSeason), sport: "volleyball").1
        XCTAssertEqual(a.items.map(\.itemSlug), b.items.map(\.itemSlug))
    }

    // §22: calm, precise copy — never advertising language.
    func testExplanationsSoundLikeACoach() {
        let banned = ["unlock", "crush", "unstoppable", "push past", "beast", "no excuses"]
        let days = [day("soccer", phase: .inSeason, practice: .hard, nextGame: 1), day("golf", phase: .offSeason, gymDay: false),
                    day("basketball", phase: .offSeason), day("tennis", phase: .offSeason, readiness: .low)]
        for d in days {
            let session = build(d, sport: "soccer").1
            let text = ([session.explanation?.summary ?? ""] + (session.explanation?.parts.map(\.answer) ?? [])).joined(separator: " ").lowercased()
            XCTAssertFalse(session.explanation?.summary.isEmpty ?? true)
            for phrase in banned { XCTAssertFalse(text.contains(phrase), "“\(phrase)” in: \(text)") }
        }
    }

    // §21: rest is correct execution, not a missed day.
    func testRestIsAPlanNotAFailure() {
        let decision = SessionPlanner.decide(day("cross-country", phase: .inSeason, gymDay: false,
                                                 recent: RecentLoad(days: (1...5).map { DayLoad(daysAgo: $0, practice: .normal) })))
        XCTAssertEqual(decision.sessionType, .rest)
        XCTAssertEqual(decision.durationTarget, 0)
        let text = PlanExplanation.make(decision: decision, day: day("cross-country", phase: .inSeason, gymDay: false), items: [],
                                        catalogue: Self.catalogue, conditioning: nil).summary
        XCTAssertTrue(text.contains("part of the plan"))
    }

    // §23: a conditioning goal adds programmed work, but never to a sport that is itself the conditioning.
    func testAnAerobicGoalAddsConditioning() {
        let practices = RecentLoad(days: (1...4).map { DayLoad(daysAgo: $0, practice: .normal) })
        let without = SessionPlanner.conditioningRemaining(day("basketball", phase: .inSeason, recent: practices))
        let with = SessionPlanner.conditioningRemaining(day("basketball", phase: .inSeason, recent: practices, goals: [.aerobic]))
        XCTAssertGreaterThan(with, without)
        XCTAssertEqual(SessionPlanner.conditioningRemaining(day("cross-country", phase: .inSeason, recent: practices, goals: [.aerobic])), 0)
    }

    func testWeekPlannerKeepsGymDaysOffGameEves() {
        // Mon practice, Tue free, Wed practice, Thu free, Fri game eve, Sat game, Sun free.
        let week: [(practice: Bool, game: Bool)] = [(true, false), (false, false), (true, false), (false, false), (false, false), (false, true), (false, false)]
        let days = WeekPlanner.gymDays(days: week, count: 2)
        XCTAssertEqual(days.count, 2)
        XCTAssertFalse(days.contains(4), "never the day before a game")
        XCTAssertFalse(days.contains(5), "never on a game day")
    }

    // MARK: Engine review (2026-11-18)

    // Owner's rule: every session has a drill of the athlete's own sport — for their position when there is one.
    func testEverySessionHasADrillOfTheSportForThePosition() {
        let (_, gym) = build(day("soccer", position: "goalkeeper", phase: .offSeason), sport: "soccer", position: "goalkeeper")
        let drills = gym.items.filter { $0.block == .skill }
        XCTAssertEqual(drills.count, 1, "one drill of the sport")
        XCTAssertTrue(Self.catalogue.item(drills[0].itemSlug)?.positions?.contains("goalkeeper") ?? false, "a goalkeeper drill")
        let (_, outfield) = build(day("soccer", position: "midfielder", phase: .inSeason, practice: .normal, nextGame: 3), sport: "soccer", position: "midfielder")
        for item in outfield.items where item.block == .skill {
            XCTAssertEqual(Self.catalogue.item(item.itemSlug)?.itemSportSlug, "soccer")
            XCTAssertFalse(Self.catalogue.item(item.itemSlug)?.positions?.contains("goalkeeper") ?? false, "never another position's drill")
        }
    }

    // Conditioning follows the same age, coaching and experience limits as everything else.
    func testConditioningRespectsAge() {
        for sport in ["basketball", "soccer", "volleyball", "track-and-field"] {
            let young = TrainingDay(date: date, phase: .offSeason, age: 13, experience: .beginner,
                                    demands: SportDemandsTable.demands(sport: Self.catalogue.sportsBySlug[sport], position: nil),
                                    goals: [.aerobic], plannedGymDay: true)
            let (_, session) = build(young, sport: sport, requested: .conditioning)
            for item in session.items {
                XCTAssertLessThanOrEqual(Self.catalogue.item(item.itemSlug)?.minAge ?? 0, 13, "\(item.itemSlug) for a 13-year-old in \(sport)")
            }
        }
    }

    // Travelling never overrides a body that needs to recover; a game day never loads the legs.
    /// The twin's findings steer the plan, and "Why" says so.
    func testTwinSteersTheDay() {
        var plain = day("soccer", phase: .offSeason, lastGame: 2)
        let usual = SessionPlanner.decide(plain)
        XCTAssertFalse(usual.avoids(.heavyLowerBody))
        plain.twin = [.slowGameRecovery, .loadSpike]
        let steered = SessionPlanner.decide(plain)
        XCTAssertTrue(steered.avoids(.heavyLowerBody), "slow recovery: two days after a game stays light on the legs")
        XCTAssertTrue(steered.avoids(.hardConditioning), "load spike: no hard conditioning")
        XCTAssertLessThan(steered.durationTarget, usual.durationTarget)
        XCTAssertTrue(steered.reasons.contains(.twinSlowGameRecovery))
        XCTAssertTrue(steered.reasons.contains(.twinLoadSpike))
        let (decision, session) = build(plain, sport: "soccer")
        XCTAssertEqual(decision, steered)
        XCTAssertTrue(session.explanation?.parts.contains { $0.question == "What does your twin change?" } ?? false)
        XCTAssertEqual(TwinSteer.from([.strengthNotSpeed, .sleepBase]), [.strengthNotSpeed])
    }

    func testTravelAndGameDaysRespectRecovery() {
        let tired = TrainingDay(date: date, phase: .inSeason, age: 16, experience: .intermediate,
                                demands: SportDemandsTable.demands(sport: Self.catalogue.sportsBySlug["soccer"], position: nil),
                                readiness: .low, travelling: true)
        XCTAssertEqual(SessionPlanner.decide(tired, requested: nil).sessionType, .mobility)
        XCTAssertEqual(SessionPlanner.decide(tired, requested: .travel).sessionType, .mobility)
        let evening = TrainingDay(date: date, phase: .inSeason, age: 16, experience: .intermediate,
                                  demands: SportDemandsTable.demands(sport: Self.catalogue.sportsBySlug["soccer"], position: nil),
                                  gameToday: true, travelling: true, evening: true)
        let decision = SessionPlanner.decide(evening, requested: nil)
        XCTAssertEqual(decision.sessionType, .mobility)
        XCTAssertEqual(decision.mobilityPurpose, .eveningDownshift, "after the game: wind down, not warm up")
        XCTAssertEqual(decision.legBudget, 0)
    }

    // Travel uses what needs no equipment.
    func testTravelNeedsNoEquipment() {
        let travel = TrainingDay(date: date, phase: .inSeason, age: 16, experience: .intermediate,
                                 demands: SportDemandsTable.demands(sport: Self.catalogue.sportsBySlug["basketball"], position: nil),
                                 travelling: true)
        let (_, session) = build(travel, sport: "basketball", requested: .travel, equipment: ["none"])
        XCTAssertFalse(session.items.isEmpty)
        for item in session.items {
            XCTAssertTrue(PlanGenerator.isEligibleForEquipment(Self.catalogue.item(item.itemSlug)!, available: ["none"]), item.itemSlug)
        }
    }

    // Limited time: the session really fits (fewer sets, then less work), and keeps the sport's drill.
    func testATwentyMinuteDayFitsInTwentyMinutes() {
        let short = TrainingDay(date: date, phase: .offSeason, age: 16, experience: .intermediate,
                                demands: SportDemandsTable.demands(sport: Self.catalogue.sportsBySlug["basketball"], position: nil),
                                availableMinutes: 20, plannedGymDay: true)
        let (decision, session) = build(short, sport: "basketball")
        XCTAssertLessThanOrEqual(decision.durationTarget, 20)
        XCTAssertLessThanOrEqual(session.estimatedMinutes, 24, "about 20 minutes, not 30")
        XCTAssertTrue(session.items.contains { $0.block == .primaryStrength }, "still a real strength session")
    }

    // MARK: - "What's on today?": the athlete decides, safety still shapes the session

    private func said(_ choices: Set<DayChoice>, _ base: TrainingDay) -> TrainingDay {
        var day = base
        day.said = choices
        return day
    }

    func testARestDayTheAthleteChoseHasNoSession() {
        // Even on a planned gym day: their word wins, and rest costs nothing.
        let decision = SessionPlanner.decide(said([.rest], day("soccer", position: "midfielder", phase: .inSeason, gymDay: true)))
        XCTAssertEqual(decision.sessionType, .rest)
        XCTAssertTrue(decision.reasons.contains(.choseRest))
        let (_, session) = build(said([.rest], day("soccer", position: "midfielder", phase: .inSeason)), sport: "soccer", position: "midfielder")
        XCTAssertTrue(session.items.isEmpty)
        XCTAssertTrue(session.explanation?.summary.contains("You chose a rest day") ?? false)
    }

    func testGymOnADayWithoutAPlannedGymSessionIsAFullGymSession() {
        let auto = SessionPlanner.decide(day("basketball", position: "guard", phase: .offSeason, gymDay: false))
        XCTAssertNotEqual(auto.sessionType, .gymDevelopment, "without the athlete's word, not a gym day")
        let (decision, session) = build(said([.gym], day("basketball", position: "guard", phase: .offSeason, gymDay: false)),
                                        sport: "basketball", position: "guard")
        XCTAssertEqual(decision.sessionType, .gymDevelopment)
        XCTAssertTrue(decision.reasons.contains(.choseGym))
        XCTAssertTrue(session.items.contains { $0.block == .primaryStrength })
        XCTAssertTrue(session.explanation?.summary.hasPrefix("You said gym today") ?? false)
        XCTAssertTrue(session.explanation?.parts.contains { $0.question == "What did you tell AthleteOS?" } ?? false)
    }

    func testSomethingLightIsMobilityNotTraining() {
        let (decision, session) = build(said([.light], day("soccer", position: "midfielder", phase: .inSeason, gymDay: true)),
                                        sport: "soccer", position: "midfielder")
        XCTAssertEqual(decision.sessionType, .mobility)
        XCTAssertTrue(decision.reasons.contains(.choseLight))
        XCTAssertFalse(session.items.contains { $0.block == .primaryStrength || $0.block == .power || $0.block == .conditioning })
        // Home asks for "after practice" on a practice day; "something light" stays light.
        let afterPractice = SessionPlanner.decide(said([.practice, .light], day("soccer", position: "midfielder", phase: .inSeason, practice: .normal)),
                                                  requested: .afterPractice)
        XCTAssertEqual(afterPractice.sessionType, .mobility)
        XCTAssertEqual(afterPractice.mobilityPurpose, .recovery)
    }

    func testTheChoiceOverridesTheSchedule() {
        // TodayEngine turns "gym, no practice" on a practice weekday into practice: nil; the planner follows.
        let gym = SessionPlanner.decide(said([.gym], day("soccer", position: "midfielder", phase: .inSeason, practice: nil, nextGame: 4, gymDay: false)))
        XCTAssertEqual(gym.sessionType, .gymDevelopment)
        // Practice and gym after an easy practice: a full session; after a hard one, the short after-practice session.
        let easy = SessionPlanner.decide(said([.practice, .gym], day("soccer", position: "midfielder", phase: .inSeason, practice: .light, nextGame: 4)),
                                         requested: .afterPractice)
        XCTAssertEqual(easy.sessionType, .gymDevelopment)
        let hard = SessionPlanner.decide(said([.practice, .gym], day("soccer", position: "midfielder", phase: .inSeason, practice: .hard, nextGame: 4)))
        XCTAssertEqual(hard.sessionType, .afterPractice)
        XCTAssertTrue(hard.reasons.contains(.choseGymMadeLighter))
        // "Let AthleteOS decide" is today's behaviour exactly.
        let base = day("basketball", position: "guard", phase: .offSeason)
        XCTAssertEqual(SessionPlanner.decide(said([], base)), SessionPlanner.decide(base))
    }

    func testSafetyStillWinsOverTheGym() {
        // Something hurt last night: easy movement, explained.
        var hurt = said([.gym], day("soccer", position: "midfielder", phase: .inSeason, gymDay: false))
        hurt.reflection = ReflectionSignal(dayFelt: 2, bodyFelt: 4)
        let hurtDecision = SessionPlanner.decide(hurt)
        XCTAssertEqual(hurtDecision.sessionType, .recovery)
        XCTAssertTrue(hurtDecision.reasons.contains(.choseGymMadeLighter))
        // Just back from being sick.
        var sick = said([.gym], day("soccer", position: "midfielder", phase: .inSeason, gymDay: false))
        sick.illnessReturnDay = 1
        XCTAssertEqual(SessionPlanner.decide(sick).sessionType, .recovery)
        // Low readiness.
        XCTAssertEqual(SessionPlanner.decide(said([.gym], day("soccer", phase: .inSeason, readiness: .low, gymDay: false))).sessionType, .recovery)
        // A game tomorrow: a short primer, not a full gym day.
        let eve = SessionPlanner.decide(said([.gym], day("soccer", position: "midfielder", phase: .inSeason, nextGame: 1, gymDay: false)))
        XCTAssertEqual(eve.sessionType, .primer)
        XCTAssertTrue(eve.reasons.contains(.choseGymMadeLighter))
        // A game today: the game is the training.
        var gameDay = said([.gym, .game], day("soccer", position: "midfielder", phase: .inSeason, gymDay: false))
        gameDay.gameToday = true
        XCTAssertEqual(SessionPlanner.decide(gameDay).sessionType, .mobility)
        // Pain: a gym session, but nothing that loads the sore area.
        var knee = said([.gym], day("basketball", position: "guard", phase: .offSeason, gymDay: false))
        knee.painAreas = [.knee]
        let (kneeDecision, kneeSession) = build(knee, sport: "basketball", position: "guard")
        XCTAssertEqual(kneeDecision.sessionType, .gymDevelopment)
        for item in kneeSession.items {
            guard let catalogueItem = Self.catalogue.item(item.itemSlug) else { continue }
            XCTAssertFalse(PainFilter.loads(catalogueItem, areas: [.knee]), "\(item.itemSlug) loads a sore knee")
        }
    }

    func testDayAnswersCombineAndStandAlone() {
        var answer = DayAnswer.suggested(practiceScheduled: true, gameScheduled: false)
        XCTAssertEqual(answer.choices, [.practice])
        XCTAssertEqual(answer.practice, .normal)
        answer = answer.toggling(.gym)
        XCTAssertEqual(answer.choices, [.practice, .gym])
        XCTAssertEqual(answer.label, "practice + gym")
        answer = answer.toggling(.rest)
        XCTAssertEqual(answer.choices, [.rest], "rest stands alone")
        XCTAssertNil(answer.practice)
        answer = answer.toggling(.light)
        XCTAssertEqual(answer.choices, [.light])
        XCTAssertTrue(answer.toggling(.auto).isAuto)
        XCTAssertEqual(DayAnswer.suggested(practiceScheduled: false, gameScheduled: false).choices, [.auto])
        let stored = DayAnswer(choices: [.practice, .gym], practice: .hard)
        XCTAssertEqual(DayAnswer(encoded: stored.encoded), stored)
        XCTAssertEqual(DayAnswer(encoded: "gym"), DayAnswer(choices: [.gym]))
        XCTAssertNil(DayAnswer(encoded: ""))
        XCTAssertEqual(DayAnswer(choices: [.auto]).engineChoices, [])
    }
}
