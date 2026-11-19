import Foundation

/// The app side of the V6 workout engine: turns the athlete's real day —
/// sport, season, schedule, games, check-in, pain, last night's reflection,
/// the last week of training — into a TrainingDay, and asks the engine.
/// Everything the engine decides it decides here; the old patch-up layers
/// (readiness, taper, exam lightening) don't touch its sessions again.
@MainActor
enum TodayEngine {
    /// Whether the downloaded packs carry exercise profiles (V6 content).
    static func isAvailable(_ catalogue: Catalogue) -> Bool {
        catalogue.itemsBySlug.values.first?.profile != nil || catalogue.itemsBySlug.values.contains { $0.profile != nil }
    }

    static func goals() -> [Capacity] {
        var out: [Capacity] = []
        for struggle in Struggles.selected {
            let capacity: Capacity?
            switch struggle {
            case .acceleration: capacity = .acceleration
            case .maxSpeed: capacity = .speed
            case .agility: capacity = .coordination
            case .strength, .relativeStrength: capacity = .strength
            case .power, .verticalJump: capacity = .power
            case .conditioning: capacity = .repeatedEffort
            case .aerobicFitness: capacity = .aerobic
            case .mobility: capacity = .mobility
            case .movementQuality: capacity = .balance
            default: capacity = nil
            }
            if let capacity, !out.contains(capacity) { out.append(capacity) }
        }
        return out
    }

    static func practiceIntensity(on date: Date, calendar: Calendar = .current) -> PracticeIntensity? {
        // The athlete's own word on the day ("What's on today?") wins over the schedule.
        let said = DayChoiceStore.answer(on: date, calendar: calendar).flatMap { $0.isAuto ? nil : $0 }
        if let said {
            guard said.choices.contains(.practice) else { return nil }
        } else {
            guard PracticeSchedule.hasPractice(on: date, calendar: calendar) else { return nil }
        }
        // That evening's reflection says how hard it was, when there is one;
        // before it, how hard the athlete said it would be.
        switch MindsetStore.reflection(on: date, calendar: calendar)?.hardness {
        case 3?, 4?: return .hard
        case 1?: return .light
        default: return said?.practice ?? .normal
        }
    }

    /// The athlete's answer for that day, when they decided (nil: left to AthleteOS).
    static func said(on date: Date, calendar: Calendar = .current) -> DayAnswer? {
        DayChoiceStore.answer(on: date, calendar: calendar).flatMap { $0.isAuto ? nil : $0 }
    }

