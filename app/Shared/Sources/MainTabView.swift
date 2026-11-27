import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The tabs: Home (today), Academy (Twin · Campus) and Workout (what to do and,
/// in its training calendar, what was done) (owner, 2026-11-18; Progress moved
/// to Workout 2026-11-26). `.campus` routes into the Academy, `.progress` opens
/// the Workout tab's calendar.
/// Me is not a tab:
/// it opens from the profile button at the top left of every tab, and
/// anything that routes to `.me` opens it there.
enum AppTab: Hashable {
    case today, campus, academy, workout, progress, me
}

/// §15's five tabs. Owns the one generated week so Today and Plan can never
/// disagree about it, and regenerates it whenever something that feeds the
/// generator changes (a game added, the sport/season/equipment edited).
@MainActor
public struct MainTabView: View {
    let athlete: Athlete
    let apiClient: APIClient

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var week: GeneratedWeek?
    @State private var selectedTab: AppTab = DemoData.initialTab
    @State private var showingMe = false
    @AppStorage("healthPermissionAsked") private var healthPermissionAsked = false
    @State private var showingHealthPermission = false
    @AppStorage("appTourSeen") private var appTourSeen = false
    @State private var workoutContext: WorkoutContext?
    @State private var backingUp = false
    @State private var demoPaywall = false
    // Opened with a link or QR code: the team or workout it points to.
    @State private var linkSheet: DeepLink?
    @State private var linkMessage: String?
    @State private var startFromLink: CustomWorkout?
    @State private var liveFromLink: LiveSessionLaunch?

    public init(athlete: Athlete, apiClient: APIClient) {
        self.athlete = athlete
        self.apiClient = apiClient
    }

    private var tabView: some View {
        TabView(selection: $selectedTab) {
            HomeView(athlete: athlete, apiClient: apiClient, week: week, selectedTab: $selectedTab, onPlanInputsChanged: regenerate)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tint(AppTheme.accent)
                .modifier(FloatingTabBarSpace())
                .tag(AppTab.today)

            AcademyTabView(athlete: athlete, week: week, onPlanInputsChanged: regenerate)
                .tabItem { Label("Academy", systemImage: "figure.stand.line.dotted.figure.stand") }
                .tint(AppTheme.accent)
                .modifier(FloatingTabBarSpace())
                .tag(AppTab.academy)

            WorkoutTabView(athlete: athlete, apiClient: apiClient, week: week, onPlanInputsChanged: regenerate)
                .tabItem { Label("Workout", systemImage: "figure.strengthtraining.traditional") }
                .tint(AppTheme.accent)
                .modifier(FloatingTabBarSpace())
                .tag(AppTab.workout)
        }
        #if os(iOS)
        // V8: the floating pill tab bar replaces the system bar.
        .overlay(alignment: .bottom) {
            PillTabBar(selection: $selectedTab, items: [
                (AppTab.today, "Home", "house.fill"),
                (AppTab.academy, "Academy", "figure.stand.line.dotted.figure.stand"),
                (AppTab.workout, "Workout", "figure.strengthtraining.traditional"),
            ])
            .padding(.bottom, 2)
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        #endif
        .environment(\.openMe, OpenMeAction { showingMe = true })
        // V5: the selected tab is lit red; each screen keeps the white tint.
        .tint(AppTheme.brightRed)
        // Counted after the switch, never inside the tab bar's own binding
        // (a hand-made binding there sent lesson taps to the Me tab).
        .onChange(of: selectedTab) { previous, tab in
            // Me opens over the current tab instead of being one.
            if tab == .me {
                selectedTab = previous == .me ? .today : previous
                showingMe = true
                return
            }
            // The training calendar lives in the Workout tab.
            if tab == .progress {
                WorkoutNavigation.shared.showingCalendar = true
                selectedTab = .workout
                return
            }
            // Campus lives in the Academy.
            if let page = academyRoute(tab) {
                AcademyNavigation.shared.page = page
                selectedTab = .academy
                return
            }
            UsageCounts.count("tab.\(tab)")
        }
        // A cold start from Siri / Shortcuts.
        .onAppear {
            if selectedTab == .me {
                selectedTab = .today
                showingMe = true
            }
            if let page = academyRoute(selectedTab) {
                AcademyNavigation.shared.page = page
                selectedTab = .academy
            }
            if selectedTab == .progress {
                WorkoutNavigation.shared.showingCalendar = true
                selectedTab = .workout
            }
            switch IntentRoute.pending {
            case .workout?: _ = IntentRoute.take([.workout]); selectedTab = .workout
            case .logPractice?:
                WorkoutNavigation.shared.showingCalendar = true
                selectedTab = .workout
            case .tell?: selectedTab = .today
            default: break
            }
        }
    }

    /// Where an old Campus route lands in the Academy.
    private func academyRoute(_ tab: AppTab) -> AcademyPage? {
        switch tab {
        case .campus: return .campus
        default: return nil
        }
    }

    private var chrome: some View {
        tabView
        .modifier(CompactTabBar())
        .environment(\.workoutContext, workoutContext)
        .sheet(isPresented: $showingHealthPermission) {
            HealthPermissionView()
        }
        .sheet(isPresented: $showingMe) {
            MeView(athlete: athlete, onPlanInputsChanged: regenerate, onClose: { showingMe = false })
                .environment(\.workoutContext, workoutContext)
        }
        // Switching or adding a sport rebuilds the week for it.
        .onChange(of: athlete.activeSport?.id) { regenerate() }
        .onChange(of: athlete.sports.count) { regenerate() }
        .onChange(of: ProAccess.isPro) { regenerate() }
        // A check-in or a finished workout: the same week everywhere (Home,
        // Workout, widgets, Watch), not a throwaway copy for the widget.
        .onReceive(NotificationCenter.default.publisher(for: WeeklyPlan.inputsChanged)) { _ in regenerate() }
        // A "why" from the twin, tapped anywhere: its home is the Twin page.
        .onReceive(NotificationCenter.default.publisher(for: AcademyNavigation.openTwinRequested)) { _ in selectedTab = .academy }
        .proPaywall(isPresented: $demoPaywall, athlete: athlete, feature: .skillBlocks)
    }

    private var links: some View {
        chrome
        .sheet(item: $linkSheet, onDismiss: {
            if let workout = startFromLink {
                startFromLink = nil
                liveFromLink = LiveSessionLaunch(planned: workout.session(date: .now), kind: .gym)
            }
        }) { link in
            switch link {
            case .team(let code):
                MyTeamView(initialCode: code)
            case .workout(let code):
                SharedWorkoutSheet(initialCode: code, onSaved: { workout in
                    MyWorkoutsStore.upsert(workout)
                    selectedTab = .workout
                }, onStart: { workout in
                    startFromLink = workout
                })
            case .webLogin(let id):
                WebLoginApproveSheet(loginID: id)
            case .code:
                EmptyView()
            }
        }
        .fullScreenCover(item: $liveFromLink) { launch in
            LiveSessionView(athlete: athlete, apiClient: apiClient, planned: launch.planned, kind: launch.kind)
        }
        .alert("Couldn't open that code", isPresented: Binding(get: { linkMessage != nil }, set: { if !$0 { linkMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(linkMessage ?? "")
        }
        .onChange(of: DeepLinkCenter.shared.pending) {
            Task { await openPendingLink() }
        }
    }

    private var lifecycle: some View {
        links
        // A tapped notification opens the screen it is about.
        .onAppear(perform: takePushRoute)
        .onChange(of: PushRoute.shared.tab) { takePushRoute() }
        // Quietly checks for the coach's news while the app is open.
        .task(id: scenePhase) { await pollLiveUpdates() }
        // A tap on the lock-screen card while the app is already open.
        .onReceive(NotificationCenter.default.publisher(for: IntentRoute.didChange)) { note in
            // The route rides along: Home may already have taken it off the shelf.
            switch (note.object as? String).flatMap(IntentRoute.init(rawValue:)) {
            case .workout?: _ = IntentRoute.take([.workout]); selectedTab = .workout
            case .checkIn?, .reflection?, .tell?: selectedTab = .today
            default: break
            }
        }
    }

    public var body: some View {
        lifecycle
        // Back up when the athlete leaves the app, pick up other phones'
        // changes when they come back.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .active {
                Task { await backUp() }
            }
            if phase == .active {
                // Siri / Shortcuts: open the right tab (the screen takes the rest).
                switch IntentRoute.pending {
                case .workout?: _ = IntentRoute.take([.workout]); selectedTab = .workout
                case .checkIn?, .reflection?, .tell?: selectedTab = .today
                case .logPractice?: selectedTab = .progress
                case nil: break
                }
                StreakFreeze.protectTodayIfResting()
                Task {
                    await ExternalWorkoutStore.refresh(sportSlug: athlete.activeSport?.sportSlug, birthDate: athlete.birthDate)
                    await HeartStore.refresh()
                    // A workout from Health counts as today's training straight away.
                    if !athlete.isDeleted, HealthWorkoutInbox.importNew(athlete: athlete, context: modelContext) > 0 { regenerate() }
                }
            }
            if phase == .active, !DemoData.isEnabled {
                Task { await refreshAnimations() }
                Task { await LiveUpdates.shared.refresh(apiClient: apiClient) }
            }
        }
        .task {
            _ = RatingMoment.firstUse
            StreakFreeze.protectTodayIfResting()
            if !DemoData.isEnabled {
                await ExternalWorkoutStore.refresh(sportSlug: athlete.activeSport?.sportSlug, birthDate: athlete.birthDate)
                await HeartStore.refresh()
                HealthWorkoutInbox.importNew(athlete: athlete, context: modelContext)
            }
            workoutContext = WorkoutContext(athlete: athlete, apiClient: apiClient)
            #if os(iOS) && !APP_EXTENSION
            ProStore.shared.start(athlete: athlete)
            #endif
            // First run: a short tour of the five tabs, then (once) the
            // HealthKit ask, reason first — never two prompts stacked.
            if DemoData.showsPaywall { demoPaywall = true }
            // The tour stays in Me → Help; first run goes straight to the day
            // (Home's next step guides), with the one Health ask.
            if !appTourSeen { appTourSeen = true }
            askForHealthIfNeeded()
            regenerate()
            await openPendingLink()
            await backUp()
            // Keep the offline packs current: newer exercises, cues and
            // animations arrive without re-running setup.
            if !DemoData.isEnabled {
                for sport in athlete.sports {
                    await SportPackInstaller.install(slug: sport.sportSlug, context: modelContext)
                }
                regenerate()
                await refreshAnimations()
            }
        }
    }

    /// Pushes queued workouts and check-ins, syncs the backed-up documents
    /// (sports, games, plans, settings, Campus progress…) and pulls
    /// in recent workouts logged on another phone.
    private func backUp() async {
        guard !DemoData.isEnabled, !athlete.isDeleted, !backingUp else { return }
        backingUp = true
        defer { backingUp = false }
        SessionLogger(modelContext: modelContext).removeAbandoned()
        #if canImport(ActivityKit) && os(iOS) && !APP_EXTENSION
        if scenePhase == .active, liveFromLink == nil { WorkoutActivity.endLeftovers() }
        #endif
        #if os(iOS) && !APP_EXTENSION
        // Leaving the app: ask iOS for the few seconds the upload needs.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "backup")
        defer { UIApplication.shared.endBackgroundTask(backgroundTask) }
        #endif
        let sync = SyncQueue(apiClient: apiClient, tokenStore: KeychainTokenStore(), modelContext: modelContext)
        await sync.drainPendingSessions()
        await sync.drainPendingCheckIns()
        let reached = await CloudSync.sync(athlete: athlete, context: modelContext, apiClient: apiClient)
        if reached {
            await CloudSync.restoreRows(athlete: athlete, context: modelContext, apiClient: apiClient, full: false)
        }
        // Team and school calendars: new games, moved or cancelled practices, exams.
        if !athlete.isDeleted, scenePhase != .background {
            await CalendarSync.refresh(athlete: athlete, context: modelContext)
        }
        // Workouts and announcements from the coach.
        await CoachAssignments.refresh(apiClient: apiClient)
        await TeamAnnouncements.refresh(apiClient: apiClient)
        await PushSettings.syncIfNeeded(apiClient: apiClient)
        if !athlete.isDeleted, scenePhase != .background { regenerate() }
    }

    private func pollLiveUpdates() async {
        guard scenePhase == .active, !DemoData.isEnabled else { return }
        for _ in 0..<2000 {
            try? await Task.sleep(for: .seconds(45))
            if Task.isCancelled { break }
            await LiveUpdates.shared.refresh(apiClient: apiClient)
        }
    }

    private func takePushRoute() {
        guard let tab = PushRoute.shared.tab else { return }
        selectedTab = tab
        PushRoute.shared.tab = nil
    }

    /// Shows what a link or QR code points to. A bare code (aos://ABC234)
    /// is looked up first: is it a team or a workout?
    private func openPendingLink() async {
        guard let link = DeepLinkCenter.shared.pending, !DemoData.isEnabled else { return }
        DeepLinkCenter.shared.handled()
        guard case .code(let code) = link else {
            linkSheet = link
            return
        }
        do {
            let info = try await apiClient.lookUpCode(code)
            if let resolved = DeepLink.resolved(code: code, kind: info.kind) {
                linkSheet = resolved
            } else {
                linkMessage = "This version of the app doesn't know what \(code) is — update AthleteOS."
            }
        } catch APIClient.APIError.http(status: 404, _) {
            linkMessage = "No team or workout has the code \(code)."
        } catch {
            linkMessage = "Couldn't reach AthleteOS to open \(code) — check your connection and open the link again."
        }
    }

    /// Fixed or re-assigned exercise animations, published on the server,
    /// arrive without a new app version (AnimationLibrary).
    private func refreshAnimations() async {
        await AnimationLibrary.shared.refresh(packsBaseURL: apiClient.baseURL.appending(path: "packs"))
        await KnowledgeReleaseStore.refresh(baseURL: apiClient.baseURL)
    }

    private func askForHealthIfNeeded() {
        if !healthPermissionAsked, HealthKitManager.shared.isAvailable, !DemoData.isEnabled {
            showingHealthPermission = true
        }
    }

    private func regenerate() {
        // The one place the plan is made; every screen reads PlanStore.
        week = PlanStore.shared.rebuild(for: athlete)
        WidgetSnapshotWriter.write(for: athlete, week: week)
        let settings = ReminderScheduler.settings
        if settings.anyEnabled {
            // The sport's own word ("Race", "Match"…) for a plain game.
            let event = AcademyContent.family(forSport: athlete.activeSport?.sportSlug).tokens["Event"] ?? "Game"
            let games = AthleteStats.upcomingCompetitions(athlete).map { (date: $0.date, kind: $0.kind == .game ? event : $0.kind.rawValue.capitalized) }
            let tomorrow = PlanStore.shared.eveningLines()
            Task { await ReminderScheduler.reschedule(games: games, tomorrow: tomorrow) }
        }
    }
}

/// The tab bar shrinks while scrolling (iOS 26), so it never covers content.
private struct CompactTabBar: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// "Delete my plan and give me a new one": the weekly plan is built from the
/// athlete's inputs, so deleting it means building a different one — a new
/// variant changes the generator's seed (different exercises, same rules).
enum PlanVariant {
    static let key = "plans.variant"
    static var current: Int { UserDefaults.standard.integer(forKey: key) }
    static func buildNew() { UserDefaults.standard.set(current + 1, forKey: key) }
    static func set(_ variant: Int) { UserDefaults.standard.set(variant, forKey: key) }
    static func backToOriginal() { UserDefaults.standard.removeObject(forKey: key) }
    static func seed(_ base: String, variant: Int = current) -> String { variant == 0 ? base : "\(base)-v\(variant)" }
}

/// Shared by the Today and Plan tabs so the two can never disagree about
/// what "this week" is.
enum WeeklyPlan {
    /// Posted after a check-in is saved or a workout is finished: the tab
    /// view rebuilds the week once, and the widgets and the Watch with it.
    static let inputsChanged = Notification.Name("AthleteOS.weeklyPlanInputsChanged")

    /// What this week's plan is generated from (a plan variant other than the
    /// current one when building a new plan, and exercises to leave out).
    @MainActor
    static func input(for athlete: Athlete, variant: Int = PlanVariant.current, avoid: Set<String> = [],
                      catalogue: Catalogue? = nil, painAreas: Set<PainArea> = [], weekOf reference: Date = .now) -> PlanGeneratorInput? {
        guard let athleteSport = athlete.activeSport, let sportInfo = allSportsBySlug[athleteSport.sportSlug] else { return nil }
        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: reference)) ?? reference
        let basePosition = athleteSport.positionSlug.flatMap { slug in
            sportInfo.positions.first { $0.slug == slug }?.qualityProfile
        }
        let struggles: [Struggle] = Struggles.selected
        let positionProfile = struggles.isEmpty ? basePosition
            : Struggles.profile(base: basePosition ?? sportInfo.qualityProfile, struggles: struggles)
        let custom = PlanCustomizationStore.load()
        return PlanGeneratorInput(
            sportProfile: sportInfo.qualityProfile, positionProfile: positionProfile,
            seasonStart: athleteSport.seasonStart, seasonEnd: athleteSport.seasonEnd,
            weekStart: weekStart, birthDate: athlete.birthDate,
            trainsUnderCoach: athlete.trainsUnderCoach,
            equipmentAvailable: Set(athlete.equipmentAvailable),
            catalogue: catalogue ?? CatalogueLoader.load(from: AppConfig.packsDirectory()),
            seed: PlanVariant.seed("\(athlete.id)-\(Int(weekStart.timeIntervalSince1970))", variant: variant),
            timeBudgetMinutesPerSession: custom.settings.effectiveMinutesPerSession ?? 60,
            sportSlug: athleteSport.sportSlug, positionSlug: athleteSport.positionSlug, formatSlug: athleteSport.formatSlug,
            sessionsPerWeek: custom.settings.effectiveSessionsPerWeek,
            experience: TrainingExperience.current, avoid: avoid, painAreas: painAreas
        )
    }

    @MainActor
    /// The week that contains `reference` (this week by default; the plan of
    /// record also builds next week, so Sunday's "tomorrow" is real).
    static func generate(for athlete: Athlete, weekOf reference: Date = .now, catalogue: Catalogue? = nil) -> GeneratedWeek? {
        guard
            let athleteSport = athlete.activeSport,
            let sportInfo = allSportsBySlug[athleteSport.sportSlug]
        else { return nil }

        let calendar = Calendar.current
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: reference)
        ) ?? reference

        // The athlete's own say: how many gym days, which days, how long, and
        // their own version of any gym day.
        let custom = PlanCustomizationStore.load()
        guard let planInput = Self.input(for: athlete, catalogue: catalogue, weekOf: reference) else { return nil }
        let catalogue = planInput.catalogue
        let customized = PlanCustomizer.apply(custom, to: PlanGenerator.generate(planInput), catalogue: catalogue)
        // Every fifth week of the building phases is a planned deload.
        let deloaded = Deload.isDeloadWeek(weekStart: weekStart, anchor: athlete.createdAt, phase: customized.phase, calendar: calendar)
            ? Deload.apply(to: customized) : customized
        // Every gym day the app built starts with a warm-up for the sport
        // (the athlete's own versions stay exactly as they made them).
        let warmUpContext = WorkoutModeContext(
            catalogue: catalogue, sport: sportInfo, positionSlug: athleteSport.positionSlug, formatSlug: athleteSport.formatSlug,
            equipment: Set(athlete.equipmentAvailable), trainsUnderCoach: athlete.trainsUnderCoach,
            age: PlanGenerator.ageInYears(birthDate: athlete.birthDate, now: .now), prepMoment: .beforePractice
        )
        let generated = GeneratedWeek(phase: deloaded.phase, weekStart: deloaded.weekStart, sessions: deloaded.sessions.map { session in
            if let slot = session.slot, custom.workout(for: .gym(slot)) != nil { return session }
            return WorkoutModeBuilder.withWarmUp(session, warmUpContext)
        })
        // Every game counts, whatever sport it's for: the body that plays a
        // basketball game on Friday shouldn't squat heavy on Thursday.
        // Free tapers for the next game; Pro for every game in the week.
        // Next week (built ahead by the plan of record) tapers as that Monday will.
        let competitions = ProGate.competitionsForTaper(athlete.competitions.map(\.date), isPro: ProAccess.isPro,
                                                        now: max(reference, .now), calendar: calendar)
        let tapered = TaperApplier.apply(to: generated, competitions: competitions, contactLevel: sportInfo.contactLevel)
        // A practice cancelled today or later pulls a gym day onto that day.
        let startOfToday = calendar.startOfDay(for: .now)
        let cancelled = calendar.dateInterval(of: .weekOfYear, for: weekStart).map {
            ScheduleStore.imported.cancelledPracticeDays(in: $0, calendar: calendar).filter { $0 >= startOfToday }
        } ?? []
        // Days the athlete picked win over the automatic placement.
        let placed = custom.settings.weekdays.isEmpty
            ? alignToSchedule(tapered, isPracticeDay: { PracticeSchedule.hasPractice(on: $0, calendar: calendar) },
                              preferredDays: cancelled, gameDays: athlete.competitions.map(\.date), calendar: calendar)
            : PlanCustomizer.place(tapered, weekdays: custom.settings.weekdays, calendar: calendar)
        // Days the athlete can't train: the workout moves to the nearest free day.
        let aligned = BusyDays.moveOff(placed, isPracticeDay: { PracticeSchedule.hasPractice(on: $0, calendar: calendar) },
                                       gameDays: athlete.competitions.map(\.date), calendar: calendar)
        // V6: each gym day of the week is built by the engine for that day
        // (its games, school and season); the athlete's own versions stay theirs.
        if let aligned, TodayEngine.isAvailable(catalogue) {
            let rebuilt = aligned.sessions.map { planned -> GeneratedSession in
                if let slot = planned.slot, custom.workout(for: .gym(slot)) != nil { return planned }
                // On a practice day the strength session follows practice (the same one Today shows).
                let practiceDay = PracticeSchedule.hasPractice(on: planned.date, calendar: calendar)
                guard var built = TodayEngine.session(practiceDay ? .afterPractice : .gymDevelopment, athlete: athlete,
                                                      sessions: athlete.sessions, catalogue: catalogue,
                                                      date: planned.date, plannedGymDay: true) else { return planned }
                built.slot = planned.slot
                return built
            }
            let week = GeneratedWeek(phase: aligned.phase, weekStart: aligned.weekStart, sessions: rebuilt)
            return Deload.isDeloadWeek(weekStart: weekStart, anchor: athlete.createdAt, phase: week.phase, calendar: calendar)
                ? Deload.apply(to: week) : week
        }
        // Exam weeks: fewer, shorter sessions.
        guard let aligned, ScheduleStore.isExamWeek(weekStart, calendar: calendar) else { return aligned }
        return ExamWeek.lighten(aligned)
    }

    /// Gym days go on free days away from games first, then after a practice
    /// two or more days from a game, spread across the week, never on a game day.
    static func alignToSchedule(_ week: GeneratedWeek?, practiceWeekdays: Set<Int>, gameDays: [Date], calendar: Calendar = .current) -> GeneratedWeek? {
        alignToSchedule(week, isPracticeDay: { practiceWeekdays.contains(calendar.component(.weekday, from: $0)) },
                        preferredDays: [], gameDays: gameDays, calendar: calendar)
    }

    /// The same, for a schedule that changes week to week (a team calendar).
    /// `preferredDays` — days a practice was cancelled — get a gym session
    /// first: the gym day moves there.
    ///
    /// Where a gym day goes, best first (owner, 2026-11-27): a free day away
    /// from games; then a practice day two or more days from a game (the
    /// strength session follows practice, Part 2 A4); only then the day before
    /// or after a game, which would become a primer or recovery anyway. A team
    /// that practises Mon–Thu and plays Saturday used to get only those two —
    /// no real strength session all season.
    static func alignToSchedule(_ week: GeneratedWeek?, isPracticeDay: (Date) -> Bool, preferredDays: [Date],
                                gameDays: [Date], calendar: Calendar = .current) -> GeneratedWeek? {
        guard let week, !week.sessions.isEmpty else { return week }
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.weekStart) }
        let preferred = Set(preferredDays.map { calendar.startOfDay(for: $0) })
        guard days.contains(where: isPracticeDay) || !preferred.isEmpty else { return week }
        let games = Set(gameDays.map { calendar.startOfDay(for: $0) })
        func nextToGame(_ day: Date) -> Bool {
            let start = calendar.startOfDay(for: day)
            return games.contains { abs(calendar.dateComponents([.day], from: $0, to: start).day ?? 9) == 1 }
        }
        let open = days.filter { !games.contains(calendar.startOfDay(for: $0)) }
        let freeAway = open.filter { !isPracticeDay($0) && !nextToGame($0) }
        let practiceAway = open.filter { isPracticeDay($0) && !nextToGame($0) }
        let freeNext = open.filter { !isPracticeDay($0) && nextToGame($0) }
        let pool = freeAway + practiceAway + freeNext
        guard !pool.isEmpty else { return week }
        let count = min(week.sessions.count, pool.count)
        // Cancelled practices first, then the best kind of day, spread out within it.
        var chosen = Array(pool.filter { preferred.contains(calendar.startOfDay(for: $0)) }.prefix(count))
        for tier in [freeAway, practiceAway, freeNext] where chosen.count < count {
            let left = tier.filter { !chosen.contains($0) }
            let need = min(count - chosen.count, left.count)
            guard need > 0 else { continue }
            chosen += (0..<need).map { left[($0 * left.count) / need] }
        }
        chosen.sort()
        let sessions = week.sessions.prefix(chosen.count).enumerated().map { index, session in
            GeneratedSession(date: chosen[index], title: session.title, focusQualities: session.focusQualities,
                             estimatedMinutes: session.estimatedMinutes, items: session.items, slot: session.slot)
        }
        return GeneratedWeek(phase: week.phase, weekStart: week.weekStart, sessions: Array(sessions))
    }
}

