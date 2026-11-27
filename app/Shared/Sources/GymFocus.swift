import Foundation

// The gym, chosen by the athlete (owner, 2026-11-19): tap Gym, pick what to
// train — upper body, legs, core, full body or "you pick" — and how long.
// Every focus has a few anchor lifts that stay the same for a block of four
// weeks, so progress is real and measurable, and accessories that rotate every
// session, so it never goes stale. "You pick" reads what was trained when,
// what has stalled, the sport, practice, games, readiness and sleep.
// Evidence: docs/GYM-ALGORITHM-RESEARCH.md.

/// What a gym session trains.
public enum GymFocus: String, Codable, Sendable, CaseIterable, Identifiable {
    case auto, upper, lower, core, full

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: "You pick"
        case .upper: "Upper body"
        case .lower: "Legs"
        case .core: "Core"
        case .full: "Full body"
        }
    }

    public var symbol: String {
        switch self {
        case .auto: "sparkles"
        case .upper: "figure.arms.open"
        case .lower: "figure.step.training"
        case .core: "figure.core.training"
        case .full: "figure.strengthtraining.traditional"
        }
    }

    /// The focuses an athlete can pick themselves.
    public static let choices: [GymFocus] = [.upper, .lower, .core, .full]

    /// The regions a focus loads with strength work.
    public var regions: Set<GymRegion> {
        switch self {
        case .auto: []
        case .upper: [.upper]
        case .lower: [.lower]
        case .core: [.core]
        case .full: [.upper, .lower, .core]
        }
    }
}

/// How long the athlete has.
public enum GymLength: Int, Codable, Sendable, CaseIterable, Identifiable {
    case quick = 30
    case standard = 60
    case full = 90

    public var id: Int { rawValue }
    public var minutes: Int { rawValue }

    public var title: String {
        switch self {
        case .quick: "Quick"
        case .standard: "Standard"
        case .full: "Full"
        }
    }

    /// One line on what the length holds.
    public var detail: String {
        switch self {
        case .quick: "The anchor lifts, nothing extra"
        case .standard: "Anchors, power and accessories"
        case .full: "Everything, plus a bike or rower finisher"
        }
    }
}

/// A body region, for "what was trained when".
public enum GymRegion: String, Codable, Sendable, CaseIterable {
    case upper, lower, core

    public var title: String {
        switch self {
        case .upper: "upper body"
        case .lower: "legs"
        case .core: "core"
        }
    }

    /// Days a region wants between hard strength sessions: heavy legs 72 h,
    /// upper body 48 h, core any day (research rule 3, Sousa 2024).
    var recoveryDays: Int {
        switch self {
        case .lower: 3
        case .upper: 2
        case .core: 0
        }
    }

    /// Days between sessions that keep the region developing (about twice a
    /// week per muscle group; core every other day is fine).
    var targetGap: Double {
        switch self {
        case .lower: 3.5
        case .upper: 3.5
        case .core: 2.5
        }
    }
}

/// What the athlete's own training history says about each region.
public struct GymHistory: Sendable, Equatable {
    /// Days since the region last got strength work (nil: not in the last 14 days).
    public var daysSince: [GymRegion: Int]
    /// Sessions that trained the region in the last 7 days.
    public var weekCount: [GymRegion: Int]
    /// Anchor lifts that haven't gone up in their last three sessions.
    public var stalledAnchors: Set<String>
    /// Regions with a stalled anchor.
    public var stalledRegions: Set<GymRegion>
    /// The accessories of the last session per focus, so the next one rotates.
    public var lastAccessories: [GymFocus: Set<String>]
    /// Hours slept last night when a watch or Health measured it (nil: not measured).
    public var measuredSleepHours: Double?
    /// Average measured sleep over the last three nights (nil: fewer than two nights measured).
    public var measuredSleepAverage: Double?
    /// When the region's last session was a workout from Health the athlete
    /// rated: the days it wants after that effort (`WorkoutTagging.recoveryDays`).
    public var recoveryOverride: [GymRegion: Int]
    /// The twin lengthened leg rest after the newest hard leg session (T10):
    /// the rest the legs would have had otherwise, and the twin's days. Lets
    /// the advisor say *why* legs wait one more day.
    public var legsUsualDays: Int? = nil
    public var legsTwinDays: Int? = nil

    /// Days until legs are ready, while only the twin's extra time holds them.
    public var legsHeldByTwin: Int? {
        guard let usual = legsUsualDays, let twin = legsTwinDays, let since = daysSince[.lower],
              since >= usual, twin - since > 0 else { return nil }
        return twin - since
    }

