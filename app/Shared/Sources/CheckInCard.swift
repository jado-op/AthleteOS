import SwiftData
import SwiftUI

extension DailyLoop {
    /// Today's readiness for this athlete: the morning check-in (against
    /// their own normal after a week), reported pain and last night's
    /// reflection. Nil before anything is known.
    @MainActor
    static func today(_ athlete: Athlete, now: Date = .now) -> (level: TodayReadiness, reason: String)? {
        let checkIn = AthleteStats.todaysCheckIn(athlete)
        let answers = checkIn.map {
            MorningAnswers(sleepQuality: $0.sleepQuality, sleepHours: $0.sleepHours, energy: $0.energy, soreness: $0.soreness, stress: $0.stress)
        }
        return readiness(answers: answers, personalBand: checkIn?.readinessBand, pain: PainStore.report(on: now),
                         yesterday: MindsetStore.yesterdaySignal(now: now),
                         painFollowUp: PainFollowUp.pending(reports: PainStore.all(), resolvedDays: PainFollowUp.resolvedDays(), today: now),
                         wearable: WearableLoad.reason(ExternalWorkoutStore.recent, now: now,
                                                       age: PlanGenerator.ageInYears(birthDate: athlete.birthDate, now: now),
                                                       practiceToday: PracticeSchedule.hasPractice(on: now) ? PracticeSchedule.time(on: now) : nil),
                         measuredSleep: MeasuredSleepStore.recent(now: now))
    }

    /// How today's training is adjusted (nil: as planned).
    @MainActor
    static func todayBand(_ athlete: Athlete) -> ReadinessBand? {
        guard let level = today(athlete)?.level, level > .normal else { return nil }
        return level.band
    }
}

/// The morning check-in (V3): about thirty seconds, one question at a time,
/// one tap each — what's on today, sleep, energy, soreness, pain, mood —
/// then today's readiness in words. Checking in again the same day edits
/// the day's answers (one check-in per day).
struct CheckInSheet: View {
    let athlete: Athlete

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    enum Step: Hashable { case loading, summary, context(Int), today, sleepHours, sleepQuality, energy, soreness, pain, painDetail, illness, mood, result }

    @State private var step: Step = .loading
    @State private var sleepHours: CheckInOption?
    @State private var sleepQuality: CheckInOption?
    @State private var energy: CheckInOption?
    @State private var soreness: CheckInOption?
    @State private var hasPain: Bool?
    @State private var painAreas: Set<PainArea> = []
    @State private var painLevel: PainLevel?
    @State private var mood: CheckInOption?
    /// Ill or under a new restriction (yes / no / not sure).
    @State private var illness: IllnessAnswer? = IllnessStore.answer()
    /// "What's on today?": the athlete decides; starts from what the schedule says.
    @State private var dayAnswer: DayAnswer
    /// Hours slept from Apple Health, when connected: pre-selects the answer.
    @State private var healthHours: Double?
    /// Where `healthHours` came from, named in the sleep question's hint.
    /// Recovery signals from a watch or band, against the athlete's normal.
    @State private var energyFromWatch = false
    /// Resting heart rate read the careful way (two nights, own usual; `HeartSignals`).
    @State private var heart: HeartMorning?
    /// Confirmed on the summary with pain: ask where, then save.
    @State private var saveAfterPain = false
    /// The summary exists: the step-by-step flow can go back to it.
    @State private var hasSummary = false
    /// Apple Health filled in sleep or energy (the summary shows where from).
    @State private var fromWatch = false
    @State private var canConnectHealth = false
    @State private var dayStatus = DayStatusStore.status()
    @State private var showingSafety = false
    @State private var saveCount = 0
    /// Follow-ups on what the athlete told AthleteOS ("You said your legs were
    /// very tired. How do they feel this morning?"): only what can change today's plan.
    @State private var contextQuestions: [ContextQuestion] = AthleteContextStore.questions()
    @State private var contextAnswers: [UUID: ContextQuestion.Answer] = [:]

