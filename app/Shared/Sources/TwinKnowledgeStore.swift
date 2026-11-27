import Foundation

/// Gathers what "What I know about you" reads (`TwinKnowledgeEngine`) from
/// the athlete's own data on the phone, keeps the athlete's corrections (T13)
/// and when each line was first known (the monthly letter), all inside the
/// twin's sealed state — "Delete twin" deletes them too.
@MainActor
enum TwinKnowledgeStore {
    private static var cache: (key: String, knowledge: TwinKnowledge)?

    /// The portrait for today, built at most once per change of the data.
    static func current(_ athlete: Athlete, state: AcademyState = AcademyStore.load(), now: Date = .now,
                        calendar: Calendar = .current) -> TwinKnowledge {
        // Counts alone miss edits (a changed rating, a check-in answered
        // again, a 60-day pain list that only rolls): a cheap fingerprint of
        // each source's content instead.
        let results = CompetitionStore.results().values.map { "\($0.id)\($0.rating)" }.sorted().joined()
        let pains = PainStore.all().map { "\($0.day)\($0.areas.map(\.rawValue).joined())" }.joined()
        let practices = PracticeLogStore.logs.map { "\($0.day)\($0.hard)\($0.saidWent)" }.joined()
        let mornings = athlete.checkIns.map { "\($0.date.timeIntervalSince1970)\($0.soreness)\($0.energy)\($0.sleepHours ?? 0)" }.joined()
            + OneTapCheckIns.days.joined()
        let efforts = athlete.sessions.reduce(0) { $0 + ($1.sessionRPE ?? 0) }
        let key = [DayKey.of(now, calendar: calendar), "\(mornings.hashValue)", "\(athlete.sessions.count)", "\(efforts)",
                   "\(athlete.competitions.count)", "\(results.hashValue)", "\(pains.hashValue)",
                   "\(practices.hashValue)", "\(HealthWorkoutInbox.revision)", "\(AthleteContextStore.revision)",
                   "\(HeartStore.resting.count)\(HeartStore.resting.last?.value ?? 0)"].joined(separator: "|")
        if let cache, cache.key == key { return cache.knowledge }
        let knowledge = TwinKnowledgeEngine.build(input(athlete, state: state, now: now, calendar: calendar), calendar: calendar)
        cache = (key, knowledge)
        return knowledge
    }

    static func input(_ athlete: Athlete, state: AcademyState, now: Date, calendar: Calendar) -> KnowledgeInput {
        let base = TwinInputBuilder.input(athlete: athlete, state: state, now: now, calendar: calendar)
        // The athlete's own rating of their game, never the result (research §1).
        let results = CompetitionStore.results()
        let rated = athlete.competitions.compactMap { game -> KnowledgeInput.RatedGame? in
            guard game.date < now, let result = results[game.id], (1...5).contains(result.rating) else { return nil }
            return KnowledgeInput.RatedGame(date: game.date, rating: result.rating)
        }
        let pains = PainStore.all().compactMap { report -> KnowledgeInput.Pain? in
            guard let day = TwinInputBuilder.day(report.day, calendar: calendar) else { return nil }
            return KnowledgeInput.Pain(date: day, areas: report.areas.map(\.rawValue))
        }
        return KnowledgeInput(base: base, ratedGames: rated, pains: pains, efforts: legEfforts(athlete),
                              excludedDays: excludedDays(now: now, calendar: calendar), restingHeart: HeartStore.resting)
    }

    /// How hard each session worked the legs (CR-10): the athlete's own
    /// answer for a workout from Health or told, else a logged gym session's
    /// effort when it had leg strength work.
    static func legEfforts(_ athlete: Athlete) -> [KnowledgeInput.RegionEffort] {
        let catalogue = CatalogueLoader.load(from: AppConfig.packsDirectory())
        return athlete.sessions.compactMap { session -> KnowledgeInput.RegionEffort? in
            if let answer = HealthWorkoutInbox.answer(for: session) {
                guard let band = WorkoutTagging.effectiveBands(answer, minutes: session.minutes)[.lower] else { return nil }
                let effort = band == .veryHard ? max(7, answer.rating ?? 7) : band == .solid ? 5 : 2
                return KnowledgeInput.RegionEffort(date: session.startedAt, region: "legs", effort: effort)
            }
            guard let rpe = session.sessionRPE else { return nil }
            let legs = session.sets.contains { set in
                guard let profile = catalogue.item(set.itemSlug)?.planProfile else { return false }
                return profile.isLower && (profile.role == "primary" || profile.role == "secondary")
            }
            return legs ? KnowledgeInput.RegionEffort(date: session.startedAt, region: "legs", effort: rpe) : nil
        }
    }

