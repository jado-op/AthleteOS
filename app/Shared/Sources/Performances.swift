import Foundation

/// A performance the twin holds: a best and its history. Lifts and tests come
/// in by themselves (logged sets, Performances → Tests); anything else the
/// athlete adds by hand (CustomPerformance).
public struct PerformanceRecord: Sendable, Hashable, Identifiable {
    public enum Source: Sendable, Hashable {
        case lift(String)
        case test(String)
        case custom(String)
    }

    public var id: String
    public var name: String
    /// "kg" (shown in the athlete's own unit), "s", "cm", "reps", or the athlete's own.
    public var unit: String
    public var higherIsBetter: Bool
    /// The best result per day, oldest first.
    public var history: [TwinPoint]
    public var source: Source

    public var best: TwinPoint? {
        higherIsBetter ? history.max { $0.value < $1.value } : history.min { $0.value < $1.value }
    }

    public var latest: TwinPoint? { history.last }

    /// Change of the best against the best before `since` (positive = better).
    public func improvement(since: Date) -> Double? {
        let before = history.filter { $0.date < since }
        guard let best, !before.isEmpty else { return nil }
        let old = higherIsBetter ? before.map(\.value).max() ?? 0 : before.map(\.value).min() ?? 0
        guard old != 0 else { return nil }
        return higherIsBetter ? best.value - old : old - best.value
    }
}

public enum Performances {
    /// Lifts the twin tracks by itself, by catalogue slug.
    public static let lifts: [String: String] = [
        "bench-press": "Bench press", "dumbbell-bench-press": "Dumbbell bench press",
        "barbell-back-squat": "Back squat", "barbell-front-squat": "Front squat", "goblet-squat": "Goblet squat",
        "barbell-deadlift": "Deadlift", "trap-bar-deadlift": "Trap-bar deadlift", "romanian-deadlift": "Romanian deadlift",
        "hip-thrust": "Hip thrust", "bulgarian-split-squat": "Bulgarian split squat", "hang-power-clean": "Hang power clean",
        "overhead-press-dumbbell": "Overhead press",
    ]

    public static func records(lifts: [TwinInput.Lift], tests: [TwinInput.Test], custom: [CustomPerformance],
                               calendar: Calendar = .current) -> [PerformanceRecord] {
        var out: [PerformanceRecord] = []
        for (slug, name) in Self.lifts.sorted(by: { $0.value < $1.value }) {
            let sets = lifts.filter { $0.slug == slug && $0.weightKg > 0 }
            guard !sets.isEmpty else { continue }
            let history = Dictionary(grouping: sets) { calendar.startOfDay(for: $0.date) }
                .map { TwinPoint(date: $0.key, value: $0.value.map(\.weightKg).max() ?? 0) }
                .sorted { $0.date < $1.date }
            out.append(PerformanceRecord(id: "lift.\(slug)", name: name, unit: "kg", higherIsBetter: true, history: history, source: .lift(slug)))
        }
        for (id, results) in Dictionary(grouping: tests, by: \.testID).sorted(by: { $0.key < $1.key }) {
            guard let first = results.first else { continue }
            let history = Dictionary(grouping: results) { calendar.startOfDay(for: $0.date) }
                .map { TwinPoint(date: $0.key, value: first.higherIsBetter ? $0.value.map(\.value).max() ?? 0 : $0.value.map(\.value).min() ?? 0) }
                .sorted { $0.date < $1.date }
            out.append(PerformanceRecord(id: "test.\(id)", name: first.name, unit: first.unit.isEmpty ? unit(forTest: id) : first.unit, higherIsBetter: first.higherIsBetter,
                                         history: history, source: .test(id)))
        }
        for item in custom {
            let history = item.entries.sorted { $0.date < $1.date }.map { TwinPoint(date: $0.date, value: $0.value) }
            out.append(PerformanceRecord(id: "custom.\(item.id)", name: item.name, unit: item.unit, higherIsBetter: item.higherIsBetter,
                                         history: history, source: .custom(item.id)))
        }
        return out
    }

    static func unit(forTest id: String) -> String {
        if id.contains("sprint") || id == "plank" { return "s" }
        if id == "jump" { return "cm" }
        if id == "pushups" { return "reps" }
        return ""
    }

    /// A number as the athlete reads it: "4.21", "105", "17.5".
    public static func number(_ value: Double, unit: String) -> String {
        if unit == "s" { return String(format: "%.2f", value) }
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }
}
