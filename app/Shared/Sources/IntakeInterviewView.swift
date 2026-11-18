import SwiftUI

/// The intake interview: who the athlete is, in their own words. No right or
/// wrong answers; some feed the twin's analysis, all show under "Who you are
/// as an athlete". Opens again from there to change anything.
struct IntakeInterviewView: View {
    /// "Central midfielder · Soccer · In season"
    let sportSummary: String
    let sportSlug: String?

    @Environment(\.dismiss) private var dismiss
    @State private var index = -1
    @State private var answers: [String: String] = AcademyStore.load().intake
    @FocusState private var typing: Bool

    private var questions: [IntakeQuestion] { AcademyContent.intake(forSport: sportSlug) }
    private var family: SportFamily { AcademyContent.family(forSport: sportSlug) }

    private var question: IntakeQuestion? { questions.indices.contains(index) ? questions[index] : nil }

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
            footer
        }
        .background(AppBackground(.hero).ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: index)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
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
                    Capsule().fill(AppTheme.brightRed)
                        .frame(width: proxy.size.width * CGFloat(max(index, 0) + (index >= 0 ? 1 : 0)) / CGFloat(max(questions.count, 1)))
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Interview")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.brightRed)
            Text("Let your twin get to know you")
                .font(.system(size: 34, weight: .semibold))
                .tracking(-1)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Your data shows what you do. These questions are about how you think: what drives you, what pressure does to you, how you deal with mistakes. There are no right answers — the honest one is the useful one.")
                .font(.reading(18))
                .lineSpacing(6)
                .foregroundStyle(AppTheme.ink.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                Label(sportSummary, systemImage: "sportscourt.fill")
                Label("\(questions.count) questions · about five minutes", systemImage: "clock")
                Label("Only you can see your answers. Change them any time.", systemImage: "hand.raised.fill")
            }
            .font(.subheadline)
            .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func questionView(_ question: IntakeQuestion) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("\(index + 1) of \(questions.count) · \(family.fill(question.label))")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.mutedText)
            Text(family.fill(question.prompt))
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if question.freeText {
                TextField(question.placeholder ?? "Your answer", text: Binding(
                    get: { answers[question.id] ?? "" },
                    set: { answers[question.id] = $0 }), axis: .vertical)
                    .lineLimit(2...5)
                    .font(.body)
                    .foregroundStyle(AppTheme.ink)
                    .focused($typing)
                    .padding(16)
                    .glassSurface(cornerRadius: 16)
                Text("Optional.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedText)
            } else {
                VStack(spacing: 10) {
                    ForEach(question.options) { option in
                        let picked = answers[question.id] == option.id
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { answers[question.id] = option.id }
                        } label: {
                            HStack(spacing: 12) {
                                Text(family.fill(option.text))
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(AppTheme.ink)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(picked ? AppTheme.brightRed : AppTheme.mutedText)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .glassSurface(cornerRadius: 16)
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(picked ? AppTheme.brightRed.opacity(0.8) : Color.white.opacity(0.08), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(picked ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var isLast: Bool { index == questions.count - 1 }

    private var footer: some View {
        HStack(spacing: 12) {
            if let question, !question.freeText {
                Button("Skip") { advance() }
                    .buttonStyle(.secondary)
                    .frame(width: 110)
            }
            Button(action: advance) {
                HeroCTALabel(index < 0 ? "Start" : (isLast ? "Done" : "Continue"))
            }
            .buttonStyle(.primary)
            .disabled(question.map { !$0.freeText && answers[$0.id] == nil } ?? false)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func advance() {
        typing = false
        if isLast || questions.isEmpty {
            let before = AcademyStore.load()
            AcademyStore.save(AcademyStore.answering(answers, in: before, at: .now))
            AcademyEvent.log(before.intakeDoneAt == nil ? .twinBorn : .reflectionSubmitted)
            dismiss()
        } else {
            index += 1
        }
    }
}
