import XCTest

/// Campus's weekly lesson count and spaced review.
final class CampusExtrasTests: XCTestCase {
    private var defaults: UserDefaults!
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "CampusExtrasTests")
        defaults.removePersistentDomain(forName: "CampusExtrasTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "CampusExtrasTests")
        super.tearDown()
    }

    private func day(_ d: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: 12))! }

    func testWeeksStartOnMondayForEveryone() {
        XCTAssertEqual(CampusLog.weekKey(day(24), calendar: calendar), "2026-09-21")
        XCTAssertEqual(CampusLog.weekKey(day(27), calendar: calendar), "2026-09-21", "Sunday belongs to the week that started Monday")
        defaults.set(120, forKey: "campus.xp")
        CampusLog.recordLesson(on: day(24), calendar: calendar, defaults: defaults)
        CampusLog.recordLesson(on: day(27), calendar: calendar, defaults: defaults)
        XCTAssertEqual(CampusLog.lessons(inWeekOf: day(22), calendar: calendar, defaults: defaults), 2)
        XCTAssertNil(defaults.object(forKey: "campus.xp"), "retired points are cleared")
    }

    func testReviewsComeBackLaterWhenRightAndTomorrowWhenWrong() {
        let ids = campusTopics[0].lessons.map(\.id)
        CampusReview.schedule(ids[0], today: day(24), calendar: calendar, defaults: defaults)
        XCTAssertTrue(CampusReview.due(learned: [ids[0]], today: day(24), calendar: calendar, defaults: defaults).isEmpty)
        XCTAssertEqual(CampusReview.due(learned: [ids[0]], today: day(25), calendar: calendar, defaults: defaults), [ids[0]])
        CampusReview.record(reviewed: [ids[0], ids[1]], wrong: [ids[1]], today: day(25), calendar: calendar, defaults: defaults)
        XCTAssertEqual(CampusReview.due(learned: [ids[0], ids[1]], today: day(26), calendar: calendar, defaults: defaults), [ids[1]])
        let questions = CampusReview.questions(for: [ids[0]], today: day(25), calendar: calendar)
        XCTAssertEqual(questions.count, 2)
        XCTAssertEqual(CampusReview.lesson(of: questions[0]), ids[0])
    }
}
