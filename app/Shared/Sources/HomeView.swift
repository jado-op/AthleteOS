#if os(iOS)
import StoreKit
#endif
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Home answers "what do I do now?" (docs/CLARITY-PLAN.md): the kind of day
/// and a greeting, then the one next step — check-in, training, a lesson,
/// the reflection — and today's plan as a short numbered list with why it
/// looks like this. Below it, the week and the widgets the athlete added in
/// Edit Home (none by default).
struct HomeView: View {
    let athlete: Athlete
    let apiClient: APIClient
    let week: GeneratedWeek?
    @Binding var selectedTab: AppTab
    let onPlanInputsChanged: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Session.startedAt, order: .reverse) private var allSessions: [Session]
    @AppStorage(CampusProgress.learnedKey) private var campusLearnedRaw = ""
    @State private var catalogue = Catalogue()
    @State private var status: DayStatus = DayStatusStore.status()
    @State private var practiceDays: Set<Int> = PracticeSchedule.weekdays
    @State private var scheduleIsSet = PracticeSchedule.isSet
    /// The briefing the twin's coach assigned and the athlete hasn't read:
    /// the day's reading comes from the twin first (one recommender).
    @State private var twinBriefing: Briefing?
    @State private var briefingReadToday = false
    /// "Train as planned instead": one choice for today, shared by Home and Workout.
    @AppStorage(ReadinessOverride.key) private var readinessOverrideDay = ""
    private var readinessOverridden: Bool {
        get { readinessOverrideDay == DayKey.of(.now) }
        nonmutating set { readinessOverrideDay = newValue ? DayKey.of(.now) : "" }
    }
    @State private var liveLaunch: LiveSessionLaunch?
    @State private var activeSheet: HomeSheet?
    @State private var showingCompetitions = false
    @State private var showingTell = false
    @State private var pendingAction: QuickAction?
    /// Picked in "Today completed": opens once that popup has closed.
    /// Picked in search: opens once the search has closed.
    @State private var pendingSearch: AppSearchTarget?
    @State private var searchDestination: SearchBox?
    @State private var proFeature: ProFeature?
    @State private var showingUpgrade = false
    /// A workout started from a sheet opened by search: starts once it closes.
    @State private var pendingLive: LiveSessionLaunch?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    /// Now, for the part of the day (morning, day, evening, night).
    @State private var clock = Date.now
    @State private var showingWhy = false
    @State private var preview: PreviewBox?
    @State private var loaded = false
    @State private var routine: MindsetRoutine?
    @State private var lowEnergySnoozed = LowEnergyCheck.isSnoozed
    /// The coach's latest announcement (closed ones stay closed).
    @State private var announcement = TeamAnnouncements.current
    /// Bumped when a sheet closes, so what it changed (reflection, pain, day status) redraws.
    @State private var revision = 0
    #if os(iOS)
    #endif
    /// The widget being held while arranging, and where the board is in reordering it.

    enum HomeSheet: String, Identifiable {
        case quickActions, checkIn, addGame, history, fuel, dayStatus, schedule, reflection, search, safety, mindset, tests, windDown, seasonReview, tournament
        var id: String { rawValue }
    }

    private var calendar: Calendar { .current }
    private var todaysCheckIn: CheckIn? { AthleteStats.todaysCheckIn(athlete) }
    private var sportInfo: SportInfo? { athlete.activeSport.flatMap { allSportsBySlug[$0.sportSlug] } }
    private var gameToday: Competition? { athlete.competitions.first { calendar.isDateInToday($0.date) } }
    /// The team calendar decides when there is one (practice days otherwise).
    /// `practiceDays` and `revision` are read so a change there redraws this.
    private var practiceToday: Bool { _ = practiceDays; _ = revision; return PracticeSchedule.hasPractice(on: .now) }
    private var practicesToday: [ScheduleEvent] { ScheduleStore.imported.practices(on: .now) }
    private var examWeek: Bool { _ = practiceDays; return ScheduleStore.isExamWeek(.now) }
    private var loggedToday: Bool { allSessions.contains { calendar.isDateInToday($0.startedAt) } }
    private var isTrainingDay: Bool { status != .sick && status != .concussion }

    private var modeContext: WorkoutModeContext {
        WorkoutModeContext(
            catalogue: catalogue, sport: sportInfo, positionSlug: athlete.activeSport?.positionSlug,
            formatSlug: athlete.activeSport?.formatSlug, equipment: Set(athlete.equipmentAvailable),
            trainsUnderCoach: athlete.trainsUnderCoach, age: PlanGenerator.ageInYears(birthDate: athlete.birthDate, now: .now),
            struggles: Struggles.selected,
            prepMoment: PrepMoment.at(.now, gameToday: gameToday != nil)
        )
    }

    // MARK: - Today's plan

    /// Today's readiness in words (the check-in, reported pain, last night).
    private var readiness: (level: TodayReadiness, reason: String)? {
        _ = revision
        return DailyLoop.today(athlete)
    }

    private var readinessBand: ReadinessBand? {
        guard !readinessOverridden, let level = readiness?.level, level > .normal else { return nil }
        return level.band
    }

    /// Today's workout: built around practice, games and the day's status.
    /// Today's decision from the rules (safety first; see KnowledgeSystem.swift).
    private var planning: PlanningEvaluation {
        _ = revision
        return PlanningRules.today(athlete, sessions: allSessions)
    }

    private var todaysWorkout: (mode: WorkoutMode, session: GeneratedSession)? {
        // No added training when the rules say so (game near, illness, pain…).
        guard planning.decision.allowsAddedTraining else { return nil }
        switch status {
        case .sick, .concussion: return nil
        case .travel, .holiday:
            return engine(.travel).map { (mode: WorkoutMode.travel, session: $0) }
        case .active:
            if gameToday != nil { return nil }
            if practiceToday {
                return engine(.afterPractice).map { (mode: WorkoutMode.afterPractice, session: $0) }
            }
            let planned = week?.sessions.first(where: { calendar.isDateInToday($0.date) })
            // The athlete's own version of this gym day stays exactly theirs.
            if let planned, let slot = planned.slot, PlanCustomizationStore.load().workout(for: .gym(slot)) != nil {
                return (mode: WorkoutMode.gymDay, session: adjusted(planned))
            }
            // V6: the engine decides — a development day, a primer before a
            // game, recovery, a programmed conditioning day, or rest.
            if TodayEngine.isAvailable(catalogue) {
                return TodayEngine.session(nil, athlete: athlete, sessions: allSessions, catalogue: catalogue, plannedGymDay: planned != nil)
                    .map { (mode: WorkoutMode.gymDay, session: $0) }
            }
            return planned.map { (mode: WorkoutMode.gymDay, session: adjusted($0)) }
        }
    }

    /// A workout of this kind for today: the athlete's own version, the V6
    /// engine's, or (old packs) the previous builder's with today's adjustments.
    private func engine(_ mode: WorkoutMode) -> GeneratedSession? {
        let plannedGymDay = week?.sessions.contains { calendar.isDateInToday($0.date) } ?? false
        guard let session = TodayEngine.workout(mode, athlete: athlete, sessions: allSessions, catalogue: catalogue,
                                                context: modeContext, plannedGymDay: plannedGymDay) else { return nil }
        if session.decision != nil { return session }
        return mode == .afterPractice ? adjusted(session) : TodaysPain.apply(session, athlete: athlete, catalogue: catalogue)
    }

    /// A low-readiness day lightens the workout (the athlete can undo it).
    /// Today's pain first (nothing that loads a sore area), then readiness.
    private func adjusted(_ session: GeneratedSession) -> GeneratedSession {
        // The V6 engine already took pain, readiness and the day into account.
        if session.decision != nil { return session }
        let safe = TodaysPain.apply(session, athlete: athlete, catalogue: catalogue)
        // Back after illness or a long school day: shorter too.
        let ruleBand: ReadinessBand? = planning.reasonCodes.contains { ["RETURN_AFTER_ILLNESS", "LONG_SCHOOL_DAY"].contains($0) } ? .amber : nil
        guard let band = readinessBand ?? ruleBand else { return safe }
        return ReadinessApplier.apply(to: safe, band: band).session
    }

    private var movementPrep: GeneratedSession? {
        isTrainingDay ? engine(.mobility) : nil
    }

    // MARK: - Food around practice and games

    @AppStorage("gameStartMinutes") private var gameStartMinutes = 17 * 60
    @State private var prePracticeAnswer: Bool?

    /// Game day: the next two fuel steps, timed from the game.
    private var gameFuelTips: [FuelTip]? {
        guard let game = gameToday, status == .active else { return nil }
        let start = FuelEngine.gameStart(game.date, usualMinutes: gameStartMinutes, calendar: calendar)
        return Array(FuelEngine.gameDayTimeline(gameStart: start, isTournament: game.kind == .tournament)
            .filter { ($0.time ?? .distantFuture) > .now.addingTimeInterval(-15 * 60) && $0.time != nil }
            .prefix(2))
    }

    /// In the three hours before practice: one question, not a food diary.
    private var askPrePracticeFuel: Bool {
        guard status == .active, practiceToday, prePracticeAnswer != true,
              let time = PracticeSchedule.time(on: .now) else { return false }
        let now = calendar.component(.hour, from: .now) * 60 + calendar.component(.minute, from: .now)
        guard now >= time.start - 180, now <= time.start + 15 else { return false }
        return !MealStore.meals(of: athlete, on: .now).contains { $0.slot == .preTraining }
    }

    private var prePracticeFuelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Did you eat before practice?").font(.title3.weight(.semibold)).foregroundStyle(AppTheme.ink)
            if prePracticeAnswer == false {
                Text("A banana, toast or a cereal bar now gives you energy for practice.")
                    .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
            }
            ButtonRow {
                Button("Yes") {
                    _ = try? MealStore(modelContext: modelContext).logMeal(athlete: athlete, slot: .preTraining, protein: 0, carbs: 1, colour: 0)
                    prePracticeAnswer = true
                }
                .buttonStyle(.primary)
                Button("Not yet") { prePracticeAnswer = false }
                    .buttonStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// From 6 pm: tonight's bedtime for 9 hours before tomorrow's start, and
    /// last week's sleep when it's been short.
    private var bedtimeTonight: (minutes: Int, detail: String)? {
        guard calendar.component(.hour, from: .now) >= 18, status != .sick else { return nil }
        let settings = ReminderScheduler.settings
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: .now) else { return nil }
        let early = Bedtime.firstSessionStart(on: tomorrow, games: athlete.competitions.map(\.date), calendar: calendar)
        let wake = ReminderScheduler.nextWake(after: .now, settings: settings, calendar: calendar)
        let minutes = Bedtime.suggested(wakeMinutes: wake, firstSessionTomorrow: early)
        let week = athlete.checkIns.filter { $0.date > calendar.date(byAdding: .day, value: -7, to: .now) ?? .now }.compactMap(\.sleepHours)
        let average = week.isEmpty ? nil : week.reduce(0, +) / Double(week.count)
        if let average, average < 8 {
            return (minutes, "You've averaged \(average.formatted(.number.precision(.fractionLength(1)))) h this week")
        }
        return (minutes, early != nil ? "Early start tomorrow: 9 h of sleep" : "9 h before tomorrow")
    }


    private var daysToNextGame: Int? {
        AthleteStats.upcomingCompetitions(athlete).first.map { AthleteStats.daysUntil($0.date) }
    }

    private var whyThisPlan: String {
        if let explanation = planning.explanation, planning.decision > .modifyOptionalWork { return explanation }
        // V6: the engine's own reason for today's session.
        if let summary = todaysWorkout?.session.explanation?.summary { return summary }
        return DailyLoop.whyThisPlan(status: status, mode: todaysWorkout?.mode, practiceToday: practiceToday, gameToday: gameToday != nil,
                              daysToNextGame: daysToNextGame, readiness: readinessOverridden ? nil : readiness)
    }

    // MARK: - Learning and reflecting

    private var nextLesson: (lesson: CampusLesson, topic: CampusTopic)? {
        let learned = CampusProgress.learned(campusLearnedRaw)
        // A lesson for today's situation first (a short night, a game…).
        let context = LessonPicker.Context(
            sleepHours: todaysCheckIn?.sleepHours, sleepQuality: todaysCheckIn?.sleepQuality, soreness: todaysCheckIn?.soreness,
            energy: todaysCheckIn?.energy, daysToGame: daysToNextGame, pain: PainStore.report() != nil, examWeek: examWeek,
            gameYesterday: LessonSignals.gameYesterday(athlete), hardDayYesterday: LessonSignals.hardDayYesterday(),
            shortNights: LessonSignals.shortNights(athlete), lowConfidence: LessonSignals.lowConfidence(),
            trainingToday: todaysWorkout?.session.decision?.primaryTargets.map(\.rawValue) ?? [],
            inSeason: LessonSignals.inSeason(athlete), learned: learned
        )
        if let pick = LessonPicker.forToday(context), !(learnedToday && learned.contains(pick.id)),
           let found = LessonPicker.lesson(pick.id) { return found }
        for topic in campusTopics {
            if let lesson = topic.lessons.first(where: { !learned.contains($0.id) }) { return (lesson, topic) }
        }
        return nil
    }

    private var learnedToday: Bool {
        _ = campusLearnedRaw
        return briefingReadToday || CampusProgress.newLessonDates().contains { calendar.isDateInToday($0) }
    }

    private func refreshTwinBriefing() {
        let state = AcademyStore.load()
        briefingReadToday = state.read.values.contains { calendar.isDateInToday($0) }
        let report = TwinAnalysis.report(TwinInputBuilder.input(athlete: athlete, state: state))
        twinBriefing = report.insights.compactMap(\.briefing).first { state.read[$0.id] == nil }
    }

    private var reflectedToday: Bool {
        _ = revision
        return MindsetStore.reflection(on: .now) != nil
    }

    private var completion: DayCompletion {
        DayCompletion(checkedIn: todaysCheckIn != nil, trained: loggedToday, learned: learnedToday, reflected: reflectedToday)
    }


    /// Constant fatigue while training hard (see Safety.swift).
    private var lowEnergy: LowEnergyWarning? {
        status == .active ? LowEnergyCheck.current(for: athlete) : nil
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                // Centred and open: the one next step, today's plan under it
                // (docs/CLARITY-PLAN.md); everything else stays compact below.
                VStack(spacing: 56) {
                    VStack(spacing: 22) {
                        topBar
                        header
                        quickBar
                    }
                    if let announcement {
                        AnnouncementCard(announcement: announcement) {
                            TeamAnnouncements.markSeen(announcement.id)
                            withAnimation { self.announcement = nil }
                        }
                    }
                    if let lowEnergy, !lowEnergySnoozed {
                        LowEnergyCard(warning: lowEnergy) {
                            LowEnergyCheck.snoozeForAWeek()
                            lowEnergySnoozed = true
                        }
                    }
                    VStack(spacing: 56) { dayContent }
                        .id(contentKey)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 16)), removal: .opacity))
                    if !scheduleIsSet && status == .active { scheduleCard }
                    if askPrePracticeFuel { prePracticeFuelCard }
                    if loaded { HomeWeekBlock(week: weekSummary, accent: phase.red, plan: weekPlan) }
                }
                .animation(.easeInOut(duration: 0.45), value: contentKey)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            // Home's own backdrop: the hour's light at the top (other tabs stay plain).
            .background(HomeAmbientBackground())
            .contentMargins(.bottom, 24, for: .scrollContent)
            .modifier(ReadableWidth())
            .task {
                // Follows the day: a new part of the day shows up within a minute.
                for _ in 0..<1440 {
                    try? await Task.sleep(for: .seconds(60))
                    if Task.isCancelled { break }
                    clock = .now
                }
            }
            .onChange(of: selectedTab) { _, tab in
                if tab == .today { refreshTwinBriefing() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    clock = .now
                    revision += 1
                    refreshTwinBriefing()
                    announcement = TeamAnnouncements.current
                    switch IntentRoute.take([.checkIn, .reflection]) {
                    case .checkIn?: activeSheet = .checkIn
                    case .reflection?: activeSheet = .reflection
                    default: break
                    }
                }
            }
            // A push or the quiet check: the coach's new workout or note shows up now.
            .onChange(of: LiveUpdates.shared.tick) {
                revision += 1
                announcement = TeamAnnouncements.current
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingCompetitions) {
                CompetitionHubView(athlete: athlete, onChanged: onPlanInputsChanged)
            }
            .sheet(isPresented: $showingTell) {
                TellView(athlete: athlete, onChanged: onPlanInputsChanged)
            }
            .task(id: allSessions.count + athlete.checkIns.count) {
                switch IntentRoute.take([.checkIn, .reflection]) {
                case .checkIn?: activeSheet = .checkIn
                case .reflection?: activeSheet = .reflection
                default: break
                }
                // No prompts tied to streaks (Backend Knowledge System §18):
                // ratings are only asked after a new test best.
                catalogue = CatalogueLoader.load(from: AppConfig.packsDirectory())
                // The record of today's decision (Me → How AthleteOS decides).
                let planningContext = PlanningRules.context(athlete, sessions: allSessions)
                let evaluation = PlanningRules.evaluate(planningContext, disabled: Set(KnowledgeReleaseStore.current.disabledRules))
                DecisionTraceStore.record(evaluation, context: planningContext,
                                          selected: todaysWorkout.map { "\($0.mode.title) · \($0.session.estimatedMinutes) min" }
                                              ?? (evaluation.decision.allowsAddedTraining ? "No workout planned" : "No added workout"))
                status = DayStatusStore.status()
                refreshTwinBriefing()
                if !loaded, DemoData.initialTab == .today, let name = DemoData.initialSheet { activeSheet = HomeSheet(rawValue: name) }
                loaded = true
            }
            .sheet(item: $activeSheet, onDismiss: {
                status = DayStatusStore.status()
                revision += 1
                runPendingAction()
                runPendingSearch()
            }) { sheet in
                switch sheet {
                case .quickActions:
                    QuickActionsSheet { action in
                        pendingAction = action
                        activeSheet = nil
                    }
                    .presentationDetents([.height(420)])
                case .checkIn:
                    CheckInSheet(athlete: athlete)
                case .addGame:
                    AddGameSheet(athlete: athlete, onSaved: onPlanInputsChanged)
                case .history:
                    SessionHistoryView()
                case .fuel:
                    FuelView(athlete: athlete, todaysSession: todaysWorkout?.session)
                case .dayStatus:
                    DayStatusSheet(current: status) { newStatus, days in
                        DayStatusStore.set(newStatus, days: days)
                        status = DayStatusStore.status()
                        activeSheet = nil
                        onPlanInputsChanged()
                    }
                case .tournament:
                    TournamentModeView(onHotelWorkout: { selectedTab = .workout },
                                       onFood: { Task { @MainActor in try? await Task.sleep(for: .milliseconds(600)); activeSheet = .fuel } })
                case .windDown:
                    WindDownView(bedtime: bedtimeTonight.map { Bedtime.label($0.minutes) },
                                 gameTomorrow: athlete.competitions.contains { calendar.isDateInTomorrow($0.date) })
                case .seasonReview:
                    if let sport = athlete.activeSport {
                        SeasonReviewSheet(athlete: athlete, sport: sport, sessions: allSessions)
                    }
                case .safety:
                    SafetyCenterView()
                case .mindset:
                    MindsetView(sportName: AthleteStats.sportName(athlete)) { selectedTab = .academy }
                case .tests:
                    BenchmarksView(sportSlug: athlete.activeSport?.sportSlug)
                case .reflection:
                    ReflectionSheet(completion: completion, practiceToday: practiceToday,
                                    restDay: !loggedToday && !practiceToday && gameToday == nil) { revision += 1 }
                case .search:
                    AppSearchSheet(entries: searchEntries, exercises: searchableExercises) { target in
                        pendingSearch = target
                        activeSheet = nil
                    }
                case .schedule:
                    ScheduleSheet(athlete: athlete) {
                        practiceDays = PracticeSchedule.weekdays
                        scheduleIsSet = PracticeSchedule.isSet
                        onPlanInputsChanged()
                    }
                }
            }
            .sheet(item: $preview) { box in
                SessionPreviewSheet(session: box.session, catalogue: catalogue) {
                    preview = nil
                    liveLaunch = LiveSessionLaunch(planned: box.session, kind: box.kind)
                }
            }
            .fullScreenCover(item: $routine, onDismiss: { revision += 1 }) { routine in
                switch routine {
                case .breathing: BreathingView()
                case .visualization: VisualizationView(sportName: AthleteStats.sportName(athlete))
                }
            }
            .fullScreenCover(item: $liveLaunch) { launch in
                LiveSessionView(athlete: athlete, apiClient: apiClient, planned: launch.planned, kind: launch.kind)
            }
            .sheet(item: $searchDestination, onDismiss: {
                revision += 1
                if let launch = pendingLive {
                    pendingLive = nil
                    liveLaunch = launch
                }
            }) { box in
                searchView(box.target)
            }
            .proFeature(item: $proFeature, athlete: athlete)
            .proPaywall(isPresented: $showingUpgrade, athlete: athlete, feature: .multipleSports)
        }
    }

    // MARK: - Search

    struct SearchBox: Identifiable {
        let id = UUID()
        let target: AppSearchTarget
    }

    /// Everything search can find right now.
    private var searchEntries: [AppSearchEntry] {
        AppSearch.functions + AppSearch.skills(sportInfo) + AppSearch.workoutModes() + AppSearch.gymDays(week)
            + AppSearch.myWorkouts(MyWorkoutsStore.load()) + AppSearch.lessons(learned: CampusProgress.learned(campusLearnedRaw))
    }

    /// General exercises and the drills of the athlete's own sport(s) only.
    private var searchableExercises: [CatalogueItem] {
        let sports = SportVisibility.sports(for: athlete)
        return catalogue.itemsBySlug.values
            .filter { SportVisibility.isVisible($0, sports: sports) }
            .sorted { $0.name < $1.name }
    }

    private func runPendingSearch() {
        guard let target = pendingSearch else { return }
        pendingSearch = nil
        switch target {
        case .checkIn: activeSheet = .checkIn
        case .addGame: activeSheet = .addGame
        case .history: activeSheet = .history
        case .fuel: activeSheet = .fuel
        case .dayStatus: activeSheet = .dayStatus
        case .schedule: activeSheet = .schedule
        case .reflection: activeSheet = .reflection
        case .safety: activeSheet = .safety
        case .mindset: activeSheet = .mindset
        case .tests: activeSheet = .tests
        case .logWorkout: liveLaunch = LiveSessionLaunch(planned: nil)
        case .breathing: routine = .breathing
        case .visualization: routine = .visualization
        case .tab(let tab): selectedTab = tab
        case .lesson(let id):
            CampusLaunch.shared.pendingLessonID = id
            selectedTab = .campus
        case .workoutMode(let mode):
            if let session = searchSession(mode) {
                preview = PreviewBox(session: session, kind: workoutKind(mode))
            } else {
                selectedTab = .workout
            }
        case .gymDay(let index):
            if let sessions = week?.sessions, sessions.indices.contains(index) {
                preview = PreviewBox(session: adjusted(sessions[index]), kind: .gym)
            }
        case .myWorkout(let id):
            if let workout = MyWorkoutsStore.load().first(where: { $0.id == id }) {
                preview = PreviewBox(session: TodaysPain.apply(workout.session(date: .now, catalogue: catalogue), athlete: athlete, catalogue: catalogue),
                                     kind: .gym)
            }
        case .exerciseProgress:
            if ProAccess.isPro { searchDestination = SearchBox(target: target) } else { proFeature = .exerciseProgress }
        case .upgrade: showingUpgrade = true
        case .link(let path): openURL(AppConfig.backendBaseURL.appending(path: path))
        case .newWorkout:
            if ProGate.canKeepAnotherWorkout(isPro: ProAccess.isPro, myWorkoutCount: MyWorkoutsStore.load().count) {
                searchDestination = SearchBox(target: target)
            } else {
                proFeature = .myWorkouts
            }
        default: searchDestination = SearchBox(target: target)
        }
    }

    /// A workout type found in search, built for today like Home's own.
    private func searchSession(_ mode: WorkoutMode) -> GeneratedSession? {
        if mode == .gymDay {
            let planned = week?.sessions.first { calendar.isDateInToday($0.date) } ?? week?.sessions.first
            return planned.map { adjusted($0) }
        }
        return engine(mode)
    }

    @ViewBuilder
    private func searchView(_ target: AppSearchTarget) -> some View {
        switch target {
        case .practiceLog: PracticeLogSheet(athlete: athlete, date: .now)
        case .sports: SportsManagerSheet(athlete: athlete, onChanged: onPlanInputsChanged)
        case .season: SeasonEditorSheet(athlete: athlete, onSaved: onPlanInputsChanged)
        case .equipment: EquipmentEditorSheet(athlete: athlete, onSaved: onPlanInputsChanged)
        case .experience: ExperienceEditorSheet(onSaved: onPlanInputsChanged)
        case .name: NameEditorSheet(athlete: athlete)
        case .reports:
            #if os(iOS)
            ReportsSheet(athlete: athlete, sessions: allSessions, catalogue: catalogue)
            #else
            EmptyView()
            #endif
        case .checkIns: CheckInHistoryView(checkIns: athlete.checkIns)
        case .exerciseProgress: ExerciseProgressListView(sessions: allSessions, catalogue: catalogue)
        case .dataExport: DataExportView(athlete: athlete, sessions: allSessions)
        case .reminders: RemindersSheet(athlete: athlete)
        case .downloads: DownloadsSheet(athlete: athlete)
        case .health: HealthPermissionView()
        case .help: HelpCenterView()
        case .team: MyTeamView()
        case .coach: CoachView()
        case .parent: ParentSummaryView()
        case .goals: StrugglesSheet(onSaved: onPlanInputsChanged)
        case .trends:
            TrendsSheet(athlete: athlete, sessions: allSessions, balance: CoachEngine.muscleBalance(sessions: allSessions.map { session in
                CoachSession(date: session.startedAt, minutes: session.minutes, rpe: session.sessionRPE,
                             sets: session.sets.map { CoachSet(itemSlug: $0.itemSlug, reps: $0.reps, weightKg: $0.weightKg) })
            }, catalogue: catalogue))
        case .library: LibraryView(athlete: athlete)
        case .sportGuide: SportGuideView(athlete: athlete)
        case .support: SupportSheet()
        case .newGymPlan: NewGymPlanSheet(athlete: athlete, gymDays: week?.sessions.count ?? 3, onChanged: onPlanInputsChanged)
        case .skillPlans: ImproveView(athlete: athlete, apiClient: apiClient, onPlanInputsChanged: onPlanInputsChanged)
        case .skill(let slug):
            ImproveView(athlete: athlete, apiClient: apiClient, onPlanInputsChanged: onPlanInputsChanged, initialSkillSlug: slug)
        case .muscleWorkouts:
            ImproveView(athlete: athlete, apiClient: apiClient, onPlanInputsChanged: onPlanInputsChanged, initialMode: .muscles)
        case .planSettings: PlanSettingsSheet(onChanged: onPlanInputsChanged)
        case .newWorkout:
            WorkoutEditorView(heading: "New workout", workout: CustomWorkout(title: "My workout", items: []),
                              sportSlug: athlete.activeSport?.sportSlug) { saved in
                MyWorkoutsStore.upsert(saved)
            }
        case .addWithCode:
            SharedWorkoutSheet(onSaved: { MyWorkoutsStore.upsert($0) }, onStart: { workout in
                pendingLive = LiveSessionLaunch(planned: workout.session(date: .now, catalogue: catalogue), kind: .gym)
            })
        case .addTraining: ExtraPracticeSheet { onPlanInputsChanged() }
        case .calendars: ScheduleSheet(athlete: athlete, onChanged: onPlanInputsChanged)
        case .sportPosition: SportEditorSheet(athlete: athlete, onSaved: onPlanInputsChanged)
        default: EmptyView()
        }
    }

    private func runPendingAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        switch action {
        case .logWorkout: liveLaunch = LiveSessionLaunch(planned: nil)
        case .addGame: activeSheet = .addGame
        case .fuel: activeSheet = .fuel
        }
    }

    // MARK: - Top

    /// Small floating glass controls: the kind of day, search, "+".
    private var topBar: some View {
        HStack(spacing: 8) {
            ProfileButton(name: athlete.displayName)
            Button { activeSheet = .dayStatus } label: {
                HStack(spacing: 7) {
                    Image(systemName: status.systemImage)
                        .foregroundStyle(status == .active ? AppTheme.secondaryText : phase.red)
                    Text(status.title)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.mutedText)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .glassCapsule()
            }
            .buttonStyle(.plain)
            .fixedSize()
            .layoutPriority(1)
            Spacer(minLength: 4)
            .accessibilityLabel("Today is: \(status.title). Change what kind of day it is.")
            searchButton
            Button { activeSheet = .quickActions } label: {
                Image(systemName: "plus")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .glassCapsule()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add: log a workout, add a game, or food and water")
        }
    }

    /// Two ways in: tell the app what's going on in your own words, and the
    /// next competition with its countdown.
    private var quickBar: some View {
        let next = AthleteStats.upcomingCompetitions(athlete).first
        let family = AcademyContent.family(forSport: athlete.activeSport?.sportSlug)
        return HStack(spacing: 10) {
            Button { showingTell = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(AppTheme.brightRed)
                    Text("Tell AthleteOS…")
                        .foregroundStyle(AppTheme.secondaryText)
                    Spacer(minLength: 0)
                }
                .font(.subheadline)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 44)
                .glassSurface(cornerRadius: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tell AthleteOS what's going on")
            Button { showingCompetitions = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(AppTheme.yellow)
                    if let next {
                        let days = AthleteStats.daysUntil(next.date)
                        Text(days == 0 ? "Today" : days == 1 ? "Tomorrow" : "\(days) d")
                            .font(.telemetry(13, weight: .medium))
                            .foregroundStyle(AppTheme.ink)
                    } else {
                        Text(family.tokens["Events"] ?? "Games")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .glassSurface(cornerRadius: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(next.map { "Next \(family.event) in \(AthleteStats.daysUntil($0.date)) days. Results and plan." } ?? "\(family.tokens["Events"] ?? "Games"): results and plan")
        }
    }

    /// Search everything: fills the space between the day and the "+".
    private var searchButton: some View {
        Button { activeSheet = .search } label: {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.85))
                .frame(width: 40, height: 40)
                .glassCapsule()
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search")
        .accessibilityHint("Find any part of the app, a workout, a lesson or an exercise")
    }

    private var firstName: String? {
        guard let name = athlete.displayName?.split(separator: " ").first, !name.isEmpty else { return nil }
        return String(name)
    }

    private var greeting: String {
        firstName.map { "\(phase.greeting), \($0)" } ?? phase.greeting
    }

    // MARK: - The part of the day (V4)

    /// Refreshed every minute and when the app comes back, so Home follows the day.
    private var phase: DayPhase { DayPhase.at(clock) }

    private var todaysSessions: [Session] { allSessions.filter { calendar.isDateInToday($0.startedAt) } }
    private var workoutDoneToday: Bool { todaysSessions.contains { SessionKinds.kind(of: $0.clientId) != .mobility } }
    private var mobilityDoneToday: Bool { todaysSessions.contains { SessionKinds.kind(of: $0.clientId) == .mobility } }
    private var practiceLogToday: PracticeLog? {
        _ = revision
        return PracticeLogStore.log(on: DayKey.of(.now), sportSlug: athlete.activeSport?.sportSlug)
    }

    private var weekPlan: WeekPlanProgress {
        let summary = weekSummary
        return WeekPlanProgress(workoutsPlanned: week?.sessions.count ?? 0, workoutsDone: summary.workouts,
                                practicesPlanned: practiceDays.count, practicesDone: summary.practices)
    }

    private var weekSummary: WeekSummary {
        _ = revision
        return WeekSummary.make(
            now: clock,
            sessions: allSessions.map { (date: $0.startedAt, mobility: SessionKinds.kind(of: $0.clientId) == .mobility) },
            practiceDays: PracticeLogStore.logs.map(\.day),
            checkInDates: athlete.checkIns.map(\.date)
        )
    }

    private var minuteNow: Int {
        calendar.component(.hour, from: clock) * 60 + calendar.component(.minute, from: clock)
    }

    /// The day's fixed point: the game, else team practice, with the times the athlete gave.
    private var fixedPoint: TodayPlan.FixedPoint? {
        guard status == .active else { return nil }
        if let game = gameToday {
            let start = FuelEngine.gameStart(game.date, usualMinutes: gameStartMinutes, calendar: calendar)
            return .init(kind: .game, start: calendar.component(.hour, from: start) * 60 + calendar.component(.minute, from: start))
        }
        guard practiceToday else { return nil }
        if let event = practicesToday.first(where: { !$0.cancelled }), !event.allDay {
            let start = calendar.component(.hour, from: event.start) * 60 + calendar.component(.minute, from: event.start)
            var end: Int?
            if let finish = event.end, calendar.isDate(finish, inSameDayAs: event.start), finish > event.start {
                end = calendar.component(.hour, from: finish) * 60 + calendar.component(.minute, from: finish)
            }
            return .init(kind: .practice, start: start, end: end)
        }
        if let time = PracticeSchedule.time(on: .now) {
            return .init(kind: .practice, start: time.start, end: time.end > time.start ? time.end : nil)
        }
        return .init(kind: .practice, start: nil)
    }

    /// Today as a numbered plan and the one step that is next (TodayPlan.swift).
    private var todayPlan: TodayPlan {
        TodayPlan.make(.init(minute: minuteNow, checkedIn: todaysCheckIn != nil, reflected: reflectedToday, learned: learnedToday,
                             lessonAvailable: twinBriefing != nil || nextLesson != nil, fixed: fixedPoint, workoutPlanned: todaysWorkout != nil,
                             workoutDone: workoutDoneToday, practiceLogged: practiceLogToday != nil, sick: status == .sick))
    }

    /// What's on screen, so a change (a check-in, a finished workout, the
    /// evening) animates in instead of jumping.
    private var contentKey: String {
        "\(todayPlan.next.key)-\(status.rawValue)"
    }

    /// The season the active sport is in ("IN SEASON").
    private var seasonLine: String? {
        guard let sport = athlete.activeSport else { return nil }
        let phase = PhaseCalculator.phase(today: clock, seasonStart: sport.seasonStart, seasonEnd: sport.seasonEnd)
        switch phase {
        case .offSeason: return "Off-season"
        case .preSeason: return "Pre-season"
        case .inSeason: return "In season"
        case .postSeason: return "Post-season"
        }
    }

    /// An editorial opening: the greeting small, the name huge, the season,
    /// a short quote. No box around any of it.
    private var header: some View {
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: phase.systemImage)
                        .foregroundStyle(phase.red)
                        .symbolRenderingMode(.hierarchical)
                    Text(phase.greeting)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .font(.footnote.weight(.semibold))
                Text(firstName ?? clock.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 46, weight: .bold))
                    .tracking(-1)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                Text(clock.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.telemetry(12))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            // Streaks live on Progress and Me now (V6 §21: secondary).
            HStack(spacing: 10) {
                SportSwitcher(athlete: athlete, onChanged: onPlanInputsChanged)
                if let seasonLine {
                    Text(seasonLine)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(phase.red.opacity(0.9))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - The day: one next step, then the plan (docs/CLARITY-PLAN.md)

    @ViewBuilder
    private var dayContent: some View {
        if !loaded {
            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
        } else if status == .concussion {
            pausedCard
        } else {
            let plan = todayPlan
            switch plan.next {
            case .dayComplete:
                dayCompleteView
                alsoToday
            case .sleep:
                nightView
            default:
                // What to do now, then the whole day in order.
                VStack(spacing: 30) {
                    nextStepHero(plan.next)
                    VStack(spacing: 12) {
                        painNote
                        planPanel(plan)
                        whySection
                    }
                }
                alsoToday
            }
        }
    }

    /// The one thing to do now — or, when nothing is, what the day is waiting for.
    @ViewBuilder
    private func nextStepHero(_ next: TodayPlan.Next) -> some View {
        switch next {
        case .checkIn: checkInHero
        case .game: gameHero
        case .workout: workoutHero
        case .lesson: lessonHero
        case .reflection: reflectionHero
        case .waiting(let reason): waitingHero(reason)
        case .dayComplete, .sleep: EmptyView()
        }
    }

    // The check-in opens the day: the plan is built from it.

    private var checkInHero: some View {
        VStack(spacing: 12) {
            NextStepEyebrow("Start here · check-in", accent: phase.red)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("30")
                    .font(.system(size: 82, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.ink)
                Text("sec")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .background(HeroBloom(color: phase.red))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("30 seconds")
            Text("Sleep · Energy · Body · Mood")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
            Button { activeSheet = .checkIn } label: { HeroCTALabel("Check in") }
                .buttonStyle(.primary)
                .padding(.top, 10)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var painNote: some View {
        if let pain = PainStore.report() {
            Button { activeSheet = .safety } label: {
                Label(pain.involvesHead ? "Hit your head? Stop training and tell an adult."
                      : pain.areas.contains(.other) ? "Pain reported · only gentle mobility today"
                      : "Pain reported · today's workout leaves it alone",
                      systemImage: "bandage.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.coral)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                    .background(AppTheme.coral.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
    }

    // The heroes: the title and the number dominate.

    @ViewBuilder
    private var gameHero: some View {
        if let game = gameToday {
            VStack(spacing: 14) {
                NextStepEyebrow("Game day", accent: phase.red)
                heroTitle(gameTitle(game))
                clockNumber(game.date)
                heroMeta(game.isHome ? "Home" : "Away")
                Button { activeSheet = .fuel } label: { HeroCTALabel("What to eat before") }
                    .buttonStyle(.primary)
                    .padding(.top, 6)
                    .frame(maxWidth: 300)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var workoutHero: some View {
        if let workout = todaysWorkout {
            let session = workout.session
            VStack(spacing: 14) {
                NextStepEyebrow("Next step · training", accent: phase.red)
                Button { preview = PreviewBox(session: session, kind: workoutKind(workout.mode)) } label: {
                    heroTitle(focusTitle(session, mode: workout.mode))
                }
                .buttonStyle(.plain)
                bigNumber("\(session.estimatedMinutes)", unit: "min")
                if let qualities = qualityLine(session) {
                    heroMeta(qualities)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    if session.decision == nil {
                        GlassMetric(value: "\(session.items.count)", label: "Exercises", height: 86)
                    }
                    GlassMetric(value: loadWord, label: "Load", height: 70, accent: readinessBand == nil ? nil : phase.red)
                    if let tag = focusTag, tag != "LIGHTER TODAY" {
                        GlassMetric(value: tag.capitalized, label: "Note", height: 70)
                    }
                }
                .frame(maxWidth: 380)
                .padding(.top, 4)
                Button { liveLaunch = LiveSessionLaunch(planned: session, kind: workoutKind(workout.mode)) } label: {
                    HeroCTALabel("Start training")
                }
                .buttonStyle(.primary)
                .padding(.top, 8)
                .frame(maxWidth: 300)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Nothing to train right now: a few minutes of Campus are the next step.
    @ViewBuilder
    private var lessonHero: some View {
        if let briefing = twinBriefing {
            VStack(spacing: 14) {
                NextStepEyebrow("Next step · read", accent: phase.red)
                Button { openLesson() } label: { heroTitle(briefing.title) }
                    .buttonStyle(.plain)
                bigNumber("\(briefing.minutes)", unit: "min")
                heroMeta("Your coach assigned it from your twin")
                Button { openLesson() } label: { HeroCTALabel("Read") }
                    .buttonStyle(.primary)
                    .padding(.top, 6)
                    .frame(maxWidth: 300)
            }
            .frame(maxWidth: .infinity)
        } else if let next = nextLesson {
            VStack(spacing: 14) {
                NextStepEyebrow("Next step · learn", accent: phase.red)
                Button { openLesson() } label: { heroTitle(next.lesson.title) }
                    .buttonStyle(.plain)
                bigNumber("\(next.lesson.minutes)", unit: "min")
                heroMeta(next.topic.title)
                Button { openLesson() } label: { HeroCTALabel("Start lesson") }
                    .buttonStyle(.primary)
                    .padding(.top, 6)
                    .frame(maxWidth: 300)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Today's lesson, opened in Campus (the tab alone once it is learned).
    private func openLesson() {
        if let briefing = twinBriefing {
            AcademyNavigation.shared.page = .twin
            AcademyNavigation.shared.pendingBriefingID = briefing.id
            selectedTab = .academy
            return
        }
        if !learnedToday, let next = nextLesson { CampusLaunch.shared.pendingLessonID = next.lesson.id }
        selectedTab = .campus
    }

    private var reflectionHero: some View {
        VStack(spacing: 12) {
            NextStepEyebrow("Next step · reflect", accent: phase.red)
            Text("How did today actually feel?")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.center)
                .background(HeroBloom(color: phase.red))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("45")
                    .font(.system(size: 60, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.ink)
                Text("sec")
                    .font(.headline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("45 seconds")
            Button { activeSheet = .reflection } label: { HeroCTALabel("Reflect") }
                .buttonStyle(.primary)
                .padding(.top, 6)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
    }

    /// Nothing to do right now, said plainly — never a made-up task.
    private func waitingHero(_ reason: TodayPlan.Waiting) -> some View {
        VStack(spacing: 14) {
            switch reason {
            case .practice:
                HomeEyebrow((fixedPoint?.hasBegun(at: minuteNow) ?? false) ? "Now" : "Up next")
                heroTitle("Team practice")
                if let start = practiceStart { clockNumber(start) }
                heroMeta(todaysWorkout != nil && !workoutDoneToday ? "Your training comes after practice." : "Your sport's training")
            case .restDay:
                HomeEyebrow("Today")
                heroTitle("Rest day")
                heroMeta("Recovery is part of the plan.")
            case .recover:
                HomeEyebrow("Today")
                heroTitle("Rest and recover")
                heroMeta("No training today. Drink, eat, sleep.")
            case .reflectTonight:
                HomeEyebrow("Today")
                heroTitle(workoutDoneToday ? "Training done" : "Done for now")
                heroMeta("Reflect tonight. It takes 45 seconds.")
            case .clear:
                HomeEyebrow("Today")
                heroTitle("You're set")
                heroMeta("Nothing else is planned today.")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var loadWord: String {
        if readinessBand != nil { return "Lighter" }
        if status != .active { return "Optional" }
        return "Normal"
    }

    private func heroTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 42, weight: .bold))
            .tracking(-0.6)
            .foregroundStyle(AppTheme.ink)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .background(HeroBloom(color: phase.red))
    }

    /// The big number: 60–82 pt, its unit small beside it.
    private func bigNumber(_ value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(.system(size: 76, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(AppTheme.ink)
                .contentTransition(.numericText())
            if !unit.isEmpty {
                Text(unit)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A time of day as the big number ("4:30" with a small "PM").
    private func clockNumber(_ date: Date) -> some View {
        bigNumber(date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()),
                  unit: date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated))).filter(\.isLetter).uppercased())
    }

    private func heroMeta(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(AppTheme.secondaryText)
            .multilineTextAlignment(.center)
    }

    /// The workout's focus in words: its main quality ("Rotational power").
    private func focusTitle(_ session: GeneratedSession, mode: WorkoutMode) -> String {
        if session.decision != nil { return session.title }
        return session.focusQualities.first.flatMap { qualitiesBySlug[$0]?.name } ?? mode.title
    }

    private func qualityLine(_ session: GeneratedSession) -> String? {
        if let decision = session.decision {
            let line = decision.primaryTargets.prefix(3).map(\.title).joined(separator: " · ")
            return line.isEmpty ? nil : line.prefix(1).uppercased() + line.dropFirst()
        }
        var seen: Set<String> = []
        let names = session.focusQualities.compactMap { qualitiesBySlug[$0]?.shortName }.filter { seen.insert($0).inserted }
        return names.count > 1 ? names.prefix(3).joined(separator: " · ") : nil
    }

    private var focusTag: String? {
        if readinessBand != nil { return "LIGHTER TODAY" }
        if examWeek { return "EXAM WEEK" }
        if status != .active { return "OPTIONAL" }
        return nil
    }

    private func gameTitle(_ game: Competition) -> String {
        game.kind == .tournament ? "Tournament" : (game.kind == .meet ? "Meet" : "Game")
    }

    // Today's plan: every step of the day in order, the next one lit.

    private func planPanel(_ plan: TodayPlan) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Today's plan")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("\(plan.doneCount) of \(plan.total) done")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(.bottom, 10)
            ForEach(plan.rows) { row in
                Divider().opacity(0.4)
                planRow(row)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .glassSurface()
        .frame(maxWidth: 520)
    }

    @ViewBuilder
    private func planRow(_ row: TodayPlan.Row) -> some View {
        let text = planText(row)
        if row.step == .rest {
            PlanStepRow(row: row, title: text.title, detail: text.detail, accent: phase.red, showsChevron: false)
        } else {
            Button { open(row.step) } label: {
                PlanStepRow(row: row, title: text.title, detail: text.detail, accent: phase.red)
            }
            .buttonStyle(.plain)
        }
    }

    /// What a step is called, and the few words on its right.
    private func planText(_ row: TodayPlan.Row) -> (title: String, detail: String?) {
        let done = row.state == .done
        switch row.step {
        case .checkIn:
            return ("Check-in", done ? readiness?.level.title : "30 sec")
        case .game:
            guard let game = gameToday else { return ("Game", nil) }
            return (gameTitle(game), game.date.formatted(date: .omitted, time: .shortened))
        case .practice:
            if practiceLogToday != nil { return ("Team practice", "Logged") }
            if done { return ("Team practice", "Log it") }
            return ("Team practice", practiceStart?.formatted(date: .omitted, time: .shortened))
        case .workout:
            guard let workout = todaysWorkout else { return ("Workout", nil) }
            return (focusTitle(workout.session, mode: workout.mode), done ? nil : "\(workout.session.estimatedMinutes) min")
        case .rest:
            return (status == .sick ? "Rest and recover" : "Rest day", nil)
        case .lesson:
            if !done, let briefing = twinBriefing { return (briefing.title, "\(briefing.minutes) min read") }
            guard !done, let next = nextLesson else { return ("Lesson", nil) }
            return (next.lesson.title, "\(next.lesson.minutes) min")
        case .reflection:
            return ("Reflection", done ? nil : (minuteNow >= TodayPlan.eveningStart ? "45 sec" : "Tonight"))
        }
    }

    /// A tap on a step does it, or shows what was done.
    private func open(_ step: TodayPlan.Step) {
        switch step {
        case .checkIn: activeSheet = .checkIn
        case .game: activeSheet = .fuel
        case .practice:
            if practiceLogToday != nil || (fixedPoint?.hasBegun(at: minuteNow) ?? false) {
                searchDestination = SearchBox(target: .practiceLog)
            } else {
                activeSheet = .schedule
            }
        case .workout:
            if workoutDoneToday { activeSheet = .history } else if let workout = todaysWorkout {
                preview = PreviewBox(session: workout.session, kind: workoutKind(workout.mode))
            }
        case .lesson: openLesson()
        case .reflection: activeSheet = .reflection
        case .rest: break
        }
    }

    // Extras for today: compact, never competing with the next step.

    @ViewBuilder
    private var alsoToday: some View {
        let rows = alsoRows
        if !rows.isEmpty {
            VStack(spacing: 6) {
                HomeEyebrow("Also today")
                VStack(spacing: 0) {
                    ForEach(rows.indices, id: \.self) { index in
                        rows[index]
                        if index < rows.count - 1 { Divider().opacity(0.5) }
                    }
                }
            }
        }
    }

    /// Today's drills from the athlete's saved skill plans.
    private var skillPlanDays: [SkillPlanDay] {
        guard !catalogue.itemsBySlug.isEmpty else { return [] }
        return SavedSkillPlans.days(on: .now, athlete: athlete, catalogue: catalogue)
    }

    private var alsoRows: [AnyView] {
        var rows: [AnyView] = []
        if isTrainingDay {
            for assignment in CoachAssignments.today() {
                rows.append(AnyView(HomeDetailRow(systemImage: "megaphone.fill", color: AppTheme.brand, title: assignment.title) {
                    startButton { liveLaunch = LiveSessionLaunch(planned: CoachAssignments.session(assignment, catalogue: catalogue), kind: .coach) }
                }))
            }
        }
        // Saved skill plans: today's drills (the sport-first part of the day).
        if isTrainingDay {
            for day in skillPlanDays {
                rows.append(AnyView(Button { preview = PreviewBox(session: day.session) } label: {
                    HomeDetailRow(systemImage: "target", color: AppTheme.orange, title: "\(day.skillName) drills") {
                        Text("\(day.session.items.count) drills · \(day.session.estimatedMinutes) min")
                    }
                }.buttonStyle(.plain)))
            }
        }
        // Game day: the head and the fuel, one row each.
        if gameToday != nil && status == .active && phase != .night {
            rows.append(AnyView(Button { routine = .breathing } label: {
                HomeDetailRow(systemImage: "wind", color: AppTheme.purple, title: "Get your head ready") { Text("2 min") }
            }.buttonStyle(.plain)))
        }
        if let tips = gameFuelTips, let next = tips.first(where: { ($0.time ?? .distantFuture) > .now }) ?? tips.first {
            rows.append(AnyView(Button { activeSheet = .fuel } label: {
                HomeDetailRow(systemImage: "fork.knife", color: AppTheme.green, title: next.title) {
                    Text(next.time?.formatted(date: .omitted, time: .shortened) ?? "Game-day fuel")
                }
            }.buttonStyle(.plain)))
        }
        if status == .travel {
            rows.append(AnyView(Button { activeSheet = .tournament } label: {
                HomeDetailRow(systemImage: "airplane", color: AppTheme.ink, title: "Tournament & travel") { Text("Tips") }
            }.buttonStyle(.plain)))
        }
        if SeasonReviewStore.due(athlete) != nil {
            rows.append(AnyView(Button { activeSheet = .seasonReview } label: {
                HomeDetailRow(systemImage: "flag.checkered", color: AppTheme.ink, title: "Your season review") { Text("3 min") }
            }.buttonStyle(.plain)))
        }
        if let movementPrep = movementPrep {
            rows.append(AnyView(Button { preview = PreviewBox(session: movementPrep, kind: .mobility) } label: {
                HomeDetailRow(systemImage: "figure.flexibility", color: AppTheme.cyan, title: movementPrep.title) {
                    if mobilityDoneToday { Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.green) } else { Text("\(movementPrep.estimatedMinutes) min") }
                }
            }.buttonStyle(.plain)))
        }
        return rows
    }

    /// The reason stays one tap away: today's readiness (a word and its
    /// scale, never a number) and why the plan looks like this.
    @ViewBuilder
    private var whySection: some View {
        if todaysCheckIn != nil || todaysWorkout != nil || gameToday != nil {
            VStack(spacing: 10) {
                Button { withAnimation(.easeInOut(duration: 0.35)) { showingWhy.toggle() } } label: {
                    HStack(spacing: 6) {
                        Text("Why this plan?")
                        Image(systemName: showingWhy ? "chevron.up" : "chevron.down").font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                if showingWhy {
                    if todaysCheckIn != nil, let readiness = readiness {
                        VStack(spacing: 8) {
                            Text("Readiness: \(readiness.level.title)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                            ReadinessScale(level: readiness.level)
                                .frame(maxWidth: 240)
                        }
                    }
                    Text(whyLines.joined(separator: "\n\n"))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                    if readinessBand != nil, todaysWorkout != nil {
                        Button("Train as planned instead") { readinessOverridden = true }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                            .frame(minHeight: 44)
                    } else if readinessOverridden {
                        Button("Use the lighter plan") { readinessOverridden = false }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                            .frame(minHeight: 44)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// What the check-in said, then why the plan looks like this (once, when both say the same).
    private var whyLines: [String] {
        var lines: [String] = []
        if todaysCheckIn != nil, let reason = readiness?.reason, !reason.isEmpty { lines.append(reason) }
        let plan = whyThisPlan
        if !lines.contains(plan) { lines.append(plan) }
        return lines
    }

    /// After the reflection: a poster, not a dashboard. Done, one note,
    /// tomorrow, sleep.
    private var dayCompleteView: some View {
        VStack(spacing: 44) {
            VStack(spacing: 14) {
                Text("Day complete")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .background(HeroBloom(color: phase.red))
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(phase.red)
                    .frame(width: 60, height: 60)
                    .glassCapsule()
                    .overlay { Circle().strokeBorder(phase.red.opacity(0.55), lineWidth: 1) }
                    .shadow(color: phase.red.opacity(0.4), radius: 14)
                    .accessibilityHidden(true)
                let rows = doneRows
                if !rows.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(rows, id: \.title) { row in
                            GlassMetric(value: row.value.replacingOccurrences(of: " min", with: ""), label: row.title,
                                        height: 70, accent: row.color)
                        }
                    }
                    .frame(maxWidth: 400)
                    .padding(.top, 8)
                }
            }
            if let note = todaysNote {
                VStack(spacing: 8) {
                    HomeEyebrow("Today's note")
                    Text(note)
                        .font(.title3)
                        .foregroundStyle(AppTheme.ink.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                }
            }
            if let tomorrow = tomorrowLine {
                VStack(spacing: 6) {
                    HomeEyebrow("Tomorrow")
                    Text(tomorrow.title.uppercased())
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.center)
                    if let detail = tomorrow.detail {
                        Text(detail.uppercased())
                            .font(.footnote.weight(.semibold))
                            .tracking(1.5)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }
            VStack(spacing: 14) {
                Text(firstName.map { "Sleep well, \($0)." } ?? "Sleep well.")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                if let bedtime = bedtimeTonight {
                    Text("Bed by \(Bedtime.label(bedtime.minutes))")
                        .font(.caption.weight(.bold))
                        .tracking(1.8)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Button { activeSheet = .windDown } label: { HeroCTALabel("Wind down") }
                    .buttonStyle(.secondary)
                    .frame(maxWidth: 240)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// After midnight without a finished day: nothing to do but sleep.
    private var nightView: some View {
        VStack(spacing: 12) {
            HomeEyebrow("It's late")
            Text("Sleep is training too.")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.center)
            Text("Everything else can wait until morning.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
            Button { activeSheet = .windDown } label: { Label("Wind down", systemImage: "wind") }
                .buttonStyle(.secondary)
                .frame(maxWidth: 260)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private struct DoneRow {
        let icon: String
        let color: Color
        let title: String
        let value: String
    }

    private var doneRows: [DoneRow] {
        var rows: [DoneRow] = []
        if let log = practiceLogToday {
            rows.append(DoneRow(icon: "person.3.fill", color: AppTheme.orange, title: "Practice", value: log.minutes.map { "\($0) min" } ?? "Logged"))
        }
        let workoutMinutes = todaysSessions.filter { SessionKinds.kind(of: $0.clientId) != .mobility }.reduce(0) { $0 + $1.minutes }
        if workoutDoneToday { rows.append(DoneRow(icon: "dumbbell.fill", color: AppTheme.red, title: "Workout", value: "\(workoutMinutes) min")) }
        let mobilityMinutes = todaysSessions.filter { SessionKinds.kind(of: $0.clientId) == .mobility }.reduce(0) { $0 + $1.minutes }
        if mobilityDoneToday { rows.append(DoneRow(icon: "figure.flexibility", color: AppTheme.water, title: "Mobility", value: "\(mobilityMinutes) min")) }
        if learnedToday { rows.append(DoneRow(icon: "graduationcap.fill", color: AppTheme.purple, title: "Campus", value: "Lesson done")) }
        return rows
    }

    /// One sentence from tonight's reflection — what tomorrow's plan takes from it.
    private var todaysNote: String? {
        _ = revision
        guard let reflection = MindsetStore.reflection(on: .now) else { return nil }
        if (reflection.body ?? 0) >= 4 { return "Something hurt today. Tell a coach or parent, and add it in tomorrow's check-in." }
        if (reflection.hardness ?? 0) >= 3 || (reflection.body ?? 0) >= 3 {
            return "Today felt harder than usual. Tomorrow's plan will account for it."
        }
        if let practice = reflection.practice, practice >= 3 { return "A good practice. Tomorrow builds on it." }
        return "A steady day. Tomorrow builds on it."
    }

    /// Tomorrow's first thing: a game, practice, a gym day or rest.
    private var tomorrowLine: (title: String, detail: String?)? {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: clock) else { return nil }
        if let game = athlete.competitions.first(where: { calendar.isDate($0.date, inSameDayAs: tomorrow) }) {
            return (gameTitle(game), game.date.formatted(date: .omitted, time: .shortened))
        }
        if PracticeSchedule.hasPractice(on: tomorrow) {
            return ("Team practice", PracticeSchedule.time(on: tomorrow).map(\.label))
        }
        if let gym = week?.sessions.first(where: { calendar.isDate($0.date, inSameDayAs: tomorrow) }) {
            return ("Gym day", "\(gym.estimatedMinutes) min")
        }
        return ("Rest day", "Recovery is part of the plan.")
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("When is practice?")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Text("Your plan is built around it.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
            Button("Set up my schedule") { activeSheet = .schedule }
                .buttonStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 20)
    }

    private var practiceStart: Date? {
        if let event = practicesToday.first(where: { !$0.cancelled }), !event.allDay { return event.start }
        guard let time = PracticeSchedule.time(on: .now) else { return nil }
        return calendar.date(bySettingHour: time.start / 60, minute: time.start % 60, second: 0, of: .now)
    }

    private func startButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Start")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.onAccent)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(AppTheme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func workoutKind(_ mode: WorkoutMode) -> WorkoutKind {
        switch mode {
        case .afterPractice: .afterPractice
        case .gymDay: .gym
        case .mobility: .mobility
        case .travel: .travel
        }
    }

    /// A head injury pauses everything until a doctor clears the athlete.
    private var pausedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Training paused", systemImage: "pause.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Text("Until a doctor clears you after the head injury.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
            Button("Safety Center") { activeSheet = .safety }
                .buttonStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 20)
    }

    /// Game day: get the head ready too.

}

/// `GeneratedSession` isn't Identifiable; this wraps one for `.sheet(item:)`.
struct PreviewBox: Identifiable {
    let id = UUID()
    let session: GeneratedSession
    var kind: WorkoutKind? = nil
    /// Where the workout comes from, so it can be edited: a planned workout…
    var slot: PlanSlot? = nil
    /// …or one of the athlete's own.
    var myWorkoutID: UUID? = nil
}


/// "What kind of day is it?" — each option says what the app does about it.
struct DayStatusSheet: View {
    let current: DayStatus
    let onSave: (DayStatus, Int?) -> Void
    @State private var choice: DayStatus = .active
    @State private var days: Int? = 1
    @Environment(\.dismiss) private var dismiss

    private let lengths: [(String, Int?)] = [("Just today", 1), ("3 days", 3), ("A week", 7), ("Two weeks", 14), ("Until I change it", nil)]

    var body: some View {
        StepScaffold(title: "What kind of day is it?", subtitle: "Your plan and reminders follow it.",
                     onClose: { dismiss() }, onConfirm: { onSave(choice, choice == .active ? nil : days) }) {
            VStack(spacing: 10) {
                ForEach(DayStatus.menu) { status in
                    Button { choice = status } label: {
                        OptionRow(title: status.title, subtitle: status.explanation, systemImage: status.systemImage, isSelected: choice == status)
                    }
                    .buttonStyle(.plain)
                }
            }
            if choice != .active {
                VStack(alignment: .leading, spacing: 10) {
                    Text("For how long?")
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.ink)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                        ForEach(lengths.indices, id: \.self) { index in
                            Button { days = lengths[index].1 } label: { Chip(lengths[index].0, isSelected: days == lengths[index].1) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .onAppear { choice = DayStatus.menu.contains(current) ? current : .active }
    }
}

/// The athlete's team-practice days.
struct PracticeDaysSheet: View {
    @State var selection: Set<Int>
    let onSave: (Set<Int>) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        StepScaffold(title: "Your practice days", subtitle: "Tap every day you have team practice. Practice days get a short after-practice workout; gym days go on the others.",
                     onClose: { dismiss() }, onConfirm: { onSave(selection) }) {
            let calendar = Calendar.current
            // Monday first.
            let order = [2, 3, 4, 5, 6, 7, 1]
            VStack(spacing: 10) {
                ForEach(order, id: \.self) { weekday in
                    Button {
                        if selection.contains(weekday) { selection.remove(weekday) } else { selection.insert(weekday) }
                    } label: {
                        OptionRow(title: calendar.weekdaySymbols[weekday - 1], subtitle: selection.contains(weekday) ? "Practice" : "No practice",
                                  systemImage: selection.contains(weekday) ? "sportscourt.fill" : "circle", isSelected: selection.contains(weekday))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// A workout's exercises in order, with the Start button.
struct SessionPreviewSheet: View {
    let session: GeneratedSession
    let catalogue: Catalogue
    let onStart: () -> Void
    /// Offered when the workout can be changed / shared.
    var onEdit: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil
    @State private var detailItem: CatalogueItem?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let explanation = session.explanation {
                        PlanHero(session: session, explanation: explanation)
                        BlockedSessionList(session: session, catalogue: catalogue) { detailItem = $0 }
                        WhyThisPlanPanel(explanation: explanation)
                    } else {
                        Text("Do them in this order. Tap one to watch how it's done.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                        ForEach(Array(session.items.enumerated()), id: \.element.order) { index, item in
                            row(item, number: index + 1)
                        }
                    }
                    Button { onStart() } label: { Label("Start", systemImage: "play.fill") }
                        .buttonStyle(.primary)
                        .padding(.top, 8)
                    if onEdit != nil || onShare != nil {
                        ButtonRow {
                            if let onEdit {
                                Button { onEdit() } label: { Label("Change it", systemImage: "slider.horizontal.3") }
                                    .buttonStyle(.secondary)
                            }
                            if let onShare {
                                Button { onShare() } label: { Label("Share", systemImage: "qrcode") }
                                    .buttonStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .appScreen()
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CloseToolbarItem { dismiss() }
            }
            .sheet(item: $detailItem) { item in
                NavigationStack { ItemDetailView(item: item, closes: true) }
            }
        }
    }

    private func row(_ item: GeneratedPlannedItem, number: Int) -> some View {
        let catalogueItem = catalogue.item(item.itemSlug)
        return Button { detailItem = catalogueItem } label: {
            HStack(spacing: 14) {
                ItemThumbnail(item: catalogueItem)
                    .overlay(alignment: .topLeading) {
                        Text("\(number)")
                            .font(.caption2.bold())
                            .foregroundStyle(AppTheme.onAccent)
                            .frame(width: 22, height: 22)
                            .background(AppTheme.accent, in: Circle())
                            .offset(x: -6, y: -6)
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text(catalogueItem?.name ?? displayName(forSlug: item.itemSlug))
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.leading)
                    Text(DoseFormatter.text(item.dose))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.ink)
                    if !item.rationale.isEmpty {
                        Text(item.rationale)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .cardStyle(padding: 12)
        }
        .buttonStyle(.plain)
        .disabled(catalogueItem == nil)
    }
}



/// A one-way message from the coach, until the athlete closes it.
struct AnnouncementCard: View {
    let announcement: APIClient.Announcement
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("From your coach\(announcement.teamName.map { " · \($0)" } ?? "")")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close the announcement")
            }
            Text(announcement.text)
                .font(.body)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
    }
}
