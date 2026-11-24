import SwiftData
import SwiftUI

/// Every logged session, newest first, grouped by week — tap one to see
/// every set it contained.
public struct SessionHistoryView: View {
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @Environment(\.dismiss) private var dismiss
    @State private var catalogue = Catalogue()

    public init() {}

    /// §4: free shows the last 30 days; Pro shows everything.
    private var visibleSessions: [Session] {
        guard let cutoff = ProGate.historyCutoff(isPro: ProAccess.isPro) else { return sessions }
        return sessions.filter { $0.startedAt >= cutoff }
    }

    private var weeks: [(start: Date, sessions: [Session])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: visibleSessions) { calendar.dateInterval(of: .weekOfYear, for: $0.startedAt)?.start ?? $0.startedAt }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    // V8: the whole history in one sentence.
                    Headline([.strong(countedNoun(sessions.count, "session")), .soft(", "),
                              .strong("\(sessions.reduce(0) { $0 + $1.minutes }) minutes"), .soft(" of training.")], size: 32)
                        .padding(.bottom, 4)
                    if sessions.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 30))
                                .foregroundStyle(AppTheme.secondaryText)
                            Text("No sessions yet")
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)
                            Text("Start today's session and it lands here the moment you finish.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .cardStyle(padding: 28)
                    }
                    ForEach(weeks, id: \.start) { week in
                        Text("Week of \(week.start.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                            .padding(.top, 8)
                        ForEach(week.sessions) { session in
                            NavigationLink {
                                SessionDetailView(session: session, catalogue: catalogue)
                            } label: {
                                SessionRow(session: session)
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                    if visibleSessions.count < sessions.count {
                        ProLockCard(
                            feature: .fullHistory,
                            title: "\(sessions.count - visibleSessions.count) older sessions",
                            message: "Free shows your last \(ProLimits.freeHistoryDays) days. Nothing is deleted — Pro shows your whole history."
                        )
                        .padding(.top, 8)
                    }
                }
                .padding(20)
            }
            .appScreen()
            .task { catalogue = CatalogueLoader.load(from: AppConfig.packsDirectory()) }
            .toolbar {
                CloseToolbarItem { dismiss() }
            }
        }
    }
}

struct SessionDetailView: View {
    let session: Session
    let catalogue: Catalogue

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

    /// Deletes the workout here, keeps a restore from bringing it back, and
    /// removes the server copy when online (best effort; a restore still skips it).
    private func deleteSession() {
        let clientId = session.clientId
        let wasBackedUp = session.syncedAt != nil
        let context = modelContext
        let doomed = session
        CloudSync.discard(sessionClientId: clientId)
        // Leave the screen first: a view must never draw a deleted model.
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            context.delete(doomed)
            try? context.save()
            guard wasBackedUp, let token = try? KeychainTokenStore().read() else { return }
            try? await APIClient(baseURL: AppConfig.backendBaseURL).deleteSession(clientId: clientId, sessionToken: token)
        }
    }

    private var byItem: [(slug: String, sets: [SetLog])] {
        var order: [String] = []
        var grouped: [String: [SetLog]] = [:]
        for set in session.sets.sorted(by: { $0.setIndex < $1.setIndex }) {
            if grouped[set.itemSlug] == nil { order.append(set.itemSlug) }
            grouped[set.itemSlug, default: []].append(set)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    private func setText(_ set: SetLog) -> String {
        var parts: [String] = []
        if let reps = set.reps { parts.append(countedNoun(reps, "rep")) }
        if let weight = set.weightKg { parts.append(WeightUnit.current.format(kg: weight)) }
        if let seconds = set.seconds { parts.append("\(seconds)s") }
        if let distance = set.distanceM { parts.append("\(Int(distance)) m") }
        if let contacts = set.contacts { parts.append("\(contacts) contacts") }
        return parts.isEmpty ? "Logged" : parts.joined(separator: " · ")
    }

    /// V8: the minutes big on the training (ember) card, sets and effort beside them.
    private var summaryCard: some View {
        AuraCard(.training, focus: UnitPoint(x: 0.22, y: 0.5), radius: 200) {
            HStack(alignment: .lastTextBaseline, spacing: 16) {
                BigFigure(session.minutes > 0 ? "\(session.minutes)" : "—", unit: "min", size: 72)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    summaryLine("\(session.sets.count)", session.sets.count == 1 ? "set" : "sets")
                    summaryLine(session.sessionRPE.map { "\($0)/10" } ?? "—", "effort")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Minutes: \(session.minutes). Sets: \(session.sets.count). Effort: \(session.sessionRPE.map { "\($0) of 10" } ?? "not rated")")
    }

    private func summaryLine(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
                .foregroundStyle(AppTheme.ink)
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.75))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Headline([.strong(session.startedAt.formatted(.dateTime.weekday(.wide).month().day())),
                          .soft(" · " + session.startedAt.formatted(date: .omitted, time: .shortened))], size: 32)
                summaryCard
                if HealthWorkoutInbox.isImported(session) {
                    // From Apple Health or told in Tell AthleteOS: what it was, and that it stays on this phone.
                    VStack(alignment: .leading, spacing: 6) {
                        Text(HealthWorkoutInbox.activity(of: session))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        HStack(spacing: 8) {
                            Image(systemName: HealthWorkoutInbox.isTold(session) ? "text.bubble" : "heart.text.square")
                            Text(HealthWorkoutInbox.isTold(session)
                                 ? (session.healthKitWorkoutId != nil ? "Told AthleteOS · times from Apple Health" : "Told AthleteOS · stays on this phone")
                                 : "From Apple Health · stays on this phone")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.secondaryText)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: session.syncedAt != nil ? "checkmark.icloud.fill" : "icloud.slash")
                        Text(session.syncedAt != nil ? "Backed up" : "Saved on this phone — backs up next time you're online")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(session.syncedAt != nil ? AppTheme.green : AppTheme.secondaryText)
                }

                ForEach(byItem, id: \.slug) { entry in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            ItemThumbnail(item: catalogue.item(entry.slug), size: 48)
                            Text(catalogue.item(entry.slug)?.name ?? displayName(forSlug: entry.slug))
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)
                        }
                        ForEach(Array(entry.sets.enumerated()), id: \.offset) { index, set in
                            HStack {
                                Text("Set \(index + 1)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .frame(width: 60, alignment: .leading)
                                Text(setText(set))
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.ink)
                                Spacer()
                            }
                        }
                    }
                    .cardStyle(padding: 16)
                }

                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label("Delete this workout", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .confirmationDialog("Delete this workout?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive, action: deleteSession)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Its sets leave your history, progress and the twin's analysis. This can't be undone.")
                }
            }
            .padding(20)
        }
        .appScreen()
    }
}
