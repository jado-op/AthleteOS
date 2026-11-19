import Foundation

// Apple Health is the one way wearable data comes in (owner, 2026-11-19):
// Apple Watch, Garmin, Suunto, Fitbit, Polar, Oura, WHOOP… whatever writes to
// Health is read the same way, with no brand-specific logic. This file is the
// plain model (Foundation only, tested in the engine harness): what each
// measurement is, the athlete's days of it, and what can honestly be said
// about them. Nothing here invents a value: a metric without samples simply
// has no series, and its widget doesn't exist.

/// The sections of the health insights page.
public enum HealthCategory: String, CaseIterable, Sendable {
    case recovery, sleep, heart, activity, body

    public var title: String {
        switch self {
        case .recovery: "This morning"
        case .sleep: "Sleep"
        case .heart: "Heart"
        case .activity: "Activity"
        case .body: "Body"
        }
    }
}

/// Every quantity read from Apple Health. Values are kept in one unit each
/// (the HealthKit layer converts): counts, km, kcal, minutes, bpm, ms,
/// ml/kg/min, percent (0–100), breaths/min, °C, kg.
public enum HealthMetric: String, CaseIterable, Sendable, Codable {
    // Activity
    case exerciseMinutes, steps, distance, flightsClimbed, activeEnergy, restingEnergy
    // Heart and breathing
    case restingHeartRate, heartRateVariability, heartRate, walkingHeartRate, heartRateRecovery, vo2Max, bloodOxygen, respiratoryRate
    // Body
    case wristTemperature, bodyTemperature, bodyMass

    /// Summed over a day (steps) or averaged (heart rate).
    public enum Aggregation: Sendable { case sum, average }

    public var aggregation: Aggregation {
        switch self {
        case .exerciseMinutes, .steps, .distance, .flightsClimbed, .activeEnergy, .restingEnergy: .sum
        default: .average
        }
    }

    public var category: HealthCategory {
        switch self {
        case .exerciseMinutes, .steps, .distance, .flightsClimbed, .activeEnergy, .restingEnergy: .activity
        case .wristTemperature, .bodyTemperature, .bodyMass: .body
        default: .heart
        }
    }

    public var title: String {
        switch self {
        case .exerciseMinutes: "Exercise"
        case .steps: "Steps"
        case .distance: "Walking and running"
        case .flightsClimbed: "Flights climbed"
        case .activeEnergy: "Active energy"
        case .restingEnergy: "Resting energy"
        case .restingHeartRate: "Resting heart rate"
        case .heartRateVariability: "Heart-rate variability"
        case .heartRate: "Heart rate"
        case .walkingHeartRate: "Walking heart rate"
        case .heartRateRecovery: "Heart-rate recovery"
        case .vo2Max: "VO2 max"
        case .bloodOxygen: "Blood oxygen"
        case .respiratoryRate: "Breathing rate"
        case .wristTemperature: "Wrist temperature"
        case .bodyTemperature: "Body temperature"
        case .bodyMass: "Body weight"
        }
    }

    /// SF Symbol for the card's label.
    public var symbol: String {
        switch self {
        case .exerciseMinutes: "figure.run"
        case .steps: "shoeprints.fill"
        case .distance: "point.topleft.down.to.point.bottomright.curvepath"
        case .flightsClimbed: "figure.stairs"
        case .activeEnergy, .restingEnergy: "flame.fill"
        case .restingHeartRate, .heartRate: "heart.fill"
        case .heartRateVariability: "waveform.path.ecg"
        case .walkingHeartRate: "figure.walk"
        case .heartRateRecovery: "arrow.down.heart.fill"
        case .vo2Max: "lungs.fill"
        case .bloodOxygen: "drop.fill"
        case .respiratoryRate: "wind"
        case .wristTemperature, .bodyTemperature: "thermometer.medium"
        case .bodyMass: "scalemass.fill"
        }
    }

