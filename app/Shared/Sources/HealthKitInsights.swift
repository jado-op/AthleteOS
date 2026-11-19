import Foundation
#if canImport(HealthKit)
import HealthKit
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif

/// A point on a workout's GPS route.
public struct RoutePoint: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double
}

/// Health's ways of saying "this changed", for the repository.
public enum HealthDataPart: Hashable, Sendable {
    case metric(HealthMetric)
    case sleep
    case workouts

    public static var all: Set<HealthDataPart> {
        Set(HealthMetric.allCases.map { .metric($0) } + [.sleep, .workouts])
    }
}

// The health insights page's reads (owner, 2026-11-19). Apple Health is the
// only source; every function returns nothing rather than an error when
// Health is unavailable, permission was refused or nothing was recorded.
extension HealthKitManager {

    // MARK: Measurements

    /// One value per day for the last `days` days (sum or average with the
    /// day's low and high), oldest first. Health's statistics merge every
    /// source by the athlete's source priority, so an iPhone and a watch
    /// counting the same steps count them once.
    /// Throws when Health could not be read (the phone is locked, the
    /// database is busy): the caller keeps what it had instead of an empty card.
    public func dailySeries(_ metric: HealthMetric, days: Int, calendar: Calendar = .current) async throws -> HealthSeries? {
        #if canImport(HealthKit)
        guard isAvailable else { return nil }
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return nil }
        let unit = metric.healthKitUnit
        let scale = metric.healthKitScale
        let isSum = metric.aggregation == .sum
        let options: HKStatisticsOptions = isSum ? .cumulativeSum : [.discreteAverage, .discreteMin, .discreteMax]
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: [])
        let store = self.store
        let days: [HealthDay] = try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: metric.quantityType, quantitySamplePredicate: predicate,
                                                    options: options, anchorDate: start, intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, error in
                if let error, !Self.meansNoData(error) {
                    continuation.resume(throwing: error)
                    return
                }
                var result: [HealthDay] = []
                collection?.enumerateStatistics(from: start, to: .now) { statistics, _ in
                    if isSum {
                        if let sum = statistics.sumQuantity() {
                            result.append(HealthDay(date: statistics.startDate, value: sum.doubleValue(for: unit) * scale))
                        }
                    } else if let average = statistics.averageQuantity() {
                        result.append(HealthDay(date: statistics.startDate, value: average.doubleValue(for: unit) * scale,
                                                low: statistics.minimumQuantity().map { $0.doubleValue(for: unit) * scale },
                                                high: statistics.maximumQuantity().map { $0.doubleValue(for: unit) * scale }))
                    }
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
        let latest = await latestSample(metric)
        guard !days.isEmpty || latest != nil else { return nil }
        return HealthSeries(metric: metric, days: days, latest: latest?.value, latestDate: latest?.date, latestSource: latest?.source)
        #else
        return nil
        #endif
    }

    /// The newest sample of a measurement: its value, when it ended, and who wrote it.
    public func latestSample(_ metric: HealthMetric) async -> (value: Double, date: Date, source: String)? {
        #if canImport(HealthKit)
        guard isAvailable else { return nil }
        let unit = metric.healthKitUnit
        let scale = metric.healthKitScale
        let store = self.store
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: metric.quantityType, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (sample.quantity.doubleValue(for: unit) * scale, sample.endDate,
                                                sample.sourceRevision.source.name))
            }
            store.execute(query)
        }
        #else
        return nil
        #endif
    }

    // MARK: Sleep

    /// The last `days` nights, each dated by its morning: hours asleep (every
    /// source merged so overlaps count once, never "in bed"), when sleep
    /// started and ended, and the stages from the device that recorded most.
    public func healthNights(days: Int = 14, calendar: Calendar = .current) async throws -> [HealthNight] {
        #if canImport(HealthKit)
        guard isAvailable else { return [] }
        let today = calendar.startOfDay(for: .now)
        guard let first = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: first.addingTimeInterval(-6 * 3600), end: .now, options: [])
        let store = self.store
        let samples: [SleepStages.Sample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis), predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error, !Self.meansNoData(error) {
                    continuation.resume(throwing: error)
                    return
                }
                let mapped = (samples as? [HKCategorySample] ?? []).compactMap { sample -> SleepStages.Sample? in
                    guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
                    let stage: SleepStages.Stage
                    switch value {
                    case .asleepDeep: stage = .deep
                    case .asleepREM: stage = .rem
                    case .asleepCore: stage = .core
                    case .awake: stage = .awake
                    case .asleepUnspecified: stage = .unspecified
                    default: return nil  // in bed is not sleep
                    }
                    return SleepStages.Sample(start: sample.startDate, end: sample.endDate, stage: stage,
                                              source: sample.sourceRevision.source.bundleIdentifier)
                }
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
        return HealthNights.build(samples, calendar: calendar)
        #else
        return []
        #endif
    }

    // MARK: Workouts

    /// Workouts every other app and device wrote in the last `days` days
    /// (never the ones AthleteOS saved), newest first, with distance, energy,
    /// heart rate and whether a GPS route is stored.
    public func healthWorkouts(days: Int = 30, calendar: Calendar = .current) async throws -> [HealthWorkout] {
        #if canImport(HealthKit)
        guard isAvailable else { return [] }
        let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: .now)) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: [])
        let own = Self.ownBundlePrefix
        let store = self.store
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: 100, sortDescriptors: [sort]) { _, samples, error in
                if let error, !Self.meansNoData(error) {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKWorkout] ?? []).filter { !$0.sourceRevision.source.bundleIdentifier.hasPrefix(own) })
            }
            store.execute(query)
        }
        var result: [HealthWorkout] = []
        for (index, workout) in workouts.enumerated() {
            // Routes only for the ones the page shows (and only on the iPhone).
            #if os(iOS)
            let hasRoute = index < 12 ? await routeCount(for: workout) > 0 : false
            #else
            let hasRoute = false
            #endif
            result.append(Self.healthWorkout(workout, hasRoute: hasRoute))
        }
        return result
        #else
        return []
        #endif
    }

    /// A workout's GPS route, thinned to at most `limit` points. Empty when
    /// none was recorded or location access to it was refused.
    public func route(forWorkout id: String, limit: Int = 600) async -> [RoutePoint] {
        #if canImport(HealthKit) && os(iOS)
        guard isAvailable, let uuid = UUID(uuidString: id) else { return [] }
        let store = self.store
        let workout: HKWorkout? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: HKQuery.predicateForObject(with: uuid),
                                      limit: 1, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: samples?.first as? HKWorkout)
            }
            store.execute(query)
        }
        guard let workout else { return [] }
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workout),
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: samples as? [HKWorkoutRoute] ?? [])
            }
            store.execute(query)
        }
        var points: [RoutePoint] = []
        for route in routes { points += await locations(of: route) }
        guard points.count > limit else { return points }
        let step = Double(points.count) / Double(limit)
        return (0..<limit).map { points[min(points.count - 1, Int(Double($0) * step))] }
        #else
        return []
        #endif
    }

    #if canImport(HealthKit)
    /// "Nothing recorded" is an answer, not a failure.
    static func meansNoData(_ error: Error) -> Bool {
        (error as? HKError)?.code == .errorNoData
    }

    static var ownBundlePrefix: String {
        Bundle.main.bundleIdentifier.map { String($0.split(separator: ".").prefix(3).joined(separator: ".")) } ?? "com.studentathlete.app"
    }

    #if os(iOS)
    private func routeCount(for workout: HKWorkout) async -> Int {
        let store = self.store
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workout),
                                      limit: 1, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: samples?.count ?? 0)
            }
            store.execute(query)
        }
    }

    private func locations(of route: HKWorkoutRoute) async -> [RoutePoint] {
        let store = self.store
        return await withCheckedContinuation { continuation in
            let box = RouteBox()
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                box.points += (locations ?? []).map { RoutePoint(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
                // The handler runs once per batch; answer exactly once.
                if (done || error != nil) && !box.finished {
                    box.finished = true
                    continuation.resume(returning: box.points)
                }
            }
            store.execute(query)
        }
    }
    #endif

    static func healthWorkout(_ workout: HKWorkout, hasRoute: Bool) -> HealthWorkout {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let distanceTypes: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming,
                                                         .distanceDownhillSnowSports]
        let meters = distanceTypes.lazy
            .compactMap { workout.statistics(for: HKQuantityType($0))?.sumQuantity()?.doubleValue(for: .meter()) }
            .first { $0 > 0 }
        return HealthWorkout(
            id: workout.uuid.uuidString, start: workout.startDate, end: workout.endDate,
            activity: activityName(workout.workoutActivityType), source: workout.sourceRevision.source.name,
            averageHeartRate: workout.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: bpm),
            distanceKm: meters.map { $0 / 1000 },
            energyKcal: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
            hasRoute: hasRoute
        )
    }

    /// A short name for the activity ("Run", "Soccer"…).
    static func activityName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: "Run"
        case .walking: "Walk"
        case .hiking: "Hike"
        case .cycling: "Ride"
        case .swimming: "Swim"
        case .rowing: "Row"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Strength training"
        case .highIntensityIntervalTraining: "HIIT"
        case .crossTraining: "Cross training"
        case .coreTraining: "Core"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        case .flexibility: "Mobility"
        case .elliptical: "Elliptical"
        case .stairClimbing, .stairs: "Stairs"
        case .jumpRope: "Jump rope"
        case .soccer: "Soccer"
        case .basketball: "Basketball"
        case .americanFootball: "Football"
        case .volleyball: "Volleyball"
        case .hockey: "Hockey"
        case .tennis: "Tennis"
        case .baseball: "Baseball"
        case .softball: "Softball"
        case .lacrosse: "Lacrosse"
        case .rugby: "Rugby"
        case .handball: "Handball"
        case .badminton: "Badminton"
        case .tableTennis: "Table tennis"
        case .golf: "Golf"
        case .downhillSkiing: "Downhill ski"
        case .crossCountrySkiing: "Cross-country ski"
        case .snowboarding: "Snowboard"
        case .climbing: "Climb"
        case .martialArts: "Martial arts"
        case .boxing, .kickboxing: "Boxing"
        case .wrestling: "Wrestling"
        case .gymnastics: "Gymnastics"
        case .dance, .socialDance, .cardioDance: "Dance"
        case .mixedCardio: "Cardio"
        case .surfingSports: "Surf"
        case .paddleSports: "Paddle"
        default: "Workout"
        }
    }
    #endif

    // MARK: Staying up to date

    #if canImport(HealthKit)
    /// The types whose changes the page and the plan care about, with how
    /// often iOS may wake the app for them (iOS decides the real timing).
    static var observedTypes: [(type: HKSampleType, frequency: HKUpdateFrequency, part: HealthDataPart)] {
        [(HKObjectType.workoutType(), .immediate, .workouts),
         (HKCategoryType(.sleepAnalysis), .hourly, .sleep),
         (HKQuantityType(.restingHeartRate), .hourly, .metric(.restingHeartRate)),
         (HKQuantityType(.heartRateVariabilitySDNN), .hourly, .metric(.heartRateVariability)),
         (HKQuantityType(.stepCount), .hourly, .metric(.steps)),
         (HKQuantityType(.appleExerciseTime), .hourly, .metric(.exerciseMinutes)),
         (HKQuantityType(.appleSleepingWristTemperature), .daily, .metric(.wristTemperature)),
         (HKQuantityType(.vo2Max), .daily, .metric(.vo2Max))]
    }
    #endif

    /// Registers one observer query per watched type (once per launch) and
    /// asks iOS for background delivery. `onChange` runs on HealthKit's queue;
    /// it must call the completion it is handed when its work is done, so iOS
    /// keeps waking the app.
    public func startObserving(_ onChange: @escaping @Sendable (HealthDataPart, @escaping @Sendable () -> Void) -> Void) {
        #if canImport(HealthKit)
        guard isAvailable, !ObserverState.shared.started else { return }
        ObserverState.shared.started = true
        for entry in Self.observedTypes {
            let part = entry.part
            let query = HKObserverQuery(sampleType: entry.type, predicate: nil) { _, completion, error in
                guard error == nil else {
                    completion()
                    return
                }
                let done = CompletionBox(completion)
                onChange(part) { done.call() }
            }
            store.execute(query)
            // Without permission or the entitlement this fails quietly; the
            // observers still deliver while the app is open.
            store.enableBackgroundDelivery(for: entry.type, frequency: entry.frequency) { _, _ in }
        }
        #endif
    }

    /// Workouts added and deleted since the last call (HKAnchoredObjectQuery),
    /// so a watch workout reaches the plan without re-reading everything. The
    /// anchor lives in UserDefaults; the first call returns the last `days`.
    public func workoutChanges(days: Int = 3) async -> (added: [ExternalWorkout], deleted: Set<String>) {
        #if canImport(HealthKit)
        guard isAvailable else { return ([], []) }
        let key = "health.workoutAnchor"
        let anchor = UserDefaults.standard.data(forKey: key).flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: .now)) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: [])
        let own = Self.ownBundlePrefix
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let store = self.store
        let result: (added: [ExternalWorkout], deleted: Set<String>, anchor: HKQueryAnchor?) = await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: HKObjectType.workoutType(), predicate: predicate, anchor: anchor,
                                              limit: HKObjectQueryNoLimit) { _, samples, deleted, newAnchor, _ in
                let added = (samples as? [HKWorkout] ?? [])
                    .filter { !$0.sourceRevision.source.bundleIdentifier.hasPrefix(own) }
                    .map { workout in
                        ExternalWorkout(start: workout.startDate, end: workout.endDate,
                                        activity: HealthKitManager.activityName(workout.workoutActivityType),
                                        averageHeartRate: workout.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: bpm),
                                        source: workout.sourceRevision.source.name, id: workout.uuid.uuidString)
                    }
                continuation.resume(returning: (added, Set((deleted ?? []).map(\.uuid.uuidString)), newAnchor))
            }
            store.execute(query)
        }
        if let newAnchor = result.anchor, let data = try? NSKeyedArchiver.archivedData(withRootObject: newAnchor, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return (result.added, result.deleted)
        #else
        return ([], [])
        #endif
    }
}

