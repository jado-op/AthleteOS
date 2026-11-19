import Charts
import SwiftUI

// The twin's "What your watch sees" (owner, 2026-11-19): as soon as a watch
// or band delivers sleep, heart rate or workouts, the twin opens with this.
// V8: one big word up top (how recovered you look), then one card per
// signal, each with the aura behind its number and the athlete's own line.
// Numbers are the athlete's own and always compared with their own usual.

/// Health and a connected Suunto account, put together for the twin.
enum WearableSignalsLoader {
    @MainActor
    static func load(now: Date = .now, calendar: Calendar = .current) async -> (signals: WearableSignals, workouts: [ExternalWorkout]) {
        if DemoData.isEnabled { return demo(now: now, calendar: calendar) }
        let health = HealthKitManager.shared
        var sleep = health.isAvailable ? await health.sleepNights(days: 14, now: now, calendar: calendar) : []
        var heartRate = await health.dailyRestingHeartRate(days: 28)
        var variability = await health.dailyVariability(days: 28)
        var kind = WearableSignals.HeartRateKind.resting

        // Suunto doesn't write sleep or heart rate to Health; its own account fills the gaps.
        let suunto = await SuuntoCloud.nights(days: 28)
        if !suunto.isEmpty {
            let today = calendar.startOfDay(for: now)
            let twoWeeks = calendar.date(byAdding: .day, value: -13, to: today) ?? today
            let known = Set(sleep.map { calendar.startOfDay(for: $0.date) })
            for night in suunto where night.end >= twoWeeks && !known.contains(calendar.startOfDay(for: night.end)) {
                sleep.append(TwinPoint(date: calendar.startOfDay(for: night.end), value: night.hours))
            }
            sleep.sort { $0.date < $1.date }
            if heartRate.isEmpty {
                heartRate = suunto.compactMap { night in night.lowestHeartRate.map { TwinPoint(date: calendar.startOfDay(for: night.end), value: $0) } }
                kind = .lowestAsleep
            }
            if variability.isEmpty {
                variability = suunto.compactMap { night in night.variability.map { TwinPoint(date: calendar.startOfDay(for: night.end), value: $0) } }
            }
        }

        // This week's workouts from the watch (Health and Suunto, no duplicates).
        let weekStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        var workouts = health.isAvailable ? await health.externalWorkouts(since: weekStart) : []
        for cloud in await SuuntoCloud.workouts(days: 7)
        where !workouts.contains(where: { abs($0.start.timeIntervalSince(cloud.start)) < 180 }) {
            workouts.append(cloud)
        }
        workouts.sort { $0.start > $1.start }

        // Name the device: Suunto's own account, else the brand behind the
        // week's workouts, else whoever wrote last night's sleep or heart rate
        // (a Fitbit Air syncs through Google Health and may log no workout).
        let named = workouts.map(\.device).first { $0 != "watch" }
        let fromHealth = health.isAvailable ? await health.wearableBrand() : nil
        let device = SuuntoCloud.isConnected ? "Suunto" : (named ?? fromHealth ?? "watch")
        let stages = health.isAvailable ? await health.sleepStages(forNightEnding: now, calendar: calendar) : nil
        let signals = WearableSignals(sleep: sleep, heartRate: heartRate, variability: variability, heartRateKind: kind,
                                      device: device, lastNightStages: stages)
        return (signals, workouts)
    }
}

extension WearableSignalsLoader {
    /// Screenshots: `-demoWearable fitbit` shows a Fitbit Air athlete instead of a Suunto one.
    static var demoBrand: String {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-demoWearable"), args.indices.contains(index + 1) else { return "Suunto" }
        return args[index + 1].lowercased() == "fitbit" ? "Fitbit" : "Suunto"
    }

