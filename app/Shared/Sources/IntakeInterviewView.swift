import SwiftUI

/// The intake interview — "create my twin": who the athlete is, in their own
/// words. No right or wrong answers; some feed the twin's analysis, all show
/// under "Who you are as an athlete".
///
/// First time: intro, then one question at a time, back and forward. Closing
/// half-way keeps the answers as a draft and the next open picks up there;
/// the twin is only created when the last question is done.
/// Editing (after that): opens straight on the question that was tapped,
/// saves any time, and asks before throwing changes away.
struct IntakeInterviewView: View {
    /// "Central midfielder · Soccer · In season"
    let sportSummary: String
    let sportSlug: String?
    /// Open on this question (editing one answer); nil = from the start.
    var startAt: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var index = -1
    @State private var answers: [String: String] = [:]
    /// The answers as they were when the interview opened, to spot changes.
    @State private var original: [String: String] = [:]
    @State private var editing = false
    @State private var loaded = false
    @State private var confirmingClose = false
    @FocusState private var typing: Bool

    private var questions: [IntakeQuestion] { AcademyContent.intake(forSport: sportSlug) }
    private var family: SportFamily { AcademyContent.family(forSport: sportSlug) }
    private var question: IntakeQuestion? { questions.indices.contains(index) ? questions[index] : nil }
    private var isLast: Bool { index == questions.count - 1 }
    private var hasChanges: Bool { normalized(answers) != normalized(original) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                Group {
                    if let question { questionView(question).id(question.id) } else { intro }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            footer
        }
        .background(AppTheme.background.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: index)
        .onAppear(perform: load)
        .confirmationDialog("Save your changes?", isPresented: $confirmingClose, titleVisibility: .visible) {
            Button("Save") { finish() }
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("You changed some answers in your interview.")
        }
    }

    // MARK: Opening and closing

    private func load() {
        guard !loaded else { return }
        loaded = true
        let state = AcademyStore.load()
        editing = state.intakeDoneAt != nil
        if editing {
            answers = state.intake
            original = state.intake
            // Editing goes straight to the questions: to the tapped one, or the first.
            index = startAt.flatMap { id in questions.firstIndex { $0.id == id } } ?? 0
        } else if let draft = state.intakeDraft {
            answers = draft.answers
            original = draft.answers
            // Pick up where they left off.
            index = draft.questionID.flatMap { id in questions.firstIndex { $0.id == id } } ?? 0
        }
    }

    private func close() {
        typing = false
        if editing {
            if hasChanges { confirmingClose = true } else { dismiss() }
        } else {
            // A first interview is never lost: what's answered stays as a draft.
            AcademyStore.save(AcademyStore.savingDraft(answers, at: question?.id, in: AcademyStore.load(), date: .now))
            dismiss()
        }
    }

    private func finish() {
        typing = false
        let before = AcademyStore.load()
        // Every question asked, so a cleared answer ("") clears what was stored.
        var all = answers
        for question in questions where all[question.id] == nil { all[question.id] = "" }
        AcademyStore.save(AcademyStore.answering(all, in: before, at: .now))
        if before.intakeDoneAt == nil { AcademyEvent.log(.twinBorn) }
        dismiss()
    }

    private func advance() {
        typing = false
        if isLast || questions.isEmpty { finish() } else { index += 1 }
    }

