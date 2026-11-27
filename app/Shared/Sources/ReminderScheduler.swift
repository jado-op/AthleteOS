import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// A bedtime from tomorrow's wake-up and teenagers' 8–10 hours of sleep
/// (aiming for 9), earlier when practice or a game starts early.
public enum Bedtime {
    public static let sleepNeedMinutes = 9 * 60

    /// Minutes after midnight (can be before midnight of the previous day,
    /// e.g. 22:15 = 1335).
    public static func suggested(wakeMinutes: Int, firstSessionTomorrow: Int?) -> Int {
        // Up at least 90 minutes before an early start.
        let wake = min(wakeMinutes, firstSessionTomorrow.map { $0 - 90 } ?? Int.max)
        let bed = wake - sleepNeedMinutes
        return bed < 0 ? bed + 24 * 60 : bed
    }

    /// The first practice or game start tomorrow, if it's in the morning.
    public static func firstSessionStart(on day: Date, games: [Date], calendar: Calendar = .current) -> Int? {
        var starts: [Int] = []
        if PracticeSchedule.hasPractice(on: day, calendar: calendar), let time = PracticeSchedule.time(on: day, calendar: calendar) {
            starts.append(time.start)
        }
        for game in games where calendar.isDate(game, inSameDayAs: day) {
            let parts = calendar.dateComponents([.hour, .minute], from: game)
            let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            if minutes > 0 { starts.append(minutes) }
        }
        return starts.filter { $0 < 12 * 60 }.min()
    }

