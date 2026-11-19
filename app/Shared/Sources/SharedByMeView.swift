import SwiftUI

/// Workouts this athlete shared with a code: anyone with the code can open
/// them, so each can be taken back for good.
struct SharedByMeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var workouts: [APIClient.MySharedWorkout]?
    @State private var message: String?
    private let apiClient = APIClient(baseURL: AppConfig.backendBaseURL)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Headline([.strong("Shared workouts."), .soft(" Anyone with the code can open these. Stop sharing and the code stops working.")], size: 30)
                    if let message {
                        Text(message).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                    }
                    if let workouts {
                        if workouts.isEmpty {
                            Text("You haven't shared a workout.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        ForEach(workouts) { workout in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(workout.title).font(.body.weight(.semibold)).foregroundStyle(AppTheme.ink)
                                    Text("\(workout.code) · \(workout.itemCount) exercises")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                                Spacer(minLength: 0)
                                Button("Stop sharing") { Task { await stop(workout) } }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.danger)
                            }
                            .padding(14)
                            .glassSurface(cornerRadius: 16)
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                    }
                }
                .padding(20)
            }
            .appScreen()
            .toolbar { CloseToolbarItem { dismiss() } }
            .task { await load() }
        }
    }

    private func load() async {
        guard let token = try? KeychainTokenStore().read() else {
            workouts = []
            message = "Sign in to see what you shared."
            return
        }
        do {
            workouts = try await apiClient.mySharedWorkouts(sessionToken: token)
        } catch {
            workouts = []
            message = "Couldn't load them — check your connection."
        }
    }

    private func stop(_ workout: APIClient.MySharedWorkout) async {
        guard let token = try? KeychainTokenStore().read() else { return }
        do {
            try await apiClient.stopSharing(code: workout.code, sessionToken: token)
            withAnimation { workouts?.removeAll { $0.code == workout.code } }
        } catch {
            message = "Couldn't stop sharing — try again."
        }
    }
}
