import Foundation

/// §17: "sum the asleep stages rather than trusting inBed." Samples from
/// the iPhone and the Watch can overlap, so intervals are merged before
/// summing — otherwise one night can read as fourteen hours.
public enum SleepMath {
    public static func asleepHours(_ intervals: [(start: Date, end: Date)]) -> Double {
        let sorted = intervals.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var current: (start: Date, end: Date)?
        for interval in sorted {
            if let open = current, interval.start <= open.end {
                current = (open.start, max(open.end, interval.end))
            } else {
                if let open = current { total += open.end.timeIntervalSince(open.start) }
                current = interval
            }
        }
        if let open = current { total += open.end.timeIntervalSince(open.start) }
        return total / 3600
    }

    public static func label(_ hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