    /// What it is, in one or two plain sentences. Never a diagnosis.
    public var meaning: String {
        switch self {
        case .exerciseMinutes:
            "Minutes of movement at least as hard as a brisk walk. Teens are advised about 60 a day, sport included."
        case .steps: "Every step your phone, watch or band counted, each counted once even when several devices record."
        case .distance: "How far you walked and ran, outside of any bike or swim."
        case .flightsClimbed: "Floors you climbed on foot, about three metres each."
        case .activeEnergy: "Energy your body used moving, on top of resting. An estimate from your heart rate and motion."
        case .restingEnergy: "Energy your body uses just to run itself, estimated from your age, height and weight."
        case .restingHeartRate:
            "Your heart's slowest steady rate at rest. Above your own usual can mean you're tired, stressed or getting sick."
        case .heartRateVariability:
            "The tiny changes in time between heartbeats. Higher than your usual tends to mean rested; it varies a lot between people."
        case .heartRate: "Your heart rate through the day: the line is each day's average, the band its lowest and highest."
        case .walkingHeartRate: "Your average heart rate while walking. It tends to drop slowly as your fitness grows."
        case .heartRateRecovery:
            "How many beats your heart drops in the first minute after hard exercise. A bigger drop usually means fitter."
        case .vo2Max:
            "Your watch's estimate of how much oxygen your body can use at full effort: aerobic fitness. It rises slowly with training."
        case .bloodOxygen: "How much oxygen your blood carries, as measured at the wrist. Readings vary; this isn't a medical test."
        case .respiratoryRate: "Breaths per minute while you sleep. It moves little night to night, so a change stands out."
        case .wristTemperature:
            "Your skin temperature overnight against your own usual. Illness, your cycle, travel and the room all move it."
        case .bodyTemperature: "Temperatures you or a thermometer app saved to Health."
        case .bodyMass: "Weight from a scale or app that writes to Health. Growing athletes change; this is a record, never a target."
        }
    }

    /// Days a reading stays worth showing: older than this, the card hides.
    public var freshnessDays: Int {
        switch self {
        case .vo2Max: 120
        case .bodyMass: 90
        case .bodyTemperature: 30
        case .heartRateRecovery: 60
        case .exerciseMinutes, .steps, .distance, .flightsClimbed, .activeEnergy, .restingEnergy: 7
        default: 14
        }
    }

    /// A daily target where one is established: WHO's 60 minutes a day for 5–17-year-olds.
    public var dailyGoal: Double? { self == .exerciseMinutes ? 60 : nil }

    /// Whether more is the better direction; nil where neither is (weight, temperature).
    public var higherIsBetter: Bool? {
        switch self {
        case .exerciseMinutes, .steps, .distance, .flightsClimbed, .heartRateVariability, .heartRateRecovery, .vo2Max: true
        case .restingHeartRate, .walkingHeartRate: false
        default: nil
        }
    }

    /// Wrist temperature is shown as the difference from the athlete's usual,
    /// as Apple does; a single absolute skin temperature means little.
    public var showsDeviation: Bool { self == .wristTemperature }

    /// Unit words for display in the athlete's system (metric or US).
    public func unit(metric: Bool = HealthFormat.usesMetric) -> String {
        switch self {
        case .exerciseMinutes: "min"
        case .steps: "steps"
        case .distance: metric ? "km" : "mi"
        case .flightsClimbed: "floors"
        case .activeEnergy, .restingEnergy: "kcal"
        case .restingHeartRate, .heartRate, .walkingHeartRate: "bpm"
        case .heartRateRecovery: "bpm"
        case .heartRateVariability: "ms"
        case .vo2Max: "ml/kg/min"
        case .bloodOxygen: "%"
        case .respiratoryRate: "br/min"
        case .wristTemperature, .bodyTemperature: metric ? "°C" : "°F"
        case .bodyMass: metric ? "kg" : "lb"
        }
    }