    /// A game that day: the athlete's word first, then the competitions.
    static func gameOn(_ athlete: Athlete, date: Date, calendar: Calendar = .current) -> Bool {
        if let answer = Self.said(on: date, calendar: calendar) { return answer.choices.contains(.game) }
        return athlete.competitions.contains { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// What a logged session trained, from its exercises' profiles.
    static func load(of session: Session, daysAgo: Int, catalogue: Catalogue) -> DayLoad {
        var capacities: [Capacity] = []
        var lower: String?
        var upper: String?
        var heavyLower = false
        var conditioningSeconds = 0
        let slugs = Array(Set(session.sets.map(\.itemSlug)))
        for slug in slugs {
            guard let item = catalogue.item(slug) else { continue }
            let p = item.planProfile
            if let top = item.qualities.max(by: { $0.value < $1.value }), top.value >= 0.7, let c = Capacity.fromQuality[top.key], !capacities.contains(c) {
                capacities.append(c)
            }
            if p.role == "primary" || p.role == "secondary" {
                if p.isLower, lower == nil { lower = ["hinge"].contains(p.pattern) ? "hinge" : "squat" }
                if p.isUpper, !p.isLower, upper == nil, ["push", "pull"].contains(p.pattern) { upper = p.pattern }
            }
            if p.isLower, p.fatigue >= 4 { heavyLower = true }
            if p.role == "conditioning" {
                conditioningSeconds += session.sets.filter { $0.itemSlug == slug }.reduce(0) { $0 + ($1.seconds ?? 30) }
            }
        }
        // A workout from Apple Health with no exercises (a run, a ride) is conditioning.
        if slugs.isEmpty { conditioningSeconds = session.minutes * 60; capacities = [.aerobic] }
        return DayLoad(daysAgo: daysAgo, capacities: capacities, lowerPattern: lower, upperPattern: upper, heavyLower: heavyLower,
                       conditioningMinutes: conditioningSeconds / 60,
                       sessionType: slugs.count >= 6 ? .gymDevelopment : slugs.isEmpty ? .conditioning : .afterPractice)
    }

    static func recentLoad(_ athlete: Athlete, sessions: [Session], catalogue: Catalogue, before date: Date,
                           calendar: Calendar = .current) -> RecentLoad {
        let today = calendar.startOfDay(for: date)
        var days: [DayLoad] = []
        for daysAgo in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            var load = DayLoad(daysAgo: daysAgo, practice: practiceIntensity(on: day, calendar: calendar),
                               game: gameOn(athlete, date: day, calendar: calendar))
            for session in sessions where calendar.isDate(session.startedAt, inSameDayAs: day) {
                let logged = self.load(of: session, daysAgo: daysAgo, catalogue: catalogue)
                load.capacities = Array(Set(load.capacities + logged.capacities)).sorted { $0.rawValue < $1.rawValue }
                load.lowerPattern = load.lowerPattern ?? logged.lowerPattern
                load.upperPattern = load.upperPattern ?? logged.upperPattern
                load.heavyLower = load.heavyLower || logged.heavyLower
                load.conditioningMinutes += logged.conditioningMinutes
                load.sessionType = load.sessionType ?? logged.sessionType
            }
            days.append(load)
        }
        return RecentLoad(days: days)
    }

    /// Today (or another day this week) as the engine sees it.
    static func trainingDay(_ athlete: Athlete, sessions: [Session], catalogue: Catalogue, date: Date = .now,
                            plannedGymDay: Bool, calendar: Calendar = .current) -> TrainingDay? {
        guard let active = athlete.activeSport else { return nil }
        let sport = catalogue.sportsBySlug[active.sportSlug] ?? allSportsBySlug[active.sportSlug]
        let isToday = calendar.isDateInToday(date)
        let day = calendar.startOfDay(for: date)
        let games = athlete.competitions.map { calendar.startOfDay(for: $0.date) }
        let next = games.filter { $0 > day }.min().flatMap { calendar.dateComponents([.day], from: day, to: $0).day }
        let last = games.filter { $0 < day }.max().flatMap { calendar.dateComponents([.day], from: $0, to: day).day }

        var readiness: ReadinessLevel = .normal
        var soreLegs = false
        var pain: Set<PainArea> = []
        var reflection: ReflectionSignal?
        if isToday {
            // "Train as planned instead" chosen today: full readiness (pain
            // and illness are still handled on their own).
            if !ReadinessOverride.isOn(date, calendar: calendar) {
                switch DailyLoop.today(athlete)?.level {
                case .recovery?: readiness = .low
                case .reduced?: readiness = .belowNormal
                default: readiness = .normal
                }
            }
            if let checkIn = AthleteStats.todaysCheckIn(athlete) { soreLegs = checkIn.soreness >= 5 }
            pain = TodaysPain.areas(now: date)
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: day), let last = MindsetStore.reflection(on: yesterday, calendar: calendar) {
                reflection = ReflectionSignal(dayFelt: last.hardness, bodyFelt: last.body)
            }
        }
        // Days in a row with practice, a game or a workout, up to yesterday.
        var inARow = 0
        for back in 1...10 {
            guard let d = calendar.date(byAdding: .day, value: -back, to: day) else { break }
            let busy = PracticeSchedule.hasPractice(on: d, calendar: calendar) || games.contains(d)
                || sessions.contains { calendar.isDate($0.startedAt, inSameDayAs: d) }
            if busy { inARow += 1 } else { break }
        }
        let status = isToday ? DayStatusStore.status() : .active
        let said = Self.said(on: date, calendar: calendar)
        let gameToday = said.map { $0.choices.contains(.game) } ?? games.contains(day)
        let moment = PrepMoment.at(date, gameToday: gameToday)
        let custom = PlanCustomizationStore.load()
        return TrainingDay(
            date: date,
            phase: PhaseCalculator.phase(today: date, seasonStart: active.seasonStart, seasonEnd: active.seasonEnd),
            age: PlanGenerator.ageInYears(birthDate: athlete.birthDate, now: date),
            experience: TrainingExperience.current,
            demands: SportDemandsTable.demands(sport: sport, position: active.positionSlug),
            goals: goals(),
            practice: practiceIntensity(on: date, calendar: calendar).map { isToday || said != nil ? $0 : .normal },
            gameToday: gameToday,
            daysToNextGame: next,
            daysSinceLastGame: last,
            readiness: readiness,
            soreLegs: soreLegs,
            painAreas: pain,
            illnessReturnDay: isToday ? IllnessReturn.day(on: date, calendar: calendar) : nil,
            examOrLongDay: ScheduleStore.isExamWeek(date, calendar: calendar) || SchoolHours.isLongDay(date, calendar: calendar),
            daysTrainedInARow: inARow,
            availableMinutes: custom.settings.effectiveMinutesPerSession,
            recent: recentLoad(athlete, sessions: sessions, catalogue: catalogue, before: date, calendar: calendar),
            reflection: reflection,
            plannedGymDay: plannedGymDay,
            travelling: status == .travel || status == .holiday,
            beforeSession: moment == .beforePractice,
            evening: moment == .evening,
            twin: twinSteers(athlete, date: date, calendar: calendar),
            said: said?.engineChoices ?? []
        )
    }