    public static func label(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: (minutes / 60) % 24, minute: minutes % 60, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Tomorrow's plan for one evening's message (from the plan of record):
/// "Strength after practice · 40 min" and "Practice 4:00–6:00 pm".
public struct EveningPlan: Sendable, Equatable {
    public var title: String
    public var detail: String?
    public init(title: String, detail: String?) { self.title = title; self.detail = detail }
}

/// Local notifications only — no push server, no third party (§0). A daily
/// morning check-in nudge (§11: "a check-in nobody completes is worse than
/// none") and a heads-up the evening before each game.
public enum ReminderScheduler {
    static let checkInIdentifier = "reminder.check-in"
    static let checkedInDayKey = "reminders.checkedInDay"

    /// The check-in or reflection is done for today: today's reminder for it
    /// goes (and isn't scheduled again on the next reschedule).
    public static func markDone(checkIn: Bool = false, reflection: Bool = false, now: Date = .now, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        let suffix = "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
        var ids: [String] = []
        if checkIn {
            UserDefaults.standard.set(DayKey.of(now, calendar: calendar), forKey: checkedInDayKey)
            ids.append("\(checkInIdentifier).\(suffix)")
        }
        if reflection { ids.append("\(reflectionIdentifier).\(suffix)") }
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        #endif
    }

    static let gamePrefix = "reminder.game."
    static let reflectionIdentifier = "reminder.reflection"

    public struct Settings: Codable, Equatable, Sendable {
        public var checkInEnabled: Bool
        public var checkInHour: Int
        public var checkInMinute: Int
        public var gameRemindersEnabled: Bool
        /// The 2-minute evening reflection (Mindset).
        public var reflectionEnabled: Bool
        public var reflectionHour: Int
        public var reflectionMinute: Int
        /// A quiet nudge 30 minutes before the suggested bedtime.
        public var bedtimeEnabled: Bool
        /// Reminders follow the day: a later check-in at weekends, the
        /// reflection an hour after practice ends.
        public var smartTiming: Bool

        public init(checkInEnabled: Bool, checkInHour: Int, checkInMinute: Int, gameRemindersEnabled: Bool,
                    reflectionEnabled: Bool = false, reflectionHour: Int = 20, reflectionMinute: Int = 30,
                    bedtimeEnabled: Bool = false, smartTiming: Bool = true) {
            self.bedtimeEnabled = bedtimeEnabled
            self.smartTiming = smartTiming
            self.checkInEnabled = checkInEnabled
            self.checkInHour = checkInHour
            self.checkInMinute = checkInMinute
            self.gameRemindersEnabled = gameRemindersEnabled
            self.reflectionEnabled = reflectionEnabled
            self.reflectionHour = reflectionHour
            self.reflectionMinute = reflectionMinute
        }

        /// Settings saved before the evening reflection existed still load,
        /// and so do ones saved with the retired hydration reminder (its key
        /// is simply ignored).
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            checkInEnabled = try c.decode(Bool.self, forKey: .checkInEnabled)
            checkInHour = try c.decode(Int.self, forKey: .checkInHour)
            checkInMinute = try c.decode(Int.self, forKey: .checkInMinute)
            gameRemindersEnabled = try c.decode(Bool.self, forKey: .gameRemindersEnabled)
            reflectionEnabled = try c.decodeIfPresent(Bool.self, forKey: .reflectionEnabled) ?? false
            reflectionHour = try c.decodeIfPresent(Int.self, forKey: .reflectionHour) ?? 20
            reflectionMinute = try c.decodeIfPresent(Int.self, forKey: .reflectionMinute) ?? 30
            bedtimeEnabled = try c.decodeIfPresent(Bool.self, forKey: .bedtimeEnabled) ?? false
            smartTiming = try c.decodeIfPresent(Bool.self, forKey: .smartTiming) ?? true
        }

        public static let `default` = Settings(checkInEnabled: false, checkInHour: 7, checkInMinute: 15, gameRemindersEnabled: false)

        public var anyEnabled: Bool { checkInEnabled || gameRemindersEnabled || reflectionEnabled || bedtimeEnabled }
    }

    static let bedtimeIdentifier = "reminder.bedtime"
    /// The retired hydration reminder. No longer scheduled; kept so any
    /// still-pending ones from older builds are removed on reschedule.
    static let retiredHydrationIdentifier = "reminder.hydration"

    /// Weekend mornings the check-in comes 75 minutes later.
    public static let weekendDelayMinutes = 75

    /// Minutes after midnight for one day's check-in and reflection, and the
    /// bedtime nudge (nil when off or not on that day). Pure, for testing.
    public static func plan(for day: Date, settings: Settings, practice: PracticeTime?, sessionTomorrowStart: Int?,
                            calendar: Calendar = .current) -> (checkIn: Int?, reflection: Int?, bedtime: Int?) {
        let weekday = calendar.component(.weekday, from: day)
        let weekend = weekday == 1 || weekday == 7
        var checkIn = settings.checkInHour * 60 + settings.checkInMinute
        if settings.smartTiming && weekend { checkIn += weekendDelayMinutes }
        var reflection = settings.reflectionHour * 60 + settings.reflectionMinute
        if settings.smartTiming, let practice {
            // An hour after practice, but never later than 21:30 or earlier than 17:00.
            reflection = min(21 * 60 + 30, max(17 * 60, practice.end + 60))
        }
        let bed = Bedtime.suggested(wakeMinutes: nextWake(after: day, settings: settings, calendar: calendar),
                                    firstSessionTomorrow: sessionTomorrowStart)
        return (settings.checkInEnabled ? checkIn : nil,
                settings.reflectionEnabled ? reflection : nil,
                // A bedtime after midnight stays after midnight (minutes past
                // 24:00), never pulled back to 20:00.
                settings.bedtimeEnabled ? max(20 * 60, (bed < 12 * 60 ? bed + 24 * 60 : bed) - 30) : nil)
    }

    /// Tomorrow's wake-up: the check-in time (later at weekends).
    static func nextWake(after day: Date, settings: Settings, calendar: Calendar = .current) -> Int {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let weekday = calendar.component(.weekday, from: tomorrow)
        let base = settings.checkInHour * 60 + settings.checkInMinute
        return base + (settings.smartTiming && (weekday == 1 || weekday == 7) ? weekendDelayMinutes : 0)
    }

    private static let settingsKey = "reminderSettings"

    public static var settings: Settings {
        get {
            guard let data = UserDefaults.standard.data(forKey: settingsKey),
                  let decoded = try? JSONDecoder().decode(Settings.self, from: data) else { return .default }
            return decoded
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: settingsKey)
        }
    }

