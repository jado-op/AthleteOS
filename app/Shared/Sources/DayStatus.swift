import Foundation

/// What kind of day it is for the athlete, set from the top-left of Home.
/// The plan and the reminders follow it, so the app never nags someone who
/// is ill, travelling or on holiday.
public enum DayStatus: String, CaseIterable, Codable, Sendable, Identifiable {
    /// A normal day: school, practice, the plan as usual.
    case active
    case sick
    /// A possible head injury: every workout pauses until a doctor clears the
    /// athlete. Set from the Safety Center, never from the day menu.
    case concussion
    case travel
    case holiday

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .active: "Normal Day"
        case .sick: "Sick / Rest"
        case .concussion: "Training paused"
        case .travel: "Travel Day"
        case .holiday: "Holiday"
        }
    }

    public var systemImage: String {
        switch self {
        case .active: "sun.max.fill"
        case .sick: "bed.double.fill"
        case .concussion: "bandage.fill"
        case .travel: "airplane"
        case .holiday: "beach.umbrella.fill"
        }
    }

    /// What the app does differently, in one line — shown in the menu so it explains itself.
    public var explanation: String {
        switch self {
        case .active: "Your plan as usual."
        case .sick: "No training. Rest and recover."
        case .concussion: "Possible head injury: no training until a doctor clears you."
        case .travel: "An optional 15-minute workout, no equipment."
        case .holiday: "Plan paused. Optional light workouts."
        }
    }

    /// Whether workouts are planned and reminded as usual.
    public var trainsAsPlanned: Bool { self == .active }

    /// The day types an athlete picks from. A head injury isn't a kind of
    /// day — it's reported in the Safety Center, which pauses training.
    public static let menu: [DayStatus] = [.active, .sick, .travel, .holiday]
}

/// The athlete's current status and how long it lasts. Stored on this
/// device; an expired status falls back to `.active` on its own.
public enum DayStatusStore {
    private static let key = "dayStatus.v1"

    private struct Stored: Codable {
        var status: DayStatus
        /// Last day (inclusive) the status applies; nil = until changed.
        var until: Date?
        var from: Date
    }

    private static var stored: Stored? {
        get {
            guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(Stored.self, from: data)
        }
        set {
            UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
        }
    }

    public static func status(on date: Date = .now, calendar: Calendar = .current) -> DayStatus {
        let day = calendar.startOfDay(for: date)
        if let stored, day >= calendar.startOfDay(for: stored.from),
           stored.until.map({ day <= calendar.startOfDay(for: $0) }) ?? true {
            return stored.status
        }
        // Days told ahead ("holiday Friday until Monday"); the latest told wins.
        if let ahead = planned.last(where: { day >= calendar.startOfDay(for: $0.from) && day <= calendar.startOfDay(for: $0.until) }) {
            return ahead.status
        }
        return .active
    }

    // MARK: Days told ahead

    private static let plannedKey = "dayStatus.planned.v1"

    private struct Planned: Codable {
        var status: DayStatus
        var from: Date
        /// Last day, inclusive.
        var until: Date
    }

