import XCTest
#if canImport(Engine)
@testable import Engine
#endif

/// The twin's health insights (owner, 2026-11-19): today against the
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
        XCTAssertEqual(WearableRead.heartRateLine(SignalReading(today: 54.4, usual: 51)),
                       "Resting heart rate 54, 3 above your usual.")
        XCTAssertEqual(WearableRead.heartRateLine(SignalReading(today: 51, usual: 51.2)),
                       "Resting heart rate 51, your usual.")
        XCTAssertEqual(WearableRead.variabilityLine(SignalReading(today: 70, usual: 60)), "Variability 70 ms, above your usual 60.")
        XCTAssertEqual(WearableRead.variabilityLine(SignalReading(today: 61, usual: 60)), "Variability 61 ms, your usual.")
        XCTAssertNil(WearableRead.sleepLine([]))
        XCTAssertEqual(WearableRead.sleepLine(series([8.5, 9, 7.5])), "2 of 3 nights at 8 hours or more. Right where your body builds.")
    }

    // MARK: Brand and band

    func testABrandIsNamedOnlyFromItsOwnName() {
        XCTAssertNil(WearableBrand.name(fromSource: "Google Health"), "no brand-specific rules")
        XCTAssertEqual(WearableBrand.name(fromSource: "Fitbit"), "Fitbit")
        XCTAssertEqual(WearableBrand.name(fromSource: "Suunto"), "Suunto")
        XCTAssertEqual(WearableBrand.name(fromSource: "Garmin Connect"), "Garmin")
        XCTAssertNil(WearableBrand.name(fromSource: "Jacob's Apple Watch"))
        XCTAssertNil(WearableBrand.name(fromSource: nil))
    }

    // MARK: Sleep stages

    private func at(_ minutes: Double) -> Date { now.addingTimeInterval(-8 * 3600 + minutes * 60) }
    private func sample(_ from: Double, _ to: Double, _ stage: SleepStages.Stage, _ source: String = "google") -> SleepStages.Sample {
        SleepStages.Sample(start: at(from), end: at(to), stage: stage, source: source)
    }

    func testStagesAddUpPerStage() {
        let night = [sample(0, 90, .core), sample(90, 150, .deep), sample(150, 160, .awake), sample(160, 250, .rem),
                     sample(250, 400, .core), sample(400, 430, .deep)]
        let stages = SleepStages.from(night)
        XCTAssertEqual(stages?.deep ?? 0, 90, accuracy: 0.01)
        XCTAssertEqual(stages?.rem ?? 0, 90, accuracy: 0.01)
        XCTAssertEqual(stages?.core ?? 0, 240, accuracy: 0.01)
        XCTAssertEqual(stages?.awake ?? 0, 10, accuracy: 0.01)
        XCTAssertEqual(stages?.line, "Deep 1h 30m · REM 1h 30m")
    }

    func testTwoDevicesOnOneNightDontAddUp() {
        // The band recorded the most staged sleep: only its night counts.
        let band = [sample(0, 120, .core), sample(120, 200, .deep), sample(200, 300, .rem)]
        let watch = [sample(10, 60, .deep, "watch"), sample(60, 100, .rem, "watch")]
        let stages = SleepStages.from(band + watch)
        XCTAssertEqual(stages?.deep ?? 0, 80, accuracy: 0.01)
        XCTAssertEqual(stages?.asleep ?? 0, 300, accuracy: 0.01)
    }

    func testOverlappingSamplesCountOnce() {
        let stages = SleepStages.from([sample(0, 120, .core), sample(60, 180, .core)])
        XCTAssertEqual(stages?.core ?? 0, 180, accuracy: 0.01)
    }

    func testNoStagesOrTooLittleIsNil() {
        XCTAssertNil(SleepStages.from([]))
        XCTAssertNil(SleepStages.from([sample(0, 30, .core), sample(30, 300, .awake)]))
    }
}
