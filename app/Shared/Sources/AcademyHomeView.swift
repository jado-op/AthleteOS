import Charts
import SwiftUI
#if os(iOS)
import UIKit
#endif

// The Academy's Twin page (owner, 2026-11-27: shaped around the ecosystem;
// order and rules in TwinPage.swift): who this is and the one line that
// matters now, then "What I know about you" — one portrait, the lines that
// shape the plan saying how — then what it's still learning, then the
// evidence one level down (how you're performing, changing, and how your
// mind is evolving). The interview answers and the long reads live on Campus.

extension BriefingTopic {
    var color: Color {
        switch self {
        case .recovery: AppTheme.cyan
        case .strength: AppTheme.orange
        case .mind: AppTheme.purple
        case .fuel: AppTheme.yellow
        }
    }
}

extension TwinInsightKind {
    var topic: BriefingTopic? {
        switch self {
        case .sleepBeforeGames, .recoveryAfterGames, .sleepBase, .irregularSleep, .sleepAffectsPractice: .recovery
        case .strengthNotSpeed, .strengthRising, .consistentTraining, .loadSpike: .strength
        case .mistakeReplay, .pressureConfidence, .stressAndSleep: .mind
        case .gameDayFuel: .fuel
        }
    }
}

/// Reading serif (New York on iOS) for the coach's voice and the briefings.
/// Scales with the athlete's text size (Dynamic Type): the long reads are
/// the screens where it matters most.
extension Font {
    static func reading(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        #if os(iOS)
        let scaled = UIFontMetrics(forTextStyle: .body).scaledValue(for: size)
        #else
        let scaled = size
        #endif
        return .system(size: scaled, weight: weight, design: .serif)
    }
}

/// Where the Twin page goes one level down: the evidence behind the portrait.
enum TwinRoute: Hashable {
    case performing, body, mind, allHealth
}

struct AcademyHomeView: View {
    let athlete: Athlete

    @State private var state = AcademyState()
    @State private var report: TwinReport?
    @State private var records: [PerformanceRecord] = []
    @State private var reading: ReadingTarget?
    @State private var showingInterview = false
    /// The question the interview opens on (an answer tapped to edit).
    @State private var interviewStart: String?
    @State private var showingSupport = false
    @State private var confirmingDelete = false
    @State private var liftTrends: [LiftTrend] = []
    @State private var weekLoads: [WeekLoad] = []
    @State private var sleepNights: [TwinPoint] = []
    @State private var readinessDays: [(date: Date, band: ReadinessBand?)] = []
    @State private var calmWeeks: [TwinPoint] = []
    @State private var feltWeeks: [TwinPoint] = []
    @State private var stressShift: Double?
    @State private var bodyReport: MuscleTraining.Report?
    @State private var recovering: [(region: GymRegion, days: Int)] = []
    /// "Your last 7 days": the body lit by this week only, and one line about it.
    @State private var weekGroups: [MuscleTraining.GroupWeek] = []
    @State private var weekSentence = "How hard each part of your body worked, and your week's numbers."
    @State private var showingWeek = false
    /// "What I know about you" shows three lines until "See all".
    @State private var showingAllKnown = false
    /// "What I know about you" (owner, 2026-11-27): the twin's portrait of the athlete.
    @State private var knowledge = TwinKnowledge(lines: [], learning: [], legRecoveryDays: nil)
    /// What the twin changes in the plan, said where the fact is (TwinPage).
    @State private var effects: [TwinPlanEffect] = []
    @State private var letter: TwinLetter?
    /// A line the athlete is about to say isn't right.
    @State private var correcting: KnowledgeLine?
    /// "Got it": shown after a correction so the athlete sees it was used.
    @State private var correctedNote: String?
    /// "More insights into your health": everything Apple Health holds.
    @StateObject private var health = HealthInsightsViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [TwinRoute] = []
    /// A part of the page to bring into view ("know").
    @State private var scrollTarget: String?
    @State private var openLift: LiftTrend?
    @State private var showingTests = false
    /// The last 30 days, sleep and load over time: the twin's one Trends page.
    @State private var showingTrends = false
    @State private var showingExerciseProgress = false
    @State private var showingExerciseProgressPaywall = false
    @State private var showingCompetitions = false
    @State private var catalogue = Catalogue()
    @ObservedObject private var navigation = AcademyNavigation.shared
    @State private var addingPerformance = false
    @State private var openRecord: PerformanceRecord?

