import SwiftUI

// MARK: - The part of the day

/// Home changes its purpose through the day — PREPARE, PERFORM, REFLECT —
/// and its light with it. Same app, same dark design; only the ambient glow,
/// the greeting, the hero and the call to action change.
public enum DayPhase: String, Sendable, CaseIterable {
    /// 5:00–11:30: prepare. What does my body feel like, what's planned?
    case morning
    /// 11:30–17:30: perform. What's next? Start it.
    case day
    /// 17:30–24:00: reflect. What happened, what did I learn?
    case evening
    /// 0:00–5:00: rest. Nothing to do but sleep.
    case night

    public static func at(_ date: Date, calendar: Calendar = .current) -> DayPhase {
        at(minute: minuteOfDay(date, calendar: calendar))
    }

    public static func at(minute: Int) -> DayPhase {
        switch minute {
        case 300..<690: .morning
        case 690..<1050: .day
        case 1050..<1440: .evening
        default: .night
        }
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    public var greeting: String {
        switch self {
        case .morning: "Good morning"
        case .day: "Good afternoon"
        case .evening: "Good evening"
        case .night: "Good night"
        }
    }

    public var systemImage: String {
        switch self {
        case .morning: "sunrise.fill"
        case .day: "sun.max.fill"
        case .evening: "sunset.fill"
        case .night: "moon.stars.fill"
        }
    }

    /// The training ember (V8), with the character of the hour: lighter in
    /// the morning, pure in the day, deeper in the evening.
    public var red: Color {
        switch self {
        case .morning: Color(rgb: 0xFDBA8C)
        case .day: AppTheme.red
        case .evening: Color(rgb: 0xF97316)
        case .night: Color(rgb: 0xD9480F)
        }
    }
}

// MARK: - Ambient light

/// The glow at the top of Home: a colour and a strength that drift through
/// the day. Anchors hold for hours and blend into each other over an hour or
/// two, so 5:29 pm and 5:31 pm look the same.
public struct AmbientLight: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var strength: Double

    /// (minute of the day, light). Wraps around midnight.
    static let anchors: [(minute: Int, light: AmbientLight)] = [
        (0, .night), (270, .night),          // until 4:30 near-black with faint deep violet
        (390, .morning), (630, .morning),    // 6:30–10:30 soft lavender morning light
        (750, .day), (990, .day),            // 12:30–16:30 pure AthleteOS violet
        (1110, .evening), (1350, .evening),  // 18:30–22:30 deep violet
        (1440, .night),
    ]

    static let night = AmbientLight(red: 0.16, green: 0.07, blue: 0.36, strength: 0.22)
    static let morning = AmbientLight(red: 0.66, green: 0.42, blue: 0.98, strength: 0.30)
    static let day = AmbientLight(red: 0.55, green: 0.36, blue: 0.96, strength: 0.22)
    static let evening = AmbientLight(red: 0.33, green: 0.13, blue: 0.62, strength: 0.38)

    public static func at(_ date: Date, calendar: Calendar = .current) -> AmbientLight {
        at(minute: DayPhase.minuteOfDay(date, calendar: calendar))
    }

    public static func at(minute: Int) -> AmbientLight {
        let m = ((minute % 1440) + 1440) % 1440
        for index in 0..<(anchors.count - 1) {
            let (from, to) = (anchors[index], anchors[index + 1])
            guard m >= from.minute, m <= to.minute else { continue }
            let span = Double(to.minute - from.minute)
            let t = span == 0 ? 0 : Double(m - from.minute) / span
            return from.light.mixed(with: to.light, t: t)
        }
        return .night
    }

    func mixed(with other: AmbientLight, t: Double) -> AmbientLight {
        let t = min(max(t, 0), 1)
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        return AmbientLight(red: lerp(red, other.red), green: lerp(green, other.green),
                            blue: lerp(blue, other.blue), strength: lerp(strength, other.strength))
    }

    public var color: Color { Color(red: red, green: green, blue: blue) }
}

/// Home's backdrop (V5): near-black space, the hour's light from the top,
/// a low crimson field on the side and the sport's geometry barely there.
/// Checked once a minute; every change is tiny.
struct HomeAmbientBackground: View {
    var sportSlug: String? = nil

    /// The sky of the hour (AppBackground follows the time of day).
    var body: some View {
        AppBackground(.hero)
    }
}

