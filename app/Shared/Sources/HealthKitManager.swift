import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// §17. The app must work fully for someone who refuses every permission,
/// so every call here degrades to "nil / false" rather than throwing at the
/// caller. Nonisolated and Sendable: HealthKit's store is thread-safe, and
/// keeping the async work off the main actor avoids moving non-Sendable
/// HealthKit objects across isolation boundaries.
public final class HealthKitManager: @unchecked Sendable {
    public static let shared = HealthKitManager()

    #if canImport(HealthKit)
    let store = HKHealthStore()
    #endif

    public init() {}

    public var isAvailable: Bool {
        #if canImport(HealthKit)
        HKHealthStore.isHealthDataAvailable()
        #else
        false
        #endif
    }

    /// Shows the system sheet (only ever after the app's own reason-first
    /// screen, HealthPermissionView). Returns whether the request completed;
    /// HealthKit deliberately never reveals whether READ access was granted.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        #if canImport(HealthKit)
        guard isAvailable else { return false }
        let read = Self.readTypes
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    #if canImport(HealthKit)
    /// Everything the app reads: sleep, workouts and their routes, and every
    /// measurement on the health insights page (`HealthMetric`).
    static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKCategoryType(.sleepAnalysis), HKObjectType.workoutType()]
        #if os(iOS)
        types.insert(HKSeriesType.workoutRoute())
        #endif
        for metric in HealthMetric.allCases { types.insert(metric.quantityType) }
        return types
    }
    #endif

    /// Whether asking again would show Apple's sheet — true when something
    /// new is needed (resting heart rate was added for the check-in).
    public func needsAuthorization() async -> Bool {
        #if canImport(HealthKit)
        guard isAvailable else { return false }
        let status = try? await store.statusForAuthorizationRequest(toShare: [HKObjectType.workoutType()], read: Self.readTypes)
        return status == .shouldRequest
        #else
        return false
        #endif
    }

    /// This morning's resting heart rate and the athlete's usual one (the
    /// median of the 4 weeks before). nil without data or permission; no
    /// baseline until there are at least 7 days of it.
    public func restingHeartRate(on day: Date = .now, calendar: Calendar = .current) async -> (today: Double, usual: Double?)? {
        #if canImport(HealthKit)
        await todayAndUsual(HKQuantityType(.restingHeartRate), unit: HKUnit.count().unitDivided(by: .minute()), on: day, calendar: calendar)
        #else
        return nil
        #endif
    }

    /// This morning's heart-rate variability (SDNN, ms — what Apple Watch
    /// records; WHOOP, Oura and others write it too) and the usual one.
    public func heartRateVariability(on day: Date = .now, calendar: Calendar = .current) async -> (today: Double, usual: Double?)? {
        #if canImport(HealthKit)
        await todayAndUsual(HKQuantityType(.heartRateVariabilitySDNN), unit: .secondUnit(with: .milli), on: day, calendar: calendar)
        #else
        return nil
        #endif
    }

    /// One value per day (the day's average) over the last `days` days,
    /// oldest first: the twin's resting heart rate and variability lines.
    public func dailyRestingHeartRate(days: Int = 28) async -> [TwinPoint] {
        #if canImport(HealthKit)
        await dailyAverages(HKQuantityType(.restingHeartRate), unit: HKUnit.count().unitDivided(by: .minute()), days: days)
        #else
        return []
        #endif
    }

    public func dailyVariability(days: Int = 28) async -> [TwinPoint] {
        #if canImport(HealthKit)
        await dailyAverages(HKQuantityType(.heartRateVariabilitySDNN), unit: .secondUnit(with: .milli), days: days)
        #else
        return []
        #endif
    }

    /// Hours asleep for each of the last `days` nights that has data, dated by
    /// the morning; oldest first.
    public func sleepNights(days: Int = 14, now: Date = .now, calendar: Calendar = .current) async -> [TwinPoint] {
        var nights: [TwinPoint] = []
        let today = calendar.startOfDay(for: now)
        for back in (0..<days).reversed() {
            guard let morning = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            if let hours = await sleepHours(forNightEnding: morning, calendar: calendar) {
                nights.append(TwinPoint(date: morning, value: hours))
            }
        }
        return nights
    }

    #if canImport(HealthKit)
    private func dailyAverages(_ type: HKQuantityType, unit: HKUnit, days: Int, calendar: Calendar = .current) async -> [TwinPoint] {
        guard isAvailable else { return [] }
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: [])
        let samples: [(Date, Double)] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample] ?? []).map { ($0.startDate, $0.quantity.doubleValue(for: unit)) })
            }
            store.execute(query)
        }
        var perDay: [Date: [Double]] = [:]
        for (date, value) in samples { perDay[calendar.startOfDay(for: date), default: []].append(value) }
        return perDay.sorted { $0.key < $1.key }.map { TwinPoint(date: $0.key, value: $0.value.reduce(0, +) / Double($0.value.count)) }
    }

    /// One value per day **per device** (the day's average from that source),
    /// so a new watch or a second band never looks like a change in the body
    /// (`HeartSignals` compares one device with itself).
    public func dailyBySource(resting: Bool, days: Int, calendar: Calendar = .current) async -> [HeartNight] {
        guard isAvailable else { return [] }
        let type = resting ? HKQuantityType(.restingHeartRate) : HKQuantityType(.heartRateVariabilitySDNN)
        let unit = resting ? HKUnit.count().unitDivided(by: .minute()) : HKUnit.secondUnit(with: .milli)
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: [])
        let samples: [(Date, String, Double)] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample] ?? []).map {
                    ($0.startDate, $0.sourceRevision.source.bundleIdentifier, $0.quantity.doubleValue(for: unit))
                })
            }
            store.execute(query)
        }
        var perDay: [String: [Double]] = [:]
        var dates: [String: Date] = [:]
        for (date, source, value) in samples {
            let day = calendar.startOfDay(for: date)
            let key = "\(day.timeIntervalSince1970)|\(source)"
            perDay[key, default: []].append(value)
            dates[key] = day
        }
        return perDay.compactMap { key, values -> HeartNight? in
            guard let day = dates[key], let source = key.split(separator: "|", maxSplits: 1).last else { return nil }
            return HeartNight(date: day, value: values.reduce(0, +) / Double(values.count), source: String(source))
        }.sorted { $0.date < $1.date }
    }

    /// Today's latest value and the median of the daily values over the 4
    /// weeks before (from 7 days of data).
    private func todayAndUsual(_ type: HKQuantityType, unit: HKUnit, on day: Date, calendar: Calendar) async -> (today: Double, usual: Double?)? {
        guard isAvailable else { return nil }
        let today = calendar.startOfDay(for: day)
        guard let start = calendar.date(byAdding: .day, value: -28, to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let samples: [(date: Date, bpm: Double)] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let values = (samples as? [HKQuantitySample] ?? []).map { ($0.startDate, $0.quantity.doubleValue(for: unit)) }
                continuation.resume(returning: values.map { (date: $0.0, bpm: $0.1) })
            }
            store.execute(query)
        }
        return RestingHeartRate.summarize(samples, today: today, calendar: calendar)
    }
    #endif

    /// Hours actually asleep in the night ending on `morning` (18:00 the day
    /// before until noon), summing only asleep stages — never `inBed` — and
    /// merging overlapping iPhone/Watch samples. nil when there is no data
    /// or no permission.
    public func sleepHours(forNightEnding morning: Date = .now, calendar: Calendar = .current) async -> Double? {
        #if canImport(HealthKit)
        guard isAvailable else { return nil }
        let day = calendar.startOfDay(for: morning)
        guard
            let start = calendar.date(byAdding: .hour, value: -6, to: day),
            let end = calendar.date(byAdding: .hour, value: 12, to: day)
        else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let asleepValues = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        let intervals: [SleepInterval] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis), predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, _ in
                let asleep = (samples as? [HKCategorySample] ?? [])
                    .filter { asleepValues.contains($0.value) }
                    .map { SleepInterval(start: $0.startDate, end: $0.endDate) }
                continuation.resume(returning: asleep)
            }
            store.execute(query)
        }
        guard !intervals.isEmpty else { return nil }
        let hours = SleepMath.asleepHours(intervals.map { ($0.start, $0.end) })
        return hours > 0 ? hours : nil
        #else
        return nil
        #endif
    }

    /// Last night's sleep by stage (deep, REM, core), from the device that
    /// recorded the most of it. nil without staged data or permission.
    public func sleepStages(forNightEnding morning: Date = .now, calendar: Calendar = .current) async -> SleepStages? {
        #if canImport(HealthKit)
        guard isAvailable else { return nil }
        let day = calendar.startOfDay(for: morning)
        guard
            let start = calendar.date(byAdding: .hour, value: -6, to: day),
            let end = calendar.date(byAdding: .hour, value: 12, to: day)
        else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let samples: [SleepStages.Sample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis), predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, _ in
                let staged = (samples as? [HKCategorySample] ?? []).compactMap { sample -> SleepStages.Sample? in
                    guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
                    let stage: SleepStages.Stage
                    switch value {
                    case .asleepDeep: stage = .deep
                    case .asleepREM: stage = .rem
                    case .asleepCore: stage = .core
                    case .awake: stage = .awake
                    default: return nil
                    }
                    return SleepStages.Sample(start: sample.startDate, end: sample.endDate, stage: stage,
                                              source: sample.sourceRevision.source.bundleIdentifier)
                }
                continuation.resume(returning: staged)
            }
            store.execute(query)
        }
        return SleepStages.from(samples)
        #else
        return nil
        #endif
    }

    /// Workouts other apps and devices wrote (a run on the watch, a WHOOP
    /// session…), never the ones this app saved. Newest first; empty without
    /// data or permission.
    public func externalWorkouts(since start: Date) async -> [ExternalWorkout] {
        #if canImport(HealthKit)
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: [])
        let own = Bundle.main.bundleIdentifier.map { String($0.split(separator: ".").prefix(3).joined(separator: ".")) } ?? "com.studentathlete.app"
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: 50, sortDescriptors: [sort]) { _, samples, _ in
                let workouts = (samples as? [HKWorkout] ?? [])
                    .filter { !$0.sourceRevision.source.bundleIdentifier.hasPrefix(own) }
                    .map { workout in
                        ExternalWorkout(
                            start: workout.startDate, end: workout.endDate,
                            activity: HealthKitManager.activityName(workout.workoutActivityType),
                            averageHeartRate: workout.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: bpm),
                            source: workout.sourceRevision.source.name, id: workout.uuid.uuidString
                        )
                    }
                continuation.resume(returning: workouts)
            }
            store.execute(query)
        }
        #else
        return []
        #endif
    }

    /// Average and highest heart rate between two moments (a finished
    /// session), from a watch or band. nil without data or permission.
    public func heartRate(from start: Date, to end: Date) async -> HeartRateSummary? {
        #if canImport(HealthKit)
        guard isAvailable, end > start else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let values: [Double] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKQuantityType(.heartRate), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample] ?? []).map { $0.quantity.doubleValue(for: bpm) })
            }
            store.execute(query)
        }
        return HeartRateSummary(values)
        #else
        return nil
        #endif
    }

    /// Writes ONE workout for a finished session and returns its UUID, which
    /// the caller stores on `Session.healthKitWorkoutId` so it is never
    /// written twice (§16/§17). Returns the existing id untouched if one is
    /// already recorded.
    public func saveWorkout(start: Date, end: Date, sportSlug: String?, existingId: String?) async -> String? {
        if let existingId { return existingId }
        #if canImport(HealthKit)
        guard isAvailable, end > start else { return nil }
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return nil }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = Self.activityType(for: sportSlug)
        configuration.locationType = .unknown
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.endCollection(at: end)
            let workout = try await builder.finishWorkout()
            return workout?.uuid.uuidString
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    #if canImport(HealthKit)
    /// §16: "the workout type mapped from the sport (.hockey, .soccer,
    /// .traditionalStrengthTraining for gym work)".
    static func activityType(for sportSlug: String?) -> HKWorkoutActivityType {
        switch sportSlug {
        case "soccer": .soccer
        case "football", "flag-football": .americanFootball
        case "basketball", "unified-basketball", "wheelchair-basketball": .basketball
        case "baseball", "beep-baseball": .baseball
        case "softball": .softball
        case "volleyball", "boys-volleyball", "sand-volleyball", "sitting-volleyball": .volleyball
        case "ice-hockey", "inline-hockey", "adapted-floor-hockey", "field-hockey", "field-hockey-goalkeeping": .hockey
        case "lacrosse", "lacrosse-box": .lacrosse
        case "tennis": .tennis
        case "golf", "disc-golf": .golf
        case "swimming-diving", "adapted-swimming", "water-polo": .swimming
        case "cross-country", "track-and-field", "indoor-track-and-field", "unified-track", "para-track", "orienteering": .running
        case "wrestling": .wrestling
        case "gymnastics": .gymnastics
        case "rowing": .rowing
        case "skiing": .downhillSkiing
        case "snowboarding": .snowboarding
        case "fencing": .fencing
        case "badminton": .badminton
        case "table-tennis": .tableTennis
        case "squash": .squash
        case "racquetball": .racquetball
        case "pickleball": .pickleball
        case "team-handball": .handball
        case "rugby": .rugby
        case "archery": .archery
        case "cycling", "mountain-biking", "bmx": .cycling
        case "sailing": .sailing
        case "surfing": .surfingSports
        case "judo": .martialArts
        case "climbing": .climbing
        case "equestrian": .equestrianSports
        case "bowling": .bowling
        case "competitive-dance", "step-team": .socialDance
        case "triathlon", "triathlon-duathlon": .mixedCardio
        default: .traditionalStrengthTraining
        }
    }
    #endif
}

