import SwiftData
import SwiftUI

/// Games and extra trainings coming up — planning input, so it lives with
/// the training (Workout), not in the Academy's Progress page.
struct GamesAndEventsSection: View {
    let athlete: Athlete
    let onPlanInputsChanged: () -> Void

    enum Sheet: String, Identifiable {
        case calendars, addGame, addTraining
        var id: String { rawValue }
    }

    @State private var sheet: Sheet?
    @State private var revision = 0
    private var calendar: Calendar { .current }

    var body: some View {
        content
            .sheet(item: $sheet, onDismiss: { revision += 1 }) { sheet in
                switch sheet {
                case .calendars: ScheduleSheet(athlete: athlete, onChanged: onPlanInputsChanged)
                case .addGame: AddGameSheet(athlete: athlete, onSaved: onPlanInputsChanged)
                case .addTraining: ExtraPracticeSheet { onPlanInputsChanged() }
                }
            }
    }

    private var content: some View {
        _ = revision
        let upcomingGames = AthleteStats.upcomingCompetitions(athlete).prefix(4)
        let extras = ExtraPractices.all.filter { $0.day >= DayKey.of(.now, calendar: calendar) }.prefix(4)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Games & events")
            // The schedule itself is set up in Me → Training Setup; here only while it is missing.
            if !PracticeSchedule.isSet {
                row("Set up your schedule", "Practice days and team calendars", icon: "calendar.badge.clock") { sheet = .calendars }
            }
            ButtonRow {
                Button { sheet = .addGame } label: { Label("Add a game", systemImage: "sportscourt.fill") }
                    .buttonStyle(.primary)
                Button { sheet = .addTraining } label: { Label("Add a training", systemImage: "plus") }
                    .buttonStyle(.secondary)
            }
            if !upcomingGames.isEmpty || !extras.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(upcomingGames), id: \.id) { game in
                        Label("\(game.date.formatted(.dateTime.weekday(.abbreviated).month().day())) · \(game.kind.rawValue.capitalized) · \(game.isHome ? "Home" : "Away")\(game.notes.map { " · \($0)" } ?? "")",
                              systemImage: "sportscourt.fill")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(2)
                    }
                    ForEach(Array(extras)) { extra in
                        HStack {
                            Label("\(extra.day) · \(extra.title)\(extra.time.map { " · \($0.label)" } ?? "")", systemImage: "figure.run")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            Button {
                                ExtraPractices.all = ExtraPractices.all.filter { $0.id != extra.id }
                                revision += 1
                                onPlanInputsChanged()
                            } label: {
                                Image(systemName: "trash").foregroundStyle(AppTheme.secondaryText).frame(width: 40, height: 40)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(extra.title)")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle(padding: 16)
            }
        }
    }

    private func row(_ title: String, _ detail: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ListRow(systemImage: icon, color: AppTheme.ink, title: title, detail: detail)
                .padding(12)
                .glassSurface(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }
}
