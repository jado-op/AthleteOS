import Foundation

/// What the athlete's heart says, read the careful way (owner, 2026-11-27:
/// "heart data is important information"; docs/TWIN-RESEARCH.md §3, T2, T3,
/// T8, T12, T14):
/// - "Usual" is the athlete's own: the middle value of the 28 nights before,
///   and only once there are at least 14 of them (T1, T2). Never a population norm.
/// - One night is noise. A resting heart rate above usual by at least
///   max(3 bpm, 5%) on the last **two** nights is a sign (T3); HRV at least
///   10% below usual over three days is a second sign.
/// - It never diagnoses (T8): "your body is working harder than usual" —
///   hard training, short sleep, stress or a cold starting. It shows only in
///   the morning check-in, never as a push, and the plan changes only
///   through what the athlete answers there (T12: their words come first).
/// - No HRV number is ever "good" or "bad" on its own (T14).
public struct HeartNight: Sendable, Equatable {
    public var date: Date
    public var value: Double
    /// The device that measured it (a bundle id); nil when unknown.
    public var source: String?
    public init(date: Date, value: Double, source: String? = nil) { self.date = date; self.value = value; self.source = source }
}

public struct HeartMorning: Sendable, Equatable {
    /// The athlete's usual resting heart rate (nil: fewer than 14 nights yet).
    public var usual: Double?
    /// The last two nights, newest last.
    public var lastTwo: [Double]
    /// Both of the last two nights above usual by max(3 bpm, 5%).
    public var raised: Bool
    /// HRV's three-day average at least 10% under its own usual.
    public var variabilityLow: Bool
    /// The three complete days' HRV average and its usual (nil: not enough data).
    public var variabilityRecent: Double? = nil
    public var variabilityUsual: Double? = nil

    /// The check-in's note, calm, with the numbers — only when two signs
    /// agree (T8: a raised resting heart rate *and* low variability). One
    /// sign alone stays quiet; it only stops the app guessing "normal".
    public var note: String? {
        guard raised, variabilityLow, let usual, let latest = lastTwo.last else { return nil }
        return "Your resting heart rate has been higher than your usual for two nights (\(Int(latest.rounded())), usually \(Int(usual.rounded()))). "
            + "That often comes with hard training, short sleep, stress or a cold starting. How do you feel?"
    }
}

public enum HeartSignals {
    public static let baselineNights = 28
    public static let minimumNights = 14

    /// The usual (median) of the nights in the 28 days before `day`, if 14+.
    public static func usual(_ nights: [HeartNight], before day: Date, calendar: Calendar = .current) -> (value: Double, count: Int)? {
        let start = calendar.startOfDay(for: day)
        guard let from = calendar.date(byAdding: .day, value: -baselineNights, to: start) else { return nil }
        let values = nights.filter { $0.date >= from && $0.date < start }.map(\.value).sorted()
        guard values.count >= minimumNights else { return nil }
        let mid = values.count / 2
        return (values.count % 2 == 0 ? (values[mid - 1] + values[mid]) / 2 : values[mid], values.count)
    }

    /// One device compared with itself: the source with the most days in
    /// the last week (a new watch starts its own usual; two devices worn
    /// together never mix). Nights without a source count as one device.
    public static func oneSource(_ nights: [HeartNight], now: Date, calendar: Calendar = .current) -> [HeartNight] {
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)) ?? now
        var days: [String: Int] = [:]
        for night in nights where night.date >= weekAgo { days[night.source ?? "", default: 0] += 1 }
        // Nothing this week (a watch in a drawer): the newest device, so the
        // twin keeps its usual instead of forgetting it.
        guard let current = days.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value })?.key
                ?? nights.max(by: { $0.date < $1.date }).map({ $0.source ?? "" }) else { return [] }
        return nights.filter { ($0.source ?? "") == current }
    }

    /// This morning: is the resting heart rate raised two nights running, and
    /// is variability low? The baseline ends before those two nights so they
    /// don't hide themselves.
    public static func morning(restingHeartRate allResting: [HeartNight], variability allVariability: [HeartNight], now: Date,
                               calendar: Calendar = .current) -> HeartMorning {
        let rhr = oneSource(allResting, now: now, calendar: calendar)
        let hrv = oneSource(allVariability, now: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        func value(_ series: [HeartNight], on day: Date) -> Double? {
            series.last { calendar.isDate($0.date, inSameDayAs: day) }?.value
        }
        // Apple writes resting heart rate through the day: early in the
        // morning today may have no value yet, so the two latest days are
        // today and yesterday when today has one, else the two days before.
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: yesterday) ?? yesterday
        let pair = value(rhr, on: today) != nil ? (yesterday, today) : (dayBefore, yesterday)
        let lastTwo = [value(rhr, on: pair.0), value(rhr, on: pair.1)].compactMap { $0 }
        let base = usual(rhr, before: pair.0, calendar: calendar)
        var raised = false
        if let base, lastTwo.count == 2 {
            let threshold = base.value + max(3, base.value * 0.05)
            raised = lastTwo.allSatisfy { $0 >= threshold }
        }
        // Variability: the three complete days up to yesterday (today's is a
        // partial daytime reading), all three needed, against the usual of
        // the 28 days before them — the same strictness as the heart rate.
        var low = false
        var hrvRecent: Double?
        let hrvDays = (1...3).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let hrvBase = hrvDays.last.flatMap { usual(hrv, before: $0, calendar: calendar) }
        let recent = hrvDays.compactMap { value(hrv, on: $0) }
        if recent.count == 3 {
            let average = recent.reduce(0, +) / 3
            hrvRecent = average
            if let hrvBase { low = average <= hrvBase.value * 0.9 }
        }
        return HeartMorning(usual: base?.value, lastTwo: lastTwo, raised: raised, variabilityLow: low,
                            variabilityRecent: hrvRecent, variabilityUsual: hrvBase?.value)
    }

    /// The check-in's energy guess from the heart: nothing without a usual
    /// (T1) or when the heart is raised (then the athlete is asked, T12);
    /// otherwise "good", which the athlete confirms or changes.
    public static func energyPrefill(_ morning: HeartMorning) -> Int? {
        // A usual and both recent days measured — no reading, no guess (T1, T3).
        guard morning.usual != nil, morning.lastTwo.count == 2, !morning.raised, !morning.variabilityLow else { return nil }
        return 4
    }

    /// The twin's lines: the usual, and how it moved over two months (only a
    /// change of 3 bpm or more, with 14+ nights at both ends).
    public static func knowledge(_ allResting: [HeartNight], now: Date, calendar: Calendar = .current) -> (usual: Double?, was: Double?, nights: Int) {
        // One device only: a change of watch never reads as a change of heart.
        let rhr = oneSource(allResting, now: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let nowUsual = usual(rhr, before: today, calendar: calendar)
        let then = calendar.date(byAdding: .day, value: -56, to: today).flatMap { usual(rhr, before: $0, calendar: calendar) }
        let nights = rhr.filter { $0.date < today && $0.date >= (calendar.date(byAdding: .day, value: -baselineNights, to: today) ?? today) }.count
        guard let nowUsual else { return (nil, nil, nights) }
        guard let then, abs(then.value - nowUsual.value) >= 3 else { return (nowUsual.value, nil, nights) }
        return (nowUsual.value, then.value, nights)
    }
}
