import XCTest
#if canImport(Engine)
@testable import Engine
#endif

/// Home shows one next step and today as a numbered plan (docs/CLARITY-PLAN.md).
final class TodayPlanTests: XCTestCase {
    private func plan(_ hour: Int, _ minute: Int = 0, checkedIn: Bool = true, reflected: Bool = false, learned: Bool = false,
                      lessonAvailable: Bool = true, fixed: TodayPlan.FixedPoint? = nil, workoutPlanned: Bool = false,
                      workoutDone: Bool = false, practiceLogged: Bool = false, sick: Bool = false) -> TodayPlan {
        TodayPlan.make(.init(minute: hour * 60 + minute, checkedIn: checkedIn, reflected: reflected, learned: learned,
                             lessonAvailable: lessonAvailable, fixed: fixed, workoutPlanned: workoutPlanned, workoutDone: workoutDone,
                             practiceLogged: practiceLogged, sick: sick))
    }

    private func steps(_ plan: TodayPlan) -> [TodayPlan.Step] { plan.rows.map(\.step) }
    private func state(_ plan: TodayPlan, _ step: TodayPlan.Step) -> TodayPlan.RowState? { plan.rows.first { $0.step == step }?.state }

    func testTheDayStartsWithTheCheckIn() {
        let morning = plan(7, checkedIn: false, workoutPlanned: true)
        XCTAssertEqual(morning.next, .checkIn)
        XCTAssertEqual(steps(morning), [.checkIn, .workout, .lesson, .reflection])
        XCTAssertEqual(morning.rows.map(\.number), [1, 2, 3, 4])
        XCTAssertEqual(state(morning, .checkIn), .now)
        XCTAssertEqual(state(morning, .workout), .open)
        XCTAssertEqual(morning.doneCount, 0)
        XCTAssertEqual(morning.total, 4)
    }

    func testAfterTheCheckInTheWorkoutIsNext() {
        let ready = plan(8, workoutPlanned: true)
        XCTAssertEqual(ready.next, .workout)
        XCTAssertEqual(state(ready, .checkIn), .done)
        XCTAssertEqual(state(ready, .workout), .now)
        XCTAssertEqual(ready.doneCount, 1)
    }

    func testTheWorkoutWaitsForPractice() {
        let practice = TodayPlan.FixedPoint(kind: .practice, start: 16 * 60, end: 17 * 60 + 30)
        let before = plan(14, fixed: practice, workoutPlanned: true)
        XCTAssertEqual(before.next, .lesson, "something useful while practice is still to come")
        XCTAssertEqual(steps(before), [.checkIn, .practice, .workout, .lesson, .reflection])

        let waiting = plan(14, learned: true, fixed: practice, workoutPlanned: true)
        XCTAssertEqual(waiting.next, .waiting(.practice))
        XCTAssertEqual(state(waiting, .practice), .now)
        XCTAssertEqual(state(waiting, .workout), .open)

        let after = plan(17, 45, learned: true, fixed: practice, workoutPlanned: true)
        XCTAssertEqual(after.next, .workout)
        XCTAssertEqual(state(after, .practice), .done)
    }

    func testPracticeWithoutATimeDoesNotBlockTheWorkout() {
        let practice = TodayPlan.FixedPoint(kind: .practice, start: nil)
        XCTAssertEqual(plan(10, fixed: practice, workoutPlanned: true).next, .workout)
        XCTAssertFalse(practice.isOver(at: 10 * 60))
        XCTAssertTrue(practice.isOver(at: 18 * 60))
    }

    func testAGameLeadsTheDayUntilItIsOver() {
        let game = TodayPlan.FixedPoint(kind: .game, start: 15 * 60)
        let before = plan(10, fixed: game)
        XCTAssertEqual(before.next, .game)
        XCTAssertEqual(steps(before), [.checkIn, .game, .lesson, .reflection])
        XCTAssertEqual(state(before, .game), .now)
        XCTAssertEqual(plan(16, fixed: game).next, .game, "still on")

        let after = plan(17, 30, fixed: game)
        XCTAssertEqual(after.next, .reflection)
        XCTAssertEqual(state(after, .game), .done)
    }

