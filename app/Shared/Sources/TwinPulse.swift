import SwiftUI

/// "Your twin learned …" after an input (TwinLearned): the check-in or a
/// game rating; and the end of a workout that trained legs. Each line belongs
/// to the input that made it and shows where the athlete lands next (Home's
/// notices; the games hub for a rating), once. Tapping it opens the twin
/// where that line lives.
@MainActor
final class TwinPulse: ObservableObject {
    enum Source { case checkIn, gameRating, workout }

    struct Message: Equatable {
        let text: String
        let source: Source
        /// Where on the Twin page it lives: a new line in "know", progress in "learning".
        let target: String
        let at: Date
    }

    static let shared = TwinPulse()

    @Published private(set) var message: Message?

    /// How long the line waits for the athlete to land on it.
    static let lasts: TimeInterval = 10 * 60

    /// What the athlete sees of the twin: lines they said weren't right don't count (T13).
    private static func seen(_ athlete: Athlete) -> TwinKnowledge {
        let state = AcademyStore.load()
        var knowledge = TwinKnowledgeStore.current(athlete, state: state)
        knowledge.lines = TwinKnowledgeStore.visible(knowledge, state: state)
        return knowledge
    }

    /// Before saving an input: what the twin knows now (an older line goes —
    /// a new input never shows the last one's words).
    static func before(_ athlete: Athlete) -> TwinKnowledge {
        shared.message = nil
        return seen(athlete)
    }

    /// After saving it: the one line this input added, if any.
    static func after(_ athlete: Athlete, before: TwinKnowledge, input: TwinLearned.Input) {
        guard let line = TwinLearned.line(before: before, after: seen(athlete), input: input) else { return }
        let source: Source = input == .gameRating ? .gameRating : .checkIn
        shared.message = Message(text: line, source: source, target: line.hasPrefix(TwinLearned.newPrefix) ? "know" : "learning", at: .now)
    }

    /// The end of a workout whose own sets trained legs: when they're ready
    /// for hard work again — and, when that's the twin's longer rest, that it is (T10).
    static func afterWorkout(_ athlete: Athlete, session: Session, catalogue: Catalogue, now: Date = .now, calendar: Calendar = .current) {
        guard !catalogue.itemsBySlug.isEmpty else { return }
        let legs = session.sets.contains { set in
            guard let profile = catalogue.item(set.itemSlug)?.planProfile else { return false }
            return profile.isLower && (profile.role == "primary" || profile.role == "secondary")
        }
        guard legs else { return }
        let history = GymHistoryBuilder.history(athlete, catalogue: catalogue, now: now, calendar: calendar)
        let days = history.recoveryDays(.lower)
        guard let ready = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) else { return }
        let when = days == 1 ? "tomorrow" : TwinPage.weekday(ready, calendar: calendar)
        let why = history.legsTwinDays == days ? " Your legs usually need \(days) days after a hard session." : ""
        shared.message = Message(text: "Your legs are ready for hard work again \(when).\(why)", source: .workout, target: "know", at: now)
    }

    /// The line for a place, while it's fresh.
    func current(for sources: Set<Source>) -> Message? {
        guard let message, sources.contains(message.source), Date.now.timeIntervalSince(message.at) < Self.lasts else { return nil }
        return message
    }

    func dismiss() {
        message = nil
    }
}

/// The line itself: calm, the twin's colour, tap to see it in the twin.
/// Shown once: leaving the place it showed in lets it go.
struct TwinPulseLine: View {
    /// The inputs whose lines belong here.
    let sources: Set<TwinPulse.Source>
    /// Closes the sheet it sits in first (nil on Home).
    var close: (() -> Void)? = nil
    @ObservedObject private var pulse = TwinPulse.shared

    var body: some View {
        if let message = pulse.current(for: sources) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AuraTone.mind.mark)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                Button {
                    pulse.dismiss()
                    close?()
                    AcademyNavigation.shared.openTwin(message.target)
                } label: {
                    Text(message.text)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.pressable)
                .accessibilityHint("Opens it in your twin")
                Button { withAnimation { pulse.dismiss() } } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Dismiss")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface()
            .transition(.opacity)
            .onDisappear {
                // Seen here once; it doesn't follow the athlete around.
                if pulse.message == message { pulse.dismiss() }
            }
        }
    }
}
