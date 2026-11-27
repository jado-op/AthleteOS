import XCTest
#if canImport(Engine)
@testable import Engine
#endif

/// Heart data the careful way: the athlete's own usual, two nights not one,
/// the athlete asked instead of guessed, never a diagnosis.
final class HeartSignalsTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let now = Date(timeIntervalSince1970: 1_800_014_400) // 2027-01-15 12:00 UTC

    private func nights(_ values: [Int: Double]) -> [HeartNight] {
        values.map { back, value in
            HeartNight(date: calendar.startOfDay(for: calendar.date(byAdding: .day, value: -back, to: now)!), value: value)
        }.sorted { $0.date < $1.date }
    }

    /// 28 usual nights at 52 bpm before the last two.
    private func usualPlus(_ recent: [Int: Double]) -> [HeartNight] {
        var values: [Int: Double] = [:]
        for back in 2...29 { values[back] = 52 }
        for (back, value) in recent { values[back] = value }
        return nights(values)
    }

    /// HRV at 60 for weeks, then 50 on the three days up to yesterday.
    private var lowVariability: [HeartNight] {
        var hrv: [Int: Double] = [:]
        for back in 4...31 { hrv[back] = 60 }
        for back in 1...3 { hrv[back] = 50 }
        return nights(hrv)
    }

    func testTwoRaisedNightsAreASignOneIsNot() {
        // Raised alone: quiet, but no "normal" guess either.
        let alone = HeartSignals.morning(restingHeartRate: usualPlus([1: 57, 0: 58]), variability: [], now: now, calendar: calendar)
        XCTAssertTrue(alone.raised)
        XCTAssertEqual(alone.usual, 52)
        XCTAssertNil(alone.note, "one sign is not enough to say anything (T8)")
        XCTAssertNil(HeartSignals.energyPrefill(alone), "raised: the athlete is asked, not guessed for")

        // Raised and variability low: two signs agree, the note shows.
        let two = HeartSignals.morning(restingHeartRate: usualPlus([1: 57, 0: 58]), variability: lowVariability, now: now, calendar: calendar)
        XCTAssertTrue(two.variabilityLow)
        XCTAssertTrue(two.note?.contains("58, usually 52") ?? false)
        XCTAssertFalse(two.note?.lowercased().contains("sick") ?? true, "never a diagnosis")

        let one = HeartSignals.morning(restingHeartRate: usualPlus([1: 52, 0: 60]), variability: [], now: now, calendar: calendar)
        XCTAssertFalse(one.raised)
        XCTAssertNil(one.note)
        XCTAssertEqual(HeartSignals.energyPrefill(one), 4)
    }

    func testSmallRiseIsNotASign() {
        // +2 bpm is under max(3 bpm, 5%).
        let morning = HeartSignals.morning(restingHeartRate: usualPlus([1: 54, 0: 54]), variability: [], now: now, calendar: calendar)
        XCTAssertFalse(morning.raised)
    }

    func testEarlyMorningUsesTheTwoDaysBefore() {
        // No value today yet: yesterday and the day before are the two nights.
        var values: [Int: Double] = [:]
        for back in 3...30 { values[back] = 52 }
        values[2] = 58
        values[1] = 58
        let morning = HeartSignals.morning(restingHeartRate: nights(values), variability: [], now: now, calendar: calendar)
        XCTAssertTrue(morning.raised)
    }

    func testNoUsualBeforeFourteenNights() {
        var values: [Int: Double] = [:]
        for back in 0...10 { values[back] = 52 }
        let morning = HeartSignals.morning(restingHeartRate: nights(values), variability: [], now: now, calendar: calendar)
        XCTAssertNil(morning.usual)
        XCTAssertNil(HeartSignals.energyPrefill(morning), "no usual, no guess (T1)")
    }

    func testLowVariabilityHoldsBackTheGuess() {
        let morning = HeartSignals.morning(restingHeartRate: usualPlus([1: 52, 0: 52]), variability: lowVariability, now: now, calendar: calendar)
        XCTAssertTrue(morning.variabilityLow)
        XCTAssertNil(HeartSignals.energyPrefill(morning))
    }

    func testTwinLineSaysTheUsualAndHowItMoved() {
        var values: [Int: Double] = [:]
        for back in 0...90 { values[back] = back > 56 ? 58 : 53 }
        let input = KnowledgeInput(base: TwinInput(now: now), restingHeart: nights(values))
        let line = TwinKnowledgeEngine.build(input, calendar: calendar).lines.first { $0.id == "body.heart" }
        XCTAssertEqual(line?.text, "Your usual resting heart rate is about 53 beats a minute. It has come down from about 58 two months ago — that often goes with getting fitter.")

        let few = KnowledgeInput(base: TwinInput(now: now), restingHeart: nights([1: 52, 2: 52]))
        let learning = TwinKnowledgeEngine.build(few, calendar: calendar).learning.first { $0.id == "body.heart" }
        XCTAssertEqual(learning?.progress, "2 of 14 nights from your watch so far")

        let none = TwinKnowledgeEngine.build(KnowledgeInput(base: TwinInput(now: now)), calendar: calendar)
        XCTAssertNil(none.learning.first { $0.id == "body.heart" }, "no watch: nothing to learn here")
    }

    func testNoRecentReadingNoGuess() {
        // Twenty nights two weeks ago, then the watch stayed in a drawer.
        var values: [Int: Double] = [:]
        for back in 14...34 { values[back] = 52 }
        let morning = HeartSignals.morning(restingHeartRate: nights(values), variability: [], now: now, calendar: calendar)
        XCTAssertNil(HeartSignals.energyPrefill(morning))
        XCTAssertFalse(morning.raised)
    }

    func testANewWatchIsNotAChangeOfHeart() {
        // Months on a ring reading 51; an Apple Watch reads 58 from two days ago.
        var all: [HeartNight] = []
        for back in 2...60 {
            all.append(HeartNight(date: calendar.startOfDay(for: calendar.date(byAdding: .day, value: -back, to: now)!), value: 51, source: "ring"))
        }
        for back in 0...1 {
            all.append(HeartNight(date: calendar.startOfDay(for: calendar.date(byAdding: .day, value: -back, to: now)!), value: 58, source: "watch"))
        }
        let morning = HeartSignals.morning(restingHeartRate: all, variability: [], now: now, calendar: calendar)
        XCTAssertFalse(morning.raised, "the ring still has most days this week, and the watch has no usual of its own yet")
        // A week later the watch is the device: it starts its own usual.
        let later = all + (2...8).map { back in
            HeartNight(date: calendar.startOfDay(for: calendar.date(byAdding: .day, value: -back, to: now)!), value: 58, source: "watch")
        }
        let switched = HeartSignals.morning(restingHeartRate: later.filter { !($0.source == "ring" && $0.date >= calendar.date(byAdding: .day, value: -8, to: now)!) },
                                            variability: [], now: now, calendar: calendar)
        XCTAssertNil(switched.usual, "a new device learns its own usual first")
        XCTAssertFalse(switched.raised)
    }
}
