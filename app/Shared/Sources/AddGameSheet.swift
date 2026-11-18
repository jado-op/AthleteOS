import SwiftData
import SwiftUI

/// §10: "Add a game → the week visibly rearranges." Date, type, home/away,
/// and an optional note — the full shape of §14's `Competition`.
struct AddGameSheet: View {
    let athlete: Athlete
    let onSaved: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now
    @State private var kind: CompetitionKind = .game
    @State private var isHome = true
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ScreenTitle("Add a game", subtitle: "Your week rearranges around it — heavy work early, sharp and fresh on the day.")

                    DatePicker("Date", selection: $date, in: Calendar.current.startOfDay(for: .now)..., displayedComponents: .date)
                        .labelsHidden()
                        .calendarDatePickerStyle()
                        .tint(AppTheme.accent)
                        .cardStyle(padding: 12)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Type")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        HStack(spacing: 8) {
                            kindChip(.game, "Game")
                            kindChip(.tournament, "Tournament")
                            kindChip(.meet, "Meet")
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Where")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        HStack(spacing: 8) {
                            Button { isHome = true } label: { Chip("Home", isSelected: isHome) }
                                .buttonStyle(.plain)
                            Button { isHome = false } label: { Chip("Away", isSelected: !isHome) }
                                .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Note")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        TextField("Opponent, time… (optional)", text: $notes)
                            .padding(16)
                            .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                    }

                    Button("Save game", action: save)
                        .buttonStyle(.primary)
                }
                .padding(20)
            }
            .appScreen()
            .toolbar {
                CloseToolbarItem { dismiss() }
            }
        }
    }

    private func kindChip(_ value: CompetitionKind, _ title: String) -> some View {
        Button { kind = value } label: { Chip(title, isSelected: kind == value) }
            .buttonStyle(.plain)
    }

    private func save() {
        guard let sportSlug = athlete.activeSport?.sportSlug else { return }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let competition = Competition(
            sportSlug: sportSlug, date: date, kind: kind, isHome: isHome,
            notes: trimmed.isEmpty ? nil : trimmed, athlete: athlete
        )
        modelContext.insert(competition)
        try? modelContext.save()
        onSaved()
        dismiss()
    }
}

extension View {
    /// A month-grid date picker on iPhone; watchOS has no graphical style, so
    /// it keeps the platform default there.
    @ViewBuilder
    func calendarDatePickerStyle() -> some View {
        #if os(iOS)
        datePickerStyle(.graphical)
        #else
        self
        #endif
    }
}
