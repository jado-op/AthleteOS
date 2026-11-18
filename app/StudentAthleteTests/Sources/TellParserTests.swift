import XCTest
#if canImport(Engine)
@testable import Engine
#endif

final class TellParserTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()
    /// Wednesday 18 November 2026, 18:00.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 18))! }

    private func day(_ d: Int, _ month: Int = 11, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: d, hour: hour, minute: minute))!
    }

    private func parse(_ text: String) -> TellParser.Result { TellParser.parse(text, now: now, calendar: calendar) }

    func testTheExampleSentence() {
        let result = parse("Tournament on Saturday at 9am, my knee hurts a bit. Exams next week. I want to get faster and stronger.")
        XCTAssertTrue(result.proposals.contains(.competition(date: day(21, hour: 9), kind: .tournament, note: nil, hasTime: true)))
        XCTAssertTrue(result.proposals.contains(.pain(areas: ["knee"], level: "little")))
        XCTAssertTrue(result.proposals.contains(.examWeek(day(23))))
        XCTAssertTrue(result.proposals.contains(.goals(["acceleration", "strength"])))
        XCTAssertNil(result.safety)
    }

    func testGerman() {
        let result = parse("Spiel gegen Bayern am Samstag um 15 Uhr. Mein Knöchel tut weh. Nächste Woche Klausuren. Ich will schneller werden.")
        XCTAssertTrue(result.proposals.contains(.competition(date: day(21, hour: 15), kind: .game, note: "vs. Bayern", hasTime: true)))
        XCTAssertTrue(result.proposals.contains(.pain(areas: ["ankle"], level: "some")))
        XCTAssertTrue(result.proposals.contains(.examWeek(day(23))))
        XCTAssertTrue(result.proposals.contains(.goals(["acceleration"])))
    }

    func testDates() {
        XCTAssertEqual(firstCompetitionDay(parse("game tomorrow")), day(19, hour: 10))
        XCTAssertEqual(firstCompetitionDay(parse("match today at 4")), day(18, hour: 16))
        XCTAssertEqual(firstCompetitionDay(parse("race on 24.11.")), day(24, hour: 10))
        XCTAssertEqual(firstCompetitionDay(parse("meet on nov 29")), day(29, hour: 10))
        XCTAssertEqual(firstCompetitionDay(parse("final next friday")), day(27, hour: 10))
        XCTAssertEqual(firstCompetitionDay(parse("match in 5 days")), day(23, hour: 10))
        XCTAssertEqual(firstCompetitionDay(parse("Turnier übermorgen")), day(20, hour: 10))
        // A date earlier this year means next year.
        XCTAssertEqual(firstCompetitionDay(parse("game on 3.2.")), calendar.date(from: DateComponents(year: 2027, month: 2, day: 3, hour: 10)))
        // No day, no competition.
        XCTAssertNil(firstCompetitionDay(parse("I love my games")))
    }

    private func firstCompetitionDay(_ result: TellParser.Result) -> Date? {
        for proposal in result.proposals {
            if case .competition(let date, _, _, _) = proposal { return date }
        }
        return nil
    }

    func testSafety() {
        let head = parse("I hit my head at practice")
        XCTAssertTrue(head.proposals.contains(.headKnock))
        XCTAssertNotNil(head.safety)
        let sharp = parse("my shoulder really hurts")
        XCTAssertTrue(sharp.proposals.contains(.pain(areas: ["shoulder"], level: "lot")))
        XCTAssertTrue(sharp.safety?.contains("get it checked") == true)
        // Being sore isn't pain.
        XCTAssertTrue(parse("legs are sore after the game").proposals.isEmpty)
    }

    func testStatusesAndGoals() {
        XCTAssertTrue(parse("I'm sick for 3 days").proposals.contains(.dayStatus("sick", from: day(18), days: 3)))
        XCTAssertTrue(parse("Flight to Spain tomorrow").proposals.contains(.dayStatus("travel", from: day(19), days: 1)))
        XCTAssertTrue(parse("ich bin krank").proposals.contains(.dayStatus("sick", from: day(18), days: 2)))
        XCTAssertEqual(parse("I want more confidence and focus, and to jump higher").proposals,
                       [.goals(["verticalJump", "confidence", "focus"])])
        // Goal words without wanting anything aren't goals.
        XCTAssertTrue(parse("the jump test was fine").proposals.isEmpty)
    }

    // MARK: The competition coach

    func testFocusComesFromTheLastResultThenTheTwin() {
        let last = CompetitionResult(id: "g1", outcome: .loss, score: "1–2", rating: 2, toImprove: ["Focus", "Speed"])
        let points = CompetitionCoach.focus(last: last, insights: [.sleepBeforeGames, .gameDayFuel], daysToNext: 6, team: true)
        XCTAssertEqual(points.map(\.id), ["reset", "speed", "sleep"])
        XCTAssertEqual(points.first?.briefingID, "reset-after-mistakes")
        // Two days out: sharpen first, no speed building.
        let close = CompetitionCoach.focus(last: last, insights: [], daysToNext: 2, team: true)
        XCTAssertEqual(close.first?.id, "sharpen")
        XCTAssertFalse(close.contains { $0.id == "speed" })
        XCTAssertEqual(CompetitionCoach.focus(last: nil, insights: [], daysToNext: nil, team: false).map(\.id), ["routine"])
    }

    func testResultsAndOutlooksAreKept() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "TellParserTests"))
        defaults.removePersistentDomain(forName: "TellParserTests")
        let result = CompetitionResult(id: "g1", outcome: .placed, placement: 3, score: "11.84 s", rating: 4)
        CompetitionStore.save(result, defaults)
        CompetitionStore.save(CompetitionOutlook(id: "g2", chance: 60), defaults)
        XCTAssertEqual(CompetitionStore.results(defaults)["g1"], result)
        XCTAssertEqual(CompetitionStore.outlooks(defaults)["g2"]?.chance, 60)
        XCTAssertEqual(result.summary, "Placed 3rd · 11.84 s")
        XCTAssertEqual(CompetitionResult(id: "x", outcome: .win, score: "2–1", rating: 5).summary, "Won 2–1")
        XCTAssertEqual(CompetitionCoach.chanceWord(60), "Good chance")
        XCTAssertEqual(CompetitionCoach.ordinal(22), "22nd")
        XCTAssertEqual(CompetitionCoach.ordinal(12), "12th")
    }
}
