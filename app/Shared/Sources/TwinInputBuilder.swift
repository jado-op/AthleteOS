import Foundation

/// Gathers what the twin reads from the athlete's own data — check-ins,
/// games, logged sessions and sets, tests, evening reflections and the
/// interview — into the plain `TwinInput` the analysis works on. Nothing
/// leaves the phone.
@MainActor
enum TwinInputBuilder {
    static func input(athlete: Athlete, state: AcademyState, now: Date = .now, calendar: Calendar = .current) -> TwinInput {
        let mornings = athlete.checkIns.map {
            TwinInput.Morning(date: $0.date, sleepHours: $0.sleepHours.flatMap { $0 > 0 ? $0 : nil }, energy: $0.energy, soreness: $0.soreness)
        }
        let lifts = athlete.sessions.flatMap { session in
            session.sets.compactMap { set -> TwinInput.Lift? in
                guard let weight = set.weightKg, weight > 0, let reps = set.reps, reps > 0 else { return nil }
                return TwinInput.Lift(date: session.startedAt, slug: set.itemSlug, weightKg: weight, reps: reps)
            }
        }
        var tests: [String: BenchmarkTest] = [:]
        for test in BenchmarkCatalog.tests(for: nil) { tests[test.id] = test }
        for sport in athlete.sports {
            for test in BenchmarkCatalog.tests(for: sport.sportSlug) { tests[test.id] = test }
        }
        let results = BenchmarkStore.results.compactMap { result -> TwinInput.Test? in
            guard let test = tests[result.testID] else { return nil }
            return TwinInput.Test(date: result.date, testID: result.testID, name: test.name, value: result.value,
                                  higherIsBetter: test.higherIsBetter, unit: unit(test.unit))
        }
        let reflections = MindsetStore.reflections.compactMap { reflection -> TwinInput.Reflect? in
            guard let date = day(reflection.day, calendar: calendar) else { return nil }
            return TwinInput.Reflect(date: date.addingTimeInterval(20 * 3600), feeling: reflection.feeling, needsWork: reflection.needsWork ?? [])
        }
        return TwinInput(mornings: mornings, games: athlete.competitions.map(\.date), sessions: athlete.sessions.map(\.startedAt),
                         lifts: lifts, tests: results, reflections: reflections, intake: state.intake,
                         sportSlug: athlete.activeSport?.sportSlug, now: now)
    }

    static func unit(_ unit: BenchmarkUnit) -> String {
        switch unit {
        case .centimeters: "cm"
        case .seconds: "s"
        case .reps: "reps"
        case .outOf10: "/10"
        }
    }

    /// "2026-11-18" → that day at midnight.
    static func day(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
