import SwiftData
import SwiftUI

/// Me → Reminders: the morning check-in nudge, the evening reflection and
/// game-eve reminders.
struct RemindersSheet: View {
    let athlete: Athlete
    @Environment(\.dismiss) private var dismiss
    @State private var settings = ReminderScheduler.settings
    @State private var time = Date.now
    @State private var reflectionTime = Date.now
    @State private var denied = false
    @State private var teamUpdates = PushSettings.teamUpdatesOn
    @State private var healthNotes = PushSettings.healthNotesOn

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ScreenTitle("Reminders", subtitle: "A nudge at the right moment — never spam.")

                    VStack(spacing: 0) {
                        Toggle(isOn: $settings.checkInEnabled) {
                            row("Morning check-in", "Four taps to start the day", "sun.max.fill", AppTheme.amber)
                        }
                        .tint(AppTheme.green)
                        .padding(.vertical, 8)
                        if settings.checkInEnabled {
                            Divider().overlay(AppTheme.hairline)
                            DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                                .foregroundStyle(AppTheme.ink)
                                .tint(AppTheme.accent)
                                .padding(.vertical, 10)
                        }
                        Divider().overlay(AppTheme.hairline)
                        Toggle(isOn: $settings.reflectionEnabled) {
                            row("Evening reflection", "45 seconds: how today felt", "moon.stars.fill", AppTheme.purple)
                        }
                        .tint(AppTheme.green)
                        .padding(.vertical, 8)
                        if settings.reflectionEnabled {
                            Divider().overlay(AppTheme.hairline)
                            DatePicker("Time", selection: $reflectionTime, displayedComponents: .hourAndMinute)
                                .foregroundStyle(AppTheme.ink)
                                .tint(AppTheme.accent)
                                .padding(.vertical, 10)
                        }
                        Divider().overlay(AppTheme.hairline)
                        Toggle(isOn: $settings.gameRemindersEnabled) {
                            row("Game eve", "The evening before each game", "sportscourt.fill", AppTheme.brand)
                        }
                        .tint(AppTheme.green)
                        .padding(.vertical, 8)
                        Divider().overlay(AppTheme.hairline)
                        Toggle(isOn: $settings.bedtimeEnabled) {
                            row("Bedtime", "Silent, 30 min before a 9-hour night", "bed.double.fill", AppTheme.purple)
                        }
                        .tint(AppTheme.green)
                        .padding(.vertical, 8)
                        Divider().overlay(AppTheme.hairline)
                        Toggle(isOn: $settings.smartTiming) {
                            row("Smart timing", "Later check-in at weekends, reflection after practice", "wand.and.stars", AppTheme.ink)
                        }
                        .tint(AppTheme.green)
                        .padding(.vertical, 8)
                    }
                    .cardStyle(padding: 16)

                    if PushSettings.hasTeam {
                        VStack(spacing: 0) {
                            Toggle(isOn: $teamUpdates) {
                                row("Team updates", "A new workout, a note or a return-to-play step", "person.3.fill", AppTheme.brand)
                            }
                            .tint(AppTheme.green)
                            .padding(.vertical, 8)
                            if PushSettings.isStaff {
                                Divider().overlay(AppTheme.hairline)
                                Toggle(isOn: $healthNotes) {
                                    row("Pain reports", "When an athlete shares a new one — no names on the lock screen", "cross.case.fill", AppTheme.danger)
                                }
                                .tint(AppTheme.green)
                                .padding(.vertical, 8)
                            }
                        }
                        .cardStyle(padding: 16)
                    }

                    if denied {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "bell.slash.fill")
                                .foregroundStyle(AppTheme.secondaryText)
                            Text("Notifications are turned off for AthleteOS. Turn them on in the Settings app → Notifications.")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        .cardStyle(padding: 16)
                    }

                }
                .padding(20)
            }
            .appScreen()
            .toolbar {
                CloseToolbarItem { dismiss() }
                ConfirmToolbarItem(action: save)
            }
            .onAppear {
                time = Calendar.current.date(bySettingHour: settings.checkInHour, minute: settings.checkInMinute, second: 0, of: .now) ?? .now
                reflectionTime = Calendar.current.date(bySettingHour: settings.reflectionHour, minute: settings.reflectionMinute, second: 0, of: .now) ?? .now
            }
        }
    }

    private func row(_ title: String, _ detail: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private func save() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        settings.checkInHour = parts.hour ?? 7
        settings.checkInMinute = parts.minute ?? 15
        let evening = Calendar.current.dateComponents([.hour, .minute], from: reflectionTime)
        settings.reflectionHour = evening.hour ?? 20
        settings.reflectionMinute = evening.minute ?? 30
        ReminderScheduler.settings = settings
        PushSettings.teamUpdatesOn = teamUpdates
        PushSettings.healthNotesOn = healthNotes
        let games = AthleteStats.upcomingCompetitions(athlete).map { (date: $0.date, kind: $0.kind.rawValue.capitalized) }
        let wantsPush = PushSettings.hasTeam && (teamUpdates || (PushSettings.isStaff && healthNotes))
        let wantsAny = settings.anyEnabled || wantsPush
        Task {
            if wantsAny {
                let granted = await ReminderScheduler.requestAuthorization()
                if !granted {
                    denied = true
                    return
                }
            }
            await ReminderScheduler.reschedule(games: games)
            if wantsPush { await PushSettings.enable() } else { await PushSettings.syncIfNeeded() }
            dismiss()
        }
    }
}
