import SwiftUI

// MARK: - Duolingo-style palette and components

/// Campus: a winding path of lessons per unit (with chunky path buttons) and
/// a calm lesson player — a thin progress bar, "Check", and a quiet answer
/// sheet; a missed question comes back at the end. Its colours are Duolingo's own feedback colours plus
/// the app's red for the path.
enum Duo {
    static let green = Color(hex: "#58CC02")
    static let greenLip = Color(hex: "#58A700")
    static let greenSoft = Color.dynamic(light: 0xD7FFB8, dark: 0x1F3A12)
    static let greenText = Color.dynamic(light: 0x58A700, dark: 0x79D634)
    /// The selected answer and secondary buttons: black, not blue.
    static let blue = Color.dynamic(light: 0x111111, dark: 0xF2F2F2)
    static let blueLip = Color.dynamic(light: 0x000000, dark: 0xBDBDBD)
    static let blueSoft = Color.dynamic(light: 0xEBEBEB, dark: 0x262626)
    /// A black slab button with white text (dark grey in dark mode).
    static let black = AppTheme.solid
    static let blackLip = Color.dynamic(light: 0x000000, dark: 0x1A1A1A)
    static let red = Color(hex: "#FF4B4B")
    static let redLip = Color(hex: "#EA2B2B")
    static let redSoft = Color.dynamic(light: 0xFFDFE0, dark: 0x3F1E20)
    static let gold = Color(hex: "#FFC800")
    static let goldLip = Color(hex: "#E5A500")
    static let orange = Color(hex: "#FF9600")
    static let border = Color.dynamic(light: 0xE5E5E5, dark: 0x333333)
    static let lockedFill = Color.dynamic(light: 0xE5E5E5, dark: 0x333333)
    static let lockedLip = Color.dynamic(light: 0xCECECE, dark: 0x1F1F1F)
    static let lockedGlyph = Color.dynamic(light: 0xAFAFAF, dark: 0x6B6B6B)

    /// Unit colours along the path, starting with the brand red.
    static let units: [(Color, Color)] = [
        (AppTheme.brand, Color(hex: "#B8272A")), (AppTheme.water, AppTheme.waterDeep), (green, greenLip), (AppTheme.purple, Color(hex: "#9D2B7A")),
        (orange, Color(hex: "#CC7900")), (Color(hex: "#FF86D0"), Color(hex: "#CC6BA6")), (AppTheme.coral, Color(hex: "#C2410C")),
    ]
}

/// An answer tile: white with a gray border and lip; blue when selected, green/red once checked.
struct AnswerTile: View {
    enum State { case idle, selected, correct, wrong, done }
    let text: String
    let state: State

    var body: some View {
        let (fill, border, textColor): (Color, Color, Color) = {
            switch state {
            case .idle: (AppTheme.fill, .clear, AppTheme.ink)
            case .selected: (AppTheme.fill, AppTheme.accent, AppTheme.ink)
            case .correct: (AppTheme.green.opacity(0.14), AppTheme.green, AppTheme.ink)
            case .wrong: (AppTheme.coral.opacity(0.14), AppTheme.coral, AppTheme.ink)
            case .done: (AppTheme.fill, .clear, AppTheme.secondaryText)
            }
        }()
        let shape = RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous)
        Text(text)
            .font(.body.weight(.medium))
            .foregroundStyle(textColor)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(border, lineWidth: 2))
            .opacity(state == .done ? 0.6 : 1)
    }
}

// MARK: - Progress (learned lessons)

/// What Campus remembers: which lessons are learned. No points, levels or
/// streaks — the lessons are the point (owner, 2026-11-18).
struct CampusProgress {
    static let learnedKey = "campus.learned"
    /// The lesson finished most recently ("Continue").
    static let lastLessonKey = "campus.lastLesson"

    static func learned(_ raw: String) -> Set<String> { Set(raw.split(separator: ",").map(String.init)) }

    /// When new lessons were finished (for the free daily allowance; replays
    /// and reviews don't count). The last few only.
    static let newLessonsKey = "campus.newLessonDates"

    static func newLessonDates(_ defaults: UserDefaults = .standard) -> [Date] {
        (defaults.array(forKey: newLessonsKey) as? [Double] ?? []).map(Date.init(timeIntervalSince1970:))
    }

