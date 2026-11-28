import SwiftUI
#if os(iOS)
import UIKit
#endif

extension MindsetRoutine: Identifiable {
    public var id: String { rawValue }
}

// MARK: - Reflection

/// "One win, one lesson" — two big fields and done.
/// The evening reflection (V3): about a minute of taps — how hard today
/// was, how the body feels, how practice went, what went well and what needs
/// work — and one optional line on what you learned. Then the day is done.
/// Tomorrow's plan reads it (ADAPT).
struct ReflectionSheet: View {
    let practiceToday: Bool
    /// That day's game the athlete hasn't rated yet: the evening asks how they
    /// played (its rating — the hub won't ask again), how much, how hard.
    var gameToRate: (id: String, team: Bool, event: String)?
    private var gameToday: Bool { gameToRate != nil }
    /// The sport the evening's practice answer is saved for (a `PracticeLog`).
    var sportSlug: String?
    /// A day without training, practice or a game: no "how hard" question.
    let restDay: Bool
    /// A workout was logged that day (gym, run, Health workout).
    var trained = false
    /// The hardest effort (0–10) the day's workouts already have: no "how hard"
    /// question then — the day's hardness follows from it.
    var trainedEffort: Int?
    /// Practice length from the schedule (minutes), the evening's starting value.
    var scheduledMinutes: Int?
    /// A game that day (with or without a result): its effort isn't known, so
    /// "How hard did today feel?" is asked.
    var hadGame = false
    /// Whose twin a rated practice teaches ("Your twin learned …" on Home).
    var athlete: Athlete?
    let onSaved: () -> Void
    @State private var insight: String?
    @State private var wentWellNote = ""
    @State private var improveNote = ""
    /// The rest of today, for the "Today completed" ticks (nil: not shown).
    @State private var completion: DayCompletion?

    @Environment(\.dismiss) private var dismiss

    enum Step: Hashable { case gameRating, gamePlayed, gameEffort, practice, practiceEffort, hardness, body, pain, wentWell, needsWork, learned, review, done }

    /// One Campus review question at the end (spaced repetition without a
    /// separate screen): the lesson that's most overdue.
    private let review: (lessonID: String, question: CampusQuestion)? = {
        let learned = CampusProgress.learned(UserDefaults.standard.string(forKey: CampusProgress.learnedKey) ?? "")
        for id in CampusReview.due(learned: learned) {
            if let question = CampusReview.questions(for: [id]).first(where: {
                if case .choice = $0 { return true }
                if case .trueFalse = $0 { return true }
                return false
            }) { return (id, question) }
        }
        return nil
    }()
    @State private var reviewAnswer: Int?

    @State private var step: Step = .hardness
    @State private var hardness: Int?
    @State private var bodyFeel: Int?
    @State private var practice: Int?
    /// Practice effort 0–10 (CR-10) and minutes: practice's load, like a workout's.
    @State private var practiceRPE: Int?
    @State private var practiceMinutes = 90
    /// Where the minutes came from ("from your watch", "from your schedule").
    @State private var minutesSource: String?
    /// The length is known (watch, schedule, or the athlete set it): only then
    /// is it saved — a minute is never made up.
    @State private var minutesKnown = false
    /// A watch's heart-rate read of the practice, shown as a dot, never picked.
    @State private var practiceEstimate: Int?
    /// The game: how they played (1–5), how much (team sports), how hard (0–10).
    @State private var gameRating: Int?
    @State private var gamePlayed: GameEvening.Played?
    @State private var gameRPE: Int?
    @State private var wentWell: Set<String> = []
    @State private var needsWork: Set<String> = []
    @State private var learned = ""
    /// "Something hurt": where and how much, asked once and kept like the
    /// check-in's pain (no diagnosis; the head goes to the pause).
    @State private var painAreas: Set<PainArea> = []
    @State private var painLevel: PainLevel?
    @State private var paused = DayStatusStore.status() == .concussion
    @State private var saved = false

