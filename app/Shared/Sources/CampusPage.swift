import SwiftUI

// The Academy's Campus page (owner, 2026-11-19): Campus asks questions that
// form a picture of the athlete (the interview, one question at a time),
// shows what it knows, and holds the learning — the short lessons, the long
// reads (briefings), mental skills and the sport guide.

struct CampusPage: View {
    let athlete: Athlete

    var body: some View {
        CampusView(
            athlete: athlete,
            embedded: true,
            prelude: AnyView(VStack(alignment: .leading, spacing: 28) {
                AcademyPageSwitcher(name: athlete.displayName)
                CampusAsksSection(athlete: athlete)
            }),
            extra: AnyView(CampusReadingSection(athlete: athlete))
        )
    }
}

/// "Campus asks": the next unanswered interview question, right on the page.
/// Answer it, skip it, or answer them all at once. Answers live where the
/// interview keeps them (AcademyStore) — only the athlete sees them.
struct CampusAsksSection: View {
    let athlete: Athlete

    @State private var state = AcademyState()
    @State private var skipped: Set<String> = []
    @State private var text = ""
    @State private var showingInterview = false
    @State private var interviewStart: String?
    @State private var showingAll = false

    private var sportSlug: String? { athlete.activeSport?.sportSlug }
    private var family: SportFamily { AcademyContent.family(forSport: sportSlug) }
    private var questions: [IntakeQuestion] { AcademyContent.intake(forSport: sportSlug) }

    /// Every answer so far: the finished interview's, or the draft's.
    private var answers: [String: String] {
        state.intake.merging(state.intakeDraft?.answers ?? [:]) { _, draft in draft }
    }

    private var next: IntakeQuestion? {
        questions.first { answers[$0.id] == nil && !skipped.contains($0.id) }
    }

