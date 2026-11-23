import Foundation

// The shared athlete context (owner, 2026-11-23: "AthleteOS should never make
// the athlete repeatedly tell it something it already knows, and the workout
// algorithm should never ignore relevant information the athlete has already
// given it").
//
//   Tell AthleteOS · check-in · reflection · Health workout check · practice
//     → AthleteContextEvent (what the athlete reported, kept apart from what
//       the rules derive from it)
//     → unresolved events stay open until answered, superseded or expired
//     → the morning check-in asks only the follow-ups that can change a plan
//     → ContextSignals → TrainingDay → SessionPlanner.decide (unchanged pipeline)
//
// Foundation-only and deterministic. Profile settings (equipment, goals,
// schedule) stay where they are; this holds what is recent, temporary or open.

/// Where on the body the athlete felt it, in their words' grain.
public enum ContextRegion: String, Codable, Sendable, CaseIterable {
    case legs, calves, hamstrings, quads, hips, upperBody, shoulders, arms, chest, back, core, wholeBody

    /// The planner's region (whole body counts as legs and upper body).
    public var gymRegions: Set<GymRegion> {
        switch self {
        case .legs, .calves, .hamstrings, .quads, .hips: [.lower]
        case .upperBody, .shoulders, .arms, .chest, .back: [.upper]
        case .core: [.core]
        case .wholeBody: [.lower, .upper]
        }
    }

    /// "your legs", "your calves", "your body".
    public var phrase: String {
        switch self {
        case .legs: "your legs"
        case .calves: "your calves"
        case .hamstrings: "your hamstrings"
        case .quads: "your quads"
        case .hips: "your hips"
        case .upperBody: "your upper body"
        case .shoulders: "your shoulders"
        case .arms: "your arms"
        case .chest: "your chest"
        case .back: "your back"
        case .core: "your core"
        case .wholeBody: "your body"
        }
    }

    /// Plural regions read "they", the rest "it".
    var plural: Bool { ![.upperBody, .chest, .back, .core, .wholeBody].contains(self) }
}

/// A training quality the athlete was exposed to (from practice, a game,
/// their own workout, a Health workout).
public enum ContextQuality: String, Codable, Sendable, CaseIterable {
    case sprinting, conditioning, jumping, lowerStrength, upperStrength, core, skill, lowRunning

    public var title: String {
        switch self {
        case .sprinting: "sprinting"
        case .conditioning: "conditioning"
        case .jumping: "jumping"
        case .lowerStrength: "leg strength"
        case .upperStrength: "upper-body strength"
        case .core: "core work"
        case .skill: "skill work"
        case .lowRunning: "little running"
        }
    }
}

public enum ContextKind: String, Codable, Sendable {
    /// A body region feels tired or sore (not pain: pain has its own safety path).
    case fatigue
    /// What a session (practice, a game, the athlete's own workout) trained.
    case exposure
    /// Temporary equipment ("only dumbbells and a bench until Sunday").
    case equipment
    /// Temporary time ("only 30 minutes today").
    case time
}

public enum ContextSource: String, Codable, Sendable {
    case tellAthleteOS, morningCheckIn, reflection, healthWorkout, aosWorkout, practiceLog
}

public enum ContextResolution: String, Codable, Sendable {
    case open, resolved, expired, superseded
}

