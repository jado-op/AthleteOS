import Foundation

/// What a watch or band measured, for the twin's "What your watch sees"
/// (owner, 2026-11-19): sleep, overnight heart rate, heart-rate variability
/// and workouts. Each series is the athlete's own, compared only with their
/// own usual. Never a score; recovery is a word with the numbers behind it.
public struct WearableSignals: Sendable {
    /// Hours asleep per night, dated by the morning it ended; oldest first.
    public var sleep: [TwinPoint] = []
    /// Resting heart rate per day (Apple Health), or the lowest heart rate asleep (Suunto); oldest first.
    public var heartRate: [TwinPoint] = []
    /// Heart-rate variability per day, ms; oldest first.
    public var variability: [TwinPoint] = []
    /// Where the heart-rate numbers come from, which names them.
    public var heartRateKind: HeartRateKind = .resting
    /// The device to name ("Suunto", "Garmin"…; "watch" when unknown).
    public var device: String = "watch"

    public enum HeartRateKind: Sendable { case resting, lowestAsleep }

    public init(sleep: [TwinPoint] = [], heartRate: [TwinPoint] = [], variability: [TwinPoint] = [],
                heartRateKind: HeartRateKind = .resting, device: String = "watch") {
        self.sleep = sleep
        self.heartRate = heartRate
        self.variability = variability
        self.heartRateKind = heartRateKind
        self.device = device
    }

    /// A watch is connected and has measured something.
    public var hasData: Bool { !sleep.isEmpty || !heartRate.isEmpty || !variability.isEmpty }
}

/// Today against the athlete's usual: the latest value from today (or last
/// night) and the median of the days before, from a week of data.
public struct SignalReading: Sendable, Equatable {
    public var today: Double
    public var usual: Double?

    /// today − usual (nil until a week of data).
    public var difference: Double? { usual.map { today - $0 } }
}

public enum WearableRead {
    /// The latest point if it is from today, against the median of the earlier ones.
    public static func reading(_ series: [TwinPoint], now: Date, calendar: Calendar = .current) -> SignalReading? {
        guard let last = series.max(by: { $0.date < $1.date }), calendar.isDate(last.date, inSameDayAs: now) else { return nil }
        let earlier = series.filter { !calendar.isDate($0.date, inSameDayAs: now) && $0.date < last.date }.map(\.value).sorted()
        guard earlier.count >= 7 else { return SignalReading(today: last.value, usual: nil) }
        let middle = earlier.count / 2
        let median = earlier.count % 2 == 0 ? (earlier[middle - 1] + earlier[middle]) / 2 : earlier[middle]
        return SignalReading(today: last.value, usual: median)
    }

    /// How recovered the body looks this morning, in words.
    public enum Recovery: Sendable, Equatable {
        case recovered, slightlyTired, takeItEasy
        /// Less than a week of data: nothing to compare with yet.
        case learning

        public var word: String {
            switch self {
            case .recovered: "Recovered."
            case .slightlyTired: "A bit tired."
            case .takeItEasy: "Take it easy."
            case .learning: "Learning your normal."
            }
        }
    }

    /// The same thresholds as the check-in's energy from a watch
    /// (`WearablePrefill.energy`): heart rate 3+ above usual or variability
    /// 10 % below = a bit tired; 6+ above or 25 % below = take it easy.
    public static func recovery(heartRate: SignalReading?, variability: SignalReading?) -> Recovery? {
        guard heartRate != nil || variability != nil else { return nil }
        var level = 0
        var compared = false
        if let diff = heartRate?.difference {
            compared = true
            level = max(level, diff > 5 ? 2 : (diff > 2 ? 1 : 0))
        }
        if let hrv = variability, let usual = hrv.usual, usual > 0 {
            compared = true
            let drop = (usual - hrv.today) / usual
            level = max(level, drop > 0.25 ? 2 : (drop > 0.1 ? 1 : 0))
        }
        guard compared else { return .learning }
        return [.recovered, .slightlyTired, .takeItEasy][level]
    }

    /// "52 bpm, 3 below your usual" — the numbers behind the word.
    public static func heartRateLine(_ reading: SignalReading, kind: WearableSignals.HeartRateKind) -> String {
        let name = kind == .resting ? "Resting heart rate" : "Lowest heart rate asleep"
        let value = Int(reading.today.rounded())
        guard let diff = reading.difference else { return "\(name) \(value)." }
        let beats = Int(abs(diff).rounded())
        if beats <= 1 { return "\(name) \(value), your usual." }
        return "\(name) \(value), \(beats) \(diff > 0 ? "above" : "below") your usual."
    }

    public static func variabilityLine(_ reading: SignalReading) -> String {
        let value = Int(reading.today.rounded())
        guard let usual = reading.usual, usual > 0 else { return "Variability \(value) ms." }
        let change = (reading.today - usual) / usual
        if abs(change) < 0.1 { return "Variability \(value) ms, your usual." }
        return "Variability \(value) ms, \(change > 0 ? "above" : "below") your usual \(Int(usual.rounded()))."
    }

    /// One sentence about the last two weeks of nights.
    public static func sleepLine(_ nights: [TwinPoint]) -> String? {
        guard !nights.isEmpty else { return nil }
        let average = nights.map(\.value).reduce(0, +) / Double(nights.count)
        let enough = nights.filter { $0.value >= 8 }.count
        if average >= 8 { return "\(enough) of \(nights.count) nights at 8 hours or more. Right where your body builds." }
        return "Average \(SleepMath.label(average)) a night. Teens need 8–10: an earlier night is the easiest extra strength."
    }
}
