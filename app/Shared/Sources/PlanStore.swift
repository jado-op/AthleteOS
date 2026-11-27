import Foundation
import Observation

/// Holds the plan of record (`PlanRecord`): this week and next as the planner
/// built them, and today plus the next seven days in the calendar's words.
/// `rebuild` is the only place a plan is made; everything else reads it
/// (owner, 2026-11-27: "make the ecosystem way better" — screens used to work
/// days out themselves and disagreed).
@MainActor
@Observable
final class PlanStore {
    static let shared = PlanStore()

    /// This week, then next week (either can be missing without a sport).
    private(set) var weeks: [GeneratedWeek] = []
    /// This week alone (what `rebuild` returned last).
    private(set) var thisWeek: GeneratedWeek?
    /// Today and the next seven days.
    private(set) var record: PlanRecord?

    private init() {
        record = Self.loadSaved()
        if let data = UserDefaults.standard.data(forKey: Self.changesKey),
           let saved = try? JSONDecoder().decode([PlanChange].self, from: data) {
            changes = PlanChanges.merge(saved, with: [])
        }
    }

    static var fileURL: URL? {
        AppIdentifiers.sharedContainer?.appending(path: "plan-record.json")
    }

    static func loadSaved() -> PlanRecord? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PlanRecord.self, from: data)
    }

    /// Changes worth telling that the athlete hasn't seen yet (Home shows
    /// them once; `PlanChanges` has the rules).
    private(set) var changes: [PlanChange] = []
    static let changesKey = "plan.changes"

    /// Builds this week and next, then today and the next seven days from
    /// them. Returns this week.
    ///
    /// `announce: false` when the athlete made the change themselves (Edit
    /// week, Tell AthleteOS and the check-in show their own before → after):
    /// nothing new is told, and anything waiting for those days is dropped
    /// because they just saw the day.
    @discardableResult
    func rebuild(for athlete: Athlete, announce: Bool = true, calendar: Calendar = .current) -> GeneratedWeek? {
        let now = Date.now
        let catalogue = CatalogueLoader.load(from: AppConfig.packsDirectory())
        let thisWeek = WeeklyPlan.generate(for: athlete, weekOf: now, catalogue: catalogue)
        let nextStart = calendar.dateInterval(of: .weekOfYear, for: now)?.end
        let nextWeek = nextStart.flatMap { WeeklyPlan.generate(for: athlete, weekOf: $0, catalogue: catalogue) }
        // Assigned only when different: every screen reading these redraws.
        let both = [thisWeek, nextWeek].compactMap { $0 }
        if both != weeks { weeks = both }
        if thisWeek != self.thisWeek { self.thisWeek = thisWeek }

        let built = Self.days(athlete: athlete, week: thisWeek, catalogue: catalogue, calendar: calendar, now: now)
        let new = PlanRecord(builtAt: now, days: built)
        let stale = record.map { !calendar.isDate($0.builtAt, inSameDayAs: now) } ?? true
        guard new.days != record?.days || stale else { return thisWeek }
        // Back after a gap: an old plan is no baseline ("changed on 5 days").
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now
        let comparable = record.map { $0.builtAt >= yesterday } ?? false

        let told: [PlanChange]
        if announce && comparable {
            told = PlanChanges.merge(changes, with: PlanChanges.compare(record, new, calendar: calendar, now: now), calendar: calendar, now: now)
        } else {
            told = PlanChanges.merge(changes.filter { new.day(on: $0.date, calendar: calendar) == $0.after }, with: [], calendar: calendar, now: now)
        }
        if told != changes { setChanges(told) }
        record = new
        if let url = Self.fileURL, let data = try? JSONEncoder().encode(new) {
            try? data.write(to: url, options: .atomic)
        }
        return thisWeek
    }

    /// Tomorrow's plan for each evening the record covers, keyed by the
    /// evening's `DayKey`, in words fit for a Lock Screen (P13): only days
    /// with training or practice; rest, off and game days keep their own note.
    func eveningLines(calendar: Calendar = .current) -> [String: EveningPlan] {
        var lines: [String: EveningPlan] = [:]
        for day in record?.days ?? [] {
            guard let kind = day.kind, kind != .off, kind != .game,
                  let evening = calendar.date(byAdding: .day, value: -1, to: day.date) else { continue }
            let title = [day.title, day.minutes.map { "\($0) min" }].compactMap { $0 }.joined(separator: " · ")
            // Only the schedule line (practice time) goes along, never a because.
            let detail: String? = switch kind {
            case .workout: day.detail.flatMap { $0.hasPrefix("Practice") ? $0 : nil }
            case .practice: day.items.first { $0.kind == .practice }?.detail.map { "At \($0)" }
            default: nil
            }
            lines[DayKey.of(evening, calendar: calendar)] = EveningPlan(title: title, detail: detail)
        }
        return lines
    }

    /// The athlete saw the changes: they go (P5, told once).
    func changesSeen() { setChanges([]) }

    private func setChanges(_ new: [PlanChange]) {
        changes = new
        if new.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.changesKey)
        } else if let data = try? JSONEncoder().encode(new) {
            UserDefaults.standard.set(data, forKey: Self.changesKey)
        }
    }

    /// The planned gym session on `date`, from whichever week holds it.
    func planned(on date: Date, calendar: Calendar = .current) -> GeneratedSession? {
        for week in weeks {
            if let session = week.sessions.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) { return session }
        }
        return nil
    }

    /// The saved day for `date` (today … a week ahead).
    /// A record built on an earlier day is not used (it was saved before
    /// today's check-in, calendar and games): the caller works the day out.
    func day(on date: Date, calendar: Calendar = .current) -> PlannedDay? {
        guard let record, calendar.isDateInToday(record.builtAt) else { return nil }
        return record.day(on: date, calendar: calendar)
    }

    private static func days(athlete: Athlete, week: GeneratedWeek?, catalogue: Catalogue, calendar: Calendar, now: Date) -> [PlannedDay] {
        // Every planned day of both weeks, so next Monday reads the same on
        // Saturday as on Sunday (the calendar itself shows only this week).
        let source = CalendarSource(athlete: athlete, sessions: athlete.sessions, week: week, catalogue: catalogue, calendar: calendar,
                                    ahead: shared.weeks.flatMap(\.sessions))
        let event = source.event
        let today = calendar.startOfDay(for: now)
        return (0...7).compactMap { offset -> PlannedDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let items = source.items(on: date)
            let session = offset == 0 ? source.todayPlan : shared.planned(on: date, calendar: calendar)
            let hasPlanned = items.first.map { $0.kind == .workout && $0.state == .planned } ?? false
            let workoutBecause = session?.decision.flatMap { PlanExplanation.because($0.reasons, event: event) }
            let publicWorkoutBecause = session?.decision.flatMap { PlanExplanation.lockScreenBecause($0.reasons, event: event) }
            return PlannedDay(date: date, items: items,
                              minutes: hasPlanned ? session?.estimatedMinutes : nil,
                              because: PlanRecord.because(for: items, workoutBecause: workoutBecause),
                              publicBecause: PlanRecord.because(for: items, workoutBecause: publicWorkoutBecause))
        }
    }
}
