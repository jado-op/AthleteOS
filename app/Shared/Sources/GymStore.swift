import Foundation

/// Sleep that Health measured (a watch, a ring, the phone), by local day.
/// Written when the check-in reads Health; read by readiness and the gym
/// advisor, which trust it more than a guess.
enum MeasuredSleepStore {
    private static let key = "sleep.measured"

    static func all() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    static func save(_ hours: Double, on date: Date = .now, calendar: Calendar = .current) {
        guard hours > 0, hours < 16 else { return }
        var values = all()
        values[DayKey.of(date, calendar: calendar)] = hours
        // Keep five weeks.
        if values.count > 35 {
            for old in values.keys.sorted().prefix(values.count - 35) { values.removeValue(forKey: old) }
        }
        UserDefaults.standard.set(values, forKey: key)
        // The twin's sleep widget says where the numbers come from.
        UserDefaults.standard.set(true, forKey: "sleep.fromHealth")
    }

    /// Last night and the average of the last three measured nights.
    static func recent(now: Date = .now, calendar: Calendar = .current) -> MeasuredSleep? {
        let values = all()
        guard !values.isEmpty else { return nil }
        let today = calendar.startOfDay(for: now)
        let lastNight = values[DayKey.of(today, calendar: calendar)]
        var nights: [Double] = []
        for back in 0..<3 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today), let hours = values[DayKey.of(day, calendar: calendar)] else { continue }
            nights.append(hours)
        }
        let average = nights.count >= 2 ? nights.reduce(0, +) / Double(nights.count) : nil
        guard lastNight != nil || average != nil else { return nil }
        return MeasuredSleep(lastNight: lastNight, average: average)
    }
}

/// What the athlete picked on the gym sheet, for one day: the focus (or
/// "you pick") and the length. The athlete's choice always wins; the advisor
/// only fills in what they left to AthleteOS.
enum GymChoiceStore {
    private static let key = "gym.choice"
    private static let lengthKey = "gym.lastLength"

    struct Choice: Equatable {
        var focus: GymFocus
        var length: GymLength?
    }

    static func choice(on date: Date, calendar: Calendar = .current) -> Choice? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        let parts = raw.split(separator: "|").map(String.init)
        guard parts.count >= 2, parts[0] == DayKey.of(date, calendar: calendar), let focus = GymFocus(rawValue: parts[1]) else { return nil }
        let length = parts.count >= 3 ? Int(parts[2]).flatMap(GymLength.init(rawValue:)) : nil
        return Choice(focus: focus, length: length)
    }

    static func save(_ choice: Choice, on date: Date = .now, calendar: Calendar = .current) {
        var raw = "\(DayKey.of(date, calendar: calendar))|\(choice.focus.rawValue)"
        if let length = choice.length {
            raw += "|\(length.rawValue)"
            UserDefaults.standard.set(length.rawValue, forKey: lengthKey)
        }
        UserDefaults.standard.set(raw, forKey: key)
        NotificationCenter.default.post(name: WeeklyPlan.inputsChanged, object: nil)
    }

    /// The length the athlete picked last time (nil: never picked).
    static var lastLength: GymLength? {
        let raw = UserDefaults.standard.integer(forKey: lengthKey)
        return raw == 0 ? nil : GymLength(rawValue: raw)
    }

    /// For the session cache.
    static func fingerprint(on date: Date, calendar: Calendar = .current) -> String {
        guard let choice = choice(on: date, calendar: calendar) else { return "auto" }
        return "\(choice.focus.rawValue)\(choice.length?.rawValue ?? 0)"
    }
}

/// The athlete's own history, as the gym advisor reads it: when each region
/// last lifted, what stalled, what the last sessions' accessories were.
@MainActor
enum GymHistoryBuilder {
    private static var cache: (key: String, history: GymHistory)?

