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
    @State private var showingGym = false
    @State private var showingImprove = false
    @State private var showingMuscles = false
    @State private var showingLibrary = false
    /// The recommended session's exercises, opened from the card (details one tap away).
    @State private var showingContents = false
    @State private var detailItem: CatalogueItem?
    @State private var showingMuscleExercises = false
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
            // The athlete's own word from the check-in wins over the schedule.
            if let said = TodayEngine.said(on: .now) {
                if said.choices.contains(.rest) { return (nil, "You chose a rest day. Rest is part of the plan.") }
                if said.choices.contains(.game) { return (.mobility, "\(eventWord) day: just loosen up and save your energy.") }
                if said.choices.contains(.light), !said.choices.contains(.gym) { return (.mobility, "You asked for something light today.") }
                if said.choices.contains(.gym), !said.choices.contains(.practice), let day = engineDay {
                    return (.gymDay, day.explanation?.summary ?? "You said: gym today.")
                }
            }
            if gameToday != nil { return (.mobility, "\(eventWord) day: just loosen up and save your energy.") }
            if practiceToday { return (.afterPractice, "You have practice today, so the gym work is short.") }
            if gymSession?.isToday == true { return (.gymDay, "No team practice today, so this is your main session.") }
            // The engine may still want a primer, recovery or conditioning day
            // (the same session Home shows).
            if let day = engineDay { return (.gymDay, day.explanation?.summary ?? "Today's session, built around your week.") }
            return (.mobility, "A rest day: a few minutes of movement keeps you fresh.")
        }
    }

    /// The athlete's own word for a competition ("match", "race", "meet"…).
    private var eventWord: String { AcademyContent.family(forSport: athlete.activeSport?.sportSlug).tokens["Event"] ?? "Game" }

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
            .sheet(isPresented: $showingGym) {
                GymSetupView(athlete: athlete, catalogue: catalogue,
                             onStart: { session in liveLaunch = LiveSessionLaunch(planned: session, kind: .gym) },
                             onPreview: { session in
                                 DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { preview = PreviewBox(session: session, kind: .gym) }
                             })
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
            .sheet(item: $detailItem) { item in
                NavigationStack { ItemDetailView(item: item, closes: true) }
            }
            .sheet(isPresented: $showingMuscleExercises) {
                MuscleExercisesSheet(catalogue: catalogue, athlete: athlete) { item in
                    showingMuscleExercises = false
                    detailItem = item
                }
            }
            .fullScreenCover(item: $liveLaunch) { launch in
                LiveSessionView(athlete: athlete, apiClient: apiClient, planned: launch.planned, kind: launch.kind)
            }
        }
    }

    // MARK: - Today

    /// The recommended workout for today (nil: rest).
    private var recommendedSession: GeneratedSession? {
        guard let mode = recommendation.mode else { return nil }
        return session(for: mode)
    }

    /// On a day without practice or a planned gym day: what the engine
    /// builds (a primer before a game, recovery, conditioning), as on Home.
    private var engineDay: GeneratedSession? {
        guard status == .active, gameToday == nil, !practiceToday, gymSession?.isToday != true,
              TodayEngine.isAvailable(catalogue) else { return nil }
        return TodayEngine.session(nil, athlete: athlete, sessions: athlete.sessions, catalogue: catalogue, plannedGymDay: false)
    }

    private func session(for mode: WorkoutMode) -> GeneratedSession? {
        switch mode {
        case .gymDay: engineDay ?? gymSession?.session
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
                                     daysToNextGame: daysToNextGame, readiness: readinessOverridden ? nil : DailyLoop.today(athlete), eventWord: eventWord)
    }

    /// Short tags: what today's workout is shaped around.
    private var focusTags: [String] {
        var tags: [String] = []
        if gameToday != nil {
            tags.append("\(eventWord) day")
        } else if let days = daysToNextGame, days >= 1, days <= 3 {
            tags.append(days == 1 ? "\(eventWord) tomorrow" : "\(eventWord) in \(days) days")
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
        // V8: the training card is ember; its aura sits on the minutes.
        return AuraCard(.training, focus: UnitPoint(x: 0.22, y: 0.42), radius: 210) {
        VStack(alignment: .leading, spacing: 14) {
            Text("Today's training")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.8))
                .accessibilityAddTraits(.isHeader)
            Text(recommendedSession?.decision != nil ? (recommendedSession?.title ?? "Rest today")
                 : (rec.mode.map { $0 == .gymDay ? (gymSession?.session.title ?? $0.title) : $0.title } ?? "Rest today"))
                .font(.system(size: 38, weight: .semibold))
                .tracking(-1)
                .foregroundStyle(AppTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if let session = recommendedSession, session.decision?.gymFocus != nil {
                // A gym day: why this focus, and one tap to change focus or length.
                Button { showingGym = true } label: {
                    HStack(spacing: 6) {
                        Text(session.decision?.gymNote ?? "Change what you train")
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "slider.horizontal.3").font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.9))
                    .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.pressable)
                .accessibilityHint("Change focus or length")
            }
            if let session = recommendedSession {
                // What it builds, in one short line (docs/TRAINING-RESEARCH.md §2).
                let builds = SessionTrains.builds(session.items, catalogue: catalogue)
                if !builds.isEmpty {
                    Headline([.soft("Builds "), .strong(PlanExplanation.list(builds))], size: 22)
                        .accessibilityRemoveTraits(.isHeader)
                }
                HStack(alignment: .lastTextBaseline, spacing: 16) {
                    BigFigure("\(session.estimatedMinutes)", unit: "min", size: 68)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(band == nil ? "Normal" : "Lighter")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                        Text("load")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.ink.opacity(0.7))
                    }
                }
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
            // The exercises and what each one trains: one tap away.
            if let session = recommendedSession, !session.items.isEmpty {
                Button { withAnimation(.easeInOut(duration: 0.25)) { showingContents.toggle() } } label: {
                    HStack(spacing: 5) {
                        Text("What's in it · \(session.items.count) exercises")
                        Image(systemName: showingContents ? "chevron.up" : "chevron.down").font(.caption2.weight(.bold))
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.8))
                    .frame(minHeight: 44)
                }
                .buttonStyle(.pressable)
                if showingContents {
                    sessionContents(session)
                        .transition(.opacity)
                }
            }
            // The reasoning is one tap away, not a paragraph at first sight.
            Button { withAnimation(.easeInOut(duration: 0.25)) { showingReason.toggle() } } label: {
                HStack(spacing: 5) {
                    Text("Why this workout?")
                    Image(systemName: showingReason ? "chevron.up" : "chevron.down").font(.caption2.weight(.bold))
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.8))
                .frame(minHeight: 44)
            }
            .buttonStyle(.pressable)
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
                .foregroundStyle(AppTheme.ink.opacity(0.8))
                .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 12)
    }

    /// Each exercise with what it trains ("Power · glutes, quads") and how
    /// much; tap one for how it's done. Warm-up and cool-down stay one line each.
    private func sessionContents(_ session: GeneratedSession) -> some View {
        let warmUp = session.items.filter { $0.block == .prep }
        let coolDown = session.items.filter { $0.block == .cooldown || $0.block == .mobility }
        let main = session.items.filter { item in !warmUp.contains(item) && !coolDown.contains(item) }
        return VStack(alignment: .leading, spacing: 0) {
            if !warmUp.isEmpty {
                summaryRow("Warm-up", warmUp)
            }
            ForEach(Array(main.enumerated()), id: \.offset) { _, planned in
                if let item = catalogue.item(planned.itemSlug) {
                    Button { detailItem = item } label: { exerciseRow(item, planned) }
                        .buttonStyle(.pressable)
                }
            }
            if !coolDown.isEmpty {
                summaryRow(session.items.contains { $0.block == .cooldown } ? "Cool-down" : "Mobility", coolDown)
            }
        }
        .padding(.vertical, 4)
    }

    private func exerciseRow(_ item: CatalogueItem, _ planned: GeneratedPlannedItem) -> some View {
        let profile = item.planProfile
        let trains = planned.block == .skill ? "Your sport · \(profile.trains.title.lowercased())" : profile.trainsLabel
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.leading)
                Text(trains)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.78))
                Text(DoseFormatter.text(planned.dose))
                    .font(.telemetry(12))
                    .foregroundStyle(AppTheme.ink.opacity(0.62))
                // How hard matters most where intensity is the point: fast work and the main lifts.
                if let effort = planned.effort, planned.block == .power || planned.block == .primaryStrength {
                    Text(effort)
                        .font(.caption)
                        .foregroundStyle(AppTheme.ink.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.5))
                .padding(.top, 4)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows how it's done")
    }

    private func summaryRow(_ title: String, _ items: [GeneratedPlannedItem]) -> some View {
        let names = items.compactMap { catalogue.item($0.itemSlug)?.name }
        return VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Text(names.joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
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

    /// V8: the week as a strip of tiles — today's in ember, the rest calm —
    /// each with its day, the workout and its length. Swipe sideways.
    @ViewBuilder
    private var weekSection: some View {
        if let week, !week.sessions.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader("This week", subtitle: isDeloadWeek(week)
                              ? "Deload week: lighter on purpose, so you come back stronger." : week.phase.focus)
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(Array(week.sessions.enumerated()), id: \.offset) { _, planned in
                            let session = rowSession(planned)
                            let isToday = calendar.isDateInToday(planned.date)
                            let isPast = !isToday && planned.date < .now
                            Button { preview = PreviewBox(session: session, kind: .gym, slot: planned.slot.map { PlanSlot.gym($0) }) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        Text(isToday ? "Today" : planned.date.formatted(.dateTime.weekday(.wide)))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AppTheme.ink.opacity(isToday ? 0.92 : 0.6))
                                        if let slot = planned.slot, custom.workout(for: .gym(slot)) != nil {
                                            Text("· yours").font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink.opacity(0.6))
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    Text(session.title)
                                        .font(.system(size: 20, weight: .bold))
                                        .tracking(-0.3)
                                        .foregroundStyle(AppTheme.ink)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                                        Text("\(session.estimatedMinutes)")
                                            .font(.system(size: 30, weight: .light).monospacedDigit())
                                        Text("min · \(session.items.count) exercises")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(AppTheme.ink.opacity(0.65))
                                    }
                                    .foregroundStyle(AppTheme.ink)
                                }
                                .frame(width: 172, height: 150, alignment: .leading)
                                .padding(16)
                                .background(AuraBackground(isToday ? .training : .calm, focus: UnitPoint(x: 0.2, y: 0.85), radius: 150))
                                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                                        .strokeBorder(Color.white.opacity(isToday ? 0.14 : 0.06), lineWidth: 1)
                                }
                                .opacity(isPast ? 0.55 : 1)
                            }
                            .buttonStyle(.pressable)
                            .accessibilityLabel("\(isToday ? "Today" : planned.date.formatted(.dateTime.weekday(.wide))): \(session.title), about \(session.estimatedMinutes) minutes")
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -20)
            }
        }
    }

    /// What a row of the week opens. Today's row opens the very session the
    /// card above shows, so the screen never offers two different "todays".
    private func rowSession(_ planned: GeneratedSession) -> GeneratedSession {
        guard calendar.isDateInToday(planned.date) else { return adjusted(planned) }
        if recommendation.mode == .gymDay, let today = recommendedSession { return today }
        if let today = gymSession, today.isToday { return today.session }
        return adjusted(planned)
    }

    private func isDeloadWeek(_ week: GeneratedWeek) -> Bool {
        Deload.isDeloadWeek(weekStart: week.weekStart, anchor: athlete.createdAt, phase: week.phase)
    }

    /// Everything that isn't today's session, in one list: the other modes,
    /// a skill or chosen muscles, the exercise library.
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
                    .buttonStyle(.pressable)
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
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Other workouts")
            // V8: one small tile per workout, lit in its activity colour.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(others, id: \.self) { mode in
                    let modeSession = session(for: mode)
                    Button {
                        // The gym: pick what to train and for how long.
                        if mode == .gymDay { showingGym = true }
                        else if let modeSession { preview = PreviewBox(session: modeSession, kind: kind(mode), slot: slot(for: mode, session: modeSession)) }
                    } label: {
                        workoutTile(mode, modeSession)
                    }
                    .buttonStyle(.pressable)
                    .disabled(modeSession == nil && mode != .gymDay)
                }
            }
            SectionHeader("Build and explore")
                .padding(.top, 12)
            VStack(spacing: 4) {
                Button { showingImprove = true } label: {
                    ListRow(systemImage: "target", color: AppTheme.ink, title: "Skill plans",
                            detail: skillPlanDays.isEmpty ? "Get better at one skill of your sport before a game" : "Your drills show up here and on Home")
                }
                .buttonStyle(.pressable)
                Button { showingMuscles = true } label: {
                    ListRow(systemImage: "figure.strengthtraining.traditional", color: AppTheme.ink, title: "Muscle workouts",
                            detail: "Pick the muscles, get a workout")
                }
                .buttonStyle(.pressable)
                Button { showingLibrary = true } label: {
                    ListRow(systemImage: "books.vertical", color: AppTheme.ink, title: "Exercise library",
                            detail: "Every exercise and drill, with how it looks")
                }
                .buttonStyle(.pressable)
                Button { showingMuscleExercises = true } label: {
                    ListRow(systemImage: "figure.stand", color: AppTheme.ink, title: "Exercises by muscle",
                            detail: "Tap a muscle: what trains it, and how")
                }
                .buttonStyle(.pressable)
            }
        }
        .sheet(isPresented: $showingLibrary) {
            LibraryView(athlete: athlete)
        }
    }

    /// A workout tile: its colour glowing from the corner, the glyph, the
    /// name, and the length as a big light number.
    private func workoutTile(_ mode: WorkoutMode, _ session: GeneratedSession?) -> some View {
        let tint = color(mode)
        return VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon(mode))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
            Spacer(minLength: 0)
            Text(mode.title)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let session {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(session.estimatedMinutes)")
                        .font(.system(size: 30, weight: .light).monospacedDigit())
                        .foregroundStyle(AppTheme.ink)
                    Text("min")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            } else {
                Text(detail(mode, session))
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .padding(16)
        .background {
            ZStack {
                LinearGradient(colors: AuraTone.calm.base, startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [tint.opacity(0.42), tint.opacity(0.12), .clear], center: UnitPoint(x: 0.1, y: 0.05),
                               startRadius: 0, endRadius: 170)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        }
        .opacity(session == nil ? 0.5 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mode.title), \(detail(mode, session))")
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

    /// The plan's settings in one place: the week's shape and the workouts the athlete changed.
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
                .buttonStyle(.pressable)
                // Only for athletes who built a new plan before that sheet was cut (focus cut).
                if planVariant > 0 {
                    Divider().padding(.leading, 54)
                    Button {
                        PlanVariant.backToOriginal()
                        onPlanInputsChanged()
                    } label: {
                        ListRow(systemImage: "arrow.uturn.backward", color: AppTheme.ink, title: "Back to my first plan")
                    }
                    .buttonStyle(.pressable)
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
                .buttonStyle(.secondary)
            }
        }
        .cardStyle(padding: 18)
    }
}
