import Charts
import SwiftUI

// The twin as widgets (owner, 2026-11-19): three questions — how am I
// performing, how am I changing, how is my mind evolving — each answered by
// a few clean V8 cards built from the athlete's own data. Never a score:
// strength in kilos, training in minutes, sleep in hours, readiness and
// mood in words or an unlabelled line.

// MARK: - Data

/// One lift over the weeks: the best estimated strength of each day.
struct LiftTrend: Identifiable, Sendable {
    let slug: String
    let points: [TwinPoint]
    var id: String { slug }
    var first: Double { points.first?.value ?? 0 }
    var last: Double { points.last?.value ?? 0 }
    var change: Double { last - first }
}

/// One week's training: minutes logged and how hard (minutes × effort).
struct WeekLoad: Identifiable, Sendable {
    let start: Date
    let minutes: Int
    let load: Int
    var id: Date { start }
}

/// The twin's charts, worked out from the same data the analysis reads.
enum TwinTrends {
    /// Estimated one-rep strength (Epley): kg × (1 + reps / 30). Only sets
    /// of 12 reps or fewer, where the estimate still means something.
    static func estimated(kg: Double, reps: Int) -> Double { kg * (1 + Double(reps) / 30) }

    /// The lifts logged most often in the last 12 weeks, best estimate per day.
    static func lifts(_ lifts: [TwinInput.Lift], now: Date, days: Int = 84, limit: Int = 3,
                      calendar: Calendar = .current) -> [LiftTrend] {
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        var bySlug: [String: [Date: Double]] = [:]
        for lift in lifts where lift.date >= start && lift.date <= now && lift.weightKg > 0 && lift.reps > 0 && lift.reps <= 12 {
            let day = calendar.startOfDay(for: lift.date)
            let value = estimated(kg: lift.weightKg, reps: lift.reps)
            bySlug[lift.slug, default: [:]][day] = max(bySlug[lift.slug]?[day] ?? 0, value)
        }
        let trends = bySlug.compactMap { slug, days -> LiftTrend? in
            guard days.count >= 2 else { return nil }
            let points = days.sorted { $0.key < $1.key }.map { TwinPoint(date: $0.key, value: ($0.value * 2).rounded() / 2) }
            return LiftTrend(slug: slug, points: points)
        }
        return Array(trends.sorted {
            $0.points.count != $1.points.count ? $0.points.count > $1.points.count : $0.slug < $1.slug
        }.prefix(limit))
    }

    /// The last `weeks` weeks, oldest first, this week last.
    static func weeklyLoad(_ loads: [TwinInput.Load], now: Date, weeks: Int = 8, calendar: Calendar = .current) -> [WeekLoad] {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        return (0..<weeks).reversed().map { back in
            let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek) ?? thisWeek
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
            let inWeek = loads.filter { $0.date >= start && $0.date < end && $0.date <= now }
            let minutes = inWeek.reduce(0) { $0 + max(0, $1.minutes) }
            let load = inWeek.reduce(0) { $0 + max(0, $1.minutes) * ($1.rpe ?? 5) }
            return WeekLoad(start: start, minutes: minutes, load: load)
        }
    }

    /// Sleep each night of the last `days` days (only nights the athlete knew).
    static func sleep(_ mornings: [TwinInput.Morning], now: Date, days: Int = 14, calendar: Calendar = .current) -> [TwinPoint] {
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) ?? now
        var byDay: [Date: Double] = [:]
        for morning in mornings where morning.date >= start && morning.date <= now {
            if let hours = morning.sleepHours, hours > 0 { byDay[calendar.startOfDay(for: morning.date)] = hours }
        }
        return byDay.sorted { $0.key < $1.key }.map { TwinPoint(date: $0.key, value: $0.value, marked: $0.value < 8) }
    }

    /// Weekly averages (oldest first) of a 1…5 value; weeks without data left out.
    static func weekly(_ values: [(Date, Double)], now: Date, weeks: Int = 6, calendar: Calendar = .current) -> [TwinPoint] {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        return (0..<weeks).reversed().compactMap { back -> TwinPoint? in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let inWeek = values.filter { $0.0 >= start && $0.0 < end && $0.0 <= now }.map(\.1)
            guard !inWeek.isEmpty else { return nil }
            return TwinPoint(date: start, value: inWeek.reduce(0, +) / Double(inWeek.count))
        }
    }

    /// How stress moved: the last two weeks against the two before (1…5 scale).
    static func stressShift(_ mornings: [TwinInput.Morning], now: Date) -> Double? {
        let day = 86_400.0
        let recent = mornings.filter { $0.stress > 0 && $0.date > now.addingTimeInterval(-14 * day) && $0.date <= now }.map { Double($0.stress) }
        let before = mornings.filter { $0.stress > 0 && $0.date > now.addingTimeInterval(-28 * day) && $0.date <= now.addingTimeInterval(-14 * day) }
            .map { Double($0.stress) }
        guard recent.count >= 3, before.count >= 3 else { return nil }
        return recent.reduce(0, +) / Double(recent.count) - before.reduce(0, +) / Double(before.count)
    }

    static func readinessWord(_ band: ReadinessBand) -> String {
        switch band {
        case .green: "Ready"
        case .amber: "Go easier"
        case .red: "Recover"
        }
    }

    static func readinessColor(_ band: ReadinessBand) -> Color {
        switch band {
        case .green: AuraTone.body.mark
        case .amber: AppTheme.yellow
        case .red: AuraTone.training.mark
        }
    }
}