    init(completion: DayCompletion? = nil, practiceToday: Bool = false, gameToRate: (id: String, team: Bool, event: String)? = nil,
         sportSlug: String? = nil,
         restDay: Bool = false, trained: Bool = false, trainedEffort: Int? = nil, scheduledMinutes: Int? = nil,
         hadGame: Bool = false, athlete: Athlete? = nil, onSaved: @escaping () -> Void) {
        self.athlete = athlete
        self.hadGame = hadGame
        _completion = State(initialValue: completion)
        self.practiceToday = practiceToday
        self.gameToRate = gameToRate
        if let gameToRate, let evening = CompetitionStore.evenings()[gameToRate.id] {
            _gameRating = State(initialValue: evening.rating)
            _gamePlayed = State(initialValue: evening.played)
            _gameRPE = State(initialValue: evening.rpe)
        }
        self.sportSlug = sportSlug
        self.trained = trained
        self.trainedEffort = trainedEffort
        self.scheduledMinutes = scheduledMinutes
        // Practice as already known: a watch's minutes and heart-rate read, or
        // tonight's earlier answer.
        let log = PracticeLogStore.log(on: DayKey.of(Self.reflectionDay()), sportSlug: sportSlug)
        _practiceRPE = State(initialValue: log?.rpe)
        let fromWatch = log?.note?.hasPrefix("From your ") == true
        // Effort already said (Tell, the morning card) or measured (watch): the dot, never picked.
        if log?.rpe == nil, let hard = log?.hard { _practiceEstimate = State(initialValue: min(10, hard * 2)) }
        if let minutes = log?.minutes, minutes > 0 {
            _practiceMinutes = State(initialValue: minutes)
            _minutesSource = State(initialValue: fromWatch ? "from your watch" : nil)
            _minutesKnown = State(initialValue: true)
        } else if let scheduledMinutes, scheduledMinutes > 0 {
            _practiceMinutes = State(initialValue: scheduledMinutes)
            _minutesSource = State(initialValue: "from your schedule")
            _minutesKnown = State(initialValue: true)
        }
        self.restDay = restDay
        self.onSaved = onSaved
        let existing = MindsetStore.reflection(on: Self.reflectionDay())
        _hardness = State(initialValue: existing?.hardness)
        _bodyFeel = State(initialValue: existing?.body)
        _practice = State(initialValue: existing?.practice
            ?? (EveningPractice.skipped(on: DayKey.of(Self.reflectionDay())) ? EveningOptions.didntGo : nil))
        // Chips are the known areas; anything else is the athlete's own note.
        let areas = Set(EveningOptions.areas)
        _wentWell = State(initialValue: Set((existing?.wentWell ?? []).filter { areas.contains($0) }))
        _needsWork = State(initialValue: Set((existing?.needsWork ?? []).filter { areas.contains($0) }))
        _wentWellNote = State(initialValue: (existing?.wentWell ?? []).first { !areas.contains($0) } ?? "")
        _improveNote = State(initialValue: (existing?.needsWork ?? []).first { !areas.contains($0) } ?? "")
        _learned = State(initialValue: existing?.learned ?? "")
        // Reopened: what was already said about pain tonight is shown, not asked blank.
        if existing?.body == 4, let pain = PainStore.report(on: Self.reflectionDay()) {
            _painAreas = State(initialValue: Set(pain.areas))
            _painLevel = State(initialValue: pain.level)
        }
        let asks = EveningOptions.asksHardness(restDay: restDay, trained: trained, trainedEffort: trainedEffort, game: hadGame && gameToRate == nil)
        _step = State(initialValue: gameToRate != nil ? .gameRating : practiceToday ? .practice : asks ? .hardness : .body)
    }


    private var asksHardness: Bool {
        // A game asked about tonight has its own effort; one rated in the hub doesn't.
        EveningOptions.asksHardness(restDay: restDay, trained: trained, trainedEffort: trainedEffort, game: hadGame && gameToRate == nil)
    }

    private var practiceWent: Bool { practiceToday && practice != nil && practice != EveningOptions.didntGo }
    private var playedGame: Bool { gameToRate != nil && gamePlayed != GameEvening.Played.none }