    /// The evening-before reminder time for a game: 20:00 the day before,
    /// or nil if that moment has already passed.
    public static func gameReminderDate(for game: Date, now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: game)),
              let evening = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: dayBefore),
              evening > now else { return nil }
        return evening
    }

    #if canImport(UserNotifications)
    /// Asks once; returns whether notifications may be shown.
    public static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Replaces every reminder this app owns with ones matching `settings`
    /// and the given upcoming games. Safe to call as often as convenient.
    ///
    /// One evening message (docs/PLAN-CHANGES-RESEARCH.md P8–P13): the
    /// evening reflection says tomorrow's plan (`tomorrow`, keyed by the
    /// evening's `DayKey`, from the plan of record) and the bedtime; on a game
    /// eve the game note is the evening's one message. With the morning
    /// check-in that is at most two a day. Never pain, mood or body words.
    public static func reschedule(games: [(date: Date, kind: String)], tomorrow: [String: EveningPlan] = [:]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter {
            $0.hasPrefix(checkInIdentifier) || $0.hasPrefix(gamePrefix) || $0.hasPrefix(reflectionIdentifier)
                || $0.hasPrefix(bedtimeIdentifier) || $0.hasPrefix(retiredHydrationIdentifier)
        }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        let current = settings
        if current.checkInEnabled {
            // One reminder per day for the next two weeks rather than a
            // repeating one, so sick, travel and holiday days (Home's day
            // status) stay quiet. Rescheduled every time the app opens.
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            for offset in 0..<14 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      DayStatusStore.status(on: day).trainsAsPlanned else { continue }
                let minutes = plan(for: day, settings: current, practice: nil, sessionTomorrowStart: nil).checkIn ?? 0
                var components = calendar.dateComponents([.year, .month, .day], from: day)
                components.hour = minutes / 60
                components.minute = minutes % 60
                guard let when = calendar.date(from: components), when > .now else { continue }
                if offset == 0, UserDefaults.standard.string(forKey: checkedInDayKey) == DayKey.of(day, calendar: calendar) { continue }
                let content = UNMutableNotificationContent()
                content.title = "Morning check-in"
                content.body = "30 seconds: how did you sleep? Your plan adjusts to how you feel."
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let id = "\(checkInIdentifier).\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
                try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }

        // Evenings that already have their one message.
        var eveningsTold = Set<String>()
        // The evening before each game (even once its 20:00 note has gone).
        let gameEves: Set<String> = current.gameRemindersEnabled ? Set(games.prefix(20).compactMap { game in
            Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: game.date)).map { DayKey.of($0) }
        }) : []
        if current.reflectionEnabled {
            // Same two-week, day-by-day scheme; not on sick days.
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            for offset in 0..<14 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      DayStatusStore.status(on: day) != .sick,
                      !gameEves.contains(DayKey.of(day, calendar: calendar)) else { continue }
                let practice = PracticeSchedule.hasPractice(on: day) ? PracticeSchedule.time(on: day) : nil
                let minutes = plan(for: day, settings: current, practice: practice, sessionTomorrowStart: nil).reflection ?? 0
                var components = calendar.dateComponents([.year, .month, .day], from: day)
                components.hour = minutes / 60
                components.minute = minutes % 60
                guard let when = calendar.date(from: components), when > .now else { continue }
                if offset == 0, MindsetStore.reflection(on: day) != nil { continue }
                let content = UNMutableNotificationContent()
                let key = DayKey.of(day, calendar: calendar)
                if let plan = tomorrow[key] {
                    // The plan itself, as a when/what (P9), then the ask.
                    content.title = "Tomorrow: \(plan.title)"
                    content.body = (plan.detail.map { "\($0). " } ?? "") + "How did today feel? 45 seconds fine-tunes it."
                } else {
                    content.title = "Evening reflection"
                    content.body = "45 seconds: how today felt shapes tomorrow's plan."
                }
                if current.bedtimeEnabled, let tomorrowDay = calendar.date(byAdding: .day, value: 1, to: day) {
                    // The wind-down folds in here: one message, not two. Only a
                    // bedtime still ahead of this message is worth saying.
                    let bed = Bedtime.suggested(wakeMinutes: nextWake(after: day, settings: current, calendar: calendar),
                                                firstSessionTomorrow: Bedtime.firstSessionStart(on: tomorrowDay, games: games.map(\.date), calendar: calendar))
                    let bedAfterMidnightStart = bed < 12 * 60 ? bed + 24 * 60 : bed
                    if bedAfterMidnightStart > minutes { content.body += " Bed by \(Bedtime.label(bed))." }
                }
                eveningsTold.insert(key)
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let id = "\(reflectionIdentifier).\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
                try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }

        if current.bedtimeEnabled {
            // Quiet: no sound, one a night, only on nights before a normal day.
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            for offset in 0..<14 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      let tomorrow = calendar.date(byAdding: .day, value: 1, to: day),
                      DayStatusStore.status(on: day) != .sick,
                      !eveningsTold.contains(DayKey.of(day, calendar: calendar)) else { continue }
                let gameDates = games.map { $0.date }
                // The game reminder already says "bed early": never two nudges in one evening.
                if current.gameRemindersEnabled, gameDates.contains(where: { calendar.isDate($0, inSameDayAs: tomorrow) }) { continue }
                let early = Bedtime.firstSessionStart(on: tomorrow, games: gameDates, calendar: calendar)
                guard let minutes = plan(for: day, settings: current, practice: nil, sessionTomorrowStart: early).bedtime,
                      let at = calendar.date(byAdding: .minute, value: minutes, to: day) else { continue }
                let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: at)
                guard at > .now else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Wind down"
                content.body = "Bed in 30 minutes gives you enough sleep for tomorrow. Screens away."
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let id = "\(bedtimeIdentifier).\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
                try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }

        if current.gameRemindersEnabled {
            for game in games.prefix(20) {
                guard let when = gameReminderDate(for: game.date) else { continue }
                let content = UNMutableNotificationContent()
                content.title = "\(game.kind) tomorrow"
                content.body = "Keep today light and get to bed early."
                content.sound = .default
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: when)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                let id = gamePrefix + String(Int(game.date.timeIntervalSince1970))
                try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
    }
    #endif
}