    static func recordNewLesson(_ date: Date = .now, _ defaults: UserDefaults = .standard) {
        let kept = (newLessonDates(defaults) + [date]).suffix(10).map(\.timeIntervalSince1970)
        defaults.set(Array(kept), forKey: newLessonsKey)
        CampusLog.recordLesson(on: date, defaults: defaults)
    }

    /// New lessons left today on free; nil on Pro.
    @MainActor
    static func lessonsLeftToday(_ defaults: UserDefaults = .standard) -> Int? {
        ProGate.remainingLessonsToday(isPro: ProAccess.isPro, lessonDates: newLessonDates(defaults))
    }
}

/// A stable shuffle (the same order every time a question appears).
func stableOrder(_ count: Int, seed: String) -> [Int] {
    var hash: UInt64 = 5381
    for byte in seed.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
    var generator = SeededGenerator(seed: String(hash))
    var order = Array(0..<count)
    for i in stride(from: count - 1, to: 0, by: -1) {
        let j = Int(generator.next() % UInt64(i + 1))
        order.swapAt(i, j)
    }
    return order
}

// MARK: - The library

/// Campus's ~100 short lessons, opened from the Academy as a sheet: what to
/// continue, reviews due, the nine areas, the athlete's sport. The Academy's
/// briefings are the main reading; these are the short follow-ups.
struct CampusView: View {
    let athlete: Athlete
    /// The Academy's Campus page (no close button; the page switcher on top).
    var embedded = false
    /// Shown above the lessons (the switcher, "Campus asks").
    var prelude: AnyView? = nil
    /// Shown under the lessons (long reads, mental skills).
    var extra: AnyView? = nil
    /// Embedded: "Campus asks" under the header, and what's read between the
    /// sport and the areas (redesign 2026-11-28: one order, less to scan).
    var asks: AnyView? = nil
    var middle: AnyView? = nil
    @AppStorage(CampusProgress.learnedKey) private var learnedRaw = ""
    @State private var playing: CampusLesson?
    @State private var reviewing: ReviewSession?
    @State private var showingGuide = false
    @State private var showingPaywall = false
    /// Bumped after a review so the due list redraws.
    @State private var revision = 0

    /// A review: questions from the lessons that are due.
    struct ReviewSession: Identifiable {
        let id = UUID()
        let lessonIDs: [String]
        let steps: [CampusStep]
    }

    private var dueForReview: [String] {
        _ = revision
        return CampusReview.due(learned: learned)
    }

