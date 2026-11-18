import SwiftData
import SwiftUI

// MARK: - Start a workout from anywhere

/// Who is training and how to sync — what a live session needs. Put in the
/// environment once by `MainTabView`, so any preview (a plan day, a skill
/// plan day, a single exercise, even inside a sheet) can show a working
/// "Start" button without threading the athlete through every view.
@MainActor
final class WorkoutContext {
    let athlete: Athlete
    let apiClient: APIClient

    init(athlete: Athlete, apiClient: APIClient) {
        self.athlete = athlete
        self.apiClient = apiClient
    }
}

private struct WorkoutContextKey: EnvironmentKey {
    static var defaultValue: WorkoutContext? { nil }
}

extension EnvironmentValues {
    var workoutContext: WorkoutContext? {
        get { self[WorkoutContextKey.self] }
        set { self[WorkoutContextKey.self] = newValue }
    }
}

extension GeneratedSession {
    /// A one-exercise session, so a single library item can be done right now.
    static func single(_ item: CatalogueItem) -> GeneratedSession {
        let dose = item.defaultDose
        let minutes = max(5, (dose.sets * (item.restSeconds + 45)) / 60)
        return GeneratedSession(
            date: .now, title: item.name, focusQualities: item.primaryQuality.map { [$0.id] } ?? [],
            estimatedMinutes: minutes,
            items: [GeneratedPlannedItem(
                itemSlug: item.slug, order: 0, dose: dose, restSec: item.restSeconds,
                rationale: "", quality: item.primaryQuality?.id ?? ""
            )]
        )
    }
}

/// The one button every workout preview ends with. It presents the live
/// session itself, so it works wherever it sits.
struct StartWorkoutButton: View {
    let title: String
    let session: GeneratedSession
    var prominent = true
    /// Asked before launching; return false to stop (e.g. a paywall shown).
    var shouldStart: (() -> Bool)?

    @Environment(\.workoutContext) private var context
    @State private var launch: LiveSessionLaunch?

    init(_ title: String = "Start workout", session: GeneratedSession, prominent: Bool = true, shouldStart: (() -> Bool)? = nil) {
        self.title = title
        self.session = session
        self.prominent = prominent
        self.shouldStart = shouldStart
    }

    private func start() {
        guard shouldStart?() ?? true else { return }
        launch = LiveSessionLaunch(planned: session)
    }

    var body: some View {
        if let context, !session.items.isEmpty {
            Group {
                if prominent {
                    Button(action: start) {
                        Label(title, systemImage: "play.fill")
                    }
                    .buttonStyle(.primary)
                } else {
                    Button(action: start) {
                        Label(title, systemImage: "play.fill")
                    }
                    .buttonStyle(.secondary)
                }
            }
            .fullScreenCover(item: $launch) { launch in
                LiveSessionView(athlete: context.athlete, apiClient: context.apiClient, planned: launch.planned, kind: launch.kind)
            }
        }
    }
}

// MARK: - First-run tour

/// One card per tab, plus Me (the profile button), shown once after setup
/// (and any time from Me → Help). Says what each tab is for and the one thing to do there.
struct AppTourView: View {
    let onFinish: () -> Void
    @State private var page = 0

    struct Page {
        let icon: String
        let color: Color
        let tab: String
        let title: String
        let body: String
        let steps: [String]

        /// Where it lives: "Home tab", or the profile button for Me.
        var place: String { tab == "Me" ? "Top left" : "\(tab) tab" }
    }