    /// Screenshots (`-demoData`): a Suunto (or Fitbit Air) athlete's last weeks.
    static func demo(now: Date, calendar: Calendar) -> (signals: WearableSignals, workouts: [ExternalWorkout]) {
        let brand = demoBrand
        let today = calendar.startOfDay(for: now)
        func day(_ back: Int) -> Date { calendar.date(byAdding: .day, value: -back, to: today) ?? today }
        let hours: [Double] = [7.2, 8.4, 6.9, 7.8, 8.6, 9.1, 7.4, 6.6, 8.2, 8.9, 7.7, 8.3, 7.1, 8.1]
        let sleep = hours.enumerated().map { TwinPoint(date: day(hours.count - 1 - $0.offset), value: $0.element) }
        let heart = (0..<28).map { back -> TwinPoint in
            TwinPoint(date: day(27 - back), value: 53 + 1.6 * sin(Double(back) * 0.45) + Double((back * 7) % 3) * 0.6 - (back == 27 ? 2 : 0))
        }
        let hrv = (0..<28).map { back -> TwinPoint in
            TwinPoint(date: day(27 - back), value: 64 + 4 * sin(Double(back) * 0.38 + 1) + Double((back * 11) % 3) * 1.2 + (back == 27 ? 5 : 0))
        }
        func workout(_ back: Int, hour: Double, minutes: Int, _ activity: String, _ bpm: Double) -> ExternalWorkout {
            let start = day(back).addingTimeInterval(hour * 3600)
            return ExternalWorkout(start: start, end: start.addingTimeInterval(Double(minutes) * 60), activity: activity,
                                   averageHeartRate: bpm, source: brand == "Fitbit" ? "Google Health" : "Suunto")
        }
        if brand == "Fitbit" {
            // A band: resting heart rate from Health, sleep by stage, auto-detected workouts.
            let workouts = [workout(1, hour: 17, minutes: 88, "Soccer", 151), workout(2, hour: 7, minutes: 31, "Run", 162),
                            workout(4, hour: 16, minutes: 55, "Strength training", 118)]
            let stages = SleepStages(deep: 82, rem: 111, core: 293, awake: 24)
            return (WearableSignals(sleep: sleep, heartRate: heart.map { TwinPoint(date: $0.date, value: $0.value + 5) }, variability: hrv,
                                    heartRateKind: .resting, device: "Fitbit", lastNightStages: stages), workouts)
        }
        let workouts = [workout(1, hour: 16, minutes: 95, "Downhill ski", 148), workout(2, hour: 7, minutes: 42, "Run", 168),
                        workout(4, hour: 17, minutes: 60, "Gym", 121), workout(5, hour: 8, minutes: 35, "Run", 139)]
        return (WearableSignals(sleep: sleep, heartRate: heart, variability: hrv, heartRateKind: .lowestAsleep, device: "Suunto"), workouts)
    }
}

/// The section itself.
struct WatchSignalsSection: View {
    let signals: WearableSignals
    let workouts: [ExternalWorkout]
    let readinessDays: [(date: Date, band: ReadinessBand?)]
    let age: Int

    private var now: Date { .now }
    private var heartReading: SignalReading? { WearableRead.reading(signals.heartRate, now: now) }
    private var variabilityReading: SignalReading? { WearableRead.reading(signals.variability, now: now) }
    private var recovery: WearableRead.Recovery? { WearableRead.recovery(heartRate: heartReading, variability: variabilityReading) }
    private var lastNight: TwinPoint? { signals.sleep.last { Calendar.current.isDate($0.date, inSameDayAs: now) } }
    private var deviceName: String { signals.device == "watch" ? "watch" : signals.device }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Headline([.soft("What your "), .strong(deviceName), .soft(" sees.")], size: 30)
                .padding(.bottom, 4)
            // Workouts alone (Suunto through Health writes no sleep or resting heart rate): no morning word.
            if signals.hasData { recoveryCard }
            if !signals.sleep.isEmpty { sleepCard }
            if !signals.heartRate.isEmpty || !signals.variability.isEmpty {
                HStack(spacing: 12) {
                    if !signals.heartRate.isEmpty {
                        SignalTile(label: signals.heartRateKind == .resting ? "Resting heart rate" : "Lowest asleep",
                                   unit: "bpm", series: signals.heartRate, reading: heartReading, tint: AuraTone.training.mark)
                    }
                    if !signals.variability.isEmpty {
                        SignalTile(label: "Variability", unit: "ms", series: signals.variability, reading: variabilityReading,
                                   tint: AuraTone.mind.mark)
                    }
                }
                .id("watch-tiles")
            }
            if !workouts.isEmpty { workoutsCard }
            Text("Measured by your \(deviceName). Compared only with your own usual, never with anyone else, never a score.")
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Recovery: one word, the numbers behind it, the week's mornings

