import Foundation

/// §10's four training phases.
public enum SeasonPhase: String, Sendable, Codable, CaseIterable {
    case offSeason = "OFF_SEASON"
    case preSeason = "PRE_SEASON"
    case inSeason = "IN_SEASON"
    case postSeason = "POST_SEASON"

    /// What the gym work is for in this phase, in one line (the Workout tab).
    public var focus: String {
        switch self {
        case .offSeason: "Off-season: building strength and power while there are no games."
        case .preSeason: "Pre-season: turning strength into speed for the season ahead."
        case .inSeason: "In season: two short sessions to keep what you built, fresh for games."
        case .postSeason: "After the season: lighter weeks to recover before building again."
        }
    }
}

/// §10 describes the four phases with qualitative ranges ("3–8 weeks out",
/// "2–4 weeks after the last game"), not hard day-counts tied to a specific
/// field. This implementation anchors them to the athlete's own declared
/// season window (`AthleteSport.seasonStart`/`seasonEnd`) rather than
/// inferring a competition cadence from scattered `Competition` rows, which
/// would be fragile with a sparse calendar and, more importantly, is a
/// different concern: §10's day-by-day game-week taper (M7) already owns
/// competition-proximity logic at the SESSION level. This function answers
/// a coarser question — which phase governs the whole week — from a field
/// that already exists on the model for exactly this purpose.
public enum PhaseCalculator {
    public static func phase(
        today: Date, seasonStart: Date, seasonEnd: Date, calendar: Calendar = .current,
        preSeasonStart: Date? = PreSeasonStore.start
    ) -> SeasonPhase {
        let today = calendar.startOfDay(for: today)
        let start = calendar.startOfDay(for: seasonStart)
        let end = calendar.startOfDay(for: seasonEnd)

        if today >= start && today <= end {
            return .inSeason
        }
        // The athlete said when pre-season training starts ("dryland from the
        // first week of December"): that day, not a fixed eight weeks, opens it.
        if today < start, let pre = preSeasonStart.map({ calendar.startOfDay(for: $0) }),
           pre < start, start.timeIntervalSince(pre) <= 26 * 7 * 86_400 {
            if today >= pre { return .preSeason }
            let daysSince = calendar.dateComponents([.day], from: end, to: today).day ?? Int.max
            return daysSince >= 0 && daysSince <= 4 * 7 ? .postSeason : .offSeason
        }
        if today < start {
            let daysOut = calendar.dateComponents([.day], from: today, to: start).day ?? Int.max
            return daysOut <= 8 * 7 ? .preSeason : .offSeason
        }
        let daysSince = calendar.dateComponents([.day], from: end, to: today).day ?? Int.max
        return daysSince <= 4 * 7 ? .postSeason : .offSeason
    }
}

/// The day pre-season training starts, when the athlete has said so (Tell
/// AthleteOS: "dryland starts the first week of December"). Used by
/// `PhaseCalculator` only while it lies before the season start.
public enum PreSeasonStore {
    static let key = "season.preSeasonStart"

    public static var start: Date? {
        get { UserDefaults.standard.object(forKey: key) as? Date }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }
}