    init(athlete: Athlete) {
        self.athlete = athlete
        let existing = AthleteStats.todaysCheckIn(athlete)
        _sleepHours = State(initialValue: CheckInOptions.nearest(existing?.sleepHours, in: CheckInOptions.sleepHours))
        _sleepQuality = State(initialValue: CheckInOptions.nearest(existing.map { Double($0.sleepQuality) }, in: CheckInOptions.sleepQuality))
        _energy = State(initialValue: CheckInOptions.nearest(existing.map { Double($0.energy) }, in: CheckInOptions.energy))
        _soreness = State(initialValue: CheckInOptions.nearest(existing.map { Double($0.soreness) }, in: CheckInOptions.soreness))
        _mood = State(initialValue: CheckInOptions.nearest(existing.map { Double($0.stress) }, in: CheckInOptions.mood))
        let pain = PainStore.report()
        _hasPain = State(initialValue: existing == nil && pain == nil ? nil : pain != nil)
        _painAreas = State(initialValue: Set(pain?.areas ?? []))
        _painLevel = State(initialValue: pain?.level)
        _dayAnswer = State(initialValue: DayChoicePicker.startingAnswer(
            practiceToday: PracticeSchedule.hasPractice(on: .now),
            gameToday: athlete.competitions.contains { Calendar.current.isDateInToday($0.date) }))
    }

    private var steps: [Step] {
        // A legs follow-up already says how sore the athlete is: no second question about it.
        contextQuestions.indices.map { Step.context($0) } + [.today, .sleepHours, .sleepQuality, .energy]
            + (legsAsked ? [] : [.soreness]) + [.pain] + (hasPain == true ? [.painDetail] : []) + [.illness, .mood]
    }

    /// A follow-up covers the legs, so its answer stands in for "How sore are you?".
    private var legsAsked: Bool { contextQuestions.contains { $0.covers.contains(.lower) } }

    private var contextAnswered: Bool { contextQuestions.allSatisfy { contextAnswers[$0.id] != nil } }

    private func answerContext(_ question: ContextQuestion, _ answer: ContextQuestion.Answer) {
        contextAnswers[question.id] = answer
        if question.covers.contains(.lower) {
            // The most tired legs answer sets soreness.
            let values = contextQuestions.filter { $0.covers.contains(.lower) }.compactMap { contextAnswers[$0.id] }
                .map { AthleteContext.soreness(for: $0) }
            soreness = CheckInOptions.nearest(Double(values.max() ?? 1), in: CheckInOptions.soreness)
        }
    }

    private var progress: Double {
        guard let index = steps.firstIndex(of: step) else { return 1 }
        return Double(index) / Double(steps.count)
    }

