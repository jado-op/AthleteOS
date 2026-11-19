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

    /// The owner's own sentence (TestFlight, 2026-11-18): it used to become "Holiday from today for 7 days".
    func testSeasonFromDrylandAndHolidays() {
        let result = parse("Hi the ski season will really start with dryland exercise The first week of December. After the holidays.")
        XCTAssertEqual(result.proposals, [.season("pre", from: day(1, 12)), .season("in", from: calendar.date(from: DateComponents(year: 2027, month: 1, day: 7))!)])
        XCTAssertTrue(result.unread.isEmpty)
    }

    func testSeasonWords() {
        XCTAssertEqual(parse("Season starts mid January").proposals, [.season("in", from: calendar.date(from: DateComponents(year: 2027, month: 1, day: 15))!)])
        XCTAssertEqual(parse("Die Saison endet Ende März").proposals, [.season("end", from: calendar.date(from: DateComponents(year: 2027, month: 3, day: 22))!)])
        XCTAssertEqual(parse("Saisonvorbereitung ab Dezember").proposals, [.season("pre", from: day(1, 12))])
    }

    func testHolidaysAsATimeAreNotAHoliday() {
        XCTAssertFalse(parse("We start again after the holidays").proposals.contains { if case .dayStatus = $0 { true } else { false } })
        XCTAssertTrue(parse("I'm on holiday for a week").proposals.contains(.dayStatus("holiday", from: day(18), days: 7)))
    }

    func testWhatItCannotReadIsShown() {
        let result = parse("Hi. My coach said I should work on my weak foot.")
        XCTAssertEqual(result.unread, ["my coach said i should work on my weak foot"])
    }

    /// The language model's output is checked before it becomes a proposal.
    func testModelOutputIsChecked() {
        func item(_ kind: String, _ day: String = "", areas: [String] = [], words: String = "") -> TellModelReader.Item {
            TellModelReader.Item(kind: kind, day: day, time: "", days: 0, areas: areas, level: "", goals: [], opponent: "", words: words)
        }
        let rules = parse("I hit my head")
        let result = TellModelReader.proposals(from: [
            item("preSeasonStart", "2026-12-01"),
            item("seasonStart", "2031-01-07", words: "in 2031"),      // too far ahead: not used
            item("pain", areas: ["elbowish"], words: "my elbowish"), // unknown area: not used
            item("notUnderstood", words: "coach wants left foot work"),
        ], rules: rules, now: now, calendar: calendar)
        XCTAssertEqual(result.proposals, [.season("pre", from: day(1, 12)), .headKnock])
        XCTAssertEqual(result.unread, ["in 2031", "my elbowish", "coach wants left foot work"])
        XCTAssertNotNil(result.safety)
    }

    func testGerman() {
        let result = parse("Spiel gegen Bayern am Samstag um 15 Uhr. Mein Knöchel tut weh. Nächste Woche Klausuren. Ich will schneller werden.")
        XCTAssertTrue(result.proposals.contains(.competition(date: day(21, hour: 15), kind: .game, note: "vs. Bayern", hasTime: true)))
        XCTAssertTrue(result.proposals.contains(.pain(areas: ["ankle"], level: "some")))
        XCTAssertTrue(result.proposals.contains(.examWeek(day(23))))
        XCTAssertTrue(result.proposals.contains(.goals(["acceleration"])))
    }

    func testDates() {
        XCTAssertEqual(firstCompetitionDay(parse("game tomorrow")), day(19, hour: 0))
        XCTAssertEqual(firstCompetitionDay(parse("match today at 4")), day(18, hour: 16))
        XCTAssertEqual(firstCompetitionDay(parse("race on 24.11.")), day(24, hour: 0))
        XCTAssertEqual(firstCompetitionDay(parse("meet on nov 29")), day(29, hour: 0))
        XCTAssertEqual(firstCompetitionDay(parse("final next friday")), day(27, hour: 0))
        XCTAssertEqual(firstCompetitionDay(parse("match in 5 days")), day(23, hour: 0))
        XCTAssertEqual(firstCompetitionDay(parse("Turnier übermorgen")), day(20, hour: 0))
        // A date earlier this year means next year.
        XCTAssertEqual(firstCompetitionDay(parse("game on 3.2.")), calendar.date(from: DateComponents(year: 2027, month: 2, day: 3, hour: 0)))
        // No day, no competition.
        XCTAssertNil(firstCompetitionDay(parse("I love my games")))
        // Not competitions.
        XCTAssertNil(firstCompetitionDay(parse("I meet with my coach tomorrow")))
        XCTAssertNil(firstCompetitionDay(parse("finals at school on friday")))
        // "that 3" is not a time.
        XCTAssertEqual(firstCompetitionDay(parse("game tomorrow, that 3 hour bus ride")), day(19))
    }

    /// US dates are month first; a number over 12 can only be the day.
    func testMonthFirstDates() {
        let us = Locale(identifier: "en_US"), de = Locale(identifier: "de_DE")
        XCTAssertEqual(firstCompetitionDay(TellParser.parse("game 11/24", now: now, calendar: calendar, locale: us)), day(24))
        XCTAssertEqual(firstCompetitionDay(TellParser.parse("game 12/5", now: now, calendar: calendar, locale: us)), day(5, 12))
        XCTAssertEqual(firstCompetitionDay(TellParser.parse("game 5/12", now: now, calendar: calendar, locale: de)), day(5, 12))
        // Unambiguous either way.
        XCTAssertEqual(firstCompetitionDay(TellParser.parse("game 11/24", now: now, calendar: calendar, locale: de)), day(24))
        XCTAssertEqual(firstCompetitionDay(TellParser.parse("game 24/11", now: now, calendar: calendar, locale: us)), day(24))
        // Dots are day first everywhere.
        XCTAssertEqual(firstCompetitionDay(TellParser.parse("race on 5.12.", now: now, calendar: calendar, locale: us)), day(5, 12))
    }

    /// "sat" and "sun" are words too: a weekday only after on/this/next/until or with a dot.
    func testSatAndSunAreNotAlwaysWeekdays() {
        XCTAssertNil(firstCompetitionDay(parse("Lost the game, sat on the bench")))
        let sat = parse("I sat out practice, knee hurts")
        XCTAssertTrue(sat.proposals.contains(.pain(areas: ["knee"], level: "some")))
        XCTAssertFalse(sat.proposals.contains { if case .competition = $0 { true } else { false } })
        XCTAssertEqual(firstCompetitionDay(parse("game on sat")), day(21))
        XCTAssertEqual(firstCompetitionDay(parse("game next sun")), day(29))
        XCTAssertEqual(firstCompetitionDay(parse("tournament this sun at 10am")), day(22, hour: 10))
    }

    /// "Guten Morgen" and "good morning" are greetings, not "tomorrow".
    func testGreetingsAreNotDates() {
        XCTAssertEqual(parse("Guten Morgen, ich bin krank").proposals, [.dayStatus("sick", from: day(18), days: 2)])
        XCTAssertEqual(parse("Good morning, I'm sick").proposals, [.dayStatus("sick", from: day(18), days: 2)])
        XCTAssertTrue(parse("Guten Morgen!").unread.isEmpty)
        XCTAssertTrue(parse("Good morning").proposals.isEmpty)
        // "morgen" alone is still tomorrow.
        XCTAssertEqual(parse("Ich bin morgen krank").proposals, [.dayStatus("sick", from: day(19), days: 2)])
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
        // "Since I got back" isn't back pain.
        XCTAssertTrue(parse("my knee hurts since I got back").proposals.contains(.pain(areas: ["knee"], level: "some")))
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

    // MARK: Spans, no gym, practice

    func testTheOwnersHolidaySentence() {
        // Friday 20 to Monday 23 November: holiday (bodyweight workouts), four days.
        XCTAssertEqual(parse("Friday until Monday I don't have a real gym, I'm on holiday").proposals,
                       [.dayStatus("holiday", from: day(20), days: 4)])
        XCTAssertEqual(parse("From Fri to Mon I'm on holiday").proposals, [.dayStatus("holiday", from: day(20), days: 4)])
        XCTAssertEqual(parse("Ich bin Fr bis Mo im Urlaub").proposals, [.dayStatus("holiday", from: day(20), days: 4)])
        XCTAssertEqual(parse("Von Freitag bis Sonntag bin ich verreist").proposals, [.dayStatus("travel", from: day(20), days: 3)])
    }

    func testSpans() {
        // "until" alone starts today.
        XCTAssertEqual(parse("I'm on holiday until Sunday").proposals, [.dayStatus("holiday", from: day(18), days: 5)])
        XCTAssertEqual(parse("Ich bin bis Sonntag krank").proposals, [.dayStatus("sick", from: day(18), days: 5)])
        XCTAssertEqual(parse("No gym this weekend").proposals, [.noGym(from: day(21), days: 2)])
        XCTAssertEqual(parse("Travelling next week").proposals, [.dayStatus("travel", from: day(23), days: 7)])
        XCTAssertEqual(parse("Holiday 20.11 to 24.11").proposals, [.dayStatus("holiday", from: day(20), days: 5)])
        // "to" between words that aren't days is no span.
        XCTAssertEqual(parse("Flight to Spain tomorrow").proposals, [.dayStatus("travel", from: day(19), days: 1)])
        XCTAssertTrue(parse("I want to get stronger").proposals.allSatisfy { if case .goals = $0 { true } else { false } })
        // A two-day tournament: one competition each day, the time on the first.
        let tournament = parse("Tournament Saturday to Sunday at 9am").proposals
        XCTAssertEqual(tournament, [.competition(date: day(21, hour: 9), kind: .tournament, note: nil, hasTime: true),
                                    .competition(date: day(22), kind: .tournament, note: nil, hasTime: false)])
    }

    func testNoGymAndPractice() {
        XCTAssertEqual(parse("The gym is closed tomorrow").proposals, [.noGym(from: day(19), days: 1)])
        XCTAssertEqual(parse("Nur Eigengewicht bis Sonntag").proposals, [.noGym(from: day(18), days: 5)])
        XCTAssertEqual(parse("No practice on Friday").proposals, [.practice(from: day(20), days: 1, happening: false)])
        XCTAssertEqual(parse("Training fällt morgen aus").proposals, [.practice(from: day(19), days: 1, happening: false)])
        XCTAssertEqual(parse("Morgen fällt das Training aus").proposals, [.practice(from: day(19), days: 1, happening: false)])
        XCTAssertEqual(parse("Extra practice on Saturday").proposals, [.practice(from: day(21), days: 1, happening: true)])
        // Practice words without a day change nothing.
        XCTAssertFalse(parse("I want to practice my free throws").proposals.contains { if case .practice = $0 { true } else { false } })
        // An away game is a game, not travel.
        XCTAssertFalse(parse("Away game on Saturday").proposals.contains { if case .dayStatus = $0 { true } else { false } })
    }

    func testModelSpansAndRulesSafetyNet() {
        let items = [TellModelReader.Item(kind: "practiceOff", day: "2026-11-20", time: "", days: 2, areas: [], level: "", goals: [],
                                          opponent: "", words: "no practice fri and sat")]
        let rules = parse("The gym is closed tomorrow")
        let result = TellModelReader.proposals(from: items, rules: rules, now: now, calendar: calendar)
        XCTAssertEqual(result.proposals, [.practice(from: day(20), days: 2, happening: false), .noGym(from: day(19), days: 1)])
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