    /// The day's hardness (1 easy … 4 very hard) for tomorrow's plan: what the
    /// athlete said, else the hardest effort the day's sessions were rated.
    private var dayHardness: Int? {
        let efforts = [practiceWent ? practiceRPE : nil, playedGame ? gameRPE : nil, trainedEffort].compactMap { $0 }
        let derived = efforts.max().map(EveningOptions.hardness(fromRPE:))
        // The answer counts only when it was asked tonight (a reopened evening
        // pre-fills the saved, derived value — it mustn't hold the day up).
        switch (asksHardness ? hardness : nil, derived) {
        case let (said?, derived?): return max(said, derived)
        case let (said, derived): return said ?? derived
        }
    }

    /// The day being reflected on: after midnight (until 5:00) it is still yesterday.
    static func reflectionDay(_ now: Date = .now, calendar: Calendar = .current) -> Date {
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        guard minute < TodayPlan.nightEnd else { return now }
        return calendar.date(byAdding: .day, value: -1, to: now) ?? now
    }

    /// 3–5 short questions, depending on the day (V6 §18). "Something hurt"
    /// asks where and how much — once, never "None" after it.
    private var steps: [Step] {
        var steps: [Step] = []
        if let gameToRate {
            steps.append(.gameRating)
            if gameToRate.team { steps.append(.gamePlayed) }
            if playedGame { steps.append(.gameEffort) }
        }
        if practiceToday {
            steps.append(.practice)
            if practiceWent { steps.append(.practiceEffort) }
        }
        if asksHardness { steps.append(.hardness) }
        steps.append(.body)
        if bodyFeel == 4 { steps.append(.pain) }
        // What went well / what to improve follow a practice that happened or a
        // game the games hub hasn't asked about — not a rest day or a gym
        // session that already asked its effort (research C-rules).
        if practiceWent || gameToday {
            steps.append(.wentWell)
            steps.append(.needsWork)
        }
        return steps
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
        .sensoryFeedback(.success, trigger: step == .done)
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case .hardness:
            VStack(spacing: 0) {
                scale("How hard did today feel?", EveningOptions.hardness, selection: $hardness)
                skipFooter(.hardness)
            }
        case .pain:
            QuestionPage(progress: progress, question: "Where does it hurt?", hint: "Tap every place, then how much.",
                         buttonTitle: "Next", buttonEnabled: !painAreas.isEmpty && painLevel != nil,
                         onClose: { dismiss() }, onBack: { back() }, onButton: { savePain(); next(from: .pain) }, tone: .mind) {
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
                    // The head isn't trained through: saving this pauses training
                    // tonight (a head report has no follow-up of its own).
                    HeadKnockNote()
                    Text(paused ? "Training is paused until a doctor clears you."
                                : "Training pauses when you go on, until a doctor clears you. You lift the pause in the Safety Center.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Tomorrow's plan stays lighter until you say it's gone. If it's sharp, swelling or getting worse, tell an adult tonight.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .body:
            VStack(spacing: 0) {
                scale("How did your body feel?", EveningOptions.body, selection: $bodyFeel)
                skipFooter(.body)
            }
        case .practice:
            VStack(spacing: 0) {
                scale("How did practice go?", EveningOptions.practice + [EveningOptions.skippedPractice], selection: $practice)
                skipFooter(.practice)
            }
        case .practiceEffort:
            practiceEffortPage
        case .gameRating:
            VStack(spacing: 0) {
                scale("How did you play?", GameEvening.ratings, selection: $gameRating)
                skipFooter(.gameRating)
            }
        case .gamePlayed:
            QuestionPage(progress: progress, question: "Did you play?", hint: "How much of the \(gameToRate?.event ?? "game") you were on.",
                         buttonTitle: gamePlayed == nil ? nil : "Next", onClose: { dismiss() }, onBack: { back() },
                         onButton: { next(from: .gamePlayed) }, tone: .mind) {
                ChoiceGrid(GameEvening.Played.allCases, title: { (played: GameEvening.Played) -> String in played.title },
                           isSelected: { (played: GameEvening.Played) -> Bool in played == gamePlayed }) { (played: GameEvening.Played) in
                    gamePlayed = played
                    advance(from: .gamePlayed)
                }
            }
        case .gameEffort:
            QuestionPage(progress: progress, question: "How hard was the \(gameToRate?.event ?? "game") for you?",
                         hint: "Think of the whole \(gameToRate?.event ?? "game"), not just the end.",
                         buttonTitle: gameRPE == nil ? nil : "Next", onClose: { dismiss() }, onBack: { back() },
                         onButton: { next(from: .gameEffort) }, tone: .training) {
                EffortScale(rating: $gameRPE)
            }
        case .wentWell:
            areas("What went well?", selection: $wentWell, note: $wentWellNote, placeholder: "In your words (optional)")
        case .needsWork:
            areas("What should improve next time?", selection: $needsWork, note: $improveNote, placeholder: "One small thing to try (optional)")
        case .learned:
            QuestionPage(progress: progress, question: "What did you learn today?", hint: "Optional. One line is plenty.",
                         buttonTitle: "Save", onClose: { dismiss() }, onBack: { back() }, onButton: { save() }, tone: .mind) {
                TextField("e.g. Call for the ball earlier", text: $learned, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.body)
                    .padding(16)
                    .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            }
        case .review:
            if let review { reviewPage(review) }
        case .done:
            // Calm, not a trophy: rest days finish the same way.
            // V8: one sentence says it; what today showed sits on the mind card.
            QuestionPage(progress: 1, question: "", buttonTitle: nil, onClose: { dismiss() }, tone: .mind) {
                VStack(alignment: .leading, spacing: 20) {
                    Headline([.icon("checkmark"), .strong(restDay ? " Rest day done." : " Day done."),
                              .soft(" Your answers shape tomorrow's plan.")])
                    if bodyFeel == 4, painAreas.contains(.head) {
                        Text("Training is paused until a doctor clears you. Tell a parent or coach tonight.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.coral)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let insight {
                        AuraCard(.mind, focus: UnitPoint(x: 0.2, y: 0.3), radius: 200) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("What today shows")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink.opacity(0.8))
                                Text(insight)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityElement(children: .combine)
                    } else if bodyFeel == 4 {
                        Text("Pain is saved, and tomorrow stays lighter around it until you say it's gone. Tell a coach or parent.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.coral)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            }
        }
    }

    /// Reflection is never forced (Backend Knowledge System §20): the first
    /// question, whichever it is, can skip the evening.
    @ViewBuilder
    private func skipFooter(_ current: Step) -> some View {
        if current == steps.first {
            Button("Skip today") { saveNothing() }
                .buttonStyle(.quiet)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.bottom, 8)
                .background(AppTheme.background)
        }
    }

    /// Foster's session effort for the practice, with its minutes already
    /// filled in (watch, else schedule): effort × minutes is its load.
    private var practiceEffortPage: some View {
        QuestionPage(progress: progress, question: "How hard was practice?", hint: "Think of the whole practice, not just the end.",
                     buttonTitle: practiceRPE == nil ? nil : "Next", onClose: { dismiss() }, onBack: { back() },
                     onButton: { next(from: .practiceEffort) }, tone: .training) {
            EffortScale(rating: $practiceRPE, estimate: practiceEstimate,
                        estimateNote: practiceEstimate.map { "Your watch suggests about \($0) (the dot). How it felt decides." })
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(minutesKnown ? "About \(practiceMinutes) min" : "How long was it?")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(AppTheme.ink)
                    Text(minutesKnown ? (minutesSource ?? "how long it went") : "Optional — tap − or + to set it")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                minutesButton("minus", by: -15)
                minutesButton("plus", by: 15)
            }
            .padding(14)
            .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        }
    }

    private func minutesButton(_ symbol: String, by change: Int) -> some View {
        Button {
            if minutesKnown { practiceMinutes = min(300, max(15, practiceMinutes + change)) }
            minutesKnown = true
            minutesSource = nil
        } label: {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(change > 0 ? "15 minutes longer" : "15 minutes shorter")
    }

    private func reviewPage(_ review: (lessonID: String, question: CampusQuestion)) -> some View {
        let (prompt, options, answer, explain): (String, [String], Int, String) = {
            switch review.question {
            case .choice(let prompt, let options, let answer, let explain): return (prompt, options, answer, explain)
            case .trueFalse(let statement, let answer, let explain): return (statement, ["True", "False"], answer ? 0 : 1, explain)
            default: return ("", [], 0, "")
            }
        }()
        return QuestionPage(progress: 1, question: "One quick question", hint: prompt,
                            buttonTitle: reviewAnswer == nil ? nil : "Next", onClose: { dismiss() }, onButton: { finishReview(review, right: reviewAnswer == answer) },
                            tone: .mind) {
            VStack(alignment: .leading, spacing: 12) {
                ChoiceGrid(Array(options.indices), title: { (index: Int) -> String in options[index] },
                           isSelected: { (index: Int) -> Bool in reviewAnswer == index }) { (index: Int) in
                    if reviewAnswer == nil { reviewAnswer = index }
                }
                if let reviewAnswer {
                    Label(reviewAnswer == answer ? "Right. " + explain : "The answer: \(options[answer]). " + explain,
                          systemImage: reviewAnswer == answer ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func finishReview(_ review: (lessonID: String, question: CampusQuestion), right: Bool) {
        CampusReview.record(reviewed: [review.lessonID], wrong: right ? [] : [review.lessonID])
        if completion == nil && insight == nil {
            dismiss()
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                completion?.reflected = true
                step = .done
            }
        }
    }

    private func scale(_ question: String, _ options: [String], selection: Binding<Int?>) -> some View {
        let current = step
        let backAction: (() -> Void)? = current == steps.first ? nil : { back() }
        let buttonTitle: String? = selection.wrappedValue == nil ? nil : "Next"
        let values: [Int] = Array(1...options.count)
        return QuestionPage(progress: progress, question: question, buttonTitle: buttonTitle,
                            onClose: { dismiss() }, onBack: backAction, onButton: { next(from: current) }, tone: .mind) {
            ChoiceGrid(values, title: { (value: Int) -> String in options[value - 1] },
                       isSelected: { (value: Int) -> Bool in selection.wrappedValue == value }) { (value: Int) in
                selection.wrappedValue = value
                advance(from: current)
            }
        }
    }

    /// After a tap: a moment to see the choice, then the next question.
    private func advance(from current: Step) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            next(from: current)
        }
    }

    private func areas(_ question: String, selection: Binding<Set<String>>, note: Binding<String>, placeholder: String) -> some View {
        let current = step
        let last = current == steps.last
        let empty = selection.wrappedValue.isEmpty && note.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty
        return QuestionPage(progress: progress, question: question, hint: "Tap any that fit.",
                            buttonTitle: last ? "Save" : (empty ? "Skip" : "Next"),
                            onClose: { dismiss() }, onBack: { back() }, onButton: { next(from: current) }, tone: .mind) {
            VStack(alignment: .leading, spacing: 14) {
                ChoiceGrid(EveningOptions.areas, title: { (area: String) -> String in area },
                           isSelected: { (area: String) -> Bool in selection.wrappedValue.contains(area) }) { (area: String) in
                    if selection.wrappedValue.contains(area) { selection.wrappedValue.remove(area) } else { selection.wrappedValue.insert(area) }
                }
                TextField(placeholder, text: note, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.body)
                    .padding(14)
                    .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            }
        }
    }

    private func next(from current: Step) {
        guard step == current, let index = steps.firstIndex(of: current) else { return }
        if index + 1 < steps.count {
            withAnimation(.easeInOut(duration: 0.25)) { step = steps[index + 1] }
        } else {
            save()
        }
    }

    private func back() {
        guard let index = steps.firstIndex(of: step), index > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) { step = steps[index - 1] }
    }

    /// "Nothing to review today": the day counts as reflected, nothing asked.
    private func saveNothing() {
        MindsetStore.saveEvening(hardness: nil, body: nil, practice: nil, wentWell: [], needsWork: [], learned: nil, on: Self.reflectionDay())
        onSaved()
        dismiss()
    }

    /// Pain after training is kept like pain in the check-in (no diagnosis), on
    /// the day reflected on, joined with anything already said that day — as
    /// soon as it's answered, so closing the sheet early doesn't lose it. The
    /// head pauses training at once.
    private func savePain() {
        guard bodyFeel == 4, !painAreas.isEmpty, let painLevel else { return }
        if painAreas.contains(.head), !paused { pauseForHead() }
        let day = Self.reflectionDay()
        let report = PainReport.joining(PainStore.report(on: day), day: DayKey.of(day), areas: painAreas, level: painLevel)
        PainStore.set(report, on: day)
        HealthShare.send(kind: "pain", areas: report.areas, level: report.level, day: day)
        NotificationCenter.default.post(name: WeeklyPlan.inputsChanged, object: nil)
    }

    /// The practice answer is the practice: saved as (or joined into) the day's
    /// `PracticeLog`, so the morning doesn't ask again and the twin reads how it
    /// went. A log from a watch or Tell keeps its minutes and effort.
    private func savePractice() {
        guard practiceToday, let practice else { return }
        let key = DayKey.of(Self.reflectionDay())
        if practice == EveningOptions.didntGo {
            // Didn't go: an answer this evening gave earlier goes; a log from a
            // watch or Tell stands (something happened then), else no practice that day.
            for log in PracticeLogStore.logs where log.day == key && log.note == EveningPractice.note { PracticeLogStore.delete(log) }
            if PracticeLogStore.log(on: key) == nil {
                PracticeOverride.set(false, on: key)
                EveningPractice.setSkipped(true, on: key)
            }
            return
        }
        // Went after all: the evening's own "didn't go" is undone.
        if EveningPractice.skipped(on: key) {
            EveningPractice.setSkipped(false, on: key)
            if PracticeOverride.hasPractice(on: key) == false { PracticeOverride.set(nil, on: key) }
        }
        guard let sportSlug else { return }
        let existing = PracticeLogStore.log(on: key, sportSlug: sportSlug)
        var log = existing ?? PracticeLog(day: key, sportSlug: sportSlug, types: [], hard: EveningOptions.practiceHard(dayHardness: hardness),
                                          went: 0, mood: 0, note: EveningPractice.note)
        log.went = EveningOptions.practiceWent(practice)
        // The athlete's own effort and minutes: their word wins over a watch's estimate.
        if let practiceRPE {
            log.rpe = practiceRPE
            log.hard = PracticeLog.hard(fromRPE: practiceRPE)
            if minutesKnown { log.minutes = practiceMinutes }
        }
        PracticeLogStore.save(log)
    }

    /// The game's evening answers: its rating (the hub shows it, never asks
    /// it again), how much was played, how hard — the twin's game load.
    private func saveGame(wentWell: [String], toImprove: [String]) {
        guard let gameToRate, gameRating != nil || gamePlayed != nil || gameRPE != nil else { return }
        CompetitionStore.save(GameEvening(id: gameToRate.id, rating: gameRating, played: gameToRate.team ? gamePlayed : nil,
                                          rpe: playedGame ? gameRPE : nil, wentWell: wentWell, toImprove: toImprove))
    }

    private func pauseForHead() {
        DayStatusStore.set(.concussion, days: nil)
        HealthShare.send(kind: "paused")
        paused = true
        NotificationCenter.default.post(name: WeeklyPlan.inputsChanged, object: nil)
    }

    private func save() {
        // A quick double tap on the last scale queues two advances: save once.
        guard !saved else { return }
        saved = true
        let order = EveningOptions.areas
        let wellNote = wentWellNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let improve = improveNote.trimmingCharacters(in: .whitespacesAndNewlines)
        MindsetStore.saveEvening(
            hardness: restDay ? nil : dayHardness, body: bodyFeel, practice: practiceToday && practice != EveningOptions.didntGo ? practice : nil,
            wentWell: order.filter { wentWell.contains($0) } + (wellNote.isEmpty ? [] : [wellNote]),
            needsWork: order.filter { needsWork.contains($0) } + (improve.isEmpty ? [] : [improve]),
            learned: learned.isEmpty ? nil : learned, on: Self.reflectionDay()
        )
        // What a rated practice or game taught the twin — never next to pain (its own path).
        let twinBefore = athlete.map { TwinPulse.before($0) }
        savePractice()
        saveGame(wentWell: order.filter { wentWell.contains($0) }, toImprove: order.filter { needsWork.contains($0) })
        if let athlete, let twinBefore, (practiceWent && practiceRPE != nil) || gameRating != nil, bodyFeel != 4 {
            TwinPulse.after(athlete, before: twinBefore, input: .evening)
        }
        ReminderScheduler.markDone(reflection: true)
        // Tonight's answers shape tomorrow: the saved plan (Lock Screen card,
        // Home's Tomorrow) is rebuilt now, not at the next app open.
        defer { NotificationCenter.default.post(name: WeeklyPlan.inputsChanged, object: nil) }
        // A very tired body (physical, kept apart from how the day felt): the
        // morning check-in asks how it feels, and today's plan stays easier until then.
        if bodyFeel == 3 {
            let day = Calendar.current.startOfDay(for: Self.reflectionDay())
            // Saved again the same evening: the one event stands.
            let known = AthleteContextStore.all.contains { $0.source == .reflection && $0.kind == .fatigue && Calendar.current.isDate($0.from, inSameDayAs: day) }
            if !known {
            AthleteContextStore.add(AthleteContextEvent(from: day, kind: .fatigue, source: .reflection,
                                                        reported: ["Body very tired in the evening"], regions: [.wholeBody], level: 2))
            }
        }
        // Sometimes one small thing back (V6 §19), never the same one twice in a row.
        if let today = MindsetStore.reflection(on: Self.reflectionDay()) {
            let last = UserDefaults.standard.string(forKey: "reflection.lastInsight")
            if let found = ReflectionInsight.make(today: today, recent: MindsetStore.reflections,
                                                  practiceToday: practiceToday && practice != EveningOptions.didntGo, lastShown: last) {
                insight = found.text
                UserDefaults.standard.set(found.key, forKey: "reflection.lastInsight")
            }
        }
        onSaved()
        if review != nil {
            withAnimation(.easeInOut(duration: 0.25)) { step = .review }
        } else if completion == nil && insight == nil {
            dismiss()
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                completion?.reflected = true
                step = .done
            }
        }
    }
}

// MARK: - Breathing

/// A circle that grows as you breathe in and shrinks as you breathe out.
struct BreathingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pattern: BreathingPattern = .calm
    @State private var minutes = 2
    @State private var startedAt: Date?
    @State private var finished = false
    @State private var lastPhase = -1

    private var total: Double { Double(minutes * 60) }

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                CircleIconButton(systemImage: "xmark", accessibilityLabel: "Close") { dismiss() }
                Spacer()
            }
            if let startedAt, !finished {
                TimelineView(.animation) { context in
                    let elapsed = min(total, context.date.timeIntervalSince(startedAt))
                    let phase = pattern.phase(at: elapsed)
                    let hold = phase.label == "Hold"
                    let scale = hold ? (phase.expand ? 1 : 0.5) : (phase.expand ? 0.5 + 0.5 * phase.progress : 1 - 0.5 * phase.progress)
                    VStack(spacing: 28) {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(AppTheme.fill)
                                .frame(width: 280, height: 280)
                            Circle()
                                .fill(AppTheme.solid)
                                .frame(width: 280, height: 280)
                                .scaleEffect(scale)
                            Text(phase.label)
                                .font(.title.bold())
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(40)
                        }
                        .onChange(of: phase.index) { _, index in phaseChanged(index) }
                        Text(remainingText(total - elapsed))
                            .font(.title2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                        Spacer()
                    }
                }
                .task {
                    try? await Task.sleep(nanoseconds: UInt64(total * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    MindsetStore.logRoutine(.breathing)
                    finished = true
                }
                Button("Stop") {
                    if let started = self.startedAt, Date.now.timeIntervalSince(started) >= 60 { MindsetStore.logRoutine(.breathing) }
                    dismiss()
                }
                .buttonStyle(.secondary)
            } else if finished {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(AppTheme.green)
                Text("Nice. Calm and ready.")
                    .font(.largeTitle.bold())
                    .foregroundStyle(AppTheme.ink)
                Text("Use the same breathing whenever the nerves come back — before a free throw, a serve, a start.")
                    .font(.body)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ScreenTitle("Breathing", subtitle: "Sit or stand still, relax your shoulders, and follow the circle.")
                        ForEach(BreathingPattern.allCases) { value in
                            Button { pattern = value } label: {
                                OptionRow(title: value.title, subtitle: value.explanation, systemImage: value == .calm ? "wind" : "square", isSelected: pattern == value)
                            }
                            .buttonStyle(.plain)
                        }
                        Text("How long?")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        HStack(spacing: 10) {
                            ForEach([1, 2, 3], id: \.self) { value in
                                Button { minutes = value } label: {
                                    Text("\(value) min")
                                        .font(.headline)
                                        .foregroundStyle(minutes == value ? AppTheme.onAccent : AppTheme.ink)
                                        .frame(maxWidth: .infinity, minHeight: 52)
                                        .background(minutes == value ? AppTheme.accent : AppTheme.fill, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Button { startedAt = .now } label: { Label("Start", systemImage: "play.fill") }
                    .buttonStyle(.primary)
            }
        }
        .padding(24)
        .appScreen()
    }

    private func remainingText(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func phaseChanged(_ index: Int) {
        guard index != lastPhase else { return }
        lastPhase = index
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }
}

// MARK: - Visualization

/// The game-day visualization: seven short steps, each on its own timer.
struct VisualizationView: View {
    let sportName: String

    @Environment(\.dismiss) private var dismiss
    @State private var cueWord = MindsetStore.cueWord
    @State private var step: Int?
    @State private var stepStartedAt = Date.now

    private var steps: [VisualizationStep] { GameDayVisualization.steps(sportName: sportName, cueWord: cueWord) }

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 14) {
                CircleIconButton(systemImage: "xmark", accessibilityLabel: "Close") { dismiss() }
                if let step { StepProgressBar(progress: Double(step + 1) / Double(steps.count)) }
                Spacer(minLength: 0)
            }
            if let step, step < steps.count {
                let current = steps[step]
                Spacer()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Step \(step + 1) of \(steps.count)")
                        .font(.caption.weight(.heavy))
                        .tracking(0.8)
                        .foregroundStyle(AppTheme.purple)
                    Text(current.title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(AppTheme.ink)
                    Text(current.text)
                        .font(.title3)
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    TimelineView(.periodic(from: stepStartedAt, by: 1)) { context in
                        let left = max(0, current.seconds - Int(context.date.timeIntervalSince(stepStartedAt)))
                        Text(left > 0 ? "\(left) s" : "…")
                            .font(.title2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .task(id: step) {
                    stepStartedAt = .now
                    try? await Task.sleep(nanoseconds: UInt64(current.seconds) * 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    advance()
                }
                Spacer()
                ButtonRow {
                    if step > 0 {
                        Button("Back") { self.step = step - 1 }
                            .buttonStyle(.secondary)
                    }
                    Button(step == steps.count - 1 ? "Finish" : "Next") { advance() }
                        .buttonStyle(.primary)
                }
            } else if step != nil {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(AppTheme.green)
                Text("You've played it once already.")
                    .font(.largeTitle.bold())
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.center)
                Text("Remember your word: \"\(cueWord)\". Say it after any mistake, then go to the next play.")
                    .font(.body)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ScreenTitle("Game-day visualization", subtitle: "About 5 minutes, somewhere quiet. Picture the game going well, and bouncing back from a mistake.")
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your reset word")
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)
                            Text("One word you say in your head after a mistake, to let it go and play the next play.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryText)
                            TextField("Next", text: $cueWord)
                                .font(.title3.weight(.semibold))
                                .padding(16)
                                .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            WrapLayout(spacing: 8) {
                                ForEach(["Next", "Reset", "Attack", "Smooth", "Breathe"], id: \.self) { word in
                                    Button(word) { cueWord = word }
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(cueWord == word ? AppTheme.onAccent : AppTheme.ink)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(cueWord == word ? AppTheme.accent : AppTheme.fill, in: Capsule())
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                Button {
                    let word = cueWord.trimmingCharacters(in: .whitespacesAndNewlines)
                    cueWord = word.isEmpty ? "Next" : word
                    MindsetStore.cueWord = cueWord
                    step = 0
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.primary)
            }
        }
        .padding(24)
        .appScreen()
    }

    private func advance() {
        guard let step else { return }
        if step + 1 >= steps.count { MindsetStore.logRoutine(.visualization) }
        self.step = step + 1
    }
}