    /// A stored value in the display system's unit.
    public func display(_ value: Double, metric: Bool = HealthFormat.usesMetric) -> Double {
        guard !metric else { return value }
        switch self {
        case .distance: return value * 0.621371
        case .bodyTemperature: return value * 9 / 5 + 32
        case .wristTemperature: return value * 9 / 5  // only ever a difference
        case .bodyMass: return value * 2.20462
        default: return value
        }
    }

    /// "9,420", "6.4", "52": the number alone, rounded as the measurement deserves.
    public func format(_ value: Double, metric: Bool = HealthFormat.usesMetric) -> String {
        let shown = display(value, metric: metric)
        let decimals: Int
        switch self {
        case .distance, .vo2Max, .bodyTemperature, .respiratoryRate, .bodyMass: decimals = 1
        case .wristTemperature: decimals = 2
        default: decimals = 0
        }
        return HealthFormat.number(shown, decimals: decimals)
    }
}

public enum HealthFormat {
    /// Metric unless the phone is set to US units.
    public static var usesMetric: Bool { Locale.current.usesMetricSystem }

    /// Grouped thousands, fixed decimals, POSIX-stable for tests ("9,420", "6.4").
    public static func number(_ value: Double, decimals: Int) -> String {
        let factor = pow(10, Double(decimals))
        let rounded = (value * factor).rounded() / factor
        if decimals == 0 {
            let whole = Int(rounded)
            let digits = String(abs(whole))
            var grouped = ""
            for (index, character) in digits.reversed().enumerated() {
                if index > 0 && index % 3 == 0 { grouped.append(",") }
                grouped.append(character)
            }
            return (whole < 0 ? "-" : "") + String(grouped.reversed())
        }
        return String(format: "%.\(decimals)f", rounded)
    }
}

// MARK: - The athlete's data

/// One day of a measurement: the day's total (sum) or average, with the
/// lowest and highest sample where that means something.
public struct HealthDay: Sendable, Equatable {
    public var date: Date
    public var value: Double
    public var low: Double?
    public var high: Double?

    public init(date: Date, value: Double, low: Double? = nil, high: Double? = nil) {
        self.date = date
        self.value = value
        self.low = low
        self.high = high
    }
}

/// A metric's days (oldest first) and its newest sample.
public struct HealthSeries: Sendable, Equatable {
    public var metric: HealthMetric
    public var days: [HealthDay]
    /// The newest sample's value and when it ended ("updated 08:12").
    public var latest: Double?
    public var latestDate: Date?
    /// The app or device that wrote the newest sample ("Garmin Connect"…).
    public var latestSource: String?

    public init(metric: HealthMetric, days: [HealthDay], latest: Double? = nil, latestDate: Date? = nil, latestSource: String? = nil) {
        self.metric = metric
        self.days = days.sorted { $0.date < $1.date }
        self.latest = latest
        self.latestDate = latestDate ?? self.days.last?.date
        self.latestSource = latestSource
    }

    public var points: [TwinPoint] { days.map { TwinPoint(date: $0.date, value: $0.value) } }
}

/// One night of sleep, dated by the morning it ended.
public struct HealthNight: Sendable, Equatable {
    public var morning: Date
    public var asleepHours: Double
    /// First and last moment asleep (the schedule).
    public var fellAsleep: Date
    public var wokeUp: Date
    public var stages: SleepStages?

    public init(morning: Date, asleepHours: Double, fellAsleep: Date, wokeUp: Date, stages: SleepStages? = nil) {
        self.morning = morning
        self.asleepHours = asleepHours
        self.fellAsleep = fellAsleep
        self.wokeUp = wokeUp
        self.stages = stages
    }
}

/// A workout any app or device wrote to Health.
public struct HealthWorkout: Sendable, Equatable, Identifiable {
    /// The HealthKit sample UUID.
    public var id: String
    public var start: Date
    public var end: Date
    public var activity: String
    /// The app or device that wrote it ("Garmin Connect", "Apple Watch"…).
    public var source: String
    public var averageHeartRate: Double?
    public var distanceKm: Double?
    public var energyKcal: Double?
    /// A GPS route is stored with it.
    public var hasRoute: Bool