    static func history(_ athlete: Athlete, catalogue: Catalogue, now: Date = .now, calendar: Calendar = .current) -> GymHistory {
        let today = calendar.startOfDay(for: now)
        // Today's own sessions count: a session finished this morning makes that region "trained today".
        let key = "\(DayKey.of(now, calendar: calendar))|\(athlete.sessions.count)|\(athlete.sessions.reduce(0) { $0 + $1.sets.count })|\(catalogue.itemsBySlug.count)|\(MeasuredSleepStore.all().count)|\(HealthWorkoutInbox.revision)"
        if let cache, cache.key == key { return cache.history }
        let twoWeeks = calendar.date(byAdding: .day, value: -14, to: today) ?? today.addingTimeInterval(-14 * 86_400)
        let sixWeeks = calendar.date(byAdding: .day, value: -42, to: today) ?? today.addingTimeInterval(-42 * 86_400)
        var daysSince: [GymRegion: Int] = [:]
        var weekCount: [GymRegion: Int] = [:]
        // Best estimated strength per lift, per session, oldest first.
        var bests: [String: [Double]] = [:]
        var regionOf: [String: GymRegion] = [:]
        // The days a region wants after its newest session: set by a Health
        // workout the athlete rated, the usual rule after a logged one.
        var recoveryOverride: [GymRegion: Int] = [:]
        let sessions = athlete.sessions.filter { $0.startedAt >= sixWeeks }.sorted { $0.startedAt < $1.startedAt }
        for session in sessions {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: session.startedAt), to: today).day ?? 99
            var regions: Set<GymRegion> = []
            var perLift: [String: Double] = [:]
            for set in session.sets {
                guard let item = catalogue.item(set.itemSlug) else { continue }
                let p = item.planProfile
                let strength = p.role == "primary" || p.role == "secondary"
                if strength, p.isLower { regions.insert(.lower) }
                if strength, p.isUpper, !p.isLower { regions.insert(.upper) }
                if p.role == "trunk" { regions.insert(.core) }
                guard strength, set.setIndex >= 0 else { continue }
                let reps = Double(set.reps ?? 0)
                let value = (set.weightKg ?? 0) > 0 ? (set.weightKg ?? 0) * (1 + reps / 30) : reps
                guard value > 0 else { continue }
                perLift[set.itemSlug] = max(perLift[set.itemSlug] ?? 0, value)
                regionOf[set.itemSlug] = p.isLower ? .lower : .upper
            }
            for (slug, value) in perLift { bests[slug, default: []].append(value) }
            // A workout from Health: the regions the athlete said it trained.
            let rated = HealthWorkoutInbox.regions(of: session)
            regions.formUnion(rated.keys)
            for region in regions { recoveryOverride[region] = rated[region] }
            guard session.startedAt >= twoWeeks else { continue }
            for region in regions {
                daysSince[region] = min(daysSince[region] ?? 99, days)
                if days <= 7 { weekCount[region, default: 0] += 1 }
            }
        }
        // Stalled: four or more sessions of a lift, and the last three never beat the best before them.
        var stalled: Set<String> = []
        for (slug, values) in bests where values.count >= 4 {
            let before = values.dropLast(3).max() ?? 0
            let recent = values.suffix(3).max() ?? 0
            if recent <= before { stalled.insert(slug) }
        }
        let lastTwo = athlete.sessions.filter { $0.startedAt < now }.sorted { $0.startedAt > $1.startedAt }.prefix(2)
        let recentSlugs = Set(lastTwo.flatMap { $0.sets.map(\.itemSlug) })
        var lastAccessories: [GymFocus: Set<String>] = [:]
        for focus in GymFocus.choices { lastAccessories[focus] = recentSlugs }
        let sleep = MeasuredSleepStore.recent(now: now, calendar: calendar)
        let history = GymHistory(daysSince: daysSince, weekCount: weekCount, stalledAnchors: stalled,
                                 stalledRegions: Set(stalled.compactMap { regionOf[$0] }), lastAccessories: lastAccessories,
                                 measuredSleepHours: sleep?.lastNight, measuredSleepAverage: sleep?.average,
                                 recoveryOverride: recoveryOverride.compactMapValues { $0 })
        cache = (key, history)
        return history
    }

    /// Today's gym request: the athlete's pick when they made one, the
    /// advisor's otherwise.
    static func request(_ athlete: Athlete, day: TrainingDay, catalogue: Catalogue, calendar: Calendar = .current) -> (GymRequest, GymAdvice) {
        let history = self.history(athlete, catalogue: catalogue, now: calendar.isDateInToday(day.date) ? .now : day.date, calendar: calendar)
        let advice = GymAdvisor.advise(day: day, history: history)
        let choice = GymChoiceStore.choice(on: day.date, calendar: calendar)
        let focus = choice.map { $0.focus == .auto ? advice.focus : $0.focus } ?? advice.focus
        let length = choice?.length ?? GymChoiceStore.lastLength ?? advice.length
        let note: String? = focus == advice.focus ? advice.reason : nil
        let request = GymRequest(focus: focus, length: length,
                                 anchorSeed: "\(athlete.id)|\(GymRequest.block(for: day.date))",
                                 stalledAnchors: history.stalledAnchors,
                                 lastAccessories: history.lastAccessories[focus] ?? [], note: note)
        return (request, advice)
    }
}
