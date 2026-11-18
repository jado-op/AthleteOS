import Foundation
import SwiftData

/// M5: starting, logging and finishing a session is pure local SwiftData
/// writes — instant and fully offline by construction (§3: "the UI never
/// blocks on the network... an athlete who is offline for a fortnight loses
/// nothing"). Syncing (`SyncQueue`) is a separate, later step, never a
/// precondition for any of this to work.
@MainActor
public struct SessionLogger {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    public func startSession(
        athlete: Athlete, source: SessionSource = .phone, plannedSession: PlannedSession? = nil
    ) throws -> Session {
        let session = Session(startedAt: .now, source: source, athlete: athlete, plannedSession: plannedSession)
        modelContext.insert(session)
        try modelContext.save()
        return session
    }

    @discardableResult
    public func logSet(
        session: Session, itemSlug: String, setIndex: Int, reps: Int? = nil, weightKg: Double? = nil,
        seconds: Int? = nil, distanceM: Double? = nil, contacts: Int? = nil, side: String? = nil
    ) throws -> SetLog {
        let set = SetLog(
            itemSlug: itemSlug, setIndex: setIndex, reps: reps, weightKg: weightKg, seconds: seconds,
            distanceM: distanceM, contacts: contacts, side: side, session: session
        )
        modelContext.insert(set)
        // Changed since its last upload: send it again (the server upserts by clientId).
        session.syncedAt = nil
        try modelContext.save()
        return set
    }

    /// Workouts left open (a crash, a force-quit, a dead phone), after six
    /// hours: without a set they're removed (never "training"); with sets
    /// they're closed as they were, so the work counts and gets backed up.
    public func removeAbandoned(now: Date = .now) {
        let cutoff = now.addingTimeInterval(-6 * 3600)
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.endedAt == nil && $0.startedAt < cutoff })
        guard let open = try? modelContext.fetch(descriptor) else { return }
        for session in open {
            if session.sets.isEmpty { modelContext.delete(session) } else { try? close(session) }
        }
        try? modelContext.save()
    }

    /// Closes an interrupted workout without the effort question: about three
    /// minutes a set, at most 90 minutes.
    public func close(_ session: Session) throws {
        let minutes = min(90, max(5, session.sets.count * 3))
        session.endedAt = session.startedAt.addingTimeInterval(Double(minutes) * 60)
        session.minutes = minutes
        session.syncedAt = nil
        try modelContext.save()
    }

    /// §15: "It ends with the single RPE question and nothing else."
    /// `minutes` is derived from the actual elapsed wall-clock time rather
    /// than asked for, since the athlete already told the app when they
    /// started.
    public func finishSession(_ session: Session, sessionRPE: Int) throws {
        let endedAt = Date.now
        session.endedAt = endedAt
        session.sessionRPE = sessionRPE
        session.minutes = max(0, Int(endedAt.timeIntervalSince(session.startedAt) / 60))
        session.syncedAt = nil
        try modelContext.save()
    }
}
