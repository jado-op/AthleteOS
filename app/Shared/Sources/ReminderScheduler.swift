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
    public static func reschedule(games: [(date: Date, kind: String)]) async {
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

        if current.reflectionEnabled {
            // Same two-week, day-by-day scheme; not on sick days.
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            for offset in 0..<14 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      DayStatusStore.status(on: day) != .sick else { continue }
                let practice = PracticeSchedule.hasPractice(on: day) ? PracticeSchedule.time(on: day) : nil
                let minutes = plan(for: day, settings: current, practice: practice, sessionTomorrowStart: nil).reflection ?? 0
                var components = calendar.dateComponents([.year, .month, .day], from: day)
                components.hour = minutes / 60
                components.minute = minutes % 60
                guard let when = calendar.date(from: components), when > .now else { continue }
                if offset == 0, MindsetStore.reflection(on: day) != nil { continue }
                let content = UNMutableNotificationContent()
                content.title = "Evening reflection"
                content.body = "45 seconds: how today felt shapes tomorrow's plan."
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
                      DayStatusStore.status(on: day) != .sick else { continue }
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
