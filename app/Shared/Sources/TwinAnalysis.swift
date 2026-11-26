import Foundation

/// What the twin reads: the athlete's own data, as plain values (built from
/// SwiftData and the stores by TwinInputBuilder, so this file stays pure and
/// testable).
public struct TwinInput: Sendable {
    public struct Morning: Sendable {
        public var date: Date
        /// Last night's sleep, when the athlete knew it.
        public var sleepHours: Double?
        /// 1…5 scales (check-in): energy 5 = great, soreness 5 = high.
        public var energy: Int
        public var soreness: Int
        /// 1 calm … 5 very stressed (0: not asked).
        public var stress: Int

        public init(date: Date, sleepHours: Double?, energy: Int, soreness: Int, stress: Int = 0) {
            self.date = date
            self.sleepHours = sleepHours
            self.energy = energy
            self.soreness = soreness
            self.stress = stress
        }
    }

    /// A team or club practice the athlete logged.
    public struct Practice: Sendable {
        public var date: Date
        /// 1 badly … 5 great.
        public var went: Int
        /// 1 easy … 5 exhausting.
        public var hard: Int
        public var minutes: Int?

        public init(date: Date, went: Int, hard: Int, minutes: Int?) {
            self.date = date
            self.went = went
            self.hard = hard
            self.minutes = minutes
        }
    }

    /// A logged session: how long and how hard (RPE 1–10, when given).
    public struct Load: Sendable {
        public var date: Date
        public var minutes: Int
        public var rpe: Int?

        public init(date: Date, minutes: Int, rpe: Int?) {
            self.date = date
            self.minutes = minutes
            self.rpe = rpe
        }
    }

    public struct Lift: Sendable {
        public var date: Date
        public var slug: String
        public var weightKg: Double
        public var reps: Int

        public init(date: Date, slug: String, weightKg: Double, reps: Int) {
            self.date = date
            self.slug = slug
            self.weightKg = weightKg
            self.reps = reps
        }
    }

    public struct Test: Sendable {
        public var date: Date
        public var testID: String
        public var name: String
        public var value: Double
        public var higherIsBetter: Bool
        /// "s", "cm", "reps"… (empty: worked out from the test).
        public var unit: String

        public init(date: Date, testID: String, name: String, value: Double, higherIsBetter: Bool, unit: String = "") {
            self.date = date
            self.testID = testID
            self.name = name
            self.value = value
            self.higherIsBetter = higherIsBetter
            self.unit = unit
        }
    }

    public struct Reflect: Sendable {
        public var date: Date
        /// 1 (rough) … 5 (great), when given.
        public var feeling: Int?
        public var needsWork: [String]

        public init(date: Date, feeling: Int?, needsWork: [String]) {
            self.date = date
            self.feeling = feeling
            self.needsWork = needsWork
        }
    }

    public var mornings: [Morning]
    public var games: [Date]
    public var sessions: [Date]
    public var lifts: [Lift]
    public var tests: [Test]
    public var reflections: [Reflect]
    public var practices: [Practice]
    public var loads: [Load]
    /// Intake answers: question id → option id or free text.
    public var intake: [String: String]
    /// The athlete's sport: its words ("matches", "races") and whether speed decides.
    public var sportSlug: String?
    public var now: Date

    public init(mornings: [Morning] = [], games: [Date] = [], sessions: [Date] = [], lifts: [Lift] = [], tests: [Test] = [],
                reflections: [Reflect] = [], practices: [Practice] = [], loads: [Load] = [], intake: [String: String] = [:],
                sportSlug: String? = nil, now: Date = .now) {
        self.mornings = mornings
        self.games = games
        self.sessions = sessions
        self.lifts = lifts
        self.tests = tests
        self.reflections = reflections
        self.practices = practices
        self.loads = loads
        self.intake = intake
        self.sportSlug = sportSlug
        self.now = now
    }
}

/// One point of evidence on a chart.
public struct TwinPoint: Sendable, Hashable {
    public var date: Date
    public var value: Double
    /// Highlighted (the night before a game, the morning after one…).
    public var marked: Bool

    public init(date: Date, value: Double, marked: Bool = false) {
        self.date = date
        self.value = value
        self.marked = marked
    }
}

/// The data behind an insight, ready to chart.
public struct TwinEvidence: Sendable, Hashable {
    public enum Style: Sendable { case bars, lines }

    public var style: Style
    public var points: [TwinPoint]
    public var unit: String
    public var caption: String
    /// A second line to compare against (sprint against strength).
    public var comparison: [TwinPoint]?
}

