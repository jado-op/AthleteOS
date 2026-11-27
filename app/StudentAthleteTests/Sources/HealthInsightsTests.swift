import XCTest
#if canImport(Engine)
@testable import Engine
#endif

/// "More insights into your health" (owner, 2026-11-19): Apple Health is the
/// only source, a widget exists only when its data does, nothing is invented.
final class HealthInsightsTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 9))! }
    private var today: Date { calendar.startOfDay(for: now) }
    private func day(_ back: Int) -> Date { calendar.date(byAdding: .day, value: -back, to: today)! }

    /// `values` oldest first, the last one today.
    private func series(_ metric: HealthMetric, _ values: [Double], endingDaysAgo end: Int = 0) -> HealthSeries {
        let days = values.enumerated().map { HealthDay(date: day(end + values.count - 1 - $0.offset), value: $0.element) }
        return HealthSeries(metric: metric, days: days, latest: values.last, latestDate: days.last?.date)
    }

    private func night(_ back: Int, hours: Double, bedMinutes: Double = -60) -> HealthNight {
        let morning = day(back)
        let asleep = morning.addingTimeInterval(bedMinutes * 60)
        return HealthNight(morning: morning, asleepHours: hours, fellAsleep: asleep, wokeUp: asleep.addingTimeInterval(hours * 3600))
    }

    // MARK: Only what exists

    func testNoDataMeansNoWidgets() {
        XCTAssertTrue(HealthSnapshot.empty.isEmpty)
        XCTAssertEqual(HealthWidgetRegistry.available(in: .empty, now: now, calendar: calendar), [])
        XCTAssertTrue(HealthWidgetRegistry.sections(in: .empty, now: now, calendar: calendar).isEmpty)
    }

    func testAWidgetAppearsOnlyForItsOwnRecentData() {
        let snapshot = HealthSnapshot(series: [
            .steps: series(.steps, [8000, 9500, 10200]),
            .vo2Max: series(.vo2Max, [48.2], endingDaysAgo: 200),  // too old: hidden
            .bloodOxygen: series(.bloodOxygen, [98]),
        ])
        let shown = HealthWidgetRegistry.available(in: snapshot, now: now, calendar: calendar)
        XCTAssertTrue(shown.contains(.metric(.steps)))
        XCTAssertTrue(shown.contains(.metric(.bloodOxygen)))
        XCTAssertFalse(shown.contains(.metric(.vo2Max)), "a reading older than its freshness hides")
        XCTAssertFalse(shown.contains(.metric(.heartRateVariability)), "no HRV samples, no HRV widget")
        XCTAssertFalse(shown.contains(.sleep))
        XCTAssertFalse(shown.contains(.recovery), "recovery needs heart data and a usual")
        XCTAssertEqual(HealthWidgetRegistry.sections(in: snapshot, now: now, calendar: calendar).map(\.category), [.heart, .activity])
    }

    func testZeroStepsIsNotAMeasurement() {
        let snapshot = HealthSnapshot(series: [.flightsClimbed: series(.flightsClimbed, [0, 0, 0])])
        XCTAssertFalse(HealthWidgetRegistry.isAvailable(.metric(.flightsClimbed), in: snapshot, now: now, calendar: calendar))
    }

    /// The recovery word reads the heart the check-in's careful way (owner,
    /// 2026-11-27: one voice about the heart): a usual of 14+ days, two days not one.
    func testRecoveryNeedsAUsualToCompareWith() {
        let short = HealthSnapshot(series: [.restingHeartRate: series(.restingHeartRate, [52, 53, 51, 52, 50, 53, 52, 51, 58])])
        XCTAssertFalse(HealthWidgetRegistry.isAvailable(.recovery, in: short, now: now, calendar: calendar), "a week is not a usual")
        let usual: [Double] = Array(repeating: 52, count: 20)
        let oneDay = HealthSnapshot(series: [.restingHeartRate: series(.restingHeartRate, usual + [52, 58])])
        XCTAssertEqual(HealthRecovery.read(oneDay, now: now, calendar: calendar).recovery, .recovered, "one high morning is noise")
        let twoDays = HealthSnapshot(series: [.restingHeartRate: series(.restingHeartRate, usual + [58, 58])])
        XCTAssertTrue(HealthWidgetRegistry.isAvailable(.recovery, in: twoDays, now: now, calendar: calendar))
        let reading = HealthRecovery.read(twoDays, now: now, calendar: calendar)
        XCTAssertEqual(reading.recovery, .slightlyTired, "one sign (no HRV): a bit tired, never take it easy")
        XCTAssertEqual(reading.lines, ["Resting heart rate 58, 6 above your usual."])
    }

    func testWristTemperatureShowsOnlyAsADifferenceFromTheUsual() {
        let few = HealthSnapshot(series: [.wristTemperature: series(.wristTemperature, [34.1, 34.2])])
        XCTAssertFalse(HealthWidgetRegistry.isAvailable(.metric(.wristTemperature), in: few, now: now, calendar: calendar))
        let values = Array(repeating: 34.0, count: 14) + [34.5]
        let enough = HealthSnapshot(series: [.wristTemperature: series(.wristTemperature, values)])
        XCTAssertTrue(HealthWidgetRegistry.isAvailable(.metric(.wristTemperature), in: enough, now: now, calendar: calendar))
        let summary = enough.summary(.wristTemperature, now: now, calendar: calendar)!
        XCTAssertEqual(summary.deviation!, 0.5, accuracy: 0.001)
        XCTAssertEqual(summary.line(metric: true), "+0.50 °C against your usual.")
    }

    // MARK: The numbers behind each card

    func testSumMetricsCompareTheWeekWithTheWeekBefore() {
        // Today's 600 steps so far are not a finished day: the week is the 7 before.
        let values: [Double] = [5000, 5000, 5000, 5000, 5000, 5000, 5000, 6000, 6000, 6000, 6000, 6000, 6000, 6000, 600]
        let summary = HealthSummary(series(.steps, values), now: now, calendar: calendar)
        XCTAssertEqual(summary.week, 6000)
        XCTAssertEqual(summary.previousWeek, 5000)
        XCTAssertEqual(summary.today, 600)
        XCTAssertEqual(summary.line(metric: true), "6,000 steps a day this week, 20 % more than last week.")
    }

    func testExerciseCountsTowardSixtyMinutes() {
        let summary = HealthSummary(series(.exerciseMinutes, [30, 45]), now: now, calendar: calendar)
        XCTAssertEqual(summary.goalProgress!, 0.75, accuracy: 0.001)
    }

    func testAverageMetricsCompareWithTheUsual() {
        let values: [Double] = [60, 62, 61, 63, 60, 62, 61, 60, 62, 61, 63, 60, 62, 70]
        let summary = HealthSummary(series(.heartRateVariability, values), now: now, calendar: calendar)
        XCTAssertEqual(summary.usual, 61)
        XCTAssertEqual(summary.line(metric: true), "9 ms above your usual 61.")
        let learning = HealthSummary(series(.heartRateVariability, [60, 62]), now: now, calendar: calendar)
        XCTAssertNil(learning.usual)
        XCTAssertEqual(learning.line(metric: true), "Learning your usual: 6 more days.")
    }

    func testUnitsFollowThePhone() {
        XCTAssertEqual(HealthMetric.distance.format(10, metric: true), "10.0")
        XCTAssertEqual(HealthMetric.distance.format(10, metric: false), "6.2")
        XCTAssertEqual(HealthMetric.distance.unit(metric: false), "mi")
        XCTAssertEqual(HealthMetric.bodyTemperature.format(37, metric: false), "98.6")
        XCTAssertEqual(HealthMetric.steps.format(12345.4, metric: true), "12,345")
    }

    // MARK: Several sources, counted once

    func testTheSameWorkoutFromTwoSourcesCountsOnce() {
        let start = now.addingTimeInterval(-3 * 3600)
        let watch = HealthWorkout(id: "a", start: start, end: start.addingTimeInterval(3600), activity: "Run",
                                  source: "Garmin Connect", averageHeartRate: 158, distanceKm: 10, hasRoute: true)
        let phone = HealthWorkout(id: "b", start: start.addingTimeInterval(120), end: start.addingTimeInterval(3500),
                                  activity: "Run", source: "Strava")
        let later = HealthWorkout(id: "c", start: now.addingTimeInterval(-1800), end: now, activity: "Walk", source: "Strava")
        let unique = HealthWorkouts.unique([phone, watch, later, watch])
        XCTAssertEqual(unique.map(\.id), ["c", "a"], "the copy with the route and heart rate stays, newest first")
    }

    // MARK: Sleep

    func testSleepScheduleNeedsFiveNights() {
        let four = (1...4).map { night($0, hours: 8) }
        XCTAssertNil(SleepSchedule.summary(four, now: now, calendar: calendar))
        let nights = [night(1, hours: 8, bedMinutes: -60), night(2, hours: 8, bedMinutes: -90), night(3, hours: 8, bedMinutes: -30),
                      night(4, hours: 8, bedMinutes: -60), night(5, hours: 8, bedMinutes: -60)]
        let summary = SleepSchedule.summary(nights, now: now, calendar: calendar)!
        XCTAssertEqual(summary.bedtime, -60, accuracy: 0.01)
        XCTAssertEqual(SleepSchedule.clock(summary.bedtime), "23:00")
        XCTAssertEqual(SleepSchedule.clock(summary.wake), "07:00")
        XCTAssertEqual(summary.spread, 12, accuracy: 0.01)
        XCTAssertTrue(SleepSchedule.line(summary).hasPrefix("A steady rhythm"))
        let snapshot = HealthSnapshot(nights: nights)
        XCTAssertEqual(HealthWidgetRegistry.available(in: snapshot, now: now, calendar: calendar), [.sleep, .sleepSchedule])
    }

    func testSamplesBecomeNightsByMorningWithoutNapsOrDoubleCounting() {
        func at(_ back: Int, _ hour: Double) -> Date { day(back).addingTimeInterval(hour * 3600) }
        let samples = [
            // Last night: a watch with stages and a phone app that overlaps it.
            SleepStages.Sample(start: at(1, 23), end: at(0, 1), stage: .core, source: "watch"),
            SleepStages.Sample(start: at(0, 1), end: at(0, 2.5), stage: .deep, source: "watch"),
            SleepStages.Sample(start: at(0, 2.5), end: at(0, 3), stage: .awake, source: "watch"),
            SleepStages.Sample(start: at(0, 3), end: at(0, 7), stage: .rem, source: "watch"),
            SleepStages.Sample(start: at(1, 23.5), end: at(0, 6.5), stage: .unspecified, source: "app"),
            // A nap yesterday afternoon: not a night.
            SleepStages.Sample(start: at(1, 14), end: at(1, 15), stage: .unspecified, source: "app"),
            // The night before.
            SleepStages.Sample(start: at(2, 22), end: at(1, 6), stage: .unspecified, source: "app"),
        ]
        let nights = HealthNights.build(samples, calendar: calendar)
        XCTAssertEqual(nights.map(\.morning), [day(1), day(0)])
        XCTAssertEqual(nights[0].asleepHours, 8, accuracy: 0.001)
        XCTAssertEqual(nights[1].asleepHours, 8, accuracy: 0.001, "23:00–07:00 from two sources counted once")
        XCTAssertEqual(nights[1].fellAsleep, at(1, 23))
        XCTAssertEqual(nights[1].wokeUp, at(0, 7))
        XCTAssertEqual(nights[1].stages?.deep, 90)
        XCTAssertNil(nights[0].stages, "no stages recorded that night")
    }

    func testALieInPastNoonStaysOneNightAndAnEveningNapAddsNothing() {
        func at(_ back: Int, _ hour: Double) -> Date { day(back).addingTimeInterval(hour * 3600) }
        let samples = [
            // Saturday: asleep 01:00, up at 12:30, one block from a band.
            SleepStages.Sample(start: at(1, 1), end: at(1, 12.5), stage: .unspecified, source: "band"),
            // A nap 17:30–18:30 the same day.
            SleepStages.Sample(start: at(1, 17.5), end: at(1, 18.5), stage: .unspecified, source: "band"),
            // Then the real night.
            SleepStages.Sample(start: at(1, 23), end: at(0, 7), stage: .unspecified, source: "band"),
        ]
        let nights = HealthNights.build(samples, calendar: calendar)
        XCTAssertEqual(nights.map(\.morning), [day(1), day(0)])
        XCTAssertEqual(nights[0].asleepHours, 11.5, accuracy: 0.001, "the lie-in is kept whole")
        XCTAssertEqual(nights[1].asleepHours, 8, accuracy: 0.001, "the nap is not part of the night")
        XCTAssertEqual(nights[1].fellAsleep, at(1, 23))
    }

    func testHeartRateComparesTheDaysAverageNotOneSample() {
        var values = Array(repeating: 70.0, count: 14)
        values.append(74)
        var heart = series(.heartRate, values)
        heart.latest = 142  // a sample taken mid-practice
        let summary = HealthSummary(heart, now: now, calendar: calendar)
        XCTAssertEqual(summary.current, 74)
    }

    func testANearZeroDifferenceHasNoSign() {
        XCTAssertEqual(HealthFormat.number(-0.001, decimals: 2), "0.00")
    }

    func testAnOldNightHidesTheSleepCard() {
        let snapshot = HealthSnapshot(nights: [night(6, hours: 7.5)])
        XCTAssertFalse(HealthWidgetRegistry.isAvailable(.sleep, in: snapshot, now: now, calendar: calendar))
    }
}
