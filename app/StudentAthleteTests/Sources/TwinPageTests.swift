import XCTest
#if canImport(Engine)
@testable import Engine
#endif

/// The Twin page's order: one line leads (and only while its cause lasts),
/// one portrait (no thing said twice), plan effects where the fact is.
final class TwinPageTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let now = Date(timeIntervalSince1970: 1_800_014_400) // Friday 2027-01-15 12:00 UTC

    private func insight(_ kind: TwinInsightKind, positive: Bool = false) -> TwinInsight {
        TwinInsight(kind: kind, headline: "Headline \(kind.rawValue)", detail: "", strength: .strong, basis: "9 games",
                    evidence: nil, values: [:], reason: "", positive: positive)
    }

    private let pain = KnowledgeLine(id: "body.pain.knee", area: .body, text: "Your knee hurt again.", basis: "2 times", safety: true)
    private let sleep = KnowledgeLine(id: "habits.sleep", area: .habits, text: "You usually sleep about 8 h.", basis: "20 nights")
    private let legs = KnowledgeLine(id: "body.legs", area: .body, text: "Your legs recover on day 4.", basis: "5 times")

    func testPainLeadsThenAPlanChangeThisWeekThenWhatsNew() {
        let effects = TwinPage.effects(legRecoveryDays: 4, legsReadyIn: 2, steers: [], games: [], event: "match", now: now, calendar: calendar)
        XCTAssertEqual(effects.first?.text, "Your hard leg days get 4 days to recover, so your legs are ready for hard work again Sunday.")

        let withPain = TwinPage.hero(lines: [legs, pain], firstSeen: [:], effects: effects, insights: [], coachRead: "Read", now: now, calendar: calendar)
        XCTAssertEqual(withPain.kind, .safety)
        XCTAssertEqual(withPain.text, pain.text)
        XCTAssertEqual(withPain.lineID, pain.id, "said once: the page leaves it out of the portrait below")

        let plan = TwinPage.hero(lines: [legs], firstSeen: [:], effects: effects, insights: [], coachRead: "Read", now: now, calendar: calendar)
        XCTAssertEqual(plan.kind, .plan)

        // Legs ready: the standing rule doesn't lead; a line learned this week does.
        let ready = TwinPage.effects(legRecoveryDays: 4, legsReadyIn: nil, steers: [], games: [], event: "match", now: now, calendar: calendar)
        XCTAssertFalse(ready[0].now)
        let fresh = TwinPage.hero(lines: [legs, sleep], firstSeen: ["habits.sleep": now.addingTimeInterval(-86_400), "body.legs": .distantPast],
                                  effects: ready, insights: [insight(.loadSpike)], coachRead: "Read", now: now, calendar: calendar)
        XCTAssertEqual(fresh.kind, .learned)
        XCTAssertEqual(fresh.text, sleep.text)

        // Nothing new for a week: what matters most, then the coach's read.
        let later = now.addingTimeInterval(8 * 86_400)
        let top = TwinPage.hero(lines: [sleep], firstSeen: ["habits.sleep": now], effects: [], insights: [insight(.mistakeReplay)],
                                coachRead: "Read", now: later, calendar: calendar)
        XCTAssertEqual(top.kind, .insight)
        let read = TwinPage.hero(lines: [], firstSeen: [:], effects: [], insights: [], coachRead: "Read", now: later, calendar: calendar)
        XCTAssertEqual(read.kind, .read)
        XCTAssertEqual(read.text, "Read")
    }

    func testAGameThisWeekNamesTheLightDay() {
        let saturday = now.addingTimeInterval(86_400 + 3_600)
        let effects = TwinPage.effects(legRecoveryDays: nil, legsReadyIn: nil, steers: [.slowGameRecovery], games: [saturday],
                                       event: "match", now: now, calendar: calendar)
        XCTAssertEqual(effects.first?.text, "You still feel a match two days later, so after Saturday's match, Monday stays light on the legs too.")
        XCTAssertEqual(effects.first?.now, true)
        let none = TwinPage.effects(legRecoveryDays: nil, legsReadyIn: nil, steers: [.slowGameRecovery], games: [], event: "match", now: now, calendar: calendar)
        XCTAssertEqual(none.first?.now, false, "no game this week: a standing rule, it doesn't lead")
        // A game yesterday makes tomorrow light: still this week's change.
        let yesterday = now.addingTimeInterval(-86_400)
        let after = TwinPage.effects(legRecoveryDays: nil, legsReadyIn: nil, steers: [.slowGameRecovery], games: [yesterday],
                                     event: "match", now: now, calendar: calendar)
        XCTAssertEqual(after.first?.text, "You still feel a match two days later, so after Thursday's match, tomorrow stays light on the legs too.")
    }

    /// Saturday and Wednesday games: Monday may be the week's heavy-leg slot
    /// (the planner's two-games exception), so the twin doesn't promise it light;
    /// Friday after Wednesday's game still is.
    func testATwoGameWeekDoesntPromiseALightDay() {
        let saturday = now.addingTimeInterval(86_400 + 3_600)
        let wednesday = saturday.addingTimeInterval(4 * 86_400)
        let effects = TwinPage.effects(legRecoveryDays: nil, legsReadyIn: nil, steers: [.slowGameRecovery], games: [saturday, wednesday],
                                       event: "match", now: now, calendar: calendar)
        XCTAssertFalse(effects.contains { $0.text.contains("Monday") })
        XCTAssertEqual(effects.first?.text, "You still feel a match two days later, so after Wednesday's match, Friday stays light on the legs too.")
    }

    func testAHiddenLineIsntSaidAgainInOtherWordsAndTheHeartNeverLeads() {
        // The athlete hid "habits.sleep": the older "8 h+ sleep" strength stays away too.
        let areas = TwinPage.portrait(lines: [], known: ["habits.sleep"], insights: [],
                                      strengths: [insight(.sleepBase, positive: true)], effects: [])
        XCTAssertTrue(areas.isEmpty)
        let heart = KnowledgeLine(id: "body.heart", area: .body, text: "Your usual resting heart rate is about 53.", basis: "28 nights")
        let hero = TwinPage.hero(lines: [heart], firstSeen: ["body.heart": now], effects: [], insights: [], coachRead: "Read",
                                 now: now, calendar: calendar)
        XCTAssertEqual(hero.kind, .read)
    }

    func testOnePortraitNothingSaidTwice() {
        let effects = [TwinPlanEffect(id: "body.legs", text: "…", now: false), TwinPlanEffect(id: "recoveryAfterGames", text: "…", now: false)]
        let areas = TwinPage.portrait(lines: [sleep, legs, pain], insights: [insight(.stressAndSleep), insight(.recoveryAfterGames)],
                                      strengths: [insight(.sleepBase, positive: true), insight(.strengthRising, positive: true)], effects: effects)
        // Pain leads its area, and its area leads the page.
        XCTAssertEqual(areas.first?.area, .body)
        XCTAssertEqual(areas.first?.entries.map(\.id), ["line.body.pain.knee", "line.body.legs", "insight.recoveryAfterGames"])
        // "You sleep 8 h+" is the knowledge engine's usual sleep already: said once.
        let habits = areas.first { $0.area == .habits }
        XCTAssertEqual(habits?.entries.map(\.id), ["line.habits.sleep"])
        XCTAssertEqual(areas.first { $0.area == .mind }?.entries.map(\.id), ["insight.stressAndSleep"])
        XCTAssertEqual(areas.first { $0.area == .training }?.entries.map(\.id), ["insight.strengthRising"])
        XCTAssertNil(areas.first { $0.area == .games }, "an empty area isn't shown")
    }

    func testStillLearningClosestFirstAndCapped() {
        let items = [
            LearningItem(id: "a", area: .games, question: "A", have: 2, need: 10, unit: "rated games"),
            LearningItem(id: "b", area: .habits, question: "B", have: 6, need: 7, unit: "nights"),
            LearningItem(id: "c", area: .body, question: "C", have: 9, need: 14, unit: "nights"),
            LearningItem(id: "d", area: .training, question: "D", have: 12, need: 15, unit: "games", checking: true)
        ]
        XCTAssertEqual(TwinPage.stillLearning(items).map(\.id), ["d", "b", "c"])
    }
}

