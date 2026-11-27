import SwiftData
import SwiftUI

/// "A plan you can see bend" (owner, 2026-11-27): the week as a timeline.
/// Tap a day — a game there, or a day you can't train — and the week rebuilds
/// in front of you: every day that changed lights up with what changed and
/// why. One tap undoes it. The planner decides; this only shows it moving.
struct WeekBendView: View {
    let athlete: Athlete

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var days: [WeekBend.Day] = []
    @State private var changes: [Int: String] = [:]
    @State private var picked: Int?
    @State private var undo: (label: String, action: () -> Void)?

    private var calendar: Calendar { .current }
    private var event: String { AcademyContent.family(forSport: athlete.activeSport?.sportSlug).tokens["Event"] ?? "Game" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Headline([.strong("Your week. "), .soft("Tap a day to move things around and watch the plan adapt.")], size: 30)
                    VStack(spacing: 10) {
                        ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                            Button { picked = index } label: { row(day, change: changes[index]) }
                                .buttonStyle(.pressable)
                                .disabled(calendar.startOfDay(for: day.date) < calendar.startOfDay(for: .now))
                        }
                    }
                    if let undo {
                        Button {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { undo.action() }
                        } label: {
                            Label(undo.label, systemImage: "arrow.uturn.backward")
                                .font(.subheadline.weight(.semibold))
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.secondary)
                    }
                    Text("Past days stay as they were. Gym days never land on a game, a practice or a day you can't train.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .appScreen()
            .navigationTitle("This week")
            .navigationBarTitleDisplayModeInline()
            .toolbar { CloseToolbarItem { dismiss() } }
            .onAppear { days = current() }
            .confirmationDialog(picked.map { title(days[$0]) } ?? "", isPresented: Binding(
                get: { picked != nil }, set: { if !$0 { picked = nil } }), titleVisibility: .visible) {
                if let index = picked, days.indices.contains(index) { actions(days[index]) }
            }
        }
    }

    // MARK: Rows

    private func row(_ day: WeekBend.Day, change: String?) -> some View {
        let isToday = calendar.isDateInToday(day.date)
        return HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 2) {
                Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isToday ? AuraTone.training.mark : AppTheme.secondaryText)
                Text(day.date.formatted(.dateTime.day()))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
            }
            .frame(width: 44)
            Capsule()
                .fill(color(day.kind))
                .frame(width: 5)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 4) {
                Text(headline(day))
                    .font(.headline)
                    .foregroundStyle(day.kind == .rest || day.kind == .blocked ? AppTheme.secondaryText : AppTheme.ink)
                if let change {
                    Label(change, systemImage: "arrow.triangle.swap")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AuraTone.training.mark)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            Spacer(minLength: 0)
            if let minutes = day.minutes {
                Text("\(minutes) min")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
        .background(change != nil ? AuraTone.training.mark.opacity(0.10) : Color.white.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(change != nil ? AuraTone.training.mark.opacity(0.5) : Color.white.opacity(0.06), lineWidth: 1)
        }
        .opacity(calendar.startOfDay(for: day.date) < calendar.startOfDay(for: .now) ? 0.45 : 1)
        .accessibilityElement(children: .combine)
    }

    private func headline(_ day: WeekBend.Day) -> String {
        switch day.kind {
        case .game: "\(event) day"
        case .blocked: "Can't train"
        case .practice: day.workout.map { "Practice + \($0)" } ?? "Team practice"
        case .gym: day.workout ?? "Gym"
        case .rest: "Rest"
        }
    }

    private func color(_ kind: WeekBend.Day.Kind) -> Color {
        switch kind {
        case .gym: AuraTone.training.mark
        case .practice: AuraTone.body.mark
        case .game: AuraTone.game.mark
        case .rest: Color.white.opacity(0.15)
        case .blocked: AppTheme.coral.opacity(0.7)
        }
    }

    private func title(_ day: WeekBend.Day) -> String {
        day.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    // MARK: Actions

    @ViewBuilder
    private func actions(_ day: WeekBend.Day) -> some View {
        let date = day.date
        if BusyDays.contains(date) {
            Button("I can train this day again") { bend("Free again") { BusyDays.toggle(date) } undo: { BusyDays.toggle(date) } }
        } else if day.kind != .game {
            Button("I can't train this day") { bend("Can't train") { BusyDays.toggle(date) } undo: { BusyDays.toggle(date) } }
        }
        if let existing = game(on: date) {
            Button("Remove the \(event.lowercased())", role: .destructive) {
                let kind = existing.kind, start = existing.date, notes = existing.notes, isHome = existing.isHome
                bend("\(event) removed") {
                    modelContext.delete(existing)
                    try? modelContext.save()
                } undo: {
                    modelContext.insert(Competition(sportSlug: athlete.activeSport?.sportSlug ?? "general", date: start, kind: kind,
                                                    isHome: isHome, notes: notes, athlete: athlete))
                    try? modelContext.save()
                }
            }
        } else if !BusyDays.contains(date) {
            Button("\(event) this day") {
                let start = GameTime.start(date, usualMinutes: UserDefaults.standard.object(forKey: GameTime.usualStartKey) as? Int
                                           ?? GameTime.defaultUsualMinutes, calendar: calendar)
                let created = Competition(sportSlug: athlete.activeSport?.sportSlug ?? "general", date: start, kind: .game, athlete: athlete)
                bend("\(event) added") {
                    modelContext.insert(created)
                    try? modelContext.save()
                } undo: {
                    if let again = game(on: date) { modelContext.delete(again); try? modelContext.save() }
                }
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    private func game(on date: Date) -> Competition? {
        athlete.competitions.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// Changes the week, rebuilds it and shows what moved; the undo puts it back.
    private func bend(_ label: String, _ change: () -> Void, undo reverse: @escaping () -> Void) {
        let before = current()
        change()
        NotificationCenter.default.post(name: WeeklyPlan.inputsChanged, object: nil)
        let after = current()
        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
            days = after
            changes = WeekBend.changes(before: before, after: after, event: event, calendar: calendar)
        }
        undo = ("Undo: \(label.lowercased())", {
            reverse()
            NotificationCenter.default.post(name: WeeklyPlan.inputsChanged, object: nil)
            days = current()
            changes = [:]
            undo = nil
        })
    }

    /// This week, Monday to Sunday as the planner built it.
    private func current() -> [WeekBend.Day] {
        let week = WeeklyPlan.generate(for: athlete)
        let start = week.map { calendar.startOfDay(for: $0.weekStart) }
            ?? calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? calendar.startOfDay(for: .now)
        return (0..<7).compactMap { offset -> WeekBend.Day? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let session = week?.sessions.first { calendar.isDate($0.date, inSameDayAs: date) }
            if game(on: date) != nil { return WeekBend.Day(date: date, kind: .game) }
            if BusyDays.contains(date) { return WeekBend.Day(date: date, kind: .blocked) }
            if PracticeSchedule.hasPractice(on: date, calendar: calendar) {
                return WeekBend.Day(date: date, kind: .practice, workout: session?.title, minutes: session?.estimatedMinutes)
            }
            if let session { return WeekBend.Day(date: date, kind: .gym, workout: session.title, minutes: session.estimatedMinutes) }
            return WeekBend.Day(date: date, kind: .rest)
        }
    }
}
