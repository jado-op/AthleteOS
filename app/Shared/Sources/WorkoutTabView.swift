import SwiftData
import SwiftUI

/// Workout answers "what do I train?" (docs/CLARITY-PLAN.md): today's session
/// with one Start button, this week's gym days, then everything else in one
/// "More workouts" list, the athlete's own workouts and the plan's settings.
struct WorkoutTabView: View {
    let athlete: Athlete
    @State private var showingReason = false
    let apiClient: APIClient
    let week: GeneratedWeek?
    let onPlanInputsChanged: () -> Void

    @State private var catalogue = Catalogue()
    @State private var status: DayStatus = DayStatusStore.status()
    @State private var liveLaunch: LiveSessionLaunch?
    @State private var preview: PreviewBox?
    @State private var showingImprove = false
    @State private var showingMuscles = false
    @State private var showingProgram = false
    @State private var showingTogether = false
    @State private var showingLibrary = false
    // Making it yours: edit any workout, the week's shape, own workouts, sharing.
    @State private var editing: EditorTarget?
    @State private var sharing: ShareTarget?
    @State private var showingPlanSettings = false
    @State private var importing = false
    @State private var startAfterImport: CustomWorkout?
    @State private var afterPreview: AfterPreview?
    @State private var myWorkouts = MyWorkoutsStore.load()
    @State private var custom = PlanCustomizationStore.load()
    @State private var showingWorkoutsPaywall = false
    @State private var confirmingNewPlan = false
    /// "Train as planned instead": one choice for today, shared by Home and Workout.
    @AppStorage(ReadinessOverride.key) private var readinessOverrideDay = ""
    private var readinessOverridden: Bool {
        get { readinessOverrideDay == DayKey.of(.now) }
        nonmutating set { readinessOverrideDay = newValue ? DayKey.of(.now) : "" }
    }
    @AppStorage(PlanVariant.key) private var planVariant = 0

    private var calendar: Calendar { .current }
    private var sportInfo: SportInfo? { athlete.activeSport.flatMap { allSportsBySlug[$0.sportSlug] } }
    private var gameToday: Competition? { athlete.competitions.first { calendar.isDateInToday($0.date) } }
    private var practiceToday: Bool { PracticeSchedule.hasPractice(on: .now) }
    private var band: ReadinessBand? { readinessOverridden ? nil : DailyLoop.todayBand(athlete) }

    private var context: WorkoutModeContext {
        WorkoutModeContext(
            catalogue: catalogue, sport: sportInfo, positionSlug: athlete.activeSport?.positionSlug,
            formatSlug: athlete.activeSport?.formatSlug, equipment: Set(athlete.equipmentAvailable),
            trainsUnderCoach: athlete.trainsUnderCoach, age: PlanGenerator.ageInYears(birthDate: athlete.birthDate, now: .now),
            struggles: Struggles.selected,
            prepMoment: PrepMoment.at(.now, gameToday: gameToday != nil)
        )
    }

    /// Today's pain first (nothing that loads a sore area), then readiness.
    private func adjusted(_ session: GeneratedSession) -> GeneratedSession {
        if session.decision != nil { return session }
        let safe = calendar.isDateInToday(session.date) || session.slot == nil
            ? TodaysPain.apply(session, athlete: athlete, catalogue: catalogue) : session
        guard let band else { return safe }
        return ReadinessApplier.apply(to: safe, band: band).session
    }

    /// Today's gym session, or the next one this week.
    private var gymSession: (session: GeneratedSession, isToday: Bool)? {
        let sessions = week?.sessions ?? []
        if let today = sessions.first(where: { calendar.isDateInToday($0.date) }) {
            let own = today.slot.map { PlanCustomizationStore.load().workout(for: .gym($0)) != nil } ?? false
            if !own, let built = TodayEngine.session(nil, athlete: athlete, sessions: athlete.sessions, catalogue: catalogue, plannedGymDay: true) {
                return (built, true)
            }
            return (adjusted(today), true)
        }
        let start = calendar.startOfDay(for: .now)
        if let next = sessions.first(where: { $0.date > start }) ?? sessions.first { return (adjusted(next), false) }
        return nil
    }