/// One thing the athlete told (or the app observed), structured.
public struct AthleteContextEvent: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var createdAt: Date
    /// The first day it applies (start of day).
    public var from: Date
    /// The last day it applies (nil: until resolved, or the expiry rule).
    public var until: Date?
    public var kind: ContextKind
    public var source: ContextSource
    /// What the athlete said, in short plain facts ("Legs very tired"). Never invented numbers.
    public var reported: [String]
    public var regions: [ContextRegion]
    public var qualities: [ContextQuality]
    /// Fatigue: 1 a little, 2 tired, 3 very tired. Exposure: 1 light, 2 normal, 3 a lot.
    public var level: Int
    /// The session behind an exposure was practice (or a game), not the athlete's own workout.
    public var practice: Bool
    /// Movement patterns of a reported workout ("squat", "hinge", "push", "pull").
    public var patterns: [String]
    /// Equipment tags available while it applies (`equipmentLevelByTag` keys).
    public var equipment: [String]
    public var minutes: Int?
    public var status: ContextResolution
    /// Morning answers to a fatigue event, oldest first.
    public var checks: [Check]
    /// An exposure this fatigue came from (a hard sprint practice → tired legs).
    public var relatedID: UUID?

    public struct Check: Codable, Sendable, Equatable {
        public var day: Date
        public var level: Int
        public init(day: Date, level: Int) {
            self.day = day
            self.level = level
        }
    }

    public init(id: UUID = UUID(), createdAt: Date = .now, from: Date, until: Date? = nil, kind: ContextKind, source: ContextSource,
                reported: [String] = [], regions: [ContextRegion] = [], qualities: [ContextQuality] = [], level: Int = 2,
                practice: Bool = false, patterns: [String] = [], equipment: [String] = [], minutes: Int? = nil,
                status: ContextResolution = .open, checks: [Check] = [], relatedID: UUID? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.from = from
        self.until = until
        self.kind = kind
        self.source = source
        self.reported = reported
        self.regions = regions
        self.qualities = qualities
        self.level = level
        self.practice = practice
        self.patterns = patterns
        self.equipment = equipment
        self.minutes = minutes
        self.status = status
        self.checks = checks
        self.relatedID = relatedID
    }

    /// The fatigue level now: the latest morning answer, or the level reported.
    public var currentLevel: Int { checks.last?.level ?? level }

    /// The day of the last thing known about it (reported or answered).
    public var lastKnown: Date { checks.last?.day ?? from }

    /// Whether it applies on `day` (dates only; resolution is checked separately).
    public func covers(_ day: Date, calendar: Calendar) -> Bool {
        let d = calendar.startOfDay(for: day)
        return calendar.startOfDay(for: from) <= d && (until.map { d <= calendar.startOfDay(for: $0) } ?? true)
    }
}

/// What the context means for one day's plan: read by TodayEngine, decided on by SessionPlanner.
public struct ContextSignals: Sendable, Equatable {
    /// 0 none … 3 very tired, by planner region (the most tired open event).
    public var fatigue: [GymRegion: Int] = [:]
    /// The regions the athlete named, for the explanation.
    public var fatigueRegions: [ContextRegion] = []
    /// A lot of sprinting yesterday or today (practice or a game).
    public var recentSprinting = false
    /// Practice today or yesterday was mostly conditioning: today's is covered.
    public var conditioningCovered = false
    /// A lot of jumping yesterday: jumps wait 48 hours.
    public var jumpedYesterday = false
    /// Equipment for the day, when a temporary restriction applies (nil: the athlete's usual).
    public var equipment: Set<String>?
    /// Minutes the athlete said they have that day (nil: not told).
    public var minutes: Int?
    /// Practice reported as light ("barely ran, mostly shooting").
    public var lightPractice = false
    /// Practice reported as very hard.
    public var hardPractice = false

    public init() {}

    public var lowerFatigue: Int { fatigue[.lower] ?? 0 }
    public var upperFatigue: Int { fatigue[.upper] ?? 0 }
    public var isEmpty: Bool { self == ContextSignals() }
}

/// A morning follow-up the check-in asks.
public struct ContextQuestion: Sendable, Equatable, Identifiable {
    public enum Answer: String, Sendable, CaseIterable {
        case backToNormal, aLittleTired, same, veryTired, worse

        /// The fatigue level the answer means (0: recovered), given the level before.
        public func level(after previous: Int) -> Int {
            switch self {
            case .backToNormal: 0
            case .aLittleTired: 1
            case .same: max(1, previous)
            case .veryTired, .worse: 3
            }
        }
    }

    /// The event it follows up (or the exposure it asks about).
    public var id: UUID
    /// "Yesterday" / "Since Monday" — the small line above the question.
    public var eyebrow: String
    public var context: String?
    public var question: String
    public var options: [Option]
    /// The planner regions an answer covers (a legs answer stands in for "how sore are you?").
    public var covers: Set<GymRegion>
    /// The region asked about.
    public var region: ContextRegion

    public struct Option: Sendable, Hashable {
        public var answer: Answer
        public var title: String
        public init(_ answer: Answer, _ title: String) {
            self.answer = answer
            self.title = title
        }
    }
}

public enum AthleteContext {
    /// An open fatigue nobody answered about for this many days ends on its own.
    public static let fatigueExpiryDays = 4
    /// Exposures count for the planner's week.
    public static let exposureDays = 7
    /// Follow-ups the morning check-in may ask (pain is asked separately, always).
    public static let questionBudget = 2

    // MARK: Lifecycle

