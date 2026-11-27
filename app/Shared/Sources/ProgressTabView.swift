import SwiftData
import SwiftUI

/// The calendar's colours: four kinds, one colour each (V8 activity colours).
enum ProgressColors {
    /// A workout of any kind: gym, after practice, travel, the athlete's own.
    static let workout = AuraTone.training.mark
    /// Team practice.
    static let practice = AuraTone.body.mark
    /// The extra workout after practice is a workout too: same colour (owner, 2026-11-27: fewer colours).
    static let afterPractice = AuraTone.training.mark
    /// Stretching and mobility.
    static let mobility = AppTheme.cyan
    /// A game or competition.
    static let game = AuraTone.game.mark

    static func color(_ kind: TrainingCalendar.Item.Kind) -> Color {
        switch kind {
        case .workout: workout
        case .practice: practice
        case .game: game
        case .mobility: mobility
        case .off: AppTheme.mutedText
        }
    }
}

/// One mark under a day: filled when it happened, a ring when it's still to
/// come, half-filled for a practice from the schedule nobody logged, a short
/// dash for a day off.
struct CalendarMark: View {
    let item: TrainingCalendar.Item
    var size: CGFloat = 7

    var body: some View {
        let color = ProgressColors.color(item.kind)
        Group {
            if item.kind == .off {
                Capsule().fill(color).frame(width: size * 1.4, height: 2)
            } else {
                switch item.state {
                case .done: Circle().fill(color)
                case .planned: Circle().strokeBorder(color, lineWidth: max(1.4, size / 5))
                case .fromSchedule: Circle().fill(color.opacity(0.45))
                }
            }
        }
        .frame(width: item.kind == .off ? size * 1.4 : size, height: size)
        .accessibilityHidden(true)
    }
}

/// Everything the calendar needs, gathered once per draw and indexed by day.
@MainActor
struct CalendarSource {
    let calendar: Calendar
    let sessionsByDay: [String: [Session]]
    let practiceLogs: [String: PracticeLog]
    let games: [String: [Competition]]
    let planned: [String: GeneratedSession]
    let todayPlan: GeneratedSession?
    let practiceFrom: Date
    let event: String

    /// `ahead`: planned days beyond this week (the plan of record passes next
    /// week); by default only tomorrow from it, so Sunday's "tomorrow" isn't empty.
    init(athlete: Athlete, sessions: [Session], week: GeneratedWeek?, catalogue: Catalogue, calendar: Calendar,
         ahead: [GeneratedSession]? = nil) {
        self.calendar = calendar
        sessionsByDay = Dictionary(grouping: sessions.filter { $0.endedAt != nil || !$0.sets.isEmpty }) { DayKey.of($0.startedAt, calendar: calendar) }
        practiceLogs = Dictionary(PracticeLogStore.logs.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        games = Dictionary(grouping: athlete.competitions) { DayKey.of($0.date, calendar: calendar) }
        // This week's plan (the calendar's rule), plus tomorrow from next week
        // so Sunday's "tomorrow" isn't empty; the rest of next week can still move.
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        let extra = ahead ?? (PlanStore.shared.planned(on: tomorrow, calendar: calendar).map { [$0] } ?? [])
        planned = Dictionary(((week?.sessions ?? []) + extra).map { (DayKey.of($0.date, calendar: calendar), $0) },
                             uniquingKeysWith: { first, _ in first })
        // Today: the one workout Home, Workout, the Watch and the widgets show.
        todayPlan = catalogue.itemsBySlug.isEmpty ? nil : TodayEngine.todaysPick(athlete: athlete, week: week, catalogue: catalogue)?.session
        practiceFrom = athlete.activeSport?.seasonStart ?? calendar.date(byAdding: .year, value: -1, to: .now) ?? .now
        event = AcademyContent.family(forSport: athlete.activeSport?.sportSlug).tokens["Event"] ?? "Game"
    }

    func items(on date: Date) -> [TrainingCalendar.Item] {
        TrainingCalendar.items(facts(on: date))
    }

    func facts(on date: Date) -> TrainingCalendar.Facts {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: .now)
        var facts = TrainingCalendar.Facts(when: day < today ? .past : day == today ? .today : .future)
        let key = DayKey.of(date, calendar: calendar)
        let kinds = SessionKinds.all
        for session in sessionsByDay[key] ?? [] {
            let kind = kinds[session.clientId] ?? .gym
            facts.workoutsDone.append((title: Self.title(kind, session), detail: HealthWorkoutInbox.historyLine(session, effort: false),
                                       mobility: kind == .mobility))
        }
        if let log = practiceLogs[key] {
            facts.practiceLogged = Self.practiceSummary(log)
        } else if date >= practiceFrom, PracticeSchedule.hasPractice(on: date, calendar: calendar) {
            facts.practiceScheduled = PracticeSchedule.time(on: date, calendar: calendar)?.label ?? ""
        }
        for game in games[key] ?? [] {
            let title = game.kind == .game ? event : game.kind.rawValue.capitalized
            facts.games.append((title: title, detail: "\(game.date.formatted(date: .omitted, time: .shortened)) · \(game.isHome ? "home" : "away")"))
        }
        if facts.when == .today {
            facts.plannedWorkout = todayPlan.map { (title: $0.title, minutes: $0.estimatedMinutes) }
        } else if facts.when == .future, let session = planned[key] {
            facts.plannedWorkout = (title: session.title, minutes: session.estimatedMinutes)
        }
        if BusyDays.contains(date, calendar: calendar) {
            facts.off = PlanRecord.cantTrain
        } else {
            switch DayStatusStore.status(on: date, calendar: calendar) {
            case .sick: facts.off = "Sick"
            case .concussion: facts.off = "Training paused"
            case .travel: facts.off = facts.when == .past ? nil : "Away"
            case .holiday: facts.off = facts.when == .past ? nil : "Holiday"
            case .active: break
            }
        }
        return facts
    }

