import XCTest
#if canImport(Engine)
@testable import Engine
#endif

/// V6 §19: after the reflection, one small true thing back — or nothing.
final class ReflectionInsightTests: XCTestCase {
    private func r(_ day: String, hardness: Int? = nil, body: Int? = nil, practice: Int? = nil, wentWell: [String] = [], needsWork: [String] = []) -> Reflection {
        Reflection(day: day, win: "", lesson: "", feeling: nil, hardness: hardness, body: body, practice: practice,
                   wentWell: wentWell, needsWork: needsWork, learned: nil)
    }

    func testAnOrdinaryDayGivesNothingBack() {
        XCTAssertNil(ReflectionInsight.make(today: r("2026-10-02", hardness: 2, body: 1, practice: 3), recent: [], practiceToday: true))
    }

    func testAHarderThanUsualPracticeSaysTheSessionChanged() {
        let week = (1...4).map { r("2026-09-2\($0)", hardness: 2) }
        let insight = ReflectionInsight.make(today: r("2026-10-02", hardness: 4), recent: week, practiceToday: true)
        XCTAssertEqual(insight?.key, "hard")
        XCTAssertTrue(insight?.text.contains("adjusted") ?? false)
    }

    func testSomethingHurtComesFirst() {
        XCTAssertEqual(ReflectionInsight.make(today: r("2026-10-02", hardness: 4, body: 4), recent: [], practiceToday: true)?.key, "hurt")
    }

    func testARepeatedStrengthIsNoticed() {
        let week = [r("2026-09-30", wentWell: ["Focus"]), r("2026-10-01", wentWell: ["Focus"])]
        let insight = ReflectionInsight.make(today: r("2026-10-02", wentWell: ["Focus"]), recent: week, practiceToday: false)
        XCTAssertEqual(insight?.key, "well-Focus")
    }

    func testTheSameInsightIsNotShownTwiceInARow() {
        let week = (1...4).map { r("2026-09-2\($0)", hardness: 2) }
        XCTAssertNil(ReflectionInsight.make(today: r("2026-10-02", hardness: 4), recent: week, practiceToday: true, lastShown: "hard"))
    }

    func testAVeryHardEveningLightensTomorrow() {
        let demands = SportDemandsTable.demands(sport: nil, position: nil)
        let day = TrainingDay(date: .now, phase: .offSeason, age: 16, experience: .intermediate, demands: demands,
                              reflection: ReflectionSignal(dayFelt: 4, bodyFelt: 3))
        let decision = SessionPlanner.decide(day)
        XCTAssertTrue(decision.reasons.contains(.reflectionVeryHard))
        XCTAssertTrue(decision.reasons.contains(.belowNormalReadiness))
        XCTAssertLessThan(decision.durationTarget, 65)
    }

    /// The evening's practice answer becomes the practice log: Poor … Great on
    /// the log's 2 … 5, and a practice only told in the evening takes its effort
    /// from how hard the day felt.
    func testTheEveningPracticeAnswerMapsOntoThePracticeLog() {
        XCTAssertEqual((1...4).map(EveningOptions.practiceWent), [2, 3, 4, 5])
        XCTAssertEqual(EveningOptions.practiceHard(dayHardness: 1), 2)
        XCTAssertEqual(EveningOptions.practiceHard(dayHardness: 4), 5)
        XCTAssertEqual(EveningOptions.practiceHard(dayHardness: nil), 3)
        XCTAssertEqual(EveningOptions.practice.count + 1, EveningOptions.didntGo, "Didn't go is the fifth answer")
    }

    /// "Didn't go" in the evening is remembered for that day, so reopening
    /// shows it and it can still be changed.
    func testTheEveningsDidntGoIsRemembered() {
        let defaults = UserDefaults(suiteName: "evening-practice-\(UUID().uuidString)")!
        XCTAssertFalse(EveningPractice.skipped(on: "2026-11-27", defaults))
        EveningPractice.setSkipped(true, on: "2026-11-27", defaults)
        XCTAssertTrue(EveningPractice.skipped(on: "2026-11-27", defaults))
        XCTAssertFalse(EveningPractice.skipped(on: "2026-11-26", defaults))
        EveningPractice.setSkipped(false, on: "2026-11-27", defaults)
        XCTAssertFalse(EveningPractice.skipped(on: "2026-11-27", defaults))
    }

    /// Practice asks its own effort (CR-10), so "how hard did today feel" is
    /// asked only for training whose effort isn't known yet; the day's hardness
    /// for tomorrow follows from the effort.
    func testTheDaysHardnessComesFromSessionEffort() {
        XCTAssertEqual([0, 3, 4, 5, 6, 7, 8, 10].map(EveningOptions.hardness(fromRPE:)), [1, 1, 2, 2, 3, 3, 4, 4])
        XCTAssertFalse(EveningOptions.asksHardness(restDay: false, trained: false, trainedEffort: nil, game: false), "practice alone asks its own effort")
        XCTAssertFalse(EveningOptions.asksHardness(restDay: false, trained: true, trainedEffort: 7, game: false), "a rated workout already said it")
        XCTAssertTrue(EveningOptions.asksHardness(restDay: false, trained: true, trainedEffort: nil, game: false))
        XCTAssertTrue(EveningOptions.asksHardness(restDay: false, trained: false, trainedEffort: nil, game: true))
        XCTAssertFalse(EveningOptions.asksHardness(restDay: true, trained: false, trainedEffort: nil, game: false))
    }
}
