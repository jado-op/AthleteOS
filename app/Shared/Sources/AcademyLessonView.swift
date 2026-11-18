import SwiftUI

/// One Academy lesson, 3–5 minutes: short teaching cards, an optional legend
/// insight, then 2–4 questions — knowledge checks (one right answer) and
/// self-reflection (no right answer). The end screen shows the twin change.
struct AcademyLessonView: View {
    let lesson: AcademyLesson
    let sportSlug: String?

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var answers: [String: Int] = [:]
    @State private var finish: Finish?
    @State private var confirmQuit = false
    @State private var showingSupport = false

    struct Finish {
        let before: TwinSnapshot
        let after: TwinSnapshot
        let look: TwinAppearance
    }

    enum Step {
        case teach(AcademySection)
        case legend(AcademyLegend)
        case question(AcademyQuestion)
    }

    private var steps: [Step] {
        lesson.sections.map(Step.teach) + (lesson.legend.map { [Step.legend($0)] } ?? []) + lesson.questions.map(Step.question)
    }

    private var step: Step? { steps.indices.contains(index) ? steps[index] : nil }

    var body: some View {
        VStack(spacing: 0) {
            if let finish {
                endScreen(finish)
            } else {
                header
                ScrollView {
                    if let step { stepView(step).padding(.horizontal, 22).padding(.top, 28) }
                }
                .scrollIndicators(.hidden)
                footer
            }
        }
        .background(AppBackground(.subtle).ignoresSafeArea())
        .sheet(isPresented: $showingSupport) { SupportSheet() }
        .confirmationDialog("Leave this lesson?", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { dismiss() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Your twin only changes when you finish a lesson.")
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                if index == 0 { dismiss() } else { confirmQuit = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(lesson.pillar.color)
                        .frame(width: proxy.size.width * CGFloat(index + 1) / CGFloat(max(steps.count, 1)))
                }
            }
            .frame(height: 5)
            .animation(.easeInOut(duration: 0.3), value: index)
            if lesson.support {
                Button { showingSupport = true } label: {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.purple)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Need to talk to someone?")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var footer: some View {
        Button(action: advance) {
            HeroCTALabel(index == steps.count - 1 ? "Finish" : "Continue")
        }
        .buttonStyle(.primary)
        .disabled(!canContinue)
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var canContinue: Bool {
        guard case .question(let question)? = step else { return true }
        return answers[question.id] != nil
    }

    private func advance() {
        if index < steps.count - 1 {
            withAnimation(.easeInOut(duration: 0.25)) { index += 1 }
        } else {
            complete()
        }
    }

    private func complete() {
        let areas = AcademyContent.areas(forSport: sportSlug)
        let before = AcademyStore.load()
        let after = AcademyStore.completing(lesson, answers: answers, in: before, at: .now)
        AcademyStore.save(after)
        AcademyEvent.log(.lessonCompleted)
        finish = Finish(before: TwinScoring.snapshot(before.ledger, sportAreas: areas),
                        after: TwinScoring.snapshot(after.ledger, sportAreas: areas), look: after.look)
    }

    // MARK: Steps

    @ViewBuilder
    private func stepView(_ step: Step) -> some View {
        switch step {
        case .teach(let section):
            VStack(alignment: .leading, spacing: 16) {
                if index == 0 {
                    Label(lesson.pillar.title, systemImage: lesson.pillar.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(lesson.pillar.color)
                    Text(lesson.title)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .padding(.bottom, 12)
                }
                Text(section.heading)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(section.body)
                    .font(.body)
                    .lineSpacing(4)
                    .foregroundStyle(AppTheme.ink.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .legend(let legend):
            VStack(alignment: .leading, spacing: 14) {
                Label("Legend insight", systemImage: "star.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.yellow)
                Text(legend.athlete)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                Text(legend.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                Text(legend.body)
                    .font(.body)
                    .lineSpacing(4)
                    .foregroundStyle(AppTheme.ink.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(padding: 20)
        case .question(let question):
            questionView(question)
        }
    }

    private func questionView(_ question: AcademyQuestion) -> some View {
        AcademyQuestionCard(question: question, accent: lesson.pillar.color,
                            chosen: Binding(get: { answers[question.id] }, set: { answers[question.id] = $0 }))
    }

    // MARK: End

    private func endScreen(_ finish: Finish) -> some View {
        let deltas = TwinScoring.deltas(from: finish.before, to: finish.after)
        return ScrollView {
            VStack(spacing: 24) {
                DigitalTwinView(state: TwinVisualState(appearance: finish.look, sportSlug: sportSlug, snapshot: finish.after, mode: .levelUp,
                                                       gains: Dictionary(deltas.map { ($0.pillar, $0.change) }, uniquingKeysWith: +)))
                    .frame(height: 460)
                    .padding(.horizontal, -24)
                VStack(spacing: 8) {
                    if let first = deltas.first {
                        Text(TwinScoring.line(for: first))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                            .multilineTextAlignment(.center)
                        ForEach(deltas.dropFirst()) { delta in
                            Text(TwinScoring.line(for: delta))
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    } else {
                        Text("Lesson finished — your twin keeps what it learned.")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                            .multilineTextAlignment(.center)
                    }
                }
                Button { dismiss() } label: { HeroCTALabel("Done") }
                    .buttonStyle(.primary)
                if !lesson.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Based on")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.mutedText)
                        ForEach(lesson.sources, id: \.url) { source in
                            Text(source.detail)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.mutedText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
    }
}