    static let pages: [Page] = [
        Page(icon: "house.fill", color: AppTheme.ink, tab: "Home",
             title: "Your day at a glance",
             body: "Home is your day: the morning check-in, today's readiness, the one next step, and why. Tell AthleteOS what's coming up in your own words, and the trophy opens your competitions.",
             steps: ["Check in each morning — 30 seconds", "Do the next step at the top", "Type \u{201C}match on Saturday\u{201D} into Tell AthleteOS"]),
        Page(icon: "figure.stand.line.dotted.figure.stand", color: AppTheme.brightRed, tab: "Academy",
             title: "Your digital twin",
             body: "Your twin reads your check-ins, training, games and tests, and an interview about how you think. It shows what's really going on, holds your best performances, and your coach assigns a briefing for each thing it finds. Switch to Progress for your calendar, practice log and history. Only you can see it.",
             steps: ["Do the interview — about five minutes", "Read the coach's read and your insights", "Add any performance you want to track"]),
        Page(icon: "figure.strengthtraining.traditional", color: AppTheme.brand, tab: "Workout",
             title: "Three kinds of workout",
             body: "After practice: short and smart. Gym day: your full session on days without practice. Stretching & mobility: good every day. Each one is built for your sport, your schedule and your goals.",
             steps: ["The one for today is marked", "See it, then press Start", "Change it: swap, add or remove exercises, pick your days"]),
        Page(icon: "person.fill", color: AppTheme.purple, tab: "Me",
             title: "You, your goals and settings",
             body: "Me opens from the round button at the top left of every tab. Set your development goals — speed, strength, conditioning — and your training leans towards them. Sports, equipment, team & family, reminders and your account live here too.",
             steps: ["Me → My Development Goals", "Academy → Performances → Run a test every 6–8 weeks", "Replay this tour any time in Me → Help"]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { onFinish() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .opacity(page < Self.pages.count - 1 ? 1 : 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            TabView(selection: $page) {
                ForEach(Array(Self.pages.enumerated()), id: \.offset) { index, page in
                    pageView(page).tag(index)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif

            HStack(spacing: 8) {
                ForEach(0..<Self.pages.count, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? AppTheme.accent : AppTheme.hairline)
                        .frame(width: index == page ? 22 : 8, height: 8)
                }
            }
            .animation(.snappy, value: page)
            .padding(.bottom, 20)
            .accessibilityHidden(true)

            Button(page < Self.pages.count - 1 ? "Next" : "Let's go") {
                if page < Self.pages.count - 1 {
                    withAnimation(.snappy) { page += 1 }
                } else {
                    onFinish()
                }
            }
            .buttonStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .appScreen()
    }

    private func pageView(_ page: Page) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ZStack {
                    Circle().fill(page.color.opacity(0.12)).frame(width: 150, height: 150)
                    Circle().fill(AppTheme.card).frame(width: 104, height: 104)
                        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
                    Image(systemName: page.icon)
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(page.color)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 8) {
                    Tag(page.place, color: page.color == AppTheme.ink ? AppTheme.secondaryText : page.color)
                    Text(page.title)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(page.body)
                        .font(.body)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(page.steps.enumerated()), id: \.offset) { index, step in
                        HStack(spacing: 14) {
                            Text("\(index + 1)")
                                .font(.subheadline.bold())
                                .foregroundStyle(AppTheme.onAccent)
                                .frame(width: 30, height: 30)
                                .background(AppTheme.accent, in: Circle())
                            Text(step)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Contextual tips

/// A one-time hint at the top of a screen: what this screen is for and
/// where to tap. Dismissed for good with the ×; Me → Help brings all back.
struct TipCard: View {
    let id: String
    let icon: String
    let title: String
    let message: String

    @AppStorage private var dismissed: Bool

    init(id: String, icon: String, title: String, message: String) {
        self.id = id
        self.icon = icon
        self.title = title
        self.message = message
        _dismissed = AppStorage(wrappedValue: false, "tip.\(id)")
    }

    static let allIDs = ["plan", "improve", "muscles", "library", "live"]

    static func resetAll() {
        for id in allIDs { UserDefaults.standard.removeObject(forKey: "tip.\(id)") }
    }

    var body: some View {
        if !dismissed {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.onAccent)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.accent, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.ink)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.snappy) { dismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(width: 24, height: 24)
                        .background(AppTheme.fill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Got it")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(padding: 14)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - Help

/// Me → Help: replay the tour, bring the tips back, and plain answers to
/// the questions a new athlete actually has.
struct HelpCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingTour = false
    @State private var tipsReset = false
    @State private var expanded: String?

    private let faqs: [(q: String, a: String)] = [
        ("How do I start a workout?",
         "Home → the next step, or the Workout tab: today's workout is on top, the other workouts below. You can also start any day of a skill plan, a muscle workout, or a single exercise from the Library (Try it now)."),
        ("What happens during a workout?",
         "You see one exercise at a time with its key positions. Set the reps or weight with the big buttons, tap Log set, and a rest timer starts on its own. Swipe or tap Next when you're done with an exercise. Tap × to finish."),
        ("Why did my workout change?",
         "If your morning check-in shows poor sleep or high soreness, workouts get lighter. You can always switch back to the full ones."),
        ("How do games change my week?",
         "Add it with the + on Home, the trophy on Home (your games, results and game prep), or just tell AthleteOS (“game on Saturday”). Heavy work moves early in the week and the day before the game stays light, so you're fresh."),
        ("What do the colours in the calendar mean?",
         "Violet: a workout. Orange: team practice. Yellow: the extra workout after practice. Cyan: stretching and mobility. Green: a game. A day with several gets a split dot; outlined means planned; a ring marks a game."),
        ("How do I log team practice?",
         "Academy → Progress → Team practice → Log today's practice, or tap an earlier day in the calendar. Choose Easy (how hard, how it went, mood) or Exact (also tired muscles and how each part of your game went)."),
        ("How do I get better at one skill?",
         "Workout → Build and explore → Skill plans → choose a skill → set the date → Build my plan. Its drills then show on Home and Workout."),
        ("How do I make workouts more personal?",
         "Me → My Development Goals: choose up to three, like acceleration, strength or conditioning. Your training leans towards them."),
        ("What do the violet muscles mean?",
         "Solid violet is what an exercise mainly works, lighter violet is what helps. The same colours glow on the athlete in the pictures."),
        ("Does it work without internet?",
         "Yes. Every exercise, drill and plan is on your phone. Internet is only used to back up your history."),
        ("How do I change my sport or equipment?",
         "Me → Your training setup. Your workouts rebuild straight away."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ScreenTitle("Help", subtitle: "How the app works, in plain words.")

                    VStack(spacing: 10) {
                        Button { showingTour = true } label: {
                            Label("Replay the app tour", systemImage: "play.circle.fill")
                        }
                        .buttonStyle(.primary)
                        Button {
                            TipCard.resetAll()
                            tipsReset = true
                        } label: {
                            Label(tipsReset ? "Tips are back on every screen" : "Show screen tips again", systemImage: tipsReset ? "checkmark" : "lightbulb.fill")
                        }
                        .buttonStyle(.secondary)
                    }

                    SectionTitle("Questions")
                    VStack(spacing: 0) {
                        ForEach(Array(faqs.enumerated()), id: \.offset) { index, faq in
                            Button {
                                withAnimation(.snappy) { expanded = expanded == faq.q ? nil : faq.q }
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(faq.q)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AppTheme.ink)
                                            .multilineTextAlignment(.leading)
                                        Spacer()
                                        Image(systemName: expanded == faq.q ? "chevron.up" : "chevron.down")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(AppTheme.secondaryText)
                                    }
                                    if expanded == faq.q {
                                        Text(faq.a)
                                            .font(.footnote)
                                            .foregroundStyle(AppTheme.secondaryText)
                                            .multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < faqs.count - 1 {
                                Divider().overlay(AppTheme.hairline)
                            }
                        }
                    }
                    .cardStyle(padding: 16)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .appScreen()
            .toolbar {
                CloseToolbarItem { dismiss() }
            }
            .fullScreenCover(isPresented: $showingTour) {
                AppTourView { showingTour = false }
            }
        }
    }
}

// MARK: - Pro

/// Whether the athlete has Pro, wherever the code runs. StoreKit only
/// exists in the iOS app; the watch and widgets never gate anything.
@MainActor
enum ProAccess {
    static var isPro: Bool {
        #if os(iOS) && !APP_EXTENSION
        ProStore.shared.isPro
        #else
        true
        #endif
    }
}

extension View {
    /// The paywall, opened on the feature that was tapped — a no-op outside
    /// the iOS app.
    @ViewBuilder
    func proPaywall(isPresented: Binding<Bool>, athlete: Athlete?, feature: ProFeature) -> some View {
        #if os(iOS) && !APP_EXTENSION
        if let athlete {
            paywallSheet(isPresented: isPresented, athlete: athlete, highlight: feature)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// The paywall on whichever feature was tapped last (nil: closed).
    func proPaywall(item: Binding<ProFeature?>, athlete: Athlete?) -> some View {
        proPaywall(isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } }),
                   athlete: athlete, feature: item.wrappedValue ?? .skillBlocks)
    }
}

extension ProFeature: Identifiable {
    public var id: String { rawValue }
}

/// Entering a Pro feature: what it is, that it's part of Pro, one Upgrade
/// button (V3 — no lock icons around the app, no hard sell).
struct ProFeatureSheet: View {
    let feature: ProFeature
    let athlete: Athlete?
    @Environment(\.dismiss) private var dismiss
    @State private var showingPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "sparkles")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.onAccent)
                .frame(width: 52, height: 52)
                .background(AppTheme.accent, in: Circle())
            Text(feature.proTitle)
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Text(feature.proBenefit)
                .font(.body)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Available with AthleteOS Pro.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
            Spacer(minLength: 0)
            Button("Upgrade") { showingPaywall = true }
                .buttonStyle(.primary)
            Button("Not now") { dismiss() }
                .font(.headline)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .padding(24)
        .presentationDetents([.medium])
        .appScreen()
        .proPaywall(isPresented: $showingPaywall, athlete: athlete, feature: feature)
    }
}

extension View {
    /// Explains a Pro feature when the athlete taps into it (then Upgrade).
    func proFeature(item: Binding<ProFeature?>, athlete: Athlete?) -> some View {
        sheet(item: item) { feature in ProFeatureSheet(feature: feature, athlete: athlete) }
    }

    func proFeature(isPresented: Binding<Bool>, athlete: Athlete?, feature: ProFeature) -> some View {
        sheet(isPresented: isPresented) { ProFeatureSheet(feature: feature, athlete: athlete) }
    }
}

/// A calm card where a Pro feature would be: what it adds and one button.
/// Never a pop-up on its own.
struct ProLockCard: View {
    let feature: ProFeature
    let title: String
    let message: String

    @Environment(\.workoutContext) private var context
    @State private var showingPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(AppTheme.onAccent)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.accent, in: Circle())
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Spacer(minLength: 0)
            }
            Text(message)
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Available with AthleteOS Pro.")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
            Button("Upgrade") { showingPaywall = true }
                .buttonStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16)
        .proPaywall(isPresented: $showingPaywall, athlete: context?.athlete, feature: feature)
    }
}

