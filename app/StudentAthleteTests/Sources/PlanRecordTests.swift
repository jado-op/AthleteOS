import XCTest
#if canImport(Engine)
@testable import Engine
#endif

/// The plan of record: one saved day every screen reads, in the calendar's words.
final class PlanRecordTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func items(_ facts: TrainingCalendar.Facts) -> [TrainingCalendar.Item] { TrainingCalendar.items(facts) }

    func testStrengthAfterPracticeLeadsTheDay() {
        // The bug the owner found: Home said "Team practice", the week the workout.
        var facts = TrainingCalendar.Facts(when: .future)
        facts.plannedWorkout = ("Strength after practice", 40)
        facts.practiceScheduled = "4:00–6:00 pm"
        let day = PlannedDay(date: .now, items: items(facts), minutes: 40,
                             because: PlanRecord.because(for: items(facts), workoutBecause: "Away from the game"))
        XCTAssertEqual(day.title, "Strength after practice")
        XCTAssertEqual(day.detail, "Practice 4:00–6:00 pm")
        XCTAssertEqual(day.kind, .workout)
        XCTAssertEqual(day.because, "Away from the game")
    }

    func testAGameOutranksEverything() {
        var facts = TrainingCalendar.Facts(when: .future)
        facts.games = [("Match", "3:00 pm · home")]
        facts.practiceScheduled = ""
        let list = items(facts)
        let day = PlannedDay(date: .now, items: list, because: PlanRecord.because(for: list, workoutBecause: nil))
        XCTAssertTrue(day.isGame)
        XCTAssertEqual(day.title, "Match")
        XCTAssertEqual(day.because, "3:00 pm · home · save everything for it")
    }

    func testAnEmptyDayIsRest() {
        let day = PlannedDay(date: .now, items: [], because: PlanRecord.because(for: [], workoutBecause: nil))
        XCTAssertEqual(day.title, "Rest day")
        XCTAssertNil(day.kind)
        XCTAssertEqual(day.because, "Recovery is part of the plan")
    }

    func testPracticeOnlyAndBusyDays() {
        var practice = TrainingCalendar.Facts(when: .future)
        practice.practiceScheduled = "5:00 pm"
        XCTAssertEqual(PlanRecord.because(for: items(practice), workoutBecause: "ignored"), "Practice day")

        var busy = TrainingCalendar.Facts(when: .future)
        busy.off = "Can't train"
        busy.plannedWorkout = ("Upper body", 30)
        let list = items(busy)
        XCTAssertEqual(list.map(\.kind), [.off], "a busy day never shows a workout")
        XCTAssertEqual(PlanRecord.because(for: list, workoutBecause: nil), "You said you can't train")
    }

    func testADoneWorkoutHasNoBecause() {
        var facts = TrainingCalendar.Facts(when: .today)
        facts.workoutsDone = [("Gym workout", "45 min", false)]
        facts.plannedWorkout = ("Upper body", 30)
        XCTAssertNil(PlanRecord.because(for: items(facts), workoutBecause: "Game in 2 days"))
    }

    func testTheRecordSurvivesSavingAndFindsItsDays() throws {
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        var facts = TrainingCalendar.Facts(when: .future)
        facts.plannedWorkout = ("Legs", 45)
        let days = (0...7).map { offset in
            PlannedDay(date: calendar.date(byAdding: .day, value: offset, to: start)!, items: offset == 1 ? items(facts) : [],
                       minutes: offset == 1 ? 45 : nil)
        }
        let record = PlanRecord(builtAt: start, days: days)
        let decoded = try JSONDecoder().decode(PlanRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded, record)
        let tomorrow = calendar.date(byAdding: .hour, value: 30, to: start)!
        XCTAssertEqual(decoded.day(on: tomorrow, calendar: calendar)?.title, "Legs")
        XCTAssertEqual(decoded.day(on: tomorrow, calendar: calendar)?.minutes, 45)
        XCTAssertNil(decoded.day(on: calendar.date(byAdding: .day, value: 9, to: start)!, calendar: calendar))
    }
}
