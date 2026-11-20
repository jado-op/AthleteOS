import XCTest
#if canImport(Engine)
@testable import Engine
#endif

/// A workout from Apple Health: does it count, what did it train, and how
/// long each region wants afterwards (owner, 2026-11-20).
final class WorkoutTaggingTests: XCTestCase {
    func testWhatCountsAsTheDaysTraining() {
        XCTAssertTrue(WorkoutTagging.countsAsTraining(activity: "Strength training", minutes: 40))
        XCTAssertTrue(WorkoutTagging.countsAsTraining(activity: "Run", minutes: 20))
        XCTAssertFalse(WorkoutTagging.countsAsTraining(activity: "Run", minutes: 10), "a jog to the bus isn't training")
        XCTAssertFalse(WorkoutTagging.countsAsTraining(activity: "Walk", minutes: 30))
        XCTAssertTrue(WorkoutTagging.countsAsTraining(activity: "Walk", minutes: 60))
    }

    func testRegionsAreGuessedFromTheActivity() {
        XCTAssertEqual(WorkoutTagging.guessedRegions(activity: "Soccer"), [.lower])
        XCTAssertEqual(WorkoutTagging.guessedRegions(activity: "Run"), [.lower])
        XCTAssertEqual(WorkoutTagging.guessedRegions(activity: "Swim"), [.upper, .lower])
        XCTAssertEqual(WorkoutTagging.guessedRegions(activity: "Strength training"), [], "a gym session: the athlete says")
    }

    func testTheScaleKeepsFostersWords() {
        XCTAssertEqual(WorkoutTagging.word(5), "Hard")
        XCTAssertEqual(WorkoutTagging.word(6), "Hard")
        XCTAssertEqual(WorkoutTagging.word(8), "Very hard")
        XCTAssertEqual(WorkoutTagging.word(10), "Maximal")
        XCTAssertEqual(WorkoutTagging.band(forRating: 3), .light)
        XCTAssertEqual(WorkoutTagging.band(forRating: 6), .solid)
        XCTAssertEqual(WorkoutTagging.band(forRating: 7), .veryHard)
    }

    func testTickedRegionsTakeTheOverallEffortUnlessRatedApart() {
        let answer = WorkoutTagging.Answer(rating: 7, regions: [.upper: .veryHard, .core: .light])
        let bands = WorkoutTagging.effectiveBands(answer, minutes: 50)
        XCTAssertEqual(bands[.upper], .veryHard)
        XCTAssertEqual(bands[.core], .light)
        XCTAssertNil(bands[.lower])
    }

    func testCardioIsLegsOneBandEasierUnlessVeryHard() {
        XCTAssertEqual(WorkoutTagging.effectiveBands(.init(rating: 5, cardio: true), minutes: 40)[.lower], .light)
        XCTAssertEqual(WorkoutTagging.effectiveBands(.init(rating: 8, cardio: true), minutes: 40)[.lower], .veryHard)
    }

    func testLongSessionsAndPainCountHarder() {
        let solid = WorkoutTagging.Answer(rating: 5, regions: [.lower: .solid])
        XCTAssertEqual(WorkoutTagging.effectiveBands(solid, minutes: 100)[.lower], .veryHard)
        var hurt = solid
        hurt.hurt = true
        XCTAssertEqual(WorkoutTagging.effectiveBands(hurt, minutes: 40)[.lower], .veryHard)
    }

    func testRecoveryByRegionAndEffort() {
        XCTAssertEqual(WorkoutTagging.recoveryDays(.lower, after: .light), 1)
        XCTAssertEqual(WorkoutTagging.recoveryDays(.lower, after: .solid), 2)
        XCTAssertEqual(WorkoutTagging.recoveryDays(.lower, after: .veryHard), 3)
        XCTAssertEqual(WorkoutTagging.recoveryDays(.upper, after: .veryHard), 2)
        XCTAssertEqual(WorkoutTagging.recoveryDays(.core, after: .light), 0)
    }

