import Charts
import SwiftUI
#if os(iOS)
import UIKit
#endif

// The Academy tab (docs/ACADEMY-PLAN.md, v3): the Digital Twin as an analysis
// of the athlete. The coach's read, the insights found in their own data with
// the briefing the coach assigned for each, what's working, their
// performances, who they are (the interview), and the briefing library.

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
    @State private var showingMentalSkills = false
    @State private var showingTests = false
    @State private var showingExerciseProgress = false
    @State private var showingExerciseProgressPaywall = false
    @State private var catalogue = Catalogue()
    @ObservedObject private var navigation = AcademyNavigation.shared
    @State private var addingPerformance = false
    @State private var openRecord: PerformanceRecord?
    /// Insights opened to show their numbers.
    @State private var expanded: Set<String> = []

    struct ReadingTarget: Identifiable {
        let briefing: Briefing
        let insight: TwinInsight?
        var id: String { briefing.id }
    }

    private var sportSlug: String? { athlete.activeSport?.sportSlug }
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                    identity.padding(.top, 26)
                    if state.intakeDoneAt == nil { interviewCard.padding(.top, 28) }
                    if let report {
                        coachRead(report).padding(.top, 28)
                        insights(report).padding(.top, 48)
                        training(report).padding(.top, 48)
                        if !report.strengths.isEmpty { working(report).padding(.top, 40) }
                    }
                    performances.padding(.top, 48)
                    if state.intakeDoneAt != nil { whoYouAre.padding(.top, 48) }
                    library.padding(.top, 48)
                    lessonsRow.padding(.top, 8)
                    mentalSkillsRow.padding(.top, 4)
                    supportRow.padding(.top, 36)
                    if state.intakeDoneAt != nil || !state.read.isEmpty || !state.performances.isEmpty {
                        privacyRow.padding(.top, 28)
                    }
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .appScreen(.hero, sportSlug: sportSlug)
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            reload()
            AcademyEvent.log(.twinViewed)
            // Screenshots: `-tab academy -sheet intake` opens the interview.
            if DemoData.initialTab == .academy, DemoData.initialSheet == "intake" { showingInterview = true }
            openPendingBriefing()
            openPendingInterview()
        }
        .onChange(of: navigation.pendingBriefingID) { openPendingBriefing() }
        .onChange(of: navigation.pendingInterview) { openPendingInterview() }
        .fullScreenCover(item: $reading, onDismiss: reload) { target in
            BriefingReaderView(briefing: target.briefing, insight: target.insight, alreadyRead: state.read[target.briefing.id] != nil,
                               familyID: AcademyContent.familyID(forSport: sportSlug))
        }
        .fullScreenCover(isPresented: $showingInterview, onDismiss: reload) {
            IntakeInterviewView(sportSummary: meta, sportSlug: sportSlug, startAt: interviewStart)
        }
        .sheet(isPresented: $showingSupport) { SupportSheet() }
        .sheet(isPresented: $showingTests, onDismiss: reload) {
            BenchmarksView(sportSlug: sportSlug)
        }
        .sheet(isPresented: $showingExerciseProgress) {
            ExerciseProgressListView(sessions: athlete.sessions.sorted { $0.startedAt > $1.startedAt }, catalogue: catalogue)
        }
        .proFeature(isPresented: $showingExerciseProgressPaywall, athlete: athlete, feature: .exerciseProgress)
        .sheet(isPresented: $showingMentalSkills) {
            MentalSkillsView()
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
        .sheet(isPresented: $addingPerformance, onDismiss: reload) { AddPerformanceSheet() }
        .sheet(item: $openRecord, onDismiss: reload) { record in PerformanceDetailSheet(record: record) }
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
        let input = TwinInputBuilder.input(athlete: athlete, state: state)
        report = TwinAnalysis.report(input)
        records = Performances.records(lifts: input.lifts, tests: input.tests, custom: state.performances)
    }

    // MARK: Who this twin is

    private var topBar: some View {
        AcademyPageSwitcher(name: athlete.displayName)
    }

    private var identityLine: [Headline.Part] {
        let name = athlete.displayName ?? ""
        let opener: Headline.Part = name.isEmpty ? .strong("Your twin.") : .strong(name + ".")
        guard let counts = report?.counts else {
            if name.isEmpty { return [opener] }
            return [opener, .soft(" Your twin.")]
        }
        return [opener, .soft(" Read from "), .strong(countedNoun(counts.weeks, "week")), .soft(" of your own data.")]
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 10) {
            // V8: one sentence says whose twin this is and how much it has seen.
            Headline(identityLine, size: 36)
            Text(meta)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
            if let counts = report?.counts {
                // V8: what the twin knows, as four coloured tiles — one colour per kind of data.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    MetricTile(.mind, label: "Your data", value: "\(counts.weeks)", unit: "wk")
                    MetricTile(.body, label: "Check-ins", value: "\(counts.checkIns)")
                    MetricTile(.training, label: "Sessions", value: "\(counts.sessions)")
                    MetricTile(.game, label: family.events.prefix(1).uppercased() + family.events.dropFirst(), value: "\(counts.games)")
                }
                .padding(.top, 10)
            }
        }
    }

    private var interviewCard: some View {
        let questionIDs = AcademyContent.intake(forSport: sportSlug).map(\.id)
        let answered = state.intakeDraft.map { AcademyStore.answeredCount($0.answers, of: questionIDs) } ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            Text(answered > 0 ? "Finish creating your twin" : "Let your twin get to know you")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Text(answered > 0
                 ? "\(answered) of \(questionIDs.count) answered. Pick up where you left off — your answers are kept."
                 : "\(countedNoun(questionIDs.count, "question")) about how you train, compete and think. About five minutes. Only you can see the answers.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if answered > 0 {
                ProgressView(value: Double(answered), total: Double(max(questionIDs.count, 1)))
                    .tint(.white)
                    .padding(.top, 4)
            }
            Button { openInterview() } label: { HeroCTALabel(answered > 0 ? "Continue the interview" : "Create my twin") }
                .buttonStyle(.primary)
                .padding(.top, 8)
        }
        .padding(20)
        .background(AuraBackground(.mind, focus: UnitPoint(x: 0.8, y: 0.3), radius: 220))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private func coachRead(_ report: TwinReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AthleteOS Coach's read")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.8))
            Text(report.coachRead)
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.3)
                .lineSpacing(3)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("From \(report.counts.checkIns) check-ins, \(report.counts.sessions) sessions and \(report.counts.games) \(family.events)\(state.intakeDoneAt == nil ? "" : ", and your interview")")
                .font(.footnote)
                .foregroundStyle(AppTheme.ink.opacity(0.65))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuraBackground(.mind, focus: UnitPoint(x: 0.85, y: 0.2), radius: 230))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    // MARK: Insights

    private func insights(_ report: TwinReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel("Insights") { Text("\(report.insights.count) found") }
            if report.insights.isEmpty {
                Text(report.counts.checkIns + report.counts.sessions < 5
                     ? "Nothing yet — a couple of weeks of check-ins, sessions and \(family.events) and your twin starts to see patterns."
                     : "Nothing in your data is holding you back right now.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.top, 14)
            }
            ForEach(Array(report.insights.enumerated()), id: \.element.id) { index, insight in
                insightRow(insight, last: index == report.insights.count - 1)
            }
        }
    }

    /// V8: each insight is its own card, lit faintly in its topic's colour:
    /// the topic, the sentence big, the athlete's own chart in that colour,
    /// the numbers on a tap, and the briefing the coach assigned for it.
    private func insightRow(_ insight: TwinInsight, last: Bool) -> some View {
        let tint = insight.kind.topic?.color ?? AuraTone.mind.mark
        let open = expanded.contains(insight.id)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(insight.kind.topic?.title ?? "Insight")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
                Text(insight.strength == .strong ? "Strong pattern" : "Emerging")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.ink.opacity(0.55))
            }
            Text(insight.headline)
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let trend = insight.trend, trend != .steady {
                Text(trend.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(trendColor(trend))
            }
            if let evidence = insight.evidence {
                TwinEvidenceChart(evidence: evidence, tint: tint).frame(height: 110)
            }
            Button { withAnimation(.easeInOut(duration: 0.25)) { if open { _ = expanded.remove(insight.id) } else { _ = expanded.insert(insight.id) } } } label: {
                HStack(spacing: 6) {
                    Text(open ? "Hide the numbers" : "The numbers")
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.8))
                .frame(minHeight: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            if open {
                VStack(alignment: .leading, spacing: 6) {
                    Text(insight.detail)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("From \(insight.basis)")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.ink.opacity(0.5))
                }
                .transition(.opacity)
            }
            if let briefing = insight.briefing {
                let read = state.read[briefing.id] != nil
                Button {
                    AcademyEvent.log(.insightOpened)
                    reading = ReadingTarget(briefing: briefing, insight: insight)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(read ? "Read again: \(briefing.title)" : "Read \u{201C}\(briefing.title)\u{201D}")
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)
                                .multilineTextAlignment(.leading)
                            Text(read ? "You read it · the coach's pick" : "The coach's pick · \(briefing.minutes) min")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.ink.opacity(0.65))
                        }
                        Spacer(minLength: 8)
                        Image(systemName: read ? "checkmark" : "arrow.right")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                    }
                    .padding(16)
                    .background(tint.opacity(0.22), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(colors: AuraTone.calm.base, startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [tint.opacity(0.26), tint.opacity(0.06), .clear], center: UnitPoint(x: 0.05, y: 0), startRadius: 0, endRadius: 260)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1) }
        .padding(.top, 12)
    }

    private func trendColor(_ trend: TwinTrend) -> Color {
        switch trend {
        case .improving: AppTheme.green
        case .worsening: AppTheme.orange
        case .new, .steady: AuraTone.mind.mark
        }
    }

    /// How the twin steers training right now: the season, the goals, and
    /// what its insights change in the workouts (TwinSteer → SessionPlanner).
    private func trainingLines(_ report: TwinReport) -> [(String, String)] {
        var lines: [(String, String)] = []
        if let sport = athlete.activeSport {
            let phase = PhaseCalculator.phase(today: .now, seasonStart: sport.seasonStart, seasonEnd: sport.seasonEnd)
            let date = { (d: Date) in d.formatted(.dateTime.day().month(.abbreviated)) }
            var next = ""
            if phase != .inSeason, sport.seasonStart > .now {
                if let pre = PreSeasonStore.start, pre > .now, pre < sport.seasonStart, phase != .preSeason {
                    next = "Pre-season from \(date(pre)), the season from \(date(sport.seasonStart))."
                } else {
                    next = "The season starts \(date(sport.seasonStart))."
                }
            } else if phase == .inSeason {
                next = "Until \(date(sport.seasonEnd))."
            }
            lines.append((AthleteStats.phaseLabel(phase), (next + " " + phase.focus).trimmingCharacters(in: .whitespaces)))
        }
        let goals = Struggles.selected.prefix(3).map(\.title)
        if !goals.isEmpty {
            lines.append(("Your goals", "Workouts lean towards " + goals.joined(separator: ", ").lowercased() + "."))
        }
        for steer in TwinSteer.from(report.insights.map(\.kind)).sorted(by: { $0.rawValue < $1.rawValue }) {
            switch steer {
            case .slowGameRecovery:
                lines.append(("After games", "You still feel a \(family.event) two days later, so that day stays light on the legs too."))
            case .loadSpike:
                lines.append(("This week", "Your load jumped, so sessions are a little shorter and skip hard conditioning until it settles."))
            case .strengthNotSpeed:
                lines.append(("Strength into speed", "Your strength is rising faster than your sprint and jump, so power and acceleration come first."))
            }
        }
        return lines
    }

    private func training(_ report: TwinReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Your training") { EmptyView() }
            Text("What your twin changes in your workouts. Tell AthleteOS when something changes.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(trainingLines(report), id: \.0) { line in
                VStack(alignment: .leading, spacing: 3) {
                    Text(line.0)
                        .font(.headline)
                        .foregroundStyle(AuraTone.training.mark)
                    Text(line.1)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func working(_ report: TwinReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("What's working") { EmptyView() }
            ForEach(report.strengths) { strength in
                HStack(alignment: .top, spacing: 12) {
                    Circle().fill(AppTheme.green).frame(width: 7, height: 7).padding(.top, 7)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(strength.headline)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(strength.detail)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
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

    // MARK: Who you are

    private var whoYouAre: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Who you are") {
                Button("Edit") { openInterview() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
            }
            ForEach(AcademyContent.intake(forSport: sportSlug)) { question in
                // Every question, answered or not: tap one to change just that answer.
                Button { openInterview(at: question.id) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(family.fill(question.label))
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink)
                        Spacer(minLength: 12)
                        Text(summary(question) ?? "Add")
                            .font(.subheadline)
                            .foregroundStyle(summary(question) == nil ? AuraTone.mind.mark : AppTheme.secondaryText)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(3)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.mutedText)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityHint("Change this answer")
            }
        }
    }

    private func openInterview(at questionID: String? = nil) {
        interviewStart = questionID
        showingInterview = true
    }

    private func summary(_ question: IntakeQuestion) -> String? {
        guard let answer = state.intake[question.id] else { return nil }
        if question.freeText { return answer }
        return question.options.first { $0.id == answer }.map { family.fill($0.summary) }
    }

    // MARK: Library and support

    private var library: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel("Briefings") { Text("\(AcademyContent.briefings.count) long reads") }
            let assigned = Set(report?.assigned.map(\.id) ?? [])
            let ordered = AcademyContent.briefings.sorted { (assigned.contains($0.id) ? 0 : 1) < (assigned.contains($1.id) ? 0 : 1) }
            ForEach(ordered) { briefing in
                Button {
                    reading = ReadingTarget(briefing: briefing, insight: report?.insights.first { $0.kind == briefing.insight })
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        RoundedRectangle(cornerRadius: 2).fill(briefing.topic.color).frame(width: 3, height: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(briefing.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                                .multilineTextAlignment(.leading)
                            Text("\(briefing.topic.title) · \(briefing.minutes) min\(assigned.contains(briefing.id) ? " · assigned to you" : "")")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer(minLength: 8)
                        if state.read[briefing.id] != nil {
                            Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(AppTheme.green)
                        }
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
            }
        }
    }

    /// Campus's short lessons (no longer a tab): one quiet row.
    private var lessonsRow: some View {
        Button { AcademyNavigation.shared.showingLessons = true } label: {
            ListRow(systemImage: "book.closed", color: AuraTone.mind.mark, title: "Short lessons",
                    detail: "100 quick lessons on training, sleep and mind")
        }
        .buttonStyle(.pressable)
    }

    /// Mental skills (practice options) and "Talking it through" drafts.
    /// Reflection lives on Home; breathing and visualization in game prep.
    private var mentalSkillsRow: some View {
        Button { showingMentalSkills = true } label: {
            ListRow(systemImage: "brain.head.profile", color: AuraTone.mind.mark, title: "Mental skills",
                    detail: "Confidence, focus, talking it through")
        }
        .buttonStyle(.pressable)
    }

    private var supportRow: some View {
        Button { showingSupport = true } label: {
            ListRow(systemImage: "bubble.left.and.bubble.right.fill", color: AppTheme.purple, title: "Need to talk to someone?",
                    detail: "Free, confidential help — any time")
        }
        .buttonStyle(.pressable)
    }

    /// Whose this is, and the way out.
    private var privacyRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your twin is yours alone — never shown to coaches, parents or teammates. Backed up encrypted to your own account.")
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            Button(role: .destructive) { confirmingDelete = true } label: {
                Text("Delete twin")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.danger)
            }
            .buttonStyle(.pressable)
        }
    }

    private func sectionTitle(_ title: String, _ subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(AppTheme.ink)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
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
