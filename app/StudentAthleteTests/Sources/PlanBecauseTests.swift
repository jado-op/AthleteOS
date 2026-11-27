import XCTest
#if canImport(Engine)
@testable import Engine
#endif

/// The lock screen's short "because" and the week that bends.
final class PlanBecauseTests: XCTestCase {
    func testTheBecauseLineKeepsTheTwoThingsThatMatterMost() {
        XCTAssertEqual(PlanExplanation.because([.noPracticeToday, .gameWithin48h, .lowerBodyFatigue], event: "Match"),
                       "Match in 2 days · Legs tired")
        XCTAssertEqual(PlanExplanation.because([.hardTeamPractice]), "Hard practice")
        XCTAssertNil(PlanExplanation.because([.beginner]))
    }

    func testAWeekThatBendsSaysWhatMovedWhere() {
        let calendar = Calendar(identifier: .gregorian)
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23))!
        func day(_ i: Int, _ kind: WeekBend.Day.Kind, _ workout: String? = nil, _ minutes: Int? = nil) -> WeekBend.Day {
            WeekBend.Day(date: calendar.date(byAdding: .day, value: i, to: monday)!, kind: kind, workout: workout, minutes: minutes)
        }
        let before = [day(0, .gym, "Lower body", 60), day(1, .practice), day(2, .rest), day(3, .gym, "Upper body", 45),
                      day(4, .practice), day(5, .rest), day(6, .rest)]
        let after = [day(0, .blocked), day(1, .practice), day(2, .gym, "Lower body", 60), day(3, .gym, "Upper body", 30),
                     day(4, .practice), day(5, .game), day(6, .rest)]
        let changes = WeekBend.changes(before: before, after: after, event: "Match", calendar: calendar)
        XCTAssertEqual(changes[0], "You can't train")
        XCTAssertEqual(changes[2]?.hasPrefix("Moved here from"), true)
        XCTAssertEqual(changes[3], "Shorter: 45 → 30 min")
        XCTAssertEqual(changes[5], "Match added")
        XCTAssertNil(changes[1])
        XCTAssertNil(changes[6])
    }
}