    /// What the athlete's twin has found that changes training (TwinSteer):
    /// the same analysis the Academy shows, read by the planner. It describes
    /// the athlete, not the date, so it is worked out once per day (and per
    /// change in the data it reads) and every day of the week reuses it.
    private static var twinCache: (key: String, steers: Set<TwinSteer>)?

    static func twinSteers(_ athlete: Athlete, date: Date, calendar: Calendar = .current) -> Set<TwinSteer> {
        let now = Date.now
        let todayStart = calendar.startOfDay(for: now)
        // Sessions before today only: today's own workout doesn't reshape itself.
        let earlier = athlete.sessions.filter { $0.startedAt < todayStart }.count
        let games = athlete.competitions.map { DayKey.of($0.date, calendar: calendar) }.sorted().joined(separator: ",")
        let key = [DayKey.of(now, calendar: calendar), "\(earlier)", "\(athlete.checkIns.count)", games,
                   "\(MindsetStore.reflections.count)", "\(PracticeLogStore.logs.count)", "\(BenchmarkStore.results.count)"].joined(separator: "|")
        if let twinCache, twinCache.key == key { return twinCache.steers }
        let input = TwinInputBuilder.input(athlete: athlete, state: AcademyStore.load(), now: now, calendar: calendar)
        let steers = TwinSteer.from(TwinAnalysis.report(input, calendar: calendar).insights.map(\.kind))
        twinCache = (key, steers)
        return steers
    }

