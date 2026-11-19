import SwiftUI

/// Me → Fitbit Air. A Fitbit (Air, Charge, Inspire…) reaches AthleteOS through
/// Apple Health: Google's Health app on the iPhone writes workouts, sleep
/// (by stage), steps and heart rate there, and the twin reads them. No Google
/// account in AthleteOS, nothing through our server.
struct FitbitView: View {
    let sportSlug: String?
    let birthDate: Date
    @Environment(\.dismiss) private var dismiss
    @State private var connected: Bool?
    @State private var lastNight: Double?
    @State private var stages: SleepStages?
    @State private var lastWorkout: ExternalWorkout?
    @State private var working = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Headline([.strong("Fitbit Air."), .soft(" Your band's nights and workouts, in your plan.")], size: 30)
                    statusCard
                    usesCard
                    setupCard
                    Text("AthleteOS reads what Google Health shares with Apple Health. No Google sign-in, and nothing about your band goes to our server.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .containerRelativeFrame(.horizontal)
            }
            .appScreen()
            .toolbar { CloseToolbarItem { dismiss() } }
            .task { await reload() }
        }
    }

    // MARK: Is it arriving?

    private var statusCard: some View {
        AuraCard(.body, focus: UnitPoint(x: 0.85, y: 0.2), radius: 220, padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text(connected == true ? "Connected" : "Not seen yet")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.75))
                if connected == true {
                    if let lastNight {
                        let minutes = Int((lastNight * 60).rounded())
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            BigFigure("\(minutes / 60)", unit: "h", size: 52)
                            BigFigure(String(format: "%02d", minutes % 60), unit: "min", size: 52)
                        }
                        Text("Slept last night, measured by your Fitbit.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink.opacity(0.85))
                    }
                    if let stages { SleepStagesBar(stages: stages).padding(.top, 4) }
                    if let lastWorkout {
                        Text("Last workout: \(lastWorkout.activity), \(lastWorkout.start.formatted(.relative(presentation: .named))).")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if lastNight == nil && lastWorkout == nil {
                        Text("Your Fitbit is sending data. Last night's sleep shows here after your next sync.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(connected == nil ? "Checking…" : "Nothing from your Fitbit in Apple Health yet.")
                        .font(.system(size: 30, weight: .bold))
                        .tracking(-0.8)
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Two switches, below. After that it runs by itself.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink.opacity(0.85))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: What it does

    private var usesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            use("moon.zzz.fill", AuraTone.body.mark, "Your nights, by stage",
                "Deep sleep, REM and how long you slept fill in the morning check-in and the twin.")
            use("heart.fill", AuraTone.training.mark, "Recovery from your heart",
                "Resting heart rate against your own usual tells the twin how recovered you look.")
            use("figure.run", AuraTone.game.mark, "Workouts count",
                "A workout your band picked up lightens the gym that day, and practice logs itself.")
        }
        .cardStyle()
    }

    private func use(_ icon: String, _ tint: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(AppTheme.ink)
                Text(detail).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Setting it up

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set it up once").font(.title3.weight(.semibold)).foregroundStyle(AppTheme.ink)
            step(1, "In the Google Health app, tap your profile, then Connections, Apps and services, Apple Health, and Get started.")
            step(2, "Turn on sleep, heart rate and workouts, and allow Google Health to write them.")
            step(3, "Allow AthleteOS to read them in Apple Health.")
            Button(working ? "Connecting…" : "Allow in Apple Health") {
                working = true
                Task {
                    await HealthKitManager.shared.requestAuthorization()
                    UserDefaults.standard.set(true, forKey: "healthPermissionAsked")
                    await ExternalWorkoutStore.refresh(sportSlug: sportSlug, birthDate: birthDate)
                    await reload()
                    working = false
                }
            }
            .buttonStyle(.secondary)
            .disabled(working || !HealthKitManager.shared.isAvailable)
            Text("Data comes in when the Google Health app syncs with your band. Opening it now and then keeps it fresh.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.secondaryText)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reload() async {
        if DemoData.isEnabled {
            connected = true
            lastNight = 8.1
            stages = SleepStages(deep: 82, rem: 111, core: 293, awake: 24)
            lastWorkout = ExternalWorkout(start: .now.addingTimeInterval(-26 * 3600), end: .now.addingTimeInterval(-24.5 * 3600),
                                          activity: "Soccer", averageHeartRate: 151, source: "Google Health")
            return
        }
        let health = HealthKitManager.shared
        guard health.isAvailable else { connected = false; return }
        let brand = await health.wearableBrand()
        let fitbitWorkouts = ExternalWorkoutStore.recent.filter { $0.device == "Fitbit" }
        connected = brand == "Fitbit" || !fitbitWorkouts.isEmpty
        guard connected == true else { return }
        lastNight = await health.sleepHours(forNightEnding: .now)
        stages = await health.sleepStages(forNightEnding: .now)
        lastWorkout = fitbitWorkouts.first
    }
}
