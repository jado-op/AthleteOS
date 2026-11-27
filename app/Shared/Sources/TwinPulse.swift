import SwiftUI

/// "Your twin learned …" after an input (TwinLearned): the check-in, a game
/// rating, a practice answer, a workout's few taps. Shown where the athlete
/// lands next (Home's notices, the games hub, the workout check's last step),
/// for a few minutes, once. Tapping it opens what the twin is learning.
@MainActor
final class TwinPulse: ObservableObject {
    static let shared = TwinPulse()

    @Published private(set) var message: String?
    private var postedAt: Date?

    /// How long the line stays: long enough to land on the next screen.
    static let lasts: TimeInterval = 10 * 60

    /// Before saving an input: what the twin knows now.
    static func before(_ athlete: Athlete) -> TwinKnowledge {
        TwinKnowledgeStore.current(athlete, state: AcademyStore.load())
    }

    /// After saving it: the one line this input added, if any.
    static func after(_ athlete: Athlete, before: TwinKnowledge, input: TwinLearned.Input) {
        let now = TwinKnowledgeStore.current(athlete, state: AcademyStore.load())
        guard let line = TwinLearned.line(before: before, after: now, input: input) else { return }
        shared.message = line
        shared.postedAt = .now
    }

    /// A line the twin says itself (the end of a workout: when legs are ready).
    static func say(_ line: String) {
        shared.message = line
        shared.postedAt = .now
    }

    /// The end of a workout that trained legs: when they're ready for hard
    /// work again — and, when that's the twin's longer rest, that it is (T10).
    static func afterWorkout(_ athlete: Athlete, catalogue: Catalogue, now: Date = .now, calendar: Calendar = .current) {
        guard !catalogue.itemsBySlug.isEmpty else { return }
        let history = GymHistoryBuilder.history(athlete, catalogue: catalogue, now: now, calendar: calendar)
        guard history.daysSince[.lower] == 0 else { return }
        let days = history.recoveryDays(.lower)
        guard let ready = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) else { return }
        let when = days == 1 ? "tomorrow" : TwinPage.weekday(ready, calendar: calendar)
        let why = history.legsTwinDays == days ? " Your legs usually need \(days) days after a hard session." : ""
        say("Your legs are ready for hard work again \(when).\(why)")
    }

    /// The line while it's fresh.
    var current: String? {
        guard let message, let postedAt, Date.now.timeIntervalSince(postedAt) < Self.lasts else { return nil }
        return message
    }

    func dismiss() {
        message = nil
        postedAt = nil
    }
}

/// The line itself: calm, the twin's colour, tap to see what it's learning.
struct TwinPulseLine: View {
    @ObservedObject private var pulse = TwinPulse.shared
    /// Opens the twin (the sheet it sits in closes first).
    var open: (() -> Void)? = nil

    var body: some View {
        if let text = pulse.current {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AuraTone.mind.mark)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                Button {
                    pulse.dismiss()
                    if let open { open() } else { AcademyNavigation.shared.openTwin("learning") }
                } label: {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.pressable)
                .accessibilityHint("Opens what your twin knows and is still learning")
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
        }
    }
}
