import SwiftUI
#if os(iOS)
import AuthenticationServices
#endif

/// Me → Suunto. Two ways in: the Suunto app writes workouts and heart rate
/// to Apple Health (works today, no account), and — when our server holds
/// Suunto partner keys — a direct Suunto account connection.
struct SuuntoView: View {
    let sportSlug: String?
    let birthDate: Date
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    #endif
    @State private var status: SuuntoCloud.Status?
    @State private var working = false
    @State private var message: String?
    @State private var suuntoWorkouts: [ExternalWorkout] = ExternalWorkoutStore.recent.filter(\.isSuunto)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Headline([.strong("Suunto."), .soft(" Your watch's workouts, in your plan.")], size: 30)
                    usesCard
                    healthCard
                    if status?.available == true { accountCard }
                    Text("Suunto doesn't share sleep with Apple Health, so the morning check-in still asks how you slept.")
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
            .task { status = await SuuntoCloud.status() }
        }
    }

    // MARK: What it does

    private var usesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            use("bolt.heart.fill", AuraTone.training.mark, "A hard Suunto workout lightens the gym",
                "A hard run or ride earlier today or last night makes today's gym work lighter.")
            use("sportscourt.fill", AuraTone.body.mark, "Practice logs itself",
                "A Suunto workout at practice time counts as practice, with the effort from your heart rate.")
            use("waveform.path.ecg", AuraTone.body.mark, "Heart rate sets the effort",
                "During an AthleteOS session, your heart rate fills in how hard it was.")
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

    // MARK: Through Apple Health

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Through Apple Health").font(.title3.weight(.semibold)).foregroundStyle(AppTheme.ink)
            if let last = suuntoWorkouts.first {
                Label("Last from Suunto: \(last.activity), \(last.start.formatted(.relative(presentation: .named)))", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.green)
            } else {
                Text("No Suunto workout in Health in the last three days.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
            }
            step(1, "In the Suunto app, open your profile, then Settings, and turn on Apple Health.")
            step(2, "Allow AthleteOS to read workouts and heart rate in Health.")
            Button(working ? "Connecting…" : "Allow in Apple Health") {
                working = true
                Task {
                    await HealthKitManager.shared.requestAuthorization()
                    UserDefaults.standard.set(true, forKey: "healthPermissionAsked")
                    await reloadWorkouts()
                    working = false
                }
            }
            .buttonStyle(.secondary)
            .disabled(working || !HealthKitManager.shared.isAvailable)
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

    // MARK: Suunto account

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Suunto account").font(.title3.weight(.semibold)).foregroundStyle(AppTheme.ink)
            Text(status?.connected == true
                 ? "Connected. Workouts that didn't reach Apple Health come straight from Suunto."
                 : "Connect your Suunto account so workouts arrive even when Apple Health sync is off.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(message).font(.footnote.weight(.semibold)).foregroundStyle(AppTheme.ink)
            }
            if status?.connected == true {
                Button("Disconnect Suunto", role: .destructive) {
                    working = true
                    Task {
                        await SuuntoCloud.disconnect()
                        status = await SuuntoCloud.status()
                        message = "Disconnected."
                        working = false
                    }
                }
                .buttonStyle(.secondary)
                .disabled(working)
            } else {
                Button(working ? "Opening Suunto…" : "Connect Suunto") { connect() }
                    .buttonStyle(.primary)
                    .disabled(working)
            }
            Text("Our server keeps only the connection key, never your workouts. Disconnect any time.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .cardStyle()
    }

    private func connect() {
        #if os(iOS)
        working = true
        message = nil
        Task {
            defer { working = false }
            guard let url = await SuuntoCloud.connectURL() else {
                message = "Couldn't reach Suunto. Try again in a moment."
                return
            }
            do {
                let callback = try await webAuthenticationSession.authenticate(using: url, callbackURLScheme: "athleteos")
                switch SuuntoCloud.result(from: callback) {
                case .connected:
                    SuuntoCloud.isConnected = true
                    message = "Connected."
                    await reloadWorkouts()
                case .cancelled: message = nil
                case .failed: message = "Suunto didn't connect. Try again in a moment."
                }
            } catch {
                message = nil
            }
            status = await SuuntoCloud.status()
        }
        #endif
    }

    private func reloadWorkouts() async {
        await ExternalWorkoutStore.refresh(sportSlug: sportSlug, birthDate: birthDate)
        suuntoWorkouts = ExternalWorkoutStore.recent.filter(\.isSuunto)
    }
}
