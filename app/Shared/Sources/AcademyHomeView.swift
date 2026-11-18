import Charts
import SwiftUI

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
        case .sleepBeforeGames, .recoveryAfterGames, .sleepBase: .recovery
        case .strengthNotSpeed, .strengthRising, .consistentTraining: .strength
        case .mistakeReplay, .pressureConfidence: .mind
        case .gameDayFuel: .fuel
        }
    }
}

/// Reading serif (New York on iOS) for the coach's voice and the briefings.
extension Font {
    static func reading(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
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
    @State private var addingPerformance = false
    @State private var openRecord: PerformanceRecord?

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
                        if !report.strengths.isEmpty { working(report).padding(.top, 40) }
                    }
                    performances.padding(.top, 48)
                    if state.intakeDoneAt != nil { whoYouAre.padding(.top, 48) }
                    library.padding(.top, 48)
                    supportRow.padding(.top, 36).padding(.bottom, 24)
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
        }
        .fullScreenCover(item: $reading, onDismiss: reload) { target in
            BriefingReaderView(briefing: target.briefing, insight: target.insight, alreadyRead: state.read[target.briefing.id] != nil,
                               familyID: AcademyContent.familyID(forSport: sportSlug))
        }
        .fullScreenCover(isPresented: $showingInterview, onDismiss: reload) {
            IntakeInterviewView(sportSummary: meta, sportSlug: sportSlug, startAt: interviewStart)
        }
        .sheet(isPresented: $showingSupport) { SupportSheet() }
        .sheet(isPresented: $addingPerformance, onDismiss: reload) { AddPerformanceSheet() }
        .sheet(item: $openRecord, onDismiss: reload) { record in PerformanceDetailSheet(record: record) }
    }

    private func reload() {
        state = AcademyStore.load()
        let input = TwinInputBuilder.input(athlete: athlete, state: state)
        report = TwinAnalysis.report(input)
        records = Performances.records(lifts: input.lifts, tests: input.tests, custom: state.performances)
    }

    // MARK: Who this twin is

    private var topBar: some View {
        HStack {
            ProfileButton(name: athlete.displayName)
            Spacer()
            Text("Your twin")
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppTheme.mutedText)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.top, 8)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(athlete.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? "Your twin")
                .font(.system(size: 40, weight: .semibold))
                .tracking(-1.2)
                .foregroundStyle(AppTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            Text(meta)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
            if let counts = report?.counts {
                HStack(alignment: .top, spacing: 20) {
                    count("\(counts.weeks) wk", "of data")
                    count("\(counts.checkIns)", "check-ins")
                    count("\(counts.sessions)", "sessions")
                    count("\(counts.games)", family.events)
                }
                .padding(.top, 8)
            }
        }
    }

    private func count(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 20, weight: .semibold).monospacedDigit()).foregroundStyle(AppTheme.ink)
            Text(label).font(.caption).foregroundStyle(AppTheme.mutedText)
        }
        .accessibilityElement(children: .combine)
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
                    .tint(AppTheme.brightRed)
                    .padding(.top, 4)
            }
            Button { openInterview() } label: { HeroCTALabel(answered > 0 ? "Continue the interview" : "Create my twin") }
                .buttonStyle(.primary)
                .padding(.top, 8)
        }
        .padding(20)
        .glassSurface(cornerRadius: 22, tint: AppTheme.brand)
    }

    private func coachRead(_ report: TwinReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Coach's read")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.brightRed)
            Text(report.coachRead)
                .font(.reading(19))
                .lineSpacing(5)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("From \(report.counts.checkIns) check-ins, \(report.counts.sessions) sessions and \(report.counts.games) \(family.events)\(state.intakeDoneAt == nil ? "" : ", and your interview")")
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedText)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [AppTheme.brand.opacity(0.14), AppTheme.brand.opacity(0.03)], startPoint: .top, endPoint: .bottom))
        }
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(AppTheme.brightRed.opacity(0.22), lineWidth: 1) }
    }

    // MARK: Insights

    private func insights(_ report: TwinReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Insights", "What your data says, and what to do about it.")
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

    private func insightRow(_ insight: TwinInsight, last: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(insight.kind.topic?.title ?? "Insight")
                    .foregroundStyle(insight.kind.topic?.color ?? AppTheme.brightRed)
                Spacer()
                Text("\(insight.strength == .strong ? "Strong pattern" : "Emerging") · \(insight.basis)")
                    .foregroundStyle(AppTheme.mutedText)
            }
            .font(.footnote.weight(.medium))
            Text(insight.headline)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(insight.detail)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let evidence = insight.evidence {
                TwinEvidenceChart(evidence: evidence).frame(height: 84)
            }
            if let briefing = insight.briefing {
                Button {
                    AcademyEvent.log(.insightOpened)
                    reading = ReadingTarget(briefing: briefing, insight: insight)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Coach assigned: \(briefing.title)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                                .multilineTextAlignment(.leading)
                            Text(state.read[briefing.id] == nil ? "Briefing · \(briefing.minutes) min read" : "Read · open again")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: state.read[briefing.id] == nil ? "arrow.right" : "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.brightRed)
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 20)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
        }
    }

    private func working(_ report: TwinReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("What's working", nil)
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
                sectionTitle("Performances", nil)
                Spacer()
                Button("Add") { addingPerformance = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.brightRed)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(records) { record in
                    Button { openRecord = record } label: { PerformanceTile(record: record) }
                        .buttonStyle(.plain)
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
                .buttonStyle(.plain)
            }
            if records.isEmpty {
                Text("Your best lifts and tests appear here by themselves as you log them. Add anything else — a bench press from your school gym, a 5 km run, a beep test.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Who you are

    private var whoYouAre: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("Who you are as an athlete", "From your interview.")
                Spacer()
                Button("Edit") { openInterview() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.brightRed)
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
                            .foregroundStyle(summary(question) == nil ? AppTheme.brightRed : AppTheme.secondaryText)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(3)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.mutedText)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
                }
                .buttonStyle(.plain)
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
            sectionTitle("Briefings", "Long reads from your coach. The ones your twin needs come first.")
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
                .buttonStyle(.plain)
            }
        }
    }

    private var supportRow: some View {
        Button { showingSupport = true } label: {
            ListRow(systemImage: "bubble.left.and.bubble.right.fill", color: AppTheme.purple, title: "Need to talk to someone?",
                    detail: "Free, confidential help — any time")
        }
        .buttonStyle(.plain)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                if evidence.style == .bars {
                    ForEach(Array(evidence.points.enumerated()), id: \.offset) { _, point in
                        BarMark(x: .value("Day", point.date, unit: .day), y: .value("Value", point.value))
                            .foregroundStyle(point.marked ? AppTheme.brightRed : Color.white.opacity(0.16))
                            .cornerRadius(2)
                    }
                } else {
                    ForEach(Array(evidence.points.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Day", point.date), y: .value("Change", point.value), series: .value("Series", "main"))
                            .foregroundStyle(AppTheme.brightRed)
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
                .font(.caption2)
                .foregroundStyle(AppTheme.mutedText)
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