/// Something the twin found in the athlete's data.
public struct TwinInsight: Sendable, Hashable, Identifiable {
    public enum Strength: Sendable { case strong, emerging }

    public var kind: TwinInsightKind
    public var headline: String
    public var detail: String
    public var strength: Strength
    /// What it rests on: "9 games", "your interview"…
    public var basis: String
    public var evidence: TwinEvidence?
    /// The numbers a briefing's "why" uses.
    public var values: [String: String]
    /// The "why your coach gave you this" when the briefing's own text can't be filled.
    public var reason: String
    /// Something that works — no briefing.
    public var positive: Bool
    /// The size of the pattern, comparable over time (bigger = stronger pattern).
    public var measure: Double? = nil
    /// The measure as the athlete reads it ("58 minutes").
    public var measureText: String? = nil
    /// How it compares with three weeks ago.
    public var trend: TwinTrend? = nil

    public var id: String { kind.rawValue }
    public var briefing: Briefing? { positive ? nil : AcademyContent.briefing(for: kind) }

    /// Why the coach assigned the briefing, in the athlete's own numbers.
    public var why: String { briefing?.why(filling: values) ?? reason }
}

/// How an insight moved since the twin last looked (three weeks earlier).
public enum TwinTrend: Sendable, Hashable {
    /// Not there three weeks ago.
    case new
    /// Smaller than it was ("was 1 h 20 min").
    case improving(was: String)
    /// Bigger than it was.
    case worsening(was: String)
    case steady

    public var label: String {
        switch self {
        case .new: "New"
        case .improving(let was): "Improving · was \(was)"
        case .worsening(let was): "Growing · was \(was)"
        case .steady: "Steady"
        }
    }
}

/// What the twin knows right now.
public struct TwinReport: Sendable {
    public struct Counts: Sendable, Equatable {
        public var weeks: Int
        public var checkIns: Int
        public var sessions: Int
        public var games: Int
    }

    /// Things holding the athlete back, most important first; each has a briefing.
    public var insights: [TwinInsight]
    /// Things that are working.
    public var strengths: [TwinInsight]
    /// The coach's read, one paragraph.
    public var coachRead: String
    public var counts: Counts

    public var assigned: [Briefing] { insights.compactMap(\.briefing) }
}

/// The twin's analysis: rule-based, on the phone, every number traceable to
/// the athlete's own data. Insights never diagnose; they point at patterns.
public enum TwinAnalysis {
    /// How far back the twin looks.
    public static let windowDays = 56

    /// How far back "three weeks ago" is for trends.
    public static let trendDays = 21

    public static func report(_ input: TwinInput, calendar: Calendar = .current) -> TwinReport {
        var report = analyse(input, calendar: calendar)
        // The same analysis as the twin would have run three weeks ago.
        var earlier = input
        earlier.now = calendar.date(byAdding: .day, value: -trendDays, to: input.now) ?? input.now
        let before = analyse(earlier, calendar: calendar)
        let knewEnough = before.counts.checkIns >= 7 || before.counts.sessions >= 4
        report.insights = report.insights.map { insight in
            var insight = insight
            insight.trend = trend(insight, before.insights.first { $0.kind == insight.kind }, knewEnough: knewEnough)
            return insight
        }
        return report
    }

    static func trend(_ now: TwinInsight, _ then: TwinInsight?, knewEnough: Bool) -> TwinTrend? {
        guard let then else { return knewEnough ? .new : nil }
        guard let a = now.measure, let b = then.measure, b > 0 else { return .steady }
        if a <= b * 0.8, let was = then.measureText { return .improving(was: was) }
        if a >= b * 1.2, let was = then.measureText { return .worsening(was: was) }
        return .steady
    }

    static func analyse(_ input: TwinInput, calendar: Calendar) -> TwinReport {
        let context = Context(input: input, calendar: calendar)
        let issues = [sleepBeforeGames(context), recoveryAfterGames(context), loadSpike(context), strengthAndSpeed(context),
                      gameDayFuel(context), sleepAffectsPractice(context), irregularSleep(context), stressAndSleep(context),
                      pressureConfidence(context), mistakeReplay(context)].compactMap { $0 }
        let found = issues.filter { !$0.positive }
            .enumerated()
            .sorted { ($0.element.strength == .strong ? 0 : 1, $0.offset) < ($1.element.strength == .strong ? 0 : 1, $1.offset) }
            .map(\.element)
        let strengths = issues.filter(\.positive) + [consistentTraining(context), sleepBase(context)].compactMap { $0 }
        return TwinReport(insights: found, strengths: strengths,
                          coachRead: coachRead(found, strengths: strengths, counts: context.counts, hasIntake: !input.intake.isEmpty, events: context.events),
                          counts: context.counts)
    }

