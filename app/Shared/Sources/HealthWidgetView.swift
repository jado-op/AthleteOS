import Charts
import MapKit
import SwiftUI

// The health insights widgets (owner, 2026-11-19). V8: a dark plate per
// measurement with its colour's aura behind the number, the athlete's own
// line under it, one plain sentence, tap for the whole story. Every value is
// from Apple Health; a widget only exists when its data does
// (`HealthWidgetRegistry`).

extension HealthMetric: Identifiable {
    public var id: String { rawValue }

    /// The colour of its kind: heart ember, variability magenta, activity
    /// green, sleep and breathing blue, body calm white.
    var tint: Color {
        if self == .heartRateVariability { return AuraTone.mind.mark }
        if self == .respiratoryRate || self == .bloodOxygen { return AuraTone.body.mark }
        switch category {
        case .heart, .recovery: return AuraTone.training.mark
        case .activity: return AuraTone.game.mark
        case .sleep: return AuraTone.body.mark
        case .body: return Color(rgb: 0xC9D2E3)
        }
    }

    /// Shown as a big card with a chart; the rest are tiles.
    var isFeatured: Bool { [.restingHeartRate, .heartRateVariability, .exerciseMinutes, .steps, .heartRate].contains(self) }
}

/// "Updated 08:12" / "Updated yesterday".
enum HealthTime {
    static func updated(_ date: Date?, prefix: String = "Updated", now: Date = .now) -> String? {
        guard let date else { return nil }
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return prefix + " " + date.formatted(date: .omitted, time: .shortened) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return prefix + " yesterday"
        }
        return prefix + " " + date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// The dark plate every health widget sits on, with its colour's aura.
struct HealthPlate<Content: View>: View {
    let tint: Color
    var padding: CGFloat = 18
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    LinearGradient(colors: [Color(rgb: 0x111114), Color(rgb: 0x17171B)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    RadialGradient(colors: [tint.opacity(0.26), tint.opacity(0.05), .clear], center: UnitPoint(x: 0.12, y: 0.2),
                                   startRadius: 0, endRadius: 220)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1) }
    }
}

