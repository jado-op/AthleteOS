import Foundation

/// "Your last 7 days" (owner, 2026-11-20): tap the twin and the body stands
/// in the middle, lit by the week's training, with the week's numbers from
/// Apple Health floating around it, each tied to the part of the body it
/// belongs to (sleep to the head, heart to the chest, steps to the legs).
/// Every number is the athlete's own and traceable; never a score.
public enum TwinWeek {
    /// Where a stat's line meets the body.
    public enum Anchor: String, Sendable, CaseIterable {
        case head, chest, arms, core, legs

        /// Height on the figure (0 = top of the head, 1 = feet), for ordering
        /// the bubbles so their lines never cross.
        public var height: Double {
            switch self {
            case .head: 0.07
            case .chest: 0.26
            case .arms: 0.36
            case .core: 0.42
            case .legs: 0.68
            }
        }
    }

    public struct Stat: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let value: String
        public let unit: String
        public let symbol: String
        public let anchor: Anchor
        /// "+0.4 h vs last week" (nil when there's nothing to compare).
        public let change: String?
        /// The last 7 days, oldest first (nil: nothing that day).
        public let days: [Double?]
        public let fromHealth: Bool
    }

    /// One logged session (the app's own, including imported Health workouts).
    public struct Training: Sendable {
        public let date: Date
        public let minutes: Int
        public init(date: Date, minutes: Int) {
            self.date = date
            self.minutes = minutes
        }
    }

    /// The seven days, oldest first, today last.
    public static func days(now: Date, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    /// The week's numbers, most telling first, at most `limit`. Training
    /// always counts (it's the app's own); Health stats only when measured.
    public static func stats(snapshot: HealthSnapshot, training: [Training], now: Date, limit: Int = 6,
                             calendar: Calendar = .current) -> [Stat] {
        let week = days(now: now, calendar: calendar)
        var result: [Stat] = []

        // Sleep: the mornings of the last 7 days.
        let nights = week.map { day in snapshot.nights.first { calendar.isDate($0.morning, inSameDayAs: day) }?.asleepHours }
        let slept = nights.compactMap { $0 }
        if !slept.isEmpty {
            let mean = slept.reduce(0, +) / Double(slept.count)
            let earlierStart = calendar.date(byAdding: .day, value: -7, to: week[0]) ?? week[0]
            let before = snapshot.nights.filter { $0.morning >= earlierStart && $0.morning < week[0] }.map(\.asleepHours)
            let change = before.isEmpty ? nil : signed(mean - before.reduce(0, +) / Double(before.count), unit: "h", decimals: 1)
            result.append(Stat(id: "sleep", title: "Sleep", value: HealthFormat.number(mean, decimals: 1), unit: "h a night",
                               symbol: "moon.zzz.fill", anchor: .head, change: change, days: nights, fromHealth: true))
        }

        func metric(_ metric: HealthMetric, title: String, unit: String? = nil, anchor: Anchor, latestOnly: Bool = false) {
            guard let series = snapshot.series[metric] else { return }
            let summary = HealthSummary(series, now: now, calendar: calendar)
            let daily = week.map { day in series.days.first { calendar.isDate($0.date, inSameDayAs: day) }?.value }
            let value: Double?
            if latestOnly {
                value = series.latest ?? series.days.last?.value
            } else {
                value = summary.week
            }
            guard let value else { return }
            let change = (latestOnly ? nil : summary.previousWeek).map { previous -> String in
                let difference = value - previous
                let shown = metric.format(abs(difference))
                if shown == "0" || shown == "0.0" { return "Same as last week" }
                return (difference > 0 ? "+" : "−") + shown + " " + (unit ?? metric.unit()) + " vs last week"
            }
            result.append(Stat(id: metric.rawValue, title: title, value: metric.format(value), unit: unit ?? metric.unit(),
                               symbol: metric.symbol, anchor: anchor, change: change, days: daily, fromHealth: true))
        }

        metric(.restingHeartRate, title: "Resting heart", anchor: .chest)
        metric(.heartRateVariability, title: "HRV", anchor: .chest)
        metric(.steps, title: "Steps", unit: "a day", anchor: .legs)

        // Training: the app's own sessions (Health workouts included).
        let trainedDays = week.map { day in
            training.filter { calendar.isDate($0.date, inSameDayAs: day) && $0.date <= now }.reduce(0) { $0 + max(0, $1.minutes) }
        }
        let total = trainedDays.reduce(0, +)
        let earlierStart = calendar.date(byAdding: .day, value: -7, to: week[0]) ?? week[0]
        let earlier = training.filter { $0.date >= earlierStart && $0.date < week[0] }.reduce(0) { $0 + max(0, $1.minutes) }
        let sessions = training.filter { $0.date >= week[0] && $0.date <= now }.count
        result.append(Stat(id: "training", title: "Training", value: "\(total)", unit: "min",
                           symbol: "figure.strengthtraining.traditional", anchor: .core,
                           change: earlier == 0 && total == 0 ? nil : signed(Double(total - earlier), unit: "min", decimals: 0),
                           days: trainedDays.map { $0 > 0 ? Double($0) : nil }, fromHealth: false))
        result.append(Stat(id: "sessions", title: "Sessions", value: "\(sessions)", unit: sessions == 1 ? "session" : "sessions",
                           symbol: "calendar", anchor: .arms, change: trainedDays.filter { $0 > 0 }.count == 1 ? "On 1 day" :
                            "On \(trainedDays.filter { $0 > 0 }.count) days",
                           days: week.map { day in
                               let count = training.filter { calendar.isDate($0.date, inSameDayAs: day) && $0.date <= now }.count
                               return count > 0 ? Double(count) : nil
                           }, fromHealth: false))

        metric(.vo2Max, title: "VO2 max", unit: "ml/kg/min", anchor: .chest, latestOnly: true)
        metric(.respiratoryRate, title: "Breathing", anchor: .chest)
        metric(.bloodOxygen, title: "Blood oxygen", anchor: .chest)
        return Array(result.prefix(limit))
    }

    /// "+0.4 h vs last week", "Same as last week".
    static func signed(_ difference: Double, unit: String, decimals: Int) -> String {
        let shown = HealthFormat.number(abs(difference), decimals: decimals)
        if Double(shown.replacingOccurrences(of: ",", with: "")) == 0 { return "Same as last week" }
        return (difference > 0 ? "+" : "−") + shown + " " + unit + " vs last week"
    }

    /// The bubbles in two columns: sorted top to bottom by where their line
    /// meets the body, alternating left and right so no two lines cross.
    public static func columns(_ stats: [Stat]) -> (left: [Stat], right: [Stat]) {
        let sorted = stats.enumerated().sorted {
            $0.element.anchor.height != $1.element.anchor.height ? $0.element.anchor.height < $1.element.anchor.height : $0.offset < $1.offset
        }.map(\.element)
        var left: [Stat] = []
        var right: [Stat] = []
        for (index, stat) in sorted.enumerated() {
            if index % 2 == 0 { left.append(stat) } else { right.append(stat) }
        }
        return (left, right)
    }
}
