import XCTest
#if canImport(Engine)
@testable import Engine
#endif

/// "What I know about you": nothing before its minimum, only the athlete's
/// own usual, patterns that repeat, and pain that comes back sent to someone.
final class TwinKnowledgeTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let now = Date(timeIntervalSince1970: 1_800_014_400) // 2027-01-15 12:00 UTC

    private func day(_ offset: Int, hour: Int = 8) -> Date {
        calendar.date(byAdding: .hour, value: offset * 24 + hour - 12, to: now)!
    }

    private func build(_ input: KnowledgeInput) -> TwinKnowledge { TwinKnowledgeEngine.build(input, calendar: calendar) }

    func testWithNoDataEverythingIsStillLearning() {
        let knowledge = build(KnowledgeInput(base: TwinInput(now: now)))
        XCTAssertTrue(knowledge.lines.isEmpty)
        let games = knowledge.learning.first { $0.id == "games.best" }
        XCTAssertEqual(games?.progress, "0 of 10 rated games so far")
        XCTAssertNil(knowledge.legRecoveryDays)
    }

    func testUsualSleepIsTheAthletesOwnMedian() {
        let mornings = (1...10).map { TwinInput.Morning(date: day(-$0), sleepHours: $0 == 1 ? 4 : 7.67, energy: 3, soreness: 2) }
        let knowledge = build(KnowledgeInput(base: TwinInput(mornings: mornings, now: now)))
        XCTAssertEqual(knowledge.lines.first { $0.id == "habits.sleep" }?.text, "You usually sleep about 7 h 40 min.")
    }

    /// Rated games: every third one is best, after 8 h+ nights; the others after ~7 h.
    private func gamesInput(bestAfterLongSleep: Bool, count: Int = 12) -> KnowledgeInput {
        var mornings: [TwinInput.Morning] = []
        var rated: [KnowledgeInput.RatedGame] = []
        for index in 0..<count {
            let gameDay = -(count - index) * 5
            let best = index % 3 == 0
            let sleep = (best == bestAfterLongSleep) ? 8.3 : 7.0
            mornings.append(TwinInput.Morning(date: day(gameDay - 1), sleepHours: sleep, energy: 3, soreness: 2))
            mornings.append(TwinInput.Morning(date: day(gameDay), sleepHours: sleep, energy: 3, soreness: 2))
            rated.append(KnowledgeInput.RatedGame(date: day(gameDay, hour: 15), rating: best ? 5 : 3))
        }
        return KnowledgeInput(base: TwinInput(mornings: mornings, now: now), ratedGames: rated)
    }

    func testBestGamesPatternNeedsToHoldTwice() {
        // 12 games: seen, but it must still hold after 3 more (T6) — no direction yet.
        let early = build(gamesInput(bestAfterLongSleep: true))
        XCTAssertFalse(early.lines.contains { $0.area == .games })
        XCTAssertEqual(early.learning.first { $0.id == "games.best" }?.progress, "Checking it against your next 3 rated games")

        let knowledge = build(gamesInput(bestAfterLongSleep: true, count: 15))
        let line = knowledge.lines.first { $0.id == "games.best.sleep" }
        XCTAssertNotNil(line)
        XCTAssertTrue(line?.text.contains("5 best-rated games") ?? false, line?.text ?? "")
        XCTAssertTrue(line?.basis.contains("doesn't decide") ?? false)
        XCTAssertFalse(line?.text.contains("because") ?? true, "goes with, never causes (T7)")
    }

    func testTooFewGamesSaysNothingAboutThem() {
        let knowledge = build(gamesInput(bestAfterLongSleep: true, count: 9))
        XCTAssertFalse(knowledge.lines.contains { $0.area == .games })
        XCTAssertEqual(knowledge.learning.first { $0.id == "games.best" }?.progress, "9 of 10 rated games so far")
    }

    func testLessSleepBeforeGoodGamesIsNeverSaid() {
        let knowledge = build(gamesInput(bestAfterLongSleep: false, count: 15))
        XCTAssertFalse(knowledge.lines.contains { $0.id == "games.best.sleep" })
    }

    func testPainThatComesBackGoesToSomeone() {
        let pains = [
            KnowledgeInput.Pain(date: day(-30), areas: ["knee"]),
            KnowledgeInput.Pain(date: day(-29), areas: ["knee"]),   // same occasion
            KnowledgeInput.Pain(date: day(-6), areas: ["knee", "back"]),
            KnowledgeInput.Pain(date: day(-80), areas: ["back"])    // older than 8 weeks
        ]
        let knowledge = build(KnowledgeInput(base: TwinInput(now: now), pains: pains))
        let knee = knowledge.lines.first { $0.id == "body.pain.knee" }
        XCTAssertEqual(knee?.safety, true)
        XCTAssertEqual(knee?.text, "Your knee hurt again: 16 Dec and 9 Jan. Pain that comes back is worth showing to an athletic trainer, physio or doctor.")
        XCTAssertNil(knowledge.lines.first { $0.id == "body.pain.back" }, "once in 8 weeks isn't 'again'")
        XCTAssertFalse(knowledge.lines.contains { $0.text.lowercased().contains("injury") || $0.text.contains("%") })
    }

    func testSlowLegRecoveryLengthensRestOnly() {
        // Usual soreness 2; after each hard leg day soreness stays 4 until day 4.
        var mornings: [TwinInput.Morning] = []
        var efforts: [KnowledgeInput.RegionEffort] = []
        for block in 0..<5 {
            let start = -60 + block * 10
            efforts.append(KnowledgeInput.RegionEffort(date: day(start, hour: 18), region: "legs", effort: 8))
            for offset in 1...9 {
                mornings.append(TwinInput.Morning(date: day(start + offset), sleepHours: 8, energy: 3, soreness: offset < 4 ? 4 : 2))
            }
        }
        let knowledge = build(KnowledgeInput(base: TwinInput(mornings: mornings, now: now), efforts: efforts))
        XCTAssertEqual(knowledge.legRecoveryDays, 4)
        XCTAssertTrue(knowledge.lines.first { $0.id == "body.legs" }?.text.contains("on day 4, not day 3") ?? false)

        // Faster than the plan: said, but the plan's rest never shrinks (T10).
        let fast = mornings.map { TwinInput.Morning(date: $0.date, sleepHours: 8, energy: 3, soreness: 2) }
        let quick = build(KnowledgeInput(base: TwinInput(mornings: fast, now: now), efforts: efforts))
        XCTAssertNil(quick.legRecoveryDays)
        XCTAssertTrue(quick.lines.first { $0.id == "body.legs" }?.text.contains("still keeps 3 days") ?? false)
    }

    func testShortNightsAndPractice() {
        var mornings: [TwinInput.Morning] = []
        var practices: [TwinInput.Practice] = []
        for index in 0..<24 {
            let offset = -48 + index * 2
            let short = index % 4 == 0
            mornings.append(TwinInput.Morning(date: day(offset), sleepHours: short ? 6 : 8, energy: 3, soreness: 2))
            practices.append(TwinInput.Practice(date: day(offset, hour: 17), went: short ? 2 : 4, hard: 3, minutes: 90))
        }
        let knowledge = build(KnowledgeInput(base: TwinInput(mornings: mornings, practices: practices, now: now)))
        let line = knowledge.lines.first { $0.id == "training.sleep" }
        XCTAssertEqual(line?.text, "On days after short nights you rated practice about a step lower (6 of 6 times).")

        // Exam, travel and sick days are left out: fewer than 5 short nights remain.
        let excluded = Set(mornings.enumerated().filter { $0.offset % 4 == 0 }.prefix(3).map { $0.element.date })
        let fewer = build(KnowledgeInput(base: TwinInput(mornings: mornings, practices: practices, now: now), excludedDays: excluded))
        XCTAssertNil(fewer.lines.first { $0.id == "training.sleep" })
    }

    func testLegDaysCloseTogetherSayNothingAboutRecovery() {
        // Hard legs every 2 days: each window holds the next session, so no
        // episode counts and rest is never lengthened from it (review finding).
        var mornings: [TwinInput.Morning] = []
        var efforts: [KnowledgeInput.RegionEffort] = []
        for index in 0..<10 {
            efforts.append(KnowledgeInput.RegionEffort(date: day(-40 + index * 2, hour: 18), region: "legs", effort: 8))
        }
        for back in 1...45 { mornings.append(TwinInput.Morning(date: day(-back), sleepHours: 8, energy: 3, soreness: 4)) }
        let knowledge = build(KnowledgeInput(base: TwinInput(mornings: mornings, now: now), efforts: efforts))
        XCTAssertNil(knowledge.legRecoveryDays)
        XCTAssertNil(knowledge.lines.first { $0.id == "body.legs" })
    }

    func testRatingsAllAlikeStayCheckingWithoutDirection() {
        var input = gamesInput(bestAfterLongSleep: true, count: 15)
        input.ratedGames = input.ratedGames.map { KnowledgeInput.RatedGame(date: $0.date, rating: 4) }
        let knowledge = build(input)
        XCTAssertFalse(knowledge.lines.contains { $0.area == .games })
        XCTAssertEqual(knowledge.learning.first { $0.id == "games.best" }?.checking, true)
    }

    func testPainThatNeverStopsIsAlsoSentToSomeone() {
        let pains = stride(from: 30, through: 6, by: -2).map { KnowledgeInput.Pain(date: day(-$0), areas: ["ankle"]) }
        let knowledge = build(KnowledgeInput(base: TwinInput(now: now), pains: pains))
        let line = knowledge.lines.first { $0.id == "body.pain.ankle" }
        XCTAssertEqual(line?.safety, true)
        XCTAssertTrue(line?.text.hasPrefix("Your ankle or foot has hurt on and off since") ?? false, line?.text ?? "")
    }

    /// Rated practices (evening CR-10): the usual length and effort in words,
    /// and a weekday only when it's clearly the hard one. Still learning before 6.
    func testUsualPracticeFromRatedPractices() {
        func practice(_ back: Int, rpe: Int?) -> TwinInput.Practice {
            TwinInput.Practice(date: day(-back, hour: 18), went: 3, hard: 3, minutes: 90, rpe: rpe)
        }
        let few = build(KnowledgeInput(base: TwinInput(practices: [1, 3, 8].map { practice($0, rpe: 5) }, now: now)))
        XCTAssertEqual(few.learning.first { $0.id == "training.practice" }?.have, 3)
        XCTAssertNil(few.lines.first { $0.id == "training.practice" })
        // Same weekday every week is hard (8), two days later easy (4).
        let weeks = [0, 7, 14, 21]
        let practices = weeks.map { practice($0 + 1, rpe: 8) } + weeks.map { practice($0 + 3, rpe: 4) }
        let line = build(KnowledgeInput(base: TwinInput(practices: practices, now: now))).lines.first { $0.id == "training.practice" }
        let hardDay = calendar.weekdaySymbols[calendar.component(.weekday, from: day(-1, hour: 18)) - 1]
        XCTAssertEqual(line?.text, "Your practices usually run about 1 h 30 min at 6 of 10 — hard. \(hardDay)'s is usually the hardest.")
        XCTAssertEqual(line?.basis, "median of 8 practices you rated in the last 8 weeks")
        // Unrated practices only: nothing claimed.
        let unrated = build(KnowledgeInput(base: TwinInput(practices: weeks.map { practice($0 + 1, rpe: nil) }, now: now)))
        XCTAssertNil(unrated.lines.first { $0.id == "training.practice" })
    }
}