/// A workout from another app or device, as the plan cares about it.
public struct ExternalWorkout: Codable, Sendable, Equatable {
    public var start: Date
    public var end: Date
    public var activity: String
    public var averageHeartRate: Double?
    /// The app or device that recorded it ("Garmin Connect", "Apple Watch"…).
    public var source: String?
    /// The HealthKit sample's UUID (nil in workouts saved before 2026-11-19).
    public var id: String?

    public init(start: Date, end: Date, activity: String, averageHeartRate: Double?, source: String? = nil, id: String? = nil) {
        self.start = start
        self.end = end
        self.activity = activity
        self.averageHeartRate = averageHeartRate
        self.source = source
        self.id = id
    }

    /// The brand to name in a sentence ("Your Garmin saw…"); "watch" when unknown.
    public var device: String {
        WearableBrand.name(fromSource: source) ?? "watch"
    }

    public var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
}

/// Heart rate over a stretch of time.
public struct HeartRateSummary: Sendable, Equatable {
    public let average: Int
    public let max: Int

    public init?(_ values: [Double]) {
        guard !values.isEmpty else { return nil }
        average = Int((values.reduce(0, +) / Double(values.count)).rounded())
        max = Int((values.max() ?? 0).rounded())
    }

    public init(average: Int, max: Int) {
        self.average = average
        self.max = max
    }
}

/// A Sendable pair of dates, so samples can leave HealthKit's callback
/// queue without carrying HealthKit objects across isolation boundaries.
struct SleepInterval: Sendable {
    let start: Date
    let end: Date
}