/// Small, pure helpers over the athlete's own data that more than one tab
/// shows.
@MainActor
enum AthleteStats {
    static func todaysCheckIn(_ athlete: Athlete) -> CheckIn? {
        athlete.checkIns.first { Calendar.current.isDateInToday($0.date) }
    }

    static func upcomingCompetitions(_ athlete: Athlete) -> [Competition] {
        let today = Calendar.current.startOfDay(for: .now)
        return athlete.competitions
            .filter { Calendar.current.startOfDay(for: $0.date) >= today }
            .sorted { $0.date < $1.date }
    }

    static func daysUntil(_ date: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// The one streak: days with a check-in or a workout, and rest never
    /// breaks it. Up to two days in a row without either are rest days
    /// (they neither count nor break it); sick, travel, holiday and
    /// head-injury days (StreakFreeze) are skipped however many. Today not
    /// done yet is never a missed day. Only three days away in a row end it.
    static let restDaysAllowed = 2

    static func streak(checkInDates: [Date], sessionDates: [Date], frozen: Set<String> = StreakFreeze.days(),
                       now: Date = .now, calendar: Calendar = .current) -> Int {
        let active = Set((checkInDates + sessionDates).map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: now)
        var day = today
        var count = 0
        var rest = 0
        for _ in 0..<3650 {
            if active.contains(day) {
                count += 1
                rest = 0
            } else if day != today, !frozen.contains(DayKey.of(day, calendar: calendar)) {
                rest += 1
                if rest > restDaysAllowed { break }
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    static func sportName(_ athlete: Athlete) -> String {
        guard let slug = athlete.activeSport?.sportSlug else { return "" }
        return allSportsBySlug[slug]?.name ?? displayName(forSlug: slug)
    }

    static func phaseLabel(_ phase: SeasonPhase?) -> String {
        switch phase {
        case .offSeason: "Off-season"
        case .preSeason: "Pre-season"
        case .inSeason: "In-season"
        case .postSeason: "Post-season"
        case nil: "This week"
        }
    }
}

/// V8: the system tab bar is hidden (the pill floats instead) and every tab
/// keeps room at the bottom so nothing ends under the pill.
struct FloatingTabBarSpace: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 66).allowsHitTesting(false) }
        #else
        content
        #endif
    }
}