    public init(id: String, start: Date, end: Date, activity: String, source: String, averageHeartRate: Double? = nil,
                distanceKm: Double? = nil, energyKcal: Double? = nil, hasRoute: Bool = false) {
        self.id = id
        self.start = start
        self.end = end
        self.activity = activity
        self.source = source
        self.averageHeartRate = averageHeartRate
        self.distanceKm = distanceKm
        self.energyKcal = energyKcal
        self.hasRoute = hasRoute
    }

    public var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }

    /// How much of the shorter of two workouts the other covers (0…1).
    func overlap(with other: HealthWorkout) -> Double {
        let shared = min(end, other.end).timeIntervalSince(max(start, other.start))
        let shorter = min(end.timeIntervalSince(start), other.end.timeIntervalSince(other.start))
        guard shared > 0, shorter > 0 else { return 0 }
        return shared / shorter
    }

    /// How much this copy knows (a route, heart rate, distance): the one to keep.
    var richness: Int {
        (hasRoute ? 4 : 0) + (averageHeartRate != nil ? 2 : 0) + (distanceKm != nil ? 1 : 0)
    }
}

public enum HealthWorkouts {
    /// The same session recorded twice (a Garmin and the iPhone, or a watch
    /// and its phone app) counts once: workouts from different sources that
    /// overlap by more than half of the shorter one are one workout, and the
    /// copy with the most detail stays. Newest first.
    public static func unique(_ workouts: [HealthWorkout]) -> [HealthWorkout] {
        var kept: [HealthWorkout] = []
        let ordered = workouts.sorted { lhs, rhs in
            lhs.richness != rhs.richness ? lhs.richness > rhs.richness : lhs.minutes > rhs.minutes
        }
        for workout in ordered where !kept.contains(where: { $0.id == workout.id }) {
            if kept.contains(where: { $0.source != workout.source && $0.overlap(with: workout) > 0.5 }) { continue }
            kept.append(workout)
        }
        return kept.sorted { $0.start > $1.start }
    }
}

/// Everything read from Health in one pass.
public struct HealthSnapshot: Sendable, Equatable {
    public var series: [HealthMetric: HealthSeries]
    /// Nights oldest first.
    public var nights: [HealthNight]
    /// Newest first, duplicates across sources removed.
    public var workouts: [HealthWorkout]
    public var fetchedAt: Date

    public init(series: [HealthMetric: HealthSeries] = [:], nights: [HealthNight] = [], workouts: [HealthWorkout] = [],
                fetchedAt: Date = .now) {
        self.series = series.filter { !$0.value.days.isEmpty || $0.value.latest != nil }
        self.nights = nights.sorted { $0.morning < $1.morning }
        self.workouts = HealthWorkouts.unique(workouts)
        self.fetchedAt = fetchedAt
    }

    public static let empty = HealthSnapshot()

    public var isEmpty: Bool { series.isEmpty && nights.isEmpty && workouts.isEmpty }

    public func summary(_ metric: HealthMetric, now: Date = .now, calendar: Calendar = .current) -> HealthSummary? {
        series[metric].map { HealthSummary($0, now: now, calendar: calendar) }
    }

    /// The newest moment anything was measured.
    public var lastMeasured: Date? {
        (series.values.compactMap(\.latestDate) + nights.map(\.wokeUp) + workouts.map(\.end)).max()
    }
}

// MARK: - What can be said about a series