/// A hero button's label: "CHECK IN →".
struct HeroCTALabel: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
            Image(systemName: "arrow.right").font(.subheadline.weight(.bold))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

/// Readiness as an instrument: a thin three-part line, the current state lit.
/// Never a number.
struct ReadinessScale: View {
    let level: TodayReadiness

    private static let order: [TodayReadiness] = [.recovery, .reduced, .normal]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.order, id: \.rawValue) { step in
                let lit = step == level
                Capsule()
                    .fill(lit ? AppTheme.color(for: step.band) : Color.white.opacity(0.10))
                    .frame(height: lit ? 4 : 2)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

// MARK: - The week

/// "Your week" on Home: one small block, not accounting software.
public struct WeekSummary: Equatable, Sendable {
    public let practices: Int
    public let workouts: Int
    public let mobility: Int
    public let checkIns: Int
    /// Days of the week so far (Monday = 1 … today).
    public let daysSoFar: Int
    /// Monday … Sunday: something done that day (a check-in, practice or workout).
    public let active: [Bool]

    /// `sessions`: when each workout started and whether it was mobility.
    public static func make(now: Date, sessions: [(date: Date, mobility: Bool)], practiceDays: [String],
                            checkInDates: [Date], calendar: Calendar = .current) -> WeekSummary {
        var monday = calendar
        monday.firstWeekday = 2
        let start = monday.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let keys = days.map { DayKey.of($0, calendar: calendar) }
        let inWeek = { (date: Date) in date >= start && date < (calendar.date(byAdding: .day, value: 7, to: start) ?? now) }
        let weekSessions = sessions.filter { inWeek($0.date) }
        let weekPractices = Set(practiceDays.filter { keys.contains($0) })
        let checkInDays = Set(checkInDates.filter(inWeek).map { DayKey.of($0, calendar: calendar) })
        let sessionDays = Set(weekSessions.map { DayKey.of($0.date, calendar: calendar) })
        let today = calendar.startOfDay(for: now)
        return WeekSummary(
            practices: weekPractices.count,
            workouts: weekSessions.filter { !$0.mobility }.count,
            mobility: weekSessions.filter(\.mobility).count,
            checkIns: checkInDays.count,
            daysSoFar: days.filter { $0 <= today }.count,
            active: keys.map { checkInDays.contains($0) || sessionDays.contains($0) || weekPractices.contains($0) }
        )
    }
}

/// How much of the week's plan is done: one segment per planned workout and
/// practice. Doing more than planned never overflows the bar, it is only
/// mentioned. Rest days and missed sessions are never counted against anyone.
struct WeekPlanProgress: Equatable {
    enum Kind: Equatable { case workout, practice }
    struct Segment: Equatable {
        let kind: Kind
        let done: Bool
    }

    let workoutsPlanned: Int
    let workoutsDone: Int
    let practicesPlanned: Int
    let practicesDone: Int

    init(workoutsPlanned: Int, workoutsDone: Int, practicesPlanned: Int, practicesDone: Int) {
        self.workoutsPlanned = max(0, workoutsPlanned)
        self.workoutsDone = max(0, workoutsDone)
        self.practicesPlanned = max(0, practicesPlanned)
        self.practicesDone = max(0, practicesDone)
    }

    var plannedTotal: Int { workoutsPlanned + practicesPlanned }
    var doneTotal: Int { min(workoutsDone, workoutsPlanned) + min(practicesDone, practicesPlanned) }
    var extraTotal: Int { max(0, workoutsDone - workoutsPlanned) + max(0, practicesDone - practicesPlanned) }
    var remaining: Int { plannedTotal - doneTotal }
    var isVisible: Bool { plannedTotal > 0 }
    var isComplete: Bool { plannedTotal > 0 && remaining == 0 }

    var segments: [Segment] {
        let workouts = (0..<min(workoutsPlanned, 14)).map { Segment(kind: .workout, done: $0 < workoutsDone) }
        let practices = (0..<min(practicesPlanned, 14)).map { Segment(kind: .practice, done: $0 < practicesDone) }
        return workouts + practices
    }

    var statusLine: String {
        if isComplete {
            return extraTotal > 0 ? "Week complete, plus \(extraTotal) extra" : "Week complete"
        }
        return remaining == 1 ? "1 still ahead" : "\(remaining) still ahead"
    }
}

/// The week as one bar (V6): a big count, a segment per planned session
/// (workouts red, practices orange) that lights up when it is done.
struct WeekPlanBar: View {
    let plan: WeekPlanProgress

    var body: some View {
        // V8: no box — a big light number, then one segment per planned
        // session in its activity colour (gym ember, practice blue), dim until done.
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                BigFigure(String(plan.doneTotal), size: 56)
                Text("of \(plan.plannedTotal) planned")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                Spacer(minLength: 8)
                Text(plan.statusLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(plan.isComplete ? AppTheme.ink : AppTheme.secondaryText)
            }
            HStack(spacing: 6) {
                ForEach(Array(plan.segments.enumerated()), id: \.offset) { _, segment in
                    let color = segment.kind == .workout ? AuraTone.training.mark : AuraTone.body.mark
                    Capsule()
                        .fill(segment.done ? color : color.opacity(0.22))
                        .frame(height: 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.4), value: plan.doneTotal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week: \(plan.doneTotal) of \(plan.plannedTotal) planned sessions done. \(plan.statusLine)")
    }
}

/// The week: the plan bar and one telemetry line. The only weekly summary on Home.
struct HomeWeekBlock: View {
    let week: WeekSummary
    let accent: Color
    var plan: WeekPlanProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel("This week")
            if let plan, plan.isVisible { WeekPlanBar(plan: plan) }
            // One line, not a grid of the same numbers again.
            Text(summaryLine)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// "2 practices · 1 workout · 1 mobility · 4/5 check-ins"
    private var summaryLine: String {
        var parts: [String] = []
        if week.practices > 0 { parts.append("\(week.practices) \(week.practices == 1 ? "practice" : "practices")") }
        if week.workouts > 0 { parts.append("\(week.workouts) \(week.workouts == 1 ? "workout" : "workouts")") }
        if week.mobility > 0 { parts.append("\(week.mobility) mobility") }
        parts.append("\(week.checkIns)/\(week.daysSoFar) check-ins")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Small pieces of the centred Home

/// A compact supporting row: a small coloured dot, title left, value
/// right, never centred. (V5: fewer icons — the dot carries the colour.)
struct HomeDetailRow<Trailing: View>: View {
    let systemImage: String
    let color: Color
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .frame(width: 14)
                .accessibilityHidden(true)
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }
}

/// The eyebrow over the step to do now: a small lit dot, then the words.
struct NextStepEyebrow: View {
    let text: String
    let accent: Color

    init(_ text: String, accent: Color) {
        self.text = text
        self.accent = accent
    }

    var body: some View {
        // V8: a plain small label, like "Today's training" on the Workout card.
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.ink.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One step of today's plan (TodayPlan): its number — a check once done,
/// lit when it is the next one — its name, and a few words on the right.
struct PlanStepRow: View {
    let row: TodayPlan.Row
    let title: String
    let detail: String?
    let accent: Color
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            marker
            Text(title)
                .font(.body.weight(row.state == .now ? .semibold : .regular))
                .foregroundStyle(row.state == .done ? AppTheme.secondaryText : AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(row.state == .now ? AppTheme.ink : AppTheme.secondaryText)
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedText)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 50)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    @ViewBuilder
    private var marker: some View {
        switch row.state {
        case .done:
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.green)
                .frame(width: 28, height: 28)
                .background(AppTheme.green.opacity(0.15), in: Circle())
        case .now:
            Text(number)
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(AppTheme.ink)
                .frame(width: 28, height: 28)
                .background(accent.opacity(0.35), in: Circle())
                .overlay(Circle().stroke(accent, lineWidth: 1))
        case .open:
            Text(number)
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(AppTheme.mutedText.opacity(0.6), lineWidth: 1))
        case .info:
            Image(systemName: "leaf.fill")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 28, height: 28)
        }
    }

    private var number: String { row.number.map { "\($0)" } ?? "" }

    private var spoken: String {
        var parts: [String] = []
        if let step = row.number { parts.append("Step \(step)") }
        parts.append(title)
        if let detail { parts.append(detail) }
        switch row.state {
        case .done: parts.append("done")
        case .now: parts.append("next")
        case .open, .info: break
        }
        return parts.joined(separator: ", ")
    }
}
