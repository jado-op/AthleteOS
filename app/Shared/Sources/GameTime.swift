import Foundation

/// When a game starts. Calendar games often carry only a date; the athlete's
/// usual game time (UserDefaults `gameStartMinutes`, minutes since midnight,
/// set in the schedule editor) fills in the clock time.
public enum GameTime {
    /// UserDefaults key for the usual game start, in minutes since midnight.
    public static let usualStartKey = "gameStartMinutes"
    /// 5 pm, when the athlete hasn't set a usual time.
    public static let defaultUsualMinutes = 17 * 60

    /// The calendar's time when it has one, otherwise the athlete's usual game time.
    public static func start(_ game: Date, usualMinutes: Int, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.hour, .minute], from: game)
        if (parts.hour ?? 0) != 0 || (parts.minute ?? 0) != 0 { return game }
        return calendar.date(bySettingHour: usualMinutes / 60, minute: usualMinutes % 60, second: 0, of: game) ?? game
    }
}
