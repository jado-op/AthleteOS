import Foundation

/// Reading what a watch or band wrote to Apple Health (owner, 2026-11-19):
/// each series is the athlete's own, compared only with their own usual.
/// Never a score; recovery is a word with the numbers behind it.

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
    public static func heartRateLine(_ reading: SignalReading) -> String {
        let name = "Resting heart rate"
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

/// Which brand recorded something, from the name of the app that wrote it to
/// Apple Health — only to name it in a sentence ("Your Garmin saw a hard run").
/// Nothing depends on it: every source is read the same way, and no brand gets
/// its own rule (owner, 2026-11-19: Suunto and Fitbit/Google alike).
public enum WearableBrand {
    public static let known = ["Suunto", "Garmin", "Polar", "Coros", "WHOOP", "Oura", "Fitbit", "Wahoo"]

    /// "Suunto", "Garmin"…; nil when the source isn't a known brand (an Apple Watch, the iPhone, another app).
    public static func name(fromSource source: String?) -> String? {
        let name = (source ?? "").lowercased()
        guard !name.isEmpty else { return nil }
        return known.first { name.contains($0.lowercased()) }
    }
}

/// Last night's sleep by stage, in minutes. Apple Health holds the stages a
/// watch, band or app wrote.
public struct SleepStages: Sendable, Equatable {
    public var deep: Double
    public var rem: Double
    public var core: Double
    public var awake: Double

    public init(deep: Double = 0, rem: Double = 0, core: Double = 0, awake: Double = 0) {
        self.deep = deep
        self.rem = rem
        self.core = core
        self.awake = awake
    }

    public enum Stage: String, Sendable, CaseIterable { case awake, rem, core, deep, unspecified }

    public struct Sample: Sendable {
        public var start: Date
        public var end: Date
        public var stage: Stage
        public var source: String

        public init(start: Date, end: Date, stage: Stage, source: String) {
            self.start = start
            self.end = end
            self.stage = stage
            self.source = source
        }
    }

    public var asleep: Double { deep + rem + core }

    /// One device's view of the night: the source that recorded the most
    /// staged sleep (two devices on one night would otherwise add up), each
    /// stage's intervals merged so overlaps count once. nil without stages
    /// (a night with only "asleep" from the iPhone has nothing to split).
    public static func from(_ samples: [Sample]) -> SleepStages? {
        let staged = samples.filter { $0.end > $0.start && $0.stage != .unspecified }
        var bySource: [String: Double] = [:]
        for sample in staged where sample.stage != .awake {
            bySource[sample.source, default: 0] += sample.end.timeIntervalSince(sample.start)
        }
        guard let source = bySource.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value })?.key else { return nil }
        let mine = staged.filter { $0.source == source }
        func minutes(_ stage: Stage) -> Double {
            SleepMath.asleepHours(mine.filter { $0.stage == stage }.map { ($0.start, $0.end) }) * 60
        }
        let stages = SleepStages(deep: minutes(.deep), rem: minutes(.rem), core: minutes(.core), awake: minutes(.awake))
        return stages.asleep >= 60 ? stages : nil
    }

    /// "Deep 1h 24m · REM 1h 52m": the two stages athletes ask about.
    public var line: String {
        "Deep \(SleepMath.label(deep / 60)) · REM \(SleepMath.label(rem / 60))"
    }
}
