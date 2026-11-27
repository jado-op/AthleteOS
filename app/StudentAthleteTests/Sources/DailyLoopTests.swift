import XCTest

/// V3's daily loop: the morning answers, pain, today's readiness in words,
/// the one-sentence reason for the plan, the evening reflection feeding
/// tomorrow, and a practice confirmed in the check-in.
final class DailyLoopTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let keys = ["safety.pain", "mindset.reflections", "schedule.dayOverrides", "schedule.dayChoices"]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    private var morning: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 7))! }

    private func answers(sleep: Int = 4, hours: Double? = 8, energy: Int = 4, soreness: Int = 2, stress: Int = 2) -> MorningAnswers {
        MorningAnswers(sleepQuality: sleep, sleepHours: hours, energy: energy, soreness: soreness, stress: stress)
    }

    func testFeelingGoodIsANormalDay() {
        let result = DailyLoop.readiness(answers: answers(), personalBand: nil, pain: nil, yesterday: nil)
        XCTAssertEqual(result?.level, .normal)
        XCTAssertNil(DailyLoop.readiness(answers: nil, personalBand: nil, pain: nil, yesterday: nil), "nothing known yet")
    }

    func testOneWarningSignLightensTheDayTwoMakeItARecoveryDay() {
        XCTAssertEqual(DailyLoop.readiness(answers: answers(hours: 5.5), personalBand: nil, pain: nil, yesterday: nil)?.level, .reduced)
        XCTAssertEqual(DailyLoop.readiness(answers: answers(soreness: 5), personalBand: nil, pain: nil, yesterday: nil)?.level, .reduced)
        XCTAssertEqual(DailyLoop.readiness(answers: answers(hours: 5.5, energy: 1), personalBand: nil, pain: nil, yesterday: nil)?.level, .recovery)
    }

    func testPainAlwaysWinsAndSaysWhy() {
        let knee = PainReport(day: "2026-09-26", areas: [.knee], level: .little)
        let result = DailyLoop.readiness(answers: answers(), personalBand: .green, pain: knee, yesterday: nil)
        XCTAssertEqual(result?.level, .reduced)
        XCTAssertEqual(result?.reason, "Because you reported pain, your training is reduced today.")
        let head = PainReport(day: "2026-09-26", areas: [.head], level: .little)
        XCTAssertEqual(DailyLoop.readiness(answers: answers(), personalBand: nil, pain: head, yesterday: nil)?.level, .recovery,
                       "a head is never trained through")
        let lot = PainReport(day: "2026-09-26", areas: [.ankle], level: .lot)
        XCTAssertEqual(DailyLoop.readiness(answers: answers(), personalBand: nil, pain: lot, yesterday: nil)?.level, .recovery)
    }

    func testAVeryHardYesterdayLightensToday() {
        let result = DailyLoop.readiness(answers: answers(), personalBand: nil, pain: nil, yesterday: EveningSignal(hardness: 4, body: 2))
        XCTAssertEqual(result?.level, .reduced)
        XCTAssertEqual(TodayReadiness.reduced.band, .amber)
        XCTAssertEqual(TodayReadiness.recovery.title, "Recovery Focus")
    }

    func testWhyThisPlanIsOneSentence() {
        XCTAssertEqual(DailyLoop.whyThisPlan(status: .active, mode: .afterPractice, practiceToday: true, gameToday: false, daysToNextGame: nil, readiness: nil),
                       "You have practice today, so the gym work is short and complements it.")
        XCTAssertEqual(DailyLoop.whyThisPlan(status: .active, mode: .gymDay, practiceToday: false, gameToday: false, daysToNextGame: 2, readiness: nil),
                       "Game in 2 days, so today stays short and sharp.")
        XCTAssertEqual(DailyLoop.whyThisPlan(status: .concussion, mode: nil, practiceToday: false, gameToday: false, daysToNextGame: nil, readiness: nil),
                       "Training is paused until a doctor clears you.")
        let pain = (level: TodayReadiness.reduced, reason: "Because you reported pain, your training is reduced today.")
        XCTAssertEqual(DailyLoop.whyThisPlan(status: .active, mode: .gymDay, practiceToday: false, gameToday: false, daysToNextGame: nil, readiness: pain), pain.reason)
    }

    func testPainIsKeptPerDay() {
        let report = PainReport(day: DayKey.of(morning, calendar: calendar), areas: [.knee, .ankle], level: .some)
        PainStore.set(report, on: morning, calendar: calendar)
        XCTAssertEqual(PainStore.report(on: morning, calendar: calendar), report)
        XCTAssertNil(PainStore.report(on: morning.addingTimeInterval(86_400), calendar: calendar))
        PainStore.set(nil, on: morning, calendar: calendar)
        XCTAssertNil(PainStore.report(on: morning, calendar: calendar), "“It's gone” clears it")
    }

    func testCheckInAnswersMapOntoTheStoredScales() {
        XCTAssertEqual(CheckInOptions.nearest(7.8, in: CheckInOptions.sleepHours)?.title, "7–8 h")
        XCTAssertEqual(CheckInOptions.nearest(4, in: CheckInOptions.energy)?.title, "Good")
        XCTAssertEqual(CheckInOptions.nearest(2, in: CheckInOptions.energy)?.title, "Low", "an older 1–5 answer shows as the nearest word")
        XCTAssertNil(CheckInOptions.nearest(nil, in: CheckInOptions.mood))
        XCTAssertEqual(CheckInOptions.soreness.last?.scale, 5, "high soreness is the top of the scale")
    }

    func testThePracticeConfirmedInTheCheckInWins() {
        let day = DayKey.of(morning, calendar: calendar)
        XCTAssertNil(PracticeOverride.hasPractice(on: day))
        PracticeOverride.set(false, on: day)
        XCTAssertEqual(PracticeOverride.hasPractice(on: day), false)
        XCTAssertFalse(PracticeSchedule.hasPractice(on: morning, calendar: calendar))
        PracticeOverride.set(true, on: day)
        XCTAssertTrue(PracticeSchedule.hasPractice(on: morning, calendar: calendar))
        PracticeOverride.set(nil, on: day)
        XCTAssertNil(PracticeOverride.hasPractice(on: day))
    }

    func testWhatsOnTodayWinsOverTheSchedule() {
        let scheduled = PracticeSchedule.hasPractice(on: morning, calendar: calendar)
        XCTAssertNil(DayChoiceStore.answer(on: morning, calendar: calendar))
        // Gym, no practice: the day's practice is off, whatever the schedule says.
        DayChoiceStore.set(DayAnswer(choices: [.gym]), on: morning, calendar: calendar)
        XCTAssertEqual(DayChoiceStore.answer(on: morning, calendar: calendar), DayAnswer(choices: [.gym]))
        XCTAssertFalse(PracticeSchedule.hasPractice(on: morning, calendar: calendar))
        XCTAssertEqual(DayChoiceStore.saysGame(on: morning, calendar: calendar), false)
        // Practice and gym, a hard practice: practice is on.
        DayChoiceStore.set(DayAnswer(choices: [.practice, .gym], practice: .hard), on: morning, calendar: calendar)
        XCTAssertTrue(PracticeSchedule.hasPractice(on: morning, calendar: calendar))
        XCTAssertEqual(DayChoiceStore.answer(on: morning, calendar: calendar)?.practice, .hard)
        // "Let AthleteOS decide": nothing stored, the schedule decides again.
        DayChoiceStore.set(DayAnswer(choices: [.auto]), on: morning, calendar: calendar)
        XCTAssertNil(DayChoiceStore.answer(on: morning, calendar: calendar))
        XCTAssertNil(DayChoiceStore.saysGame(on: morning, calendar: calendar))
        XCTAssertEqual(PracticeSchedule.hasPractice(on: morning, calendar: calendar), scheduled)
    }

    func testTheEveningReflectionFeedsTomorrow() {
        let evening = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 21))!
        MindsetStore.saveEvening(hardness: 4, body: 3, practice: 3, wentWell: ["Effort", "Focus"], needsWork: ["Speed"],
                                 learned: "  Call for the ball earlier ", on: evening, calendar: calendar)
        let saved = MindsetStore.reflection(on: evening, calendar: calendar)
        XCTAssertEqual(saved?.win, "Effort, Focus")
        XCTAssertEqual(saved?.lesson, "Speed")
        XCTAssertEqual(saved?.learned, "Call for the ball earlier")
        XCTAssertEqual(MindsetStore.yesterdaySignal(now: morning, calendar: calendar), EveningSignal(hardness: 4, body: 3))
    }

    func testTheDayCountsWhatsDone() {
        let day = DayCompletion(checkedIn: true, trained: true, learned: false, reflected: true)
        XCTAssertEqual(day.doneCount, 3)
        XCTAssertEqual(day.items.map(\.title), ["Morning check-in", "Training", "Read or learn", "Evening reflection"])
        XCTAssertEqual(day.nextToDo, .lesson)
        XCTAssertNil(DayCompletion(checkedIn: true, trained: true, learned: true, reflected: true).nextToDo)
    }

    // MARK: - Coming back after pain

    func testAfterPainTrainingStaysLighterUntilTheAthleteSaysItsGone() {
        let calendar = Calendar(identifier: .gregorian)
        let painDay = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        func day(_ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: painDay)! }
        let knee = [PainReport(day: DayKey.of(painDay, calendar: calendar), areas: [.knee], level: .little)]

        XCTAssertNil(PainFollowUp.pending(reports: knee, resolvedDays: [], today: painDay, calendar: calendar), "the pain day itself is handled as pain")
        XCTAssertEqual(PainFollowUp.pending(reports: knee, resolvedDays: [], today: day(1), calendar: calendar), knee[0])
        XCTAssertEqual(PainFollowUp.pending(reports: knee, resolvedDays: [], today: day(10), calendar: calendar), knee[0],
                       "no countdown: time alone doesn't make it safe")
        XCTAssertNil(PainFollowUp.pending(reports: knee, resolvedDays: [DayKey.of(day(2), calendar: calendar)], today: day(3), calendar: calendar),
                     "the athlete said it's gone")
        XCTAssertEqual(PainFollowUp.pending(reports: knee, resolvedDays: [DayKey.of(painDay, calendar: calendar)], today: day(1), calendar: calendar), knee[0],
                       "only a later \"no pain\" counts")

        let head = [PainReport(day: DayKey.of(painDay, calendar: calendar), areas: [.head], level: .little)]
        XCTAssertNil(PainFollowUp.pending(reports: head, resolvedDays: [], today: day(1), calendar: calendar), "the concussion steps decide")

        let lighter = DailyLoop.readiness(answers: nil, personalBand: nil, pain: nil, yesterday: nil, painFollowUp: knee[0])
        XCTAssertEqual(lighter?.level, .reduced)
        XCTAssertTrue(lighter?.reason.contains("until you tell us") == true)
        XCTAssertFalse(lighter?.reason.lowercased().contains("injur") == true, "never a diagnosis")
    }

    /// The evening's "Something hurt" joins the day's report: every area,
    /// the higher level — said twice is never said less.
    func testEveningPainJoinsTheDaysReport() {
        let morning = PainReport(day: "2026-11-27", areas: [.knee], level: .some)
        let evening = PainReport.joining(morning, day: "2026-11-27", areas: [.ankle], level: .little)
        XCTAssertEqual(evening.areas, [.knee, .ankle])
        XCTAssertEqual(evening.level, .some)
        let fresh = PainReport.joining(nil, day: "2026-11-27", areas: [.head], level: .lot)
        XCTAssertEqual(fresh.areas, [.head])
        XCTAssertEqual(fresh.level, .lot)
        XCTAssertTrue(fresh.involvesHead)
    }
}
