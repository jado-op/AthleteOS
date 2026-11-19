import Foundation

/// The one place the app gets Apple Health data for the health insights
/// page (owner, 2026-11-19). It keeps the last snapshot in memory only
/// (Health data never goes to disk or our server from here), refreshes only
/// the parts HealthKit said changed, and lets overlapping requests share one
/// refresh instead of querying twice.
public actor HealthDataRepository {
    public static let shared = HealthDataRepository()

    /// Posted on the main queue when Health reports new or deleted samples.
    public static let didChange = Notification.Name("HealthDataRepository.didChange")

    /// How long a full snapshot is trusted when nothing reported a change.
    static let maxAge: TimeInterval = 10 * 60

    private let health: HealthKitManager
    private var cached: HealthSnapshot?
    private var cachedAt: Date?
    private var dirty: Set<HealthDataPart> = HealthDataPart.all
    private var refreshing: Task<HealthSnapshot, Never>?

    public init(health: HealthKitManager = .shared) {
        self.health = health
    }

    /// The current picture: from memory when fresh, otherwise re-read, only
    /// the changed parts when there is a recent snapshot to update.
    public func snapshot(force: Bool = false) async -> HealthSnapshot {
        if let refreshing { return await refreshing.value }
        let stale = cachedAt.map { Date.now.timeIntervalSince($0) > Self.maxAge } ?? true
        if !force, !stale, dirty.isEmpty, let cached { return cached }
        let parts = force || stale || cached == nil ? HealthDataPart.all : dirty
        dirty.removeAll()
        let base = force || stale ? nil : cached
        let health = self.health
        let task = Task { await Self.read(parts, into: base, health: health) }
        refreshing = task
        let result = await task.value
        refreshing = nil
        cached = result
        if parts == HealthDataPart.all { cachedAt = .now }
        return result
    }

    /// HealthKit said something changed: the next `snapshot()` re-reads it.
    public func markChanged(_ part: HealthDataPart) {
        dirty.insert(part)
        Task { @MainActor in NotificationCenter.default.post(name: Self.didChange, object: nil) }
    }

    /// Forget everything (permission changed, account deleted).
    public func reset() {
        cached = nil
        cachedAt = nil
        dirty = HealthDataPart.all
    }

    /// Reads the parts asked for, all at once, into the previous snapshot.
    private static func read(_ parts: Set<HealthDataPart>, into base: HealthSnapshot?, health: HealthKitManager) async -> HealthSnapshot {
        guard health.isAvailable else { return .empty }
        var series = base?.series ?? [:]
        var nights = base?.nights ?? []
        var workouts = base?.workouts ?? []
        let metrics = HealthMetric.allCases.filter { parts.contains(.metric($0)) }
        await withTaskGroup(of: (HealthMetric, HealthSeries?).self) { group in
            for metric in metrics {
                // Sparse measurements (VO2 max, weight) look further back.
                let days = max(28, metric.freshnessDays)
                group.addTask {
                    let read = await health.dailySeries(metric, days: days)
                    return (metric, read)
                }
            }
            for await (metric, read) in group { series[metric] = read }
        }
        if parts.contains(.sleep) { nights = await health.healthNights(days: 14) }
        if parts.contains(.workouts) { workouts = await health.healthWorkouts(days: 30) }
        return HealthSnapshot(series: series, nights: nights, workouts: workouts, fetchedAt: .now)
    }
}

/// Keeping Health current while the app runs and, where iOS allows, in the
/// background: observer queries with background delivery, plus an anchored
/// query for workouts so a watch workout reaches the plan.
public enum HealthSync {
    /// Starts once per launch, and only after the athlete was asked for
    /// Health (observing before that would ask nothing and find nothing).
    @MainActor
    public static func startIfAllowed() {
        guard UserDefaults.standard.bool(forKey: "healthPermissionAsked"), !DemoData.isEnabled else { return }
        HealthKitManager.shared.startObserving { part, done in
            Task {
                await HealthDataRepository.shared.markChanged(part)
                if part == .workouts { await updateWorkouts() }
                done()
            }
        }
    }

    /// Workouts added or deleted since last time, merged into the plan's
    /// recent workouts (`ExternalWorkoutStore`) without re-reading them all.
    public static func updateWorkouts(now: Date = .now) async {
        let changes = await HealthKitManager.shared.workoutChanges()
        guard !changes.added.isEmpty || !changes.deleted.isEmpty else { return }
        await MainActor.run {
            let cutoff = Calendar.current.date(byAdding: .day, value: -3, to: Calendar.current.startOfDay(for: now)) ?? now
            var recent = ExternalWorkoutStore.recent.filter { workout in
                guard let id = workout.id else { return true }
                return !changes.deleted.contains(id)
            }
            for workout in changes.added
            where !recent.contains(where: { ($0.id != nil && $0.id == workout.id) || abs($0.start.timeIntervalSince(workout.start)) < 180 }) {
                recent.append(workout)
            }
            ExternalWorkoutStore.recent = recent.filter { $0.start >= cutoff }.sorted { $0.start > $1.start }
        }
    }
}
