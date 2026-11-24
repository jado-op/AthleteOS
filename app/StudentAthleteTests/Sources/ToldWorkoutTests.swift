import SwiftData
import XCTest

/// A workout told in Tell AthleteOS is saved as training (owner, 2026-11-24:
/// "I put in a workout, but it didn't save anywhere").
@MainActor
final class ToldWorkoutTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        ModelContext(try AthleteStore.makeContainer(inMemory: true))
    }

    func testAToldWorkoutIsASavedSessionWithWhatItTrained() throws {
        let context = try makeContext()
        let athlete = Athlete(appleUserId: "told-1", birthDate: .now)
        context.insert(athlete)
        let session = HealthWorkoutInbox.logTold(day: .now, names: ["chest", "upper back", "core", "arms"], patterns: ["push", "pull", "core"],
                                                 qualities: ["upperStrength", "core"], level: 2, minutes: 60, athlete: athlete, context: context)
        let stored = try context.fetch(FetchDescriptor<Session>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(session.minutes, 60)
        XCTAssertNotNil(session.endedAt)
        XCTAssertTrue(HealthWorkoutInbox.isTold(session))
        XCTAssertEqual(HealthWorkoutInbox.activity(of: session), "Chest, upper back, core and arms")
        XCTAssertTrue(TodayEngine.workoutDone(athlete))
        // Already answered: never asked in the workout check.
        XCTAssertNil(HealthWorkoutInbox.pending(athlete.sessions))
        XCTAssertEqual(Set(HealthWorkoutInbox.regions(of: session).keys), [.upper, .core])
    }

    func testTellingTheSameDayAgainGrowsOneWorkout() throws {
        let context = try makeContext()
        let athlete = Athlete(appleUserId: "told-2", birthDate: .now)
        context.insert(athlete)
        HealthWorkoutInbox.logTold(day: .now, names: ["legs"], patterns: ["squat"], qualities: ["lowerStrength"], level: 2, minutes: nil,
                                   athlete: athlete, context: context)
        let again = HealthWorkoutInbox.logTold(day: .now, names: ["core"], patterns: ["core"], qualities: ["core"], level: 3, minutes: 45,
                                               athlete: athlete, context: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Session>()).count, 1)
        XCTAssertEqual(again.minutes, 45)
        XCTAssertEqual(HealthWorkoutInbox.activity(of: again), "Legs and core")
        XCTAssertEqual(Set(HealthWorkoutInbox.regions(of: again).keys), [.lower, .core])
    }

    func testNoMinutesAreInvented() throws {
        let context = try makeContext()
        let athlete = Athlete(appleUserId: "told-3", birthDate: .now)
        context.insert(athlete)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        let session = HealthWorkoutInbox.logTold(day: yesterday, names: [], patterns: [], qualities: ["conditioning"], level: 1, minutes: nil,
                                                 athlete: athlete, context: context)
        XCTAssertEqual(session.minutes, 0)
        XCTAssertEqual(HealthWorkoutInbox.activity(of: session), "Workout")
        XCTAssertTrue(Calendar.current.isDate(session.startedAt, inSameDayAs: yesterday))
    }
}
