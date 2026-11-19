import Foundation

/// Screenshots only (`-demoData`, never a real launch; see `DemoData`): a
/// believable month of Apple Health for the health insights page. Real
/// athletes only ever see what their own Health holds.
enum HealthDemo {
    static func snapshot(now: Date = .now, calendar: Calendar = .current) -> HealthSnapshot {
        let today = calendar.startOfDay(for: now)
        func day(_ back: Int) -> Date { calendar.date(byAdding: .day, value: -back, to: today) ?? today }
        func wave(_ index: Int, _ period: Double, _ size: Double) -> Double { sin(Double(index) * period) * size }
        func series(_ metric: HealthMetric, days: Int = 28, every: Int = 1, _ value: (Int) -> Double,
                    range: Double? = nil) -> HealthSeries {
            let points = stride(from: days - 1, through: 0, by: -every).map { back -> HealthDay in
                let index = days - 1 - back
                let v = value(index)
                return HealthDay(date: day(back), value: v, low: range.map { v - $0 }, high: range.map { v + $0 * 1.8 })
            }
            let last = points.last
            return HealthSeries(metric: metric, days: points, latest: last?.value,
                                latestDate: last.map { $0.date.addingTimeInterval(7.5 * 3600) }, latestSource: "Apple Watch")
        }

        var all: [HealthMetric: HealthSeries] = [:]
        all[.restingHeartRate] = series(.restingHeartRate) { 53 + wave($0, 0.45, 1.6) + Double(($0 * 7) % 3) * 0.6 - ($0 == 27 ? 2 : 0) }
        all[.heartRateVariability] = series(.heartRateVariability) { 64 + wave($0, 0.38, 4) + Double(($0 * 11) % 3) * 1.2 + ($0 == 27 ? 7 : 0) }
        all[.heartRate] = series(.heartRate, { 74 + wave($0, 0.6, 5) }, range: 20)
        all[.walkingHeartRate] = series(.walkingHeartRate) { 96 - Double($0) * 0.1 + wave($0, 0.5, 2) }
        all[.heartRateRecovery] = series(.heartRateRecovery, every: 4) { 31 + Double($0) * 0.15 + wave($0, 0.9, 1.5) }
        all[.vo2Max] = series(.vo2Max, days: 90, every: 9) { 49.2 + Double($0) * 0.02 }
        all[.bloodOxygen] = series(.bloodOxygen) { 97.6 + wave($0, 0.8, 0.6) }
        all[.respiratoryRate] = series(.respiratoryRate) { 14.6 + wave($0, 0.7, 0.4) }
        all[.wristTemperature] = series(.wristTemperature, days: 21) { 34.1 + wave($0, 0.9, 0.12) + ($0 == 20 ? 0.25 : 0) }
        all[.steps] = series(.steps) { 9_200 + wave($0, 0.9, 2_400) + Double($0) * 40 }
        all[.distance] = series(.distance) { 6.1 + wave($0, 0.9, 1.8) }
        all[.exerciseMinutes] = series(.exerciseMinutes) { $0 == 27 ? 42 : 64 + wave($0, 1.1, 22) }
        all[.flightsClimbed] = series(.flightsClimbed) { 9 + wave($0, 1.3, 4) }
        all[.activeEnergy] = series(.activeEnergy) { 690 + wave($0, 1.1, 180) }
        all[.restingEnergy] = series(.restingEnergy) { 1_690 + wave($0, 0.3, 12) }
        all[.bodyMass] = series(.bodyMass, days: 84, every: 7) { 68.2 + Double($0) * 0.012 }

        let hours: [Double] = [7.2, 8.4, 6.9, 7.8, 8.6, 9.1, 7.4, 6.6, 8.2, 8.9, 7.7, 8.3, 7.1, 8.1]
        let bedtimes: [Double] = [-50, -75, 10, -40, -95, -110, -30, 25, -60, -80, -45, -70, -20, -65]
        let nights = hours.enumerated().map { index, asleep -> HealthNight in
            let morning = day(hours.count - 1 - index)
            let fell = morning.addingTimeInterval(bedtimes[index] * 60)
            let stages = index == hours.count - 1 ? SleepStages(deep: 82, rem: 111, core: 293, awake: 24) : nil
            return HealthNight(morning: morning, asleepHours: asleep, fellAsleep: fell,
                               wokeUp: fell.addingTimeInterval(asleep * 3600 + 20 * 60), stages: stages)
        }

        func workout(_ id: String, _ back: Int, hour: Double, minutes: Int, _ activity: String, _ bpm: Double,
                     km: Double? = nil, route: Bool = false) -> HealthWorkout {
            let start = day(back).addingTimeInterval(hour * 3600)
            return HealthWorkout(id: id, start: start, end: start.addingTimeInterval(Double(minutes) * 60), activity: activity,
                                 source: "Apple Watch", averageHeartRate: bpm, distanceKm: km, hasRoute: route)
        }
        let workouts = [workout("demo-1", 1, hour: 17, minutes: 88, "Soccer", 151),
                        workout("demo-2", 2, hour: 7, minutes: 34, "Run", 162, km: 6.4, route: true),
                        workout("demo-3", 4, hour: 16, minutes: 55, "Strength training", 118),
                        workout("demo-4", 6, hour: 8, minutes: 41, "Ride", 139, km: 14.8, route: true)]
        return HealthSnapshot(series: all, nights: nights, workouts: workouts, fetchedAt: now)
    }

    /// A 6 km loop for the route screenshot.
    static func route() -> [RoutePoint] {
        (0..<120).map { index in
            let t = Double(index) / 120 * 2 * .pi
            return RoutePoint(latitude: 48.1374 + 0.008 * sin(t) + 0.002 * sin(3 * t),
                              longitude: 11.5755 + 0.013 * cos(t))
        }
    }
}
