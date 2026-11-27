import XCTest
#if canImport(Engine)
@testable import Engine
#endif

/// Plan changes are told only when the athlete would act on them, once, with the cause.
final class PlanChangesTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    // Friday 2027-01-15, noon UTC.
    private let now = Date(timeIntervalSince1970: 1_800_014_400) // 2027-01-15 12:00 UTC

    private func day(_ offset: Int, _ build: (inout TrainingCalendar.Facts) -> Void, minutes: Int? = nil) -> PlannedDay {
        let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
        var facts = TrainingCalendar.Facts(when: offset == 0 ? .today : .future)
        build(&facts)
        return PlannedDay(date: date, items: TrainingCalendar.items(facts), minutes: minutes)
    }

    private func record(_ days: [PlannedDay]) -> PlanRecord { PlanRecord(builtAt: now, days: days) }

    func testPracticeAddedTurnsLegsIntoStrengthAfterPractice() {
        let old = record([day(2, { $0.plannedWorkout = ("Legs", 45) }, minutes: 45)])
        let new = record([day(2, { $0.plannedWorkout = ("Strength after practice", 40); $0.practiceScheduled = "4:00 pm" }, minutes: 40)])
        let changes = PlanChanges.compare(old, new, calendar: calendar, now: now)
        XCTAssertEqual(changes.count, 1)
        let line = PlanChanges.line(changes[0], calendar: calendar, now: now)
        XCTAssertTrue(line.hasPrefix("Sunday: Legs → Strength after practice"), line)
        XCTAssertTrue(line.hasSuffix("practice added"), line)
    }

    func testEngineReshufflesStaySilent() {
        // A different focus or length with nothing around it changing: the
        // engine re-deciding after a session or check-in, not news.
        let old = record([day(1, { $0.plannedWorkout = ("Legs", 45) }, minutes: 45)])
        let new = record([day(1, { $0.plannedWorkout = ("Upper body", 25) }, minutes: 25)])
        XCTAssertTrue(PlanChanges.compare(old, new, calendar: calendar, now: now).isEmpty)
    }

    func testTodayIsNeverToldHere() {
        // The now slot shows today with its why; a check-in reshapes it every morning.
        let old = record([day(0, { $0.practiceScheduled = "4:00 pm" })])
        let new = record([day(0, { $0.plannedWorkout = ("After-practice strength", 25); $0.practiceScheduled = "4:00 pm" })])
        XCTAssertTrue(PlanChanges.compare(old, new, calendar: calendar, now: now).isEmpty)
        let game = record([day(0, { $0.games = [("Match", "6:00 pm · away")] })])
        XCTAssertTrue(PlanChanges.compare(old, game, calendar: calendar, now: now).isEmpty)
    }

    func testAGameAddedTomorrowIsToldWithItsCause() {
        let old = record([day(1, { $0.plannedWorkout = ("Legs", 45) }, minutes: 45)])
        let new = record([day(1, { $0.games = [("Match", "6:00 pm · away")] })])
        let told = PlanChanges.compare(old, new, calendar: calendar, now: now)
        XCTAssertEqual(told.count, 1)
        XCTAssertEqual(PlanChanges.line(told[0], event: "Match", calendar: calendar, now: now), "Tomorrow: Legs → Match · match added")
    }

    func testASickDayWithPracticeIsAnOffDay() {
        let sick = day(1, { $0.practiceScheduled = "4:00 pm"; $0.off = "Sick" })
        XCTAssertEqual(sick.kind, .off)
        XCTAssertEqual(sick.title, "Sick")
        XCTAssertNil(sick.detail)
    }

    func testDoingTheWorkoutIsNotAChange() {
        let old = record([day(0, { $0.plannedWorkout = ("Legs", 45) }, minutes: 45)])
        let new = record([day(0, { $0.workoutsDone = [("Gym workout", "45 min", false)] })])
        XCTAssertTrue(PlanChanges.compare(old, new, calendar: calendar, now: now).isEmpty)
    }

    func testNoOldPlanMeansNothingToTell() {
        XCTAssertTrue(PlanChanges.compare(nil, record([day(1, { $0.plannedWorkout = ("Legs", 45) })]), calendar: calendar, now: now).isEmpty)
    }

    func testMergeKeepsTheFirstBeforeAndDropsADayBackWhereItStarted() {
        let legs = day(2, { $0.plannedWorkout = ("Legs", 45) }, minutes: 45)
        let off = day(2, { $0.off = "Can't train" })
        let game = day(2, { $0.games = [("Match", nil)] })
        let first = PlanChanges.merge([], with: [PlanChange(date: legs.date, before: legs, after: off)], calendar: calendar, now: now)
        let merged = PlanChanges.merge(first, with: [PlanChange(date: legs.date, before: off, after: game)], calendar: calendar, now: now)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].before.title, "Legs")
        XCTAssertEqual(merged[0].after.title, "Match")
        let upper = day(2, { $0.plannedWorkout = ("Upper body", 45) }, minutes: 45)
        let back = PlanChanges.merge(merged, with: [PlanChange(date: legs.date, before: game, after: upper)], calendar: calendar, now: now)
        XCTAssertTrue(back.isEmpty, "a workout → … → a workout is no change worth telling")
    }

    func testMergeForgetsPastDays() {
        let legs = day(-1, { $0.plannedWorkout = ("Legs", 45) }, minutes: 45)
        let off = day(-1, { $0.off = "Can't train" })
        XCTAssertTrue(PlanChanges.merge([PlanChange(date: legs.date, before: legs, after: off)], with: [], calendar: calendar, now: now).isEmpty)
    }

    func testHeadlinesSummariseManyDays() {
        let changes = (1...4).map { offset -> PlanChange in
            let was = day(offset, { $0.plannedWorkout = ("Legs", 45) }, minutes: 45)
            return PlanChange(date: was.date, before: was, after: day(offset, { $0.off = "Away" }))
        }
        XCTAssertEqual(PlanChanges.headline(Array(changes.prefix(2)), calendar: calendar, now: now),
                       "Your plan changed for tomorrow and Sunday")
        XCTAssertEqual(PlanChanges.headline(changes, calendar: calendar, now: now), "Your plan changed on 4 days")
        XCTAssertEqual(PlanChanges.line(changes[1], calendar: calendar, now: now), "Sunday: Legs → Away")
    }
}