// MARK: - Pieces

/// A twin widget: a calm dark plate lit faintly in its colour, a small
/// title, then one sentence and the athlete's own chart.
struct TwinWidget<Content: View>: View {
    let title: String
    let tint: Color
    let content: Content

    init(_ title: String, tint: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(colors: AuraTone.calm.base, startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [tint.opacity(0.24), tint.opacity(0.05), .clear], center: UnitPoint(x: 0.05, y: 0),
                               startRadius: 0, endRadius: 260)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1) }
    }
}

/// The big question a section answers ("How are you performing?").
struct TwinQuestion: View {
    let question: String
    let answer: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question)
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(AppTheme.ink)
                .accessibilityAddTraits(.isHeader)
            if let answer {
                Text(answer)
                    .font(.body)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Performing

/// The main lifts going up: one line each, the change in kilos beside it.
struct LiftTrendWidget: View {
    let trends: [LiftTrend]
    let name: (String) -> String
    let onOpen: (LiftTrend) -> Void

    private static let colors: [Color] = [AuraTone.training.mark, AuraTone.body.mark, AppTheme.yellow]

    var body: some View {
        TwinWidget("Strength", tint: AuraTone.training.mark) {
            if trends.isEmpty {
                Text("Log a few sets with weight and your main lifts draw their line here.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(headline)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Chart {
                    ForEach(Array(trends.enumerated()), id: \.element.id) { index, trend in
                        ForEach(Array(trend.points.enumerated()), id: \.offset) { _, point in
                            LineMark(x: .value("Day", point.date), y: .value("Strength", point.value), series: .value("Lift", trend.slug))
                                .foregroundStyle(Self.colors[index % Self.colors.count])
                                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                                .interpolationMethod(.monotone)
                        }
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .frame(height: 110)
                .accessibilityHidden(true)
                VStack(spacing: 0) {
                    ForEach(Array(trends.enumerated()), id: \.element.id) { index, trend in
                        Button { onOpen(trend) } label: {
                            HStack(spacing: 12) {
                                Circle().fill(Self.colors[index % Self.colors.count]).frame(width: 8, height: 8)
                                Text(name(trend.slug))
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(Self.kg(trend.last))
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(AppTheme.ink)
                                Text(Self.signed(trend.change))
                                    .font(.footnote.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(trend.change > 0 ? AppTheme.green : AppTheme.secondaryText)
                                    .frame(minWidth: 54, alignment: .trailing)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppTheme.mutedText)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("\(name(trend.slug)): about \(Self.kg(trend.last)), \(Self.signed(trend.change)) in 12 weeks")
                    }
                }
                Text("Estimated one-rep strength from your sets · last 12 weeks")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedText)
            }
        }
    }

    private var headline: String {
        let rising = trends.filter { $0.change >= 1 }
        if rising.count == trends.count { return "All your main lifts are going up." }
        if let best = trends.max(by: { $0.change < $1.change }), best.change >= 1 {
            return "\(name(best.slug)) is up \(Self.kg(best.change))."
        }
        return "Holding steady — the next step comes with consistent sessions."
    }

    /// In the athlete's own unit (kg or lb), whole numbers: it's an estimate.
    static func kg(_ value: Double) -> String {
        let unit = WeightUnit.current
        return "\(Int(unit.value(kg: value).rounded())) \(unit.rawValue)"
    }

    static func signed(_ value: Double) -> String {
        let text = kg(abs(value))
        if value >= 0.5 { return "+" + text }
        if value <= -0.5 { return "−" + text }
        return "±0"
    }
}

// MARK: - Changing

/// The body: what was trained this week glows, what's fresh is named.
struct BodyStatusWidget: View {
    let report: MuscleTraining.Report?
    /// Regions still resting after a hard session (gym or Health), days left.
    var recovering: [(region: GymRegion, days: Int)] = []

    private var trained: [MuscleGroup] {
        (report?.groups ?? []).filter { ($0.daysSince ?? 99) <= 2 }.map(\.group)
    }

    private var fresh: [MuscleGroup] {
        (report?.groups ?? []).filter { ($0.daysSince ?? 99) >= 4 }.map(\.group)
    }

    var body: some View {
        TwinWidget("Your body", tint: AuraTone.body.mark) {
            if let report, report.workouts > 0 {
                Text(sentence)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                TrainingBodyView(brightness: report.brightness, showsLabels: false)
                    .frame(height: 210)
                    .frame(maxWidth: .infinity)
                if let ready = Self.readyAgain(recovering) {
                    Text(ready)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !fresh.isEmpty {
                    Text("Fresh: " + fresh.prefix(4).map { $0.title.lowercased() }.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Brighter = trained more in the last weeks")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedText)
            } else {
                Text("Log a workout and your body lights up here: what you trained, and what's fresh.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "Ready for hard work again: legs Sunday, upper body tomorrow."
    static func readyAgain(_ recovering: [(region: GymRegion, days: Int)], now: Date = .now,
                           calendar: Calendar = .current) -> String? {
        guard !recovering.isEmpty else { return nil }
        let parts = recovering.map { entry -> String in
            let when: String
            if entry.days <= 1 {
                when = "tomorrow"
            } else {
                let day = calendar.date(byAdding: .day, value: entry.days, to: calendar.startOfDay(for: now)) ?? now
                when = day.formatted(.dateTime.weekday(.wide))
            }
            return "\(entry.region.title) \(when)"
        }
        return "Ready for hard work again: " + parts.joined(separator: ", ") + "."
    }

    private var sentence: String {
        if trained.isEmpty, recovering.isEmpty { return "Everything is fresh — a good day to train." }
        if trained.isEmpty { return "Recently trained: " + recovering.map(\.region.title).joined(separator: ", ") + "." }
        let names = trained.prefix(3).map { $0.title.lowercased() }
        return "Recently trained: " + names.joined(separator: ", ") + "."
    }
}

/// Training minutes per week, the last eight weeks.
struct LoadWidget: View {
    let weeks: [WeekLoad]

    private var thisWeek: Int { weeks.last?.minutes ?? 0 }
    private var usual: Int {
        let earlier = weeks.dropLast().filter { $0.minutes > 0 }
        guard !earlier.isEmpty else { return 0 }
        return earlier.reduce(0) { $0 + $1.minutes } / earlier.count
    }

    var body: some View {
        TwinWidget("Training", tint: AuraTone.training.mark) {
            HStack(alignment: .firstTextBaseline) {
                BigFigure("\(thisWeek)", unit: "min this week", size: 44)
                Spacer(minLength: 0)
            }
            if usual > 0 {
                Text(thisWeek > usual * 3 / 2 ? "Well above your usual \(usual) min — keep tomorrow easy."
                     : "Your usual week: about \(usual) min.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Chart {
                ForEach(weeks) { week in
                    BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Minutes", week.minutes), width: .ratio(0.62))
                        .foregroundStyle(week.id == weeks.last?.id ? AuraTone.training.mark : AuraTone.training.mark.opacity(0.35))
                        .cornerRadius(4)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 90)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Training minutes, the last eight weeks")
        }
    }
}

/// Sleep each night and the readiness word of each morning this week.
struct SleepReadinessWidget: View {
    let nights: [TwinPoint]
    let days: [(date: Date, band: ReadinessBand?)]
    /// Sleep comes from a watch (Apple Health) — it counts for more.
    let fromWatch: Bool

    private var average: Double? {
        guard !nights.isEmpty else { return nil }
        return nights.map(\.value).reduce(0, +) / Double(nights.count)
    }

    var body: some View {
        TwinWidget("Sleep and readiness", tint: AuraTone.body.mark) {
            if let average {
                HStack(alignment: .firstTextBaseline) {
                    BigFigure(String(format: "%.1f", average), unit: "h a night", size: 44)
                    Spacer(minLength: 0)
                }
                Text(average < 8 ? "Teens need 8–10 hours. An earlier night is the easiest extra strength there is."
                     : "Right in the 8–10 hours your body builds on.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Chart {
                    RuleMark(y: .value("Goal", 8))
                        .foregroundStyle(Color.white.opacity(0.18))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    ForEach(Array(nights.enumerated()), id: \.offset) { _, night in
                        BarMark(x: .value("Night", night.date, unit: .day), y: .value("Hours", night.value), width: .ratio(0.62))
                            .foregroundStyle(night.marked ? AuraTone.body.mark.opacity(0.45) : AuraTone.body.mark)
                            .cornerRadius(4)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: 0...11)
                .frame(height: 90)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sleep each night, the last two weeks")
            } else {
                Text("Tell the morning check-in how long you slept — or connect Apple Health — and your nights show up here.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if days.contains(where: { $0.band != nil }) {
                HStack(spacing: 6) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                        VStack(spacing: 6) {
                            Capsule()
                                .fill(day.band.map(TwinTrends.readinessColor) ?? Color.white.opacity(0.1))
                                .frame(height: 6)
                            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(day.date.formatted(.dateTime.weekday(.wide))): \(day.band.map(TwinTrends.readinessWord) ?? "no check-in")")
                    }
                }
                .padding(.top, 4)
                if let today = days.last?.band {
                    Text("This morning: \(TwinTrends.readinessWord(today).lowercased()).")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(TwinTrends.readinessColor(today))
                }
            }
            if fromWatch {
                Label("Sleep from your watch counts for more in your plan", systemImage: "applewatch")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedText)
            }
        }
    }
}

// MARK: - Mind

/// Stress and how training felt, week by week — lines, never numbers.
struct MindWidget: View {
    let calm: [TwinPoint]
    let felt: [TwinPoint]
    let shift: Double?

    var body: some View {
        TwinWidget("Mindset", tint: AuraTone.mind.mark) {
            Text(sentence)
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if calm.count >= 2 || felt.count >= 2 {
                Chart {
                    ForEach(Array(calm.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Week", point.date), y: .value("Calm", point.value), series: .value("Line", "calm"))
                            .foregroundStyle(AuraTone.mind.mark)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(Array(felt.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("Week", point.date), y: .value("Felt", point.value), series: .value("Line", "felt"))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
                            .interpolationMethod(.monotone)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: 0.5...5.5)
                .frame(height: 90)
                .accessibilityHidden(true)
                HStack(spacing: 16) {
                    legend(AuraTone.mind.mark, "How calm you felt")
                    if felt.count >= 2 { legend(Color.white.opacity(0.7), "How training felt") }
                }
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 14, height: 4)
            Text(text).font(.footnote).foregroundStyle(AppTheme.secondaryText)
        }
    }

    private var sentence: String {
        guard let shift else {
            return calm.isEmpty ? "A few more check-ins and your twin sees how your head is doing." : "Your head over the last weeks."
        }
        if shift <= -0.4 { return "You've been calmer the last two weeks." }
        if shift >= 0.4 { return "More on your mind lately than before." }
        return "Steady — about as calm as the weeks before."
    }
}