    struct ReadingTarget: Identifiable {
        let briefing: Briefing
        let insight: TwinInsight?
        var id: String { briefing.id }
    }

    private var sportSlug: String? { athlete.activeSport?.sportSlug }
    private var athleteAge: Int { PlanGenerator.ageInYears(birthDate: athlete.birthDate, now: .now) }
    private var family: SportFamily { AcademyContent.family(forSport: sportSlug) }

    /// "Central midfielder · Soccer · In season"
    private var meta: String {
        guard let sport = athlete.activeSport else { return "Add your sport in Me" }
        var parts: [String] = []
        if let position = sport.positionSlug,
           let name = allSportsBySlug[sport.sportSlug]?.positions.first(where: { $0.slug == position })?.name {
            parts.append(name)
        }
        parts.append(AthleteStats.sportName(athlete))
        parts.append(AthleteStats.phaseLabel(PhaseCalculator.phase(today: .now, seasonStart: sport.seasonStart, seasonEnd: sport.seasonEnd)))
        return parts.joined(separator: " · ")
    }

    private var visibleLines: [KnowledgeLine] { TwinKnowledgeStore.visible(knowledge, state: state) }
    private var portrait: [TwinPageArea] {
        // The hero's own line is said once, up there.
        let heroID = heroLine.lineID
        return TwinPage.portrait(lines: visibleLines.filter { $0.id != heroID }, known: Set(knowledge.lines.map(\.id)), insights: report?.insights ?? [],
                          strengths: report?.strengths ?? [], effects: effects)
    }
    private var hiddenCount: Int { knowledge.lines.filter { state.knowledgeHidden?[$0.id] != nil && !$0.safety }.count }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topBar.id("top")
                    // 1. Whose twin, the one line that matters now, the body.
                    identity.padding(.top, 26)
                    hero.padding(.top, 22)
                    // Owner, 2026-11-20: tap the twin, see the week on your body.
                    TwinWeekCard(heat: TwinHeat.map(weekGroups), sentence: weekSentence) { showingWeek = true }
                        .padding(.top, 14)
                    if let letter {
                        TwinLetterCard(letter: letter) {
                            TwinKnowledgeStore.closeLetter(letter.month)
                            withAnimation { self.letter = nil }
                        }
                        .padding(.top, 28)
                    }
                    // 2. What it knows and, right under it, what it's learning next
                    // (one section — redesign 2026-11-28: the page was busy).
                    knowSection.padding(.top, 44).id("know")
                    // 3. The evidence, one level down.
                    evidence.padding(.top, 44).id("evidence")
                    // 4. One quiet footer: help, whose this is, the way out.
                    footer.padding(.top, 44)
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .appScreen(.hero, sportSlug: sportSlug)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TwinRoute.self) { route in destination(route) }
            // Screenshots: `-tab academy -sheet health|health2|healthAll|know|learning|evidence`.
            .onChange(of: health.phase) {
                guard DemoData.initialTab == .academy, health.phase == .ready else { return }
                switch DemoData.initialSheet {
                case "health", "health2": path = [.body]
                case "healthAll": path = [.body, .allHealth]
                default: break
                }
            }
            .onChange(of: scrollTarget) {
                guard let target = scrollTarget else { return }
                // After the tab switch settles.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation { scroller.scrollTo(target, anchor: .top) }
                    scrollTarget = nil
                }
            }
            .onAppear {
                guard DemoData.initialTab == .academy, let target = DemoData.initialSheet,
                      ["know", "learning", "evidence"].contains(target) else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { scroller.scrollTo(target, anchor: .top) }
            }
            }
        }
        .onAppear {
            reload()
            AcademyEvent.log(.twinViewed)
            // Screenshots: `-tab academy -sheet intake` opens the interview.
            if DemoData.initialTab == .academy, DemoData.initialSheet == "intake" { showingInterview = true }
            // Screenshots: `-tab academy -sheet week` opens "Your last 7 days".
            if DemoData.initialTab == .academy, DemoData.initialSheet == "week" { showingWeek = true }
            openPendingBriefing()
            openPendingInterview()
            openPendingTwinSheet()
        }
        .task { await health.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reload(); Task { await health.load() } }
        }
        // A workout from Health imported or answered while the twin is open.
        .onChange(of: athlete.sessions.count) { reload() }
        .onChange(of: navigation.pendingBriefingID) { openPendingBriefing() }
        .onChange(of: navigation.pendingInterview) { openPendingInterview() }
        .onChange(of: navigation.pendingTwinSheet) { openPendingTwinSheet() }
        .fullScreenCover(isPresented: $showingWeek) {
            TwinWeekView(weeks: weekGroups, recovering: recovering, health: health,
                         training: athlete.sessions.map { TwinWeek.Training(date: $0.startedAt, minutes: $0.minutes) })
        }
        .fullScreenCover(item: $reading, onDismiss: reload) { target in
            BriefingReaderView(briefing: target.briefing, insight: target.insight, alreadyRead: state.read[target.briefing.id] != nil,
                               familyID: AcademyContent.familyID(forSport: sportSlug))
        }
        .fullScreenCover(isPresented: $showingInterview, onDismiss: reload) {
            IntakeInterviewView(sportSummary: meta, sportSlug: sportSlug, startAt: interviewStart)
        }
        .sheet(isPresented: $showingSupport) { SupportSheet() }
        .sheet(isPresented: $showingTrends) { TrendsSheet(athlete: athlete, sessions: athlete.sessions) }
        .sheet(isPresented: $showingTests, onDismiss: reload) {
            BenchmarksView(sportSlug: sportSlug)
        }
        .sheet(isPresented: $showingExerciseProgress) {
            ExerciseProgressListView(sessions: athlete.sessions.sorted { $0.startedAt > $1.startedAt }, catalogue: catalogue)
        }
        // "Rate your last game" from Still learning: the games' one home.
        .sheet(isPresented: $showingCompetitions, onDismiss: reload) {
            CompetitionHubView(athlete: athlete, onChanged: {
                NotificationCenter.default.post(name: WeeklyPlan.inputsChanged, object: nil)
            })
        }
        .proFeature(isPresented: $showingExerciseProgressPaywall, athlete: athlete, feature: .exerciseProgress)
        .sheet(item: $openLift) { trend in
            NavigationStack {
                ExerciseProgressDetailView(slug: trend.slug, name: liftName(trend.slug),
                                           sessions: athlete.sessions.sorted { $0.startedAt > $1.startedAt },
                                           item: catalogue.item(trend.slug))
            }
        }
        .confirmationDialog("Delete your twin?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete twin", role: .destructive) {
                Task {
                    await CloudSync.deleteTwin()
                    reload()
                }
            }
        } message: {
            Text("Your interview answers, briefings read and added performances are deleted on this phone and from your backup. Your training data stays.")
        }
        .confirmationDialog("Not right?", isPresented: correctingShown, titleVisibility: .visible, presenting: correcting) { line in
            Button("Hide this — it's not right") { hide(line) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Your twin only sees your data, so it can miss what you know. Hidden lines stay hidden; you can bring them back below.")
        }
        .sheet(isPresented: $addingPerformance, onDismiss: reload) { AddPerformanceSheet() }
        .sheet(item: $openRecord, onDismiss: reload) { record in PerformanceDetailSheet(record: record) }
    }

    private var correctingShown: Binding<Bool> {
        Binding(get: { correcting != nil }, set: { if !$0 { correcting = nil } })
    }

    /// "Not right?": the line goes, and the plan stops using it now — the
    /// week is rebuilt (the gym planner's history reads hidden lines).
    private func hide(_ line: KnowledgeLine) {
        let usedInPlan = effects.contains { $0.id == line.id }
        TwinKnowledgeStore.hide(line.id)
        NotificationCenter.default.post(name: WeeklyPlan.inputsChanged, object: nil)
        withAnimation { correctedNote = usedInPlan ? "Got it — I've hidden it and stopped using it in your plan." : "Got it — I've hidden it." }
        reload()
    }

    /// Search's Trends or Tests: open it here, in its one home.
    private func openPendingTwinSheet() {
        guard let sheet = navigation.pendingTwinSheet else { return }
        navigation.pendingTwinSheet = nil
        switch sheet {
        case "trends": showingTrends = true
        case "tests": showingTests = true
        // A "why" from the twin: the portrait, at the top of the screen.
        case "top", "know", "learning", "evidence":
            path = []
            scrollTarget = sheet
        default: break
        }
    }

    private func openPendingInterview() {
        guard navigation.pendingInterview else { return }
        navigation.pendingInterview = false
        interviewStart = nil
        showingInterview = true
    }

    /// Home's "Next step · read": open that briefing, with the insight behind it.
    private func openPendingBriefing() {
        guard let id = navigation.pendingBriefingID, let briefing = AcademyContent.briefing(id) else { return }
        navigation.pendingBriefingID = nil
        reading = ReadingTarget(briefing: briefing, insight: report?.insights.first { $0.briefing?.id == id })
    }

    private func reload() {
        state = AcademyStore.load()
        knowledge = TwinKnowledgeStore.current(athlete, state: state)
        // First-seen dates are noted whenever the twin is open, not only on its page.
        state = TwinKnowledgeStore.noteFirstSeen(knowledge.lines)
        letter = TwinKnowledgeStore.weekOneLetter(knowledge, state: state, athlete: athlete)
            ?? TwinKnowledgeStore.letter(knowledge, state: state)
        let input = TwinInputBuilder.input(athlete: athlete, state: state)
        report = TwinAnalysis.report(input)
        records = Performances.records(lifts: input.lifts, tests: input.tests, custom: state.performances)
        let now = Date.now
        if catalogue.itemsBySlug.isEmpty { catalogue = CatalogueLoader.load(from: AppConfig.packsDirectory()) }
        liftTrends = TwinTrends.lifts(input.lifts, now: now)
        // Team practice is training too: its minutes × effort count with the workouts'.
        // (Only practices whose length is known: a minute is never made up.)
        weekLoads = TwinTrends.weeklyLoad(input.loads + input.practices.compactMap { practice in
            practice.minutes.map { TwinInput.Load(date: practice.date, minutes: $0, rpe: practice.rpe ?? practice.hard * 2) }
        }, now: now)
        sleepNights = TwinTrends.sleep(input.mornings, now: now)
        // How the mind evolves reads only mornings the athlete answered.
        let answered = input.mornings.filter { !$0.assumed }
        calmWeeks = TwinTrends.weekly(answered.filter { $0.stress > 0 }.map { ($0.date, Double(6 - $0.stress)) }, now: now)
        feltWeeks = TwinTrends.weekly(input.reflections.compactMap { r in r.feeling.map { (r.date, Double($0)) } }, now: now)
        stressShift = TwinTrends.stressShift(answered, now: now)
        bodyReport = catalogue.itemsBySlug.isEmpty ? nil
            : MuscleTraining.report(MuscleTraining.loggedSets(athlete.sessions, catalogue: catalogue), now: now)
        let gym: GymHistory? = catalogue.itemsBySlug.isEmpty ? nil : GymHistoryBuilder.history(athlete, catalogue: catalogue, now: now)
        recovering = gym?.stillRecovering ?? []
        if !catalogue.itemsBySlug.isEmpty {
            weekGroups = MuscleTraining.week(MuscleTraining.loggedSets(athlete.sessions, catalogue: catalogue), now: now)
            weekSentence = weekGroups.isEmpty ? "A rested week so far. Your week's numbers are inside." : TwinHeat.sentence(weekGroups)
        }
        // One place works out what the twin changes (Home's Body tile reads the same).
        effects = TwinKnowledgeStore.planEffects(athlete, history: gym, now: now)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        readinessDays = (0..<7).reversed().compactMap { back -> (date: Date, band: ReadinessBand?)? in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            let band = athlete.checkIns.first { calendar.isDate($0.date, inSameDayAs: day) }?.readinessBand
            return (date: day, band: band)
        }
    }

    private func liftName(_ slug: String) -> String {
        catalogue.item(slug)?.name ?? displayName(forSlug: slug)
    }

    /// A lift's whole history: Pro, like Exercise progress.
    private func open(_ trend: LiftTrend) {
        if ProAccess.isPro { openLift = trend } else { showingExerciseProgressPaywall = true }
    }

    // MARK: 1. Who this twin is, and the one line that matters now

    private var topBar: some View {
        AcademyPageSwitcher(name: athlete.displayName)
    }

    private var identity: some View {
        let name = athlete.displayName ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            // Whose twin, then one quiet line: the sport, the season, how much it has seen.
            Headline([.strong(name.isEmpty ? "Your twin" : name)], size: 36)
            Text(headerFacts.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "Skiing · Pre-season · season from 1 December · 1 week of your data".
    private var headerFacts: [String] {
        var facts = [meta]
        if let seasonNote { facts.append(seasonNote) }
        if let report { facts.append(countedNoun(report.counts.weeks, "week") + " of your data") }
        return facts
    }

    /// "season from 1 December" / "until 15 March" — the season, said once, up top.
    private var seasonNote: String? {
        guard let sport = athlete.activeSport else { return nil }
        let phase = PhaseCalculator.phase(today: .now, seasonStart: sport.seasonStart, seasonEnd: sport.seasonEnd)
        let date = { (d: Date) in d.formatted(.dateTime.day().month(.wide)) }
        if phase == .inSeason { return "until \(date(sport.seasonEnd))" }
        guard sport.seasonStart > .now else { return nil }
        return "season from \(date(sport.seasonStart))"
    }

    private var heroLine: TwinHero {
        TwinPage.hero(lines: visibleLines, firstSeen: state.knowledgeFirstSeen ?? [:], effects: effects,
                      insights: report?.insights ?? [], coachRead: report?.coachRead ?? "", now: .now)
    }

    /// The one line that leads (pain that came back → a plan change this
    /// week → something learned this week → what matters most → the coach's
    /// read), what it's read from, and the one thing to do about it.
    private var hero: some View {
        let line = heroLine
        let eyebrowColor: Color = line.kind == .safety ? AppTheme.danger : line.kind == .plan ? AuraTone.training.mark : AppTheme.ink.opacity(0.8)
        return VStack(alignment: .leading, spacing: 10) {
            Text(line.eyebrow)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(eyebrowColor)
            Text(line.text)
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.3)
                .lineSpacing(3)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            heroAction(line).padding(.top, 4)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if line.kind == .safety {
                Color(rgb: 0x0C0C0F)
            } else {
                AuraBackground(.mind, focus: UnitPoint(x: 0.85, y: 0.2), radius: 230)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            if line.kind == .safety {
                RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(AppTheme.danger.opacity(0.35), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func heroAction(_ line: TwinHero) -> some View {
        if line.kind == .plan, let url = URL(string: "athleteos://workout") {
            heroButton("See your week") { _ = IntentRoute.open(url) }
        } else if let briefing = line.insight?.briefing {
            heroButton(state.read[briefing.id] != nil ? "Read it again" : "Read \u{201C}\(briefing.title)\u{201D}") {
                AcademyEvent.log(.insightOpened)
                reading = ReadingTarget(briefing: briefing, insight: line.insight)
            }
        } else if line.kind == .read, state.intakeDoneAt == nil {
            heroButton(interviewAnswered > 0 ? "Continue the interview" : "Create my twin") { openInterview() }
        } else if line.kind == .learned, let known = visibleLines.first(where: { $0.id == line.lineID }) {
            // The line lives up here this week: so does its correction (T13).
            Button("Not right?") { correcting = known }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.8))
                .frame(minHeight: 44)
                .buttonStyle(.pressable)
        }
    }

    private func heroButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).lineLimit(2).multilineTextAlignment(.leading)
                Image(systemName: "arrow.right")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 16)
            .frame(minHeight: 36)
            .background(Color.white, in: Capsule())
        }
        .buttonStyle(.pressable)
    }

    // MARK: 2. What I know about you

    private var knowSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("What I know about you")
            if let correctedNote {
                Label(correctedNote, systemImage: "checkmark")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.green)
                    .transition(.opacity)
            }
            if portrait.isEmpty {
                Text("Nothing for sure yet — I'd rather wait than guess.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            let shown = showingAllKnown ? portrait : TwinPage.trimmed(portrait, limit: 3)
            ForEach(shown, id: \.area) { area in
                VStack(alignment: .leading, spacing: 10) {
                    Text(area.area.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .padding(.top, 10)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(area.entries) { entry in portraitRow(entry) }
                }
            }
            let more = TwinPage.entryCount(portrait) - TwinPage.entryCount(shown)
            if more > 0 || (showingAllKnown && TwinPage.entryCount(portrait) > 3) {
                Button(showingAllKnown ? "Show less" : "See all \(TwinPage.entryCount(portrait))") {
                    withAnimation(.easeInOut(duration: 0.2)) { showingAllKnown.toggle() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .frame(minHeight: 44)
                .buttonStyle(.pressable)
            }
            goalsLine
            if showsLearning { learningSection.padding(.top, 14).id("learning") }
            if hiddenCount > 0 {
                Button {
                    TwinKnowledgeStore.showHidden()
                    NotificationCenter.default.post(name: WeeklyPlan.inputsChanged, object: nil)
                    correctedNote = nil
                    reload()
                } label: {
                    Text("Show \(hiddenCount) hidden \(hiddenCount == 1 ? "line" : "lines") again")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func portraitRow(_ entry: TwinPageEntry) -> some View {
        let effect = effects.first { $0.id == entry.effectKey }?.text
        switch entry {
        case .line(let line):
            // A line already says what the plan does (legs: "Your plan gives
            // them that extra day"); the note adds only this week's day.
            let thisWeek = effects.first { $0.id == line.id }?.now ?? false
            KnowledgeRow(line: line, effect: thisWeek ? effect : nil) { correcting = line }
        case .insight(let insight), .strength(let insight):
            TwinInsightRow(insight: insight, effect: effect,
                           read: insight.briefing.map { state.read[$0.id] != nil } ?? false) { briefing in
                reading = ReadingTarget(briefing: briefing, insight: insight)
            }
        }
    }

    /// The athlete's own goals, as one line (the season is in the header;
    /// the twin's own steers sit on their lines).
    @ViewBuilder
    private var goalsLine: some View {
        let goals = Struggles.selected.prefix(3).map(\.title)
        if !goals.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("Your goals")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                Text("Workouts lean towards " + goals.joined(separator: ", ").lowercased() + ".")
                    .font(.body)
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        }
    }

    // MARK: 3. Still learning

    private var interviewQuestions: [String] { AcademyContent.intake(forSport: sportSlug).map(\.id) }
    private var interviewAnswered: Int {
        state.intakeDraft.map { AcademyStore.answeredCount($0.answers, of: interviewQuestions) } ?? 0
    }

    /// Nothing to show once the interview is done and everything is known.
    private var showsLearning: Bool { state.intakeDoneAt == nil || !knowledge.learning.isEmpty }

    private var learningSection: some View {
        let interviewOpen = state.intakeDoneAt == nil
        let items = TwinPage.stillLearning(knowledge.learning, limit: interviewOpen ? 2 : 3)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Learning next")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .accessibilityAddTraits(.isHeader)
            if interviewOpen {
                let total = interviewQuestions.count
                LearningRow(question: "How you train, compete and think",
                            progress: interviewAnswered > 0
                                ? "\(interviewAnswered) of \(total) questions answered · your answers are kept"
                                : "\(countedNoun(total, "question")), about five minutes. Only you see the answers.",
                            fraction: interviewAnswered > 0 ? Double(interviewAnswered) / Double(max(total, 1)) : nil,
                            actionTitle: interviewAnswered > 0 ? "Continue the interview" : "Answer the questions") { openInterview() }
            }
            ForEach(items) { item in
                let action = learningAction(item)
                LearningRow(question: item.question, progress: item.progress,
                            fraction: item.checking ? nil : Double(min(item.have, item.need)) / Double(max(item.need, 1)),
                            actionTitle: action?.title) { action?.run() }
            }
        }
    }

    /// The one thing that adds what an item is missing, when there is one
    /// to do right now (nothing for what only time or a watch can add).
    private func learningAction(_ item: LearningItem) -> (title: String, run: () -> Void)? {
        switch item.id {
        case "habits.sleep", "training.sleep":
            let checkedIn = athlete.checkIns.contains { Calendar.current.isDateInToday($0.date) }
            guard !checkedIn, let url = URL(string: "athleteos://checkin") else { return nil }
            return ("Check in now", { _ = IntentRoute.open(url) })
        case "games.best":
            // Only the newest past game: the hub offers a result for that one.
            guard let last = athlete.competitions.filter({ $0.date < .now }).max(by: { $0.date < $1.date }),
                  CompetitionStore.rating(for: last.id) == nil else { return nil }
            return ("Rate your last \(family.event)", { showingCompetitions = true })
        default:
            return nil
        }
    }

    // MARK: 4. The evidence

    private var evidence: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("The evidence")
            VStack(spacing: 0) {
                Button { path.append(.performing) } label: {
                    ListRow(systemImage: "chart.line.uptrend.xyaxis", color: AuraTone.training.mark, title: "How are you performing?",
                            detail: records.isEmpty ? "Lifts, tests and performances" : "\(countedNoun(records.count, "performance")), lifts and tests")
                }
                .buttonStyle(.pressable)
                Button { path.append(.body) } label: {
                    ListRow(systemImage: "figure.stand", color: AuraTone.body.mark, title: "How are you changing?",
                            detail: health.phase == .ready ? "Your body, training load, sleep and Health" : "Your body, training load and sleep")
                }
                .buttonStyle(.pressable)
                Button { path.append(.mind) } label: {
                    ListRow(systemImage: "brain.head.profile", color: AuraTone.mind.mark, title: "How is your mind evolving?",
                            detail: "Calm, and how training felt, week by week")
                }
                .buttonStyle(.pressable)
            }
        }
    }

    @ViewBuilder
    private func destination(_ route: TwinRoute) -> some View {
        switch route {
        case .performing: evidencePage("How are you performing?") { performing }
        case .body: evidencePage("How are you changing?") { changing }
        case .mind: evidencePage("How is your mind evolving?") { mind }
        case .allHealth: MoreHealthInsightsView(model: health, age: athleteAge, readinessDays: readinessDays)
        }
    }

    private func evidencePage<Content: View>(_ title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(title)
                        .font(.system(size: 30, weight: .bold))
                        .tracking(-0.6)
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    content()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .appScreen()
            .navigationTitle("")
            .navigationBarTitleDisplayModeInline()
            .toolbar(.visible, for: .navigationBar)
            .onAppear {
                // Screenshots: `-sheet health2` shows the health tiles.
                guard DemoData.initialTab == .academy, DemoData.initialSheet == "health2" else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { scroller.scrollTo("health-tiles", anchor: .top) }
            }
        }
    }

    private var performing: some View {
        VStack(alignment: .leading, spacing: 14) {
            LiftTrendWidget(trends: liftTrends, name: liftName) { open($0) }
            performances.padding(.top, 20)
        }
    }

    private var changing: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Owner, 2026-11-19: Apple Health's data ("More insights into your health"; any watch, band or app).
            if health.phase == .ready || health.phase == .empty {
                HealthInsightsSection(model: health, age: athleteAge, readinessDays: readinessDays) { path.append(.allHealth) }
                    .padding(.bottom, 30)
            }
            BodyStatusWidget(report: bodyReport, recovering: recovering)
            LoadWidget(weeks: weekLoads)
            // With sleep from Health, sleep and the week's mornings live in the health insights.
            if !health.widgets.contains(.sleep) {
                SleepReadinessWidget(nights: sleepNights, days: readinessDays,
                                     fromWatch: UserDefaults.standard.bool(forKey: "sleep.fromHealth"))
            }
            Button { showingTrends = true } label: {
                ListRow(systemImage: "chart.xyaxis.line", color: AuraTone.body.mark, title: "Trends", detail: "The last 30 days, sleep and load")
            }
            .buttonStyle(.pressable)
        }
    }

    private var mind: some View {
        VStack(alignment: .leading, spacing: 14) {
            MindWidget(calm: calmWeeks, felt: feltWeeks, shift: stressShift)
        }
    }

    // MARK: Performances

    private var performances: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Performances") {
                    Button("Add") { addingPerformance = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(records) { record in
                    Button { openRecord = record } label: { PerformanceTile(record: record) }
                        .buttonStyle(.pressable)
                }
                Button { addingPerformance = true } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus").font(.headline)
                        Text(records.isEmpty ? "Add your first performance" : "Add a performance")
                            .font(.footnote.weight(.medium))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 124)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    }
                }
                .buttonStyle(.pressable)
            }
            if records.isEmpty {
                Text("Your best lifts and tests appear here by themselves as you log them. Add anything else — a bench press from your school gym, a 5 km run, a beep test.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Where the numbers come from: the tests, and every logged exercise.
            VStack(spacing: 0) {
                Button { showingTests = true } label: {
                    ListRow(systemImage: "stopwatch", color: AuraTone.training.mark, title: "Tests", detail: "Sprint, jump and more · every 6–8 weeks")
                }
                .buttonStyle(.pressable)
                Button {
                    if ProAccess.isPro {
                        if catalogue.itemsBySlug.isEmpty { catalogue = CatalogueLoader.load(from: AppConfig.packsDirectory()) }
                        showingExerciseProgress = true
                    } else {
                        showingExerciseProgressPaywall = true
                    }
                } label: {
                    ListRow(systemImage: "chart.line.uptrend.xyaxis", color: AuraTone.training.mark, title: "Exercise progress", detail: "Each lift over time")
                }
                .buttonStyle(.pressable)
            }
            .padding(.top, 6)
        }
    }

    private func openInterview(at questionID: String? = nil) {
        interviewStart = questionID
        showingInterview = true
    }

    /// One quiet footer: help a tap away, how the twin reads you, whose it
    /// is, and the way out.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { showingSupport = true } label: {
                Label("Need to talk to someone? Free, confidential help", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AuraTone.mind.mark)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.pressable)
            Text("Worked out on your phone, from your own data, compared only with you. It says what goes together, never what causes what. Your twin is yours alone — never shown to coaches, parents or teammates, and backed up encrypted to your own account.")
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            if state.intakeDoneAt != nil || !state.read.isEmpty || !state.performances.isEmpty {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Text("Delete twin")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.danger)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.pressable)
            }
        }
    }
}