    /// What to do today, and why.
    private var recommendation: (mode: WorkoutMode?, reason: String) {
        // The rules decide first: no added training when they say so. A
        // light mobility option stays available unless training is held.
        let planning = PlanningRules.today(athlete, sessions: athlete.sessions)
        if !planning.decision.allowsAddedTraining, status == .active, gameToday == nil {
            let mode: WorkoutMode? = planning.decision == .holdForProfessionalReview ? nil : .mobility
            return (mode, planning.explanation ?? "No added training today.")
        }
        switch status {
        case .sick: return (nil, "You're resting today, so there's no training.")
        case .concussion: return (nil, "Training is paused until a doctor clears you.")
        case .travel, .holiday: return (.travel, "A short workout you can do anywhere, only if you feel like it.")
        case .active:
            if gameToday != nil { return (.mobility, "Game day: just loosen up and save your energy.") }
            if practiceToday { return (.afterPractice, "You have practice today, so the gym work is short.") }
            if gymSession?.isToday == true { return (.gymDay, "No team practice today, so this is your main session.") }
            return (.mobility, "A rest day: a few minutes of movement keeps you fresh.")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ProfileButtonBar(name: athlete.displayName)
                    // Sport first: today's training, then the drills of the athlete's skill plans.
                    recommendedCard
                        .padding(.bottom, skillPlanDays.isEmpty ? 24 : 4)
                    skillDrillsToday
                    weekSection
                    GamesAndEventsSection(athlete: athlete, onPlanInputsChanged: onPlanInputsChanged)
                    moreWorkouts
                    // What the athlete's training has done to their body so far (gym second).
                    MuscleTrainingSection(athlete: athlete, catalogue: catalogue)
                        .padding(.top, 12)
                    myWorkoutsSection
                    customizeSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .padding(.bottom, 20)
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
            .appScreen(.hero)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                catalogue = CatalogueLoader.load(from: AppConfig.packsDirectory())
                status = DayStatusStore.status()
            }
            // Workouts added from a link, or restored from the backup, show up.
            .onAppear {
                myWorkouts = MyWorkoutsStore.load()
                custom = PlanCustomizationStore.load()
            }
            .sheet(item: $preview, onDismiss: { runAfterPreview() }) { box in
                SessionPreviewSheet(
                    session: box.session, catalogue: catalogue,
                    onStart: {
                        preview = nil
                        liveLaunch = LiveSessionLaunch(planned: box.session, kind: box.kind)
                    },
                    onEdit: editAction(for: box),
                    onShare: {
                        afterPreview = .share(box)
                        preview = nil
                    }
                )
            }
            .sheet(item: $editing) { target in
                // Plan workouts: swapping is free, the rest is Pro. Own workouts: all of it.
                WorkoutEditorView(heading: target.heading, workout: target.workout, sportSlug: athlete.activeSport?.sportSlug,
                                  fullAccess: target.slot == nil || ProAccess.isPro,
                                  onReset: resetAction(for: target)) { saved in
                    save(saved, for: target)
                }
            }
            .sheet(item: $sharing) { target in
                ShareWorkoutSheet(workout: target.workout, athlete: athlete) { code in
                    guard let id = target.myWorkoutID, var mine = myWorkouts.first(where: { $0.id == id }) else { return }
                    mine.shareCode = code
                    MyWorkoutsStore.upsert(mine)
                    myWorkouts = MyWorkoutsStore.load()
                }
            }
            .proFeature(isPresented: $showingWorkoutsPaywall, athlete: athlete, feature: .myWorkouts)
            .sheet(isPresented: $showingPlanSettings) {
                PlanSettingsSheet {
                    custom = PlanCustomizationStore.load()
                    onPlanInputsChanged()
                }
            }
            .sheet(isPresented: $importing, onDismiss: {
                if let workout = startAfterImport {
                    startAfterImport = nil
                    liveLaunch = LiveSessionLaunch(planned: workout.session(date: .now, catalogue: catalogue), kind: .gym)
                }
            }) {
                SharedWorkoutSheet(onSaved: { workout in
                    MyWorkoutsStore.upsert(workout)
                    myWorkouts = MyWorkoutsStore.load()
                }, onStart: { workout in
                    startAfterImport = workout
                })
            }
            .sheet(isPresented: $showingMuscles) {
                ImproveView(athlete: athlete, apiClient: apiClient, onPlanInputsChanged: onPlanInputsChanged, initialMode: .muscles)
            }
            .sheet(isPresented: $showingImprove) {
                ImproveView(athlete: athlete, apiClient: apiClient, onPlanInputsChanged: onPlanInputsChanged)
            }
            .fullScreenCover(item: $liveLaunch) { launch in
                LiveSessionView(athlete: athlete, apiClient: apiClient, planned: launch.planned, kind: launch.kind, partnerCode: launch.partnerCode)
            }
            // A new plan: generate it (randomize, swap single exercises) or build it yourself.
            .sheet(isPresented: $confirmingNewPlan) {
                NewGymPlanSheet(athlete: athlete, gymDays: week?.sessions.count ?? 3) {
                    custom = PlanCustomizationStore.load()
                    onPlanInputsChanged()
                }
            }
        }
    }

    // MARK: - Today

    /// The recommended workout for today (nil: rest).
    private var recommendedSession: GeneratedSession? {
        guard let mode = recommendation.mode else { return nil }
        return session(for: mode)
    }

    private func session(for mode: WorkoutMode) -> GeneratedSession? {
        switch mode {
        case .gymDay: gymSession?.session
        case .afterPractice:
            TodayEngine.workout(.afterPractice, athlete: athlete, sessions: athlete.sessions, catalogue: catalogue, context: context,
                                plannedGymDay: gymSession?.isToday == true).map { adjusted($0) }
        case .mobility, .travel:
            TodayEngine.workout(mode, athlete: athlete, sessions: athlete.sessions, catalogue: catalogue, context: context,
                                plannedGymDay: gymSession?.isToday == true).map { $0.decision != nil ? $0 : TodaysPain.apply($0, athlete: athlete, catalogue: catalogue) }
        }
    }

    private var daysToNextGame: Int? {
        AthleteStats.upcomingCompetitions(athlete).first.map { AthleteStats.daysUntil($0.date) }
    }

    /// Why this workout, in one sentence.
    private var reason: String {
        let rec = recommendation
        if rec.mode == .mobility, status == .active, gameToday == nil, !practiceToday, gymSession?.isToday != true {
            return rec.reason
        }
        return DailyLoop.whyThisPlan(status: status, mode: rec.mode, practiceToday: practiceToday, gameToday: gameToday != nil,
                                     daysToNextGame: daysToNextGame, readiness: readinessOverridden ? nil : DailyLoop.today(athlete))
    }

    /// Short tags: what today's workout is shaped around.
    private var focusTags: [String] {
        var tags: [String] = []
        if gameToday != nil {
            tags.append("Game day")
        } else if let days = daysToNextGame, days >= 1, days <= 3 {
            tags.append(days == 1 ? "Game tomorrow" : "Game in \(days) days")
        }
        if band != nil { tags.append("Lighter today") }
        if ScheduleStore.isExamWeek(.now) { tags.append("Exam week") }
        tags += Struggles.selected.prefix(2).map(\.title)
        return tags
    }

    private func purpose(_ mode: WorkoutMode) -> String {
        switch mode {
        case .afterPractice: "Strength and injury prevention, short enough to recover."
        case .gymDay: "Your main strength and power session."
        case .mobility: "Loosen up before training, or calm down after."
        case .travel: "No equipment: hotel room, bus, holiday."
        }
    }

    /// The session at a glance: its name, three numbers, Start. The reasoning
    /// is one tap away. The list below stays practical.
    private var recommendedCard: some View {
        let rec = recommendation
        return VStack(alignment: .leading, spacing: 14) {
            Text("Today's training")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.brightRed)
                .accessibilityAddTraits(.isHeader)
            Text(recommendedSession?.decision != nil ? (recommendedSession?.title ?? "Rest today")
                 : (rec.mode.map { $0 == .gymDay ? (gymSession?.session.title ?? $0.title) : $0.title } ?? "Rest today"))
                .font(.system(size: 38, weight: .semibold))
                .tracking(-1)
                .foregroundStyle(AppTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if let session = recommendedSession {
                HStack(alignment: .top, spacing: 26) {
                    TelemetryStat("\(session.estimatedMinutes)", "minutes")
                    // V6 §7: the number of exercises isn't the point — but it's a useful glance.
                    if session.decision == nil { TelemetryStat("\(session.items.count)", "exercises") }
                    TelemetryStat(band == nil ? "Normal" : "Lighter", "load", accent: band == nil ? nil : AppTheme.brightRed)
                }
                .padding(.top, 4)
            } else {
                Text(rec.mode.map(purpose) ?? "Recovery is part of the plan.")
                    .font(.body)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !focusTags.isEmpty {
                Text(focusTags.joined(separator: " · "))
                    .font(.telemetry(12))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            // The reasoning is one tap away, not a paragraph at first sight.
            Button { withAnimation(.easeInOut(duration: 0.25)) { showingReason.toggle() } } label: {
                HStack(spacing: 5) {
                    Text("Why this workout?")
                    Image(systemName: showingReason ? "chevron.up" : "chevron.down").font(.caption2.weight(.bold))
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.8))
                .frame(minHeight: 32)
            }
            .buttonStyle(.plain)
            if showingReason {
                Text(recommendedSession?.explanation?.summary ?? reason)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            if let mode = rec.mode, let session = recommendedSession {
                ButtonRow {
                    Button { liveLaunch = LiveSessionLaunch(planned: session, kind: kind(mode)) } label: {
                        HeroCTALabel("Start")
                    }
                    .buttonStyle(.primary)
                    Button("Preview") {
                        preview = PreviewBox(session: session, kind: kind(mode), slot: slot(for: mode, session: session))
                    }
                    .buttonStyle(.secondary)
                    .accessibilityLabel("View workout")
                }
                .padding(.top, 4)
            } else if rec.mode != nil {
                Text(catalogue.itemsBySlug.isEmpty ? "Loading your exercises…" : "Nothing fits your equipment yet. Add some in Me → Equipment.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            if band != nil || readinessOverridden {
                Button(readinessOverridden ? "Use the lighter version" : "Train as planned instead") {
                    readinessOverridden.toggle()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
    }

    private func detail(_ mode: WorkoutMode, _ session: GeneratedSession?) -> String {
        guard let session else { return "Nothing fits your equipment yet" }
        if mode == .gymDay, let gym = gymSession, !gym.isToday {
            return "\(session.estimatedMinutes) min · next on \(gym.session.date.formatted(.dateTime.weekday(.wide)))"
        }
        return "\(session.estimatedMinutes) min · \(session.items.count) exercises"
    }

    private func icon(_ mode: WorkoutMode) -> String {
        switch mode {
        case .afterPractice: "bolt.fill"
        case .gymDay: "dumbbell.fill"
        case .mobility: "figure.flexibility"
        case .travel: "suitcase.fill"
        }
    }

    private func kind(_ mode: WorkoutMode) -> WorkoutKind {
        switch mode {
        case .afterPractice: .afterPractice
        case .gymDay: .gym
        case .mobility: .mobility
        case .travel: .travel
        }
    }

    private func color(_ mode: WorkoutMode) -> Color {
        switch mode {
        case .afterPractice: ProgressColors.afterPractice
        case .gymDay: ProgressColors.workout
        case .mobility: ProgressColors.mobility
        case .travel: AppTheme.purple
        }
    }

    // MARK: - Week, more

    @ViewBuilder
    private var weekSection: some View {
        if let week, !week.sessions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("This week", subtitle: isDeloadWeek(week)
                              ? "Deload week: lighter on purpose, so you come back stronger." : week.phase.focus)
                VStack(spacing: 0) {
                    ForEach(Array(week.sessions.enumerated()), id: \.offset) { index, session in
                        Button { preview = PreviewBox(session: adjusted(session), kind: .gym, slot: session.slot.map { PlanSlot.gym($0) }) } label: {
                            HStack(spacing: 12) {
                                Text(session.date.formatted(.dateTime.weekday(.abbreviated)))
                                    .font(.headline)
                                    .foregroundStyle(calendar.isDateInToday(session.date) ? AppTheme.onAccent : AppTheme.ink)
                                    .frame(width: 52, height: 40)
                                    .background(calendar.isDateInToday(session.date) ? AppTheme.accent : AppTheme.fill, in: Capsule())
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(session.title).font(.headline).foregroundStyle(AppTheme.ink)
                                        if let slot = session.slot, custom.workout(for: .gym(slot)) != nil { Tag("Yours", color: AppTheme.brand) }
                                    }
                                    Text("About \(session.estimatedMinutes) min · \(session.items.count) exercises")
                                        .font(.caption).foregroundStyle(AppTheme.secondaryText)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(AppTheme.secondaryText)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if index < week.sessions.count - 1 { Divider().overlay(AppTheme.hairline) }
                    }
                }
                .cardStyle(padding: 14)
            }
        }
    }

    private func isDeloadWeek(_ week: GeneratedWeek) -> Bool {
        Deload.isDeloadWeek(weekStart: week.weekStart, anchor: athlete.createdAt, phase: week.phase)
    }

    /// Everything that isn't today's session, in one list: the other modes,
    /// a skill or chosen muscles, training together, an off-season program.
    /// Today's drills from saved skill plans.
    private var skillPlanDays: [SkillPlanDay] {
        guard !catalogue.itemsBySlug.isEmpty, status != .sick, status != .concussion else { return [] }
        return SavedSkillPlans.days(on: .now, athlete: athlete, catalogue: catalogue)
    }

    @ViewBuilder
    private var skillDrillsToday: some View {
        let days = skillPlanDays
        if !days.isEmpty {
            VStack(spacing: 0) {
                ForEach(days, id: \.block.id) { day in
                    Button { preview = PreviewBox(session: day.session) } label: {
                        ListRow(systemImage: "target", color: AppTheme.orange, title: "\(day.skillName) drills",
                                detail: "\(day.session.items.count) drills · \(day.session.estimatedMinutes) min · skill plan")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .glassSurface()
            .padding(.bottom, 20)
        }
    }

    private var moreWorkouts: some View {
        let recommended = recommendation.mode
        let all: [WorkoutMode] = [.afterPractice, .gymDay, .mobility, .travel]
        let others: [WorkoutMode] = all.filter { mode in mode != recommended }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Other workouts")
            VStack(spacing: 0) {
                ForEach(others, id: \.self) { mode in
                    let modeSession = session(for: mode)
                    Button {
                        if let modeSession { preview = PreviewBox(session: modeSession, kind: kind(mode), slot: slot(for: mode, session: modeSession)) }
                    } label: {
                        ListRow(systemImage: icon(mode), color: color(mode), title: mode.title, detail: detail(mode, modeSession))
                    }
                    .buttonStyle(.plain)
                    .disabled(modeSession == nil)
                    if mode != others.last { Divider().padding(.leading, 54) }
                }
            }
            .padding(12)
            .glassSurface()
            SectionHeader("Build and explore")
            VStack(spacing: 0) {
                Button { showingImprove = true } label: {
                    ListRow(systemImage: "target", color: AppTheme.orange, title: "Skill plans",
                            detail: skillPlanDays.isEmpty ? "Get better at one skill of your sport before a game" : "Your drills show up here and on Home")
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 54)
                Button { showingMuscles = true } label: {
                    ListRow(systemImage: "figure.strengthtraining.traditional", color: AppTheme.ink, title: "Muscle workouts",
                            detail: "Pick the muscles, get a workout")
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 54)
                Button { showingTogether = true } label: {
                    ListRow(systemImage: "person.2.fill", color: AppTheme.ink, title: "Train together",
                            detail: "Same workout with a partner or teammates")
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 54)
                Button { showingLibrary = true } label: {
                    ListRow(systemImage: "books.vertical", color: AppTheme.ink, title: "Exercise library",
                            detail: "Every exercise and drill, with how it looks")
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 54)
                Button { showingProgram = true } label: {
                    ListRow(systemImage: "calendar.badge.clock", color: AppTheme.ink, title: "Off-season program",
                            detail: ProgramStore.active.map { "\($0.goal.title) · week \($0.week() ?? 1) of \($0.weeks)" } ?? "One goal, 4–8 weeks, tested at both ends")
                }
                .buttonStyle(.plain)
            }
            .cardStyle(padding: 12)
        }
        .sheet(isPresented: $showingProgram) {
            ProgramsView(onChanged: onPlanInputsChanged)
        }
        .sheet(isPresented: $showingLibrary) {
            LibraryView(athlete: athlete)
        }
        .sheet(isPresented: $showingTogether) {
            TrainTogetherSheet(todays: recommendedSession) { session, code in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    liveLaunch = LiveSessionLaunch(planned: session, kind: .gym, partnerCode: code)
                }
            }
        }
    }

    // MARK: - Making it yours

    /// A workout being changed: a planned one (its slot) or one of the athlete's own.
    struct EditorTarget: Identifiable {
        let id = UUID()
        let heading: String
        let workout: CustomWorkout
        var slot: PlanSlot? = nil
    }

    struct ShareTarget: Identifiable {
        let id = UUID()
        let workout: CustomWorkout
        var myWorkoutID: UUID? = nil
    }

    /// What to open once the preview sheet has gone.
    enum AfterPreview {
        case edit(PreviewBox)
        case share(PreviewBox)
    }

    private func slot(for mode: WorkoutMode, session: GeneratedSession) -> PlanSlot? {
        mode == .gymDay ? session.slot.map { PlanSlot.gym($0) } : PlanSlot.mode(mode)
    }

    private func editAction(for box: PreviewBox) -> (() -> Void)? {
        guard box.slot != nil || box.myWorkoutID != nil else { return nil }
        return {
            afterPreview = .edit(box)
            preview = nil
        }
    }

    private func resetAction(for target: EditorTarget) -> (() -> Void)? {
        guard let slot = target.slot else { return nil }
        return { resetEdits(slot) }
    }

    private func runAfterPreview() {
        guard let next = afterPreview else { return }
        afterPreview = nil
        switch next {
        case .edit(let box):
            if let id = box.myWorkoutID, let mine = myWorkouts.first(where: { $0.id == id }) {
                editing = EditorTarget(heading: "Change workout", workout: mine)
            } else if let slot = box.slot {
                editSlot(slot)
            }
        case .share(let box):
            if let id = box.myWorkoutID, let mine = myWorkouts.first(where: { $0.id == id }) {
                sharing = ShareTarget(workout: mine, myWorkoutID: id)
            } else {
                sharing = ShareTarget(workout: CustomWorkout(session: box.session))
            }
        }
    }

    /// Opens the editor on the athlete's version of a planned workout (or the app's, to start from).
    private func editSlot(_ slot: PlanSlot) {
        let heading: String
        let base: GeneratedSession?
        switch slot {
        case .gym(let index):
            heading = "Gym day \(index + 1)"
            base = week?.sessions.first { $0.slot == index }
        case .mode(let mode):
            heading = mode.title
            base = WorkoutModeBuilder.build(mode, context)
        }
        let workout = custom.workout(for: slot) ?? base.map { CustomWorkout(session: $0) }
        guard let workout else { return }
        editing = EditorTarget(heading: heading, workout: workout, slot: slot)
    }

    private func save(_ workout: CustomWorkout, for target: EditorTarget) {
        if let slot = target.slot {
            PlanCustomizationStore.setWorkout(workout, for: slot)
            custom = PlanCustomizationStore.load()
            onPlanInputsChanged()
        } else {
            MyWorkoutsStore.upsert(workout)
            myWorkouts = MyWorkoutsStore.load()
        }
    }

    private func resetEdits(_ slot: PlanSlot) {
        PlanCustomizationStore.setWorkout(nil, for: slot)
        custom = PlanCustomizationStore.load()
        onPlanInputsChanged()
    }

    /// The plan's settings in one place: the week's shape, a new plan, and the workouts the athlete changed.
    private var customizeSection: some View {
        let settings = custom.settings
        let dayNames = Calendar.current.shortWeekdaySymbols
        let days = settings.weekdays.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }.map { dayNames[$0 - 1] }.joined(separator: ", ")
        let summary = [
            settings.weekdays.isEmpty ? (settings.sessionsPerWeek.map { "\($0) gym days a week" } ?? "Gym days picked for you") : days,
            settings.effectiveMinutesPerSession.map { "\($0) min each" } ?? "length picked for you",
        ].joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Your plan")
            VStack(spacing: 0) {
                Button { showingPlanSettings = true } label: {
                    ListRow(systemImage: "calendar", color: AppTheme.ink, title: "Gym days and length", detail: summary)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 54)
                Button { confirmingNewPlan = true } label: {
                    ListRow(systemImage: "arrow.triangle.2.circlepath", color: AppTheme.ink, title: "Build a new gym plan",
                            detail: "Generate one or build it yourself")
                }
                .buttonStyle(.plain)
                if planVariant > 0 {
                    Divider().padding(.leading, 54)
                    Button {
                        PlanVariant.backToOriginal()
                        onPlanInputsChanged()
                    } label: {
                        ListRow(systemImage: "arrow.uturn.backward", color: AppTheme.ink, title: "Back to my first plan")
                    }
                    .buttonStyle(.plain)
                }
            }
            .cardStyle(padding: 12)
            let edited = custom.sessions.keys.sorted()
            if !edited.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Workouts you changed").font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.secondaryText)
                    ForEach(edited, id: \.self) { key in
                        if let slot = slotFromKey(key), let workout = custom.sessions[key] {
                            HStack(spacing: 10) {
                                Text(label(slot)).font(.headline).foregroundStyle(AppTheme.ink)
                                Text(workout.title).font(.subheadline).foregroundStyle(AppTheme.secondaryText).lineLimit(1)
                                Spacer()
                                Button("Change") { editSlot(slot) }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                    }
                }
                .cardStyle(padding: 14)
            }
        }
    }

    private func slotFromKey(_ key: String) -> PlanSlot? {
        if key.hasPrefix("gym-"), let index = Int(key.dropFirst(4)) { return .gym(index) }
        if key.hasPrefix("mode-"), let mode = WorkoutMode(rawValue: String(key.dropFirst(5))) { return .mode(mode) }
        return nil
    }

    private func label(_ slot: PlanSlot) -> String {
        switch slot {
        case .gym(let index): "Gym day \(index + 1)"
        case .mode(let mode): mode.title
        }
    }

    /// Workouts the athlete built, or added with a code.
    private var myWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("My workouts", subtitle: "Your own, or one a teammate or coach shared.")
            ForEach(myWorkouts) { workout in
                myWorkoutCard(workout)
            }
            ButtonRow {
                Button {
                    if ProGate.canKeepAnotherWorkout(isPro: ProAccess.isPro, myWorkoutCount: myWorkouts.count) {
                        editing = EditorTarget(heading: "New workout", workout: CustomWorkout(title: "My workout", items: []))
                    } else {
                        showingWorkoutsPaywall = true
                    }
                } label: { Label("New workout", systemImage: "plus") }
                .buttonStyle(.secondary)
                Button { importing = true } label: { Label("Add with a code", systemImage: "qrcode.viewfinder") }
                    .buttonStyle(.secondary)
            }
        }
    }

    private func myWorkoutCard(_ workout: CustomWorkout) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.title).font(.title3.bold()).foregroundStyle(AppTheme.ink)
                    Text("\(workout.items.count) exercises · about \(workout.estimatedMinutes) min\(workout.shareCode.map { " · shared as \($0)" } ?? "")")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                #if os(iOS)
                Menu {
                    Button { editing = EditorTarget(heading: "Change workout", workout: workout) } label: { Label("Change it", systemImage: "slider.horizontal.3") }
                    Button { sharing = ShareTarget(workout: workout, myWorkoutID: workout.id) } label: { Label("Share", systemImage: "qrcode") }
                    Button(role: .destructive) {
                        MyWorkoutsStore.delete(workout.id)
                        myWorkouts = MyWorkoutsStore.load()
                    } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.fill, in: Circle())
                }
                .accessibilityLabel("More for \(workout.title)")
                #endif
            }
            ButtonRow {
                Button {
                    preview = PreviewBox(session: workout.session(date: .now, catalogue: catalogue), kind: .gym, myWorkoutID: workout.id)
                } label: { Label("View", systemImage: "list.bullet") }
                .buttonStyle(.secondary)
                Button {
                    liveLaunch = LiveSessionLaunch(planned: workout.session(date: .now, catalogue: catalogue), kind: .gym)
                } label: { Label("Start", systemImage: "play.fill") }
                .buttonStyle(.primary)
            }
        }
        .cardStyle(padding: 18)
    }
}