    /// Applies the explicit end rules: an open fatigue not heard about for
    /// `fatigueExpiryDays` days expires; temporary equipment and time end after their last day.
    public static func expire(_ events: [AthleteContextEvent], now: Date, calendar: Calendar = .current) -> [AthleteContextEvent] {
        let today = calendar.startOfDay(for: now)
        return events.map { event in
            var e = event
            guard e.status == .open else { return e }
            switch e.kind {
            case .fatigue:
                let since = calendar.dateComponents([.day], from: calendar.startOfDay(for: e.lastKnown), to: today).day ?? 0
                if since >= fatigueExpiryDays { e.status = .expired }
            case .equipment, .time:
                if let until = e.until, calendar.startOfDay(for: until) < today { e.status = .expired }
            case .exposure:
                let since = calendar.dateComponents([.day], from: calendar.startOfDay(for: e.from), to: today).day ?? 0
                if since > exposureDays { e.status = .expired }
            }
            return e
        }
    }

    /// Adds an event. A new fatigue for a region supersedes the open one it
    /// replaces; new equipment or time for the same days supersedes the old.
    public static func adding(_ event: AthleteContextEvent, to events: [AthleteContextEvent], calendar: Calendar = .current) -> [AthleteContextEvent] {
        var out = events.map { old -> AthleteContextEvent in
            var o = old
            guard o.status == .open, o.kind == event.kind else { return o }
            switch event.kind {
            case .fatigue:
                if !Set(o.regions).isDisjoint(with: event.regions) || (o.regions == [.wholeBody] && event.regions == [.wholeBody]) {
                    o.status = .superseded
                }
            case .equipment, .time:
                if o.covers(event.from, calendar: calendar) || event.covers(o.from, calendar: calendar) { o.status = .superseded }
            case .exposure:
                break
            }
            return o
        }
        out.append(event)
        // Keep a few weeks: older history isn't read by anything.
        return Array(out.suffix(120))
    }

    /// The athlete answered a follow-up: back to normal resolves it.
    public static func answering(_ answer: ContextQuestion.Answer, to id: UUID, in events: [AthleteContextEvent], now: Date,
                                 calendar: Calendar = .current) -> [AthleteContextEvent] {
        let today = calendar.startOfDay(for: now)
        return events.map { event in
            guard event.id == id else { return event }
            var e = event
            e.checks.removeAll { calendar.isDate($0.day, inSameDayAs: today) }
            e.checks.append(.init(day: today, level: answer.level(after: e.currentLevel)))
            if answer == .backToNormal { e.status = .resolved }
            return e
        }
    }

    // MARK: What the plan reads

    public static func signals(_ events: [AthleteContextEvent], on date: Date, calendar: Calendar = .current) -> ContextSignals {
        let day = calendar.startOfDay(for: date)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        var s = ContextSignals()
        for e in events where e.status == .open {
            switch e.kind {
            case .fatigue:
                // Reported on or before this day and still open.
                guard calendar.startOfDay(for: e.from) <= day else { continue }
                for region in e.regions {
                    for g in region.gymRegions { s.fatigue[g] = max(s.fatigue[g] ?? 0, e.currentLevel) }
                    if e.currentLevel > 0, !s.fatigueRegions.contains(region) { s.fatigueRegions.append(region) }
                }
            case .exposure:
                let on = calendar.startOfDay(for: e.from)
                guard on == day || on == yesterday else { continue }
                if e.qualities.contains(.sprinting), e.level >= 3 { s.recentSprinting = true }
                if e.qualities.contains(.conditioning), e.level >= 3, e.practice { s.conditioningCovered = true }
                if e.qualities.contains(.jumping), e.level >= 3, on == yesterday { s.jumpedYesterday = true }
                if e.practice, on == day {
                    if e.qualities.contains(.lowRunning) || e.level <= 1 { s.lightPractice = true }
                    if e.level >= 3 { s.hardPractice = true }
                }
            case .equipment:
                guard e.covers(day, calendar: calendar) else { continue }
                s.equipment = Set(e.equipment)
            case .time:
                guard e.covers(day, calendar: calendar), let minutes = e.minutes else { continue }
                s.minutes = min(s.minutes ?? minutes, minutes)
            }
        }
        // A whole-body or legs answer of "normal" leaves nothing to report.
        s.fatigue = s.fatigue.filter { $0.value > 0 }
        return s
    }