/// A widget's label row: symbol and name in its colour, "updated" on the right.
struct HealthLabel: View {
    let title: String
    let symbol: String
    let tint: Color
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            if let trailing {
                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - One measurement

/// A featured measurement: the number, four weeks of the athlete's own line
/// (touch to read any day), and what it means against their usual.
struct HealthMetricCard: View {
    let summary: HealthSummary
    let series: HealthSeries
    let open: () -> Void

    @State private var selected: Date?
    private var metric: HealthMetric { summary.metric }

    private var selectedDay: HealthDay? {
        guard let selected else { return nil }
        return series.days.min { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }
    }

    var body: some View {
        HealthPlate(tint: metric.tint) {
            VStack(alignment: .leading, spacing: 12) {
                HealthLabel(title: metric.title, symbol: metric.symbol, tint: metric.tint,
                            trailing: selectedDay.map { $0.date.formatted(.dateTime.weekday(.abbreviated).day()) }
                                ?? HealthTime.updated(summary.currentDate))
                HStack(alignment: .center, spacing: 14) {
                    if let value = selectedDay?.value ?? summary.shownValue {
                        BigFigure(metric.format(value), unit: metric.unit(), size: 46)
                            .animation(.snappy(duration: 0.2), value: selectedDay?.date)
                    }
                    Spacer(minLength: 0)
                }
                HealthChart(series: series, usual: summary.usual, goal: metric.dailyGoal, tint: metric.tint, selected: $selected)
                    .frame(height: 96)
                Text(summary.line())
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.title): \(summary.shownValue.map { "\(metric.format($0)) \(metric.unit())" } ?? "no reading"). \(summary.line())")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "More") { open() }
    }
}

/// A smaller measurement: number, two weeks as a line, one short note.
struct HealthMetricTile: View {
    let summary: HealthSummary
    let series: HealthSeries
    let open: () -> Void

    private var metric: HealthMetric { summary.metric }

    var body: some View {
        Button(action: open) {
            HealthPlate(tint: metric.tint, padding: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(metric.title, systemImage: metric.symbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(metric.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let value = summary.shownValue {
                        BigFigure((metric.showsDeviation && value > 0 ? "+" : "") + metric.format(value), unit: metric.unit(), size: 30)
                    }
                    Sparkline(points: Array(series.days.suffix(14)), tint: metric.tint, bars: metric.aggregation == .sum)
                        .frame(height: 30)
                    Text(HealthNotes.short(summary) ?? HealthTime.updated(summary.currentDate) ?? "")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(metric.title): \(summary.shownValue.map { "\(metric.format($0)) \(metric.unit())" } ?? "no reading"). \(summary.line())")
    }
}

enum HealthNotes {
    /// "3 above usual", "+12 % vs last week", "Your usual".
    static func short(_ summary: HealthSummary) -> String? {
        let metric = summary.metric
        if metric.showsDeviation { return "vs your usual" }
        switch metric.aggregation {
        case .sum:
            guard let week = summary.week, let before = summary.previousWeek, before > 0 else { return nil }
            let change = (week - before) / before
            if abs(change) < 0.05 { return "Like last week" }
            return "\(change > 0 ? "+" : "−")\(Int((abs(change) * 100).rounded())) % vs last week"
        case .average:
            guard let current = summary.current, let usual = summary.usual, usual != 0 else { return nil }
            if abs(current - usual) / abs(usual) < 0.03 { return "Your usual" }
            return "\(metric.format(abs(current - usual))) \(current > usual ? "above" : "below") usual"
        }
    }
}

/// Four weeks (or more) of one measurement: bars for daily totals, a line
/// with its daily range for readings, the usual dashed, touch to read a day.
struct HealthChart: View {
    let series: HealthSeries
    let usual: Double?
    let goal: Double?
    let tint: Color
    @Binding var selected: Date?

    private var metric: HealthMetric { series.metric }
    private var days: [HealthDay] { series.days }

    var body: some View {
        Chart {
            if let reference = goal ?? usual {
                RuleMark(y: .value("Usual", reference))
                    .foregroundStyle(Color.white.opacity(0.28))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                if metric.aggregation == .sum {
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value(metric.title, day.value), width: .ratio(0.62))
                        .foregroundStyle(index == days.count - 1 ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.42)))
                        .cornerRadius(3)
                } else {
                    if let low = day.low, let high = day.high, high > low {
                        AreaMark(x: .value("Day", day.date), yStart: .value("Low", low), yEnd: .value("High", high))
                            .foregroundStyle(tint.opacity(0.12))
                            .interpolationMethod(.monotone)
                    }
                    LineMark(x: .value("Day", day.date), y: .value(metric.title, day.value))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
            }
            if let selected, let day = days.min(by: { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }) {
                if metric.aggregation == .sum {
                    RuleMark(x: .value("Day", day.date, unit: .day))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                } else {
                    RuleMark(x: .value("Day", day.date))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            } else if metric.aggregation == .average, let last = days.last {
                PointMark(x: .value("Day", last.date), y: .value(metric.title, last.value))
                    .foregroundStyle(Color.white)
                    .symbolSize(28)
            }
        }
        .chartXSelection(value: $selected)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(AppTheme.mutedText)
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: yDomain)
        .accessibilityHidden(true)
    }

    private var yDomain: ClosedRange<Double> {
        var values = days.map(\.value) + days.compactMap(\.low) + days.compactMap(\.high)
        if let reference = goal ?? usual { values.append(reference) }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        if metric.aggregation == .sum { return 0...max(high * 1.1, 1) }
        let pad = max((high - low) * 0.2, abs(high) * 0.01, 0.1)
        return (low - pad)...(high + pad)
    }
}

/// A tile's two weeks: a quiet line, or small bars for daily totals.
struct Sparkline: View {
    let points: [HealthDay]
    let tint: Color
    let bars: Bool

    var body: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                if bars {
                    BarMark(x: .value("Day", point.date, unit: .day), y: .value("Value", point.value), width: .ratio(0.55))
                        .foregroundStyle(tint.opacity(index == points.count - 1 ? 1 : 0.4))
                        .cornerRadius(2)
                } else {
                    LineMark(x: .value("Day", point.date), y: .value("Value", point.value))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: domain)
        .accessibilityHidden(true)
    }

    private var domain: ClosedRange<Double> {
        let values = points.map(\.value)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        if bars { return 0...max(high, 1) }
        let pad = max((high - low) * 0.25, abs(high) * 0.005, 0.05)
        return (low - pad)...(high + pad)
    }
}

// MARK: - Recovery

/// The morning in one word, from resting heart rate and HRV against the
/// usual. Not a medical or validated score; the numbers sit under it.
struct HealthRecoveryWidget: View {
    let reading: HealthRecovery.Reading
    let readinessDays: [(date: Date, band: ReadinessBand?)]

    var body: some View {
        AuraCard(.body, focus: UnitPoint(x: 0.85, y: 0.15), radius: 230) {
            VStack(alignment: .leading, spacing: 14) {
                Text("This morning")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.75))
                Text((reading.recovery ?? .learning).word)
                    .font(.system(size: 44, weight: .bold))
                    .tracking(-1.2)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(reading.lines, id: \.self) { line in
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if readinessDays.contains(where: { $0.band != nil }) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How you felt this week")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.ink.opacity(0.7))
                        HStack(spacing: 6) {
                            ForEach(Array(readinessDays.enumerated()), id: \.offset) { _, day in
                                VStack(spacing: 6) {
                                    Capsule()
                                        .fill(day.band.map(TwinTrends.readinessColor) ?? Color.white.opacity(0.15))
                                        .frame(height: 6)
                                    Text(day.date.formatted(.dateTime.weekday(.narrow)))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(AppTheme.ink.opacity(0.7))
                                }
                                .frame(maxWidth: .infinity)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(day.date.formatted(.dateTime.weekday(.wide))): \(day.band.map(TwinTrends.readinessWord) ?? "no check-in")")
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                Text("Against your own usual, not a medical score.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.ink.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Sleep

/// Last night big, its stages, and two weeks of nights.
struct HealthSleepWidget: View {
    let nights: [HealthNight]

    private var now: Date { .now }
    private var lastNight: HealthNight? { nights.last { Calendar.current.isDate($0.morning, inSameDayAs: now) } }

    var body: some View {
        AuraCard(.calm, padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HealthLabel(title: "Sleep", symbol: "moon.zzz.fill", tint: AuraTone.body.mark,
                            trailing: lastNight == nil ? "Last measured" : "Last night")
                if let shown = lastNight ?? nights.last {
                    let minutes = Int((shown.asleepHours * 60).rounded())
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        BigFigure("\(minutes / 60)", unit: "h", size: 56)
                        BigFigure(String(format: "%02d", minutes % 60), unit: "min", size: 56)
                    }
                    if let stages = shown.stages {
                        SleepStagesBar(stages: stages).padding(.bottom, 6)
                    }
                }
                Chart {
                    RuleMark(y: .value("Goal", 8))
                        .foregroundStyle(Color.white.opacity(0.22))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("8 h").font(.caption2).foregroundStyle(AppTheme.mutedText)
                        }
                    ForEach(Array(nights.suffix(14).enumerated()), id: \.offset) { index, night in
                        BarMark(x: .value("Night", night.morning, unit: .day), y: .value("Hours", night.asleepHours), width: .ratio(0.6))
                            .foregroundStyle(index == min(nights.count, 14) - 1
                                             ? AnyShapeStyle(LinearGradient(colors: [Color(rgb: 0x9CC3FF), AuraTone.body.mark],
                                                                            startPoint: .top, endPoint: .bottom))
                                             : AnyShapeStyle(AuraTone.body.mark.opacity(night.asleepHours >= 8 ? 0.7 : 0.38)))
                            .cornerRadius(5)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated)).foregroundStyle(AppTheme.mutedText)
                    }
                }
                .chartYAxis(.hidden)
                .chartYScale(domain: 0...11)
                .frame(height: 110)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sleep each night, the last two weeks")
                if let line = WearableRead.sleepLine(nights.suffix(14).map { TwinPoint(date: $0.morning, value: $0.asleepHours) }) {
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// When sleep starts and ends, night by night: each night a bar from
/// falling asleep to waking, the average times big.
struct HealthSleepScheduleWidget: View {
    let nights: [HealthNight]
    let summary: SleepSchedule.Summary

    private func minutes(_ date: Date, _ morning: Date) -> Double {
        date.timeIntervalSince(Calendar.current.startOfDay(for: morning)) / 60
    }

    var body: some View {
        HealthPlate(tint: AuraTone.body.mark) {
            VStack(alignment: .leading, spacing: 14) {
                HealthLabel(title: "Sleep rhythm", symbol: "bed.double.fill", tint: AuraTone.body.mark, trailing: "\(summary.nights) nights")
                HStack(alignment: .top, spacing: 26) {
                    FigureStat(SleepSchedule.clock(summary.bedtime), label: "Asleep", size: 30)
                    FigureStat(SleepSchedule.clock(summary.wake), label: "Awake", size: 30)
                }
                Chart {
                    ForEach(Array(nights.suffix(14).enumerated()), id: \.offset) { _, night in
                        BarMark(xStart: .value("Asleep", minutes(night.fellAsleep, night.morning)),
                                xEnd: .value("Awake", minutes(night.wokeUp, night.morning)),
                                y: .value("Night", night.morning, unit: .day), height: .ratio(0.55))
                            .foregroundStyle(LinearGradient(colors: [AuraTone.body.mark.opacity(0.45), Color(rgb: 0x9CC3FF)],
                                                            startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(3)
                    }
                    RuleMark(x: .value("Average", summary.bedtime))
                        .foregroundStyle(Color.white.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }
                .chartXAxis {
                    AxisMarks(values: [-180.0, 0.0, 180.0, 360.0, 540.0]) { value in
                        AxisValueLabel {
                            Text(SleepSchedule.clock(value.as(Double.self) ?? 0))
                        }
                        .foregroundStyle(AppTheme.mutedText)
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 130)
                .accessibilityHidden(true)
                Text(SleepSchedule.line(summary))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Last night split by stage: one bar, deep → core → REM, and the minutes
/// under it. Deep is where the body rebuilds; REM where the day's skills settle.
struct SleepStagesBar: View {
    let stages: SleepStages

    private struct Part: Identifiable {
        let label: String
        let minutes: Double
        let color: Color
        var id: String { label }
    }

    private var parts: [Part] {
        [Part(label: "Deep", minutes: stages.deep, color: Color(rgb: 0x3D6BFF)),
         Part(label: "Core", minutes: stages.core, color: AuraTone.body.mark.opacity(0.55)),
         Part(label: "REM", minutes: stages.rem, color: Color(rgb: 0x9CC3FF)),
         Part(label: "Awake", minutes: stages.awake, color: Color.white.opacity(0.28))]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { proxy in
                let shown = parts.filter { $0.minutes > 0 }
                let total = max(1, shown.reduce(0) { $0 + $1.minutes })
                let gaps = CGFloat(max(0, shown.count - 1)) * 3
                HStack(spacing: 3) {
                    ForEach(shown) { part in
                        Capsule()
                            .fill(part.color)
                            .frame(width: max(6, (proxy.size.width - gaps) * part.minutes / total))
                    }
                }
            }
            .frame(height: 10)
            HStack(alignment: .top, spacing: 0) {
                ForEach(parts.filter { $0.minutes > 0 }) { part in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Circle().fill(part.color).frame(width: 7, height: 7)
                            Text(part.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Text(SleepMath.label(part.minutes / 60))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(AppTheme.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last night by stage: deep \(SleepMath.label(stages.deep / 60)), core \(SleepMath.label(stages.core / 60)), REM \(SleepMath.label(stages.rem / 60)), awake \(SleepMath.label(stages.awake / 60))")
    }
}

// MARK: - Workouts

/// Workouts from every app and device in Health, counted once, with an
/// effort word and the route where one was recorded.
struct HealthWorkoutsWidget: View {
    let workouts: [HealthWorkout]
    let age: Int
    let openRoute: (HealthWorkout) -> Void

    private var recent: [HealthWorkout] {
        let start = Calendar.current.date(byAdding: .day, value: -13, to: Calendar.current.startOfDay(for: .now)) ?? .now
        return workouts.filter { $0.start >= start }
    }

    private var weekMinutes: Int {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)) ?? .now
        return workouts.filter { $0.start >= start }.reduce(0) { $0 + $1.minutes }
    }

    var body: some View {
        AuraCard(.training, focus: UnitPoint(x: 0.15, y: 0.1), radius: 200, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Workout minutes, last 7 days")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.8))
                BigFigure("\(weekMinutes)", unit: "min", size: 52)
                VStack(spacing: 0) {
                    ForEach(Array(recent.prefix(6).enumerated()), id: \.element.id) { index, workout in
                        if index > 0 { Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1) }
                        row(workout)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ workout: HealthWorkout) -> some View {
        let effort = WearableLoad.effort(averageHeartRate: workout.averageHeartRate, minutes: workout.minutes, age: age)
        var details = [workout.start.formatted(.dateTime.weekday(.wide)), "\(workout.minutes) min"]
        if let km = workout.distanceKm { details.append("\(HealthMetric.distance.format(km)) \(HealthMetric.distance.unit())") }
        if let bpm = workout.averageHeartRate { details.append("\(Int(bpm.rounded())) bpm") }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.activity)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Text(details.joined(separator: " · "))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(AppTheme.ink.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 8)
            if workout.hasRoute {
                Button { openRoute(workout) } label: {
                    Image(systemName: "map.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.16), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Route of the \(workout.activity.lowercased())")
            }
            Text(Self.effortWord(effort))
                .font(.caption.weight(.bold))
                .foregroundStyle(effort >= 7 ? Color.black : AppTheme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(effort >= 7 ? Color.white : Color.white.opacity(0.16), in: Capsule())
        }
        .padding(.vertical, 10)
    }

    static func effortWord(_ effort: Int) -> String {
        switch effort {
        case ..<5: "Easy"
        case 5...6: "Steady"
        case 7...8: "Hard"
        default: "Very hard"
        }
    }
}

/// One workout's GPS route on a map.
struct HealthRouteSheet: View {
    let workout: HealthWorkout
    @Environment(\.dismiss) private var dismiss
    @State private var points: [RoutePoint]?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Headline([.strong(workout.activity + "."),
                          .soft(" " + workout.start.formatted(.dateTime.weekday(.wide).hour().minute()))], size: 28)
                HStack(spacing: 26) {
                    FigureStat("\(workout.minutes)", unit: "min", label: "Time", size: 30)
                    if let km = workout.distanceKm {
                        FigureStat(HealthMetric.distance.format(km), unit: HealthMetric.distance.unit(), label: "Distance", size: 30)
                    }
                    if let bpm = workout.averageHeartRate {
                        FigureStat("\(Int(bpm.rounded()))", unit: "bpm", label: "Average", size: 30)
                    }
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.white.opacity(0.05))
                    if let points, points.count > 1 {
                        Map(initialPosition: .automatic) {
                            MapPolyline(coordinates: points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                                .stroke(AuraTone.training.mark, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        }
                        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .transition(.opacity)
                    } else if points != nil {
                        Text("No route could be read for this workout.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    } else {
                        ProgressView().tint(AppTheme.ink)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeOut(duration: 0.3), value: points?.count)
                Text("Recorded by \(workout.source). Your route stays on your phone.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedText)
            }
            .padding(20)
            .appScreen()
            .toolbar { CloseToolbarItem { dismiss() } }
            .task {
                if DemoData.isEnabled {
                    points = HealthDemo.route()
                } else {
                    points = await HealthKitManager.shared.route(forWorkout: workout.id)
                }
            }
        }
    }
}

// MARK: - The whole story of one measurement

struct HealthMetricDetail: View {
    let summary: HealthSummary
    let series: HealthSeries
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Date?

    private var metric: HealthMetric { summary.metric }
    private var lowest: Double? { series.days.suffix(28).map { $0.low ?? $0.value }.min() }
    private var highest: Double? { series.days.suffix(28).map { $0.high ?? $0.value }.max() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Headline([.icon(metric.symbol), .strong(" " + metric.title + ".")], size: 30)
                    if let value = summary.shownValue {
                        BigFigure((metric.showsDeviation && value > 0 ? "+" : "") + metric.format(value), unit: metric.unit(), size: 64)
                    }
                    HealthPlate(tint: metric.tint) {
                        HealthChart(series: series, usual: summary.usual, goal: metric.dailyGoal, tint: metric.tint, selected: $selected)
                            .frame(height: 180)
                    }
                    Text(summary.line())
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        if metric.showsDeviation {
                            // Wrist temperature is only ever a difference from the usual.
                            if let week = summary.week, let usual = summary.usual { stat("This week", week - usual, signed: true) }
                            if let before = summary.previousWeek, let usual = summary.usual { stat("Week before", before - usual, signed: true) }
                        } else {
                            if metric.aggregation == .sum, let today = summary.today { stat("Today so far", today) }
                            if let week = summary.week { stat(metric.aggregation == .sum ? "Daily, last 7 days" : "This week", week) }
                            if let before = summary.previousWeek { stat("Week before", before) }
                            if let usual = summary.usual { stat("Your usual", usual) }
                            if let lowest, metric.aggregation == .average { stat("Lowest, 4 weeks", lowest) }
                            if let highest, metric.aggregation == .average { stat("Highest, 4 weeks", highest) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What it is").font(.headline).foregroundStyle(AppTheme.ink)
                        Text(metric.meaning)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .cardStyle()
                    Text(([series.latestSource.map { "Recorded by \($0)" }, HealthTime.updated(summary.currentDate)].compactMap { $0 }
                           + ["From Apple Health, compared only with your own usual, never a diagnosis."]).joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .appScreen()
            .toolbar { CloseToolbarItem { dismiss() } }
        }
    }

    private func stat(_ label: String, _ value: Double, signed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text((signed && metric.format(value) != metric.format(0) && value > 0 ? "+" : "") + metric.format(value))
                    .font(.title2.weight(.light).monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
                Text(metric.unit())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