    func testTheAnswerSurvivesSaving() throws {
        let answer = WorkoutTagging.Answer(rating: 6, regions: [.lower: .solid], hurt: false, exercises: ["back-squat"])
        let data = try JSONEncoder().encode(answer)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutTagging.Answer.self, from: data), answer)
    }

    func testAskedOnlyWithinADay() {
        let end = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertTrue(WorkoutTagging.stillAskable(workoutEnd: end, now: end.addingTimeInterval(20 * 3600)))
        XCTAssertFalse(WorkoutTagging.stillAskable(workoutEnd: end, now: end.addingTimeInterval(30 * 3600)))
    }

    func testALightLegSessionYesterdayLeavesLegsOpenToday() {
        let day = TrainingDay(date: Date(timeIntervalSince1970: 1_790_000_000), phase: .offSeason, age: 16, experience: .intermediate,
                              demands: SportDemandsTable.demands(sport: nil, position: nil), practice: nil, daysToNextGame: nil,
                              plannedGymDay: true)
        let light = GymHistory(daysSince: [.lower: 1, .upper: 6], recoveryOverride: [.lower: 1])
        XCTAssertNil(GymAdvisor.advise(day: day, history: light).notToday[.lower])
        let hard = GymHistory(daysSince: [.lower: 1, .upper: 6], recoveryOverride: [.lower: 3])
        XCTAssertNotNil(GymAdvisor.advise(day: day, history: hard).notToday[.lower])
    }

    func testARunLightsTheLegsBeforeAnyAnswer() {
        let guess = WorkoutTagging.guessedAnswer(activity: "Run")
        XCTAssertEqual(WorkoutTagging.trainedBands(guess), [.lower: .light])
        XCTAssertEqual(WorkoutTagging.trainedBands(WorkoutTagging.guessedAnswer(activity: "Swim")), [.upper: .light, .lower: .light])
        XCTAssertTrue(WorkoutTagging.trainedBands(WorkoutTagging.guessedAnswer(activity: "Strength training")).isEmpty,
                      "a gym session stays dark until the athlete says what it trained")
    }

    func testARegionAnswerReachesTheBodyMap() {
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        let sets = MuscleTraining.regionSets(date: day, label: "Strength training", bands: [.lower: .veryHard, .core: .light])
        let report = MuscleTraining.report(sets, now: day.addingTimeInterval(3600))
        let trained = Set(report.groups.filter { $0.sets > 0 }.map(\.group))
        XCTAssertEqual(trained, [.glutes, .quads, .hamstrings, .calves, .core])
        XCTAssertEqual(report.groups.first { $0.group == .quads }?.sets, Double(WorkoutTagging.bodyMapSets(.veryHard)))
        XCTAssertGreaterThan(report.workouts, 0)
        XCTAssertFalse(report.brightness.isEmpty)
    }

    func testTheTwinSaysWhenARegionIsReadyAgain() {
        let history = GymHistory(daysSince: [.lower: 1, .upper: 1, .core: 1], recoveryOverride: [.lower: 3, .upper: 2])
        let resting = history.stillRecovering
        XCTAssertEqual(resting.map(\.region), [.lower, .upper])
        XCTAssertEqual(resting.map(\.days), [2, 1])
        XCTAssertTrue(GymHistory(daysSince: [.lower: 4]).stillRecovering.isEmpty)
    }

    func testTheSummarySaysWhenEachPartIsReady() {
        let answer = WorkoutTagging.Answer(rating: 8, regions: [.lower: .veryHard, .core: .light])
        let ready = WorkoutTagging.readyAfter(answer, minutes: 50)
        XCTAssertEqual(ready.map(\.region), [.lower, .core])
        XCTAssertEqual(ready.map(\.days), [3, 0])
        XCTAssertEqual(WorkoutTagging.feel(5), "Talking only in short phrases.")
        XCTAssertEqual(WorkoutTagging.symbol(forActivity: "Run"), "figure.run")
    }
}
