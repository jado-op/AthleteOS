import Foundation
import SwiftData

/// Workouts from Apple Health become the athlete's own training (owner,
/// 2026-11-20: "I just did a workout, it shows in the app, but the app still
/// tells me to do another one"). Each counting workout is logged as a session
/// straight away, so Home and the Workout tab show training done; the next
/// time the app opens it asks how hard it was and what it trained
/// (`WorkoutCheckSheet`, rules in `WorkoutTagging`).
///
/// Stays on this phone like the rest of Health: imported sessions are never
/// pushed to the server (`syncedAt` is set when they are created).
@MainActor
enum HealthWorkoutInbox {
    private static let importedKey = "health.importedWorkouts"   // session clientId → Health workout UUID
    private static let answersKey = "health.workoutAnswers"      // session clientId → answer
    private static let skippedKey = "health.workoutSkipped"      // session clientIds not to ask about
    private static let removedKey = "health.workoutRemoved"      // Health UUIDs the athlete said weren't training

    // MARK: Store

    static var imported: [String: String] {
        get { (UserDefaults.standard.dictionary(forKey: importedKey) as? [String: String]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: importedKey) }
    }

    static var answers: [String: WorkoutTagging.Answer] {
        get {
            UserDefaults.standard.data(forKey: answersKey)
                .flatMap { try? JSONDecoder().decode([String: WorkoutTagging.Answer].self, from: $0) } ?? [:]
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: answersKey) }
    }

    private static var skipped: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: skippedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue.suffix(200)), forKey: skippedKey) }
    }

    private static let snoozedKey = "health.workoutSnoozed"     // session clientId → when "later" was tapped

    /// "Later": not asked again for a few hours (the next app open after that asks).
    private static var snoozed: [String: Date] {
        get { (UserDefaults.standard.dictionary(forKey: snoozedKey) as? [String: Date]) ?? [:] }
        set { UserDefaults.standard.set(newValue.filter { $0.value > Date.now.addingTimeInterval(-2 * 86_400) }, forKey: snoozedKey) }
    }

    private static var removed: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: removedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue.suffix(200)), forKey: removedKey) }
    }

    private static let revisionKey = "health.workoutRevision"

    /// Goes up whenever an answer is saved or a workout imported or removed
    /// (for caches keyed on it).
    static var revision: Int { UserDefaults.standard.integer(forKey: revisionKey) }

    private static func bump() { UserDefaults.standard.set(revision + 1, forKey: revisionKey) }

    static func isImported(_ session: Session) -> Bool { imported[session.clientId] != nil }

    static func answer(for session: Session) -> WorkoutTagging.Answer? { answers[session.clientId] }

    /// "Strength training · from your Apple Watch" → "Strength training".
    static func activity(of session: Session) -> String {
        (session.notes ?? "Workout").components(separatedBy: " · ").first ?? "Workout"
    }

    /// What an imported workout did to the body map: the picked exercises
    /// (each counted as a few sets, the effort the athlete gave its region),
    /// plus every ticked region no exercise covered. Before an answer, the
    /// activity's usual regions, counted light (a run lights the legs).
    static func bodyMapSets(_ session: Session, catalogue: Catalogue) -> [MuscleTraining.LoggedSet] {
        let activity = activity(of: session)
        let answer = answers[session.clientId] ?? WorkoutTagging.guessedAnswer(activity: activity)
        let bands = WorkoutTagging.trainedBands(answer)
        var covered: Set<GymRegion> = []
        var sets: [MuscleTraining.LoggedSet] = []
        for slug in Set(session.sets.map(\.itemSlug)).sorted() {
            guard let item = catalogue.item(slug) else { continue }
            let regions = WorkoutCheckSheet.regions(of: item)
            covered.formUnion(regions)
            let band = regions.compactMap { bands[$0] }.max() ?? answer.rating.map(WorkoutTagging.band(forRating:)) ?? .solid
            let set = MuscleTraining.LoggedSet(date: session.startedAt, exercise: item.name, muscles: item.muscles,
                                               effort: WorkoutTagging.effort(of: band))
            sets += Array(repeating: set, count: WorkoutTagging.bodyMapSets(band))
        }
        return sets + MuscleTraining.regionSets(date: session.startedAt, label: activity,
                                                bands: bands.filter { !covered.contains($0.key) })
    }

    // MARK: Told in Tell AthleteOS

    /// Marks a session the athlete told AthleteOS about (no Health workout yet).
    private static let toldPrefix = "told:"
    private static let toldKey = "health.toldWorkouts"           // session clientIds told in Tell AthleteOS

    private static var told: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: toldKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue.suffix(300)), forKey: toldKey) }
    }

    /// A workout the athlete told AthleteOS about ("chest, upper back and core, 1 h").
    static func isTold(_ session: Session) -> Bool { told.contains(session.clientId) }

    /// Logs a workout told in Tell AthleteOS as the athlete's own training, so
    /// it shows in Training History, Home's "Training done", the body map and
    /// the gym planner — like a workout from Health, already answered with what
    /// they said (never asked again). Told twice for one day: one workout, merged.
    /// Minutes only when they said them; nothing is invented.
    @discardableResult
    static func logTold(day: Date, names: [String], patterns: [String], qualities: [String], level: Int, minutes: Int?,
                        athlete: Athlete, context: ModelContext, now: Date = .now, calendar: Calendar = .current) -> Session {
        var regions: [GymRegion: WorkoutTagging.Band] = [:]
        let band: WorkoutTagging.Band = level >= 3 ? .veryHard : level <= 1 ? .light : .solid
        if patterns.contains(where: { ["push", "pull"].contains($0) }) || qualities.contains("upperStrength") { regions[.upper] = band }
        if patterns.contains(where: { ["squat", "hinge", "lunge"].contains($0) }) || qualities.contains("lowerStrength") { regions[.lower] = band }
        if patterns.contains("core") || qualities.contains("core") { regions[.core] = band }
        let cardio = qualities.contains("conditioning")
        let rating = level >= 3 ? 8 : level <= 1 ? 3 : 5
        let isToday = calendar.isDate(day, inSameDayAs: now)
        let toldSet = told
        var answersMap = answers
        var map = imported

        // The watch already brought this workout in and it isn't answered yet: what
        // they told is its answer (no second session, and the check doesn't ask).
        if let health = athlete.sessions.first(where: { map[$0.clientId] != nil && !toldSet.contains($0.clientId) && answersMap[$0.clientId] == nil
                                                        && calendar.isDate($0.startedAt, inSameDayAs: day) }) {
            answersMap[health.clientId] = WorkoutTagging.Answer(rating: rating, regions: regions, cardio: cardio)
            answers = answersMap
            health.sessionRPE = rating
            if !regions.isEmpty { SessionKinds.record(health.clientId, .gym) }
            bump()
            try? context.save()
            return health
        }

        // The same day told again: the one workout grows instead of a second appearing.
        if let existing = athlete.sessions.first(where: { toldSet.contains($0.clientId) && calendar.isDate($0.startedAt, inSameDayAs: day) }) {
            var answer = answersMap[existing.clientId] ?? WorkoutTagging.Answer()
            var bands = answer.bands
            for (region, value) in regions { bands[region] = max(bands[region] ?? value, value) }
            answer = WorkoutTagging.Answer(rating: max(answer.rating ?? rating, rating), regions: bands, cardio: answer.cardio || cardio,
                                           hurt: answer.hurt, exercises: answer.exercises)
            answersMap[existing.clientId] = answer
            answers = answersMap
            if let minutes, minutes > 0, existing.healthKitWorkoutId == nil {
                existing.minutes = minutes
                existing.startedAt = (existing.endedAt ?? existing.startedAt).addingTimeInterval(-Double(minutes) * 60)
            }
            existing.sessionRPE = answer.rating
            let old = activity(of: existing)
            let merged = merge(old == "Workout" ? [] : old.components(separatedBy: ", ").flatMap { $0.components(separatedBy: " and ") }, names)
            existing.notes = "\(toldTitle(merged)) · told AthleteOS"
            if !regions.isEmpty { SessionKinds.record(existing.clientId, .gym) }
            bump()
            try? context.save()
            return existing
        }

        let length = max(0, minutes ?? 0)
        let end = isToday ? now : (calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? calendar.startOfDay(for: day))
        let session = Session(startedAt: end.addingTimeInterval(-Double(length) * 60), endedAt: end, sessionRPE: rating, minutes: length,
                              source: .phone, notes: "\(toldTitle(names)) · told AthleteOS", syncedAt: now, athlete: athlete)
        context.insert(session)
        if !regions.isEmpty { SessionKinds.record(session.clientId, .gym) }
        map[session.clientId] = toldPrefix + session.clientId
        imported = map
        answersMap[session.clientId] = WorkoutTagging.Answer(rating: rating, regions: regions, cardio: cardio)
        answers = answersMap
        var toldNow = toldSet
        toldNow.insert(session.clientId)
        told = toldNow
        bump()
        try? context.save()
        return session
    }

    /// "60 min · 3 sets · effort 6/10"; a Health or told workout without sets
    /// says what it was, and no minutes when none were told.
    static func historyLine(_ session: Session, effort: Bool) -> String {
        var parts: [String] = []
        if session.minutes > 0 { parts.append("\(session.minutes) min") }
        parts.append(session.sets.isEmpty && isImported(session) ? activity(of: session) : countedNoun(session.sets.count, "set"))
        if effort, let rpe = session.sessionRPE { parts.append("effort \(rpe)/10") }
        return parts.joined(separator: " · ")
    }

    /// ["chest", "upper back", "core", "arms"] → "Chest, upper back, core and arms".
    static func toldTitle(_ names: [String]) -> String {
        let clean = merge([], names)
        guard let first = clean.first else { return "Workout" }
        let list = clean.count == 1 ? first : clean.dropLast().joined(separator: ", ") + " and " + (clean.last ?? "")
        return list.prefix(1).uppercased() + list.dropFirst()
    }

    private static func merge(_ a: [String], _ b: [String]) -> [String] {
        var out: [String] = []
        for name in (a + b).map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) where !name.isEmpty && !out.contains(name) {
            out.append(name)
        }
        return out
    }

    // MARK: Import

    /// Logs every counting Health workout of today and yesterday that isn't
    /// logged yet. Practice-time workouts stay practice (`ExternalWorkoutStore`
    /// logs those), and a workout the athlete removed never comes back.
    @discardableResult
    static func importNew(athlete: Athlete, context: ModelContext, workouts: [ExternalWorkout] = ExternalWorkoutStore.recent,
                          now: Date = .now, calendar: Calendar = .current) -> Int {
        guard !DemoData.isEnabled, let since = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) else { return 0 }
        let known = Set(imported.values).union(removed)
        // Never twice: also skip one the AthleteOS Watch app already logged.
        let logged = Set(athlete.sessions.compactMap(\.healthKitWorkoutId))
        var added = 0
        var map = imported
        for workout in workouts {
            guard let id = workout.id, !known.contains(id), !logged.contains(id),
                  workout.start >= since, workout.end <= now,
                  WorkoutTagging.countsAsTraining(activity: workout.activity, minutes: workout.minutes),
                  !duringPractice(workout, calendar: calendar),
                  // A session the athlete logged in the app at the same time is the same workout.
                  !athlete.sessions.contains(where: { abs($0.startedAt.timeIntervalSince(workout.start)) < 20 * 60 && $0.endedAt != nil })
            else { continue }
            // The athlete told AthleteOS about this workout already: the told one gets
            // the watch's real times and minutes, and stays the one workout.
            let toldSet = told
            if let toldSession = athlete.sessions.first(where: { toldSet.contains($0.clientId) && $0.healthKitWorkoutId == nil
                                                                 && calendar.isDate($0.startedAt, inSameDayAs: workout.start) }) {
                toldSession.startedAt = workout.start
                toldSession.endedAt = workout.end
                toldSession.minutes = workout.minutes
                toldSession.healthKitWorkoutId = id
                map[toldSession.clientId] = id
                added += 1
                continue
            }
            let age = PlanGenerator.ageInYears(birthDate: athlete.birthDate, now: now)
            let session = Session(startedAt: workout.start, endedAt: workout.end,
                                  sessionRPE: WearableLoad.effort(averageHeartRate: workout.averageHeartRate, minutes: workout.minutes, age: age),
                                  minutes: workout.minutes, source: .watch, healthKitWorkoutId: id,
                                  notes: "\(workout.activity) · from your \(workout.device)", syncedAt: now, athlete: athlete)
            context.insert(session)
            if WorkoutTagging.kind(ofActivity: workout.activity) == .strength { SessionKinds.record(session.clientId, .gym) }
            map[session.clientId] = id
            added += 1
        }
        guard added > 0 else { return 0 }
        imported = map
        bump()
        try? context.save()
        return added
    }

    private static func duringPractice(_ workout: ExternalWorkout, calendar: Calendar) -> Bool {
        guard PracticeSchedule.hasPractice(on: workout.start, calendar: calendar),
              let practice = PracticeSchedule.time(on: workout.start, calendar: calendar) else { return false }
        return WearableLoad.overlaps(workout, practice: practice, day: workout.start, calendar: calendar)
    }

    // MARK: Asking

    /// The newest imported workout still waiting for an answer, asked only
    /// within a day of it (a later recall isn't trustworthy).
    static func pending(_ sessions: [Session], now: Date = .now) -> Session? {
        let answered = answers
        let skip = skipped
        let later = snoozed
        return sessions
            .filter { isImported($0) && answered[$0.clientId] == nil && !skip.contains($0.clientId) }
            .filter { later[$0.clientId].map { now.timeIntervalSince($0) > 3 * 3600 } ?? true }
            .filter { WorkoutTagging.stillAskable(workoutEnd: $0.endedAt ?? $0.startedAt, now: now) }
            .max { $0.startedAt < $1.startedAt }
    }

    /// Saves the answer: effort onto the session, picked exercises as sets
    /// (so the body map and the gym planner see them), pain into today's report.
    static func save(_ answer: WorkoutTagging.Answer, for session: Session, painAreas: [PainArea] = [], painLevel: PainLevel = .some,
                     context: ModelContext) {
        if let rating = answer.rating { session.sessionRPE = max(1, rating) }
        for (index, slug) in answer.exercises.enumerated() where !session.sets.contains(where: { $0.itemSlug == slug }) {
            let set = SetLog(itemSlug: slug, setIndex: index, session: session)
            context.insert(set)
        }
        if answer.hurt == true {
            // Into today's pain report, joined with anything already reported.
            let existing = PainStore.report(on: .now)
            let areas = Array(Set((existing?.areas ?? []) + (painAreas.isEmpty ? [.other] : painAreas))).sorted { $0.rawValue < $1.rawValue }
            let rank = { (level: PainLevel) in PainLevel.allCases.firstIndex(of: level) ?? 0 }
            let level = existing.map { rank($0.level) > rank(painLevel) ? $0.level : painLevel } ?? painLevel
            PainStore.set(PainReport(day: DayKey.of(.now), areas: areas, level: level))
        }
        var all = answers
        all[session.clientId] = answer
        answers = all
        // A very hard part (legs, upper body) is remembered: the next morning's
        // check-in asks how it feels, until it's back to normal (AthleteContext).
        let calendar = Calendar.current
        let tired = WorkoutTagging.trainedBands(answer).filter { $0.value == .veryHard }.map(\.key)
        if !tired.isEmpty, let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: session.startedAt),
                                                              to: calendar.startOfDay(for: .now)).day, days <= 1 {
            let regions: [ContextRegion] = tired.sorted { $0.rawValue < $1.rawValue }.map { $0 == .lower ? .legs : $0 == .upper ? .upperBody : .core }
            AthleteContextStore.add(AthleteContextEvent(from: calendar.startOfDay(for: session.startedAt), kind: .fatigue, source: .healthWorkout,
                                                        reported: ["Very hard \(activity(of: session).lowercased())"], regions: regions, level: 2))
        }
        bump()
        try? context.save()
    }

    /// "Ask me later": asked again on an app open a few hours from now (still
    /// within the day after the workout); it counts either way.
    static func later(_ session: Session) {
        var all = snoozed
        all[session.clientId] = .now
        snoozed = all
    }

    /// Not asked again for this workout; it still counts.
    static func skip(_ session: Session) {
        skipped.insert(session.clientId)
    }

    /// "It wasn't training": the session goes, and the workout never comes back.
    static func remove(_ session: Session, context: ModelContext) {
        if let id = imported[session.clientId] { removed.insert(id) }
        var map = imported
        map[session.clientId] = nil
        imported = map
        bump()
        context.delete(session)
        try? context.save()
    }

    // MARK: For the planner

    /// Regions the athlete's answers say a session trained, with the days each wants.
    static func regions(of session: Session) -> [GymRegion: Int] {
        guard let answer = answers[session.clientId] else { return [:] }
        return WorkoutTagging.effectiveBands(answer, minutes: session.minutes)
            .reduce(into: [:]) { $0[$1.key] = WorkoutTagging.recoveryDays($1.key, after: $1.value) }
    }
}
