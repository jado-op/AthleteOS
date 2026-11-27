import Foundation

/// Every card the health insights page can show. A new measurement means a
/// new `HealthMetric` case (or a new kind here) and nothing else: the page
/// lays out whatever `HealthWidgetRegistry.available` returns.
public enum HealthWidgetKind: Hashable, Sendable, Identifiable {
    /// Recovery as a word from resting heart rate and HRV against the usual (derived).
    case recovery
    /// Last night, its stages, and two weeks of nights.
    case sleep
    /// When the athlete falls asleep and wakes, and how steady that is (derived).
    case sleepSchedule
    /// Workouts from any app or device, with routes where recorded.
    case workouts
    /// One measurement.
    case metric(HealthMetric)

    public var id: String {
        switch self {
        case .recovery: "recovery"
        case .sleep: "sleep"
        case .sleepSchedule: "sleepSchedule"
        case .workouts: "workouts"
        case .metric(let metric): "metric." + metric.rawValue
        }
    }

    public var category: HealthCategory {
        switch self {
        case .recovery: .recovery
        case .sleep, .sleepSchedule: .sleep
        case .workouts: .activity
        case .metric(let metric): metric == .respiratoryRate ? .sleep : metric.category
        }
    }
}

public enum HealthWidgetRegistry {
    /// Every widget, in page order.
    public static let all: [HealthWidgetKind] = [
        .recovery,
        .sleep, .sleepSchedule, .metric(.respiratoryRate),
        .metric(.restingHeartRate), .metric(.heartRateVariability), .metric(.heartRate), .metric(.walkingHeartRate),
        .metric(.heartRateRecovery), .metric(.vo2Max), .metric(.bloodOxygen),
        .workouts, .metric(.exerciseMinutes), .metric(.steps), .metric(.distance), .metric(.flightsClimbed),
        .metric(.activeEnergy), .metric(.restingEnergy),
        .metric(.wristTemperature), .metric(.bodyTemperature), .metric(.bodyMass),
    ]

    /// Only the widgets Health has real, recent data for.
    public static func available(in snapshot: HealthSnapshot, now: Date = .now, calendar: Calendar = .current) -> [HealthWidgetKind] {
        all.filter { isAvailable($0, in: snapshot, now: now, calendar: calendar) }
    }

    /// The available widgets grouped into the page's sections, empty sections dropped.
    public static func sections(in snapshot: HealthSnapshot, now: Date = .now,
                                calendar: Calendar = .current) -> [(category: HealthCategory, widgets: [HealthWidgetKind])] {
        let shown = available(in: snapshot, now: now, calendar: calendar)
        return HealthCategory.allCases.compactMap { category in
            let widgets = shown.filter { $0.category == category }
            return widgets.isEmpty ? nil : (category, widgets)
        }
    }

    public static func isAvailable(_ kind: HealthWidgetKind, in snapshot: HealthSnapshot, now: Date = .now,
                                   calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        func within(_ days: Int, _ date: Date?) -> Bool {
            guard let date, let start = calendar.date(byAdding: .day, value: -days, to: today) else { return false }
            return date >= start
        }
        switch kind {
        case .recovery:
            // Derived: needs today's resting heart rate or HRV AND a week of usual to compare with.
            guard let recovery = HealthRecovery.read(snapshot, now: now, calendar: calendar).recovery else { return false }
            return recovery != .learning
        case .sleep:
            return within(3, snapshot.nights.last?.morning)
        case .sleepSchedule:
            return SleepSchedule.summary(snapshot.nights, now: now, calendar: calendar) != nil
        case .workouts:
            return snapshot.workouts.contains { within(14, $0.start) }
        case .metric(let metric):
            guard let series = snapshot.series[metric], within(metric.freshnessDays, series.latestDate) else { return false }
            // A day of zero steps is no data, not a measurement worth a card.
            if metric.aggregation == .sum { return series.days.contains { $0.value > 0 && within(metric.freshnessDays, $0.date) } }
            // A difference needs a usual to differ from.
            if metric.showsDeviation { return snapshot.summary(metric, now: now, calendar: calendar)?.deviation != nil }
            return true
        }
    }
}

/// The morning's recovery word, from whichever of resting heart rate and HRV
/// Health has — the check-in's careful reading (`WearableRead.recovery`). Not a
/// medical or validated score: the athlete against their own usual.
public enum HealthRecovery {
    public struct Reading: Sendable, Equatable {
        public var heartRate: SignalReading?
        public var variability: SignalReading?
        public var recovery: WearableRead.Recovery?

        /// The numbers behind the word.
        public var lines: [String] {
            var lines: [String] = []
            if let heartRate { lines.append(WearableRead.heartRateLine(heartRate)) }
            if let variability { lines.append(WearableRead.variabilityLine(variability)) }
            return lines
        }
    }

    /// `morning`: the app's device-aware reading (`HeartStore.morning`), the
    /// same one the check-in uses; without it, read from Health's daily values.
    public static func read(_ snapshot: HealthSnapshot, morning given: HeartMorning? = nil, now: Date = .now,
                            calendar: Calendar = .current) -> Reading {
        let morning = given ?? HeartSignals.morning(
            restingHeartRate: (snapshot.series[.restingHeartRate]?.points ?? []).map { HeartNight(date: $0.date, value: $0.value) },
            variability: (snapshot.series[.heartRateVariability]?.points ?? []).map { HeartNight(date: $0.date, value: $0.value) },
            now: now, calendar: calendar)
        let heart = morning.lastTwo.last.map { SignalReading(today: $0, usual: morning.usual) }
        let hrv = morning.variabilityRecent.map { SignalReading(today: $0, usual: morning.variabilityUsual) }
        return Reading(heartRate: heart, variability: hrv, recovery: WearableRead.recovery(morning))
    }
}
