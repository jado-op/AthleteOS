import XCTest
#if canImport(Engine)
@testable import Engine
#endif

/// The Workout tab's body map: how sets are weighted per muscle group, how
/// often and how long since, the brightness, and the one-line summary.
final class MuscleTrainingTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 18))! }
    private func day(_ back: Int) -> Date { calendar.date(byAdding: .day, value: -back, to: now)! }

    private let squat = ["vastus-lateralis": 0.9, "gluteus-maximus": 0.8, "rectus-femoris": 0.6, "rectus-abdominis": 0.4]
    private let bench = ["pectoralis-major": 1.0, "triceps-brachii": 0.6, "deltoid-anterior": 0.5]
    private let calfRaise = ["gastrocnemius": 1.0, "soleus": 0.7]

    private func sets(_ count: Int, _ name: String, _ muscles: [String: Double], daysAgo: Int) -> [MuscleTraining.LoggedSet] {
        (0..<count).map { _ in MuscleTraining.LoggedSet(date: day(daysAgo), exercise: name, muscles: muscles) }
    }

    func testASetCountsOncePerGroupAtItsStrongestMuscle() {
        // Two quad muscles in one set: one quad set at 0.9, not 1.5.
        let report = MuscleTraining.report(sets(1, "Goblet squat", squat, daysAgo: 0), now: now, calendar: calendar)
        XCTAssertEqual(report.stats(.quads)?.sets ?? 0, 0.9, accuracy: 0.0001)
        XCTAssertEqual(report.stats(.glutes)?.sets ?? 0, 0.8, accuracy: 0.0001)
    }

    func testStabilisersGetNoCredit() {
        let report = MuscleTraining.report(sets(3, "Goblet squat", squat, daysAgo: 0), now: now, calendar: calendar)
        XCTAssertEqual(report.stats(.core)?.sets, 0, "0.4 = stabiliser: a squat is not a core workout")
        XCTAssertNil(report.brightness["rectus-abdominis"])
    }

    func testFrequencyCountsDaysWithAFullSetOverTheWindow() {
        // Squats twice a week for four weeks, bench once a week.
        var all: [MuscleTraining.LoggedSet] = []
        for week in 0..<4 {
            all += sets(3, "Goblet squat", squat, daysAgo: week * 7 + 1)
            all += sets(3, "Goblet squat", squat, daysAgo: week * 7 + 4)
            all += sets(3, "Bench press", bench, daysAgo: week * 7 + 2)
        }
        all += sets(1, "Bench press", bench, daysAgo: 40)  // outside the window
        let report = MuscleTraining.report(all, now: now, calendar: calendar)
        let quads = report.stats(.quads)!
        XCTAssertEqual(quads.daysTrained, 8)
        XCTAssertEqual(quads.timesPerWeek, 2, accuracy: 0.0001)
        XCTAssertEqual(quads.setsPerWeek, 24 * 0.9 / 4, accuracy: 0.0001)
        XCTAssertEqual(quads.rank, 1)
        XCTAssertEqual(report.stats(.chest)?.timesPerWeek ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(report.weeks, 4, accuracy: 0.0001)
        XCTAssertEqual(report.workouts, 12)
        XCTAssertEqual(report.totalSets, 36)
    }

    func testAShortHistoryIsNotSpreadOverFourWeeks() {
        // Started 10 days ago: rates are per the 10 days, not 28.
        let all = sets(3, "Bench press", bench, daysAgo: 9) + sets(3, "Bench press", bench, daysAgo: 2)
        let report = MuscleTraining.report(all, now: now, calendar: calendar)
        XCTAssertEqual(report.weeks, 10.0 / 7, accuracy: 0.0001)
        XCTAssertEqual(report.stats(.chest)?.timesPerWeek ?? 0, 2 / (10.0 / 7), accuracy: 0.0001)
    }

    func testOneWeakSetOnADayDoesNotCountAsTrainingThatGroup() {
        // A single shoulder credit of 0.5 is not a day "trained".
        let report = MuscleTraining.report(sets(1, "Bench press", bench, daysAgo: 1), now: now, calendar: calendar)
        XCTAssertEqual(report.stats(.shoulders)?.daysTrained, 0)
        XCTAssertEqual(report.stats(.chest)?.daysTrained, 1)
        XCTAssertEqual(report.stats(.shoulders)?.daysSince, 1, "but it was last worked yesterday")
    }

    func testDaysSinceLooksBeyondTheWindow() {
        let all = sets(3, "Calf raise", calfRaise, daysAgo: 40) + sets(3, "Bench press", bench, daysAgo: 0)
        let report = MuscleTraining.report(all, now: now, calendar: calendar)
        let calves = report.stats(.calves)!
        XCTAssertEqual(calves.sets, 0)
        XCTAssertEqual(calves.daysSince, 40)
        XCTAssertNil(report.stats(.hamstrings)?.daysSince)
    }

    func testBrightnessIsRelativeAndFadesWithTime() {
        // The same work, two weeks apart: the older one is half as bright.
        let all = sets(3, "Bench press", bench, daysAgo: 0) + sets(3, "Calf raise", calfRaise, daysAgo: 14)
        let report = MuscleTraining.report(all, now: now, calendar: calendar)
        XCTAssertEqual(report.brightness["pectoralis-major"] ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(report.brightness["gastrocnemius"] ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(report.brightness["triceps-brachii"] ?? 0, 0.6, accuracy: 0.0001)
    }

    func testNonDrawableMusclesShowThroughTheirStandIn() {
        let report = MuscleTraining.report(sets(1, "Plank", ["transverse-abdominis": 1.0], daysAgo: 0), now: now, calendar: calendar)
        let via = musclesBySlug["transverse-abdominis"]?.renderVia
        XCTAssertNotNil(via)
        XCTAssertEqual(report.brightness[via ?? ""] ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(report.stats(.core)?.sets, 1)
    }

    func testSharesAddUpToOne() {
        let all = sets(4, "Goblet squat", squat, daysAgo: 1) + sets(2, "Bench press", bench, daysAgo: 2)
        let report = MuscleTraining.report(all, now: now, calendar: calendar)
        XCTAssertEqual(report.groups.map(\.share).reduce(0, +), 1, accuracy: 0.0001)
        XCTAssertEqual(report.groups.count, MuscleGroup.allCases.count)
        XCTAssertEqual(report.groups.map(\.rank), Array(1...MuscleGroup.allCases.count))
    }

    func testTopExercisesAreTheBiggestContributors() {
        let all = sets(4, "Goblet squat", squat, daysAgo: 1) + sets(1, "Lunge", ["vastus-lateralis": 1.0], daysAgo: 2)
        let quads = MuscleTraining.report(all, now: now, calendar: calendar).stats(.quads)!
        XCTAssertEqual(quads.topExercises.map(\.name), ["Goblet squat", "Lunge"])
    }

    // MARK: Summary

    func testSummaryNamesTheMostTrainedGroupHowOftenAndWhatIsLeftOut() {
        var all: [MuscleTraining.LoggedSet] = []
        for week in 0..<4 {
            all += sets(4, "Goblet squat", squat, daysAgo: week * 7 + 1)
            all += sets(4, "Goblet squat", squat, daysAgo: week * 7 + 4)
        }
        let summary = MuscleTraining.report(all, now: now, calendar: calendar).summary
        XCTAssertTrue(summary.hasPrefix("Most of your training goes to your quads and glutes, about twice a week."), summary)
        XCTAssertTrue(summary.contains("haven't been trained in four weeks."), summary)
        XCTAssertLessThanOrEqual(summary.count, 200, "short")
    }

    func testSummaryWithEveryGroupTrainedNamesTheLeast() {
        let everything: [String: Double] = [
            "pectoralis-major": 1, "deltoid-lateral": 1, "latissimus-dorsi": 1, "erector-spinae": 1, "biceps-brachii": 1,
            "rectus-abdominis": 1, "gluteus-maximus": 1, "vastus-lateralis": 1, "biceps-femoris": 1,
        ]
        let all = sets(6, "Full body", everything, daysAgo: 1) + sets(1, "Calf raise", calfRaise, daysAgo: 5)
        let summary = MuscleTraining.report(all, now: now, calendar: calendar).summary
        XCTAssertTrue(summary.hasSuffix("Calves get the least, last 5 days ago."), summary)
    }

    func testSummaryWithNothingLogged() {
        XCTAssertEqual(MuscleTraining.report([], now: now, calendar: calendar).summary,
                       "No workouts logged yet. Log one and your body map fills in here.")
    }

    func testSummaryAfterABreak() {
        let summary = MuscleTraining.report(sets(3, "Bench press", bench, daysAgo: 35), now: now, calendar: calendar).summary
        XCTAssertEqual(summary, "No workouts in the last four weeks. Your chest was trained last, 35 days ago.")
    }

    func testFrequencyWords() {
        XCTAssertEqual(MuscleTraining.frequency(0.5), "less than once a week")
        XCTAssertEqual(MuscleTraining.frequency(1), "about once a week")
        XCTAssertEqual(MuscleTraining.frequency(2), "about twice a week")
        XCTAssertEqual(MuscleTraining.frequency(3.4), "about 3 times a week")
    }

    func testEveryGroupHasMusclesToDraw() {
        for group in MuscleGroup.allCases {
            XCTAssertFalse(group.drawableMuscles.isEmpty, group.rawValue)
        }
    }
}
