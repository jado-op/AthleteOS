import XCTest
#if canImport(Engine)
@testable import Engine
#endif

final class SleepMathTests: XCTestCase {
    private let calendar = Calendar.current
    private let reference = Date(timeIntervalSince1970: 1_790_000_000)

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: reference)!
    }

    // §17: sum asleep stages, merge overlapping sources

    func testOverlappingPhoneAndWatchSamplesAreNotDoubleCounted() {
        let intervals: [(start: Date, end: Date)] = [
            (at(22), at(23, 30)),
            (at(23), at(23, 59)),      // overlaps the first
            (at(23, 59), at(23, 59)),  // zero-length, ignored
        ]
        XCTAssertEqual(SleepMath.asleepHours(intervals), 2 - 1.0 / 60, accuracy: 0.001)
    }

    func testSeparateBlocksAddUp() {
        let intervals: [(start: Date, end: Date)] = [(at(1), at(3)), (at(4), at(7))]
        XCTAssertEqual(SleepMath.asleepHours(intervals), 5, accuracy: 0.001)
        XCTAssertEqual(SleepMath.label(7 + 40.0 / 60), "7h 40m")
    }
}