#if canImport(HealthKit)
extension HealthMetric {
    var quantityType: HKQuantityType {
        switch self {
        case .exerciseMinutes: HKQuantityType(.appleExerciseTime)
        case .steps: HKQuantityType(.stepCount)
        case .distance: HKQuantityType(.distanceWalkingRunning)
        case .flightsClimbed: HKQuantityType(.flightsClimbed)
        case .activeEnergy: HKQuantityType(.activeEnergyBurned)
        case .restingEnergy: HKQuantityType(.basalEnergyBurned)
        case .restingHeartRate: HKQuantityType(.restingHeartRate)
        case .heartRateVariability: HKQuantityType(.heartRateVariabilitySDNN)
        case .heartRate: HKQuantityType(.heartRate)
        case .walkingHeartRate: HKQuantityType(.walkingHeartRateAverage)
        case .heartRateRecovery: HKQuantityType(.heartRateRecoveryOneMinute)
        case .vo2Max: HKQuantityType(.vo2Max)
        case .bloodOxygen: HKQuantityType(.oxygenSaturation)
        case .respiratoryRate: HKQuantityType(.respiratoryRate)
        case .wristTemperature: HKQuantityType(.appleSleepingWristTemperature)
        case .bodyTemperature: HKQuantityType(.bodyTemperature)
        case .bodyMass: HKQuantityType(.bodyMass)
        }
    }

