import Foundation

/// The athlete's Suunto account through Suunto's Cloud API, via our server
/// (backend/src/routes/suunto.js). The server keeps only the tokens; workouts
/// come straight through to this phone. Everything degrades to "nothing":
/// no account, no server keys, or no network means no Suunto workouts, never
/// an error on screen.
public enum SuuntoCloud {
    static let connectedKey = "suunto.cloudConnected"

    /// Whether this phone last saw the Suunto account connected (so the
    /// plan doesn't ask the server when nothing is connected).
    public static var isConnected: Bool {
        get { UserDefaults.standard.bool(forKey: connectedKey) }
        set { UserDefaults.standard.set(newValue, forKey: connectedKey) }
    }

    public struct Status: Decodable, Sendable, Equatable {
        /// The server holds Suunto partner keys (otherwise there is nothing to connect).
        public var available: Bool
        public var connected: Bool
    }

    private struct WireWorkout: Decodable {
        let start: String
        let end: String
        let activity: String
        let averageHeartRate: Double?
    }

    private struct WireWorkouts: Decodable { let workouts: [WireWorkout] }
    private struct WireConnect: Decodable { let url: String }

    private static var token: String? { try? KeychainTokenStore().read() }

    private static func request(_ path: String, method: String = "GET", query: [URLQueryItem] = []) -> URLRequest? {
        guard let token else { return nil }
        var url = AppConfig.backendBaseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// nil: no account on this phone, or the server couldn't be reached.
    public static func status() async -> Status? {
        guard let request = request("suunto/status"),
              let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let status = try? JSONDecoder().decode(Status.self, from: data) else { return nil }
        isConnected = status.connected
        return status
    }

    /// The Suunto sign-in page to open; it comes back to athleteos://suunto.
    public static func connectURL() async -> URL? {
        guard let request = request("suunto/connect", method: "POST"),
              let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let wire = try? JSONDecoder().decode(WireConnect.self, from: data) else { return nil }
        return URL(string: wire.url)
    }

    /// What the server's redirect said: connected, or why not.
    public enum ConnectResult: Equatable { case connected, cancelled, failed }

    public static func result(from callback: URL) -> ConnectResult {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if items.contains(where: { $0.name == "connected" && $0.value == "1" }) { return .connected }
        return items.contains(where: { $0.name == "error" && $0.value == "denied" }) ? .cancelled : .failed
    }

    public static func disconnect() async {
        isConnected = false
        guard let request = request("suunto/connection", method: "DELETE") else { return }
        _ = try? await URLSession.shared.data(for: request)
    }

    /// One night from Suunto's 24/7 data: when it ended and hours actually asleep.
    public struct Night: Sendable, Equatable {
        public var end: Date
        public var hours: Double
        /// Overnight heart-rate variability, ms.
        public var variability: Double? = nil
        /// Lowest heart rate asleep, bpm.
        public var lowestHeartRate: Double? = nil
    }

    private struct WireNight: Decodable {
        let end: String
        let hours: Double
        let variability: Double?
        let lowestHeartRate: Double?
    }
    private struct WireNights: Decodable { let nights: [WireNight] }

    /// The last `days` nights of Suunto sleep, oldest first (empty when not connected).
    public static func nights(days: Int) async -> [Night] {
        guard isConnected, let request = request("suunto/sleep", query: [URLQueryItem(name: "days", value: "\(days)")]),
              let (data, response) = try? await URLSession.shared.data(for: request) else { return [] }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { isConnected = false }
        guard status == 200, let wire = try? JSONDecoder().decode(WireNights.self, from: data) else { return [] }
        return wire.nights.compactMap { night in
            APIClient.parseTimestamp(night.end).map {
                Night(end: $0, hours: night.hours, variability: night.variability, lowestHeartRate: night.lowestHeartRate)
            }
        }.sorted { $0.end < $1.end }
    }

    /// Last night's sleep from Suunto: a night that ended this morning.
    public static func lastNight(now: Date = .now, calendar: Calendar = .current) async -> Double? {
        let today = calendar.startOfDay(for: now)
        return await nights(days: 2).last { $0.end >= today.addingTimeInterval(-6 * 3600) && $0.end <= now }?.hours
    }

    /// Fills measured sleep for nights Health doesn't have (readiness, the gym
    /// advisor and the weights read it).
    public static func storeNights(days: Int = 7, calendar: Calendar = .current) async {
        let measured = MeasuredSleepStore.all()
        for night in await nights(days: days) where measured[DayKey.of(night.end, calendar: calendar)] == nil {
            MeasuredSleepStore.save(night.hours, on: night.end, calendar: calendar)
        }
    }

    /// The last `days` days of Suunto workouts (empty when not connected).
    public static func workouts(days: Int) async -> [ExternalWorkout] {
        guard isConnected, let request = request("suunto/workouts", query: [URLQueryItem(name: "days", value: "\(days)")]) else { return [] }
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return [] }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { isConnected = false }
        guard status == 200, let wire = try? JSONDecoder().decode(WireWorkouts.self, from: data) else { return [] }
        return wire.workouts.compactMap { workout in
            guard let start = APIClient.parseTimestamp(workout.start), let end = APIClient.parseTimestamp(workout.end) else { return nil }
            return ExternalWorkout(start: start, end: end, activity: workout.activity,
                                   averageHeartRate: workout.averageHeartRate, source: "Suunto")
        }
    }
}