    /// The athlete's own workouts and reported practices as the planner's past days.
    public static func pastLoads(_ events: [AthleteContextEvent], before date: Date, calendar: Calendar = .current) -> [DayLoad] {
        let day = calendar.startOfDay(for: date)
        var byDay: [Int: DayLoad] = [:]
        for e in events where e.kind == .exposure && e.status != .superseded {
            let ago = calendar.dateComponents([.day], from: calendar.startOfDay(for: e.from), to: day).day ?? 99
            guard (1...7).contains(ago) else { continue }
            var load = byDay[ago] ?? DayLoad(daysAgo: ago)
            var capacities = Set(load.capacities)
            for q in e.qualities {
                switch q {
                case .sprinting: capacities.formUnion([.speed, .acceleration])
                case .conditioning: capacities.insert(.repeatedEffort)
                case .jumping: capacities.insert(.power)
                case .lowerStrength: capacities.insert(.strength)
                case .upperStrength: capacities.insert(.upperStrength)
                case .core: capacities.insert(.trunk)
                case .skill, .lowRunning: break
                }
            }
            load.capacities = capacities.sorted { $0.rawValue < $1.rawValue }
            if e.practice, load.practice == nil {
                load.practice = e.level >= 3 ? .hard : e.level <= 1 ? .light : .normal
            }
            if !e.practice {
                if let lower = e.patterns.first(where: { ["squat", "hinge", "lunge"].contains($0) }) {
                    load.lowerPattern = load.lowerPattern ?? (lower == "hinge" ? "hinge" : "squat")
                }
                if let upper = e.patterns.first(where: { ["push", "pull"].contains($0) }) { load.upperPattern = load.upperPattern ?? upper }
                if e.qualities.contains(.lowerStrength), e.level >= 3 { load.heavyLower = true }
                if e.qualities.contains(.upperStrength) || e.qualities.contains(.lowerStrength) {
                    load.sessionType = load.sessionType ?? .gymDevelopment
                }
            }
            byDay[ago] = load
        }
        return byDay.values.sorted { $0.daysAgo < $1.daysAgo }
    }

    /// Days since each region last got strength work in a workout the athlete
    /// reported (Tell AthleteOS), for the gym advisor's region recency.
    public static func regionDays(_ events: [AthleteContextEvent], now: Date, calendar: Calendar = .current) -> [GymRegion: Int] {
        let day = calendar.startOfDay(for: now)
        var out: [GymRegion: Int] = [:]
        for e in events where e.kind == .exposure && !e.practice && e.status != .superseded {
            let ago = calendar.dateComponents([.day], from: calendar.startOfDay(for: e.from), to: day).day ?? 99
            guard (0...14).contains(ago) else { continue }
            var regions: Set<GymRegion> = []
            if e.qualities.contains(.lowerStrength) { regions.insert(.lower) }
            if e.qualities.contains(.upperStrength) { regions.insert(.upper) }
            if e.qualities.contains(.core) { regions.insert(.core) }
            for region in regions { out[region] = min(out[region] ?? 99, ago) }
        }
        return out
    }

    // MARK: Morning follow-ups

    /// The follow-ups worth asking this morning, most important first, within
    /// the budget. Only what can change today's plan: tired regions change leg
    /// or upper-body work; a hard session yesterday with nothing said about the
    /// body is asked about once. Pain is never here: the check-in always asks it.
    public static func questions(_ events: [AthleteContextEvent], now: Date, calendar: Calendar = .current) -> [ContextQuestion] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var out: [ContextQuestion] = []
        var asked: Set<ContextRegion> = []

        // 1. Open fatigue reported before today, most tired first, newest first.
        let open = events
            .filter { $0.kind == .fatigue && $0.status == .open && calendar.startOfDay(for: $0.from) < today }
            .sorted { $0.currentLevel != $1.currentLevel ? $0.currentLevel > $1.currentLevel : $0.lastKnown > $1.lastKnown }
        for e in open {
            guard let region = e.regions.first(where: { !asked.contains($0) }) else { continue }
            asked.formUnion(e.regions)
            out.append(fatigueQuestion(e, region: region, today: today, calendar: calendar, events: events))
        }