    public init(daysSince: [GymRegion: Int] = [:], weekCount: [GymRegion: Int] = [:], stalledAnchors: Set<String> = [],
                stalledRegions: Set<GymRegion> = [], lastAccessories: [GymFocus: Set<String>] = [:],
                measuredSleepHours: Double? = nil, measuredSleepAverage: Double? = nil,
                recoveryOverride: [GymRegion: Int] = [:]) {
        self.recoveryOverride = recoveryOverride
        self.daysSince = daysSince
        self.weekCount = weekCount
        self.stalledAnchors = stalledAnchors
        self.stalledRegions = stalledRegions
        self.lastAccessories = lastAccessories
        self.measuredSleepHours = measuredSleepHours
        self.measuredSleepAverage = measuredSleepAverage
    }

    /// Days the region wants between hard sessions, after its last one.
    public func recoveryDays(_ region: GymRegion) -> Int {
        recoveryOverride[region] ?? region.recoveryDays
    }

    /// Regions still recovering, with the days until they're ready for hard
    /// work again (1 = tomorrow). Legs first, then upper body, then core.
    public var stillRecovering: [(region: GymRegion, days: Int)] {
        [GymRegion.lower, .upper, .core].compactMap { region in
            guard let since = daysSince[region] else { return nil }
            let left = recoveryDays(region) - since
            return left > 0 ? (region, left) : nil
        }
    }
}

/// The athlete's gym choice for a session, resolved (never `.auto`).
public struct GymRequest: Sendable, Equatable {
    public var focus: GymFocus
    public var length: GymLength
    /// Stable for a block of four weeks: the anchors are picked with it.
    public var anchorSeed: String
    public var stalledAnchors: Set<String>
    public var lastAccessories: Set<String>
    /// Why this focus, in one sentence (from the advisor, or the athlete's own pick).
    public var note: String?

    public init(focus: GymFocus, length: GymLength, anchorSeed: String, stalledAnchors: Set<String> = [],
                lastAccessories: Set<String> = [], note: String? = nil) {
        self.focus = focus == .auto ? .full : focus
        self.length = length
        self.anchorSeed = anchorSeed
        self.stalledAnchors = stalledAnchors
        self.lastAccessories = lastAccessories
        self.note = note
    }

    /// Anchors stay for four weeks, then the block changes (research rule 3).
    public static func block(for date: Date) -> Int {
        Int(date.timeIntervalSince1970 / (28 * 86_400))
    }
}

/// "You pick": which focus today, and why — in the athlete's words.
public struct GymAdvice: Sendable, Equatable {
    public var focus: GymFocus
    public var length: GymLength
    /// One sentence: "Legs today — upper body yesterday, core two days ago."
    public var reason: String
    /// Focuses that aren't a good idea today, with the reason ("Game tomorrow").
    public var notToday: [GymFocus: String]
}