    private func back() {
        typing = false
        if index > (editing ? 0 : -1) { index -= 1 }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(editing ? "Close" : "Close — your answers so far are kept")
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(AppTheme.ink)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 4)
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue(question == nil ? "Not started" : "Question \(index + 1) of \(questions.count)")
            if editing {
                Button("Save", action: finish)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(hasChanges ? AppTheme.ink : AppTheme.mutedText)
                    .disabled(!hasChanges)
                    .frame(minWidth: 44, minHeight: 40)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var progress: CGFloat {
        guard !questions.isEmpty, index >= 0 else { return 0 }
        return CGFloat(index + 1) / CGFloat(questions.count)
    }

    // MARK: Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Interview")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AuraTone.mind.mark)
            Headline([.strong("Let your twin get to know you."), .soft(" How you think — not what you lift.")], size: 36)
            Text("Your data shows what you do. These questions are about how you think: what drives you, what pressure does to you, how you deal with mistakes. There are no right answers — the honest one is the useful one.")
                .font(.reading(18))
                .lineSpacing(6)
                .foregroundStyle(AppTheme.ink.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                Label(sportSummary, systemImage: "sportscourt.fill")
                Label("\(countedNoun(questions.count, "question")) · about five minutes", systemImage: "clock")
                Label("Only you can see your answers. Stop any time — they're kept.", systemImage: "hand.raised.fill")
            }
            .font(.subheadline)
            .foregroundStyle(AppTheme.secondaryText)
        }
    }

    // MARK: A question

    private func questionView(_ question: IntakeQuestion) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("\(index + 1) of \(questions.count) · \(family.fill(question.label))")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.mutedText)
            Text(family.fill(question.prompt))
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.7)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if question.freeText {
                freeText(question)
            } else {
                options(question)
            }
        }
    }

    private func freeText(_ question: IntakeQuestion) -> some View {
        let text = answers[question.id] ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            TextField(question.placeholder ?? "Your answer", text: Binding(
                get: { answers[question.id] ?? "" },
                set: { answers[question.id] = String($0.prefix(AcademyStore.freeTextLimit)) }), axis: .vertical)
                .lineLimit(2...6)
                .font(.body)
                .foregroundStyle(AppTheme.ink)
                .focused($typing)
                .submitLabel(.done)
                .padding(16)
                .glassSurface(cornerRadius: 16)
            HStack {
                Text("Optional.")
                Spacer()
                if text.count > AcademyStore.freeTextLimit - 60 {
                    Text("\(AcademyStore.freeTextLimit - text.count) left")
                        .monospacedDigit()
                }
            }
            .font(.footnote)
            .foregroundStyle(AppTheme.mutedText)
        }
    }

    private func options(_ question: IntakeQuestion) -> some View {
        VStack(spacing: 10) {
            ForEach(question.options) { option in
                let picked = answers[question.id] == option.id
                Button {
                    // Tap the chosen answer again to take it back.
                    withAnimation(.easeInOut(duration: 0.15)) { answers[question.id] = picked ? "" : option.id }
                } label: {
                    HStack(spacing: 12) {
                        Text(family.fill(option.text))
                            .font(.body.weight(.medium))
                            .foregroundStyle(AppTheme.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(picked ? AuraTone.mind.mark : AppTheme.mutedText)
                            .accessibilityHidden(true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .glassSurface(cornerRadius: 16)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(picked ? AuraTone.mind.mark.opacity(0.85) : Color.white.opacity(0.08), lineWidth: 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(picked ? .isSelected : [])
                .accessibilityHint(picked ? "Tap again to clear" : "")
            }
        }
        .sensoryFeedback(.selection, trigger: answers[question.id])
    }

    // MARK: Footer

    private var answeredCurrent: Bool {
        guard let question else { return true }
        return !(answers[question.id]?.isEmpty ?? true)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if index > (editing ? 0 : -1) {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .frame(width: 52, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.secondaryText)
                .glassCapsule()
                .accessibilityLabel("Previous question")
            }
            if let question, !question.freeText, !answeredCurrent {
                // Nothing chosen: move on without an answer.
                Button(isLast ? "Skip and finish" : "Skip", action: advance)
                    .buttonStyle(.secondary)
            } else {
                Button(action: advance) {
                    HeroCTALabel(primaryTitle)
                }
                .buttonStyle(.primary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var primaryTitle: String {
        if index < 0 { return AcademyStore.answeredCount(answers, of: questions.map(\.id)) > 0 ? "Continue" : "Start" }
        if isLast { return editing ? "Save" : "Create my twin" }
        return "Continue"
    }

    // MARK: Helpers

    /// Answers without the empty ones, trimmed — what would actually be saved.
    private func normalized(_ answers: [String: String]) -> [String: String] {
        answers.compactMapValues { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}