    /// HealthKit's unit for reading the value `HealthMetric` keeps.
    var healthKitUnit: HKUnit {
        switch self {
        case .exerciseMinutes: HKUnit.minute()
        case .steps, .flightsClimbed: HKUnit.count()
        case .distance: HKUnit.meterUnit(with: .kilo)
        case .activeEnergy, .restingEnergy: HKUnit.kilocalorie()
        case .restingHeartRate, .heartRate, .walkingHeartRate, .heartRateRecovery, .respiratoryRate:
            HKUnit.count().unitDivided(by: HKUnit.minute())
        case .heartRateVariability: HKUnit.secondUnit(with: .milli)
        case .vo2Max: HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: HKUnit.minute()))
        case .bloodOxygen: HKUnit.percent()
        case .wristTemperature, .bodyTemperature: HKUnit.degreeCelsius()
        case .bodyMass: HKUnit.gramUnit(with: .kilo)
        }
    }

    /// Blood oxygen comes as 0…1; it is shown as a percentage.
    var healthKitScale: Double { self == .bloodOxygen ? 100 : 1 }
}

/// Accumulates a route's location batches.
private final class RouteBox: @unchecked Sendable {
    var points: [RoutePoint] = []
    var finished = false
}

/// The observer queries are registered once per launch.
private final class ObserverState: @unchecked Sendable {
    static let shared = ObserverState()
    var started = false
}

/// HealthKit's completion handler, carried across to async work.
final class CompletionBox: @unchecked Sendable {
    private let completion: () -> Void
    private var called = false
    private let lock = NSLock()

    init(_ completion: @escaping () -> Void) { self.completion = completion }

    func call() {
        lock.lock()
        let first = !called
        called = true
        lock.unlock()
        if first { completion() }
    }
}
#endif