    private static var planned: [Planned] {
        get {
            guard let data = UserDefaults.standard.data(forKey: plannedKey) else { return [] }
            return (try? JSONDecoder().decode([Planned].self, from: data)) ?? []
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: plannedKey)
        }
    }

    /// Statuses told for days ahead (sick, travel, holiday), from `from` for
    /// `days` days. Starting today it's the current status (`set`); later it
    /// waits for its day without touching today's. Rest days never break the streak.
    public static func schedule(_ status: DayStatus, from: Date, days: Int, now: Date = .now, calendar: Calendar = .current) {
        guard status != .active, status != .concussion, days > 0 else { return }
        let today = calendar.startOfDay(for: now)
        let start = max(calendar.startOfDay(for: from), today)
        let lastDay = calendar.date(byAdding: .day, value: days - 1, to: calendar.startOfDay(for: from)) ?? start
        guard lastDay >= start else { return }
        if start == today {
            // A head-injury pause is only lifted by the Safety Center.
            guard self.status(on: now, calendar: calendar) != .concussion else { return }
            let left = (calendar.dateComponents([.day], from: today, to: lastDay).day ?? 0) + 1
            set(status, days: left, now: now, calendar: calendar)
            return
        }
        var all = planned.filter { calendar.startOfDay(for: $0.until) >= today }
        all.append(Planned(status: status, from: start, until: lastDay))
        planned = Array(all.suffix(20))
    }

    /// Days ahead with a told status, in order (for "coming up" lists).
    public static func plannedDays(now: Date = .now, calendar: Calendar = .current) -> [(day: Date, status: DayStatus)] {
        let today = calendar.startOfDay(for: now)
        var out: [(day: Date, status: DayStatus)] = []
        for entry in planned where calendar.startOfDay(for: entry.until) >= today {
            var day = max(calendar.startOfDay(for: entry.from), today)
            for _ in 0..<31 where day <= calendar.startOfDay(for: entry.until) {
                out.append((day, status(on: day, calendar: calendar)))
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            }
        }
        return out.sorted { $0.day < $1.day }
    }

    /// The last day the current status lasts, if it has an end.
    public static var until: Date? { stored?.until }

    /// Sets the status from today. `days` = how many days it lasts (1 = just
    /// today); nil keeps it until changed. `.active` clears it.
    /// The status as stored, even after it ran out (nil: none).
    public static var storedStatus: DayStatus? { stored?.status }

    public static func set(_ status: DayStatus, days: Int?, now: Date = .now, calendar: Calendar = .current) {
        // Leaving "sick" starts the return after illness (IllnessReturn).
        if stored?.status == .sick, status != .sick, self.status(on: now, calendar: calendar) == .sick {
            IllnessReturn.markRecovered(on: now, calendar: calendar)
        }
        // Today's own choice wins over anything told ahead for today.
        let todayStart = calendar.startOfDay(for: now)
        planned = planned.compactMap { (original: Planned) -> Planned? in
            var entry = original
            guard calendar.startOfDay(for: entry.from) <= todayStart, calendar.startOfDay(for: entry.until) >= todayStart else { return entry }
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart), tomorrow <= calendar.startOfDay(for: entry.until) else { return nil }
            entry.from = tomorrow
            return entry
        }
        guard status != .active else { stored = nil; return }
        let today = calendar.startOfDay(for: now)
        let until = days.flatMap { calendar.date(byAdding: .day, value: max(0, $0 - 1), to: today) }
        stored = Stored(status: status, until: until, from: today)
        StreakFreeze.protect(today, calendar: calendar)
    }
}

/// Sick, travel, holiday and head-injury days don't break the streak: they
/// are remembered here (backed up with progress) and skipped when counting.
public enum StreakFreeze {
    static let key = "progress.frozenDays"

    public static func days(_ defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    public static func protect(_ date: Date, calendar: Calendar = .current, _ defaults: UserDefaults = .standard) {
        var all = days(defaults)
        all.insert(DayKey.of(date, calendar: calendar))
        defaults.set(Array(all.sorted().suffix(400)), forKey: key)
    }

    /// Called when the app opens: a day spent sick, travelling or on holiday
    /// is protected, even when the status was set days ago.
    public static func protectTodayIfResting(now: Date = .now, calendar: Calendar = .current) {
        if DayStatusStore.status(on: now, calendar: calendar) != .active { protect(now, calendar: calendar) }
    }
}

/// The athlete chose to train as planned on a low-readiness day (today only).
public enum ReadinessOverride {
    public static let key = "progress.readinessOverrideDay"

    public static func isOn(_ date: Date = .now, calendar: Calendar = .current, _ defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: key) == DayKey.of(date, calendar: calendar)
    }
}

/// Days without a gym (gym closed, hotel, holiday flat): the planned workout
/// stays, built from bodyweight exercises only. Keyed by local day.
public enum NoGymDays {
    static let key = "schedule.noGymDays"

    public static func contains(_ date: Date, calendar: Calendar = .current, _ defaults: UserDefaults = .standard) -> Bool {
        (defaults.stringArray(forKey: key) ?? []).contains(DayKey.of(date, calendar: calendar))
    }

    public static func add(from: Date, days: Int, calendar: Calendar = .current, _ defaults: UserDefaults = .standard) {
        var all = Set(defaults.stringArray(forKey: key) ?? [])
        let start = calendar.startOfDay(for: from)
        for offset in 0..<max(0, min(days, 31)) {
            if let day = calendar.date(byAdding: .day, value: offset, to: start) { all.insert(DayKey.of(day, calendar: calendar)) }
        }
        // Keep recent and future days only.
        let oldest = DayKey.of(calendar.date(byAdding: .day, value: -14, to: Date()) ?? Date(), calendar: calendar)
        defaults.set(all.filter { $0 >= oldest }.sorted(), forKey: key)
    }

    public static func remove(_ date: Date, calendar: Calendar = .current, _ defaults: UserDefaults = .standard) {
        let day = DayKey.of(date, calendar: calendar)
        defaults.set((defaults.stringArray(forKey: key) ?? []).filter { $0 != day }, forKey: key)
    }
}
