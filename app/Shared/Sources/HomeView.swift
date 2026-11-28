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
    /// No twin yet: after the first check-in the day's learning step is the interview.
    @State private var twinInterviewDue = false
    /// "Train as planned instead": one choice for today, shared by Home and Workout.
    @AppStorage(ReadinessOverride.key) private var readinessOverrideDay = ""
    private var readinessOverridden: Bool {
        get { readinessOverrideDay == DayKey.of(.now) }
        nonmutating set { readinessOverrideDay = newValue ? DayKey.of(.now) : "" }
    }
    @State private var liveLaunch: LiveSessionLaunch?
    @State private var activeSheet: HomeSheet?
    @State private var showingCompetitions = false
    /// Where the Competitions hub opens (overview, add a game, game prep).
    @State private var hubOpening: CompetitionHubFocus = .overview
    @State private var showingTell = false
    @State private var showingGym = false
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
    @State private var lowEnergySnoozed = LowEnergyCheck.isSnoozed
    /// Bumped when a practice card is answered, so the notices redraw.
    @State private var practiceRevision = 0
    /// What the twin changes this week, in a few words, for the Body tile
    /// ("Legs ready Sunday") — the same effects the Twin page shows.
    @State private var twinTile: String?
    /// The coach's latest announcement (closed ones stay closed).
    @State private var announcement = TeamAnnouncements.current
    /// Bumped when a sheet closes, so what it changed (reflection, pain, day status) redraws.
    @State private var revision = 0
    /// "Sick, travelling or on holiday?" tapped in the Today sheet: the day-status sheet opens once it has closed.
    @State private var openDayStatusNext = false
    /// The widget being held while arranging, and where the board is in reordering it.

    /// The Health workout `WorkoutCheckSheet` asks about.
    @State private var checkSession: Session?
    @State private var checkStartStep: WorkoutCheckSheet.Step = .effort

    enum HomeSheet: String, Identifiable {
        case checkIn, history, dayStatus, todayPlan, schedule, reflection, search, safety, seasonReview, tournament
        /// "How hard was it, what did it train?" after a workout from Apple Health.
        case workoutCheck
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
    private var loggedToday: Bool { !todaysSessions.isEmpty }

    /// The athlete's sport words and whether it's a team sport ("Did you play?").
    private var gameFamily: SportFamily { AcademyContent.family(forSport: athlete.activeSport?.sportSlug) }

    /// The day the evening reflects on (after midnight, until 05:00, still
    /// yesterday): its practice — kept when the evening itself said "Didn't go",
    /// so the answer can be changed — its game, and whether a game still waits
    /// for the games hub's questions (asked there, not twice).
    private var reflectionDayFacts: (practice: Bool, game: Bool, gameToRate: Competition?, trained: Bool, effort: Int?, practiceMinutes: Int?) {
        let day = ReflectionSheet.reflectionDay()
        let key = DayKey.of(day)
        let practice = PracticeSchedule.hasPractice(on: day) || EveningPractice.skipped(on: key)
        let games = athlete.competitions.filter { calendar.isDate($0.date, inSameDayAs: day) }
        let sessions = athlete.sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
        // The day's effort is known only when every workout has one the athlete
        // gave (a watch's heart-rate guess isn't an answer — else ask).
        let efforts = sessions.compactMap { session -> Int? in
            HealthWorkoutInbox.isImported(session) && HealthWorkoutInbox.answer(for: session) == nil ? nil : session.sessionRPE
        }
        let effort = !sessions.isEmpty && efforts.count == sessions.count ? efforts.max() : nil
        let minutes = PracticeSchedule.time(on: day, calendar: calendar).map { $0.end - $0.start }.flatMap { $0 > 0 ? $0 : nil }
        // A game not rated yet (hub or an earlier evening): the evening asks how it went.
        let unrated = games.first { CompetitionStore.rating(for: $0.id) == nil }
            ?? games.first { CompetitionStore.evenings()[$0.id] != nil && CompetitionStore.results()[$0.id] == nil }
        return (practice, !games.isEmpty, unrated, !sessions.isEmpty, effort, minutes)
    }
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
        refreshToday()
        return memo.planning ?? PlanningRules.today(athlete, sessions: allSessions)
    }

    private var todaysWorkout: (mode: WorkoutMode, session: GeneratedSession)? {
        refreshToday()
        return memo.workout
    }

    /// Today's plan and workout, worked out once per change in what they
    /// read (a redraw asks for them a dozen times; the clock ticks each minute).
    @State private var memo = HomeTodayMemo()

    private func refreshToday() {
        let key = HomeTodayMemo.Key(
            revision: revision, clock: clock, sessions: allSessions.count, checkIns: athlete.checkIns.count,
            competitions: athlete.competitions.map(\.date), status: status, catalogue: catalogue.itemsBySlug.count,
            override: readinessOverrideDay, practiceDays: practiceDays, week: week)
        guard memo.key != key else { return }
        // Planning first and the key set, so building the workout (which reads
        // `planning`) doesn't start over.
        memo.planning = PlanningRules.today(athlete, sessions: allSessions)
        memo.key = key
        memo.workout = buildTodaysWorkout()
    }

    /// The one decision every screen shows (`TodayEngine.todaysPick`).
    private func buildTodaysWorkout() -> (mode: WorkoutMode, session: GeneratedSession)? {
        TodayEngine.todaysPick(athlete: athlete, sessions: allSessions, week: week, catalogue: catalogue)
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

    // MARK: - Game time

    @AppStorage(GameTime.usualStartKey) private var gameStartMinutes = GameTime.defaultUsualMinutes

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
                              daysToNextGame: daysToNextGame, readiness: readinessOverridden ? nil : readiness, eventWord: eventWord)
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

    /// After Tell AthleteOS or the Competitions hub: the day status, the plan
    /// and the reading may all have changed.
    private func refreshAfterChange() {
        status = DayStatusStore.status()
        revision += 1
        refreshTwinBriefing()
    }

    /// A workout from Apple Health waiting for its few taps: ask once, when
    /// nothing else is open (never over the check-in or another sheet).
    private func askAboutHealthWorkout() {
        guard activeSheet == nil, selectedTab == .today, let session = HealthWorkoutInbox.pending(allSessions) else { return }
        checkSession = session
        checkStartStep = .effort
        activeSheet = .workoutCheck
    }

    private func refreshTwinBriefing() {
        let state = AcademyStore.load()
        briefingReadToday = state.read.values.contains { calendar.isDateInToday($0) }
        twinInterviewDue = state.intakeDoneAt == nil && !athlete.checkIns.isEmpty
        let report = TwinAnalysis.report(TwinInputBuilder.input(athlete: athlete, state: state))
        twinBriefing = report.insights.compactMap(\.briefing).first { state.read[$0.id] == nil }
        let gym = catalogue.itemsBySlug.isEmpty ? nil : GymHistoryBuilder.history(athlete, catalogue: catalogue)
        twinTile = TwinKnowledgeStore.planEffects(athlete, history: gym).first(where: \.now)?.short
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
                // A fixed skeleton (owner, 2026-11-26; NN/g and Findlater: adapt
                // the content, never move the places): the one thing to do now,
                // three glance tiles, today and tomorrow, then notices — always
                // in this order. Only what each slot says changes with the day.
                VStack(alignment: .leading, spacing: 40) {
                    VStack(alignment: .leading, spacing: 22) {
                        topBar
                        header
                        tellBar
                    }
                    nowSlot
                        .id(contentKey)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 16)), removal: .opacity))
                    if loaded { glanceRow }
                    dayDetails
                    notices
                    if loaded, status != .concussion, todayPlan.next != .sleep { alsoToday }
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
                    status = DayStatusStore.status()
                    announcement = TeamAnnouncements.current
                    switch IntentRoute.take([.checkIn, .reflection, .tell]) {
                    case .checkIn?: activeSheet = .checkIn
                    case .reflection?: activeSheet = .reflection
                    case .tell?: showingTell = true
                    default: break
                    }
                    askAboutHealthWorkout()
                }
            }
            // The lock-screen card tapped while the app was open.
            .onReceive(NotificationCenter.default.publisher(for: IntentRoute.didChange)) { _ in
                switch IntentRoute.take([.checkIn, .reflection, .tell]) {
                case .checkIn?: activeSheet = .checkIn
                case .reflection?: activeSheet = .reflection
                case .tell?: showingTell = true
                default: break
                }
            }
            // A push or the quiet check: the coach's new workout or note shows up now.
            .onChange(of: LiveUpdates.shared.tick) {
                revision += 1
                announcement = TeamAnnouncements.current
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingCompetitions, onDismiss: refreshAfterChange) {
                CompetitionHubView(athlete: athlete, onChanged: onPlanInputsChanged, opening: hubOpening)
            }
            .sheet(isPresented: $showingTell, onDismiss: refreshAfterChange) {
                TellView(athlete: athlete, catalogue: catalogue,
                         plannedGymDay: week?.sessions.contains { Calendar.current.isDateInToday($0.date) } ?? false,
                         onChanged: onPlanInputsChanged)
            }
            .task(id: allSessions.count + athlete.checkIns.count) {
                switch IntentRoute.take([.checkIn, .reflection, .tell]) {
                case .checkIn?: activeSheet = .checkIn
                case .reflection?: activeSheet = .reflection
                case .tell?: showingTell = true
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
                if !loaded, DemoData.initialTab == .today, let name = DemoData.initialSheet {
                    // Screenshots: a gym session the watch recorded an hour ago (never saved).
                    if name.hasPrefix(HomeSheet.workoutCheck.rawValue) {
                        checkSession = Session(startedAt: .now.addingTimeInterval(-6000), endedAt: .now.addingTimeInterval(-3000), sessionRPE: 6,
                                               minutes: 52, source: .watch, notes: "Strength training · from your Apple Watch")
                        checkStartStep = name.hasSuffix("Done") ? .done : name.hasSuffix("Trained") ? .trained : .effort
                    }
                    if name == "addGame" { openHub(.addGame) }
                    else { activeSheet = name.hasPrefix(HomeSheet.workoutCheck.rawValue) ? .workoutCheck : HomeSheet(rawValue: name) }
                }
                loaded = true
                askAboutHealthWorkout()
            }
            .sheet(item: $activeSheet, onDismiss: {
                status = DayStatusStore.status()
                revision += 1
                if openDayStatusNext {
                    openDayStatusNext = false
                    activeSheet = .dayStatus
                }
                refreshTwinBriefing()
                runPendingSearch()
            }) { sheet in
                switch sheet {
                case .checkIn:
                    CheckInSheet(athlete: athlete)
                case .history:
                    SessionHistoryView()
                case .dayStatus:
                    DayStatusSheet(current: status) { newStatus, days in
                        DayStatusStore.set(newStatus, days: days)
                        status = DayStatusStore.status()
                        activeSheet = nil
                        onPlanInputsChanged()
                    }
                case .todayPlan:
                    TodayChoiceSheet(initial: todayAnswer, gameWord: gameWord, hint: todayHint, onSave: { answer in
                        DayChoiceStore.set(answer)
                        activeSheet = nil
                        onPlanInputsChanged()
                    }, onOtherKindOfDay: {
                        openDayStatusNext = true
                        activeSheet = nil
                    })
                case .tournament:
                    TournamentModeView(onHotelWorkout: { selectedTab = .workout })
                case .seasonReview:
                    SeasonReviewSheet(athlete: athlete, sessions: allSessions, catalogue: catalogue)
                case .safety:
                    SafetyCenterView()
                case .reflection:
                    let evening = reflectionDayFacts
                    ReflectionSheet(completion: completion, practiceToday: evening.practice,
                                    gameToRate: evening.gameToRate.map { ($0.id, gameFamily.team, gameFamily.event) },
                                    sportSlug: athlete.activeSport?.sportSlug ?? athlete.sports.first?.sportSlug,
                                    restDay: !evening.trained && !evening.practice && !evening.game,
                                    trained: evening.trained, trainedEffort: evening.effort,
                                    scheduledMinutes: evening.practiceMinutes, hadGame: evening.game, athlete: athlete) { revision += 1 }
                case .search:
                    AppSearchSheet(entries: searchEntries, exercises: searchableExercises) { target in
                        pendingSearch = target
                        activeSheet = nil
                    }
                case .workoutCheck:
                    if let checkSession {
                        WorkoutCheckSheet(session: checkSession, catalogue: catalogue, sports: SportVisibility.sports(for: athlete),
                                          startStep: checkStartStep) {
                            revision += 1
                            // The answer sets each region's rest: tomorrow's plan reads it.
                            onPlanInputsChanged()
                        }
                        .interactiveDismissDisabled()
                    }
                case .schedule:
                    ScheduleSheet(athlete: athlete) {
                        practiceDays = PracticeSchedule.weekdays
                        scheduleIsSet = PracticeSchedule.isSet
                        onPlanInputsChanged()
                    }
                }
            }
            .sheet(isPresented: $showingGym, onDismiss: { revision += 1 }) {
                GymSetupView(athlete: athlete, catalogue: catalogue,
                             onStart: { session in liveLaunch = LiveSessionLaunch(planned: session, kind: .gym) },
                             onPreview: { session in
                                 DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { preview = PreviewBox(session: session, kind: .gym) }
                             })
            }
            .sheet(item: $preview) { box in
                SessionPreviewSheet(session: box.session, catalogue: catalogue) {
                    preview = nil
                    liveLaunch = LiveSessionLaunch(planned: box.session, kind: box.kind)
                }
            }
            .fullScreenCover(item: $liveLaunch) { launch in
                LiveSessionView(athlete: athlete, apiClient: apiClient, planned: launch.planned, kind: launch.kind, resuming: launch.resuming)
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
        // The one add-a-game form lives in the Competitions hub.
        case .addGame: openHub(.addGame)
        case .history: activeSheet = .history
        case .dayStatus: activeSheet = .dayStatus
        case .schedule: activeSheet = .schedule
        case .reflection: activeSheet = .reflection
        case .safety: activeSheet = .safety
        // Search lands in each thing's one home (owner, 2026-11-26).
        case .mentalSkills:
            AcademyNavigation.shared.page = .campus
            selectedTab = .academy
        case .seasonReview: activeSheet = .seasonReview
        case .competitions: openHub(.overview)
        case .gamePrep: openHub(.gamePrep)
        case .tests: openTwin("tests")
        case .trends: openTwin("trends")
        // One door for input (owner, 2026-11-26): adding goes through Tell AthleteOS.
        case .logWorkout:
            IntentRoute.prefillTell("I did a workout: ")
            showingTell = true
        case .addTraining:
            IntentRoute.prefillTell("Extra practice on ")
            showingTell = true
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
            // Today's gym day when there is one; otherwise a gym session built
            // for today (never another day's session shown as today's).
            if let planned = week?.sessions.first(where: { calendar.isDateInToday($0.date) }) { return adjusted(planned) }
            return engine(.gymDay)
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
        case .checkIns: CheckInHistoryView(checkIns: athlete.checkIns)
        case .exerciseProgress: ExerciseProgressListView(sessions: allSessions, catalogue: catalogue)
        case .dataExport: DataExportView(athlete: athlete, sessions: allSessions)
        case .reminders: RemindersSheet(athlete: athlete)
        case .health: HealthConnectionView()
        case .help: HelpCenterView()
        case .team: MyTeamView()
        case .coach: CoachView()
        case .parent: ParentSummaryView()
        case .goals: StrugglesSheet(onSaved: onPlanInputsChanged)
        case .library: LibraryView(athlete: athlete)
        case .sportGuide: SportGuideView(athlete: athlete)
        case .support: SupportSheet()
        case .skillPlans: ImproveView(athlete: athlete, apiClient: apiClient, onPlanInputsChanged: onPlanInputsChanged)
        case .skill(let slug):
            ImproveView(athlete: athlete, apiClient: apiClient, onPlanInputsChanged: onPlanInputsChanged, initialSkillSlug: slug)
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
        case .calendars: ScheduleSheet(athlete: athlete, onChanged: onPlanInputsChanged)
        case .sportPosition: SportEditorSheet(athlete: athlete, onSaved: onPlanInputsChanged)
        default: EmptyView()
        }
    }

    /// The twin, with one of its pages open (Trends, Tests).
    private func openTwin(_ sheet: String) {
        AcademyNavigation.shared.page = .twin
        AcademyNavigation.shared.pendingTwinSheet = sheet
        selectedTab = .academy
    }

    /// The Competitions hub, opened where it's needed.
    private func openHub(_ opening: CompetitionHubFocus) {
        hubOpening = opening
        showingCompetitions = true
    }

    // MARK: - Top

    /// Small floating glass controls: the kind of day and search. Everything the
    /// athlete adds goes through one door, Tell AthleteOS (owner, 2026-11-26).
    private var topBar: some View {
        HStack(spacing: 8) {
            ProfileButton(name: athlete.displayName)
            // A normal day: what's on today (the athlete's word), changeable
            // any time. Sick, travel or holiday: that status, as before.
            Button { activeSheet = status == .active ? .todayPlan : .dayStatus } label: {
                HStack(spacing: 7) {
                    Image(systemName: dayChipImage)
                        .foregroundStyle(status == .active ? AppTheme.secondaryText : phase.red)
                    Text(dayChipTitle)
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
            .buttonStyle(.pressable)
            .fixedSize()
            .layoutPriority(1)
            Spacer(minLength: 4)
            .accessibilityLabel("Today is: \(dayChipTitle). Change what's on today.")
            searchButton
        }
    }

    /// The athlete's answer to "What's on today?" (nil: left to AthleteOS).
    private var saidToday: DayAnswer? {
        _ = revision
        return TodayEngine.said(on: .now)
    }

    private var dayChipTitle: String {
        guard status == .active, let said = saidToday else { return status.title }
        return "Today: \(said.label)"
    }

    private var dayChipImage: String {
        guard status == .active, let first = saidToday?.ordered.first else { return status.systemImage }
        return first.systemImage
    }

    private var gameWord: String {
        AcademyContent.family(forSport: athlete.activeSport?.sportSlug).tokens["Event"] ?? "Game"
    }

    private var todayAnswer: DayAnswer {
        DayChoicePicker.startingAnswer(practiceToday: practiceToday, gameToday: gameToday != nil)
    }

    private var todayHint: String {
        DayChoicePicker.scheduleHint(practiceToday: practiceToday, practiceTime: PracticeSchedule.time(on: .now),
                                     game: gameToday?.date, gameWord: gameWord)
    }

    /// The one door for input: tell the app what's going on in your own words.
    /// (The next competition is a glance tile below.)
    private var tellBar: some View {
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
        .buttonStyle(.pressable)
        .accessibilityLabel("Tell AthleteOS what's going on")
    }

    /// Search everything, at the end of the top bar.
    private var searchButton: some View {
        Button { activeSheet = .search } label: {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.85))
                .frame(width: 40, height: 40)
                .glassCapsule()
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Search")
        .accessibilityHint("Find any part of the app, a workout, a lesson or an exercise")
    }

    private var firstName: String? {
        guard let name = athlete.displayName?.split(separator: " ").first, !name.isEmpty else { return nil }
        return String(name)
    }

    // MARK: - The part of the day (V4)

    /// Refreshed every minute and when the app comes back, so Home follows the day.
    private var phase: DayPhase { DayPhase.at(clock) }

    /// A workout of today left open with sets in it (the app closed, the
    /// phone died): carry on or finish it.
    private var unfinishedWorkout: Session? {
        _ = revision
        guard liveLaunch == nil else { return nil }
        return allSessions.first { calendar.isDateInToday($0.startedAt) && $0.endedAt == nil && !$0.sets.isEmpty }
    }

    private func resumeCard(_ open: Session) -> some View {
        AuraCard(.training, focus: UnitPoint(x: 0.85, y: 0.2), radius: 180) {
        VStack(alignment: .leading, spacing: 14) {
            Headline([.strong("Workout not finished. "), .soft("Pick it up where you left off.")], size: 26)
            Text("Started \(open.startedAt.formatted(date: .omitted, time: .shortened)) · \(countedNoun(open.sets.count, "set")) logged")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.ink.opacity(0.8))
            ButtonRow {
                Button {
                    let logged = Set(open.sets.map(\.itemSlug))
                    let plan = todaysWorkout.map(\.session).flatMap { logged.isSubset(of: Set($0.items.map(\.itemSlug))) ? $0 : nil }
                    liveLaunch = LiveSessionLaunch(planned: plan, kind: SessionKinds.kind(of: open.clientId), resuming: open)
                } label: { Text("Resume") }
                .buttonStyle(.primary)
                Button {
                    try? SessionLogger(modelContext: modelContext).close(open)
                    revision += 1
                } label: { Text("Finish it") }
                .buttonStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Today's real sessions: finished, or with at least one set (an open or
    /// abandoned workout isn't "training done").
    private var todaysSessions: [Session] {
        allSessions.filter { calendar.isDateInToday($0.startedAt) && ($0.endedAt != nil || !$0.sets.isEmpty) }
    }
    private var workoutDoneToday: Bool { todaysSessions.contains { SessionKinds.kind(of: $0.clientId) != .mobility } }
    private var mobilityDoneToday: Bool { todaysSessions.contains { SessionKinds.kind(of: $0.clientId) == .mobility } }
    private var practiceLogToday: PracticeLog? {
        _ = revision
        return PracticeLogStore.log(on: DayKey.of(.now), sportSlug: athlete.activeSport?.sportSlug)
    }

    private var weekPlan: WeekPlanProgress {
        let summary = weekSummary
        // Planned and done over the same Monday-to-Sunday week (the plan's own
        // week starts on Sunday in some countries).
        var monday = calendar
        monday.firstWeekday = 2
        let interval = monday.dateInterval(of: .weekOfYear, for: clock)
        let planned = week?.sessions.filter { interval?.contains($0.date) ?? true }.count ?? 0
        return WeekPlanProgress(workoutsPlanned: planned, workoutsDone: summary.workouts,
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
            let start = GameTime.start(game.date, usualMinutes: gameStartMinutes, calendar: calendar)
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
                             lessonAvailable: twinInterviewDue || twinBriefing != nil || nextLesson != nil, fixed: fixedPoint, workoutPlanned: todaysWorkout != nil,
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
        VStack(alignment: .leading, spacing: 14) {
            Text(clock.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.7)
                .foregroundStyle(AppTheme.ink)
            Headline(headlineParts)
                .animation(.easeInOut(duration: 0.3), value: contentKey)
            HStack(spacing: 10) {
                SportSwitcher(athlete: athlete, onChanged: onPlanInputsChanged)
                if let seasonLine {
                    Text(seasonLine)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// V8: the day in one sentence — what matters bright, the rest dimmed.
    private var headlineParts: [Headline.Part] {
        let hello: Headline.Part = .soft(firstName.map { "\(phase.greeting), \($0). " } ?? "\(phase.greeting). ")
        guard loaded else { return [hello] }
        if status == .concussion {
            return [hello, .soft("Training is "), .strong("paused"), .soft(" until a doctor clears you.")]
        }
        let plan = todayPlan
        let progress: Headline.Part = .soft(plan.total > 0 ? " \(plan.doneCount) of \(plan.total) done." : "")
        switch plan.next {
        case .checkIn:
            if QuickCheckIn.isOffered(athlete) {
                return [hello, .soft("Today is "), .strong("already planned"), .soft(". One tap if it's a usual day.")]
            }
            return [hello, .soft("Start with a "), .icon("waveform.path.ecg"), .strong(" 30-second check-in"), .soft(" — today's plan is built from it.")]
        case .game:
            var parts: [Headline.Part] = [hello, .soft("It's "), .icon("trophy.fill"), .strong(" \(eventWord.lowercased()) day")]
            if let game = gameToday {
                parts += [.soft(" at "), .strong(game.date.formatted(date: .omitted, time: .shortened))]
            }
            return parts + [.soft(". Warm up, then save everything for it.")]
        case .workout:
            if let workout = todaysWorkout {
                return [hello, .soft("Today: "), .icon("flame.fill"), .strong(" \(workout.session.estimatedMinutes) min of training"),
                        .soft(readinessBand != nil ? ", lighter than usual." : "."), progress]
            }
            return [hello, .strong("Training is next."), progress]
        case .lesson:
            if twinInterviewDue { return [hello, .soft("Next: "), .icon("person.crop.circle"), .strong(" meet your twin"), .soft(" — 5 minutes.")] }
            if let briefing = twinBriefing {
                return [hello, .soft("Your twin has a "), .icon("book.fill"), .strong(" \(briefing.minutes)-minute read"), .soft(" for you.")]
            }
            return [hello, .soft("Next: "), .icon("book.fill"), .strong(" a short lesson"), .soft("."), progress]
        case .reflection:
            return [hello, .soft("One thing left: "), .strong("45 seconds"), .soft(" to reflect on today.")]
        case .waiting(let reason):
            switch reason {
            case .practice:
                var parts: [Headline.Part] = [hello, .strong("Team practice")]
                if let start = practiceStart { parts += [.soft(" at "), .strong(start.formatted(date: .omitted, time: .shortened))] }
                return parts + [.soft("."), progress]
            case .restDay: return [hello, .strong("Rest day."), .soft(" Recovery is part of the plan.")]
            case .recover: return [hello, .strong("Rest and recover"), .soft(" today.")]
            case .reflectTonight: return [hello, .strong("Training's done."), .soft(" Reflect tonight.")]
            case .clear: return [hello, .strong("You're set."), .soft(" Nothing else today.")]
            }
        case .dayComplete:
            return [hello, .strong("All done today."), .soft(" Recovery is training too.")]
        case .sleep:
            return [hello, .soft("Time to "), .strong("sleep"), .soft(". Tomorrow builds on tonight.")]
        }
    }

    /// The colour of the next step's card: training ember, body blue, mind magenta, games green.
    private func tone(_ next: TodayPlan.Next) -> AuraTone {
        switch next {
        case .checkIn: .body
        case .game: .game
        case .workout: .training
        case .lesson, .reflection: .mind
        case .waiting(.practice): .body
        case .waiting, .dayComplete, .sleep: .calm
        }
    }

    // MARK: - The day: one next step, then the plan (docs/CLARITY-PLAN.md)

    /// Slot 1: the one thing to do now. A workout left open comes first; then
    /// the day's next step (check in, warm up, train, read, reflect), the day
    /// done, or sleep.
    @ViewBuilder
    private var nowSlot: some View {
        if !loaded {
            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
        } else if let open = unfinishedWorkout {
            resumeCard(open)
        } else if status == .concussion {
            pausedCard
        } else {
            let plan = todayPlan
            switch plan.next {
            case .dayComplete: dayCompleteView
            case .sleep: nightView
            default:
                AuraCard(tone(plan.next), focus: UnitPoint(x: 0.3, y: 0.5), radius: 220) {
                    nextStepHero(plan.next)
                }
            }
        }
    }

    /// Slot 3: today in order and tomorrow in a line, with the reason under them.
    @ViewBuilder
    private var dayDetails: some View {
        if loaded, status != .concussion, todayPlan.next != .dayComplete, todayPlan.next != .sleep {
            VStack(alignment: .leading, spacing: 18) {
                planPanel(todayPlan)
                if let tomorrow = tomorrowLine {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("Tomorrow")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                        tomorrowText(tomorrow)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                    }
                    .accessibilityElement(children: .combine)
                }
                whySection
            }
        }
    }

    /// Slot 4: anything that needs a word today, always here, never above the
    /// plan — pain, constant tiredness, the coach's note, a missing schedule.
    @ViewBuilder
    private var notices: some View {
        if loaded {
            VStack(alignment: .leading, spacing: 14) {
                painNote
                // What the last input taught the twin (a check-in, a practice answer…).
                TwinPulseLine(sources: [.checkIn, .workout])
                // The plan moved since the athlete last looked: said once, cause first.
                if !PlanStore.shared.changes.isEmpty {
                    PlanChangeCard(changes: PlanStore.shared.changes, event: eventWord) {
                        withAnimation { PlanStore.shared.changesSeen() }
                    } onOpenWeek: {
                        PlanStore.shared.changesSeen()
                        selectedTab = .workout
                    }
                }
                if let lowEnergy, !lowEnergySnoozed {
                    LowEnergyCard(warning: lowEnergy) {
                        LowEnergyCheck.snoozeForAWeek()
                        lowEnergySnoozed = true
                    }
                }
                if let announcement {
                    AnnouncementCard(announcement: announcement) {
                        TeamAnnouncements.markSeen(announcement.id)
                        withAnimation { self.announcement = nil }
                    }
                }
                // Better practice data (P14–P17): yesterday in one tap, a routine offered, not assumed.
                if let day = practiceToAsk {
                    PracticeAskCard(day: day) { answer in
                        PracticeAnswers.save(answer, on: day, sportSlug: athlete.activeSport?.sportSlug)
                        withAnimation { practiceRevision += 1 }
                    }
                }
                if let offer = routineOffer {
                    RoutineOfferCard(weekdays: offer) { accepted in
                        if accepted { PracticeSchedule.weekdays = PracticeSchedule.weekdays.union(offer) } else { PracticeAnswers.declineRoutine() }
                        scheduleIsSet = PracticeSchedule.isSet
                        withAnimation { practiceRevision += 1 }
                        NotificationCenter.default.post(name: WeeklyPlan.inputsChanged, object: nil)
                    } adjust: {
                        activeSheet = .schedule
                    }
                } else if !scheduleIsSet && status == .active { scheduleCard }
            }
        }
    }

    /// Slot 2: three tiles, each a doorway to its one home — the body today
    /// (the twin), the next competition (the hub), this week (the calendar).
    private var glanceRow: some View {
        HStack(spacing: 10) {
            GlanceTile(tone: .body, label: "Body today", value: bodyGlance.value, detail: bodyGlance.detail) {
                if todaysCheckIn == nil, status == .active {
                    activeSheet = .checkIn
                } else {
                    AcademyNavigation.shared.page = .twin
                    selectedTab = .academy
                }
            }
            GlanceTile(tone: .game, label: "Next \(eventWord.lowercased())", value: gameGlance.value, detail: gameGlance.detail) {
                openHub(.overview)
            }
            GlanceTile(tone: .training, label: "This week", value: weekGlance.value, detail: weekGlance.detail) {
                // The week lives once: the Workout tab's strip, with Edit week under it.
                selectedTab = .workout
            }
        }
    }

    private var bodyGlance: (value: String, detail: String) {
        switch status {
        case .concussion: return ("Paused", "Until a doctor clears you")
        case .sick: return ("Resting", "Get well first")
        default: break
        }
        guard todaysCheckIn != nil, let level = readiness?.level else { return ("Check in", "30 seconds") }
        switch level {
        // Ready: the twin's change this week says more than "as planned".
        case .normal: return ("Ready", twinTile ?? "Train as planned")
        case .reduced: return ("Lighter", "A bit less today")
        case .recovery: return ("Recover", "Easy day today")
        }
    }

    private var gameGlance: (value: String, detail: String) {
        guard let next = AthleteStats.upcomingCompetitions(athlete).first else { return ("None", "Add one in a sentence") }
        let days = AthleteStats.daysUntil(next.date)
        let value = days == 0 ? "Today" : days == 1 ? "Tomorrow" : "\(days) days"
        return (value, next.date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
    }

    private var weekGlance: (value: String, detail: String) {
        let plan = weekPlan
        let practices = plan.practicesPlanned > 0 ? "\(plan.practicesDone)/\(plan.practicesPlanned) practices" : "Your week"
        guard plan.workoutsPlanned > 0 else { return ("\(plan.workoutsDone) done", practices) }
        return ("\(min(plan.workoutsDone, plan.workoutsPlanned))/\(plan.workoutsPlanned)", "workouts · " + practices)
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

    /// Decided before you look (owner, 2026-11-27): the plan is already made;
    /// the check-in is one tap when the day is a usual one, the full check-in
    /// when something's different. First check-ins and open follow-ups or
    /// pain still go through the full questions.
    @ViewBuilder
    private var checkInHero: some View {
        if QuickCheckIn.isOffered(athlete) {
            decidedHero
        } else {
            fullCheckInHero
        }
    }

    private var decidedHero: some View {
        let workout = todaysWorkout
        let because = workout?.session.decision.flatMap { PlanExplanation.because($0.reasons, event: eventWord) }
        return VStack(alignment: .leading, spacing: 14) {
            NextStepEyebrow("Already planned for you", accent: .white)
            heroTitle(workout.map { "\($0.session.estimatedMinutes) min · \($0.session.title)" } ?? "Rest day")
            if let because { heroMeta("Because: \(because)") }
            Button {
                QuickCheckIn.save(athlete, context: modelContext)
                revision += 1
            } label: { HeroCTALabel("Feeling normal, no pain") }
                .buttonStyle(.primary)
                .padding(.top, 6)
            Button("Something's different") { activeSheet = .checkIn }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.85))
                .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fullCheckInHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            NextStepEyebrow("Start here · check-in", accent: .white)
            heroTitle("How do you feel?")
            bigNumber("30", unit: "sec")
                .accessibilityLabel("30 seconds")
            heroMeta("Sleep · Energy · Body · Mood")
            Button { activeSheet = .checkIn } label: { HeroCTALabel("Check in") }
                .buttonStyle(.primary)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 40)
                    .background(AppTheme.coral.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.pressable)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // The heroes: the title and the number dominate.

    @ViewBuilder
    private var gameHero: some View {
        if let game = gameToday {
            VStack(alignment: .leading, spacing: 14) {
                NextStepEyebrow("\(eventWord) day", accent: .white)
                heroTitle(gameTitle(game))
                clockNumber(game.date)
                heroMeta(game.isHome ? "Home" : "Away")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var workoutHero: some View {
        if let workout = todaysWorkout {
            let session = workout.session
            VStack(alignment: .leading, spacing: 14) {
                NextStepEyebrow("Next step · training", accent: .white)
                Button { preview = PreviewBox(session: session, kind: workoutKind(workout.mode)) } label: {
                    heroTitle(focusTitle(session, mode: workout.mode))
                }
                .buttonStyle(.pressable)
                bigNumber("\(session.estimatedMinutes)", unit: "min")
                if let qualities = qualityLine(session) {
                    heroMeta(qualities)
                }
                // One short line instead of a row of grey boxes: the load word
                // and, for a plain session, how many exercises.
                heroMeta(loadLine(session))
                // The athlete's own gym session: why this focus, and a way to pick another.
                if session.decision?.gymFocus != nil {
                    if let note = session.decision?.gymNote { heroMeta(note) }
                    ButtonRow {
                        Button { liveLaunch = LiveSessionLaunch(planned: session, kind: workoutKind(workout.mode)) } label: {
                            HeroCTALabel("Start training")
                        }
                        .buttonStyle(.primary)
                        Button("Change") { showingGym = true }
                            .buttonStyle(.secondary)
                            .accessibilityLabel("Change what you train today")
                    }
                    .padding(.top, 8)
                } else {
                    Button { liveLaunch = LiveSessionLaunch(planned: session, kind: workoutKind(workout.mode)) } label: {
                        HeroCTALabel("Start training")
                    }
                    .buttonStyle(.primary)
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Nothing to train right now: a few minutes of Campus are the next step.
    @ViewBuilder
    private var lessonHero: some View {
        if twinInterviewDue {
            VStack(alignment: .leading, spacing: 14) {
                NextStepEyebrow("Next step · your twin", accent: .white)
                Button { openLesson() } label: { heroTitle("Meet your twin") }
                    .buttonStyle(.pressable)
                bigNumber("5", unit: "min")
                heroMeta("Ten questions about how you think and train — no right answers. Only you see it.")
                Button { openLesson() } label: { HeroCTALabel("Start the interview") }
                    .buttonStyle(.primary)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let briefing = twinBriefing {
            VStack(alignment: .leading, spacing: 14) {
                NextStepEyebrow("Next step · read", accent: .white)
                Button { openLesson() } label: { heroTitle(briefing.title) }
                    .buttonStyle(.pressable)
                bigNumber("\(briefing.minutes)", unit: "min")
                heroMeta("Picked for you by AthleteOS Coach, from your twin")
                Button { openLesson() } label: { HeroCTALabel("Read") }
                    .buttonStyle(.primary)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let next = nextLesson {
            VStack(alignment: .leading, spacing: 14) {
                NextStepEyebrow("Next step · learn", accent: .white)
                Button { openLesson() } label: { heroTitle(next.lesson.title) }
                    .buttonStyle(.pressable)
                bigNumber("\(next.lesson.minutes)", unit: "min")
                heroMeta(next.topic.title)
                Button { openLesson() } label: { HeroCTALabel("Start lesson") }
                    .buttonStyle(.primary)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Today's lesson, opened in Campus (the tab alone once it is learned).
    private func openLesson() {
        if twinInterviewDue {
            AcademyNavigation.shared.page = .twin
            AcademyNavigation.shared.pendingInterview = true
            selectedTab = .academy
            return
        }
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
        VStack(alignment: .leading, spacing: 14) {
            NextStepEyebrow("Next step · reflect", accent: .white)
            heroTitle("How did today actually feel?")
            bigNumber("45", unit: "sec")
                .accessibilityLabel("45 seconds")
            Button { activeSheet = .reflection } label: { HeroCTALabel("Reflect") }
                .buttonStyle(.primary)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Nothing to do right now, said plainly — never a made-up task.
    private func waitingHero(_ reason: TodayPlan.Waiting) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            switch reason {
            case .practice:
                NextStepEyebrow((fixedPoint?.hasBegun(at: minuteNow) ?? false) ? "Now" : "Up next", accent: .white)
                heroTitle("Team practice")
                if let start = practiceStart { clockNumber(start) }
                heroMeta(todaysWorkout != nil && !workoutDoneToday ? "Your training comes after practice." : "Your sport's training")
            case .restDay:
                NextStepEyebrow("Today", accent: .white)
                heroTitle("Rest day")
                heroMeta("Recovery is part of the plan.")
            case .recover:
                NextStepEyebrow("Today", accent: .white)
                heroTitle("Rest and recover")
                heroMeta("No training today. Rest well.")
            case .reflectTonight:
                NextStepEyebrow("Today", accent: .white)
                heroTitle(workoutDoneToday ? "Training done" : "Done for now")
                heroMeta("Reflect tonight. It takes 45 seconds.")
            case .clear:
                NextStepEyebrow("Today", accent: .white)
                heroTitle("You're set")
                heroMeta("Nothing else is planned today.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Normal load · 12 exercises": the hero's one data line.
    private func loadLine(_ session: GeneratedSession) -> String {
        var parts: [String] = []
        parts.append(loadWord == "Optional" ? "Optional" : loadWord + " load")
        if session.decision == nil { parts.append("\(session.items.count) exercises") }
        if let tag = focusTag, tag != "Lighter today" { parts.append(tag) }
        return parts.joined(separator: " · ")
    }

    private var loadWord: String {
        if readinessBand != nil { return "Lighter" }
        if status != .active { return "Optional" }
        return "Normal"
    }

    private func heroTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 32, weight: .bold))
            .tracking(-0.6)
            .foregroundStyle(AppTheme.ink)
            .multilineTextAlignment(.leading)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The big number: 60–82 pt, its unit small beside it.
    private func bigNumber(_ value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(.system(size: 76, weight: .light))
                .monospacedDigit()
                .tracking(-1.5)
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
            .font(.subheadline.weight(.medium))
            .foregroundStyle(AppTheme.ink.opacity(0.8))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
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
        if readinessBand != nil { return "Lighter today" }
        if examWeek { return "Exam week" }
        if status != .active { return "Optional" }
        return nil
    }

    /// The athlete's own word for a competition ("match", "race", "meet"…).
    private var eventWord: String { AcademyContent.family(forSport: athlete.activeSport?.sportSlug).tokens["Event"] ?? "Game" }

    private func gameTitle(_ game: Competition) -> String {
        game.kind == .tournament ? "Tournament" : (game.kind == .meet ? "Meet" : eventWord)
    }

    // Today's plan: every step of the day in order, the next one lit.

    private func planPanel(_ plan: TodayPlan) -> some View {
        VStack(spacing: 0) {
            SectionLabel("Today's plan") { Text("\(plan.doneCount) of \(plan.total) done").monospacedDigit() }
                .padding(.bottom, 10)
            VStack(spacing: 0) {
                ForEach(Array(plan.rows.enumerated()), id: \.element.id) { position, row in
                    if position > 0 { Divider().opacity(0.4) }
                    planRow(row)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 4)
            .background(AuraBackground(.calm))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func planRow(_ row: TodayPlan.Row) -> some View {
        let text = planText(row)
        if row.step == .rest {
            PlanStepRow(row: row, title: text.title, detail: text.detail, accent: phase.red, showsChevron: false)
        } else {
            Button { open(row.step) } label: {
                PlanStepRow(row: row, title: text.title, detail: text.detail, accent: .white)
            }
            .buttonStyle(.pressable)
        }
    }

    /// What a step is called, and the few words on its right.
    private func planText(_ row: TodayPlan.Row) -> (title: String, detail: String?) {
        let done = row.state == .done
        switch row.step {
        case .checkIn:
            return ("Check-in", done ? readiness?.level.title : "30 sec")
        case .game:
            guard let game = gameToday else { return (eventWord, nil) }
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
            if !done, twinInterviewDue { return ("Meet your twin", "5 min") }
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
        case .game: openHub(.overview)
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
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Also today")
                VStack(spacing: 0) {
                    ForEach(rows.indices, id: \.self) { index in
                        rows[index]
                        if index < rows.count - 1 { Divider().opacity(0.4) }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 4)
                .background(AuraBackground(.calm))
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                }.buttonStyle(.pressable)))
            }
        }
        // Game day: get the head ready.
        if gameToday != nil && status == .active && phase != .night {
            rows.append(AnyView(Button { openHub(.gamePrep) } label: {
                HomeDetailRow(systemImage: "wind", color: AppTheme.purple, title: "Get your head ready") { Text("2 min") }
            }.buttonStyle(.pressable)))
        }
        if status == .travel {
            rows.append(AnyView(Button { activeSheet = .tournament } label: {
                HomeDetailRow(systemImage: "airplane", color: AppTheme.ink, title: "Tournament & travel") { Text("Tips") }
            }.buttonStyle(.pressable)))
        }
        if SeasonReviewStore.due(athlete) != nil {
            rows.append(AnyView(Button { activeSheet = .seasonReview } label: {
                HomeDetailRow(systemImage: "flag.checkered", color: AppTheme.ink, title: "Your season review") { Text("3 min") }
            }.buttonStyle(.pressable)))
        }
        if let movementPrep = movementPrep {
            rows.append(AnyView(Button { preview = PreviewBox(session: movementPrep, kind: .mobility) } label: {
                HomeDetailRow(systemImage: "figure.flexibility", color: AppTheme.cyan, title: movementPrep.title) {
                    if mobilityDoneToday { Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.green) } else { Text("\(movementPrep.estimatedMinutes) min") }
                }
            }.buttonStyle(.pressable)))
        }
        return rows
    }

    /// The reason stays one tap away: today's readiness (a word and its
    /// scale, never a number) and why the plan looks like this.
    @ViewBuilder
    private var whySection: some View {
        if todaysCheckIn != nil || todaysWorkout != nil || gameToday != nil {
            VStack(alignment: .leading, spacing: 10) {
                Button { withAnimation(.easeInOut(duration: 0.35)) { showingWhy.toggle() } } label: {
                    HStack(spacing: 6) {
                        Text("Why this plan?")
                        Image(systemName: showingWhy ? "chevron.up" : "chevron.down").font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.pressable)
                if showingWhy {
                    if todaysCheckIn != nil, let readiness = readiness {
                        VStack(alignment: .leading, spacing: 8) {
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
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
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
            .frame(maxWidth: .infinity, alignment: .leading)
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

    /// After the reflection (V8): one blue body card — the day is done, sleep
    /// is the job left, what got done as big light numbers — then today's
    /// note and tomorrow as plain sentences. Left-aligned like the rest of Home.
    private var dayCompleteView: some View {
        VStack(alignment: .leading, spacing: 36) {
            AuraCard(.body, focus: UnitPoint(x: 0.85, y: 0.15), radius: 200) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .center) {
                        Text("Day complete")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink.opacity(0.85))
                        Spacer(minLength: 8)
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color(rgb: 0x1E40AF))
                            .frame(width: 46, height: 46)
                            .background(Color.white, in: Circle())
                            .accessibilityHidden(true)
                    }
                    Headline(sleepParts, size: 32)
                    let rows = doneRows
                    if !rows.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(rows, id: \.title) { row in
                                doneFigure(row)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            if let note = todaysNote {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Today's note")
                    Text(note)
                        .font(.title3)
                        .foregroundStyle(AppTheme.ink.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let tomorrow = tomorrowLine {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Tomorrow")
                    tomorrowText(tomorrow)
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Sleep well, Dom. Bed by 10:15 PM."
    private var sleepParts: [Headline.Part] {
        var parts: [Headline.Part] = [.strong(firstName.map { "Sleep well, \($0). " } ?? "Sleep well. ")]
        if let bedtime = bedtimeTonight {
            parts.append(.soft("Bed by "))
            parts.append(.strong(Bedtime.label(bedtime.minutes)))
            parts.append(.soft("."))
        } else {
            parts.append(.soft("Recovery is training too."))
        }
        return parts
    }

    /// One thing done today: a big light number, its name under it.
    private func doneFigure(_ row: DoneRow) -> some View {
        let minutes = row.value.hasSuffix(" min")
        let value = minutes ? String(row.value.dropLast(4)) : row.value
        return VStack(alignment: .leading, spacing: 2) {
            BigFigure(value, unit: minutes ? "min" : "", size: 34)
            Label(row.title, systemImage: row.icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.title): \(row.value)")
    }

    /// Tomorrow in one line: the activity's symbol in its colour, the words, the time dimmed.
    private func tomorrowText(_ tomorrow: (title: String, detail: String?, kind: TrainingCalendar.Item.Kind?)) -> Text {
        let style = tomorrowStyle(tomorrow.kind)
        var text = Text(Image(systemName: style.icon)).foregroundColor(style.color)
            + Text(" \(tomorrow.title)").foregroundColor(AppTheme.ink)
        if let detail = tomorrow.detail {
            text = text + Text(" · \(detail)").foregroundColor(AppTheme.ink.opacity(0.42))
        }
        return text
    }

    /// Activity colours (V8): game green, practice blue, gym ember, rest calm.
    private func tomorrowStyle(_ kind: TrainingCalendar.Item.Kind?) -> (icon: String, color: Color) {
        switch kind {
        case .practice: ("person.3.fill", ProgressColors.practice)
        case .workout: ("dumbbell.fill", ProgressColors.workout)
        case .mobility: ("figure.flexibility", ProgressColors.mobility)
        case .game: ("trophy.fill", ProgressColors.game)
        case .off, nil: ("moon.fill", AuraTone.calm.mark)
        }
    }

    /// After midnight without a finished day: nothing to do but sleep.
    private var nightView: some View {
        // V8: the body (blue) card — sleep is the one job left today.
        AuraCard(.body, focus: UnitPoint(x: 0.25, y: 0.4), radius: 200) {
            VStack(alignment: .leading, spacing: 10) {
                Text("It's late")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.8))
                Headline([.strong("Sleep is training too. "), .soft("Everything else can wait until morning.")], size: 30)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
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
        if workoutDoneToday { rows.append(DoneRow(icon: "dumbbell.fill", color: AppTheme.red, title: "Workout", value: workoutMinutes > 0 ? "\(workoutMinutes) min" : "Done")) }
        let mobilityMinutes = todaysSessions.filter { SessionKinds.kind(of: $0.clientId) == .mobility }.reduce(0) { $0 + $1.minutes }
        if mobilityDoneToday { rows.append(DoneRow(icon: "figure.flexibility", color: AppTheme.water, title: "Mobility", value: "\(mobilityMinutes) min")) }
        if learnedToday { rows.append(DoneRow(icon: "graduationcap.fill", color: AppTheme.purple, title: "Learning", value: "Done")) }
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

    /// Tomorrow in the week strip's and the calendar's own words (owner,
    /// 2026-11-27: Home said "Team practice" while the week showed the
    /// strength session after it): the day's main item, then the rest.
    private var tomorrowLine: (title: String, detail: String?, kind: TrainingCalendar.Item.Kind?)? {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: clock) else { return nil }
        // The plan of record: the same saved day the Lock Screen card shows.
        let day = PlanStore.shared.day(on: tomorrow, calendar: calendar) ?? {
            let source = CalendarSource(athlete: athlete, sessions: athlete.sessions, week: week, catalogue: catalogue, calendar: calendar)
            return PlannedDay(date: tomorrow, items: source.items(on: tomorrow))
        }()
        return (day.title, day.detail, day.kind)
    }

    /// Yesterday, if its scheduled practice has nothing logged and wasn't answered.
    private var practiceToAsk: Date? {
        _ = practiceRevision
        guard athlete.activeSport != nil, status == .active else { return nil }
        return PracticeRoutine.dayToAsk(
            now: clock,
            hadPractice: { PracticeSchedule.hasPractice(on: $0, calendar: calendar) && DayStatusStore.status(on: $0, calendar: calendar) == .active },
            logged: { PracticeLogStore.log(on: DayKey.of($0, calendar: calendar)) != nil },
            answered: { PracticeAnswers.answered(DayKey.of($0, calendar: calendar)) },
            calendar: calendar)
    }

    /// Practice weekdays the logs show but the schedule doesn't have.
    private var routineOffer: Set<Int>? {
        _ = practiceRevision
        guard status == .active, let sport = athlete.activeSport?.sportSlug else { return nil }
        let days = PracticeLogStore.logs.filter { $0.sportSlug == sport }.compactMap { TwinInputBuilder.day($0.day, calendar: calendar) }
        let offer = PracticeRoutine.proposal(inferred: PracticeRoutine.inferredWeekdays(days, now: clock, calendar: calendar),
                                             current: PracticeSchedule.weekdays, hasCalendar: !ScheduleStore.feeds.isEmpty,
                                             declinedUntil: PracticeAnswers.routineDeclinedUntil, now: clock)
        return offer.isEmpty ? nil : offer
    }

    private var scheduleCard: some View {
        AuraCard(.body, focus: UnitPoint(x: 0.85, y: 0.2), radius: 180) {
            VStack(alignment: .leading, spacing: 16) {
                Headline([.icon("person.3.fill"), .strong(" When is practice?"), .soft(" Your plan is built around it.")], size: 26)
                Text("Pick your team calendar on this phone and games, practices and cancellations come in by themselves.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Set up my schedule") { activeSheet = .schedule }
                    .buttonStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        .buttonStyle(.pressable)
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
        AuraCard(.calm) {
            VStack(alignment: .leading, spacing: 16) {
                Headline([.icon("pause.circle.fill"), .strong(" Training paused"), .soft(" until a doctor clears you after the head injury.")], size: 26)
                Button("Safety Center") { activeSheet = .safety }
                    .buttonStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                    .buttonStyle(.pressable)
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
                                .buttonStyle(.pressable)
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
                    .buttonStyle(.pressable)
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
                        WhyThisPlanPanel(explanation: explanation) {
                            dismiss()
                            AcademyNavigation.shared.openTwin()
                        }
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
        .buttonStyle(.pressable)
        .disabled(catalogueItem == nil)
    }
}



/// "Your plan changed" (docs/PLAN-CHANGES-RESEARCH.md P3–P5): one line per
/// day, before → after and the cause; more than three days fold into one
/// line with the list behind a tap. Gone once seen.
struct PlanChangeCard: View {
    let changes: [PlanChange]
    let event: String
    let onClose: () -> Void
    let onOpenWeek: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Plan changed", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Got it")
            }
            if changes.count > PlanChanges.summaryAfter && !expanded {
                Button { withAnimation { expanded = true } } label: {
                    HStack {
                        Text(PlanChanges.headline(changes, event: event) ?? "")
                            .font(.body)
                            .foregroundStyle(AppTheme.ink)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .buttonStyle(.pressable)
            } else {
                ForEach(changes) { change in
                    Text(PlanChanges.line(change, event: event))
                        .font(.body)
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(action: onOpenWeek) {
                Text("See your week")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.pressable)
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

/// What Home worked out for today, and from what (see `HomeView.refreshToday`).
/// Only read and written from Home's body, on the main thread.
final class HomeTodayMemo {
    struct Key: Equatable {
        let revision: Int
        let clock: Date
        let sessions: Int
        let checkIns: Int
        let competitions: [Date]
        let status: DayStatus
        let catalogue: Int
        let override: String
        let practiceDays: Set<Int>
        let week: GeneratedWeek?
    }

    var key: Key?
    var planning: PlanningEvaluation?
    var workout: (mode: WorkoutMode, session: GeneratedSession)?
}
