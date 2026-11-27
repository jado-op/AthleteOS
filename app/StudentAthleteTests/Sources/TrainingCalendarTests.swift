import XCTest
#if canImport(Engine)
@testable import Engine
#endif

/// The calendar shows the past as it happened and the future as planned.
final class TrainingCalendarTests: XCTestCase {
    func testThePastNeverShowsAPlan() {
        var facts = TrainingCalendar.Facts(when: .past)
        facts.plannedWorkout = ("Lower body", 45)
        facts.practiceScheduled = "4:00–6:00 pm"
        let items = TrainingCalendar.items(facts)
        XCTAssertFalse(items.contains { $0.state == .planned })
        XCTAssertEqual(items.map(\.kind), [.practice])
        XCTAssertEqual(items.first?.state, .fromSchedule)
    }

    func testTodayShowsThePlanUntilAWorkoutIsDone() {
        var facts = TrainingCalendar.Facts(when: .today)
        facts.plannedWorkout = ("Upper body", 30)
        XCTAssertEqual(TrainingCalendar.items(facts).first?.state, .planned)
        facts.workoutsDone = [("Upper body", "32 min", false)]
        let items = TrainingCalendar.items(facts)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.state, .done)
    }

    func testAGameComesFirstAndADayOffHidesThePlan() {
        var facts = TrainingCalendar.Facts(when: .future)
        facts.plannedWorkout = ("Full body", 60)
        facts.off = "Can't train"
        XCTAssertEqual(TrainingCalendar.items(facts).map(\.kind), [.off])
        var game = TrainingCalendar.Facts(when: .future)
        game.practiceScheduled = ""
        game.games = [("Match", "3:00 pm")]
        let items = TrainingCalendar.items(game)
        XCTAssertEqual(items.map(\.kind), [.game, .practice])
        XCTAssertEqual(TrainingCalendar.line(items), "Match · 3:00 pm + Practice")
    }

    func testMarksAreOnePerKindAndAtMostThree() {
        var facts = TrainingCalendar.Facts(when: .past)
        facts.workoutsDone = [("Gym", nil, false), ("Gym 2", nil, false), ("Stretch", nil, true)]
        facts.practiceLogged = ""
        facts.games = [("Game", nil)]
        let marks = TrainingCalendar.marks(TrainingCalendar.items(facts))
        XCTAssertEqual(marks.map(\.kind), [.game, .workout, .practice])
    }
}
