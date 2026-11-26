import SwiftData
import SwiftUI

struct LiveSessionLaunch: Identifiable {
    let id = UUID()
    let planned: GeneratedSession?
    var kind: WorkoutKind? = nil
    /// An interrupted workout to carry on (app closed, phone died).
    var resuming: Session? = nil
}

/// One logged session as a list card.
struct SessionRow: View {
    let session: Session

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: HealthWorkoutInbox.isTold(session) ? "text.bubble" : session.source == .watch ? "applewatch" : "figure.strengthtraining.traditional")
                .font(.title2)
                .foregroundStyle(AppTheme.ink)
                .frame(width: 64, height: 64)
                .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.startedAt.formatted(.dateTime.weekday(.wide).month().day()))
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                if session.notes != nil, HealthWorkoutInbox.isImported(session) {
                    // A workout from Health or told in Tell AthleteOS: what it was.
                    Text(HealthWorkoutInbox.activity(of: session))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                }
                HStack(spacing: 10) {
                    if session.minutes > 0 { Label("\(session.minutes) min", systemImage: "clock") }
                    if !session.sets.isEmpty || !HealthWorkoutInbox.isImported(session) {
                        Label("\(countedNoun(session.sets.count, "set")) done", systemImage: "list.bullet")
                    }
                    if let rpe = session.sessionRPE {
                        Label("Effort \(rpe)/10", systemImage: "flame")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.secondaryText)
                .labelStyle(CompactLabelStyle())
            }
        }
        .cardStyle(padding: 12)
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

