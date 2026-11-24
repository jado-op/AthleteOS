import Foundation

/// Where a Siri or Shortcuts request wants the app to open (the intents
/// live in the iOS app; screens pick their part up when the app comes up).
public enum IntentRoute: String, Sendable {
    case workout, checkIn, reflection, logPractice, tell

    static let key = "intent.pendingRoute"
    static let tellKey = "intent.tellText"

    /// "Tell AthleteOS …" from Siri: the words wait for Tell AthleteOS to open.
    public static func tell(_ text: String) {
        UserDefaults.standard.set(text, forKey: tellKey)
        set(.tell)
    }

    /// The words Siri brought, once.
    public static func takeTellText() -> String? {
        defer { UserDefaults.standard.removeObject(forKey: tellKey) }
        return UserDefaults.standard.string(forKey: tellKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    public static func set(_ route: IntentRoute) {
        UserDefaults.standard.set(route.rawValue, forKey: key)
    }

    public static var pending: IntentRoute? {
        UserDefaults.standard.string(forKey: key).flatMap(IntentRoute.init(rawValue:))
    }

    /// Takes the route if it is one of `routes` (each screen takes its own).
    public static func take(_ routes: Set<IntentRoute>) -> IntentRoute? {
        guard let route = pending, routes.contains(route) else { return nil }
        UserDefaults.standard.removeObject(forKey: key)
        return route
    }
}
