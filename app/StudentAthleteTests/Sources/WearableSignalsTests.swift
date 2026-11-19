import XCTest
#if canImport(Engine)
@testable import Engine
#endif

/// The twin's "What your watch sees" (owner, 2026-11-19): today against the
/// athlete's own usual, and recovery as a word, never a score.
final class WearableSignalsTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 8))! }

    private func series(_ values: [Double]) -> [TwinPoint] {
        let today = calendar.startOfDay(for: now)
        return values.enumerated().map { index, value in
            TwinPoint(date: calendar.date(byAdding: .day, value: -(values.count - 1 - index), to: today)!, value: value)
        }
    }

    func testTodayIsComparedWithTheMedianOfTheWeekBefore() {
        let reading = WearableRead.reading(series([50, 52, 51, 53, 50, 52, 51, 58]), now: now, calendar: calendar)
        XCTAssertEqual(reading?.today, 58)
        XCTAssertEqual(reading?.usual, 51)
        XCTAssertEqual(reading?.difference, 7)
        // Less than a week before today: no usual yet.
        XCTAssertNil(WearableRead.reading(series([50, 52, 58]), now: now, calendar: calendar)?.usual)
        // Nothing from today: nothing to read.
        let old = series([50, 52, 51, 53, 50, 52, 51, 58]).dropLast()
        XCTAssertNil(WearableRead.reading(Array(old), now: now, calendar: calendar))
    }

    func testRecoveryIsAWordFromTheCheckInThresholds() {
        let calm = SignalReading(today: 52, usual: 51)
        XCTAssertEqual(WearableRead.recovery(heartRate: calm, variability: SignalReading(today: 60, usual: 62)), .recovered)
        XCTAssertEqual(WearableRead.recovery(heartRate: SignalReading(today: 55, usual: 51), variability: nil), .slightlyTired)
        XCTAssertEqual(WearableRead.recovery(heartRate: calm, variability: SignalReading(today: 40, usual: 62)), .takeItEasy)
        XCTAssertEqual(WearableRead.recovery(heartRate: SignalReading(today: 55, usual: nil), variability: nil), .learning)
        XCTAssertNil(WearableRead.recovery(heartRate: nil, variability: nil))
        XCTAssertEqual(WearableRead.Recovery.takeItEasy.word, "Take it easy.")
    }

    func testTheLinesSayTheNumbers() {
        XCTAssertEqual(WearableRead.heartRateLine(SignalReading(today: 54.4, usual: 51), kind: .resting),
                       "Resting heart rate 54, 3 above your usual.")
        XCTAssertEqual(WearableRead.heartRateLine(SignalReading(today: 51, usual: 51.2), kind: .lowestAsleep),
                       "Lowest heart rate asleep 51, your usual.")
        XCTAssertEqual(WearableRead.variabilityLine(SignalReading(today: 70, usual: 60)), "Variability 70 ms, above your usual 60.")
        XCTAssertEqual(WearableRead.variabilityLine(SignalReading(today: 61, usual: 60)), "Variability 61 ms, your usual.")
        XCTAssertNil(WearableRead.sleepLine([]))
        XCTAssertEqual(WearableRead.sleepLine(series([8.5, 9, 7.5])), "2 of 3 nights at 8 hours or more. Right where your body builds.")
        XCTAssertTrue(WearableSignals(sleep: series([7])).hasData)
        XCTAssertFalse(WearableSignals().hasData)
    }
}