/// A series read against the athlete's own past: this week, the week before,
/// and their usual. Each part is nil until there is enough real data for it.
public struct HealthSummary: Sendable, Equatable {
    public var metric: HealthMetric
    /// The newest sample (an average metric) or today's total (a sum metric).
    public var current: Double?
    public var currentDate: Date?
    /// Today's day bucket, when there is one.
    public var today: Double?
    /// Mean of the days with data in the last 7 (today included).
    public var week: Double?
    /// Mean of the days with data 8–14 days ago.
    public var previousWeek: Double?
    /// Median of the days before today (up to 4 weeks); needs 7 of them.
    public var usual: Double?
    /// Days with data before today, in the last 4 weeks.
    public var priorDays: Int
    /// Days with data in the last 28.
    public var dayCount: Int

    public init(_ series: HealthSeries, now: Date, calendar: Calendar) {
        metric = series.metric
        let today = calendar.startOfDay(for: now)
        func back(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: today) ?? today }
        let recent = series.days.filter { $0.date >= back(27) && $0.date <= now }
        dayCount = recent.count
        let todayDay = recent.first { calendar.isDate($0.date, inSameDayAs: now) }
        self.today = todayDay?.value
        let thisWeek = recent.filter { $0.date >= back(6) }.map(\.value)
        let lastWeek = recent.filter { $0.date >= back(13) && $0.date < back(6) }.map(\.value)
        week = thisWeek.isEmpty ? nil : thisWeek.reduce(0, +) / Double(thisWeek.count)
        previousWeek = lastWeek.isEmpty ? nil : lastWeek.reduce(0, +) / Double(lastWeek.count)
        // The usual: like the morning check-in (`WearableRead.reading`), the
        // median of the days before today, from a week of them.
        let before = recent.filter { !calendar.isDate($0.date, inSameDayAs: now) }.map(\.value).sorted()
        priorDays = before.count
        if before.count >= 7 {
            let middle = before.count / 2
            usual = before.count % 2 == 0 ? (before[middle - 1] + before[middle]) / 2 : before[middle]
        } else {
            usual = nil
        }
        if series.metric.aggregation == .sum {
            current = todayDay?.value ?? series.days.last?.value
            currentDate = todayDay != nil ? series.latestDate : series.days.last?.date
        } else {
            current = series.latest ?? series.days.last?.value
            currentDate = series.latestDate
        }
    }

    /// Progress toward a daily goal (0…1+), today.
    public var goalProgress: Double? {
        guard let goal = metric.dailyGoal, goal > 0, let today else { return nil }
        return today / goal
    }

    /// Wrist temperature against the usual (°C); nil until there is a usual.
    public var deviation: Double? {
        guard let current, let usual else { return nil }
        return current - usual
    }

    /// The headline number as shown on the card.
    public var shownValue: Double? { metric.showsDeviation ? deviation : current }

    /// One sentence with the numbers: against the week before for things you
    /// do (steps), against the usual for things you are (resting heart rate).
    public func line(metric system: Bool = HealthFormat.usesMetric) -> String {
        let unit = metric.unit(metric: system)
        switch metric.aggregation {
        case .sum:
            guard let week else { return "Nothing this week yet." }
            var text = "\(metric.format(week, metric: system)) \(unit) a day this week"
            if let previousWeek, previousWeek > 0 {
                let change = (week - previousWeek) / previousWeek
                if abs(change) < 0.05 {
                    text += ", about the same as last week"
                } else {
                    text += ", \(Int((abs(change) * 100).rounded())) % \(change > 0 ? "more" : "less") than last week"
                }
            }
            return text + "."
        case .average:
            if metric.showsDeviation {
                guard let deviation else { return learningLine }
                if abs(deviation) < 0.1 { return "Right at your usual." }
                let sign = deviation > 0 ? "+" : "−"
                return "\(sign)\(metric.format(abs(deviation), metric: system)) \(unit) against your usual."
            }
            guard let current else { return learningLine }
            guard let usual, usual != 0 else { return learningLine }
            let change = (current - usual) / abs(usual)
            if abs(change) < 0.03 { return "Right at your usual \(metric.format(usual, metric: system)) \(unit)." }
            let difference = metric.format(abs(current - usual), metric: system)
            return "\(difference) \(unit) \(current > usual ? "above" : "below") your usual \(metric.format(usual, metric: system))."
        }
    }

    /// Sparse measurements (VO2 max, weight) never get a usual from 7 days:
    /// say what is there instead of pretending to compare.
    private var learningLine: String {
        if metric == .vo2Max || metric == .bodyMass || metric == .heartRateRecovery || metric == .bodyTemperature {
            return dayCount > 1 ? "\(dayCount) readings in the last four weeks." : "Your latest reading."
        }
        let needed = max(1, 7 - priorDays)
        return "Learning your usual: \(needed) more \(needed == 1 ? "day" : "days")."
    }
}