/// Reminders for days told ahead in Tell AthleteOS ("holiday Friday until
/// Monday", "no gym this weekend"): one the evening before the first day and
/// one each morning — a short bodyweight workout is ready, always optional.
/// Kept apart from `ReminderScheduler.reschedule`, which leaves these alone.
public enum AwayReminders {
    static let prefix = "reminder.away."

    /// "holiday", "travel" or "noGym" for each day.
    public static func title(_ kind: String) -> String {
        switch kind {
        case "holiday": "Holiday"
        case "travel": "Travel day"
        default: "No gym"
        }
    }

    #if canImport(UserNotifications)
    public static func schedule(days: [(day: Date, kind: String)], now: Date = .now, calendar: Calendar = .current) async {
        let sorted = days.filter { ["holiday", "travel", "noGym"].contains($0.kind) }.sorted { $0.day < $1.day }
        guard let first = sorted.first, await ReminderScheduler.requestAuthorization() else { return }
        let center = UNUserNotificationCenter.current()
        func add(_ id: String, at date: Date, title: String, body: String) async {
            guard date > now else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            try? await center.add(UNNotificationRequest(identifier: id, content: content,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
        let body = first.kind == "noGym"
            ? "Your workouts switch to bodyweight — same plan, no equipment. Do as much as you like."
            : "Bodyweight workouts are ready, 15–20 minutes. All optional."
        if let eve = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: first.day)),
           let at = calendar.date(bySettingHour: 19, minute: 30, second: 0, of: eve) {
            await add(prefix + "eve." + DayKey.of(first.day, calendar: calendar), at: at, title: "\(title(first.kind)) from tomorrow", body: body)
        }
        // Mornings: the check-in time when that reminder is on, otherwise 9:30.
        let settings = ReminderScheduler.settings
        let hour = settings.checkInEnabled ? settings.checkInHour : 9
        let minute = settings.checkInEnabled ? settings.checkInMinute : 30
        for entry in sorted.prefix(14) {
            guard let at = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.startOfDay(for: entry.day)) else { continue }
            await add(prefix + DayKey.of(entry.day, calendar: calendar), at: at, title: "\(title(entry.kind)) today",
                      body: entry.kind == "noGym" ? "Today's workout is bodyweight only. Optional, as always."
                                                  : "A quick bodyweight workout is ready if you feel like moving.")
        }
    }
    #endif
}
