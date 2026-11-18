import XCTest

/// Home: the part of the day sets the light, which drifts without jumps, and
/// the week counts right. Today's steps: TodayPlanTests.
final class HomeDayTests: XCTestCase {
    func testThePartsOfTheDay() {
        XCTAssertEqual(DayPhase.at(minute: 4 * 60 + 59), .night)
        XCTAssertEqual(DayPhase.at(minute: 5 * 60), .morning)
        XCTAssertEqual(DayPhase.at(minute: 11 * 60 + 29), .morning)
        XCTAssertEqual(DayPhase.at(minute: 11 * 60 + 30), .day)
        XCTAssertEqual(DayPhase.at(minute: 17 * 60 + 29), .day)
        XCTAssertEqual(DayPhase.at(minute: 17 * 60 + 30), .evening)
        XCTAssertEqual(DayPhase.at(minute: 23 * 60 + 59), .evening)
        XCTAssertEqual(DayPhase.at(minute: 0), .night)
    }

    func testTheLightNeverJumps() {
        // 5:29 pm and 5:31 pm must look the same app: every two minutes, a tiny step.
        for minute in stride(from: 0, to: 1440, by: 2) {
            let a = AmbientLight.at(minute: minute)
            let b = AmbientLight.at(minute: minute + 2)
            XCTAssertLessThan(abs(a.red - b.red) + abs(a.green - b.green) + abs(a.blue - b.blue), 0.03, "minute \(minute)")
            XCTAssertLessThan(abs(a.strength - b.strength), 0.01, "minute \(minute)")
        }
        XCTAssertEqual(AmbientLight.at(minute: 1440), AmbientLight.at(minute: 0), "midnight wraps around")
    }

    func testMorningIsWarmerThanTheDayAndTheEveningDeeper() {
        let morning = AmbientLight.at(minute: 8 * 60)
        let day = AmbientLight.at(minute: 14 * 60)
        let evening = AmbientLight.at(minute: 20 * 60)
        XCTAssertGreaterThan(morning.green, day.green, "warmer: more orange in it")
        XCTAssertLessThan(evening.red, day.red, "deeper crimson")
    }

    func testTheWeekCountsThisWeekOnly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func day(_ d: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: 10))! }
        // Thursday 24 Sep 2026; the week started Monday 21.
        let week = WeekSummary.make(
            now: day(24),
            sessions: [(date: day(21), mobility: false), (date: day(22), mobility: true), (date: day(23), mobility: false), (date: day(18), mobility: false)],
            practiceDays: ["2026-09-22", "2026-09-24", "2026-09-17"],
            checkInDates: [day(21), day(22), day(24), day(20)],
            calendar: calendar
        )
        XCTAssertEqual(week.workouts, 2)
        XCTAssertEqual(week.mobility, 1)
        XCTAssertEqual(week.practices, 2)
        XCTAssertEqual(week.checkIns, 3)
        XCTAssertEqual(week.daysSoFar, 4)
        XCTAssertEqual(week.active, [true, true, true, true, false, false, false])
    }

}
