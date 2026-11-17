import XCTest
#if canImport(Engine)
@testable import Engine
#endif

final class TwinScoringTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_800_000_000)

    private func effect(_ pillar: TwinPillar, _ side: TwinSide, _ delta: Int, area: String? = nil, trait: String? = nil,
                        ego: Int? = nil, daysLater: Double = 0) -> TwinEffect {
        TwinEffect(date: day.addingTimeInterval(daysLater * 86_400), source: "test",
                   spec: TwinEffectSpec(pillar: pillar, side: side, delta: delta, area: area, trait: trait, ego: ego))
    }

    func testAnEmptyTwinIsZeroEverywhere() {
        let twin = TwinScoring.snapshot([], sportAreas: ["glutes"])
        for pillar in TwinPillar.allCases {
            XCTAssertEqual(twin.score(pillar), TwinPillarScore())
        }
        XCTAssertTrue(twin.bodyAreas.isEmpty)
        XCTAssertTrue(twin.traits.isEmpty)
        XCTAssertEqual(twin.egoBalance, 0)
        XCTAssertEqual(twin.overall, 0)
    }

    func testKnowledgeAndHabitsAreSeparateAndAveraged() {
        let twin = TwinScoring.snapshot([effect(.recovery, .knowledge, 10), effect(.recovery, .habits, 4), effect(.recovery, .knowledge, 2)],
                                        sportAreas: [])
        XCTAssertEqual(twin.score(.recovery).knowledge, 12)
        XCTAssertEqual(twin.score(.recovery).habits, 4)
        XCTAssertEqual(twin.score(.recovery).total, 8)
        XCTAssertEqual(twin.score(.fuel).total, 0)
    }

    func testScoresStayWithin0And100() {
        let many = (0..<40).map { _ in effect(.mind, .knowledge, 10) }
        XCTAssertEqual(TwinScoring.snapshot(many, sportAreas: []).score(.mind).knowledge, 100)
    }

    func testWeakestPillarIsTheLowestAndTiesFollowTheOrder() {
        XCTAssertEqual(TwinScoring.snapshot([], sportAreas: []).weakest, .body)
        let ledger = TwinPillar.allCases.filter { $0 != .recovery }.map { effect($0, .knowledge, 10) }
        XCTAssertEqual(TwinScoring.snapshot(ledger, sportAreas: []).weakest, .recovery)
    }

    func testSportMusclesLightUpAsBodyGrowsFirstOnesFirst() {
        let areas = ["thighBack", "glutes", "abs"]
        let low = TwinScoring.snapshot([effect(.body, .knowledge, 10)], sportAreas: areas)
        let high = TwinScoring.snapshot([effect(.body, .knowledge, 60), effect(.body, .habits, 60)], sportAreas: areas)
        XCTAssertGreaterThan(low.bodyAreas["thighBack"] ?? 0, 0)
        XCTAssertGreaterThan(low.bodyAreas["thighBack"] ?? 0, low.bodyAreas["abs"] ?? 0)
        XCTAssertGreaterThan(high.bodyAreas["thighBack"] ?? 0, low.bodyAreas["thighBack"] ?? 0)
        XCTAssertLessThanOrEqual(high.bodyAreas.values.max() ?? 0, 1)
        XCTAssertNil(low.bodyAreas["chest"])
    }

    func testALessonsOwnRegionGlowsOnTop() {
        let twin = TwinScoring.snapshot([effect(.body, .knowledge, 5, area: "chest")], sportAreas: ["glutes"])
        XCTAssertGreaterThan(twin.bodyAreas["chest"] ?? 0, 0)
        // Areas only light from Body effects.
        let fuel = TwinScoring.snapshot([effect(.fuel, .knowledge, 5, area: "chest")], sportAreas: [])
        XCTAssertNil(fuel.bodyAreas["chest"])
    }

    func testTraitsUnlockOnceInOrder() {
        let twin = TwinScoring.snapshot([effect(.legends, .knowledge, 5, trait: "craft"), effect(.mind, .habits, 3, trait: "composure"),
                                         effect(.legends, .knowledge, 5, trait: "craft")], sportAreas: [])
        XCTAssertEqual(twin.traits, ["craft", "composure"])
    }

    func testEgoBalanceLeansAndStaysWithinOne() {
        XCTAssertLessThan(TwinScoring.snapshot([effect(.mind, .habits, 1, ego: -2)], sportAreas: []).egoBalance, 0)
        XCTAssertGreaterThan(TwinScoring.snapshot([effect(.mind, .habits, 1, ego: 1)], sportAreas: []).egoBalance, 0)
        let lots = (0..<10).map { _ in effect(.mind, .habits, 1, ego: 2) }
        XCTAssertEqual(TwinScoring.snapshot(lots, sportAreas: []).egoBalance, 1)
    }

    func testBeforeVsNowCutsTheLedgerAtADate() {
        let ledger = [effect(.fuel, .knowledge, 10), effect(.fuel, .knowledge, 20, daysLater: 5)]
        XCTAssertEqual(TwinScoring.snapshot(ledger, sportAreas: [], until: day.addingTimeInterval(86_400)).score(.fuel).knowledge, 10)
        XCTAssertEqual(TwinScoring.snapshot(ledger, sportAreas: []).score(.fuel).knowledge, 30)
    }

    func testDeltasAndTheLevelUpLine() {
        let before = TwinScoring.snapshot([], sportAreas: [])
        let after = TwinScoring.snapshot([effect(.recovery, .knowledge, 8), effect(.recovery, .habits, 4), effect(.mind, .knowledge, 2)],
                                         sportAreas: [])
        let deltas = TwinScoring.deltas(from: before, to: after)
        XCTAssertEqual(deltas.map(\.pillar), [.recovery, .mind])
        XCTAssertEqual(deltas.first?.change, 6)
        XCTAssertEqual(TwinScoring.line(for: deltas[0]), "+6 Recovery — your battery is charging")
    }
}
