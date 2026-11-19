import XCTest
#if canImport(Engine)
@testable import Engine
#endif

/// The athlete's own gym session (owner, 2026-11-19): focus + length, anchors
/// that hold for a block, accessories that rotate, and "you pick" that reads
/// what was trained when (docs/GYM-ALGORITHM-RESEARCH.md).
final class GymFocusTests: XCTestCase {
    private static let catalogue: Catalogue = {
        let dist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "content/dist")
        let fallback = URL(fileURLWithPath: ProcessInfo.processInfo.environment["AOS_CONTENT_DIST"] ?? "/root/fitness/content/dist")
        return CatalogueLoader.load(from: FileManager.default.fileExists(atPath: dist.path) ? dist : fallback)
    }()

    private let fullGym: Set<String> = ["dumbbell", "barbell", "rack", "bench", "pull-up-bar", "band", "box", "med-ball", "wall", "cones",
                                        "kettlebell", "weight-plate", "trap-bar", "low-bar", "step", "mini-band", "slider", "cable-machine",
                                        "lat-pulldown", "foam-roller", "jump-rope", "bumper-plates", "landmine", "hurdle", "ball", "stick", "partner"]
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    private func day(phase: SeasonPhase = .offSeason, nextGame: Int? = nil, practice: PracticeIntensity? = nil,
                     gym: GymRequest?, date: Date? = nil) -> TrainingDay {
        var day = TrainingDay(date: date ?? self.date, phase: phase, age: 16, experience: .intermediate,
                              demands: SportDemandsTable.demands(sport: Self.catalogue.sportsBySlug["soccer"], position: nil),
                              practice: practice, daysToNextGame: nextGame, plannedGymDay: true)
        day.gym = gym
        return day
    }

    private func build(_ day: TrainingDay, seed: String = "test") -> (SessionDecision, GeneratedSession) {
        let decision = SessionPlanner.decide(day, requested: .gymDevelopment)
        let kit = AthleteKit(catalogue: Self.catalogue, sport: Self.catalogue.sportsBySlug["soccer"], equipment: fullGym, seed: seed)
        return (decision, SessionBuilder.build(decision, day: day, kit: kit))
    }

    private func request(_ focus: GymFocus, _ length: GymLength, last: Set<String> = [], stalled: Set<String> = []) -> GymRequest {
        GymRequest(focus: focus, length: length, anchorSeed: "athlete|1", stalledAnchors: stalled, lastAccessories: last)
    }

    private func anchors(_ session: GeneratedSession) -> [String] {
        session.items.filter { $0.rationale.hasPrefix("Anchor") }.map(\.itemSlug)
    }

    private func profile(_ slug: String) -> ExerciseProfile? { Self.catalogue.item(slug)?.planProfile }

    func testUpperBodyTrainsNoLegs() {
        let (decision, session) = build(day(gym: request(.upper, .standard)))
        XCTAssertEqual(decision.gymFocus, .upper)
        XCTAssertEqual(session.title, "Upper body")
        for item in session.items where [.primaryStrength, .secondaryStrength].contains(item.block) {
            XCTAssertFalse(profile(item.itemSlug)?.isLower ?? true, "\(item.itemSlug) is a leg lift in an upper-body session")
        }
        XCTAssertEqual(anchors(session).count, 2, "one push, one pull")
    }

    func testLegsHaveSquatAndHingeAnchors() {
        let (_, session) = build(day(gym: request(.lower, .standard)))
        let groups = anchors(session).compactMap { profile($0)?.group }
        XCTAssertTrue(groups.contains { $0.hasPrefix("squat") || $0 == "single-leg-knee" }, "\(groups)")
        XCTAssertTrue(groups.contains { $0.hasPrefix("hinge") || $0 == "single-leg-hip" }, "\(groups)")
    }

    func testLengthsTakeTheirTime() {
        for length in GymLength.allCases {
            let (decision, session) = build(day(gym: request(.full, length)))
            XCTAssertEqual(decision.durationTarget, length.minutes)
            XCTAssertLessThanOrEqual(abs(session.estimatedMinutes - length.minutes), length == .quick ? 8 : 15,
                                     "\(length): \(session.estimatedMinutes) min")
        }
    }

    func testFullLengthEndsWithAFinisherAndQuickHasNone() {
        let (full, fullSession) = build(day(gym: request(.full, .full)))
        XCTAssertNotNil(full.conditioning)
        XCTAssertTrue(fullSession.items.contains { $0.block == .conditioning })
        let (quick, quickSession) = build(day(gym: request(.full, .quick)))
        XCTAssertNil(quick.conditioning)
        XCTAssertFalse(quickSession.items.contains { $0.block == .conditioning })
    }

    func testAnchorsStayAcrossSessionsAndAccessoriesRotate() {
        let first = build(day(gym: request(.upper, .standard)), seed: "monday").1
        let later = Calendar.current.date(byAdding: .day, value: 3, to: date)!
        let accessories = Set(first.items.filter { $0.block == .accessory }.map(\.itemSlug))
        let second = build(day(gym: request(.upper, .standard, last: accessories), date: later), seed: "thursday").1
        XCTAssertEqual(Set(anchors(first)), Set(anchors(second)), "anchors hold for the block")
        let next = Set(second.items.filter { $0.block == .accessory && !$0.rationale.hasPrefix("Anchor") }.map(\.itemSlug))
        XCTAssertFalse(next.isEmpty)
        XCTAssertNotEqual(next, accessories.subtracting(anchors(first)), "accessories change session to session")
    }

    func testAStalledAnchorIsSwappedForItsSibling() {
        let first = build(day(gym: request(.upper, .standard))).1
        guard let stalled = anchors(first).first else { return XCTFail("no anchors") }
        let second = build(day(gym: request(.upper, .standard, stalled: [stalled]))).1
        XCTAssertFalse(anchors(second).contains(stalled))
    }

    func testLegsBeforeAGameStayLight() {
        let (decision, session) = build(day(phase: .inSeason, nextGame: 1, gym: request(.lower, .standard)))
        XCTAssertLessThan(decision.legBudget, 2)
        for item in session.items where item.block != .prep {
            XCTAssertLessThan(profile(item.itemSlug)?.legLoad ?? 0, 2, "\(item.itemSlug) is heavy legs the day before a game")
        }
    }

    // MARK: You pick

    func testAdvisorPicksTheRegionMissingLongest() {
        let history = GymHistory(daysSince: [.upper: 1, .core: 2, .lower: 5])
        let advice = GymAdvisor.advise(day: day(gym: nil), history: history)
        XCTAssertEqual(advice.focus, .lower)
        XCTAssertTrue(advice.reason.contains("upper body yesterday"), advice.reason)
    }

    func testAdvisorKeepsLegsFreshBeforeAGame() {
        let history = GymHistory(daysSince: [.upper: 4, .lower: 9])
        let advice = GymAdvisor.advise(day: day(phase: .inSeason, nextGame: 1, gym: nil), history: history)
        XCTAssertNotEqual(advice.focus, .lower)
        XCTAssertNotEqual(advice.focus, .full)
        XCTAssertNotNil(advice.notToday[.lower])
    }

    func testShortMeasuredSleepShortensTheSession() {
        let history = GymHistory(daysSince: [.upper: 4, .lower: 4], measuredSleepHours: 5.5)
        XCTAssertNotNil(GymAdvisor.advise(day: day(gym: nil), history: history).notToday[.lower], "under 6 h: no heavy legs")
        let advice = GymAdvisor.advise(day: day(gym: nil), history: history)
        XCTAssertEqual(advice.length, .quick)
        XCTAssertTrue(advice.reason.contains("slept"), advice.reason)
    }

    // MARK: Athlete evidence (docs/GYM-ALGORITHM-RESEARCH.md Part 2)

    func testTwoDaysBeforeAGameLegsStayAllowedButLight() {
        let history = GymHistory(daysSince: [.upper: 1, .core: 1, .lower: 9])
        let advice = GymAdvisor.advise(day: day(phase: .inSeason, nextGame: 2, gym: nil), history: history)
        XCTAssertNil(advice.notToday[.lower], "two days out legs are allowed (A6)")
        let (decision, _) = build(day(phase: .inSeason, nextGame: 2, gym: request(.lower, .standard)))
        XCTAssertTrue(decision.avoids(.highVolumeLowerBody), "but short: few sets")
    }

    func testInSeasonLegsComeBackAfterAWeek() {
        let history = GymHistory(daysSince: [.upper: 3, .core: 3, .lower: 9])
        let advice = GymAdvisor.advise(day: day(phase: .inSeason, gym: nil), history: history)
        XCTAssertTrue(advice.focus == .lower || advice.focus == .full, "\(advice.focus): \(advice.reason)")
    }

    func testLegDaysCarryTheSportsNordicAndCopenhagen() {
        let (_, session) = build(day(gym: request(.lower, .standard)))
        let groups = session.items.compactMap { profile($0.itemSlug)?.group }
        XCTAssertTrue(groups.contains("hamstring-eccentric"), "soccer leg day without Nordics: \(groups)")
        XCTAssertTrue(groups.contains("hip-adductor"), "soccer leg day without Copenhagen: \(groups)")
        let (_, quick) = build(day(gym: request(.lower, .quick)))
        XCTAssertTrue(quick.items.contains { profile($0.itemSlug)?.group == "hamstring-eccentric" }, "even quick keeps the Nordic")
    }

    func testTrainedAthletesRideEasyAfterHeavyLegs() {
        var experienced = day(gym: request(.lower, .full))
        experienced.age = 17
        experienced.experience = .experienced
        let decision = SessionPlanner.decide(experienced, requested: .gymDevelopment)
        XCTAssertEqual(decision.conditioning, .aerobicBase, "no hard intervals after heavy legs (A26)")
    }

    func testFullBodyWhenEverythingIsFresh() {
        let advice = GymAdvisor.advise(day: day(gym: nil), history: GymHistory())
        XCTAssertEqual(advice.focus, .full)
    }
}