    static func title(_ kind: WorkoutKind, _ session: Session) -> String {
        switch kind {
        case .afterPractice: "After-practice workout"
        case .mobility: "Stretching & mobility"
        case .travel: "Travel workout"
        case .coach: "Workout from your coach"
        case .gym: HealthWorkoutInbox.isTold(session) || session.source != .phone ? "Workout" : "Gym workout"
        }
    }

    static func practiceSummary(_ log: PracticeLog) -> String {
        let types = log.types.isEmpty ? "" : log.types.joined(separator: ", ") + " · "
        let minutes = log.minutes.map { "\($0) min · " } ?? ""
        return "\(types)\(minutes)effort \(log.hard)/5" + (log.saidWent > 0 ? " · went \(log.saidWent)/5" : "")
    }
}

/// The training calendar (owner, 2026-11-27: reworked to be clear): this
/// week in three numbers, the next seven days in words, the month with one
/// mark per kind of thing on each day — done filled, still to come as a
/// ring — then the practice log, what you practised, and the history.
struct ProgressTabView: View {
    let athlete: Athlete
    let week: GeneratedWeek?
    let onPlanInputsChanged: () -> Void

    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @State private var zoom: Zoom = .month
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
    @State private var selectedDay: DayBox?
    @State private var loggingPractice: DayBox?
    @State private var sheet: ProgressSheet?
    @State private var statsPeriod: StatsPeriod = ProAccess.isPro ? .season : .month
    @State private var revision = 0
    @State private var tracking = ProAccess.isPro ? TrackingLevel.current : .easy
    @State private var paywall: ProFeature?
    @State private var catalogue = Catalogue()
    @Environment(\.dismiss) private var dismiss

    enum Zoom: String, CaseIterable, Identifiable {
        case month = "Month", season = "Season", year = "Year"
        var id: String { rawValue }
    }

    enum StatsPeriod: String, CaseIterable, Identifiable {
        case month = "30 days", season = "This season", all = "All time"
        var id: String { rawValue }
    }

    enum ProgressSheet: String, Identifiable {
        case history, checkIns, seasonReview
        var id: String { rawValue }
    }

