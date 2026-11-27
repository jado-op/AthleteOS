import XCTest
#if canImport(Engine)
@testable import Engine
#endif

final class TwinAnalysisTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 18))! }

    private func day(_ back: Int, hour: Int = 7) -> Date {
        calendar.date(byAdding: .day, value: -back, to: calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: hour))!)!
    }

    /// 21 mornings; game mornings sleep `gameSleep`, the rest 8.4 h; the mornings after games are sore.
    private func season(games: [Int], gameSleep: Double = 7.2, soreAfter: Int = 2, gameEnergy: Int = 4) -> TwinInput {
        let mornings = (1...21).map { back -> TwinInput.Morning in
            let isGame = games.contains(back)
            let afterGame = games.contains(back + 1)
            return TwinInput.Morning(date: day(back), sleepHours: isGame ? gameSleep : 8.4,
                                     energy: isGame ? gameEnergy : 4, soreness: afterGame ? 4 : soreAfter == 2 ? 2 : 2)
        }
        return TwinInput(mornings: mornings, games: games.map { day($0, hour: 16) }, sessions: [], now: now)
    }

    // MARK: Sleep before games

    func testShortSleepBeforeGamesIsFoundWithTheGap() {
        let report = TwinAnalysis.report(season(games: [3, 10, 17]), calendar: calendar)
        let insight = report.insights.first { $0.kind == .sleepBeforeGames }
        XCTAssertNotNil(insight)
        XCTAssertEqual(insight?.values["sleepGap"], "1 h 12 min")
        XCTAssertEqual(insight?.values["gameCount"], "3")
        XCTAssertEqual(insight?.strength, .strong)
        XCTAssertEqual(insight?.evidence?.points.filter(\.marked).count, 3)
        XCTAssertEqual(insight?.briefing?.id, "sleep-before-games")
        XCTAssertTrue(insight?.why.contains("1 h 12 min") == true)
        XCTAssertFalse(insight?.why.contains("{") == true)
    }

    func testNoPatternNoInsight() {
        let report = TwinAnalysis.report(season(games: [3, 10, 17], gameSleep: 8.3), calendar: calendar)
        XCTAssertNil(report.insights.first { $0.kind == .sleepBeforeGames })
        // One game isn't a pattern.
        let one = TwinAnalysis.report(season(games: [3]), calendar: calendar)
        XCTAssertNil(one.insights.first { $0.kind == .sleepBeforeGames })
    }

    // MARK: Recovery and fuel

    func testSorenessAfterGamesIsFound() {
        let report = TwinAnalysis.report(season(games: [3, 10, 17]), calendar: calendar)
        let insight = report.insights.first { $0.kind == .recoveryAfterGames }
        XCTAssertEqual(insight?.values["sorenessDays"], "a day")
        XCTAssertEqual(insight?.briefing?.id, "recovery-after-games")
        XCTAssertTrue(insight?.detail.contains("get it checked") == true)
    }

    /// Day-one soreness says nothing about day two: the plan's day-two caution
    /// needs the athlete's own day-two mornings (priors research, second opinion).
    func testGameCautionOnDayTwoNeedsDayTwoMornings() {
        let dayOneOnly = TwinAnalysis.report(season(games: [3, 10, 17]), calendar: calendar).insights
        XCTAssertNotNil(dayOneOnly.first { $0.kind == .recoveryAfterGames })
        XCTAssertFalse(TwinSteer.from(dayOneOnly).contains(.slowGameRecovery))

        var input = season(games: [3, 10, 17])
        input.mornings = input.mornings.map { morning in
            let back = calendar.dateComponents([.day], from: calendar.startOfDay(for: morning.date), to: calendar.startOfDay(for: now)).day ?? 0
            guard [1, 8, 15].contains(back) else { return morning }
            var sore = morning
            sore.soreness = 4
            return sore
        }
        let both = TwinAnalysis.report(input, calendar: calendar).insights
        XCTAssertEqual(both.first { $0.kind == .recoveryAfterGames }?.values["sorenessDays"], "two days")
        XCTAssertTrue(TwinSteer.from(both).contains(.slowGameRecovery))
    }

    /// One-tap "feeling normal" mornings repeat the athlete's usual: they never
    /// make a pattern about how games feel the morning after.
    func testOneTapMorningsDontTeachGamePatterns() {
        var input = season(games: [3, 10, 17])
        XCTAssertNotNil(TwinAnalysis.report(input, calendar: calendar).insights.first { $0.kind == .recoveryAfterGames })
        input.mornings = input.mornings.map { morning in
            let back = calendar.dateComponents([.day], from: calendar.startOfDay(for: morning.date), to: calendar.startOfDay(for: now)).day ?? 0
            guard [2, 9, 16].contains(back) else { return morning }
            var assumed = morning
            assumed.assumed = true
            return assumed
        }
        XCTAssertNil(TwinAnalysis.report(input, calendar: calendar).insights.first { $0.kind == .recoveryAfterGames },
                     "the mornings after the games were one-tap: nothing said, nothing learned")
    }

    func testLowGameDayEnergyOrTheInterviewFlagsFuel() {
        let tired = TwinAnalysis.report(season(games: [3, 10, 17], gameEnergy: 2), calendar: calendar)
        XCTAssertEqual(tired.insights.first { $0.kind == .gameDayFuel }?.values["energyGap"], "2.0 points")
        var input = TwinInput(intake: ["gameFood": "nothing"], now: now)
        XCTAssertEqual(TwinAnalysis.report(input, calendar: calendar).insights.first { $0.kind == .gameDayFuel }?.strength, .emerging)
        input.intake["gameFood"] = "meal"
        XCTAssertNil(TwinAnalysis.report(input, calendar: calendar).insights.first { $0.kind == .gameDayFuel })
    }

    // MARK: Strength and speed

    private func squats(_ weights: [(Int, Double)]) -> [TwinInput.Lift] {
        weights.map { TwinInput.Lift(date: day($0.0), slug: "barbell-back-squat", weightKg: $0.1, reps: 5) }
    }

    func testStrongerButNotFasterIsFound() {
        let lifts = squats([(40, 80), (33, 82), (12, 90), (5, 92)])
        let sprints = [TwinInput.Test(date: day(41), testID: "sprint30", name: "30 m sprint", value: 4.22, higherIsBetter: false),
                       TwinInput.Test(date: day(4), testID: "sprint30", name: "30 m sprint", value: 4.21, higherIsBetter: false)]
        let report = TwinAnalysis.report(TwinInput(lifts: lifts, tests: sprints, now: now), calendar: calendar)
        let insight = report.insights.first { $0.kind == .strengthNotSpeed }
        XCTAssertEqual(insight?.values["strengthGain"], "12%")
        XCTAssertEqual(insight?.values["sprintChange"], "no change")
        XCTAssertNotNil(insight?.evidence?.comparison)
    }

    func testStrongerAndFasterIsAStrength() {
        let lifts = squats([(40, 80), (33, 82), (12, 90), (5, 92)])
        let sprints = [TwinInput.Test(date: day(41), testID: "sprint30", name: "30 m sprint", value: 4.40, higherIsBetter: false),
                       TwinInput.Test(date: day(4), testID: "sprint30", name: "30 m sprint", value: 4.21, higherIsBetter: false)]
        let report = TwinAnalysis.report(TwinInput(lifts: lifts, tests: sprints, now: now), calendar: calendar)
        XCTAssertNil(report.insights.first { $0.kind == .strengthNotSpeed })
        XCTAssertNotNil(report.strengths.first { $0.kind == .strengthRising })
    }

    // MARK: Mind

    func testTheInterviewAndReflectionsFlagMistakesAndConfidence() {
        let reflections = (1...6).map { back in
            TwinInput.Reflect(date: day(back * 2, hour: 21), feeling: 3, needsWork: back.isMultiple(of: 2) ? ["Focus", "Confidence"] : ["Speed"])
        }
        let input = TwinInput(reflections: reflections, intake: ["mistake": "replay", "pressure": "tense"], now: now)
        let report = TwinAnalysis.report(input, calendar: calendar)
        let mistakes = report.insights.first { $0.kind == .mistakeReplay }
        XCTAssertEqual(mistakes?.strength, .strong)
        XCTAssertEqual(mistakes?.values["mistakeCount"], "3")
        XCTAssertEqual(mistakes?.values["reflectionCount"], "6")
        XCTAssertNotNil(report.insights.first { $0.kind == .pressureConfidence })
        let calm = TwinAnalysis.report(TwinInput(intake: ["mistake": "reset", "pressure": "narrow", "confidence": "preparation"], now: now),
                                       calendar: calendar)
        XCTAssertTrue(calm.insights.isEmpty)
    }

    // MARK: The report

    func testStrongInsightsComeFirstAndTheCoachNamesTheBriefing() {
        let input = season(games: [3, 10, 17])
        var withInterview = input
        withInterview.intake = ["gameFood": "small"]
        let report = TwinAnalysis.report(withInterview, calendar: calendar)
        XCTAssertEqual(report.insights.first?.strength, .strong)
        XCTAssertEqual(report.insights.last?.kind, .gameDayFuel)
        XCTAssertTrue(report.coachRead.contains("“\(report.insights[0].briefing?.title ?? "")”"))
        XCTAssertEqual(report.counts.games, 3)
        XCTAssertEqual(report.counts.checkIns, 21)
        XCTAssertEqual(Set(report.assigned.map(\.id)).count, report.assigned.count)
    }

    func testANewTwinSaysWhatItNeeds() {
        let report = TwinAnalysis.report(TwinInput(now: now), calendar: calendar)
        XCTAssertTrue(report.insights.isEmpty)
        XCTAssertTrue(report.coachRead.contains("interview"))
    }

    func testOldDataIsOutsideTheWindow() {
        let old = (60...80).map { TwinInput.Morning(date: day($0), sleepHours: 6, energy: 1, soreness: 5) }
        let report = TwinAnalysis.report(TwinInput(mornings: old, games: [day(70)], now: now), calendar: calendar)
        XCTAssertEqual(report.counts.checkIns, 0)
        XCTAssertTrue(report.insights.isEmpty)
    }

    // MARK: Content, performances, store

    func testTheContentDecodesWithABriefingForEveryInsight() {
        XCTAssertEqual(AcademyContent.briefings.count, 6)
        for kind in [TwinInsightKind.sleepBeforeGames, .recoveryAfterGames, .gameDayFuel, .strengthNotSpeed, .mistakeReplay, .pressureConfidence] {
            XCTAssertNotNil(AcademyContent.briefing(for: kind), kind.rawValue)
        }
        XCTAssertTrue(AcademyContent.briefings.allSatisfy { $0.minutes >= 8 && $0.chapters.count >= 3 })
        XCTAssertTrue(AcademyContent.intake.contains { $0.freeText })
        XCTAssertTrue(AcademyContent.intake.filter { !$0.freeText }.allSatisfy { $0.options.count >= 2 })
    }

    func testPerformancesComeFromLiftsTestsAndTheAthlete() {
        let lifts = [TwinInput.Lift(date: day(20), slug: "bench-press", weightKg: 65, reps: 5),
                     TwinInput.Lift(date: day(20), slug: "bench-press", weightKg: 67.5, reps: 3),
                     TwinInput.Lift(date: day(3), slug: "bench-press", weightKg: 72.5, reps: 2),
                     TwinInput.Lift(date: day(3), slug: "soccer-plant-and-strike", weightKg: 0, reps: 6)]
        let tests = [TwinInput.Test(date: day(30), testID: "sprint30", name: "30 m sprint", value: 4.4, higherIsBetter: false),
                     TwinInput.Test(date: day(2), testID: "sprint30", name: "30 m sprint", value: 4.21, higherIsBetter: false)]
        let custom = [CustomPerformance(name: "Yo-Yo IR1", unit: "level", higherIsBetter: true,
                                        entries: [.init(date: day(10), value: 17.4)])]
        let records = Performances.records(lifts: lifts, tests: tests, custom: custom, calendar: calendar)
        XCTAssertEqual(records.map(\.name), ["Bench press", "30 m sprint", "Yo-Yo IR1"])
        XCTAssertEqual(records[0].best?.value, 72.5)
        XCTAssertEqual(records[0].history.count, 2)
        XCTAssertEqual(records[0].improvement(since: day(10)), 5)
        XCTAssertEqual(records[1].best?.value, 4.21)
        XCTAssertEqual(records[1].unit, "s")
        XCTAssertEqual(records[1].improvement(since: day(10))!, 0.19, accuracy: 0.0001)
        XCTAssertEqual(Performances.number(4.2, unit: "s"), "4.20")
        XCTAssertEqual(Performances.number(72.5, unit: "kg"), "72.5")
        XCTAssertEqual(Performances.number(105, unit: "kg"), "105")
    }

    func testTheStoreKeepsTheInterviewReadsAndPerformances() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "TwinAnalysisTests"))
        defaults.removePersistentDomain(forName: "TwinAnalysisTests")
        var state = AcademyStore.answering(["mistake": "replay", "goal": "  Start every game  "], in: AcademyState(), at: now)
        XCTAssertEqual(state.intake["goal"], "Start every game")
        XCTAssertEqual(state.intakeDoneAt, now)
        state = AcademyStore.answering(["goal": " "], in: state, at: now.addingTimeInterval(60))
        XCTAssertNil(state.intake["goal"])
        XCTAssertEqual(state.intakeDoneAt, now)
        state = AcademyStore.reading("sleep-before-games", in: state, at: now)
        state = AcademyStore.recording("Bench press", unit: "kg", higherIsBetter: true, value: 70, at: day(5), in: state)
        state = AcademyStore.recording("bench press", unit: "kg", higherIsBetter: true, value: 72.5, at: day(1), in: state)
        XCTAssertEqual(state.performances.count, 1)
        XCTAssertEqual(state.performances[0].entries.map(\.value), [70, 72.5])
        AcademyStore.save(state, defaults)
        XCTAssertEqual(AcademyStore.load(defaults), state)
        AcademyStore.delete(defaults)
        XCTAssertEqual(AcademyStore.load(defaults), AcademyState())
    }

    func testEventsAreCountsWithoutContent() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AcademyEventTests"))
        defaults.removePersistentDomain(forName: "AcademyEventTests")
        AcademyEvent.log(.lessonCompleted, defaults)
        AcademyEvent.log(.lessonCompleted, defaults)
        XCTAssertEqual(defaults.dictionary(forKey: "usage.counts") as? [String: Int], ["academy.lesson_completed": 2])
        XCTAssertNil(AcademyAccess.freeBriefingsPerWeek)
        XCTAssertTrue(AcademyAccess.canOpen(readThisWeek: 99, isPro: false))
        XCTAssertFalse(AcademyAccess.canOpen(readThisWeek: 2, isPro: false, limit: 2))
    }

    func testSupportResourcesByCountry() {
        XCTAssertEqual(SupportResources.resource(region: "DE").display, "116 111")
        XCTAssertEqual(SupportResources.resource(region: "US").phone, "988")
        XCTAssertNil(SupportResources.resource(region: nil).phone)
    }

    // MARK: Every sport

    func testTheTwinSpeaksTheAthletesSport() {
        var tennis = season(games: [3, 10, 17])
        tennis.sportSlug = "tennis"
        let report = TwinAnalysis.report(tennis, calendar: calendar)
        let sleep = report.insights.first { $0.kind == .sleepBeforeGames }
        XCTAssertEqual(sleep?.headline, "You sleep 1 h 12 min less before matches.")
        XCTAssertEqual(sleep?.basis, "3 matches")
        XCTAssertFalse(sleep?.why.contains("{") == true)
        XCTAssertFalse(sleep?.why.contains("games") == true)
        XCTAssertTrue(report.insights.allSatisfy { !$0.headline.contains("game") })
        XCTAssertEqual(AcademyContent.family(forSport: "swimming-diving").events, "races")
        XCTAssertEqual(AcademyContent.family(forSport: "golf").event, "round")
        XCTAssertEqual(AcademyContent.familyID(forSport: "unknown-sport"), "field")
        XCTAssertEqual(AcademyContent.family(forSport: "tennis").fill("Before a {event} — {Events} matter."), "Before a match — Matches matter.")
    }

    func testStrengthIsJustProgressWhereSpeedDoesntDecide() {
        let lifts = squats([(40, 80), (33, 82), (12, 90), (5, 92)])
        let sprints = [TwinInput.Test(date: day(41), testID: "sprint30", name: "30 m sprint", value: 4.22, higherIsBetter: false),
                       TwinInput.Test(date: day(4), testID: "sprint30", name: "30 m sprint", value: 4.21, higherIsBetter: false)]
        let golf = TwinAnalysis.report(TwinInput(lifts: lifts, tests: sprints, sportSlug: "golf", now: now), calendar: calendar)
        XCTAssertNil(golf.insights.first { $0.kind == .strengthNotSpeed })
        XCTAssertNotNil(golf.strengths.first { $0.kind == .strengthRising })
    }

    func testEveryBriefingReadsForEverySport() {
        for briefing in AcademyContent.briefings {
            for family in AcademyContent.pack.families.keys {
                let words = AcademyContent.pack.families[family]!
                for chapter in briefing.chapters {
                    for block in chapter.blocks {
                        let resolved = block.resolved(for: family)
                        XCTAssertFalse(words.fill(resolved.text ?? "").contains("{event"), "\(briefing.id) / \(family)")
                    }
                }
            }
        }
    }

    // MARK: Deeper patterns

    /// A28: a big week is said in hours the athlete can picture — never a
    /// percent, a ratio or an injury-risk claim.
    func testABigWeekIsSaidInHoursNotAPercentOrRisk() {
        var loads: [TwinInput.Load] = []
        for back in stride(from: 22, through: 8, by: -2) { loads.append(.init(date: day(back), minutes: 60, rpe: 6)) }
        for back in [6, 5, 4, 3, 2, 1] { loads.append(.init(date: day(back), minutes: 90, rpe: 8)) }
        let spike = TwinAnalysis.report(TwinInput(loads: loads, now: now), calendar: calendar).insights.first { $0.kind == .loadSpike }
        let text = [spike?.headline, spike?.detail, spike?.reason, spike?.measureText].compactMap { $0 }.joined(separator: " ")
        XCTAssertTrue(text.contains("9 h"), text)
        XCTAssertTrue(text.contains("usual week is about 2½ h"), text)
        XCTAssertFalse(text.contains("%"), text)
        XCTAssertFalse(text.lowercased().contains("injur"), text)
        XCTAssertEqual(TwinAnalysis.hours(45), "45 min")
        XCTAssertEqual(TwinAnalysis.hours(270), "4½ h")
    }

    func testALoadSpikeIsFound() {
        // Three steady weeks of 60 min at RPE 6, then a week of long hard sessions.
        var loads: [TwinInput.Load] = []
        for back in stride(from: 22, through: 8, by: -2) { loads.append(.init(date: day(back), minutes: 60, rpe: 6)) }
        for back in [6, 5, 4, 3, 2, 1] { loads.append(.init(date: day(back), minutes: 90, rpe: 8)) }
        let report = TwinAnalysis.report(TwinInput(loads: loads, now: now), calendar: calendar)
        let spike = report.insights.first { $0.kind == .loadSpike }
        XCTAssertNotNil(spike)
        XCTAssertEqual(spike?.strength, .strong)
        XCTAssertEqual(spike?.evidence?.points.last?.marked, true)
        XCTAssertNil(spike?.briefing)
        // Steady weeks: nothing.
        let steady = (1...24).filter { $0.isMultiple(of: 2) }.map { TwinInput.Load(date: day($0), minutes: 60, rpe: 6) }
        XCTAssertNil(TwinAnalysis.report(TwinInput(loads: steady, now: now), calendar: calendar).insights.first { $0.kind == .loadSpike })
    }

    func testShortNightsAndPracticeQuality() {
        let mornings = (1...14).map { TwinInput.Morning(date: day($0), sleepHours: $0.isMultiple(of: 2) ? 6.5 : 8.5, energy: 4, soreness: 2) }
        let practices = (1...14).map { TwinInput.Practice(date: day($0, hour: 17), went: $0.isMultiple(of: 2) ? 2 : 4, hard: 3, minutes: 90) }
        let report = TwinAnalysis.report(TwinInput(mornings: mornings, practices: practices, now: now), calendar: calendar)
        let insight = report.insights.first { $0.kind == .sleepAffectsPractice }
        XCTAssertEqual(insight?.headline, "After nights under 7½ hours, you rate your practice 2.0 points lower.")
        XCTAssertNotNil(report.insights.first { $0.kind == .irregularSleep })
    }

    func testStressfulDaysCostSleep() {
        let mornings = (1...14).map { back in
            TwinInput.Morning(date: day(back), sleepHours: back % 3 == 0 ? 6.8 : 8.3, energy: 4, soreness: 2, stress: back % 3 == 0 ? 5 : 2)
        }
        let insight = TwinAnalysis.report(TwinInput(mornings: mornings, now: now), calendar: calendar).insights.first { $0.kind == .stressAndSleep }
        XCTAssertEqual(insight?.headline, "Stressful days cost you 1 h 30 min of sleep.")
    }

    func testTrendsCompareWithThreeWeeksAgo() {
        // Six weeks: game eves were very short early on, much better lately.
        let games = [4, 11, 18, 25, 32, 39]
        let mornings = (1...42).map { back -> TwinInput.Morning in
            let eve = games.contains(back)
            return TwinInput.Morning(date: day(back), sleepHours: eve ? (back > 21 ? 6.4 : 7.8) : 8.4, energy: 4, soreness: 2)
        }
        let report = TwinAnalysis.report(TwinInput(mornings: mornings, games: games.map { day($0, hour: 16) }, now: now), calendar: calendar)
        let sleep = report.insights.first { $0.kind == .sleepBeforeGames }
        guard case .improving(let was)? = sleep?.trend else { return XCTFail("expected improving, got \(String(describing: sleep?.trend))") }
        XCTAssertEqual(was, "2 h")
    }
}
