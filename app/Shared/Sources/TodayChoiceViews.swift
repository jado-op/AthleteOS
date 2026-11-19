import SwiftUI

/// "What's on today?" — big tappable choices the athlete combines (team
/// practice and the gym, a game and something light); rest and "let
/// AthleteOS decide" stand alone. With team practice, how hard it is.
/// Used by the morning check-in and Home's "Today" sheet.
struct DayChoicePicker: View {
    @Binding var answer: DayAnswer
    var gameWord: String = "Game"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(DayChoice.order) { choice in
                    tile(choice)
                }
            }
            if answer.choices.contains(.practice) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How hard is practice?")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    WrapLayout(spacing: 8) {
                        ForEach(PracticeIntensity.choices, id: \.self) { level in
                            Button {
                                answer = DayAnswer(choices: answer.choices, practice: level)
                            } label: {
                                Chip(level.choiceTitle, isSelected: answer.practice == level)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func title(_ choice: DayChoice) -> String {
        choice == .game ? gameWord : choice.title
    }

    private func tile(_ choice: DayChoice) -> some View {
        let selected = answer.choices.contains(choice)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { answer = answer.toggling(choice) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: choice.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selected ? AppTheme.ink : AppTheme.secondaryText)
                Text(title(choice))
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .selectableSurface(selected, shape: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// What the schedule already says, so a day that didn't change is one tap.
    static func scheduleHint(practiceToday: Bool, practiceTime: PracticeTime?, game: Date?, gameWord: String) -> String {
        var parts: [String] = []
        if let game { parts.append("\(gameWord.lowercased()) at \(game.formatted(date: .omitted, time: .shortened))") }
        if practiceToday { parts.append(practiceTime.map { "practice · \($0.label)" } ?? "practice") }
        guard !parts.isEmpty else { return "Nothing on your schedule today. Your choice shapes today's plan." }
        return "Your schedule says \(parts.joined(separator: " and ")). One tap if nothing changed."
    }

    /// The athlete's answer for today, or what the schedule suggests.
    static func startingAnswer(practiceToday: Bool, gameToday: Bool) -> DayAnswer {
        DayChoiceStore.answer() ?? DayAnswer.suggested(practiceScheduled: practiceToday, gameScheduled: gameToday)
    }
}

/// Home's "Today" sheet: change what's on today without redoing the
/// check-in. A different kind of day (sick, travel, holiday) is one tap away.
struct TodayChoiceSheet: View {
    let gameWord: String
    let hint: String
    let onSave: (DayAnswer) -> Void
    let onOtherKindOfDay: () -> Void
    @State private var answer: DayAnswer
    @Environment(\.dismiss) private var dismiss

    init(initial: DayAnswer, gameWord: String, hint: String, onSave: @escaping (DayAnswer) -> Void, onOtherKindOfDay: @escaping () -> Void) {
        self.gameWord = gameWord
        self.hint = hint
        self.onSave = onSave
        self.onOtherKindOfDay = onOtherKindOfDay
        _answer = State(initialValue: initial)
    }

    var body: some View {
        QuestionPage(progress: 1, question: "What's on today?", hint: hint, buttonTitle: "Save", buttonEnabled: !answer.choices.isEmpty,
                     onClose: { dismiss() }, onButton: { onSave(answer) }, tone: .training) {
            DayChoicePicker(answer: $answer, gameWord: gameWord)
            Button { onOtherKindOfDay() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bed.double.fill")
                        .foregroundStyle(AppTheme.secondaryText)
                    Text("Sick, travelling or on holiday?")
                        .foregroundStyle(AppTheme.ink)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.mutedText)
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
    }
}