    /// A date for `.sheet(item:)`.
    struct DayBox: Identifiable {
        let date: Date
        var id: Double { date.timeIntervalSince1970 }
    }

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal
    }

    private var sportSlug: String? { athlete.activeSport?.sportSlug }

    private var source: CalendarSource {
        _ = revision
        return CalendarSource(athlete: athlete, sessions: Array(sessions), week: week, catalogue: catalogue, calendar: calendar)
    }

    // MARK: Body

    var body: some View {
        let source = source
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    // The week lives once, in the Workout tab's strip (owner, 2026-11-27).
                    calendarCard(source)
                        .padding(.top, 16)
                    practiceSection
                    statsSection
                    workoutsSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .padding(.bottom, 20)
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
            .appScreen(.hero)
            .navigationTitle("Training calendar")
            .navigationBarTitleDisplayModeInline()
            .toolbar { CloseToolbarItem { dismiss() } }
            .onAppear {
                revision += 1
                if IntentRoute.take([.logPractice]) != nil { loggingPractice = DayBox(date: .now) }
            }
            .task { catalogue = CatalogueLoader.load(from: AppConfig.packsDirectory()) }
            .sheet(item: $selectedDay, onDismiss: { revision += 1 }) { box in
                DayDetailSheet(athlete: athlete, date: box.date, items: source.items(on: box.date)) {
                    let date = box.date
                    selectedDay = nil
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        loggingPractice = DayBox(date: date)
                    }
                }
            }
            .sheet(item: $loggingPractice, onDismiss: { revision += 1; tracking = ProAccess.isPro ? TrackingLevel.current : .easy }) { box in
                PracticeLogSheet(athlete: athlete, date: box.date)
            }
            .sheet(item: $sheet, onDismiss: { revision += 1 }) { sheet in
                switch sheet {
                case .history: SessionHistoryView()
                case .checkIns: CheckInHistoryView(checkIns: athlete.checkIns)
                case .seasonReview: SeasonReviewSheet(athlete: athlete, sessions: sessions, catalogue: catalogue)
                }
            }
            .proFeature(item: $paywall, athlete: athlete)
        }
    }

    // MARK: Calendar

    private func calendarCard(_ source: CalendarSource) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(Zoom.allCases) { value in
                    // Month is free; the whole season and year are Pro.
                    let locked = value != .month && !ProAccess.isPro
                    Button {
                        if locked { paywall = .fullSeasonCalendar } else { withAnimation(.easeInOut(duration: 0.2)) { zoom = value } }
                    } label: {
                        Text(value.rawValue)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(zoom == value ? AppTheme.onAccent : AppTheme.ink)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(zoom == value ? AppTheme.accent : AppTheme.fill, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(value.rawValue)
                }
            }
            switch zoom {
            case .month: monthView(source)
            case .season: overview(months: seasonMonths, source)
            case .year: overview(months: yearMonths, source)
            }
            legend
        }
        .cardStyle(padding: 16)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                ForEach([TrainingCalendar.Item.Kind.workout, .practice, .game, .mobility], id: \.self) { kind in
                    HStack(spacing: 5) {
                        Circle().fill(ProgressColors.color(kind)).frame(width: 8, height: 8)
                        Text(kind == .workout ? "Workout" : kind == .practice ? "Practice" : kind == .game ? "Game" : "Mobility")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
            HStack(spacing: 14) {
                HStack(spacing: 5) { Circle().fill(AppTheme.ink).frame(width: 8, height: 8); Text("Done") }
                HStack(spacing: 5) { Circle().strokeBorder(AppTheme.ink, lineWidth: 1.5).frame(width: 8, height: 8); Text("Coming up") }
                HStack(spacing: 5) { Capsule().fill(AppTheme.mutedText).frame(width: 11, height: 2); Text("Day off") }
            }
            .font(.caption)
            .foregroundStyle(AppTheme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return Array(symbols[1...]) + [symbols[0]]
    }

    /// Leading blanks so the 1st lands on its weekday (Monday first).
    private func leadingBlanks(_ monthStart: Date) -> Int {
        (calendar.component(.weekday, from: monthStart) + 5) % 7
    }

    private func days(in monthStart: Date) -> [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: monthStart) }
    }

    private func monthView(_ source: CalendarSource) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let blanks = leadingBlanks(month)
        let monthDays = days(in: month)
        return VStack(spacing: 10) {
            HStack {
                Button { month = calendar.date(byAdding: .month, value: -1, to: month) ?? month } label: {
                    Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Previous month")
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Button { month = calendar.date(byAdding: .month, value: 1, to: month) ?? month } label: {
                    Image(systemName: "chevron.right").font(.headline).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Next month")
            }
            .foregroundStyle(AppTheme.ink)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption.weight(.bold)).foregroundStyle(AppTheme.secondaryText)
                }
                ForEach(0..<blanks, id: \.self) { _ in Color.clear.frame(height: 48) }
                ForEach(monthDays, id: \.self) { day in
                    let isToday = calendar.isDateInToday(day)
                    let items = source.items(on: day)
                    Button { selectedDay = DayBox(date: day) } label: {
                        VStack(spacing: 5) {
                            Text("\(calendar.component(.day, from: day))")
                                .font(.subheadline.weight(isToday ? .heavy : .semibold))
                                .foregroundStyle(isToday ? AppTheme.onAccent : AppTheme.ink)
                                .frame(width: 30, height: 26)
                                .background(isToday ? AppTheme.accent : Color.clear, in: Capsule())
                            HStack(spacing: 2) {
                                ForEach(TrainingCalendar.marks(items)) { CalendarMark(item: $0, size: 7) }
                            }
                            .frame(height: 8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + ". " + TrainingCalendar.line(items))
                }
            }
            .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -60 { month = calendar.date(byAdding: .month, value: 1, to: month) ?? month }
                if value.translation.width > 60 { month = calendar.date(byAdding: .month, value: -1, to: month) ?? month }
            })
        }
    }

    private var seasonMonths: [Date] {
        guard let sport = athlete.activeSport else { return yearMonths }
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: sport.seasonStart)) ?? sport.seasonStart
        var months: [Date] = []
        var cursor = start
        while cursor <= sport.seasonEnd, months.count < 12 {
            months.append(cursor)
            cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? sport.seasonEnd.addingTimeInterval(1)
        }
        return months.isEmpty ? yearMonths : months
    }

    private var yearMonths: [Date] {
        let year = calendar.component(.year, from: month)
        return (1...12).compactMap { calendar.date(from: DateComponents(year: year, month: $0, day: 1)) }
    }

    /// Zoomed out: every month as a small grid, one mark per day (its most important thing).
    private func overview(months: [Date], _ source: CalendarSource) -> some View {
        let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
        return VStack(alignment: .leading, spacing: 10) {
            if zoom == .year {
                HStack {
                    Button { month = calendar.date(byAdding: .year, value: -1, to: month) ?? month } label: {
                        Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Previous year")
                    Spacer()
                    Text(String(calendar.component(.year, from: month))).font(.title3.bold())
                    Spacer()
                    Button { month = calendar.date(byAdding: .year, value: 1, to: month) ?? month } label: {
                        Image(systemName: "chevron.right").font(.headline).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Next year")
                }
                .foregroundStyle(AppTheme.ink)
            } else {
                Text("Your season").font(.title3.bold()).foregroundStyle(AppTheme.ink)
            }
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(months, id: \.self) { monthStart in
                    Button {
                        month = monthStart
                        withAnimation { zoom = .month }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(monthStart.formatted(.dateTime.month(.abbreviated)))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(calendar.isDate(monthStart, equalTo: .now, toGranularity: .month) ? AppTheme.brand : AppTheme.ink)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 3) {
                                ForEach(0..<leadingBlanks(monthStart), id: \.self) { _ in Color.clear.frame(height: 10) }
                                ForEach(days(in: monthStart), id: \.self) { day in
                                    if let first = TrainingCalendar.marks(source.items(on: day)).first {
                                        CalendarMark(item: first, size: 8).frame(height: 10)
                                    } else {
                                        Circle().fill(AppTheme.fill).frame(width: 4, height: 4).frame(height: 10)
                                    }
                                }
                            }
                        }
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }

    // MARK: Team practice

    private var practiceSection: some View {
        let todayKey = DayKey.of(.now, calendar: calendar)
        let loggedToday = PracticeLogStore.log(on: todayKey, sportSlug: sportSlug) != nil
        let practiceToday = PracticeSchedule.hasPractice(on: .now, calendar: calendar)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Practice log")
            // V8: two capsules and one line, not two boxes.
            HStack(spacing: 8) {
                ForEach(TrackingLevel.allCases, id: \.self) { level in
                    let locked = level == .exact && !ProAccess.isPro
                    Button {
                        if locked {
                            paywall = .detailedTracking
                        } else {
                            tracking = level
                            TrackingLevel.current = level
                        }
                    } label: {
                        Chip(level.title, isSelected: tracking == level)
                    }
                    .buttonStyle(.pressable)
                }
            }
            Text(tracking == .easy ? "Time, effort, mood and result." : "Plus each part of your sport.")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
            if loggedToday {
                Label("Today's practice is logged", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.green)
            }
            Button { loggingPractice = DayBox(date: .now) } label: {
                Label(loggedToday ? "Edit today's practice" : (practiceToday ? "Log today's practice" : "Log a practice"), systemImage: "square.and.pencil")
            }
            .buttonStyle(.primary)
        }
    }

    private var statsSince: String? {
        switch statsPeriod {
        case .month: return DayKey.of(calendar.date(byAdding: .day, value: -30, to: .now) ?? .now, calendar: calendar)
        case .season: return athlete.activeSport.map { DayKey.of($0.seasonStart, calendar: calendar) }
        case .all: return nil
        }
    }

    private var statsSection: some View {
        _ = revision
        let logs = PracticeLogStore.logs.filter { sportSlug == nil || $0.sportSlug == sportSlug }
        let counts = PracticeStats.counts(logs, since: statsSince)
        let ratings = PracticeStats.ratings(logs, since: statsSince)
        let top = counts.first?.count ?? 1
        let insight = PracticeStats.insight(counts, allTypes: SportPractice.types(for: sportSlug))
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("What you practised")
            WrapLayout(spacing: 8) {
                ForEach(StatsPeriod.allCases) { period in
                    // The last 30 days are free; longer is Pro.
                    let locked = period != .month && !ProAccess.isPro
                    Button {
                        if locked { paywall = .fullHistory } else { statsPeriod = period }
                    } label: {
                        Chip(period.rawValue, isSelected: statsPeriod == period)
                    }
                    .buttonStyle(.pressable)
                }
            }
            if counts.isEmpty {
                Text("Nothing logged yet. Log a practice and pick what you worked on.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle(padding: 16)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(counts, id: \.type) { entry in
                        HStack(spacing: 10) {
                            Text(entry.type)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                                .frame(width: 130, alignment: .leading)
                            GeometryReader { proxy in
                                Capsule().fill(ProgressColors.practice)
                                    .frame(width: max(8, proxy.size.width * Double(entry.count) / Double(top)))
                            }
                            .frame(height: 12)
                            Text("\(entry.count)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(AppTheme.ink)
                                .frame(width: 34, alignment: .trailing)
                        }
                    }
                    if let insight {
                        if ProAccess.isPro {
                            Label(insight, systemImage: "lightbulb.fill")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.ink)
                                .padding(.top, 4)
                        } else {
                            Button { paywall = .detailedTracking } label: {
                                Label("See what you practise least", systemImage: "lightbulb")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)
                            }
                            .buttonStyle(.pressable)
                            .padding(.top, 4)
                        }
                    }
                }
                .cardStyle(padding: 16)
            }
            if !ratings.isEmpty, ProAccess.isPro {
                VStack(alignment: .leading, spacing: 10) {
                    Text(SportPractice.components(for: sportSlug).title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    ForEach(ratings, id: \.item) { entry in
                        HStack {
                            Text(entry.item).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                            Spacer()
                            Text("\(SportPractice.ratingWords[max(0, min(3, Int(entry.average.rounded()) - 1))]) · \(entry.times)×")
                                .font(.subheadline)
                                .foregroundStyle(entry.average >= 3 ? AppTheme.green : (entry.average < 2 ? AppTheme.red : AppTheme.secondaryText))
                        }
                    }
                }
                .cardStyle(padding: 16)
            }
        }
    }

    // MARK: Workouts

    private var workoutsSection: some View {
        let kinds = SessionKinds.all
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Training history", subtitle: "\(sessions.count) workouts so far.")
            ForEach(sessions.prefix(3)) { session in
                let kind = kinds[session.clientId] ?? .gym
                HStack(spacing: 12) {
                    Circle().fill(color(kind)).frame(width: 14, height: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label(kind)).font(.headline).foregroundStyle(AppTheme.ink)
                        Text(session.startedAt.formatted(.dateTime.weekday(.abbreviated).month().day()) + " · " + HealthWorkoutInbox.historyLine(session, effort: false))
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            // Every look back lives here (docs/CLARITY-PLAN.md): one list.
            VStack(spacing: 0) {
                Button { sheet = .history } label: {
                    ListRow(systemImage: "clock.arrow.circlepath", color: AppTheme.ink, title: "All workouts", detail: "\(sessions.count)")
                }
                .buttonStyle(.pressable)
                Button { sheet = .checkIns } label: {
                    ListRow(systemImage: "sun.max.fill", color: AppTheme.ink, title: "Past check-ins", detail: "\(athlete.checkIns.count)")
                }
                .buttonStyle(.pressable)
                Button { sheet = .seasonReview } label: {
                    ListRow(systemImage: "flag.checkered", color: AppTheme.ink, title: "Season review", detail: "Your season, PDF, recruiting")
                }
                .buttonStyle(.pressable)
            }
        }
    }

    private func color(_ kind: WorkoutKind) -> Color {
        switch kind {
        case .afterPractice: ProgressColors.afterPractice
        case .mobility: ProgressColors.mobility
        default: ProgressColors.workout
        }
    }

    private func label(_ kind: WorkoutKind) -> String {
        switch kind {
        case .gym: "Gym workout"
        case .afterPractice: "After practice"
        case .mobility: "Stretching & mobility"
        case .travel: "Travel workout"
        case .coach: "From your coach"
        }
    }
}

