import XCTest
#if canImport(Engine)
@testable import Engine
#endif

/// "Your last 7 days": the week's numbers around the body (owner, 2026-11-20).
final class TwinWeekTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ back: Int, hour: Int = 12, from now: Date) -> Date {
        calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: now))!)!
    }

    func testTheWeeksNumbersComeFromTheAthletesOwnData() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let nights = (1...10).map { back in
            HealthNight(morning: day(back, hour: 7, from: now), asleepHours: back <= 6 ? 8 : 7,
                        fellAsleep: day(back + 1, hour: 23, from: now), wokeUp: day(back, hour: 7, from: now))
        }
        let steps = HealthSeries(metric: .steps, days: (0...13).map { HealthDay(date: day($0, hour: 0, from: now), value: 9_000) })
        let snapshot = HealthSnapshot(series: [.steps: steps], nights: nights)
        let training = [TwinWeek.Training(date: day(1, from: now), minutes: 50), TwinWeek.Training(date: day(3, from: now), minutes: 40),
                        TwinWeek.Training(date: day(9, from: now), minutes: 30)]
        let stats = TwinWeek.stats(snapshot: snapshot, training: training, now: now, calendar: calendar)
        let byID = Dictionary(uniqueKeysWithValues: stats.map { ($0.id, $0) })

        XCTAssertEqual(byID["sleep"]?.value, "8.0")
        XCTAssertEqual(byID["sleep"]?.anchor, .head)
        XCTAssertEqual(byID["sleep"]?.change, "+1.0 h vs last week")
        XCTAssertEqual(byID["steps"]?.value, "9,000")
        XCTAssertEqual(byID["steps"]?.change, "Same as last week")
        XCTAssertEqual(byID["training"]?.value, "90")
        XCTAssertEqual(byID["training"]?.change, "+60 min vs last week")
        XCTAssertEqual(byID["sessions"]?.value, "2")
        XCTAssertEqual(byID["training"]?.days.count, 7)
        XCTAssertNil(byID["restingHeartRate"], "nothing measured, nothing shown")
    }

    func testWithoutHealthTheTrainingStillShows() {
        let stats = TwinWeek.stats(snapshot: .empty, training: [], now: Date(timeIntervalSince1970: 1_790_000_000), calendar: calendar)
        XCTAssertEqual(stats.map(\.id), ["training", "sessions"])
        XCTAssertEqual(stats.first?.value, "0")
    }

    func testBubblesAlternateSidesTopToBottom() {
        func stat(_ id: String, _ anchor: TwinWeek.Anchor) -> TwinWeek.Stat {
            TwinWeek.Stat(id: id, title: id, value: "1", unit: "", symbol: "circle", anchor: anchor, change: nil, days: [], fromHealth: true)
        }
        let columns = TwinWeek.columns([stat("steps", .legs), stat("sleep", .head), stat("heart", .chest), stat("training", .core)])
        XCTAssertEqual(columns.left.map(\.id), ["sleep", "training"])
        XCTAssertEqual(columns.right.map(\.id), ["heart", "steps"])
    }
}
