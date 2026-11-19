import SwiftUI

/// §15/§17: "HealthKit permission with the reason stated before the system
/// sheet." Everything here is optional — "Not now" leaves the whole app
/// working, and the check-in simply asks for sleep manually.
struct HealthPermissionView: View {
    var onFinished: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @AppStorage("healthPermissionAsked") private var asked = false
    @State private var isRequesting = false

    var body: some View {
        QuestionStep(
            question: "Connect Apple Health?",
            hint: "Optional. Everything in AthleteOS works without it.",
            buttonTitle: isRequesting ? "Connecting…" : "Continue",
            buttonEnabled: !isRequesting,
            onClose: { finish() },
            tone: .body,
            onContinue: request
        ) {
            VStack(alignment: .leading, spacing: 18) {
                reason("moon.zzz.fill", AuraTone.body.mark, "Sleep",
                       "Reads how long you actually slept, so your morning check-in fills itself in instead of you guessing.")
                reason("heart.fill", AuraTone.body.mark, "Resting heart rate",
                       "A resting heart rate above your normal can mean you're tired or getting sick — it fills in your energy, so the check-in is two taps.")
                reason("figure.run", AuraTone.training.mark, "Workouts",
                       "A run or game your watch recorded lightens the gym that day. Each session you finish is saved to Health, once.")
                reason("waveform.path.ecg", AuraTone.mind.mark, "Your health, in your twin",
                       "Heart-rate variability, activity, VO2 max, temperature and more: only what your watch, band or phone actually records.")
                reason("hand.raised.fill", AppTheme.secondaryText, "Stays private",
                       "Health data stays on your phone and is only used inside the app. Never for ads, never shared, never sold.")
            }
            .cardStyle()

            Button("Not now") { finish() }
                .buttonStyle(.secondary)
        }
    }

    private func reason(_ icon: String, _ tint: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func request() {
        isRequesting = true
        Task {
            await HealthKitManager.shared.requestAuthorization()
            isRequesting = false
            finish()
            await HealthDataRepository.shared.reset()
            HealthSync.startIfAllowed()
        }
    }

    private func finish() {
        asked = true
        onFinished()
        dismiss()
    }
}