    private var recoveryCard: some View {
        AuraCard(.body, focus: UnitPoint(x: 0.85, y: 0.15), radius: 230) {
            VStack(alignment: .leading, spacing: 14) {
                Text("This morning")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.75))
                Text((recovery ?? .learning).word)
                    .font(.system(size: 44, weight: .bold))
                    .tracking(-1.2)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(recoveryLines, id: \.self) { line in
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var recoveryLines: [String] {
        var lines: [String] = []
        if let heartReading { lines.append(WearableRead.heartRateLine(heartReading, kind: signals.heartRateKind)) }
        if let variabilityReading { lines.append(WearableRead.variabilityLine(variabilityReading)) }
        if let lastNight { lines.append("Slept \(SleepMath.label(lastNight.value)).") }
        if lines.isEmpty || recovery == .learning || recovery == nil {
            lines.append("After a week of nights your \(deviceName) can compare each morning with your usual.")
        }
        return lines
    }

    // MARK: Sleep: last night big, two weeks of nights below

    private var sleepCard: some View {
        AuraCard(.calm, padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Sleep", systemImage: "moon.zzz.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AuraTone.body.mark)
                    Spacer()
                    Text(lastNight == nil ? "Last measured" : "Last night")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                let shown = lastNight ?? signals.sleep.last
                if let shown {
                    let minutes = Int((shown.value * 60).rounded())
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        BigFigure("\(minutes / 60)", unit: "h", size: 56)
                        BigFigure(String(format: "%02d", minutes % 60), unit: "min", size: 56)
                    }
                }
                if let stages = signals.lastNightStages, lastNight != nil {
                    SleepStagesBar(stages: stages)
                        .padding(.bottom, 6)
                }
                Chart {
                    RuleMark(y: .value("Goal", 8))
                        .foregroundStyle(Color.white.opacity(0.22))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("8 h").font(.caption2).foregroundStyle(AppTheme.mutedText)
                        }
                    ForEach(Array(signals.sleep.enumerated()), id: \.offset) { index, night in
                        BarMark(x: .value("Night", night.date, unit: .day), y: .value("Hours", night.value), width: .ratio(0.6))
                            .foregroundStyle(index == signals.sleep.count - 1
                                             ? AnyShapeStyle(LinearGradient(colors: [Color(rgb: 0x9CC3FF), AuraTone.body.mark], startPoint: .top, endPoint: .bottom))
                                             : AnyShapeStyle(AuraTone.body.mark.opacity(night.value >= 8 ? 0.7 : 0.38)))
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
                .frame(height: 120)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sleep each night, the last two weeks")
                if let line = WearableRead.sleepLine(signals.sleep) {
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Workouts the watch recorded this week

    private var weekMinutes: Int { workouts.reduce(0) { $0 + $1.minutes } }

    private var workoutsCard: some View {
        AuraCard(.training, focus: UnitPoint(x: 0.15, y: 0.1), radius: 200, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("On your \(deviceName) this week")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.8))
                BigFigure("\(weekMinutes)", unit: "min", size: 52)
                VStack(spacing: 0) {
                    ForEach(Array(workouts.prefix(6).enumerated()), id: \.offset) { index, workout in
                        if index > 0 { Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1) }
                        workoutRow(workout)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func workoutRow(_ workout: ExternalWorkout) -> some View {
        let effort = WearableLoad.effort(averageHeartRate: workout.averageHeartRate, minutes: workout.minutes, age: age)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.activity)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Text(workout.start.formatted(.dateTime.weekday(.wide)) + " · \(workout.minutes) min"
                     + (workout.averageHeartRate.map { " · \(Int($0.rounded())) bpm" } ?? ""))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(AppTheme.ink.opacity(0.75))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Self.effortWord(effort))
                .font(.caption.weight(.bold))
                .foregroundStyle(effort >= 7 ? Color.black : AppTheme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(effort >= 7 ? Color.white : Color.white.opacity(0.16), in: Capsule())
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
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

/// A heart signal: the number today, how it sits against the usual, and four
/// weeks of the athlete's own line with the usual as a band.
struct SignalTile: View {
    let label: String
    let unit: String
    let series: [TwinPoint]
    let reading: SignalReading?
    let tint: Color

    private var shown: Double? { reading?.today ?? series.last?.value }

    private var note: String? {
        guard let diff = reading?.difference, let usual = reading?.usual, usual > 0 else { return nil }
        if abs(diff) / usual < 0.04 { return "Your usual" }
        return "\(Int(abs(diff).rounded())) \(diff > 0 ? "above" : "below") usual"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let shown {
                BigFigure("\(Int(shown.rounded()))", unit: unit, size: 36)
            }
            Chart {
                if let usual = reading?.usual {
                    RuleMark(y: .value("Usual", usual))
                        .foregroundStyle(Color.white.opacity(0.25))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
                ForEach(Array(series.enumerated()), id: \.offset) { _, point in
                    AreaMark(x: .value("Day", point.date), yStart: .value("Floor", yDomain.lowerBound), yEnd: .value(label, point.value))
                        .foregroundStyle(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Day", point.date), y: .value(label, point.value))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
                if let last = series.last {
                    PointMark(x: .value("Day", last.date), y: .value(label, last.value))
                        .foregroundStyle(Color.white)
                        .symbolSize(30)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: yDomain)
            .frame(height: 54)
            .clipped()
            .accessibilityHidden(true)
            Text(note ?? (series.count < 8 ? "Learning your usual" : "4 weeks"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(colors: [Color(rgb: 0x111114), Color(rgb: 0x17171B)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [tint.opacity(0.28), tint.opacity(0.06), .clear], center: UnitPoint(x: 0.1, y: 0.25),
                               startRadius: 0, endRadius: 140)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(shown.map { "\(Int($0.rounded())) \(unit)" } ?? "no data")\(note.map { ", \($0)" } ?? "")")
    }

    private var yDomain: ClosedRange<Double> {
        let values = series.map(\.value) + (reading?.usual.map { [$0] } ?? [])
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let pad = max(2, (high - low) * 0.25)
        return (low - pad)...(high + pad)
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
         Part(label: "REM", minutes: stages.rem, color: Color(rgb: 0x9CC3FF))]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { proxy in
                let total = max(1, parts.reduce(0) { $0 + $1.minutes })
                let gaps = CGFloat(parts.filter { $0.minutes > 0 }.count - 1) * 3
                HStack(spacing: 3) {
                    ForEach(parts) { part in
                        if part.minutes > 0 {
                            Capsule()
                                .fill(part.color)
                                .frame(width: max(6, (proxy.size.width - gaps) * part.minutes / total))
                        }
                    }
                }
            }
            .frame(height: 10)
            HStack(alignment: .top, spacing: 0) {
                ForEach(parts) { part in
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
        .accessibilityLabel("Last night by stage: deep \(SleepMath.label(stages.deep / 60)), core \(SleepMath.label(stages.core / 60)), REM \(SleepMath.label(stages.rem / 60))")
    }
}