/// The evidence behind an insight: the athlete's own days, the ones that
/// matter highlighted; or two lines to compare.
struct TwinEvidenceChart: View {
    let evidence: TwinEvidence
    /// The insight's topic colour: the days that matter in full, the rest faint.
    var tint: Color = AuraTone.mind.mark

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                if evidence.style == .bars {
                    ForEach(Array(evidence.points.enumerated()), id: \.offset) { _, point in
                        BarMark(x: .value("Day", point.date, unit: .day), y: .value("Value", point.value), width: .ratio(0.7))
                            .foregroundStyle(point.marked ? tint : tint.opacity(0.32))
                            .cornerRadius(4)
                    }
                } else {
                    ForEach(Array(evidence.points.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Day", point.date), y: .value("Change", point.value), series: .value("Series", "main"))
                            .foregroundStyle(tint)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(Array((evidence.comparison ?? []).enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Day", point.date), y: .value("Change", point.value), series: .value("Series", "comparison"))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            Text(evidence.caption)
                .font(.footnote)
                .foregroundStyle(AppTheme.ink.opacity(0.5))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(evidence.caption)
    }
}

/// "Need to talk to someone?" — the helpline for the phone's country
/// (SupportResources), a trusted adult, and the emergency number.
struct SupportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    private let resource = SupportResources.resource(region: Locale.current.region?.identifier)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("You don't have to sort it out alone. Talking helps — to a parent, a coach, a teacher, or someone at a helpline.")
                        .font(.body)
                        .foregroundStyle(AppTheme.secondaryText)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(resource.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        if let display = resource.display {
                            Text(display)
                                .font(.system(size: 40, weight: .bold).monospacedDigit())
                                .foregroundStyle(AppTheme.ink)
                        }
                        Text(resource.detail)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                        if let phone = resource.phone, let url = URL(string: "tel:\(phone)") {
                            Button { openURL(url) } label: { HeroCTALabel("Call \(resource.display ?? phone)") }
                                .buttonStyle(.primary)
                                .padding(.top, 6)
                        }
                        if let website = resource.website, let url = URL(string: website) {
                            Button("Website") { openURL(url) }
                                .buttonStyle(.secondary)
                        }
                    }
                    .cardStyle(padding: 18)
                    Text("In an emergency, or if you think about hurting yourself, call \(resource.emergency) now.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.danger)
                    Text("Briefings about the mind teach mental skills for sport. They are not therapy.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedText)
                }
                .padding(24)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Need to talk?")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