    /// Sick, travel and exam days of the last four months: they shorten sleep
    /// and lower practice alike, so the sleep comparisons leave them out.
    static func excludedDays(now: Date, calendar: Calendar) -> Set<Date> {
        let today = calendar.startOfDay(for: now)
        var days: Set<Date> = []
        var examWeeks: [Date: Bool] = [:]
        for back in 0..<120 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            let status = DayStatusStore.status(on: day, calendar: calendar)
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
            // One look per week: the imported calendar is read once per week, not per day.
            let exam = examWeeks[weekStart] ?? ScheduleStore.isExamWeek(weekStart, calendar: calendar)
            examWeeks[weekStart] = exam
            if status == .sick || status == .travel || status == .concussion || exam { days.insert(day) }
        }
        return days
    }

    // MARK: Corrections and the monthly letter

    /// The leg recovery the planner may use: not when the athlete said that
    /// line wasn't right (T13 — never ignore what they told us).
    static func legRecoveryDays(_ athlete: Athlete, now: Date = .now, calendar: Calendar = .current) -> Int? {
        let state = AcademyStore.load()
        guard state.knowledgeHidden?["body.legs"] == nil else { return nil }
        return current(athlete, state: state, now: now, calendar: calendar).legRecoveryDays
    }

    /// What the twin changes in the plan right now, worked out once for
    /// every screen (the Twin page, Home's Body tile): only what the planner
    /// really does — the gym planner's leg rest, the session planner's steers.
    static func planEffects(_ athlete: Athlete, history: GymHistory?, now: Date = .now, calendar: Calendar = .current) -> [TwinPlanEffect] {
        let state = AcademyStore.load()
        let legDays = state.knowledgeHidden?["body.legs"] == nil ? current(athlete, state: state, now: now, calendar: calendar).legRecoveryDays : nil
        let event = AcademyContent.family(forSport: athlete.activeSport?.sportSlug).event
        return TwinPage.effects(legRecoveryDays: legDays, legsReadyIn: legDays == nil ? nil : history?.legsHeldByTwin,
                                steers: TodayEngine.twinSteers(athlete, date: now, calendar: calendar),
                                games: athlete.competitions.map(\.date), event: event, now: now, calendar: calendar)
    }

    /// Lines the athlete hasn't said were wrong.
    static func visible(_ knowledge: TwinKnowledge, state: AcademyState) -> [KnowledgeLine] {
        let hidden = state.knowledgeHidden ?? [:]
        return knowledge.lines.filter { hidden[$0.id] == nil || $0.safety }
    }

    /// "That's not right": the line goes and stays gone (pain lines can't be
    /// hidden — showing it to someone is the safety rule, T9).
    static func hide(_ id: String, now: Date = .now) {
        var state = AcademyStore.load()
        var hidden = state.knowledgeHidden ?? [:]
        hidden[id] = now
        state.knowledgeHidden = hidden
        AcademyStore.save(state)
    }

    /// Bring back every hidden line.
    static func showHidden() {
        var state = AcademyStore.load()
        state.knowledgeHidden = nil
        AcademyStore.save(state)
    }

    /// Notes when lines were first known; returns the updated state. The
    /// very first time, everything already known counts as known from
    /// before — so the first letter doesn't call months of data "new".
    @discardableResult
    static func noteFirstSeen(_ lines: [KnowledgeLine], now: Date = .now) -> AcademyState {
        var state = AcademyStore.load()
        let baseline = state.knowledgeFirstSeen == nil
        var seen = state.knowledgeFirstSeen ?? [:]
        var changed = baseline
        for line in lines where seen[line.id] == nil {
            seen[line.id] = baseline ? .distantPast : now
            changed = true
        }
        if changed {
            state.knowledgeFirstSeen = seen
            AcademyStore.save(state)
        }
        return state
    }

    /// Last month's letter (T15), shown in the first ten days of a month:
    /// what the twin learned that month, what it's still unsure about.
    static func letter(_ knowledge: TwinKnowledge, state: AcademyState, now: Date = .now, calendar: Calendar = .current) -> TwinLetter? {
        guard calendar.component(.day, from: now) <= 10,
              let thisMonth = calendar.dateInterval(of: .month, for: now),
              let last = calendar.dateInterval(of: .month, for: thisMonth.start.addingTimeInterval(-1)) else { return nil }
        let monthKey = DayKey.of(last.start, calendar: calendar).prefix(7)
        guard state.letterClosed != String(monthKey) else { return nil }
        let seen = state.knowledgeFirstSeen ?? [:]
        let learned = visible(knowledge, state: state).filter { seen[$0.id].map { last.contains($0) } ?? false }
        guard !learned.isEmpty || !knowledge.learning.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM"
        return TwinLetter(month: String(monthKey), monthName: formatter.string(from: last.start),
                          learned: learned, unsure: Array(knowledge.learning.prefix(3)))
    }

    static func closeLetter(_ month: String) {
        var state = AcademyStore.load()
        state.letterClosed = month
        AcademyStore.save(state)
    }
}

struct TwinLetter: Equatable {
    let month: String
    let monthName: String
    let learned: [KnowledgeLine]
    let unsure: [LearningItem]
}
