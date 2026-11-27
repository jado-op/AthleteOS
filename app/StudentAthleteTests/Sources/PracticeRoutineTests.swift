import XCTest
#if canImport(Engine)
@testable import Engine
#endif

/// Practice days are proposed after 3 of 4 weeks, never assumed; yesterday is asked once.
final class PracticeRoutineTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }()
    private let now = Date(timeIntervalSince1970: 1_800_014_400) // Friday 2027-01-15 12:00 UTC

    private func day(_ back: Int) -> Date { calendar.date(byAdding: .day, value: -back, to: now)! }

    func testThreeOfFourWeeksMakesARoutine() {
        // Tuesdays 2027-01-12 (this week: ignored), 01-05, 12-29, 12-22; Thursday once.
        let days = [day(3), day(10), day(17), day(24), day(15)]
        let inferred = PracticeRoutine.inferredWeekdays(days, now: now, calendar: calendar)
        XCTAssertEqual(inferred, [3], "Tuesday only; this week's doesn't count, one Thursday isn't a routine")
        let two = PracticeRoutine.inferredWeekdays([day(10), day(17)], now: now, calendar: calendar)
        XCTAssertTrue(two.isEmpty)
        let old = PracticeRoutine.inferredWeekdays([day(10), day(17), day(38)], now: now, calendar: calendar)
        XCTAssertTrue(old.isEmpty, "older than four weeks doesn't count")
    }

    func testProposalRespectsCalendarScheduleAndNo() {
        XCTAssertEqual(PracticeRoutine.proposal(inferred: [3, 5], current: [3], hasCalendar: false, declinedUntil: nil, now: now), [5])
        XCTAssertTrue(PracticeRoutine.proposal(inferred: [3, 5], current: [], hasCalendar: true, declinedUntil: nil, now: now).isEmpty)
        XCTAssertTrue(PracticeRoutine.proposal(inferred: [3], current: [], hasCalendar: false,
                                               declinedUntil: now.addingTimeInterval(86_400), now: now).isEmpty)
        XCTAssertEqual(PracticeRoutine.proposal(inferred: [3], current: [], hasCalendar: false,
                                                declinedUntil: now.addingTimeInterval(-1), now: now), [3])
    }

    func testNamesRunMondayFirst() {
        XCTAssertEqual(PracticeRoutine.names([5, 3], calendar: calendar), "Tuesday and Thursday")
        XCTAssertEqual(PracticeRoutine.names([1, 2, 4], calendar: calendar), "Monday, Wednesday and Sunday")
    }

    func testYesterdayIsAskedOnlyWhenScheduledUnloggedAndUnanswered() {
        let yesterday = calendar.startOfDay(for: day(1))
        XCTAssertEqual(PracticeRoutine.dayToAsk(now: now, hadPractice: { _ in true }, logged: { _ in false }, answered: { _ in false },
                                                calendar: calendar), yesterday)
        XCTAssertNil(PracticeRoutine.dayToAsk(now: now, hadPractice: { _ in false }, logged: { _ in false }, answered: { _ in false }, calendar: calendar))
        XCTAssertNil(PracticeRoutine.dayToAsk(now: now, hadPractice: { _ in true }, logged: { _ in true }, answered: { _ in false }, calendar: calendar))
        XCTAssertNil(PracticeRoutine.dayToAsk(now: now, hadPractice: { _ in true }, logged: { _ in false }, answered: { _ in true }, calendar: calendar))
        XCTAssertNil(PracticeRoutine.Answer.didntGo.hard)
        XCTAssertEqual(PracticeRoutine.Answer.hard.hard, 4)
    }
}
