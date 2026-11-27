import Foundation

/// Daily resting heart rate and HRV from Apple Health, per device, kept on
/// this phone only (`health.` keys are never backed up — Health data stays
/// on the device). The check-in and the twin read it through `HeartSignals`.
@MainActor
enum HeartStore {
    /// Day → device → value.
    static let restingKey = "health.heart.resting.v2"
    static let variabilityKey = "health.heart.variability.v2"
    /// Enough for a 28-night usual now and two months ago.
    static let keepDays = 100

    static var resting: [HeartNight] { load(restingKey) }
    static var variability: [HeartNight] { load(variabilityKey) }

    /// Reads the last 90 days from Health (any watch or band that writes
    /// there). When anything new arrived, the plan and Home redraw with it.
    static func refresh() async {
        #if canImport(HealthKit)
        guard HealthKitManager.shared.isAvailable, !DemoData.isEnabled else { return }
        let rhr = await HealthKitManager.shared.dailyBySource(resting: true, days: 90)
        let hrv = await HealthKitManager.shared.dailyBySource(resting: false, days: 90)
        let restingChanged = save(rhr, key: restingKey)
        let variabilityChanged = save(hrv, key: variabilityKey)
        let changed = restingChanged || variabilityChanged
        if changed { NotificationCenter.default.post(name: WeeklyPlan.inputsChanged, object: nil) }
        #endif
    }

    /// This morning, read the careful way.
    static func morning(now: Date = .now, calendar: Calendar = .current) -> HeartMorning {
        HeartSignals.morning(restingHeartRate: resting, variability: variability, now: now, calendar: calendar)
    }

    private static func load(_ key: String) -> [HeartNight] {
        let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Double]] ?? [:]
        var nights: [HeartNight] = []
        for (day, sources) in stored {
            guard let date = TwinInputBuilder.day(day, calendar: .current) else { continue }
            for (source, value) in sources {
                nights.append(HeartNight(date: date, value: value, source: source))
            }
        }
        // By day, then device, so the order is the same every time.
        nights.sort { first, second in
            if first.date != second.date { return first.date < second.date }
            return (first.source ?? "") < (second.source ?? "")
        }
        return nights
    }

    /// Merges what Health returned (it may hold less than we kept: a reset
    /// phone, a watch unpaired) and drops days older than `keepDays`.
    /// Returns whether anything changed; writes only then.
    private static func save(_ nights: [HeartNight], key: String) -> Bool {
        guard !nights.isEmpty else { return false }
        let before = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: Double]] ?? [:]
        var values = before
        for night in nights where night.value > 0 {
            values[DayKey.of(night.date), default: [:]][night.source ?? "unknown"] = (night.value * 10).rounded() / 10
        }
        let cutoff = DayKey.of(Calendar.current.date(byAdding: .day, value: -keepDays, to: .now) ?? .now)
        values = values.filter { $0.key >= cutoff }
        guard values != before else { return false }
        UserDefaults.standard.set(values, forKey: key)
        return true
    }
}