public enum GymAdvisor {
    /// The best focus and length for today. Safety first (games, sore legs,
    /// recovery between sessions), then what's been missing longest, then the
    /// sport and the athlete's goals.
    public static func advise(day: TrainingDay, history: GymHistory) -> GymAdvice {
        var notToday: [GymFocus: String] = [:]
        // Legs: recovery between sessions, games, practice, soreness.
        var legsBlocked: String?
        if day.gameToday { legsBlocked = "Game today" }
        else if day.daysToNextGame == 1 { legsBlocked = "Game tomorrow — legs stay fresh" }
        else if day.daysSinceLastGame == 1 { legsBlocked = "You played yesterday" }
        else if day.twinHoldsLegsAfterGame { legsBlocked = "You usually still feel a game two days later" }
        else if day.context.lowerFatigue >= 2 { legsBlocked = "You said your legs are still tired" }
        else if day.soreLegs { legsBlocked = "Your legs are sore" }
        else if day.practice == .hard { legsBlocked = "Hard practice today already loads your legs" }
        else if let left = history.legsHeldByTwin, let days = history.legsTwinDays {
            // The twin's own finding, said as such (one analyst, every why traceable).
            legsBlocked = "Your legs usually need \(days) days after a hard session — ready \(left == 1 ? "tomorrow" : "in \(left) days")"
        }
        else if let since = history.daysSince[.lower], since < history.recoveryDays(.lower) {
            let left = history.recoveryDays(.lower) - since
            legsBlocked = since == 0 ? "Legs trained today" : since == 1 ? "Legs trained yesterday"
                : "Legs trained \(since == 2 ? "two" : "\(since)") days ago — \(left == 1 ? "one more day" : "\(left) more days") to recover"
        }
        else if let hours = history.measuredSleepHours, hours < 6 { legsBlocked = "Under 6 h of sleep — no heavy legs today" }
        else if let heavy = day.recent.daysSinceHeavyLower, heavy <= 1 { legsBlocked = "Legs trained yesterday" }
        if let legsBlocked {
            notToday[.lower] = legsBlocked
            notToday[.full] = legsBlocked
        }
        if day.context.upperFatigue >= 2 {
            notToday[.upper] = "You said your upper body is still tired"
            if notToday[.full] == nil { notToday[.full] = "You said your upper body is still tired" }
        } else if let since = history.daysSince[.upper], since < history.recoveryDays(.upper) {
            let why = since == 0 ? "Upper body trained today" : "Upper body trained yesterday"
            notToday[.upper] = why
            if notToday[.full] == nil { notToday[.full] = why }
        }

        // Two days before a game legs may train, but short and light (Part 2, A6):
        // allowed, not first choice.
        let gameInTwo = day.daysToNextGame == 2 && legsBlocked == nil

        // Need: how overdue each region is, plus the sport and goals.
        func need(_ region: GymRegion) -> Double {
            let gap = history.daysSince[region].map(Double.init) ?? 14
            var value = min(gap / region.targetGap, 2.5)
            switch region {
            case .lower:
                if day.goals.contains(where: { [.strength, .power, .acceleration, .speed].contains($0) }) { value += 0.3 }
                if day.phase == .inSeason {
                    // In season practice loads the legs most days — but leg strength
                    // fades after about a week without a heavy exposure (Part 2, A4).
                    if gap >= 8 { value += 0.6 } else if day.demands.practiceLegLoad >= 2 { value -= 0.3 }
                }
                if gameInTwo { value -= 0.5 }
            case .upper:
                if day.goals.contains(.upperStrength) { value += 0.3 }
                value += 0.2 * (day.demands.weights[.upperStrength] ?? 0)
            case .core:
                value -= 0.35 // core rides along in every session; on its own only when it's the gap
            }
            if history.stalledRegions.contains(region) { value += 0.15 }
            return value
        }
        var scores: [GymFocus: Double] = [
            .upper: need(.upper),
            .lower: need(.lower),
            .core: need(.core),
        ]
        // Full body is best when both halves are due — and for athletes who
        // only get to the gym once or twice a week (research rule 2).
        let fewGymDays = day.recent.gymSessions <= 1 || day.stage == .foundation
        scores[.full] = min(need(.upper), need(.lower)) + (fewGymDays ? 0.45 : 0.05)
        let ranked = GymFocus.choices
            .filter { notToday[$0] == nil }
            .sorted { (scores[$0] ?? 0) != (scores[$1] ?? 0) ? (scores[$0] ?? 0) > (scores[$1] ?? 0) : $0.rawValue < $1.rawValue }
        let focus = ranked.first ?? .core

        // Length: shorter when sleep was short or the body is below normal;
        // in season the gym keeps strength, it doesn't chase more.
        var length: GymLength = day.phase == .inSeason || day.stage == .foundation ? .quick : .standard
        if day.phase == .offSeason, day.experience != .beginner, day.age >= 15 { length = .standard }
        var sleepNote: String?
        if let hours = history.measuredSleepHours, hours < 7 {
            length = .quick
            sleepNote = "you slept \(Self.hours(hours)) — shorter today"
        } else if let average = history.measuredSleepAverage, average < 7 {
            length = .quick
            sleepNote = "sleep has been short lately (\(Self.hours(average)) a night)"
        } else if day.readiness < .normal {
            length = .quick
        }

        return GymAdvice(focus: focus, length: length, reason: reason(focus, history: history, notToday: notToday, sleepNote: sleepNote, day: day),
                         notToday: notToday)
    }

    static func hours(_ value: Double) -> String {
        let rounded = (value * 2).rounded() / 2
        return rounded == rounded.rounded() ? "\(Int(rounded)) h" : String(format: "%.1f h", rounded)
    }

    static func ago(_ days: Int?) -> String {
        guard let days else { return "not in two weeks" }
        switch days {
        case 0: return "today"
        case 1: return "yesterday"
        case 2: return "two days ago"
        default: return "\(days) days ago"
        }
    }

