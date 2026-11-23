import XCTest
#if canImport(Engine)
@testable import Engine
#endif

/// The shared athlete context (owner, 2026-11-23): what the athlete told
/// AthleteOS is stored, remembered until resolved, asked about the next
/// morning only when it can change the plan, and read by the planner.
final class AthleteContextTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Monday 16 November 2026, evening.
    private var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 19))! }
    private func morning(_ daysLater: Int) -> Date { calendar.date(byAdding: .day, value: daysLater, to: monday)!.addingTimeInterval(-11 * 3600) }
    private func dayStart(_ daysLater: Int) -> Date { calendar.startOfDay(for: calendar.date(byAdding: .day, value: daysLater, to: monday)!) }

    private static let catalogue: Catalogue = {
        let dist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "content/dist")
        let fallback = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AOS_CONTENT_DIST"] ?? "/root/fitness/content/dist")
        return CatalogueLoader.load(from: FileManager.default.fileExists(atPath: dist.path) ? dist : fallback)
    }()

    private func trainingDay(_ context: ContextSignals, practice: PracticeIntensity? = nil, gym: GymRequest? = nil) -> TrainingDay {
        var day = TrainingDay(date: morning(1), phase: .offSeason, age: 16, experience: .intermediate,
                              demands: SportDemandsTable.demands(sport: Self.catalogue.sportsBySlug["soccer"], position: nil),
                              practice: practice, plannedGymDay: true)
        day.context = context
        day.gym = gym
        return day
    }

    /// Monday evening: "Practice was brutal. Tons of sprints and my legs are cooked."
    private func mondayReport() -> [AthleteContextEvent] {
        let practice = AthleteContextEvent(createdAt: monday, from: dayStart(0), kind: .exposure, source: .tellAthleteOS,
                                           reported: ["Hard practice: a lot of sprinting"], qualities: [.sprinting], level: 3, practice: true)
        let legs = AthleteContextEvent(createdAt: monday, from: dayStart(0), kind: .fatigue, source: .tellAthleteOS,
                                       reported: ["Legs very tired"], regions: [.legs], level: 3, relatedID: practice.id)
        return AthleteContext.adding(legs, to: AthleteContext.adding(practice, to: [], calendar: calendar), calendar: calendar)
    }

    // MARK: Tell AthleteOS reads it

    func testTellReadsTheOwnersExample() {
        let result = TellParser.parse("Practice was brutal. Tons of sprints and my legs are cooked.", now: monday, calendar: calendar)
        XCTAssertTrue(result.proposals.contains(.fatigue(day: dayStart(0), regions: ["legs"], level: 3)), "\(result.proposals)")
        XCTAssertTrue(result.proposals.contains { if case .training(dayStart(0), let q, 3) = $0 { q.contains("sprinting") } else { false } },
                      "\(result.proposals)")
        // A report about practice is not a request to add practice, a game, or a goal.
        XCTAssertFalse(result.proposals.contains { if case .practice = $0 { true } else if case .goals = $0 { true } else { false } })
        XCTAssertFalse(result.proposals.contains { if case .pain = $0 { true } else { false } }, "tired legs are not pain")
        XCTAssertTrue(result.unread.isEmpty, "\(result.unread)")
    }

    func testTellReadsFatigueByClause() {
        let result = TellParser.parse("Upper body feels fine but my legs are dead", now: monday, calendar: calendar)
        XCTAssertEqual(result.proposals, [.fatigue(day: dayStart(0), regions: ["legs"], level: 3)])
        XCTAssertEqual(TellParser.parse("My calves are a bit tired", now: monday, calendar: calendar).proposals,
                       [.fatigue(day: dayStart(0), regions: ["calves"], level: 1)])
        XCTAssertEqual(TellParser.parse("Meine Beine sind total platt", now: monday, calendar: calendar).proposals,
                       [.fatigue(day: dayStart(0), regions: ["legs"], level: 3)])
    }

    func testPainStaysOnTheSafetyPath() {
        let result = TellParser.parse("My legs are sore and my knee hurts", now: monday, calendar: calendar)
        // Pain is read for the whole sentence (safety errs towards more, never less).
        XCTAssertTrue(result.proposals.contains { if case .pain(let areas, _) = $0 { areas.contains("knee") } else { false } }, "\(result.proposals)")
        XCTAssertTrue(result.proposals.contains(.fatigue(day: dayStart(0), regions: ["legs"], level: 2)))
        // Hurting calves are pain, never "tired calves".
        let hurt = TellParser.parse("My calves really hurt", now: monday, calendar: calendar)
        XCTAssertFalse(hurt.proposals.contains { if case .fatigue = $0 { true } else { false } })
        XCTAssertTrue(hurt.proposals.contains { if case .pain = $0 { true } else { false } })
    }

    func testTellReadsPracticeCharacter() {
        let light = TellParser.parse("We barely ran today, mostly shooting.", now: monday, calendar: calendar)
        XCTAssertTrue(light.proposals.contains { if case .training(_, let q, 1) = $0 { q.contains("lowRunning") } else { false } }, "\(light.proposals)")
        let conditioning = TellParser.parse("Practice was mostly conditioning", now: monday, calendar: calendar)
        XCTAssertTrue(conditioning.proposals.contains { if case .training(_, let q, 3) = $0 { q.contains("conditioning") } else { false } },
                      "\(conditioning.proposals)")
    }

    func testTellReadsAnOwnWorkout() {
        let result = TellParser.parse("Yesterday I did bench, rows, pull-ups and shoulder press.", now: monday, calendar: calendar)
        guard case .workout(let day, let patterns, let qualities, _, _)? = result.proposals.first else { return XCTFail("\(result.proposals)") }
        XCTAssertEqual(day, dayStart(-1))
        XCTAssertEqual(Set(patterns), ["push", "pull"])
        XCTAssertEqual(qualities, ["upperStrength"])
        let legs = TellParser.parse("I did squats and RDLs with my friend", now: monday, calendar: calendar)
        guard case .workout(_, let legPatterns, _, _, _)? = legs.proposals.first else { return XCTFail("\(legs.proposals)") }
        XCTAssertEqual(Set(legPatterns), ["squat", "hinge"])
        XCTAssertEqual(TellParser.parse("I trained chest and back yesterday", now: monday, calendar: calendar).proposals.count, 1)
    }

    func testTellReadsEquipmentAndTime() {
        let dumbbells = TellParser.parse("I only have dumbbells until Sunday", now: monday, calendar: calendar)
        XCTAssertEqual(dumbbells.proposals, [.equipment(from: dayStart(0), days: 7, tags: ["dumbbell"])])
        let hotel = TellParser.parse("Hotel gym has cables, dumbbells and a bench", now: monday, calendar: calendar)
        XCTAssertEqual(hotel.proposals, [.equipment(from: dayStart(0), days: 1, tags: ["dumbbell", "bench", "cable-machine"])], "a hotel gym with equipment isn't 'no gym'")
        XCTAssertEqual(TellParser.parse("I only have 30 minutes today", now: monday, calendar: calendar).proposals, [.time(day: dayStart(0), minutes: 30)])
        XCTAssertEqual(TellParser.parse("Ich habe nur eine halbe Stunde", now: monday, calendar: calendar).proposals, [.time(day: dayStart(0), minutes: 30)])
        // When practice is, or how long it was, is not free time.
        XCTAssertFalse(TellParser.parse("I have practice in 2 hours", now: monday, calendar: calendar).proposals
            .contains { if case .time = $0 { true } else { false } })
    }

    // MARK: Remembered and asked about

    func testFatiguePersistsAndIsAskedTheNextMorning() {
        let events = mondayReport()
        let questions = AthleteContext.questions(events, now: morning(1), calendar: calendar)
        XCTAssertEqual(questions.count, 1, "one question about the legs, not two (fatigue + the hard practice)")
        XCTAssertEqual(questions.first?.question, "How do they feel this morning?")
        XCTAssertEqual(questions.first?.context, "You said your legs were very tired after a sprint-heavy practice.")
        XCTAssertEqual(questions.first?.covers, [.lower])
        // Not asked the same evening it was told.
        XCTAssertTrue(AthleteContext.questions(events, now: monday, calendar: calendar).isEmpty)
    }

    func testStillTiredKeepsLegsLightAndRecoveredResolves() {
        var events = mondayReport()
        let id = AthleteContext.questions(events, now: morning(1), calendar: calendar)[0].id
        events = AthleteContext.answering(.veryTired, to: id, in: events, now: morning(1), calendar: calendar)
        let tuesday = AthleteContext.signals(events, on: morning(1), calendar: calendar)
        XCTAssertEqual(tuesday.lowerFatigue, 3)
        XCTAssertTrue(tuesday.recentSprinting, "Monday's sprints still count on Tuesday")
        let decision = SessionPlanner.decide(trainingDay(tuesday))
        XCTAssertEqual(decision.legBudget, 0)
        XCTAssertTrue(decision.reasons.contains(.highLowerBodyFatigue))
        XCTAssertTrue(decision.reasons.contains(.recentHighSprintExposure))
        for avoid in [AvoidToday.heavyLowerBody, .highImpact, .maxSprinting, .hardConditioning] {
            XCTAssertTrue(decision.avoids(avoid), "\(avoid)")
        }
        XCTAssertFalse(decision.primaryTargets.contains(.strength), "no heavy legs")

        // Wednesday: compared with yesterday; back to normal resolves it.
        let wednesday = AthleteContext.questions(events, now: morning(2), calendar: calendar)
        XCTAssertEqual(wednesday.first?.question, "How are your legs compared with yesterday?")
        events = AthleteContext.answering(.backToNormal, to: wednesday[0].id, in: events, now: morning(2), calendar: calendar)
        XCTAssertEqual(AthleteContext.signals(events, on: morning(2), calendar: calendar).lowerFatigue, 0)
        // Thursday: not asked again.
        XCTAssertTrue(AthleteContext.questions(events, now: morning(3), calendar: calendar).isEmpty)
    }

    func testCalvesImproveThenResolveThenStopBeingAsked() {
        var events = AthleteContext.adding(AthleteContextEvent(from: dayStart(0), kind: .fatigue, source: .tellAthleteOS,
                                                               regions: [.calves], level: 3), to: [], calendar: calendar)
        let tuesday = AthleteContext.questions(events, now: morning(1), calendar: calendar)
        XCTAssertEqual(tuesday.first?.context, "You said your calves were very tired.")
        events = AthleteContext.answering(.aLittleTired, to: tuesday[0].id, in: events, now: morning(1), calendar: calendar)
        XCTAssertEqual(AthleteContext.signals(events, on: morning(1), calendar: calendar).lowerFatigue, 1)
        let wednesday = AthleteContext.questions(events, now: morning(2), calendar: calendar)
        XCTAssertEqual(wednesday.first?.question, "How are your calves compared with yesterday?")
        events = AthleteContext.answering(.backToNormal, to: wednesday[0].id, in: events, now: morning(2), calendar: calendar)
        for later in 3...6 {
            XCTAssertTrue(AthleteContext.questions(events, now: morning(later), calendar: calendar).isEmpty, "day \(later)")
        }
    }

    func testUnansweredFatigueExpires() {
        let events = mondayReport()
        XCTAssertFalse(AthleteContext.questions(AthleteContext.expire(events, now: morning(3), calendar: calendar), now: morning(3), calendar: calendar).isEmpty)
        let later = AthleteContext.expire(events, now: morning(AthleteContext.fatigueExpiryDays), calendar: calendar)
        XCTAssertTrue(AthleteContext.questions(later, now: morning(AthleteContext.fatigueExpiryDays), calendar: calendar)
            .allSatisfy { $0.region != .legs || !$0.covers.contains(.lower) || $0.id != events[1].id })
        XCTAssertEqual(AthleteContext.signals(later, on: morning(AthleteContext.fatigueExpiryDays), calendar: calendar).lowerFatigue, 0)
    }

    func testQuestionBudget() {
        var events: [AthleteContextEvent] = []
        for region in [ContextRegion.calves, .shoulders, .back, .core] {
            events = AthleteContext.adding(AthleteContextEvent(from: dayStart(0), kind: .fatigue, source: .tellAthleteOS, regions: [region], level: 2),
                                           to: events, calendar: calendar)
        }
        XCTAssertEqual(AthleteContext.questions(events, now: morning(1), calendar: calendar).count, AthleteContext.questionBudget)
    }

    func testAHardPracticeWithNothingSaidIsAskedOnce() {
        let practice = AthleteContextEvent(from: dayStart(0), kind: .exposure, source: .tellAthleteOS, qualities: [.conditioning], level: 3, practice: true)
        var events = [practice]
        let questions = AthleteContext.questions(events, now: morning(1), calendar: calendar)
        XCTAssertEqual(questions.map(\.id), [practice.id])
        // "Fresh": remembered, not asked again.
        XCTAssertNil(AthleteContext.fatigueFromAnswer(.backToNormal, to: practice, now: morning(1), calendar: calendar))
        var fresh = AthleteContextEvent(from: morning(1), kind: .fatigue, source: .morningCheckIn, regions: [.legs], level: 0, status: .resolved,
                                        relatedID: practice.id)
        fresh.checks = [.init(day: dayStart(1), level: 0)]
        events = AthleteContext.adding(fresh, to: events, calendar: calendar)
        XCTAssertTrue(AthleteContext.questions(events, now: morning(1), calendar: calendar).isEmpty)
        // "Very tired": an open fatigue the next morning follows.
        let tired = AthleteContext.fatigueFromAnswer(.veryTired, to: practice, now: morning(1), calendar: calendar)
        XCTAssertEqual(tired?.currentLevel, 3)
        XCTAssertEqual(tired?.relatedID, practice.id)
    }

    // MARK: What the plan does with it

    func testPracticeThatCoveredConditioningAddsNone() {
        let practice = AthleteContextEvent(from: dayStart(1), kind: .exposure, source: .tellAthleteOS, qualities: [.conditioning, .sprinting],
                                           level: 3, practice: true)
        let signals = AthleteContext.signals([practice], on: morning(1), calendar: calendar)
        XCTAssertTrue(signals.conditioningCovered)
        XCTAssertTrue(signals.hardPractice)
        let decision = SessionPlanner.decide(trainingDay(signals, practice: .hard))
        XCTAssertTrue(decision.avoids(.hardConditioning))
        XCTAssertTrue(decision.reasons.contains(.recentHighSprintExposure))
        XCTAssertNotEqual(decision.conditioning, .anaerobic)
    }

    func testAReportedWorkoutCountsForRegionRecency() {
        let workout = AthleteContextEvent(from: dayStart(0), kind: .exposure, source: .tellAthleteOS, qualities: [.upperStrength],
                                          level: 2, patterns: ["push", "pull"])
        XCTAssertEqual(AthleteContext.regionDays([workout], now: morning(1), calendar: calendar), [.upper: 1])
        let loads = AthleteContext.pastLoads([workout], before: morning(1), calendar: calendar)
        XCTAssertEqual(loads.first?.daysAgo, 1)
        XCTAssertEqual(loads.first?.upperPattern, "push")
        XCTAssertTrue(loads.first?.capacities.contains(.upperStrength) ?? false)
        // The gym advisor doesn't pick upper body the day after.
        let advice = GymAdvisor.advise(day: trainingDay(ContextSignals()), history: GymHistory(daysSince: [.upper: 1]))
        XCTAssertNotNil(advice.notToday[.upper])
    }

    func testTemporaryEquipmentOnlyWithinItsDays() {
        let hotel = AthleteContextEvent(from: dayStart(1), until: dayStart(4), kind: .equipment, source: .tellAthleteOS, equipment: ["dumbbell", "bench"])
        XCTAssertNil(AthleteContext.signals([hotel], on: morning(0), calendar: calendar).equipment)
        XCTAssertEqual(AthleteContext.signals([hotel], on: morning(2), calendar: calendar).equipment, ["dumbbell", "bench"])
        XCTAssertNil(AthleteContext.signals([hotel], on: morning(5), calendar: calendar).equipment, "the usual setup returns by itself")
        let expired = AthleteContext.expire([hotel], now: morning(5), calendar: calendar)
        XCTAssertEqual(expired.first?.status, .expired)
        // Only those exercises are built.
        let day = trainingDay(AthleteContext.signals([hotel], on: morning(2), calendar: calendar), gym: GymRequest(focus: .full, length: .standard, anchorSeed: "a"))
        let decision = SessionPlanner.decide(day, requested: .gymDevelopment)
        XCTAssertTrue(decision.reasons.contains(.limitedEquipment))
        let kit = AthleteKit(catalogue: Self.catalogue, sport: Self.catalogue.sportsBySlug["soccer"], equipment: ["dumbbell", "bench"], seed: "t")
        let session = SessionBuilder.build(decision, day: day, kit: kit)
        XCTAssertFalse(session.items.isEmpty)
        for item in session.items {
            guard let catalogued = Self.catalogue.item(item.itemSlug) else { continue }
            XCTAssertTrue(PlanGenerator.isEligibleForEquipment(catalogued, available: ["dumbbell", "bench"]), item.itemSlug)
        }
    }

    func testNewEquipmentReplacesTheOldForTheSameDays() {
        let none = AthleteContextEvent(from: dayStart(1), until: dayStart(4), kind: .equipment, source: .tellAthleteOS, equipment: [])
        let better = AthleteContextEvent(from: dayStart(2), until: dayStart(4), kind: .equipment, source: .tellAthleteOS, equipment: ["dumbbell", "cable-machine"])
        let events = AthleteContext.adding(better, to: [none], calendar: calendar)
        XCTAssertEqual(AthleteContext.signals(events, on: morning(3), calendar: calendar).equipment, ["dumbbell", "cable-machine"])
    }

    func testThirtyMinutesRecomposesTheSession() {
        let told = AthleteContextEvent(from: dayStart(1), until: dayStart(1), kind: .time, source: .tellAthleteOS, minutes: 30)
        let signals = AthleteContext.signals([told], on: morning(1), calendar: calendar)
        XCTAssertEqual(signals.minutes, 30)
        XCTAssertNil(AthleteContext.signals([told], on: morning(2), calendar: calendar).minutes, "only that day")
        let decision = SessionPlanner.decide(trainingDay(signals), requested: .gymDevelopment)
        XCTAssertEqual(decision.durationTarget, 30)
        XCTAssertTrue(decision.reasons.contains(.availableTimeToday))
        let kit = AthleteKit(catalogue: Self.catalogue, sport: Self.catalogue.sportsBySlug["soccer"],
                             equipment: ["dumbbell", "barbell", "rack", "bench", "pull-up-bar", "band", "box", "med-ball", "weight-plate"], seed: "t")
        let short = SessionBuilder.build(decision, day: trainingDay(signals), kit: kit)
        let full = SessionBuilder.build(SessionPlanner.decide(trainingDay(ContextSignals()), requested: .gymDevelopment), day: trainingDay(ContextSignals()), kit: kit)
        XCTAssertLessThan(short.items.count, full.items.count)
        // Rebuilt by priority, not cut off: the main strength work is still there.
        XCTAssertTrue(short.items.contains { $0.block == .primaryStrength }, "\(short.items.map(\.block))")
        let explanation = PlanExplanation.make(decision: decision, day: trainingDay(signals), items: short.items, catalogue: Self.catalogue, conditioning: nil)
        XCTAssertTrue(explanation.summary.contains("30 minutes"), explanation.summary)
    }

    func testTheExplanationSaysWhy() {
        var events = mondayReport()
        let id = AthleteContext.questions(events, now: morning(1), calendar: calendar)[0].id
        events = AthleteContext.answering(.veryTired, to: id, in: events, now: morning(1), calendar: calendar)
        let day = trainingDay(AthleteContext.signals(events, on: morning(1), calendar: calendar))
        let decision = SessionPlanner.decide(day)
        let lines = PlanExplanation.contextLines(Set(decision.reasons), day: day, decision: decision)
        XCTAssertEqual(lines.first, "Practice gave you a lot of sprinting, and you said your legs are still very tired. Today stays away from hard leg work, jumps and sprints.")
    }

    func testNothingToldChangesNothing() {
        let plain = SessionPlanner.decide(trainingDay(ContextSignals()))
        XCTAssertTrue(Set(plain.reasons).isDisjoint(with: [.highLowerBodyFatigue, .lowerBodyFatigue, .highUpperBodyFatigue, .recentHighSprintExposure,
                                                           .practiceCoveredConditioning, .limitedEquipment, .availableTimeToday]))
        XCTAssertTrue(AthleteContext.questions([], now: morning(1), calendar: calendar).isEmpty)
    }
}