    static func kit(_ athlete: Athlete, catalogue: Catalogue, date: Date, recent: RecentLoad, calendar: Calendar = .current) -> AthleteKit {
        let active = athlete.activeSport
        let sport = active.flatMap { catalogue.sportsBySlug[$0.sportSlug] ?? allSportsBySlug[$0.sportSlug] }
        let age = PlanGenerator.ageInYears(birthDate: athlete.birthDate, now: date)
        // The athlete's own calendar day: the same picks all day long, and the
        // same session whether it is asked for at 07:00 or at 23:00.
        let day = DayKey.of(date, calendar: calendar)
        // The 7 days before today: jumps already landed come off the weekly cap,
        // and yesterday's exercises step back so sessions vary. Today's own
        // sessions don't count, so the workout doesn't change once it's started.
        let dayStart = calendar.startOfDay(for: date)
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: dayStart) ?? dayStart.addingTimeInterval(-7 * 86_400)
        let dayAgo = calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart.addingTimeInterval(-86_400)
        var landed = 0
        var recentSlugs: Set<String> = []
        for session in athlete.sessions where session.startedAt >= weekAgo && session.startedAt < dayStart {
            for set in session.sets {
                if session.startedAt >= dayAgo { recentSlugs.insert(set.itemSlug) }
                guard let group = catalogue.item(set.itemSlug)?.planProfile.group, group.hasPrefix("jump") else { continue }
                landed += set.contacts ?? set.reps ?? 0
            }
        }
        let cap = TrainingExperience.current.contactCap(PlanGenerator.weeklyContactCap(age: age))
        // Equipment: on the road only what needs none.
        let travelling = DayStatusStore.status(on: date) == .travel || DayStatusStore.status(on: date) == .holiday
        return AthleteKit(catalogue: catalogue, sport: sport, positionSlug: active?.positionSlug, formatSlug: active?.formatSlug,
                          equipment: travelling ? ["none"] : Set(athlete.equipmentAvailable), trainsUnderCoach: athlete.trainsUnderCoach,
                          avoidSlugs: recentSlugs, contactsLeft: max(0, cap - landed),
                          seed: PlanVariant.seed("\(athlete.id)-\(day)"))
    }

    /// The session the engine builds for `type` on `date` (nil: rest, or
    /// no V6 content yet). `requested` is what the athlete opened.
    /// Built sessions, by everything they depend on: a screen asks for the
    /// same session many times per render, and a build isn't free.
    private static var cache: [String: (at: Date, session: GeneratedSession?)] = [:]

    private static func fingerprint(_ requested: SessionType?, athlete: Athlete, sessions: [Session], catalogue: Catalogue,
                                    date: Date, plannedGymDay: Bool, calendar: Calendar = .current) -> String {
        let checkIn = AthleteStats.todaysCheckIn(athlete)
        let answers = checkIn.map { "\($0.sleepQuality),\($0.sleepHours ?? -1),\($0.soreness),\($0.energy),\($0.stress)" } ?? "none"
        return [requested?.rawValue ?? "auto", "\(plannedGymDay)", DayKey.of(date, calendar: calendar),
                "\(catalogue.itemsBySlug.count)", answers, "\(sessions.count)", "\(athlete.competitions.count)",
                DayStatusStore.status().rawValue, "\(ReadinessOverride.isOn(date, calendar: calendar))", TodaysPain.areas().map(\.rawValue).sorted().joined(),
                Struggles.selected.map(\.rawValue).joined(), TrainingExperience.current.rawValue,
                "\(PracticeSchedule.hasPractice(on: date, calendar: calendar))",
                DayChoiceStore.answer(on: date, calendar: calendar)?.encoded ?? "auto",
                "\(MindsetStore.reflections.first?.day ?? "")\(MindsetStore.reflections.first?.hardness ?? 0)\(MindsetStore.reflections.first?.body ?? 0)",
                athlete.activeSport.map { "\($0.sportSlug)\($0.positionSlug ?? "")\($0.seasonStart.timeIntervalSince1970)\($0.seasonEnd.timeIntervalSince1970)\(PreSeasonStore.start?.timeIntervalSince1970 ?? 0)" } ?? "",
                athlete.equipmentAvailable.sorted().joined(), "\(PlanVariant.current)",
                twinSteers(athlete, date: date, calendar: calendar).map(\.rawValue).sorted().joined()].joined(separator: "|")
    }

    static func session(_ requested: SessionType?, athlete: Athlete, sessions: [Session], catalogue: Catalogue,
                        date: Date = .now, plannedGymDay: Bool) -> GeneratedSession? {
        let key = fingerprint(requested, athlete: athlete, sessions: sessions, catalogue: catalogue, date: date, plannedGymDay: plannedGymDay)
        if let hit = cache[key], Date.now.timeIntervalSince(hit.at) < 120 { return hit.session }
        let built = build(requested, athlete: athlete, sessions: sessions, catalogue: catalogue, date: date, plannedGymDay: plannedGymDay)
        if cache.count > 40 { cache.removeAll() }
        cache[key] = (.now, built)
        return built
    }

    private static func build(_ requested: SessionType?, athlete: Athlete, sessions: [Session], catalogue: Catalogue,
                              date: Date, plannedGymDay: Bool) -> GeneratedSession? {
        guard isAvailable(catalogue),
              let day = trainingDay(athlete, sessions: sessions, catalogue: catalogue, date: date, plannedGymDay: plannedGymDay) else { return nil }
        let decision = SessionPlanner.decide(day, requested: requested)
        guard decision.sessionType != .rest else { return nil }
        var session = SessionBuilder.build(decision, day: day, kit: kit(athlete, catalogue: catalogue, date: date, recent: day.recent))
        session.slot = nil
        return session.items.isEmpty ? nil : session
    }

    /// Today's decision on its own (for Home's "why" and rest days).
    static func decision(athlete: Athlete, sessions: [Session], catalogue: Catalogue, plannedGymDay: Bool) -> (SessionDecision, TrainingDay)? {
        guard let day = trainingDay(athlete, sessions: sessions, catalogue: catalogue, plannedGymDay: plannedGymDay) else { return nil }
        return (SessionPlanner.decide(day), day)
    }

    /// The athlete's own version of a workout wins; then the engine; then the old builder.
    static func workout(_ mode: WorkoutMode, athlete: Athlete, sessions: [Session], catalogue: Catalogue,
                        context: WorkoutModeContext, plannedGymDay: Bool) -> GeneratedSession? {
        if let mine = PlanCustomizationStore.load().workout(for: .mode(mode)), !mine.items.isEmpty {
            return mine.session(date: .now, catalogue: catalogue)
        }
        let type: SessionType
        switch mode {
        case .afterPractice: type = .afterPractice
        case .gymDay: type = .gymDevelopment
        case .mobility: type = .mobility
        case .travel: type = .travel
        }
        if let built = session(type, athlete: athlete, sessions: sessions, catalogue: catalogue, plannedGymDay: plannedGymDay) {
            return built
        }
        return isAvailable(catalogue) ? nil : WorkoutModeBuilder.build(mode, context)
    }

    /// A workout (mobility on its own doesn't count) finished today — the
    /// same test as Home's "Training done", for the Watch and the widgets.
    static func workoutDone(_ athlete: Athlete, calendar: Calendar = .current) -> Bool {
        athlete.sessions.contains {
            calendar.isDateInToday($0.startedAt) && $0.endedAt != nil && SessionKinds.kind(of: $0.clientId) != .mobility
        }
    }

    /// Today's main workout, the way Home picks it — for the Watch and the
    /// widgets, so every screen shows the same session. Nil: rest or no plan.
    static func todaysWorkout(athlete: Athlete, week: GeneratedWeek?, catalogue: Catalogue, calendar: Calendar = .current) -> GeneratedSession? {
        let status = DayStatusStore.status()
        let said = Self.said(on: .now, calendar: calendar)
        guard status != .sick, status != .concussion, !gameOn(athlete, date: .now, calendar: calendar),
              said?.choices.contains(.rest) != true else { return nil }
        // The same rules gate as Home (e.g. head pain: no added training on the Watch either).
        guard PlanningRules.today(athlete, sessions: athlete.sessions).decision.allowsAddedTraining else { return nil }
        let planned = week?.sessions.first { calendar.isDateInToday($0.date) }
        let sessions = athlete.sessions
        func old(_ session: GeneratedSession) -> GeneratedSession {
            let safe = TodaysPain.apply(session, athlete: athlete, catalogue: catalogue)
            guard let band = DailyLoop.todayBand(athlete) else { return safe }
            return ReadinessApplier.apply(to: safe, band: band).session
        }
        // The athlete's own version of a workout wins, as on Home (`workout(_:)`).
        func mine(_ mode: WorkoutMode) -> GeneratedSession? {
            guard let custom = PlanCustomizationStore.load().workout(for: .mode(mode)), !custom.items.isEmpty else { return nil }
            return custom.session(date: .now, catalogue: catalogue)
        }
        // "Something light" (and no gym): mobility, whatever else the day holds.
        if let said, said.choices.contains(.light), !said.choices.contains(.gym), isAvailable(catalogue) {
            if let custom = mine(.mobility) { return TodaysPain.apply(custom, athlete: athlete, catalogue: catalogue) }
            return session(.mobility, athlete: athlete, sessions: sessions, catalogue: catalogue, plannedGymDay: planned != nil)
        }
        if status == .travel || status == .holiday {
            if let custom = mine(.travel) { return TodaysPain.apply(custom, athlete: athlete, catalogue: catalogue) }
            return session(.travel, athlete: athlete, sessions: sessions, catalogue: catalogue, plannedGymDay: planned != nil)
        }
        if PracticeSchedule.hasPractice(on: .now, calendar: calendar) {
            if let custom = mine(.afterPractice) { return old(custom) }
            return session(.afterPractice, athlete: athlete, sessions: sessions, catalogue: catalogue, plannedGymDay: planned != nil)
                ?? (isAvailable(catalogue) ? nil : planned.map(old))
        }
        if let planned, let slot = planned.slot, PlanCustomizationStore.load().workout(for: .gym(slot)) != nil { return old(planned) }
        if isAvailable(catalogue) {
            return session(nil, athlete: athlete, sessions: sessions, catalogue: catalogue, plannedGymDay: planned != nil)
        }
        return planned.map(old)
    }
}