    var body: some View {
        ZStack {
            page
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
        }
        .sensoryFeedback(.success, trigger: saveCount)
        .task {
            canConnectHealth = await HealthKitManager.shared.needsAuthorization()
            await loadHealth()
            // With a watch or band's data, or an earlier check-in to start
            // from: one screen to confirm or edit. The very first check-in
            // goes step by step (and the summary keeps that one tap away).
            fromWatch = healthHours != nil || energyFromWatch
            hasSummary = fromWatch || lastCheckIn != nil || AthleteStats.todaysCheckIn(athlete) != nil
            withAnimation(.easeInOut(duration: 0.2)) { step = hasSummary ? .summary : (steps.first ?? .today) }
        }
        .sheet(isPresented: $showingSafety) { SafetyCenterView() }
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appScreen()
        case .summary:
            summaryPage
        case .context(let index):
            contextPage(index)
        case .today:
            QuestionPage(progress: progress, question: "What's on today?", hint: todayHint,
                         buttonTitle: "Next", buttonEnabled: !dayAnswer.choices.isEmpty,
                         onClose: { dismiss() }, onBack: todayBack, onButton: { next(from: .today) }, tone: .body) {
                DayChoicePicker(answer: $dayAnswer, gameWord: gameWord)
            }
        case .sleepHours:
            question("How long did you sleep?", hint: healthHours.map { "Apple Health: \(SleepMath.label($0))" },
                     options: CheckInOptions.sleepHours, selection: $sleepHours) {
                if canConnectHealth {
                    Button {
                        Task {
                            _ = await HealthKitManager.shared.requestAuthorization()
                            canConnectHealth = false
                            await loadHealth()
                        }
                    } label: {
                        Label("Fill in from Apple Health", systemImage: "heart.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .sleepQuality:
            question("How well did you sleep?", options: CheckInOptions.sleepQuality, selection: $sleepQuality)
        case .energy:
            question("How is your energy?", hint: heart?.note, options: CheckInOptions.energy, selection: $energy)
        case .soreness:
            question("How sore are you?", hint: "Normal muscle soreness from training.", options: CheckInOptions.soreness, selection: $soreness)
        case .pain:
            QuestionPage(progress: progress, question: "Any pain or discomfort?", hint: "Something that hurts — not normal soreness.",
                         buttonTitle: hasPain == nil ? nil : "Next", onClose: { dismiss() }, onBack: { back() }, onButton: { next(from: .pain) },
                         tone: .body) {
                ChoiceGrid([false, true], title: { (answer: Bool) -> String in answer ? "Yes" : "No" },
                           isSelected: { (answer: Bool) -> Bool in answer == hasPain }) { (answer: Bool) in
                    hasPain = answer
                    if !answer {
                        painAreas = []
                        painLevel = nil
                    }
                    advance(from: .pain)
                }
            }
        case .painDetail:
            QuestionPage(progress: progress, question: "Where does it hurt?", hint: "Tap every place, then how much.",
                         buttonEnabled: !painAreas.isEmpty && painLevel != nil,
                         onClose: { dismiss() }, onBack: { back() }, onButton: { next(from: .painDetail) }) {
                ChoiceGrid(PainArea.allCases, title: { (area: PainArea) -> String in area.title },
                           isSelected: { (area: PainArea) -> Bool in painAreas.contains(area) }) { (area: PainArea) in
                    if painAreas.contains(area) { painAreas.remove(area) } else { painAreas.insert(area) }
                }
                Text("How much?")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.top, 6)
                ChoiceGrid(PainLevel.allCases, title: { (level: PainLevel) -> String in level.title },
                           isSelected: { (level: PainLevel) -> Bool in level == painLevel }) { (level: PainLevel) in painLevel = level }
                if painAreas.contains(.head) {
                    HeadKnockNote()
                }
            }
        case .illness:
            QuestionPage(progress: progress, question: "Are you ill, or told to hold back?",
                         hint: "By a doctor, athletic trainer or coach. Not sure is a fine answer.",
                         buttonTitle: illness == nil ? nil : "Next", onClose: { dismiss() }, onBack: { back() }, onButton: { next(from: .illness) },
                         tone: .body) {
                ChoiceGrid(IllnessAnswer.allCases, title: { (answer: IllnessAnswer) -> String in answer.title },
                           isSelected: { (answer: IllnessAnswer) -> Bool in answer == illness }) { (answer: IllnessAnswer) in
                    illness = answer
                    advance(from: .illness)
                }
            }
        case .mood:
            question("How do you feel today?", hint: "Mood and stress — school, home, anything.", options: CheckInOptions.mood, selection: $mood)
        case .result:
            resultPage
        }
    }

    @ViewBuilder
    private func contextPage(_ index: Int) -> some View {
        if contextQuestions.indices.contains(index) {
            let question = contextQuestions[index]
            let current = Step.context(index)
            let chosen = contextAnswers[question.id]
            let backAction: (() -> Void)? = hasSummary || index > 0 ? { back() } : nil
            QuestionPage(progress: progress, question: question.question,
                         hint: [question.eyebrow, question.context].compactMap { $0 }.joined(separator: " · "),
                         buttonTitle: chosen == nil ? nil : "Next", onClose: { dismiss() },
                         onBack: backAction, onButton: { next(from: current) }, tone: .body) {
                ChoiceGrid(question.options.map(\.answer), title: { (answer: ContextQuestion.Answer) -> String in
                    question.options.first { $0.answer == answer }?.title ?? ""
                }, isSelected: { (answer: ContextQuestion.Answer) -> Bool in answer == chosen }) { (answer: ContextQuestion.Answer) in
                    answerContext(question, answer)
                    if answer != .worse { advance(from: current) }
                }
                if chosen == .worse {
                    // Worse can mean pain: the next questions ask, and pain is never trained through.
                    Text("If it hurts rather than feels tired, say yes when it asks about pain.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The follow-ups on the summary page: the question, its context, the answers as chips.
    @ViewBuilder
    private var contextSummary: some View {
        ForEach(contextQuestions) { question in
            VStack(alignment: .leading, spacing: 8) {
                if let context = question.context {
                    Text("\(question.eyebrow) · \(context)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(question.question).font(.headline).foregroundStyle(AppTheme.ink)
                WrapLayout(spacing: 8) {
                    ForEach(question.options, id: \.self) { option in
                        Button { answerContext(question, option.answer) } label: {
                            Chip(option.title, isSelected: contextAnswers[question.id] == option.answer)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var gameWord: String {
        AcademyContent.family(forSport: athlete.activeSport?.sportSlug).tokens["Event"] ?? "Game"
    }

    private var todayHint: String {
        DayChoicePicker.scheduleHint(practiceToday: PracticeSchedule.hasPractice(on: .now), practiceTime: PracticeSchedule.time(on: .now),
                                     game: athlete.competitions.first(where: { Calendar.current.isDateInToday($0.date) })?.date,
                                     gameWord: gameWord)
    }

    /// The first question goes back to the summary when there is one.
    private var todayBack: (() -> Void)? {
        guard hasSummary else { return nil }
        return { back() }
    }

    private func question(
        _ text: String, hint: String? = nil, options: [CheckInOption], selection: Binding<CheckInOption?>
    ) -> some View {
        question(text, hint: hint, options: options, selection: selection) { EmptyView() }
    }

    private func question<Extra: View>(
        _ text: String, hint: String? = nil, options: [CheckInOption], selection: Binding<CheckInOption?>,
        @ViewBuilder extra: () -> Extra
    ) -> some View {
        let current = step
        let backAction: (() -> Void)? = { back() }
        let buttonTitle: String? = selection.wrappedValue == nil ? nil : (current == steps.last ? "Save" : "Next")
        return QuestionPage(progress: progress, question: text, hint: hint, buttonTitle: buttonTitle,
                            onClose: { dismiss() }, onBack: backAction, onButton: { next(from: current) }, tone: .body) {
            ChoiceGrid(options, title: { (option: CheckInOption) -> String in option.title },
                       isSelected: { (option: CheckInOption) -> Bool in option == selection.wrappedValue }) { (option: CheckInOption) in
                selection.wrappedValue = option
                advance(from: current)
            }
            extra()
        }
    }

    // MARK: Moving through

    /// After a tap: a moment to see the choice, then the next question.
    private func advance(from current: Step) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            next(from: current)
        }
    }

    private func next(from current: Step) {
        if current == .painDetail, saveAfterPain, step == .painDetail {
            save()
            return
        }
        guard step == current, let index = steps.firstIndex(of: current) else { return }
        if index + 1 < steps.count {
            withAnimation(.easeInOut(duration: 0.25)) { step = steps[index + 1] }
        } else {
            save()
        }
    }

    private func back() {
        if hasSummary, step == steps.first || step == .today || step == .sleepHours || (saveAfterPain && step == .painDetail) {
            saveAfterPain = false
            withAnimation(.easeInOut(duration: 0.2)) { step = .summary }
            return
        }
        guard let index = steps.firstIndex(of: step), index > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) { step = steps[index - 1] }
    }

    private func loadHealth() async {
        healthHours = await HealthKitManager.shared.sleepHours()
        if let healthHours { MeasuredSleepStore.save(healthHours) }
        // The heart, read one way everywhere (`HeartSignals`): one device, two
        // nights, the athlete's own 28-night usual.
        await HeartStore.refresh()
        heart = HeartStore.morning()
        if sleepHours == nil, let healthHours {
            sleepHours = CheckInOptions.nearest(healthHours, in: CheckInOptions.sleepHours)
        }
        if sleepQuality == nil, let healthHours {
            sleepQuality = CheckInOptions.nearest(Double(WearablePrefill.sleepQuality(hours: healthHours)), in: CheckInOptions.sleepQuality)
        }
        // One morning is noise (research T3): energy is guessed from the heart
        // only against 14+ nights of the athlete's own usual, and never when
        // it has been raised two nights — then the athlete is asked (T12).
        if let heart, let level = HeartSignals.energyPrefill(heart) {
            energyFromWatch = true
            if energy == nil { energy = CheckInOptions.nearest(Double(level), in: CheckInOptions.energy) }
        }
        // What can't be measured starts as yesterday's answer (the summary says so).
        if let last = lastCheckIn {
            if soreness == nil { soreness = CheckInOptions.nearest(Double(last.soreness), in: CheckInOptions.soreness) }
            if mood == nil { mood = CheckInOptions.nearest(Double(last.stress), in: CheckInOptions.mood) }
        }
    }

    /// The most recent check-in before today.
    private var lastCheckIn: CheckIn? {
        let today = Calendar.current.startOfDay(for: .now)
        return athlete.checkIns.filter { $0.date < today }.max { $0.date < $1.date }
    }

    // MARK: Summary (a watch or band filled it in)

    private var energyDetail: String? {
        guard let heart, let usual = heart.usual, let latest = heart.lastTwo.last else { return nil }
        return "Resting heart rate \(Int(latest.rounded())) (usually \(Int(usual.rounded())))"
    }

    private var summaryPage: some View {
        QuestionPage(progress: 0, question: "Your morning",
                     hint: fromWatch ? "Filled in from Apple Health. Confirm, or change anything." : "Tap what's true this morning, then confirm.",
                     buttonTitle: "Confirm", buttonEnabled: sleepQuality != nil && energy != nil && soreness != nil && mood != nil && hasPain != nil && illness != nil
                        && !dayAnswer.choices.isEmpty && contextAnswered,
                     onClose: { dismiss() }, onButton: { confirm() }, tone: .body) {
            contextSummary
            if !fromWatch {
                // Nothing measured: this morning's sleep and energy as taps, right here.
                compactRow("Sleep", hint: nil, CheckInOptions.sleepHours, selection: $sleepHours)
                compactRow("Sleep quality", hint: nil, CheckInOptions.sleepQuality, selection: $sleepQuality)
                if let note = heart?.note { heartNote(note) }
                compactRow("Energy", hint: nil, CheckInOptions.energy, selection: $energy)
            } else {
            if let note = heart?.note { heartNote(note) }
            VStack(spacing: 0) {
                Button { edit(from: .sleepHours) } label: {
                    ListRow(systemImage: "moon.fill", color: AppTheme.purple,
                            title: healthHours.map { "Sleep · \(SleepMath.label($0))" } ?? "Sleep · not recorded",
                            detail: sleepQuality.map { "Quality: \($0.title.lowercased())" } ?? "Tap to answer") { editMark }
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 54)
                Button { edit(from: .energy) } label: {
                    ListRow(systemImage: "bolt.fill", color: AppTheme.amber,
                            title: energy.map { "Energy · \($0.title)" } ?? "Energy",
                            detail: heart?.note != nil ? "Tap to answer" : (energyFromWatch ? energyDetail : "Tap to answer")) { editMark }
                }
                .buttonStyle(.plain)
            }
            .cardStyle(padding: 12)
            }
            compactRow("Soreness", hint: legsAsked && contextAnswered ? "from your answer above" : lastCheckIn == nil ? nil : "like yesterday — tap to change",
                       CheckInOptions.soreness, selection: $soreness)
            VStack(alignment: .leading, spacing: 8) {
                Text("Any pain or discomfort?").font(.headline).foregroundStyle(AppTheme.ink)
                WrapLayout(spacing: 8) {
                    ForEach([false, true], id: \.self) { answer in
                        Button {
                            hasPain = answer
                            if !answer { painAreas = []; painLevel = nil }
                        } label: { Chip(answer ? "Yes" : "No", isSelected: hasPain == answer) }
                        .buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Ill, or told to hold back?").font(.headline).foregroundStyle(AppTheme.ink)
                WrapLayout(spacing: 8) {
                    ForEach(IllnessAnswer.allCases, id: \.self) { answer in
                        Button { illness = answer } label: { Chip(answer.title, isSelected: illness == answer) }
                            .buttonStyle(.plain)
                    }
                }
            }
            compactRow("Mood", hint: lastCheckIn == nil ? nil : "like yesterday — tap to change", CheckInOptions.mood, selection: $mood)
            VStack(alignment: .leading, spacing: 8) {
                Text("What's on today?").font(.headline).foregroundStyle(AppTheme.ink)
                WrapLayout(spacing: 8) {
                    ForEach(DayChoice.order) { choice in
                        Button { dayAnswer = dayAnswer.toggling(choice) } label: {
                            Chip(choice == .game ? gameWord : choice.title, isSelected: dayAnswer.choices.contains(choice))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if dayAnswer.choices.contains(.practice) {
                    WrapLayout(spacing: 8) {
                        ForEach(PracticeIntensity.choices, id: \.self) { level in
                            Button { dayAnswer = DayAnswer(choices: dayAnswer.choices, practice: level) } label: {
                                Chip("Practice: \(level.choiceTitle.lowercased())", isSelected: dayAnswer.practice == level)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Button("Edit step by step") { edit(from: .today) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private var editMark: some View {
        Text("Edit")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.secondaryText)
    }

    /// The heart's two signs, said where the athlete answers how they feel:
    /// a sentence to read, not fine print next to a title.
    private func heartNote(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.subheadline)
                .foregroundStyle(AuraTone.body.mark)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text(note)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
    }

    private func compactRow(_ title: String, hint: String?, _ options: [CheckInOption], selection: Binding<CheckInOption?>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.headline).foregroundStyle(AppTheme.ink)
                if let hint {
                    Text(hint).font(.caption).foregroundStyle(AppTheme.secondaryText)
                }
            }
            WrapLayout(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button { selection.wrappedValue = option } label: {
                        Chip(option.title, isSelected: selection.wrappedValue == option)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func edit(from start: Step) {
        saveAfterPain = false
        withAnimation(.easeInOut(duration: 0.25)) { step = start }
    }

    /// Confirm: saves straight away — or first asks where it hurts.
    private func confirm() {
        if hasPain == true {
            saveAfterPain = true
            withAnimation(.easeInOut(duration: 0.25)) { step = .painDetail }
        } else {
            save()
        }
    }

    private func save() {
        guard let sleepQuality, let energy, let soreness, let mood else { return }
        ReminderScheduler.markDone(checkIn: true)
        let twinBefore = TwinPulse.before(athlete)
        let day = DayKey.of(.now)
        // The follow-ups: back to normal closes them; anything else keeps them open for tomorrow.
        for question in contextQuestions {
            if let answer = contextAnswers[question.id] { AthleteContextStore.answer(answer, to: question) }
        }
        // The athlete's word on today wins over the schedule (and sets the
        // day's practice override only when it differs from it).
        DayChoiceStore.set(dayAnswer)
        // The exact hours from Apple Health when the answer agrees with them.
        let hours = healthHours.flatMap { CheckInOptions.nearest($0, in: CheckInOptions.sleepHours) == sleepHours ? $0 : nil }
            ?? sleepHours.flatMap { $0.value > 0 ? $0.value : nil }
        _ = try? CheckInStore(modelContext: modelContext).submit(
            athlete: athlete, sleepQuality: sleepQuality.scale, sleepHours: hours,
            soreness: soreness.scale, energy: energy.scale, stress: mood.scale
        )
        let areas = PainArea.allCases.filter { painAreas.contains($0) }
        let hadPain = PainStore.report() != nil
        PainStore.set(hasPain == true && !areas.isEmpty ? PainReport(day: day, areas: areas, level: painLevel ?? .little) : nil)
        if hasPain == true, !areas.isEmpty {
            HealthShare.send(kind: "pain", areas: areas, level: painLevel ?? .little)
        } else if hadPain {
            HealthShare.send(kind: "painGone")
        }
        IllnessStore.set(illness)
        // "No pain" today: a pain reported on an earlier day is gone.
        if hasPain == false { PainFollowUp.markResolved() }
        TwinPulse.after(athlete, before: twinBefore, input: .checkIn)
        NotificationCenter.default.post(name: WeeklyPlan.inputsChanged, object: nil)
        saveCount += 1
        withAnimation(.easeInOut(duration: 0.25)) { step = .result }
    }

    // MARK: Result

    private var resultPage: some View {
        QuestionPage(progress: 1, question: "Today's readiness", buttonTitle: "Done", onClose: { dismiss() },
                     onButton: { dismiss() }, tone: .body) {
            if let readiness = DailyLoop.today(athlete) {
                ReadinessBlock(level: readiness.level, reason: readiness.reason)
            }
            // What the rules decided (illness, a game tomorrow…), in words.
            let planning = PlanningRules.today(athlete, sessions: athlete.sessions)
            if planning.decision > .modifyOptionalWork, let explanation = planning.explanation {
                Label(explanation, systemImage: "hand.raised.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let pain = PainStore.report() {
                PainNote(report: pain, paused: dayStatus == .concussion, onPause: {
                    DayStatusStore.set(.concussion, days: nil)
                    HealthShare.send(kind: "paused")
                    dayStatus = .concussion
                }, onSafety: { showingSafety = true })
            }
        }
    }
}

/// Today's readiness in words — never a score. V8: the word big on a blue
/// (body) card with the aura behind it, the three-step scale, the reason.
struct ReadinessBlock: View {
    let level: TodayReadiness
    let reason: String

    var body: some View {
        AuraCard(.body, focus: UnitPoint(x: 0.25, y: 0.3), radius: 200) {
            VStack(alignment: .leading, spacing: 14) {
                Text(level.title)
                    .font(.system(size: 44, weight: .bold))
                    .tracking(-1)
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                ReadinessScale(level: level)
                Text(reason)
                    .font(.body)
                    .foregroundStyle(AppTheme.ink.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Decided before you look (owner, 2026-11-27)

/// The plan is already made from the calendar, the watch and what the
/// athlete told AthleteOS; the morning check-in can be one tap: "feeling
/// like my usual self, no pain, not sick". That answer is saved as the
/// athlete's own usual (the middle of their last two weeks), never as an
/// invented "good" day. Only offered when nothing needs asking: no open
/// follow-up, no pain still open, a normal day, and a few check-ins to know
/// what "usual" is.
@MainActor
enum QuickCheckIn {
    static func isOffered(_ athlete: Athlete, now: Date = .now) -> Bool {
        DayStatusStore.status() == .active
            && PainStore.report() == nil
            && AthleteContextStore.questions().isEmpty
            // A heart raised two nights running: ask, don't assume "normal".
            && !HeartStore.morning(now: now).raised
            && usual(athlete, now: now) != nil
    }

    /// The middle answer of the last 14 days' check-ins, per question (at least 3).
    static func usual(_ athlete: Athlete, now: Date = .now) -> (sleepQuality: Int, energy: Int, soreness: Int, stress: Int)? {
        let since = Calendar.current.date(byAdding: .day, value: -14, to: Calendar.current.startOfDay(for: now)) ?? now
        let recent = athlete.checkIns.filter { $0.date >= since && !Calendar.current.isDate($0.date, inSameDayAs: now) }
        guard recent.count >= 3 else { return nil }
        func middle(_ values: [Int]) -> Int { values.sorted()[values.count / 2] }
        return (middle(recent.map(\.sleepQuality)), middle(recent.map(\.energy)), middle(recent.map(\.soreness)), middle(recent.map(\.stress)))
    }

    /// Saves "usual, no pain, not sick" with last night's measured sleep when the watch has it.
    static func save(_ athlete: Athlete, context: ModelContext) {
        guard let values = usual(athlete) else { return }
        ReminderScheduler.markDone(checkIn: true)
        let twinBefore = TwinPulse.before(athlete)
        _ = try? CheckInStore(modelContext: context).submit(
            athlete: athlete, sleepQuality: values.sleepQuality, sleepHours: MeasuredSleepStore.recent()?.lastNight,
            soreness: values.soreness, energy: values.energy, stress: values.stress
        )
        IllnessStore.set(.no)
        PainFollowUp.markResolved()
        TwinPulse.after(athlete, before: twinBefore, input: .checkIn)
        NotificationCenter.default.post(name: WeeklyPlan.inputsChanged, object: nil)
    }
}
