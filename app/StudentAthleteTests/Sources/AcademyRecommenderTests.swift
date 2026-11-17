import XCTest
#if canImport(Engine)
@testable import Engine
#endif

final class AcademyRecommenderTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_800_000_000)

    private func lesson(_ id: String, _ pillar: TwinPillar, sports: [String] = ["all"], phases: [String] = ["all"],
                        requires: [String] = [], ages: (Int, Int) = (13, 19)) -> AcademyLesson {
        AcademyLesson(
            id: id, title: id, pillar: pillar, sports: sports, minAge: ages.0, maxAge: ages.1, phases: phases, requires: requires,
            minutes: 4, support: pillar == .mind,
            sections: [AcademySection(heading: "One", body: "Text")], legend: nil,
            questions: [AcademyQuestion(id: "q1", kind: .knowledge, prompt: "?", explain: "Because",
                                        options: [AcademyOption(text: "Yes", correct: true,
                                                                effects: [TwinEffectSpec(pillar: pillar, side: .knowledge, delta: 5)]),
                                                  AcademyOption(text: "No", correct: false, effects: [])]),
                        AcademyQuestion(id: "q2", kind: .reflection, prompt: "How?", explain: nil,
                                        options: [AcademyOption(text: "Well", correct: false,
                                                                effects: [TwinEffectSpec(pillar: pillar, side: .habits, delta: 4)]),
                                                  AcademyOption(text: "Not yet", correct: false, effects: [])])],
            completion: [TwinEffectSpec(pillar: pillar, side: .knowledge, delta: 3)], sources: [])
    }

    private func twin(_ scores: [TwinPillar: Int]) -> TwinSnapshot {
        let ledger = scores.flatMap { entry -> [TwinEffect] in
            [TwinEffect(date: day, source: "t", spec: TwinEffectSpec(pillar: entry.key, side: .knowledge, delta: entry.value)),
             TwinEffect(date: day, source: "t", spec: TwinEffectSpec(pillar: entry.key, side: .habits, delta: entry.value))]
        }
        return TwinScoring.snapshot(ledger, sportAreas: [])
    }

    private let balanced: [TwinPillar: Int] = [.body: 50, .fuel: 50, .recovery: 50, .mind: 50, .legends: 50, .sportIQ: 50]

    func testTheWeakestDimensionLeadsWithItsReason() {
        var scores = balanced
        scores[.recovery] = 10
        let lessons = [lesson("fuel-1", .fuel), lesson("recovery-1", .recovery), lesson("mind-1", .mind)]
        let top = AcademyRecommender.recommend(lessons, snapshot: twin(scores), learner: AcademyLearner(sportSlug: "soccer"))
        XCTAssertEqual(top.first?.lesson.id, "recovery-1")
        XCTAssertEqual(top.first?.reason, "Your recovery battery is lowest")
    }

    func testGoalsLiftAPillar() {
        let lessons = [lesson("fuel-1", .fuel), lesson("mind-1", .mind)]
        let top = AcademyRecommender.recommend(lessons, snapshot: twin(balanced),
                                               learner: AcademyLearner(sportSlug: "soccer", goals: [.mind]))
        XCTAssertEqual(top.first?.lesson.id, "mind-1")
        XCTAssertEqual(top.first?.reason, "You chose Mind as a goal")
    }

    func testOwnSportBeatsAllSportsAndOtherSportsAreLeftOut() {
        let lessons = [lesson("all", .sportIQ), lesson("soccer", .sportIQ, sports: ["soccer"]), lesson("hoops", .sportIQ, sports: ["basketball"])]
        let top = AcademyRecommender.recommend(lessons, snapshot: twin(balanced),
                                               learner: AcademyLearner(sportSlug: "soccer", sportName: "Soccer"))
        XCTAssertEqual(top.map(\.lesson.id), ["soccer", "all"])
        XCTAssertEqual(top.first?.reason, "Made for Soccer")
    }

    func testSeasonPhaseCounts() {
        let lessons = [lesson("in", .fuel, phases: ["inSeason"]), lesson("off", .fuel, phases: ["offSeason"])]
        let inSeason = AcademyRecommender.recommend(lessons, snapshot: twin(balanced), learner: AcademyLearner(phase: .inSeason))
        XCTAssertEqual(inSeason.first?.lesson.id, "in")
        let offSeason = AcademyRecommender.recommend(lessons, snapshot: twin(balanced), learner: AcademyLearner(phase: .offSeason))
        XCTAssertEqual(offSeason.first?.lesson.id, "off")
    }

    func testCompletedLessonsAndUnmetPrerequisitesAreLeftOut() {
        let lessons = [lesson("a", .mind), lesson("b", .mind, requires: ["a"]), lesson("c", .fuel)]
        let first = AcademyRecommender.recommend(lessons, snapshot: twin(balanced), learner: AcademyLearner())
        XCTAssertFalse(first.contains { $0.lesson.id == "b" })
        let later = AcademyRecommender.recommend(lessons, snapshot: twin(balanced), learner: AcademyLearner(completed: ["a"]))
        XCTAssertTrue(later.contains { $0.lesson.id == "b" })
        XCTAssertFalse(later.contains { $0.lesson.id == "a" })
    }

    func testAgeRangeIsRespected() {
        let lessons = [lesson("older", .fuel, ages: (16, 19)), lesson("all-ages", .fuel)]
        let top = AcademyRecommender.recommend(lessons, snapshot: twin(balanced), learner: AcademyLearner(age: 14))
        XCTAssertEqual(top.map(\.lesson.id), ["all-ages"])
    }

    func testTopThreeHoldAtMostTwoPerPillar() {
        var scores = balanced
        scores[.recovery] = 0
        let lessons = [lesson("r1", .recovery), lesson("r2", .recovery), lesson("r3", .recovery), lesson("f1", .fuel)]
        let top = AcademyRecommender.recommend(lessons, snapshot: twin(scores), learner: AcademyLearner())
        XCTAssertEqual(top.count, 3)
        XCTAssertEqual(top.filter { $0.lesson.pillar == .recovery }.count, 2)
        XCTAssertTrue(top.contains { $0.lesson.id == "f1" })
    }

    func testNextLessonForAPillar() {
        let lessons = [lesson("m1", .mind), lesson("f1", .fuel)]
        XCTAssertEqual(AcademyRecommender.next(for: .fuel, lessons, snapshot: twin(balanced), learner: AcademyLearner())?.id, "f1")
        XCTAssertNil(AcademyRecommender.next(for: .legends, lessons, snapshot: twin(balanced), learner: AcademyLearner()))
    }

    // MARK: Store

    func testFinishingALessonAddsTheChosenAnswersOnce() {
        let recovery = lesson("r1", .recovery)
        var state = AcademyStore.completing(recovery, answers: ["q1": 0, "q2": 0], in: AcademyState(), at: day)
        let twinNow = TwinScoring.snapshot(state.ledger, sportAreas: [])
        XCTAssertEqual(twinNow.score(.recovery).knowledge, 8)
        XCTAssertEqual(twinNow.score(.recovery).habits, 4)
        XCTAssertNotNil(state.completed["r1"])
        state = AcademyStore.completing(recovery, answers: ["q1": 0, "q2": 0], in: state, at: day.addingTimeInterval(60))
        XCTAssertEqual(TwinScoring.snapshot(state.ledger, sportAreas: []).score(.recovery).knowledge, 8)
    }

    func testAWrongAnswerStillFinishesTheLesson() {
        let state = AcademyStore.completing(lesson("f1", .fuel), answers: ["q1": 1, "q2": 1], in: AcademyState(), at: day)
        XCTAssertEqual(TwinScoring.snapshot(state.ledger, sportAreas: []).score(.fuel).knowledge, 3)
    }

    func testStateRoundTripsAndDeletes() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AcademyRecommenderTests"))
        defaults.removePersistentDomain(forName: "AcademyRecommenderTests")
        var state = AcademyStore.completing(lesson("f1", .fuel), answers: ["q1": 0], in: AcademyState(), at: day)
        state.goals = [.mind]
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
        let counts = defaults.dictionary(forKey: "usage.counts") as? [String: Int]
        XCTAssertEqual(counts, ["academy.lesson_completed": 2])
        XCTAssertEqual(Set(AcademyEvent.allCases.map(\.rawValue)),
                       ["twin_viewed", "body_zone_tapped", "lesson_completed", "reflection_submitted", "twin_born"])
    }

    func testTheBetaIsUnlimitedButALimitCanBeSwitchedOn() {
        XCTAssertNil(AcademyAccess.freeLessonsPerDay)
        XCTAssertTrue(AcademyAccess.canStartLesson(finishedToday: 50, isPro: false))
        XCTAssertFalse(AcademyAccess.canStartLesson(finishedToday: 2, isPro: false, limit: 2))
        XCTAssertTrue(AcademyAccess.canStartLesson(finishedToday: 2, isPro: true, limit: 2))
    }

    // MARK: Content and support

    func testTheSeedContentDecodesAndCoversEveryPillar() {
        let pack = AcademyContent.pack
        XCTAssertEqual(pack.lessons.count, 12)
        for pillar in TwinPillar.allCases {
            XCTAssertEqual(pack.lessons.filter { $0.pillar == pillar }.count, 2, pillar.rawValue)
        }
        XCTAssertTrue(pack.lessons.allSatisfy { (2...4).contains($0.questions.count) && $0.minAge >= 13 })
        XCTAssertTrue(pack.lessons.filter { $0.pillar == .mind }.allSatisfy(\.support))
        XCTAssertFalse(AcademyContent.areas(forSport: "soccer").isEmpty)
        XCTAssertEqual(AcademyContent.areas(forSport: "curling"), AcademyContent.areas(forSport: nil))
        XCTAssertNotNil(AcademyContent.trait("vision"))
    }

    func testSupportResourcesByCountry() {
        XCTAssertEqual(SupportResources.resource(region: "DE").display, "116 111")
        XCTAssertEqual(SupportResources.resource(region: "de").name, "Nummer gegen Kummer")
        XCTAssertEqual(SupportResources.resource(region: "US").phone, "988")
        XCTAssertNil(SupportResources.resource(region: "ZZ").phone)
        XCTAssertNil(SupportResources.resource(region: nil).phone)
    }
}