// MARK: - A day

/// One day, in the calendar's own words: what happened, what's coming, the
/// check-in. Never a plan on a past day.
struct DayDetailSheet: View {
    let athlete: Athlete
    let date: Date
    let items: [TrainingCalendar.Item]
    let onLogPractice: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var calendar: Calendar { .current }
    private var isFuture: Bool { calendar.startOfDay(for: date) > calendar.startOfDay(for: .now) }
    private var done: [TrainingCalendar.Item] { items.filter { $0.state != .planned } }
    private var coming: [TrainingCalendar.Item] { items.filter { $0.state == .planned } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenTitle(date.formatted(.dateTime.weekday(.wide).month(.wide).day()),
                                subtitle: calendar.isDateInToday(date) ? "Today" : isFuture ? "Coming up" : nil)
                    if items.isEmpty {
                        Text(isFuture ? "Nothing on this day yet. Rest is part of the plan." : "Nothing on this day.")
                            .font(.body)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    if !done.isEmpty {
                        group(isFuture ? "" : "What happened", done)
                    }
                    if !coming.isEmpty {
                        group(calendar.isDateInToday(date) ? "Still to come" : "Planned", coming)
                    }
                    if let checkIn = athlete.checkIns.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
                        row(TrainingCalendar.Item(kind: .off, state: .done, title: "Check-in", detail: checkInSummary(checkIn)), mark: false)
                    }
                    if !isFuture {
                        Button { onLogPractice() } label: {
                            Label(PracticeLogStore.log(on: DayKey.of(date)) == nil ? "Log a team practice on this day" : "Edit this practice",
                                  systemImage: "square.and.pencil")
                        }
                        .buttonStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .appScreen()
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [TrainingCalendar.Item]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !title.isEmpty {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.secondaryText)
            }
            ForEach(items) { row($0, mark: true) }
        }
    }

    private func row(_ item: TrainingCalendar.Item, mark: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if mark {
                CalendarMark(item: item, size: 14).padding(.top, 4)
            } else {
                Image(systemName: "sun.max.fill").font(.footnote).foregroundStyle(AppTheme.secondaryText).frame(width: 14).padding(.top, 3)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.headline).foregroundStyle(AppTheme.ink)
                if let detail = item.detail {
                    Text(detail).font(.subheadline).foregroundStyle(AppTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .cardStyle(padding: 14)
        .accessibilityElement(children: .combine)
    }

    private func checkInSummary(_ checkIn: CheckIn) -> String {
        var parts: [String] = []
        if let hours = checkIn.sleepHours { parts.append("Sleep \(SleepMath.label(hours))") }
        if let energy = CheckInOptions.nearest(Double(checkIn.energy), in: CheckInOptions.energy) { parts.append("energy \(energy.title.lowercased())") }
        if let soreness = CheckInOptions.nearest(Double(checkIn.soreness), in: CheckInOptions.soreness) { parts.append("soreness \(soreness.title.lowercased())") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Logging a practice

struct PracticeLogSheet: View {
    let athlete: Athlete
    let date: Date

    @Environment(\.dismiss) private var dismiss
    @State private var sportSlug: String
    @State private var level = ProAccess.isPro ? TrackingLevel.current : .easy
    @State private var showingPaywall = false
    @State private var types: Set<String> = []
    @State private var hard = 3
    @State private var went = 3
    @State private var mood = 3
    @State private var minutes = 90
    @State private var tiredMuscles: Set<String> = []
    @State private var ratings: [String: Int] = [:]
    @State private var note = ""
    @State private var intent: String?
    @State private var enjoyment: Int?
    @State private var existing: PracticeLog?

    init(athlete: Athlete, date: Date) {
        self.athlete = athlete
        self.date = date
        let sport = athlete.activeSport?.sportSlug ?? athlete.sports.first?.sportSlug ?? ""
        _sportSlug = State(initialValue: sport)
        let log = PracticeLogStore.log(on: DayKey.of(date), sportSlug: sport)
        _existing = State(initialValue: log)
        if let log {
            _types = State(initialValue: Set(log.types))
            _hard = State(initialValue: log.hard)
            _went = State(initialValue: log.saidWent > 0 ? log.saidWent : 3)
            _mood = State(initialValue: log.mood > 0 ? log.mood : 3)
            _minutes = State(initialValue: log.minutes ?? 90)
            _tiredMuscles = State(initialValue: Set(log.tiredMuscles))
            _ratings = State(initialValue: log.ratings)
            _note = State(initialValue: log.note ?? "")
            _intent = State(initialValue: log.intent)
            _enjoyment = State(initialValue: log.enjoyment)
            if !log.tiredMuscles.isEmpty || !log.ratings.isEmpty { _level = State(initialValue: .exact) }
        } else if let time = PracticeSchedule.time(on: date) {
            _minutes = State(initialValue: max(15, time.end - time.start))
        }
    }

    var body: some View {
        StepScaffold(
            title: "Team practice",
            subtitle: date.formatted(.dateTime.weekday(.wide).month().day()),
            onClose: { dismiss() },
            onConfirm: save
        ) {
            if athlete.sports.count > 1 {
                WrapLayout(spacing: 8) {
                    ForEach(athlete.sports, id: \.id) { sport in
                        Button { sportSlug = sport.sportSlug; types = [] } label: {
                            Chip(allSportsBySlug[sport.sportSlug]?.name ?? sport.sportSlug, isSelected: sportSlug == sport.sportSlug)
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
            HStack(spacing: 8) {
                ForEach(TrackingLevel.allCases, id: \.self) { value in
                    let locked = value == .exact && !ProAccess.isPro
                    Button {
                        if locked {
                            showingPaywall = true
                        } else {
                            level = value
                            TrackingLevel.current = value
                        }
                    } label: {
                        Chip(value.title, isSelected: level == value)
                    }
                    .buttonStyle(.pressable)
                }
            }

            section("How long? \(minutes) min") {
                Stepper("", value: $minutes, in: 15...300, step: 15).labelsHidden()
            }
            scale("Effort", low: "Easy", high: "Max", value: $hard)
            section("Mood afterwards") {
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { value in
                        let faces = ["😣", "😕", "😐", "🙂", "😄"]
                        // Selected: a solid ring, the others faded — a
                        // tinted fill alone looked the same as unselected
                        // on black and white.
                        let selected = mood == value
                        Button { mood = value } label: {
                            Text(faces[value - 1])
                                .font(.system(size: 30))
                                .opacity(selected ? 1 : 0.45)
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(AppTheme.accent, lineWidth: selected ? 3 : 0)
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("Mood \(value) of 5")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            scale("Result: how did it go?", low: "Badly", high: "Great", value: $went)
            section("What kind of practice?") {
                WrapLayout(spacing: 8) {
                    ForEach(PracticeIntent.keys, id: \.self) { key in
                        Button { intent = intent == key ? nil : key } label: { Chip(PracticeIntent.title(key), isSelected: intent == key) }
                            .buttonStyle(.pressable)
                    }
                }
            }
            section("Enjoyed it? (optional)") {
                WrapLayout(spacing: 8) {
                    ForEach([1, 2, 3], id: \.self) { value in
                        Button { enjoyment = enjoyment == value ? nil : value } label: {
                            Chip(value == 1 ? "Not much" : (value == 2 ? "It was OK" : "A lot"), isSelected: enjoyment == value)
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
            section("Worked on (optional)") {
                WrapLayout(spacing: 8) {
                    ForEach(SportPractice.types(for: sportSlug), id: \.self) { type in
                        Button {
                            if types.contains(type) { types.remove(type) } else { types.insert(type) }
                        } label: { Chip(type, isSelected: types.contains(type)) }
                            .buttonStyle(.pressable)
                    }
                }
            }

            if level == .exact {
                section("What feels worked?") {
                    WrapLayout(spacing: 8) {
                        ForEach(MuscleRegion.allCases, id: \.self) { region in
                            Button {
                                if tiredMuscles.contains(region.rawValue) { tiredMuscles.remove(region.rawValue) } else { tiredMuscles.insert(region.rawValue) }
                            } label: { Chip(region.displayName, isSelected: tiredMuscles.contains(region.rawValue)) }
                                .buttonStyle(.pressable)
                        }
                    }
                }
                let components = SportPractice.components(for: sportSlug)
                section(components.title) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(components.items, id: \.self) { component in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(component).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                                HStack(spacing: 6) {
                                    ForEach(1...4, id: \.self) { value in
                                        Button {
                                            ratings[component] = ratings[component] == value ? nil : value
                                        } label: {
                                            Text(SportPractice.ratingWords[value - 1])
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(ratings[component] == value ? AppTheme.onAccent : AppTheme.ink)
                                                .frame(maxWidth: .infinity, minHeight: 38)
                                                .background(ratings[component] == value ? AppTheme.accent : AppTheme.fill, in: Capsule())
                                        }
                                        .buttonStyle(.pressable)
                                    }
                                }
                            }
                        }
                    }
                }
                section("Note (optional)") {
                    TextField("Anything to remember?", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(14)
                        .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            if let existing {
                Button("Delete this log", role: .destructive) {
                    PracticeLogStore.delete(existing)
                    dismiss()
                }
                .font(.headline)
                .foregroundStyle(AppTheme.red)
                .frame(maxWidth: .infinity)
            }
        }
        .proFeature(isPresented: $showingPaywall, athlete: athlete, feature: .detailedTracking)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(AppTheme.ink)
            content()
        }
    }

    private func scale(_ title: String, low: String, high: String, value: Binding<Int>) -> some View {
        section(title) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { option in
                        Button { value.wrappedValue = option } label: {
                            Text("\(option)")
                                .font(.headline)
                                .foregroundStyle(value.wrappedValue == option ? AppTheme.onAccent : AppTheme.ink)
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(value.wrappedValue == option ? AppTheme.accent : AppTheme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.pressable)
                    }
                }
                HStack { Text(low); Spacer(); Text(high) }
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private func save() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let order = SportPractice.types(for: sportSlug)
        PracticeLogStore.save(PracticeLog(
            id: existing?.id ?? UUID().uuidString, day: DayKey.of(date), sportSlug: sportSlug,
            types: order.filter { types.contains($0) } + types.subtracting(order).sorted(),
            hard: hard, went: went, mood: mood, minutes: minutes,
            tiredMuscles: level == .exact ? tiredMuscles.sorted() : [],
            ratings: level == .exact ? ratings : [:],
            note: level == .exact && !trimmed.isEmpty ? trimmed : nil,
            intent: intent, enjoyment: enjoyment
        ))
        dismiss()
    }
}