final class TwinLearnedTests: XCTestCase {
    private func item(_ id: String, have: Int, need: Int = 10, checking: Bool = false) -> LearningItem {
        LearningItem(id: id, area: .games, question: "What your best games have in common", have: have, need: need,
                     unit: "rated games", checking: checking)
    }

    func testARatingMovesTheGamesCount() {
        let before = TwinKnowledge(lines: [], learning: [item("games.best", have: 3)], legRecoveryDays: nil)
        let after = TwinKnowledge(lines: [], learning: [item("games.best", have: 4)], legRecoveryDays: nil)
        XCTAssertEqual(TwinLearned.line(before: before, after: after, input: .gameRating),
                       "Your twin is learning what your best games have in common: 4 of 10 rated games so far.")
        XCTAssertNil(TwinLearned.line(before: after, after: after, input: .gameRating), "nothing moved: nothing said")
        XCTAssertNil(TwinLearned.line(before: before, after: after, input: .checkIn), "a check-in doesn't teach games")
    }

    func testANewLineIsSaidAndPainIsNot() {
        let sleep = KnowledgeLine(id: "habits.sleep", area: .habits, text: "You usually sleep about 8 h.", basis: "7 nights")
        let empty = TwinKnowledge(lines: [], learning: [], legRecoveryDays: nil)
        XCTAssertEqual(TwinLearned.line(before: empty, after: TwinKnowledge(lines: [sleep], learning: [], legRecoveryDays: nil), input: .checkIn),
                       "Your twin learned something new: You usually sleep about 8 h.")
        let games = KnowledgeLine(id: "games.best.sleep", area: .games, text: "Your best games came after longer sleep.", basis: "15 games")
        XCTAssertEqual(TwinLearned.line(before: empty, after: TwinKnowledge(lines: [games], learning: [], legRecoveryDays: nil), input: .gameRating),
                       "Your twin learned something new: Your best games came after longer sleep.")
        let pain = KnowledgeLine(id: "body.legs.pain", area: .body, text: "Your knee hurt again.", basis: "", safety: true)
        XCTAssertNil(TwinLearned.line(before: empty, after: TwinKnowledge(lines: [pain], learning: [], legRecoveryDays: nil), input: .checkIn))
    }

    /// The portrait shows three entries until "See all"; a pain line is never cut.
    func testThePortraitIsTrimmedToThreeButKeepsPain() {
        func line(_ id: String, _ area: KnowledgeLine.Area, safety: Bool = false) -> TwinPageEntry {
            .line(KnowledgeLine(id: id, area: area, text: id, basis: "", safety: safety))
        }
        let areas = [TwinPageArea(area: .body, entries: [line("a", .body), line("b", .body)]),
                     TwinPageArea(area: .training, entries: [line("c", .training), line("d", .training)]),
                     TwinPageArea(area: .habits, entries: [line("pain", .habits, safety: true)])]
        let trimmed = TwinPage.trimmed(areas, limit: 3)
        XCTAssertEqual(trimmed.flatMap(\.entries).map(\.id), ["line.a", "line.b", "line.c", "line.pain"])
        XCTAssertEqual(TwinPage.entryCount(areas), 5)
    }
}