    // MARK: Shared

    struct Context {
        let input: TwinInput
        let calendar: Calendar
        let start: Date
        let mornings: [TwinInput.Morning]
        let gameDays: Set<Date>
        let reflections: [TwinInput.Reflect]
        let counts: TwinReport.Counts
        /// The athlete's words: game/match/race…
        let family: SportFamily
        var event: String { family.event }
        var events: String { family.events }

        init(input: TwinInput, calendar: Calendar) {
            self.input = input
            self.calendar = calendar
            family = AcademyContent.family(forSport: input.sportSlug)
            let today = calendar.startOfDay(for: input.now)
            start = calendar.date(byAdding: .day, value: -TwinAnalysis.windowDays, to: today) ?? today
            let start = start
            mornings = input.mornings.filter { $0.date >= start && $0.date <= input.now }.sorted { $0.date < $1.date }
            let games = input.games.filter { $0 >= start && $0 <= input.now }
            gameDays = Set(games.map { calendar.startOfDay(for: $0) })
            reflections = input.reflections.filter { $0.date >= start && $0.date <= input.now }.sorted { $0.date < $1.date }
            let sessions = input.sessions.filter { $0 >= start && $0 <= input.now }
            let earliest = (mornings.map(\.date) + games + sessions).min() ?? today
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: earliest), to: today).day ?? 0
            counts = TwinReport.Counts(weeks: max(1, Int((Double(days) / 7).rounded(.up))), checkIns: mornings.count,
                                       sessions: sessions.count, games: gameDays.count)
        }

        func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }

        func daysAfterGame(_ date: Date) -> Int? {
            for offset in 1...2 {
                if let back = calendar.date(byAdding: .day, value: -offset, to: day(date)), gameDays.contains(back) { return offset }
            }
            return nil
        }

        /// The last three weeks of mornings, for charts.
        var recentMornings: [TwinInput.Morning] { Array(mornings.suffix(21)) }
    }

    static func mean(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }

    static func duration(_ hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        if minutes < 60 { return "\(minutes) minutes" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    static func one(_ value: Double) -> String { String(format: "%.1f", value) }

    // MARK: Insights that need a briefing

    static func sleepBeforeGames(_ c: Context) -> TwinInsight? {
        let known = c.mornings.filter { ($0.sleepHours ?? 0) > 0 }
        let eves = known.filter { c.gameDays.contains(c.day($0.date)) }
        let others = known.filter { !c.gameDays.contains(c.day($0.date)) }
        guard eves.count >= 2, others.count >= 4 else { return nil }
        let before = mean(eves.compactMap(\.sleepHours)), usual = mean(others.compactMap(\.sleepHours))
        let gap = usual - before
        guard gap >= 0.4 else { return nil }
        let gapText = duration(gap)
        // Do the games feel worse too? (Reflections on game days.)
        let gameFeel = c.reflections.filter { c.gameDays.contains(c.day($0.date)) }.compactMap(\.feeling).map(Double.init)
        let otherFeel = c.reflections.filter { !c.gameDays.contains(c.day($0.date)) }.compactMap(\.feeling).map(Double.init)
        let ratesLower = gameFeel.count >= 2 && otherFeel.count >= 3 && mean(otherFeel) - mean(gameFeel) >= 0.5
        return TwinInsight(
            kind: .sleepBeforeGames,
            headline: "You sleep \(gapText) less before \(c.events)\(ratesLower ? " — and rate those \(c.events) lower." : ".")",
            detail: "Before your last \(eves.count) \(c.events) you slept \(one(before)) h on average; on other nights \(one(usual)) h.",
            strength: eves.count >= 3 && gap >= 0.6 ? .strong : .emerging,
            basis: "\(eves.count) \(c.events)",
            evidence: TwinEvidence(style: .bars,
                                   points: c.recentMornings.compactMap { m in
                                       m.sleepHours.flatMap { $0 > 0 ? TwinPoint(date: m.date, value: $0, marked: c.gameDays.contains(c.day(m.date))) : nil }
                                   },
                                   unit: "h", caption: "Sleep each night · highlighted: the night before a \(c.event)"),
            values: c.family.tokens.merging(["sleepGap": gapText, "gameCount": "\(eves.count)"]) { $1 },
            reason: "You slept \(gapText) less before your last \(eves.count) \(c.events) than on other nights.",
            positive: false, measure: gap, measureText: gapText)
    }

    static func recoveryAfterGames(_ c: Context) -> TwinInsight? {
        let dayOne = c.mornings.filter { c.daysAfterGame($0.date) == 1 }
        let dayTwo = c.mornings.filter { c.daysAfterGame($0.date) == 2 }
        let usual = c.mornings.filter { c.daysAfterGame($0.date) == nil && !c.gameDays.contains(c.day($0.date)) }
        guard dayOne.count >= 2, usual.count >= 4 else { return nil }
        let after = mean(dayOne.map { Double($0.soreness) }), normal = mean(usual.map { Double($0.soreness) })
        guard after >= 3, after - normal >= 1 else { return nil }
        let twoDays = !dayTwo.isEmpty && mean(dayTwo.map { Double($0.soreness) }) - normal >= 0.7
        let span = twoDays ? "two days" : "a day"
        return TwinInsight(
            kind: .recoveryAfterGames,
            headline: "\(c.family.tokens["Events"] ?? "Games") leave you sore for \(span) — far more than training does.",
            detail: "The morning after a \(c.event) your soreness is \(one(after)) of 5; on other mornings \(one(normal)). If it's sharp or in one spot, get it checked.",
            strength: dayOne.count >= 3 ? .strong : .emerging,
            basis: "\(dayOne.count) \(c.events)",
            evidence: TwinEvidence(style: .bars,
                                   points: c.recentMornings.map { TwinPoint(date: $0.date, value: Double($0.soreness), marked: c.daysAfterGame($0.date) != nil) },
                                   unit: "/5", caption: "Soreness each morning · highlighted: the days after a \(c.event)"),
            values: c.family.tokens.merging(["sorenessDays": span, "gameCount": "\(dayOne.count)"]) { $1 },
            reason: "Your soreness stays high for \(span) after \(c.events).",
            positive: false, measure: after - normal, measureText: "\(one(after)) of 5")
    }

    static func gameDayFuel(_ c: Context) -> TwinInsight? {
        let game = c.mornings.filter { c.gameDays.contains(c.day($0.date)) }
        let others = c.mornings.filter { !c.gameDays.contains(c.day($0.date)) }
        if game.count >= 2, others.count >= 4 {
            let gap = mean(others.map { Double($0.energy) }) - mean(game.map { Double($0.energy) })
            if gap >= 0.8 {
                return TwinInsight(
                    kind: .gameDayFuel,
                    headline: "Your energy is lowest on \(c.event) days — exactly when you need it most.",
                    detail: "On the mornings of your last \(game.count) \(c.events) your energy was \(one(gap)) points lower (of 5) than on other days.",
                    strength: game.count >= 3 ? .strong : .emerging,
                    basis: "\(game.count) \(c.events)",
                    evidence: TwinEvidence(style: .bars,
                                           points: c.recentMornings.map { TwinPoint(date: $0.date, value: Double($0.energy), marked: c.gameDays.contains(c.day($0.date))) },
                                           unit: "/5", caption: "Energy each morning · highlighted: \(c.event) days"),
                    values: c.family.tokens.merging(["energyGap": "\(one(gap)) points", "gameCount": "\(game.count)"]) { $1 },
                    reason: "Your energy dips on \(c.event) days.",
                    positive: false, measure: gap, measureText: "\(one(gap)) points")
            }
        }
        guard let food = c.input.intake["gameFood"], food == "nothing" || food == "small" else { return nil }
        return TwinInsight(
            kind: .gameDayFuel,
            headline: food == "nothing" ? "You often compete on an empty tank." : "You go into \(c.events) on very little fuel.",
            detail: "You told the twin you usually eat \(food == "nothing" ? "nothing" : "something small") before \(c.events). Repeated sprints run on fuel you put in hours earlier.",
            strength: .emerging, basis: "your interview", evidence: nil, values: c.family.tokens,
            reason: "You told your twin you often eat \(food == "nothing" ? "nothing" : "very little") before \(c.events).",
            positive: false)
    }

    static let strengthLifts: [String: String] = [
        "barbell-back-squat": "back squat", "barbell-front-squat": "front squat", "goblet-squat": "goblet squat",
        "trap-bar-deadlift": "trap-bar deadlift", "barbell-deadlift": "deadlift", "hip-thrust": "hip thrust",
        "bulgarian-split-squat": "split squat", "powerlifting-competition-squat-technique": "squat",
    ]

    /// Strength from a set: the weight, adjusted for reps (Epley), so heavier
    /// triples and lighter eights compare. Used for the trend only, never shown.
    static func strength(_ lift: TwinInput.Lift) -> Double { lift.weightKg * (1 + Double(min(lift.reps, 12)) / 30) }

    static func strengthAndSpeed(_ c: Context) -> TwinInsight? {
        let since = c.calendar.date(byAdding: .day, value: -70, to: c.input.now) ?? c.input.now
        var best: (slug: String, gain: Double, points: [TwinPoint])?
        for slug in strengthLifts.keys.sorted() {
            let sets = c.input.lifts.filter { $0.slug == slug && $0.date >= since && $0.weightKg > 0 && $0.reps > 0 }
            let byDay = Dictionary(grouping: sets) { c.day($0.date) }
                .map { (day: $0.key, value: $0.value.map(strength).max() ?? 0) }
                .sorted { $0.day < $1.day }
            guard byDay.count >= 4, let first = byDay.first, let last = byDay.last,
                  (c.calendar.dateComponents([.day], from: first.day, to: last.day).day ?? 0) >= 14 else { continue }
            let early = byDay.prefix(2).map(\.value).max() ?? 0, late = byDay.suffix(2).map(\.value).max() ?? 0
            guard early > 0 else { continue }
            let gain = late / early - 1
            if gain > (best?.gain ?? 0) {
                best = (slug, gain, byDay.map { TwinPoint(date: $0.day, value: ($0.value / early - 1) * 100) })
            }
        }
        guard let best, best.gain >= 0.05 else { return nil }
        let lift = strengthLifts[best.slug] ?? "squat"
        let gainText = "\(Int((best.gain * 100).rounded()))%"
        let weeks = max(1, Int((Double(c.calendar.dateComponents([.day], from: best.points.first?.date ?? c.input.now, to: best.points.last?.date ?? c.input.now).day ?? 0) / 7).rounded()))
        let sprints = c.input.tests.filter { $0.testID.contains("sprint") && !$0.higherIsBetter }.sorted { $0.date < $1.date }
        // Where speed doesn't decide (endurance, precision…), getting stronger is simply progress.
        guard c.family.speed, let id = sprints.last?.testID else {
            return TwinInsight(
                kind: .strengthRising, headline: "Your \(lift) is up \(gainText) in \(weeks) weeks.",
                detail: c.family.speed ? "Test your sprint (Academy → Performances → Tests) so the twin can see whether the strength carries into speed."
                    : "Strength you build now protects you and carries into every part of your sport.",
                strength: .strong, basis: "\(best.points.count) sessions", evidence: nil, values: [:], reason: "", positive: true)
        }
        let runs = sprints.filter { $0.testID == id }
        guard runs.count >= 2, let firstRun = runs.first, let lastRun = runs.last, firstRun.value > 0 else { return nil }
        let faster = (firstRun.value - lastRun.value) / firstRun.value
        guard faster < 0.015 else {
            return TwinInsight(
                kind: .strengthRising, headline: "Your \(lift) is up \(gainText) — and your \(firstRun.name.lowercased()) got faster with it.",
                detail: "The strength is carrying into speed. Keep the sprint work fresh and fast.",
                strength: .strong, basis: "\(best.points.count) sessions, \(runs.count) tests", evidence: nil, values: [:], reason: "", positive: true)
        }
        let sprintChange = abs(faster) <= 0.003 ? "no change" : (faster < 0 ? "a little slower" : "barely faster")
        return TwinInsight(
            kind: .strengthNotSpeed,
            headline: "Your \(lift) is up \(gainText), your \(firstRun.name.lowercased()) hasn't moved. The strength isn't turning into speed yet.",
            detail: "\(firstRun.name): \(String(format: "%.2f", firstRun.value)) s then, \(String(format: "%.2f", lastRun.value)) s now.",
            strength: runs.count >= 3 ? .strong : .emerging,
            basis: "\(best.points.count) sessions, \(runs.count) tests",
            evidence: TwinEvidence(style: .lines, points: best.points, unit: "%",
                                   caption: "Change since the start · coloured: \(lift) · white: \(firstRun.name.lowercased())",
                                   comparison: runs.map { TwinPoint(date: c.day($0.date), value: (firstRun.value - $0.value) / firstRun.value * 100) }),
            values: c.family.tokens.merging(["strengthGain": gainText, "sprintChange": sprintChange]) { $1 },
            reason: "Your \(lift) is up \(gainText), your sprint shows \(sprintChange).",
            positive: false, measure: best.gain - max(0, faster), measureText: gainText)
    }

    static func reflectionEvidence(_ c: Context, marking area: String, caption: String) -> TwinEvidence? {
        let points = c.reflections.suffix(14).compactMap { r in
            r.feeling.map { TwinPoint(date: r.date, value: Double($0), marked: r.needsWork.contains(area)) }
        }
        return points.count >= 3 ? TwinEvidence(style: .bars, points: points, unit: "/5", caption: caption) : nil
    }

    static func mistakeReplay(_ c: Context) -> TwinInsight? {
        let answer = c.input.intake["mistake"]
        let fromInterview = ["replay", "angry", "quiet"].contains(answer ?? "")
        let flagged = c.reflections.filter { $0.needsWork.contains("Focus") || $0.needsWork.contains("Decisions") }.count
        let fromData = flagged >= 2 && c.reflections.count >= 4
        guard fromInterview || fromData else { return nil }
        let habit = switch answer {
        case "angry": "get angry"
        case "quiet": "go quiet"
        default: "replay it"
        }
        let headline = fromInterview
            ? "After a mistake you \(habit) — and that's where the next play gets lost."
            : "Focus came up as the thing to work on in \(flagged) of your last \(c.reflections.count) reflections."
        var values = c.family.tokens
        if flagged >= 1, c.reflections.count >= 3 { values.merge(["mistakeCount": "\(flagged)", "reflectionCount": "\(c.reflections.count)"]) { $1 } }
        return TwinInsight(
            kind: .mistakeReplay, headline: headline,
            detail: fromData ? "In \(flagged) of \(c.reflections.count) evening reflections you named focus or decisions as the thing to work on."
                : "You told the twin that after a mistake you \(habit). A practised reset gets you to the next action.",
            strength: fromInterview && fromData ? .strong : .emerging,
            basis: fromData ? (fromInterview ? "your interview and reflections" : "\(c.reflections.count) reflections") : "your interview",
            evidence: reflectionEvidence(c, marking: "Focus", caption: "How your days felt · highlighted: focus was the thing to work on"),
            values: values,
            reason: fromInterview ? "You told your twin that after a mistake you \(habit)." : "Focus keeps coming up in your reflections.",
            positive: false)
    }

    static func pressureConfidence(_ c: Context) -> TwinInsight? {
        let pressure = c.input.intake["pressure"], source = c.input.intake["confidence"]
        let fromInterview = pressure == "tense" || pressure == "hide"
        let flagged = c.reflections.filter { $0.needsWork.contains("Confidence") }.count
        let fromData = flagged >= 2 && c.reflections.count >= 4
        guard fromInterview || fromData || source == "swings" else { return nil }
        let headline: String
        if pressure == "hide" {
            headline = "In big moments you'd rather the moment passed you by."
        } else if pressure == "tense" {
            headline = "In big moments you tense up and play it safe."
        } else if fromData {
            headline = "Confidence came up as the thing to work on in \(flagged) of your last \(c.reflections.count) reflections."
        } else {
            headline = "Your confidence comes and goes with the day."
        }
        var values = c.family.tokens
        if flagged >= 1, c.reflections.count >= 3 { values.merge(["confidenceCount": "\(flagged)", "reflectionCount": "\(c.reflections.count)"]) { $1 } }
        return TwinInsight(
            kind: .pressureConfidence, headline: headline,
            detail: "Confidence you can count on is built from preparation and evidence, not from waiting to feel it.",
            strength: fromInterview && fromData ? .strong : .emerging,
            basis: fromData ? (fromInterview ? "your interview and reflections" : "\(c.reflections.count) reflections") : "your interview",
            evidence: reflectionEvidence(c, marking: "Confidence", caption: "How your days felt · highlighted: confidence was the thing to work on"),
            values: values,
            reason: fromInterview ? "You told your twin how big moments feel for you." : "Confidence keeps coming up in your reflections.",
            positive: false)
    }

    // MARK: Patterns the coach explains

    /// Training load: minutes × effort (RPE 1–10; practice "how hard" 1–5 doubled; a
    /// competition counts as an hour at 8). This week against the three before.
    static func weeklyLoads(_ c: Context, weeks: Int = 4) -> [Double] {
        let today = c.day(c.input.now)
        return (0..<weeks).reversed().map { week -> Double in
            guard let end = c.calendar.date(byAdding: .day, value: -7 * week + 1, to: today),
                  let begin = c.calendar.date(byAdding: .day, value: -7, to: end) else { return 0 }
            func inWeek(_ d: Date) -> Bool { d >= begin && d < end }
            let sessions = c.input.loads.filter { inWeek($0.date) }.map { Double($0.minutes) * Double($0.rpe ?? 5) }
            let practices = c.input.practices.filter { inWeek($0.date) }.map { Double($0.minutes ?? 90) * Double($0.hard * 2) }
            let games = c.gameDays.filter { inWeek($0) }.map { _ in 60.0 * 8 }
            return (sessions + practices + games).reduce(0, +)
        }
    }

    static func loadSpike(_ c: Context) -> TwinInsight? {
        let loads = weeklyLoads(c)
        guard let current = loads.last else { return nil }
        let before = loads.dropLast()
        let active = before.filter { $0 > 0 }
        guard active.count >= 2 else { return nil }
        let usual = mean(Array(before))
        guard usual > 0 else { return nil }
        let ratio = current / usual
        guard ratio >= 1.5 else { return nil }
        let percent = Int(((ratio - 1) * 100).rounded())
        let today = c.day(c.input.now)
        let points = loads.enumerated().map { index, load in
            TwinPoint(date: c.calendar.date(byAdding: .day, value: -7 * (loads.count - 1 - index), to: today) ?? today,
                      value: load, marked: index == loads.count - 1)
        }
        return TwinInsight(
            kind: .loadSpike,
            headline: "Your training load jumped \(percent)% this week.",
            detail: "Big jumps are when injuries happen most. Sleep a little more, keep the next few days lighter if you can, and tell your coach if anything starts to hurt.",
            strength: ratio >= 1.8 ? .strong : .emerging,
            basis: "4 weeks of sessions",
            evidence: TwinEvidence(style: .bars, points: points, unit: "",
                                   caption: "Training load each week (minutes × effort) · highlighted: this week"),
            values: c.family.tokens, reason: "Your load jumped \(percent)% this week.", positive: false,
            measure: ratio - 1, measureText: "+\(percent)%")
    }

    static func sleepAffectsPractice(_ c: Context) -> TwinInsight? {
        var short: [Double] = [], long: [Double] = []
        var points: [TwinPoint] = []
        // went 0: a practice told in a sentence, how it went not said.
        for practice in c.input.practices where practice.date >= c.start && practice.date <= c.input.now && practice.went > 0 {
            guard let hours = c.mornings.first(where: { c.calendar.isDate($0.date, inSameDayAs: practice.date) })?.sleepHours else { continue }
            if hours < 7.5 { short.append(Double(practice.went)) } else { long.append(Double(practice.went)) }
            points.append(TwinPoint(date: practice.date, value: Double(practice.went), marked: hours < 7.5))
        }
        guard short.count >= 3, long.count >= 3 else { return nil }
        let drop = mean(long) - mean(short)
        guard drop >= 0.6 else { return nil }
        return TwinInsight(
            kind: .sleepAffectsPractice,
            headline: "After nights under 7½ hours, you rate your practice \(one(drop)) points lower.",
            detail: "Short nights: \(one(mean(short))) of 5. Longer nights: \(one(mean(long))) of 5. Sleep is where practice turns into progress — and it shows the next day.",
            strength: short.count >= 5 ? .strong : .emerging,
            basis: "\(short.count + long.count) practices",
            evidence: TwinEvidence(style: .bars, points: Array(points.suffix(16)), unit: "/5",
                                   caption: "How each practice went · highlighted: after a night under 7½ hours"),
            values: c.family.tokens, reason: "Your practice suffers after short nights.", positive: false,
            measure: drop, measureText: "\(one(drop)) points")
    }

    static func irregularSleep(_ c: Context) -> TwinInsight? {
        let nights = c.mornings.suffix(14).compactMap(\.sleepHours).filter { $0 > 0 }
        guard nights.count >= 7 else { return nil }
        let average = mean(nights)
        let spread = (nights.map { ($0 - average) * ($0 - average) }.reduce(0, +) / Double(nights.count)).squareRoot()
        guard spread >= 0.9, let low = nights.min(), let high = nights.max() else { return nil }
        return TwinInsight(
            kind: .irregularSleep,
            headline: "Your sleep swings from \(one(low)) to \(one(high)) hours.",
            detail: "Your body clock likes a rhythm. The same wake-up time most days — weekends too — steadies your energy more than catching up on Sunday.",
            strength: spread >= 1.2 ? .strong : .emerging,
            basis: "\(nights.count) nights",
            evidence: TwinEvidence(style: .bars,
                                   points: c.mornings.suffix(14).compactMap { m in m.sleepHours.map { TwinPoint(date: m.date, value: $0) } },
                                   unit: "h", caption: "Sleep each night, last two weeks"),
            values: c.family.tokens, reason: "Your sleep is irregular.", positive: false,
            measure: spread, measureText: "\(one(spread)) h swing")
    }

    static func stressAndSleep(_ c: Context) -> TwinInsight? {
        let recent = c.mornings.suffix(21).filter { $0.stress > 0 && ($0.sleepHours ?? 0) > 0 }
        let tense = recent.filter { $0.stress >= 4 }, calm = recent.filter { $0.stress < 4 }
        guard tense.count >= 3, calm.count >= 4 else { return nil }
        let gap = mean(calm.compactMap(\.sleepHours)) - mean(tense.compactMap(\.sleepHours))
        guard gap >= 0.5 else { return nil }
        return TwinInsight(
            kind: .stressAndSleep,
            headline: "Stressful days cost you \(duration(gap)) of sleep.",
            detail: "On \(tense.count) stressful days in three weeks you slept less. A short wind-down — phone away, write tomorrow's list, slow breathing — protects the night. If stress stays heavy, talk to someone you trust.",
            strength: tense.count >= 5 ? .strong : .emerging,
            basis: "\(recent.count) check-ins",
            evidence: TwinEvidence(style: .bars,
                                   points: recent.map { TwinPoint(date: $0.date, value: $0.sleepHours ?? 0, marked: $0.stress >= 4) },
                                   unit: "h", caption: "Sleep each night · highlighted: stressful days"),
            values: c.family.tokens, reason: "Stress is eating into your sleep.", positive: false,
            measure: gap, measureText: duration(gap))
    }

    // MARK: What's working

    static func consistentTraining(_ c: Context) -> TwinInsight? {
        let today = c.day(c.input.now)
        var total = 0
        for week in 0..<4 {
            guard let end = c.calendar.date(byAdding: .day, value: -7 * week, to: today),
                  let begin = c.calendar.date(byAdding: .day, value: -7, to: end) else { return nil }
            let count = (c.input.sessions + Array(c.gameDays)).filter { $0 > begin && $0 <= end.addingTimeInterval(86_399) }.count
            guard count >= 2 else { return nil }
            total += count
        }
        return TwinInsight(kind: .consistentTraining, headline: "You've trained or competed at least twice every week for a month.",
                           detail: "\(total) sessions and \(c.events) in four weeks. Consistency is what turns training into progress.",
                           strength: .strong, basis: "\(total) sessions", evidence: nil, values: [:], reason: "", positive: true)
    }

    static func sleepBase(_ c: Context) -> TwinInsight? {
        let recent = c.mornings.suffix(14).compactMap(\.sleepHours).filter { $0 > 0 }
        guard recent.count >= 5 else { return nil }
        let average = mean(recent)
        guard average >= 8 else { return nil }
        return TwinInsight(kind: .sleepBase, headline: "You average \(one(average)) h of sleep — a strong base.",
                           detail: "Most teenage athletes don't get there. It's where your training turns into progress.",
                           strength: .strong, basis: "\(recent.count) nights", evidence: nil, values: [:], reason: "", positive: true)
    }

    // MARK: The coach's read

    static func coachRead(_ insights: [TwinInsight], strengths: [TwinInsight], counts: TwinReport.Counts, hasIntake: Bool,
                          events: String = "games") -> String {
        let enough = counts.checkIns >= 5 || counts.sessions >= 3 || counts.games >= 1
        guard enough || !insights.isEmpty else {
            return hasIntake
                ? "Your twin knows who you are — now it needs your data. Check in each morning, log your sessions and add your \(events); in a couple of weeks it will show you what's really going on."
                : "Your twin needs to get to know you. Start with the interview, then check in each morning and log your sessions and \(events)."
        }
        var parts: [String] = []
        if let good = strengths.first {
            parts.append(good.headline)
        } else {
            parts.append("You're putting in the work.")
        }
        if let first = insights.first {
            parts.append("What matters most right now: \(lowercasedStart(first.headline))")
            if let briefing = first.briefing {
                parts.append("Read “\(briefing.title)” this week.")
            } else if let next = insights.dropFirst().first(where: { $0.briefing != nil }), let briefing = next.briefing {
                parts.append("Then read “\(briefing.title)”.")
            }
        } else {
            parts.append("Nothing in your data is holding you back right now — keep the habits that got you here.")
        }
        return parts.joined(separator: " ")
    }

    static func lowercasedStart(_ text: String) -> String {
        guard let first = text.first else { return text }
        // Keep "I" and acronyms as they are.
        let second = text.dropFirst().first
        if second.map({ $0.isUppercase }) == true { return text }
        return first.lowercased() + text.dropFirst()
    }
}