    private var learned: Set<String> { CampusProgress.learned(learnedRaw) }
    private var totalLessons: Int { campusTopics.reduce(0) { $0 + $1.lessons.count } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let prelude { prelude }
                    header
                    if let asks { asks }
                    continueRow
                    if !dueForReview.isEmpty { reviewCard }
                    dailyAllowance
                    if embedded {
                        // The Academy page (redesign 2026-11-28): sport, reading, then the areas as a grid.
                        sportSection
                        if let middle { middle }
                        areaGrid
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            SpaceSection(1, "Areas")
                            ForEach(Array(campusTopics.enumerated()), id: \.element.id) { index, topic in
                                NavigationLink(value: topic) { areaRow(topic, index: index) }
                                    .buttonStyle(.plain)
                            }
                        }
                        sportSection
                    }
                    if let extra { extra }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .appScreen(.hero)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: CampusTopic.self) { topic in
                LearningAreaView(topic: topic, color: Self.color(for: topic)) { lesson in start(lesson) }
            }
        }
        .fullScreenCover(item: $playing) { lesson in
            CampusLessonPlayer(lesson: lesson) { finish(lesson) }
        }
        .fullScreenCover(item: $reviewing) { session in
            CampusLessonPlayer(
                lesson: CampusLesson(id: "review", title: "Review", minutes: 3, sections: [], takeaways: []),
                customSteps: session.steps,
                onMistakes: { wrong in
                    let wrongLessons = Set(wrong.compactMap { CampusReview.lesson(of: $0) })
                    CampusReview.record(reviewed: session.lessonIDs, wrong: wrongLessons)
                }
            ) { revision += 1 }
        }
        .proFeature(isPresented: $showingPaywall, athlete: athlete, feature: .unlimitedLessons)
        .sheet(isPresented: $showingGuide, onDismiss: { revision += 1 }) {
            SportGuideView(athlete: athlete)
        }
        // A lesson picked in search or from a briefing.
        .onAppear { openPendingLesson() }
        .onChange(of: CampusLaunch.shared.pendingLessonID) { openPendingLesson() }
    }

    private func openPendingLesson() {
        guard let id = CampusLaunch.shared.pendingLessonID else { return }
        CampusLaunch.shared.pendingLessonID = nil
        if let lesson = campusTopics.flatMap(\.lessons).first(where: { $0.id == id }) { start(lesson) }
    }

    /// Area colours, as accents only.
    static func color(for topic: CampusTopic) -> Color {
        switch topic.id {
        case "training-science": AppTheme.brand
        case "nutrition": AppTheme.green
        case "injury-anatomy": AppTheme.coral
        case "sleep": AppTheme.cyan
        case "psychology": AppTheme.purple
        case "technique": AppTheme.water
        case "tactics": AppTheme.orange
        case "tracking": AppTheme.yellow
        case "teamwork": Color(hex: "#FF86D0")
        case "supplements": AppTheme.yellow
        case "digital": AppTheme.water
        default: AppTheme.amber
        }
    }

    /// Plays a lesson: replays are always free; new lessons have a daily allowance on free.
    private func start(_ lesson: CampusLesson) {
        if learned.contains(lesson.id) || CampusProgress.lessonsLeftToday() != 0 {
            playing = lesson
        } else {
            showingPaywall = true
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        if embedded {
            // The Academy's Campus: one sentence says what it is and how far you are.
            Headline([.strong("Learn what makes you better."),
                      .soft(" \(learned.count) of \(totalLessons) lessons learned.")], size: 30)
                .padding(.top, 12)
        } else {
            // V8: the count in one sentence; the next lesson is the card below.
            VStack(alignment: .leading, spacing: 8) {
                Text("Short lessons")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityAddTraits(.isHeader)
                Headline([.strong("\(learned.count) of \(totalLessons)"), .soft(" learned. A few minutes each.")], size: 30)
            }
            .padding(.top, 8)
            .padding(.trailing, 44) // the sheet's close button
        }
    }

    /// The sport guide and the athlete's position lesson.
    private var sportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Your sport")
            SportGuideCard(athlete: athlete) { showingGuide = true }
            if let lesson = positionLesson {
                Button { playing = lesson } label: {
                    ListRow(systemImage: "person.fill.viewfinder", color: AppTheme.brand, title: "Know your position",
                            detail: "\(lesson.minutes) min · your job in the \(AcademyContent.family(forSport: athlete.activeSport?.sportSlug).event)")
                }
                .buttonStyle(.plain)
                .padding(14)
                .glassSurface(cornerRadius: 16)
            }
        }
    }

    /// The nine areas as a two-column grid: icon, name, how far.
    private var areaGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Lessons by area")
            // Not lazy: a dozen tiles, every one there for VoiceOver and UI tests.
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                ForEach(Array(stride(from: 0, to: campusTopics.count, by: 2)), id: \.self) { start in
                    GridRow {
                        ForEach(campusTopics[start..<min(start + 2, campusTopics.count)]) { topic in
                            NavigationLink(value: topic) { areaTile(topic) }
                                .buttonStyle(.pressable)
                        }
                        if start + 1 >= campusTopics.count { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                    }
                }
            }
        }
    }

    private func areaTile(_ topic: CampusTopic) -> some View {
        let done = topic.lessons.filter { learned.contains($0.id) }.count
        return VStack(alignment: .leading, spacing: 10) {
            Image(systemName: topic.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Self.color(for: topic))
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text(topic.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(done) of \(topic.lessons.count)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// The athlete's position, as a lesson from their sport's guide.
    private var positionLesson: CampusLesson? {
        guard let sport = athlete.activeSport, let position = sport.positionSlug,
              let name = allSportsBySlug[sport.sportSlug]?.positions.first(where: { $0.slug == position })?.name,
              let guide = SportGuide.forSport(sport.sportSlug) else { return nil }
        return guide.positionLesson(positionSlug: position, positionName: name)
    }

    /// The next lesson in the area studied most recently, or the first not yet learned.
    private var next: (lesson: CampusLesson, topic: CampusTopic)? {
        let lastID = UserDefaults.standard.string(forKey: CampusProgress.lastLessonKey)
        if let topic = lastID.flatMap({ id in campusTopics.first { $0.lessons.contains { $0.id == id } } }),
           let lesson = topic.lessons.first(where: { !learned.contains($0.id) }) {
            return (lesson, topic)
        }
        for topic in campusTopics {
            if let lesson = topic.lessons.first(where: { !learned.contains($0.id) }) { return (lesson, topic) }
        }
        return nil
    }

    @ViewBuilder
    private var continueRow: some View {
        if let next {
            Button { start(next.lesson) } label: {
                // V8: the one place to look — the next lesson on the mind card.
                AuraCard(.mind, focus: UnitPoint(x: 0.2, y: 0.4), radius: 200, padding: 20) {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(learned.isEmpty ? "Start here" : "Continue")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.ink.opacity(0.8))
                            Text(next.lesson.title)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(AppTheme.ink)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(next.topic.title) · \(next.lesson.minutes) min")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.ink.opacity(0.75))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "play.fill")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Color.black)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.white))
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            Text("Every lesson learned. Reviews keep it fresh; replay any lesson from its area.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Learning areas

    private func areaRow(_ topic: CampusTopic, index: Int) -> some View {
        let done = topic.lessons.filter { learned.contains($0.id) }.count
        let color = Self.color(for: topic)
        return HStack(spacing: 14) {
            Image(systemName: topic.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(topic.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.leading)
                Text("\(done)/\(topic.lessons.count)")
                    .font(.telemetry(13))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func finish(_ lesson: CampusLesson) {
        // Position lessons aren't part of the library count.
        guard !lesson.id.hasPrefix("position-") else { return }
        var set = learned
        let firstTime = !set.contains(lesson.id)
        if firstTime { CampusProgress.recordNewLesson() }
        set.insert(lesson.id)
        learnedRaw = set.sorted().joined(separator: ",")
        UserDefaults.standard.set(lesson.id, forKey: CampusProgress.lastLessonKey)
        if firstTime { CampusReview.schedule(lesson.id) }
    }

    /// On free: how many new lessons are left today — calm, never a pop-up.
    @ViewBuilder
    private var dailyAllowance: some View {
        let _ = revision
        if let left = CampusProgress.lessonsLeftToday(), next != nil {
            if left > 0 {
                Text("\(left) new lesson\(left == 1 ? "" : "s") left today · replays are always free")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedText)
            } else {
                ProLockCard(feature: .unlimitedLessons, title: "That's today's \(ProLimits.freeLessonsPerDay) new lessons",
                            message: "Come back tomorrow, replay any lesson now, or keep learning with Pro.")
            }
        }
    }

    /// "Review: 3 lessons" — spaced repetition keeps what was learned.
    private var reviewCard: some View {
        let due = dueForReview
        return Button {
            let ids = Array(due.prefix(CampusReview.lessonsPerReview))
            let steps = CampusReview.questions(for: ids).map { CampusStep.question($0) }
            if !steps.isEmpty { reviewing = ReviewSession(lessonIDs: ids, steps: steps) }
        } label: {
            ListRow(systemImage: "arrow.triangle.2.circlepath", color: AppTheme.orange, title: "Review · 2 min",
                    detail: "\(due.count) lesson\(due.count == 1 ? "" : "s") to refresh")
                .padding(12)
                .glassSurface(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }
}

/// One learning area: its lessons by level, all open. Done ones replay.
struct LearningAreaView: View {
    let topic: CampusTopic
    let color: Color
    let onPlay: (CampusLesson) -> Void
    @AppStorage(CampusProgress.learnedKey) private var learnedRaw = ""

    private var learned: Set<String> { CampusProgress.learned(learnedRaw) }

    private var byLevel: [(level: CampusLevel, lessons: [CampusLesson])] {
        CampusLevel.allCases.compactMap { level in
            let lessons = topic.lessons.filter { CampusLibrary.level(of: $0.id) == level }
            return lessons.isEmpty ? nil : (level, lessons)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                ScreenTitle(topic.title, subtitle: topic.subtitle)
                ForEach(byLevel, id: \.level) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.level.title)
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        Text(group.level.subtitle)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.secondaryText)
                            .padding(.bottom, 6)
                        ForEach(group.lessons, id: \.id) { lesson in row(lesson) }
                    }
                }
                Text(CampusLibrary.reviewNote)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .appScreen()
    }

    private func row(_ lesson: CampusLesson) -> some View {
        let done = learned.contains(lesson.id)
        return Button { onPlay(lesson) } label: {
            HStack(spacing: 14) {
                Circle()
                    .fill(done ? color : AppTheme.fill)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lesson.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.leading)
                    Text(done ? "Done · replay any time" : "\(lesson.minutes) min")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer(minLength: 4)
                Image(systemName: done ? "arrow.counterclockwise" : "play.fill")
                    .font(.footnote)
                    .foregroundStyle(done ? AppTheme.secondaryText : AppTheme.ink)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - The lesson player

struct CampusLessonPlayer: View {
    let lesson: CampusLesson
    /// A review plays questions from several lessons instead of one lesson's steps.
    var customSteps: [CampusStep]? = nil
    /// Called with the questions answered wrong at least once (for reviews).
    var onMistakes: (Set<CampusQuestion>) -> Void = { _ in }
    /// Called when the lesson is finished.
    let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var queue: [CampusStep] = []
    @State private var index = 0
    @State private var completed = 0
    @State private var mistakes = 0
    @State private var phase: Phase = .answering
    @State private var choice: Int?
    @State private var fillWord: String?
    @State private var match = MatchState()
    @State private var startedAt = Date.now
    @State private var finishedAt: Date?
    @State private var feedbackTrigger = 0
    @State private var confirmQuit = false
    @State private var wrong: Set<CampusQuestion> = []
    @StateObject private var speaker = LessonSpeaker()

    enum Phase { case answering, correct, wrong }

    private var allSteps: [CampusStep] { customSteps ?? lesson.steps }
    private var questionCount: Int {
        allSteps.filter { if case .question = $0 { return true } else { return false } }.count
    }
    private var total: Int { allSteps.count }
    private var step: CampusStep? { queue.indices.contains(index) ? queue[index] : nil }

    var body: some View {
        VStack(spacing: 0) {
            if finishedAt != nil {
                CampusComplete(accuracy: accuracy, seconds: Int((finishedAt ?? .now).timeIntervalSince(startedAt))) {
                    onMistakes(wrong)
                    onFinish()
                    dismiss()
                }
            } else {
                header
                ScrollView {
                    Group {
                        if let step { stepView(step) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
                .scrollIndicators(.hidden)
                footer
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .onAppear { if queue.isEmpty { queue = allSteps } }
        .onDisappear { speaker.stop() }
        .sensoryFeedback(trigger: feedbackTrigger) { _, _ in phase == .wrong ? .error : .success }
        .confirmationDialog("Quit this lesson?", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("Quit", role: .destructive) { dismiss() }
            Button("Keep learning", role: .cancel) {}
        } message: {
            Text("Your progress in this lesson will be lost.")
        }
    }

    private var accuracy: Int {
        let answered = questionCount + mistakes
        return answered == 0 ? 100 : Int((Double(questionCount) / Double(answered) * 100).rounded())
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button { confirmQuit = true } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Quit lesson")
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.fill)
                    Capsule().fill(AppTheme.accent)
                        .frame(width: max(6, geo.size.width * Double(completed) / Double(max(1, total))))
                        .animation(.easeOut(duration: 0.3), value: completed)
                }
            }
            .frame(height: 6)
            .accessibilityElement()
            .accessibilityLabel("Step \(min(completed + 1, total)) of \(total)")
            if customSteps == nil {
                Button { speaker.toggle(lesson) } label: {
                    Image(systemName: speaker.isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(speaker.isSpeaking ? "Stop reading" : "Listen to this lesson")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    @ViewBuilder
    private func stepView(_ step: CampusStep) -> some View {
        switch step {
        case .teach(let section):
            TeachCard(section: section, lessonTitle: lesson.title)
        case .question(let question):
            QuestionView(question: question, phase: phase, choice: $choice, fillWord: $fillWord, match: $match) {
                // A matching exercise checks itself once every pair is found.
                phase = .correct
                feedbackTrigger += 1
            }
            .id(index)
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch phase {
        case .answering:
            footerButton
                .padding(20)
        case .correct:
            FeedbackPanel(correct: true, title: "Correct", detail: nil) { advance() }
        case .wrong:
            FeedbackPanel(correct: false, title: "Not quite. The answer:", detail: wrongDetail) { advance() }
        }
    }

    @ViewBuilder
    private var footerButton: some View {
        if let step {
            switch step {
            case .teach:
                Button("Continue") { advance() }
                    .buttonStyle(.primary)
            case .question(let q):
                if case .match = q {
                    // Matching needs no Check button: it checks itself.
                    Button("Check") {}.buttonStyle(.primary).disabled(true)
                } else {
                    Button("Check") { check(q) }
                        .buttonStyle(.primary)
                        .disabled(!answerReady(q))
                }
            }
        }
    }

    private var wrongDetail: String {
        guard let step, case .question(let q) = step else { return "" }
        switch q {
        case .choice(_, let options, let answer, let explain): return "\(options[answer])\n\(explain)"
        case .trueFalse(_, let answer, let explain): return "\(answer ? "True" : "False")\n\(explain)"
        case .fill(_, _, _, let answer, let explain): return "\(answer)\n\(explain)"
        case .match: return ""
        }
    }

    private func answerReady(_ q: CampusQuestion) -> Bool {
        switch q {
        case .choice, .trueFalse: choice != nil
        case .fill: fillWord != nil
        case .match: match.isComplete
        }
    }

    private func check(_ q: CampusQuestion) {
        let right: Bool
        switch q {
        case .choice(_, _, let answer, _): right = choice == answer
        case .trueFalse(_, let answer, _): right = choice == (answer ? 0 : 1)
        case .fill(_, _, _, let answer, _): right = fillWord == answer
        case .match: right = true
        }
        phase = right ? .correct : .wrong
        if !right {
            mistakes += 1
            wrong.insert(q)
            // A missed question comes back at the end of the lesson.
            queue.append(queue[index])
        }
        feedbackTrigger += 1
    }

    private func advance() {
        if phase != .wrong { completed = min(total, completed + 1) }
        phase = .answering
        choice = nil
        fillWord = nil
        match = MatchState()
        if index + 1 < queue.count {
            index += 1
        } else {
            completed = total
            finishedAt = .now
        }
    }
}

/// A teaching card: the coach explains one idea in a speech bubble.
private struct TeachCard: View {
    let section: CampusSection
    let lessonTitle: String

    var body: some View {
        let forYou = section.heading == CampusLesson.meansForYouHeading
        let example = section.heading == CampusLesson.exampleHeading
        VStack(alignment: .leading, spacing: 16) {
            Text(lessonTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AuraTone.mind.mark)
            if forYou || example {
                Label(section.heading, systemImage: forYou ? "person.fill.checkmark" : "figure.run")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
            } else {
                Text(section.heading)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(section.body)
                .font(.body)
                .foregroundStyle(AppTheme.ink)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(forYou || example ? 20 : 0)
                .background {
                    if forYou || example {
                        AuraBackground(.mind, focus: UnitPoint(x: 0.1, y: 0), radius: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Matching state: which left/right tiles are picked, which pairs are found, and a brief wrong flash.
struct MatchState: Equatable {
    var left: Int?
    var right: Int?
    var matched: Set<Int> = []
    var wrong: [Int] = []
    var pairCount = 0
    var isComplete: Bool { pairCount > 0 && matched.count == pairCount }
}

private struct QuestionView: View {
    let question: CampusQuestion
    let phase: CampusLessonPlayer.Phase
    @Binding var choice: Int?
    @Binding var fillWord: String?
    @Binding var match: MatchState
    let onMatched: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            switch question {
            case .choice(let prompt, let options, let answer, _):
                title("Choose the right answer")
                Text(prompt).font(.title2.weight(.bold)).foregroundStyle(AppTheme.ink).fixedSize(horizontal: false, vertical: true)
                let order = stableOrder(options.count, seed: prompt)
                VStack(spacing: 12) {
                    ForEach(order, id: \.self) { i in
                        tile(options[i], index: i, answer: answer)
                    }
                }
            case .trueFalse(let statement, let answer, _):
                title("True or false?")
                Text(statement).font(.title2.weight(.bold)).foregroundStyle(AppTheme.ink).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    tile("True", index: 0, answer: answer ? 0 : 1)
                    tile("False", index: 1, answer: answer ? 0 : 1)
                }
            case .fill(let before, let after, let options, let answer, _):
                title("Fill in the blank")
                sentence(before: before, after: after)
                let order = stableOrder(options.count, seed: before)
                WrapRow(items: order.map { options[$0] }) { word in
                    Button {
                        guard phase == .answering else { return }
                        fillWord = fillWord == word ? nil : word
                    } label: {
                        AnswerTile(text: word, state: fillWord == word ? (phase == .answering ? .done : (word == answer ? .correct : .wrong)) : .idle)
                            .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
            case .match(let prompt, let pairs):
                title(prompt)
                matchGrid(pairs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func tile(_ text: String, index: Int, answer: Int) -> some View {
        let state: AnswerTile.State = {
            if phase == .answering { return choice == index ? .selected : .idle }
            if index == answer { return .correct }
            return choice == index ? .wrong : .idle
        }()
        return Button {
            if phase == .answering { choice = index }
        } label: {
            AnswerTile(text: text, state: state)
        }
        .buttonStyle(.plain)
    }

    private func sentence(before: String, after: String) -> some View {
        let blank = fillWord ?? "        "
        return (Text(before + " ") + Text(blank).underline().foregroundColor(Duo.blueLip).bold() + Text(" " + after))
            .font(.title2.weight(.semibold))
            .foregroundStyle(AppTheme.ink)
            .lineSpacing(10)
            .fixedSize(horizontal: false, vertical: true)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Duo.border, lineWidth: 2))
    }

    private func matchGrid(_ pairs: [[String]]) -> some View {
        let rightOrder = stableOrder(pairs.count, seed: pairs.map { $0.first ?? "" }.joined())
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 12) {
                ForEach(0..<pairs.count, id: \.self) { i in
                    matchTile(pairs[i].first ?? "", pair: i, isLeft: true)
                }
            }
            VStack(spacing: 12) {
                ForEach(rightOrder, id: \.self) { i in
                    matchTile(pairs[i].last ?? "", pair: i, isLeft: false)
                }
            }
        }
        .onAppear { if match.pairCount == 0 { match.pairCount = pairs.count } }
    }

    private func matchTile(_ text: String, pair: Int, isLeft: Bool) -> some View {
        let picked = isLeft ? match.left == pair : match.right == pair
        let state: AnswerTile.State = match.matched.contains(pair) ? .done
            : (match.wrong.contains(pair) ? .wrong : (picked ? .selected : .idle))
        return Button {
            guard !match.matched.contains(pair) else { return }
            if isLeft { match.left = pair } else { match.right = pair }
            guard let l = match.left, let r = match.right else { return }
            if l == r {
                match.matched.insert(l)
                match.left = nil; match.right = nil
                if match.isComplete { onMatched() }
            } else {
                match.wrong = [l, r]
                match.left = nil; match.right = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { match.wrong = [] }
            }
        } label: {
            AnswerTile(text: text, state: state)
        }
        .buttonStyle(.plain)
        .disabled(match.matched.contains(pair))
    }
}

/// A simple wrapping row for word-bank chips.
private struct WrapRow<Content: View>: View {
    let items: [String]
    let content: (String) -> Content

    var body: some View {
        WrapLayout(spacing: 10) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}

struct WrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// The green or red sheet that slides up after "Check".
private struct FeedbackPanel: View {
    let correct: Bool
    let title: String
    let detail: String?
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: correct ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(correct ? AppTheme.green : AppTheme.coral)
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
            }
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.body)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(correct ? "Continue" : "Got it", action: onContinue)
                .buttonStyle(.primary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        // V8: the answer's own colour — green when right, the calm plate when not.
        .background(AuraBackground(correct ? .game : .calm, focus: UnitPoint(x: 0.1, y: 0), radius: 260).ignoresSafeArea(edges: .bottom))
        .transition(.move(edge: .bottom))
    }
}

/// Lesson complete: what it earned, calmly.
private struct CampusComplete: View {
    let accuracy: Int
    let seconds: Int
    let onContinue: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            // V8: one magenta card, the sentence big, two light numbers.
            AuraCard(.mind, focus: UnitPoint(x: 0.25, y: 0.75), radius: 240) {
                VStack(alignment: .leading, spacing: 22) {
                    Headline([.strong("Lesson complete. "), .soft("One more thing you know.")], size: 32)
                    HStack(alignment: .top, spacing: 12) {
                        FigureStat("\(accuracy)", unit: "%", label: "Right first time", size: 44)
                        FigureStat(String(format: "%d:%02d", seconds / 60, seconds % 60), label: "Time", size: 44)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(.spring(response: 0.45, dampingFraction: 0.9), value: appeared)
            Spacer()
            Button("Continue", action: onContinue)
                .buttonStyle(.primary)
        }
        .padding(24)
        .onAppear { appeared = true }
        .sensoryFeedback(.success, trigger: appeared)
    }
}