// MARK: - Sleep

public enum HealthNights {
    /// Sleep samples from every source, grouped into nights by the morning
    /// they end on: a sample ending between 18:00 and noon the next day
    /// belongs to that morning (afternoon naps are left out). Hours asleep
    /// merge overlapping sources so nothing counts twice; stages come from
    /// the one device that recorded the most (`SleepStages.from`).
    public static func build(_ samples: [SleepStages.Sample], calendar: Calendar) -> [HealthNight] {
        var byMorning: [Date: [SleepStages.Sample]] = [:]
        for sample in samples where sample.end > sample.start {
            let morning = calendar.startOfDay(for: sample.end.addingTimeInterval(6 * 3600))
            guard sample.end <= morning.addingTimeInterval(12 * 3600) else { continue }
            byMorning[morning, default: []].append(sample)
        }
        return byMorning.compactMap { morning, samples -> HealthNight? in
            let asleep = samples.filter { $0.stage != .awake }
            guard let first = asleep.map(\.start).min(), let last = asleep.map(\.end).max() else { return nil }
            let hours = SleepMath.asleepHours(asleep.map { ($0.start, $0.end) })
            guard hours >= 1 else { return nil }
            return HealthNight(morning: morning, asleepHours: hours, fellAsleep: first, wokeUp: last, stages: SleepStages.from(samples))
        }
        .sorted { $0.morning < $1.morning }
    }
}

public enum SleepSchedule {
    public struct Summary: Sendable, Equatable {
        /// Minutes from midnight (negative = the evening before): average falling asleep.
        public var bedtime: Double
        /// Minutes from midnight: average waking.
        public var wake: Double
        /// Typical distance of a night's bedtime from the average, minutes.
        public var spread: Double
        public var nights: Int
    }

    /// From at least 5 of the last 14 nights.
    public static func summary(_ nights: [HealthNight], now: Date, calendar: Calendar) -> Summary? {
        let start = calendar.date(byAdding: .day, value: -13, to: calendar.startOfDay(for: now)) ?? now
        let recent = nights.filter { $0.morning >= start }
        guard recent.count >= 5 else { return nil }
        let beds = recent.map { $0.fellAsleep.timeIntervalSince(calendar.startOfDay(for: $0.morning)) / 60 }
        let wakes = recent.map { $0.wokeUp.timeIntervalSince(calendar.startOfDay(for: $0.morning)) / 60 }
        let bed = beds.reduce(0, +) / Double(beds.count)
        let wake = wakes.reduce(0, +) / Double(wakes.count)
        let spread = beds.map { abs($0 - bed) }.reduce(0, +) / Double(beds.count)
        return Summary(bedtime: bed, wake: wake, spread: spread, nights: recent.count)
    }

    /// "22:45" from minutes around midnight.
    public static func clock(_ minutes: Double) -> String {
        var total = Int(minutes.rounded())
        total = ((total % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    public static func line(_ summary: Summary) -> String {
        let spread = Int(summary.spread.rounded())
        if spread <= 30 { return "A steady rhythm: most nights within half an hour of the same time." }
        return "Your bedtime moves about \(spread) minutes night to night. A steadier time makes the same hours count for more."
    }
}