    private var answeredCount: Int { AcademyStore.answeredCount(answers, of: questions.map(\.id)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Campus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .accessibilityAddTraits(.isHeader)
                Headline([.strong("Learn what makes you better."), .soft(" Campus gets to know you as you go.")], size: 30)
            }
            .padding(.top, 8)
            if let next {
                askCard(next)
            } else if answeredCount < questions.count {
                Button("Show the skipped questions") { withAnimation(.easeInOut(duration: 0.2)) { skipped = [] } }
                    .buttonStyle(.secondary)
            }
            if answeredCount > 0 { knows }
        }
        .onAppear(perform: load)
        .fullScreenCover(isPresented: $showingInterview, onDismiss: load) {
            IntakeInterviewView(sportSummary: AthleteStats.sportName(athlete), sportSlug: sportSlug, startAt: interviewStart)
        }
    }

    private func load() {
        state = AcademyStore.load()
    }

    // MARK: Asking

    private func askCard(_ question: IntakeQuestion) -> some View {
        AuraCard(.mind, focus: UnitPoint(x: 0.85, y: 0.15), radius: 220, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Campus asks · \(answeredCount + 1) of \(questions.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.ink.opacity(0.8))
                    Spacer()
                    Button("Skip") {
                        withAnimation(.easeInOut(duration: 0.2)) { _ = skipped.insert(question.id) }
                        text = ""
                    }
                    .buttonStyle(.quiet)
                }
                Text(family.fill(question.prompt))
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if question.freeText {
                    TextField(question.placeholder ?? "Your answer", text: $text, axis: .vertical)
                        .lineLimit(2...5)
                        .font(.body)
                        .foregroundStyle(AppTheme.ink)
                        .padding(14)
                        .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Button("Save") { answer(question, String(text.prefix(AcademyStore.freeTextLimit))) }
                        .buttonStyle(.primary)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    VStack(spacing: 8) {
                        ForEach(question.options) { option in
                            Button { answer(question, option.id) } label: {
                                Text(family.fill(option.text))
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(AppTheme.ink)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }
                Text("Only you see your answers. They shape your twin and what Campus suggests.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.ink.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(question.id)
        .transition(.opacity)
    }

    private func answer(_ question: IntakeQuestion, _ value: String) {
        let before = AcademyStore.load()
        var all = before.intake.merging(before.intakeDraft?.answers ?? [:]) { _, draft in draft }
        all[question.id] = value
        let ids = questions.map(\.id)
        if before.intakeDoneAt != nil {
            AcademyStore.save(AcademyStore.answering([question.id: value], in: before, at: .now))
        } else if AcademyStore.answeredCount(all, of: ids) >= ids.count {
            AcademyStore.save(AcademyStore.answering(all, in: before, at: .now))
            AcademyEvent.log(.twinBorn)
        } else {
            let nextID = ids.first { all[$0] == nil }
            AcademyStore.save(AcademyStore.savingDraft(all, at: nextID, in: before, date: .now))
        }
        text = ""
        withAnimation(.easeInOut(duration: 0.25)) { load() }
    }

    // MARK: What Campus knows

    private var knows: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("What Campus knows about you") {
                Button(showingAll ? "Less" : "All") { withAnimation(.easeInOut(duration: 0.2)) { showingAll.toggle() } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
            }
            let shown = questions.filter { showingAll || answers[$0.id] != nil }
            ForEach(showingAll ? shown : Array(shown.prefix(4))) { question in
                Button {
                    interviewStart = question.id
                    showingInterview = true
                } label: {
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
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityHint("Change this answer")
            }
        }
    }

    private func summary(_ question: IntakeQuestion) -> String? {
        guard let answer = answers[question.id] else { return nil }
        if question.freeText { return answer }
        return question.options.first { $0.id == answer }.map { family.fill($0.summary) }
    }
}

/// The long reads (briefings, the ones the coach assigned first) and mental
/// skills, under the short lessons.
struct CampusReadingSection: View {
    let athlete: Athlete

    @State private var state = AcademyState()
    @State private var report: TwinReport?
    @State private var reading: AcademyHomeView.ReadingTarget?
    @State private var showingMentalSkills = false
    @State private var showingAll = false

    private var sportSlug: String? { athlete.activeSport?.sportSlug }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("Long reads") {
                    Button(showingAll ? "Less" : "All \(AcademyContent.briefings.count)") {
                        withAnimation(.easeInOut(duration: 0.2)) { showingAll.toggle() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                }
                let assigned = Set(report?.assigned.map(\.id) ?? [])
                let ordered = AcademyContent.briefings.sorted { (assigned.contains($0.id) ? 0 : 1) < (assigned.contains($1.id) ? 0 : 1) }
                ForEach(showingAll ? ordered : Array(ordered.prefix(3))) { briefing in
                    Button {
                        reading = AcademyHomeView.ReadingTarget(briefing: briefing, insight: report?.insights.first { $0.kind == briefing.insight })
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            RoundedRectangle(cornerRadius: 2).fill(briefing.topic.color).frame(width: 3, height: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(briefing.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)
                                    .multilineTextAlignment(.leading)
                                Text("\(briefing.topic.title) · \(briefing.minutes) min\(assigned.contains(briefing.id) ? " · picked for you" : "")")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                            Spacer(minLength: 8)
                            if state.read[briefing.id] != nil {
                                Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(AppTheme.green)
                            }
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                }
            }
            Button { showingMentalSkills = true } label: {
                ListRow(systemImage: "brain.head.profile", color: AuraTone.mind.mark, title: "Mental skills",
                        detail: "Confidence, focus, talking it through")
            }
            .buttonStyle(.pressable)
        }
        .onAppear(perform: load)
        .fullScreenCover(item: $reading, onDismiss: load) { target in
            BriefingReaderView(briefing: target.briefing, insight: target.insight, alreadyRead: state.read[target.briefing.id] != nil,
                               familyID: AcademyContent.familyID(forSport: sportSlug))
        }
        .sheet(isPresented: $showingMentalSkills) { MentalSkillsView() }
    }

    private func load() {
        state = AcademyStore.load()
        report = TwinAnalysis.report(TwinInputBuilder.input(athlete: athlete, state: state))
    }
}