    func testARestDayHasNothingToTickOffForTraining() {
        let rest = plan(10)
        XCTAssertEqual(steps(rest), [.checkIn, .rest, .lesson, .reflection])
        XCTAssertEqual(rest.rows.map(\.number), [1, nil, 2, 3])
        XCTAssertEqual(state(rest, .rest), .info)
        XCTAssertEqual(rest.total, 3)
        XCTAssertEqual(rest.next, .lesson)
        XCTAssertEqual(plan(10, learned: true).next, .waiting(.restDay))
    }

    func testSickMeansRecover() {
        let sick = plan(10, learned: true, sick: true)
        XCTAssertEqual(sick.next, .waiting(.recover))
        XCTAssertEqual(steps(sick), [.checkIn, .rest, .lesson, .reflection])
    }

    func testTheEveningIsForTheReflection() {
        XCTAssertEqual(plan(18, learned: true, workoutPlanned: true, workoutDone: true).next, .reflection)
        XCTAssertEqual(plan(18, checkedIn: false).next, .reflection, "no morning check-in in the evening")
        XCTAssertEqual(plan(18, workoutPlanned: true).next, .workout, "an open workout still comes first")
        XCTAssertEqual(plan(21, workoutPlanned: true).next, .reflection, "but not late at night")

        let done = plan(19, reflected: true, learned: true, workoutPlanned: true, workoutDone: true)
        XCTAssertEqual(done.next, .dayComplete)
        XCTAssertEqual(done.doneCount, done.total)
    }

    func testDoneForNowDuringTheDay() {
        let trained = plan(13, learned: true, workoutPlanned: true, workoutDone: true)
        XCTAssertEqual(trained.next, .waiting(.reflectTonight))
        XCTAssertEqual(state(trained, .reflection), .open)
        XCTAssertEqual(trained.doneCount, 3)

        XCTAssertEqual(plan(13, reflected: true, learned: true, workoutPlanned: true, workoutDone: true).next, .waiting(.clear))
    }

    func testNoLessonLeftMeansNoLessonRow() {
        let none = plan(10, lessonAvailable: false, workoutPlanned: true, workoutDone: true)
        XCTAssertEqual(steps(none), [.checkIn, .workout, .reflection])
        XCTAssertEqual(none.next, .waiting(.reflectTonight))
        XCTAssertEqual(steps(plan(10, learned: true, lessonAvailable: false)), [.checkIn, .rest, .lesson, .reflection])
    }

    func testTheNightIsForSleep() {
        XCTAssertEqual(plan(2, checkedIn: false).next, .sleep)
        XCTAssertEqual(plan(2, reflected: true).next, .dayComplete)
        XCTAssertEqual(plan(4, 59, checkedIn: false, workoutDone: true).next, .dayComplete)
        XCTAssertEqual(plan(5, checkedIn: false).next, .checkIn)
    }

    func testExactlyOneRowIsNowAtMost() {
        let fixedPoints: [TodayPlan.FixedPoint?] = [nil, .init(kind: .practice, start: 16 * 60), .init(kind: .practice, start: nil),
                                                    .init(kind: .game, start: 15 * 60)]
        for minute in stride(from: 0, to: 1440, by: 45) {
            for fixed in fixedPoints {
                for flags in 0..<64 {
                    let made = TodayPlan.make(.init(minute: minute, checkedIn: flags & 1 != 0, reflected: flags & 2 != 0, learned: flags & 4 != 0,
                                                    lessonAvailable: flags & 8 != 0, fixed: fixed, workoutPlanned: flags & 16 != 0,
                                                    workoutDone: flags & 48 == 48))
                    XCTAssertLessThanOrEqual(made.rows.filter { $0.state == .now }.count, 1)
                    XCTAssertEqual(Set(made.rows.map(\.id)).count, made.rows.count)
                    XCTAssertEqual(made.rows.compactMap(\.number), Array(1...made.total))
                    switch made.next {
                    case .checkIn: XCTAssertEqual(made.rows.first { $0.step == .checkIn }?.state, .now)
                    case .workout: XCTAssertEqual(made.rows.first { $0.step == .workout }?.state, .now)
                    case .lesson: XCTAssertEqual(made.rows.first { $0.step == .lesson }?.state, .now)
                    case .reflection: XCTAssertEqual(made.rows.first { $0.step == .reflection }?.state, .now)
                    case .game: XCTAssertEqual(made.rows.first { $0.step == .game }?.state, .now)
                    default: break
                    }
                }
            }
        }
    }
}