    /// "Legs today: upper body yesterday, core two days ago."
    static func reason(_ focus: GymFocus, history: GymHistory, notToday: [GymFocus: String], sleepNote: String?, day: TrainingDay) -> String {
        var parts: [String] = []
        let others = GymRegion.allCases.filter { !focus.regions.contains($0) }
        // Legs blocked by recovery already says when they were trained: say it once.
        let legsNote = notToday[.lower].flatMap { focus != .lower && focus != .full ? $0 : nil }
        for region in others {
            if region == .lower, legsNote != nil, (history.daysSince[.lower] ?? 99) < history.recoveryDays(.lower) { continue }
            if let days = history.daysSince[region], days <= 3 { parts.append("\(region.title) \(ago(days))") }
        }
        var sentence = "\(focus.title) today"
        if focus == .full {
            if parts.isEmpty { parts.append("everything is fresh") }
        } else if let own = focus.regions.first, let days = history.daysSince[own], days >= 3 {
            parts.append("\(own.title) last \(ago(days))")
        } else if let own = focus.regions.first, history.daysSince[own] == nil {
            parts.append("\(own.title) not trained in two weeks")
        }
        if let legsNote { parts.append(legsNote.prefix(1).lowercased() + legsNote.dropFirst()) }
        if let region = focus.regions.first(where: history.stalledRegions.contains) { parts.append("\(region.title) stalled — new angle on it") }
        if day.daysToNextGame == 2, notToday[.lower] == nil {
            parts.append(focus.regions.contains(.lower) ? "game in two days, so legs stay short and light" : "game in two days, legs stay fresh")
        } else if day.phase == .inSeason, focus.regions.contains(.lower), (history.daysSince[.lower] ?? 14) >= 8 {
            parts.append("a week without heavy legs is when strength starts to fade in season")
        }
        if let sleepNote { parts.append(sleepNote) }
        if parts.isEmpty { return sentence + "." }
        return sentence + ": " + parts.joined(separator: ", ") + "."
    }
}

/// Anchor lifts per focus: the slots the block keeps for four weeks. Each slot
/// lists substitution families, best first (equipment, age and pain decide).
enum GymSlots {
    struct Slot {
        let block: SessionBlock
        let groups: [String]
        let why: String
    }

    static func anchors(_ focus: GymFocus, legBudget: Int) -> [Slot] {
        let squat = Slot(block: .primaryStrength, groups: ["squat-bilateral", "single-leg-knee"],
                         why: "Anchor: squat strength — the base for acceleration, jumping and landing.")
        let hinge = Slot(block: .primaryStrength, groups: ["hinge-bilateral", "hinge-hip-extension", "single-leg-hip"],
                         why: "Anchor: hip-hinge strength — the engine for sprinting and jumping.")
        let singleLeg = Slot(block: .secondaryStrength, groups: ["single-leg-knee", "single-leg-hip", "single-leg-lateral"],
                             why: "Anchor: one leg at a time — how you actually run, cut and land.")
        let pressH = Slot(block: .primaryStrength, groups: ["push-horizontal", "push-incline"],
                          why: "Anchor: pressing strength for pushing, blocking and fending.")
        let rowH = Slot(block: .primaryStrength, groups: ["pull-horizontal", "pull-vertical"],
                        why: "Anchor: pulling strength — balances all the pushing and throwing in sport.")
        let pullV = Slot(block: .secondaryStrength, groups: ["pull-vertical", "pull-horizontal"],
                         why: "Anchor: vertical pull for the lats and shoulder health.")
        let pressV = Slot(block: .secondaryStrength, groups: ["push-vertical", "push-incline"],
                          why: "Anchor: overhead strength for throwing, reaching and contesting.")
        let antiExt = Slot(block: .accessory, groups: ["anti-extension"], why: "Anchor: a trunk that resists arching — protects the lower back.")
        let antiRot = Slot(block: .accessory, groups: ["anti-rotation"], why: "Anchor: a trunk that resists twisting passes force from legs to arms.")
        let antiLat = Slot(block: .accessory, groups: ["anti-lateral", "carry"], why: "Anchor: side strength for cutting, contact and balance.")
        // Research rule 5: upper = one push + one pull, legs = one squat + one
        // hinge, core = anti-extension + anti-rotation, full = lower + upper.
        _ = (pullV, pressV, antiLat)
        switch focus {
        case .lower, .auto:
            return legBudget >= 2 ? [squat, hinge] : [singleLeg]
        case .upper:
            return [pressH, rowH]
        case .core:
            return [antiExt, antiRot]
        case .full:
            return legBudget >= 2 ? [squat, pressH, rowH] : [pressH, rowH]
        }
    }

    /// Rotating accessories per focus: picked fresh every session.
    static func accessories(_ focus: GymFocus) -> [[String]] {
        switch focus {
        case .lower, .auto:
            return [["single-leg-knee", "single-leg-hip"], ["hamstring-eccentric"], ["single-leg-lateral"], ["calf-ankle"], ["hip-adductor"],
                    ["knee-isometric", "knee-eccentric"], ["hinge-hip-extension"]]
        case .upper:
            return [["pull-vertical"], ["push-vertical", "push-incline"], ["shoulder-health"], ["arm-isolation"], ["grip"], ["neck"]]
        case .core:
            return [["anti-lateral", "carry"], ["rotation"], ["back-extension"], ["balance"]]
        case .full:
            return [["single-leg-knee", "single-leg-hip"], ["pull-vertical"], ["hamstring-eccentric", "single-leg-lateral"], ["shoulder-health"], ["carry"]]
        }
    }
}
