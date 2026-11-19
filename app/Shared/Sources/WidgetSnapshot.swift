import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The small, read-only picture of "today" the widget and the Watch
/// complication show (§16): written by the app into the shared App Group
/// container, never the full relational store.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public var day: Date
    public var sportName: String
    public var sessionTitle: String?
    public var sessionMinutes: Int?
    public var exerciseCount: Int
    public var isGameDay: Bool
    public var checkedIn: Bool
    public var readiness: String?
    public var nextGameDate: Date?
    public var sessionsThisWeek: Int
    public var plannedThisWeek: Int
    /// The athlete's word for a competition ("Match", "Race"); nil in older snapshots.
    public var eventWord: String?
    /// Today's session is already done.
    public var doneToday: Bool?

    public init(
        day: Date, sportName: String, sessionTitle: String?, sessionMinutes: Int?, exerciseCount: Int,
        isGameDay: Bool, checkedIn: Bool, readiness: String?, nextGameDate: Date?,
        sessionsThisWeek: Int, plannedThisWeek: Int
    ) {
        self.day = day
        self.sportName = sportName
        self.sessionTitle = sessionTitle
        self.sessionMinutes = sessionMinutes
        self.exerciseCount = exerciseCount
        self.isGameDay = isGameDay
        self.checkedIn = checkedIn
        self.readiness = readiness
        self.nextGameDate = nextGameDate
        self.sessionsThisWeek = sessionsThisWeek
        self.plannedThisWeek = plannedThisWeek
    }

    public static let placeholder = WidgetSnapshot(
        day: .now, sportName: "Soccer", sessionTitle: "Speed session", sessionMinutes: 42, exerciseCount: 4,
        isGameDay: false, checkedIn: false, readiness: nil, nextGameDate: Calendar.current.date(byAdding: .day, value: 3, to: .now),
        sessionsThisWeek: 1, plannedThisWeek: 3
    )

    static var fileURL: URL? {
        AppIdentifiers.sharedContainer?.appending(path: "widget-snapshot.json")
    }

    /// The snapshot, or nil if none has been written (or the App Group is
    /// missing — §16's silent failure mode).
    public static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Whether this snapshot still describes today.
    public var isCurrent: Bool { Calendar.current.isDateInToday(day) }
}

@MainActor
enum WidgetSnapshotWriter {
    static func write(for athlete: Athlete, week: GeneratedWeek?) {
        let calendar = Calendar.current
        let today = Date.now
        let checkIn = AthleteStats.todaysCheckIn(athlete)
        let adjusted = TodayEngine.todaysWorkout(athlete: athlete, week: week,
                                                 catalogue: CatalogueLoader.load(from: AppConfig.packsDirectory()), calendar: calendar)
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: today)
        // Workouts against the week's planned gym days, as on Home: mobility
        // alone doesn't count, and the ring stops at the plan (never 5/3).
        let planned = week?.sessions.count ?? 0
        let trained = athlete.sessions.filter {
            (weekInterval?.contains($0.startedAt) ?? false) && SessionKinds.kind(of: $0.clientId) != .mobility
        }.count
        let sessionsThisWeek = planned > 0 ? min(trained, planned) : trained

        var snapshot = WidgetSnapshot(
            day: today,
            sportName: AthleteStats.sportName(athlete),
            sessionTitle: adjusted?.title,
            sessionMinutes: adjusted?.estimatedMinutes,
            exerciseCount: adjusted?.items.count ?? 0,
            isGameDay: athlete.competitions.contains { calendar.isDateInToday($0.date) },
            checkedIn: checkIn != nil,
            readiness: checkIn == nil ? nil : DailyLoop.today(athlete)?.level.band.rawValue,
            nextGameDate: AthleteStats.upcomingCompetitions(athlete).first?.date,
            sessionsThisWeek: sessionsThisWeek,
            plannedThisWeek: planned
        )
        snapshot.eventWord = AcademyContent.family(forSport: athlete.activeSport?.sportSlug).tokens["Event"]
        // As on Home: a short mobility session alone isn't "done for today".
        snapshot.doneToday = TodayEngine.workoutDone(athlete, calendar: calendar)
        guard let url = WidgetSnapshot.fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        // Same moments the watch needs a fresh "today": a regenerated week,
        // a check-in, a finished session.
        #if os(iOS) && !APP_EXTENSION
        PhoneWatchBridge.shared.sendToday(athlete: athlete, week: week)
        #endif
    }
}
