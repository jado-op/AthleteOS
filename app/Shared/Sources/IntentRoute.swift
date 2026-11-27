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
    /// Tell AthleteOS opened from inside the app with a sentence started.
    public static func prefillTell(_ text: String) {
        UserDefaults.standard.set(text, forKey: tellKey)
    }

    public static func takeTellText() -> String? {
        defer { UserDefaults.standard.removeObject(forKey: tellKey) }
        return UserDefaults.standard.string(forKey: tellKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Posted when a route arrives while the app is already open (a widget tap).
    public static let didChange = Notification.Name("IntentRoute.didChange")

    /// The lock-screen card's links: athleteos://checkin, athleteos://workout.
    public static func route(from url: URL) -> IntentRoute? {
        guard let scheme = url.scheme?.lowercased(), scheme == "athleteos" || scheme == "aos" else { return nil }
        switch url.host(percentEncoded: false)?.lowercased() {
        case "checkin": return .checkIn
        case "workout": return .workout
        case "tell": return .tell
        default: return nil
        }
    }

    /// Opens a card link; false if the URL isn't one (a team or workout code).
    @discardableResult
    public static func open(_ url: URL) -> Bool {
        guard let route = route(from: url) else { return false }
        set(route)
        NotificationCenter.default.post(name: didChange, object: route.rawValue)
        return true
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