/// Start dates of muscle-group workouts, for the free weekly allowance.
enum MuscleWorkoutLedger {
    private static let key = "muscleWorkoutStarts"

    static var dates: [Date] {
        (UserDefaults.standard.string(forKey: key) ?? "")
            .split(separator: ",")
            .compactMap { Double($0).map(Date.init(timeIntervalSince1970:)) }
    }

    static func record(_ date: Date = .now) {
        let recent = dates.filter { $0 > date.addingTimeInterval(-60 * 60 * 24 * 60) } + [date]
        UserDefaults.standard.set(recent.map { String($0.timeIntervalSince1970) }.joined(separator: ","), forKey: key)
    }
}

// MARK: - Saved skill plans on Today

/// A saved skill plan's session for one day.
struct SkillPlanDay: Identifiable {
    let block: SkillBlock
    let skillName: String
    let session: GeneratedSession
    var id: String { block.id }
}

@MainActor
enum SavedSkillPlans {
    /// Every saved plan (for the active sport) that has drills on `date`,
    /// regenerated exactly as it was saved.
    static func days(on date: Date, athlete: Athlete, catalogue: Catalogue) -> [SkillPlanDay] {
        guard let sportSlug = athlete.activeSport?.sportSlug, let sport = allSportsBySlug[sportSlug] else { return [] }
        let calendar = Calendar.current
        return athlete.skillBlocks
            .filter { $0.sportSlug == sportSlug && calendar.startOfDay(for: $0.targetDate) >= calendar.startOfDay(for: date) }
            .compactMap { block in
                guard let skill = sport.skills.first(where: { $0.slug == block.skillSlug }) else { return nil }
                let generated = SkillMenuEngine.generate(SkillMenuInput(
                    sportSlug: sportSlug, skillSlug: skill.slug, skillName: skill.name,
                    qualityWeights: skill.qualityWeights, today: block.generatedAt, gameDate: block.targetDate,
                    birthDate: athlete.birthDate, trainsUnderCoach: athlete.trainsUnderCoach,
                    equipmentAvailable: Set(athlete.equipmentAvailable), catalogue: catalogue, seed: block.seed,
                    positionSlug: athlete.activeSport?.positionSlug, formatSlug: athlete.activeSport?.formatSlug
                ))
                guard let day = generated.days.first(where: { calendar.isDate($0.date, inSameDayAs: date) }), !day.items.isEmpty else { return nil }
                return SkillPlanDay(block: block, skillName: skill.name, session: day)
            }
    }
}