        // 2. A hard session yesterday (a lot of sprinting, conditioning or
        // jumping) with nothing said about the legs: ask once how they feel.
        if !asked.contains(where: { $0.gymRegions.contains(.lower) }) {
            let hard = events.first { e in
                e.kind == .exposure && e.status != .superseded && calendar.isDate(e.from, inSameDayAs: yesterday) && e.level >= 3
                    && !Set(e.qualities).isDisjoint(with: [.sprinting, .conditioning, .jumping, .lowerStrength])
                    && !events.contains { $0.kind == .fatigue && $0.relatedID == e.id }
            }
            if let hard {
                let what = hard.practice ? "practice" : "workout"
                let detail = hard.qualities.filter { [.sprinting, .conditioning, .jumping].contains($0) }.map(\.title).first
                out.append(ContextQuestion(
                    id: hard.id, eyebrow: "Yesterday",
                    context: "You said \(what) was hard\(detail.map { ", with a lot of \($0)" } ?? "").",
                    question: "How do your legs feel this morning?",
                    options: [.init(.backToNormal, "Fresh"), .init(.aLittleTired, "A little tired"), .init(.veryTired, "Very tired"),
                              .init(.worse, "Sore and heavy")],
                    covers: [.lower], region: .legs))
            }
        }
        return Array(out.prefix(questionBudget))
    }

    static let firstOptions: [ContextQuestion.Option] = [
        .init(.backToNormal, "Back to normal"), .init(.aLittleTired, "A little tired"), .init(.veryTired, "Still very tired"), .init(.worse, "Worse"),
    ]

    static func fatigueQuestion(_ e: AthleteContextEvent, region: ContextRegion, today: Date, calendar: Calendar,
                                events: [AthleteContextEvent]) -> ContextQuestion {
        let covers = e.regions.reduce(into: Set<GymRegion>()) { $0.formUnion($1.gymRegions) }
        let name = region.phrase
        if let last = e.checks.last(where: { calendar.startOfDay(for: $0.day) < today }) {
            // Asked before: compare with yesterday's answer.
            let lastWord = last.level >= 3 ? "very tired" : last.level == 2 ? "tired" : "a little tired"
            let ago = calendar.dateComponents([.day], from: calendar.startOfDay(for: last.day), to: today).day ?? 1
            return ContextQuestion(
                id: e.id, eyebrow: ago <= 1 ? "Yesterday" : "Earlier this week",
                context: "\(name.prefix(1).uppercased() + name.dropFirst()) \(region.plural ? "were" : "was") still \(lastWord).",
                question: "How \(region.plural ? "are" : "is") \(name) compared with \(ago <= 1 ? "yesterday" : "then")?",
                options: [.init(.backToNormal, "Back to normal"), .init(.aLittleTired, "Better, a little tired"),
                          .init(.same, "About the same"), .init(.worse, "Worse")],
                covers: covers, region: region)
        }
        let ago = calendar.dateComponents([.day], from: calendar.startOfDay(for: e.from), to: today).day ?? 1
        let word = e.level >= 3 ? "very tired" : e.level == 2 ? "tired" : "a little tired"
        var why = ""
        if let related = e.relatedID, let exposure = events.first(where: { $0.id == related }) {
            let sprint = exposure.qualities.contains(.sprinting)
            let session = exposure.practice ? "practice" : "workout"
            why = sprint ? " after a sprint-heavy \(session)" : exposure.level >= 3 ? " after a hard \(session)" : ""
        }
        return ContextQuestion(
            id: e.id, eyebrow: ago <= 1 ? "Yesterday" : ago == 2 ? "Two days ago" : "Earlier this week",
            context: "You said \(name) \(region.plural ? "were" : "was") \(word)\(why).",
            question: region.plural ? "How do they feel this morning?" : "How does it feel this morning?",
            options: firstOptions, covers: covers, region: region)
    }

    /// An answer to "how do your legs feel?" after a hard session (no fatigue
    /// event yet): tired legs become an open event the next mornings follow.
    public static func fatigueFromAnswer(_ answer: ContextQuestion.Answer, to exposure: AthleteContextEvent, now: Date,
                                         calendar: Calendar = .current) -> AthleteContextEvent? {
        guard answer != .backToNormal else { return nil }
        let today = calendar.startOfDay(for: now)
        let level = answer.level(after: 2)
        let word = level >= 3 ? "very tired" : level == 2 ? "tired" : "a little tired"
        return AthleteContextEvent(createdAt: now, from: today, kind: .fatigue, source: .morningCheckIn,
                                   reported: ["Legs \(word) this morning"], regions: [.legs], level: level,
                                   checks: [.init(day: today, level: level)], relatedID: exposure.id)
    }

    /// What a follow-up answer means for "How sore are you?" (the check-in's
    /// scale: 1 none, 2 mild, 3 moderate, 5 high), so it isn't asked again.
    public static func soreness(for answer: ContextQuestion.Answer, previous: Int = 2) -> Int {
        switch answer.level(after: previous) {
        case 0: 1
        case 1: 2
        case 2: 3
        default: 5
        }
    }
}
