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
            let set = MuscleTraining.LoggedSet(date: session.startedAt, exercise: item.name, muscles: item.muscles)
            sets += Array(repeating: set, count: WorkoutTagging.bodyMapSets(band))
        }
        return sets + MuscleTraining.regionSets(date: session.startedAt, label: activity,
                                                bands: bands.filter { !covered.contains($0.key) })
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
        return sessions
            .filter { isImported($0) && answered[$0.clientId] == nil && !skip.contains($0.clientId) }
            .filter { WorkoutTagging.stillAskable(workoutEnd: $0.endedAt ?? $0.startedAt, now: now) }
            .max { $0.startedAt < $1.startedAt }
    }

    /// Saves the answer: effort onto the session, picked exercises as sets
    /// (so the body map and the gym planner see them), pain into today's report.
    static func save(_ answer: WorkoutTagging.Answer, for session: Session, context: ModelContext) {
        if let rating = answer.rating { session.sessionRPE = max(1, rating) }
        for (index, slug) in answer.exercises.enumerated() where !session.sets.contains(where: { $0.itemSlug == slug }) {
            let set = SetLog(itemSlug: slug, setIndex: index, session: session)
            context.insert(set)
        }
        if answer.hurt == true, PainStore.report(on: .now) == nil {
            PainStore.set(PainReport(day: DayKey.of(.now), areas: [.other], level: .some))
        }
        var all = answers
        all[session.clientId] = answer
        answers = all
        bump()
        try? context.save()
    }

    /// "Later": not asked again for this workout; it still counts.
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
