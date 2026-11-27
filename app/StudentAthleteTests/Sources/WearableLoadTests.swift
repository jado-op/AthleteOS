import XCTest

/// Watch and band workouts: effort from heart rate, a lighter day after a
/// hard one, and practice logged from the watch.
final class WearableLoadTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 22))! }
    private func at(_ hour: Double, minutes: Int, heartRate: Double?, activity: String = "Run") -> ExternalWorkout {
        let start = day.addingTimeInterval(hour * 3600)
        return ExternalWorkout(start: start, end: start.addingTimeInterval(Double(minutes) * 60), activity: activity, averageHeartRate: heartRate)
    }

    func testEffortFollowsHeartRateAgainstAgePredictedMax() {
        // 16 years old: max ≈ 196.8
        XCTAssertEqual(WearableLoad.effort(averageHeartRate: 110, minutes: 40, age: 16), 3)
        XCTAssertEqual(WearableLoad.effort(averageHeartRate: 160, minutes: 40, age: 16), 7)
        XCTAssertEqual(WearableLoad.effort(averageHeartRate: 185, minutes: 40, age: 16), 9)
        XCTAssertEqual(WearableLoad.effort(averageHeartRate: nil, minutes: 70, age: 16), 6)
    }

    func testAHardMorningRunMakesTheDayLighterButPracticeDoesNot() {
        let now = day.addingTimeInterval(16 * 3600)
        let run = at(7, minutes: 45, heartRate: 165)
        XCTAssertNotNil(WearableLoad.reason([run], now: now, age: 16, practiceToday: nil, calendar: calendar))
        XCTAssertNil(WearableLoad.reason([at(7, minutes: 20, heartRate: 110)], now: now, age: 16, practiceToday: nil, calendar: calendar), "an easy jog")
        let practice = PracticeTime(start: 15 * 60, end: 17 * 60)
        let atPractice = at(15, minutes: 90, heartRate: 170, activity: "Soccer")
        XCTAssertNil(WearableLoad.reason([atPractice], now: day.addingTimeInterval(18 * 3600), age: 16, practiceToday: practice, calendar: calendar),
                     "practice itself isn't extra load")
    }

    func testAWatchWorkoutAtPracticeTimeIsLoggedAsPractice() {
        let practice = PracticeTime(start: 15 * 60, end: 17 * 60)
        let log = WearableLoad.practiceLog(from: [at(14.75, minutes: 100, heartRate: 150, activity: "Soccer")], practice: practice,
                                           day: day, sportSlug: "soccer", age: 16, calendar: calendar)
        XCTAssertEqual(log?.minutes, 100)
        XCTAssertEqual(log?.day, "2026-09-22")
        XCTAssertEqual(log?.note, "From your watch")
        XCTAssertEqual(log?.went, 0, "how it went is the athlete's to say, never made up")
        XCTAssertNil(WearableLoad.practiceLog(from: [at(9, minutes: 60, heartRate: 150)], practice: practice, day: day,
                                              sportSlug: "soccer", age: 16, calendar: calendar), "a morning run isn't practice")
    }

    // Any brand through Apple Health: named in the sentence, old saved workouts still decode.
    func testABrandWorkoutIsNamedAndOldSavedWorkoutsStillDecode() throws {
        var run = at(7, minutes: 45, heartRate: 165)
        run.source = "Garmin Connect"
        XCTAssertEqual(run.device, "Garmin")
        let reason = WearableLoad.reason([run], now: day.addingTimeInterval(16 * 3600), age: 16, practiceToday: nil, calendar: calendar)
        XCTAssertEqual(reason, "Your Garmin saw a hard run earlier today, so the gym work is lighter.")
        XCTAssertEqual(ExternalWorkout(start: day, end: day, activity: "Run", averageHeartRate: nil, source: "Dominik's Apple Watch").device, "watch")
        let old = #"[{"start":0,"end":3600,"activity":"Run"}]"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([ExternalWorkout].self, from: old)
        XCTAssertNil(decoded.first?.source)
    }

    func testHeartRateSummary() {
        XCTAssertNil(HeartRateSummary([]))
        XCTAssertEqual(HeartRateSummary([120, 140, 160]), HeartRateSummary(average: 140, max: 160))
    }

    /// The evening's 0–10 practice effort on the log's 1–5.
    func testPracticeEffortMapsOntoTheLogsScale() {
        XCTAssertEqual([0, 1, 2, 5, 9, 10].map(PracticeLog.hard(fromRPE:)), [1, 1, 1, 3, 5, 5])
    }
}
