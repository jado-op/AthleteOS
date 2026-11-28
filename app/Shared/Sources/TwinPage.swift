import Foundation

/// The Twin page's order (owner, 2026-11-27: "shape the twin page around the
/// ecosystem"; research: inverted pyramid, one salient element, explanation
/// where the fact is, progress as real counts). Four parts:
/// 1. a stable anchor (name, figure, what it's read from) and **one** line
///    that changes only when its cause does (`hero`);
/// 2. "What I know about you" — one portrait: the knowledge lines and the
///    analysis's insights and strengths in one list by area, the ones that
///    shape the plan first and saying how (`portrait`, `effects`);
/// 3. "Learning next" (inside "What I know about you") — the few closest to known first (`stillLearning`);
/// 4. the evidence, one level down.
/// Never a score; the heart's note stays in the check-in (its own rule).
public struct TwinPlanEffect: Equatable, Sendable {
    /// The line or insight it belongs to ("body.legs", "recoveryAfterGames").
    public var id: String
    /// What it changes: "Hard leg days get 4 days to recover — your legs are ready again Friday."
    public var text: String
    /// True while it changes a day this week (it can lead the page).
    public var now: Bool
    /// A few words for a tile ("Legs ready Sunday"), only while `now`.
    public var short: String? = nil

    public init(id: String, text: String, now: Bool, short: String? = nil) {
        self.id = id
        self.text = text
        self.now = now
        self.short = short
    }
}

public enum TwinPageEntry: Identifiable, Equatable, Sendable {
    case line(KnowledgeLine)
    /// Something holding the athlete back (has a briefing).
    case insight(TwinInsight)
    /// Something that works.
    case strength(TwinInsight)

    public var id: String {
        switch self {
        case .line(let line): "line." + line.id
        case .insight(let insight), .strength(let insight): "insight." + insight.id
        }
    }

    /// The key `effects` uses.
    public var effectKey: String {
        switch self {
        case .line(let line): line.id
        case .insight(let insight), .strength(let insight): insight.kind.rawValue
        }
    }

    var isSafety: Bool { if case .line(let line) = self { return line.safety } else { return false } }
}

public struct TwinPageArea: Equatable, Sendable {
    public var area: KnowledgeLine.Area
    public var entries: [TwinPageEntry]
}

public struct TwinHero: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case safety, plan, learned, insight, read }
    public var kind: Kind
    /// The small word above the sentence: what kind of thing this is.
    public var eyebrow: String
    public var text: String
    /// The entry it comes from, when there is one (to open its briefing).
    public var insight: TwinInsight?
    /// The knowledge line it repeats word for word: left out of the
    /// portrait below, so it's said once (research: no second copy).
    public var lineID: String? = nil
}

public enum TwinPage {
    /// Which part of the athlete an insight is about.
    public static func area(of kind: TwinInsightKind) -> KnowledgeLine.Area {
        switch kind {
        case .sleepBeforeGames, .gameDayFuel: .games
        case .recoveryAfterGames: .body
        case .sleepBase, .irregularSleep: .habits
        case .sleepAffectsPractice, .strengthNotSpeed, .strengthRising, .consistentTraining, .loadSpike: .training
        case .mistakeReplay, .pressureConfidence, .stressAndSleep: .mind
        }
    }

    /// One analyst: where the stricter knowledge engine already says a thing,
    /// the older analysis doesn't say it again (in other words).
    static let sameSubject: [TwinInsightKind: String] = [
        .sleepBase: "habits.sleep",
        .consistentTraining: "training.rhythm",
        .sleepAffectsPractice: "training.sleep"
    ]

    /// The portrait by area: pain that came back first, then what shapes
    /// the plan, then what holds the athlete back, then the rest, then what
    /// works. Areas with nothing in them are left out.
    /// - known: every line the twin knows, hidden ones too — a line the
    ///   athlete said wasn't right must not come back in other words.
    public static func portrait(lines: [KnowledgeLine], known: Set<String> = [], insights: [TwinInsight], strengths: [TwinInsight],
                                effects: [TwinPlanEffect]) -> [TwinPageArea] {
        let lineIDs = Set(lines.map(\.id)).union(known)
        let inPlan = Set(effects.map(\.id))
        let keep = { (insight: TwinInsight) in sameSubject[insight.kind].map { !lineIDs.contains($0) } ?? true }
        var areas: [TwinPageArea] = []
        for area in KnowledgeLine.Area.allCases {
            var entries: [(rank: Int, order: Int, entry: TwinPageEntry)] = []
            for (index, line) in lines.enumerated() where line.area == area {
                let entry = TwinPageEntry.line(line)
                entries.append((line.safety ? 0 : inPlan.contains(line.id) ? 1 : 3, index, entry))
            }
            for (index, insight) in insights.enumerated() where self.area(of: insight.kind) == area && keep(insight) {
                entries.append((inPlan.contains(insight.kind.rawValue) ? 1 : 2, 100 + index, .insight(insight)))
            }
            for (index, strength) in strengths.enumerated() where self.area(of: strength.kind) == area && keep(strength) {
                entries.append((4, 200 + index, .strength(strength)))
            }
            guard !entries.isEmpty else { continue }
            entries.sort { ($0.rank, $0.order) < ($1.rank, $1.order) }
            areas.append(TwinPageArea(area: area, entries: entries.map(\.entry)))
        }
        // An area holding pain that came back leads the page's portrait.
        let safety = areas.filter { $0.entries.contains(where: \.isSafety) }
        return safety + areas.filter { !$0.entries.contains(where: \.isSafety) }
    }

    /// What the twin changes in the plan, said where the fact is. Only what
    /// the planner really does (GymHistoryBuilder, TwinSteer → SessionPlanner).
    /// - legRecoveryDays: the athlete's own, when longer than usual (nil otherwise or hidden).
    /// - legsReadyIn: days until legs are ready for hard work again, only
    ///   while it is the twin's extra time holding them (the usual 3 days
    ///   alone would already say ready); nil otherwise.
    public static func effects(legRecoveryDays: Int?, legsReadyIn: Int?, steers: Set<TwinSteer>, games: [Date],
                               event: String, now: Date, calendar: Calendar = .current) -> [TwinPlanEffect] {
        var effects: [TwinPlanEffect] = []
        let today = calendar.startOfDay(for: now)
        if steers.contains(.loadSpike) {
            effects.append(TwinPlanEffect(id: TwinInsightKind.loadSpike.rawValue,
                                          text: "This week was bigger than your usual, so sessions are a little shorter and skip hard conditioning until it settles.",
                                          now: true, short: "Lighter after a big week"))
        }
        if steers.contains(.slowGameRecovery) {
            // The light day a game brings (two days after it, as the planner
            // does), still ahead or today, from a game within the next week.
            let soon = calendar.date(byAdding: .day, value: 7, to: today) ?? today
            let lightDay = { (game: Date) in calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: game)) ?? game }
            // Another game within two days of the light day: the planner may keep
            // it as the week's heavy-leg slot (TrainingDay.twinHoldsLegsAfterGame),
            // so the twin doesn't promise a light day there.
            let crowded = { (game: Date) in
                games.contains { other in
                    let gap = calendar.dateComponents([.day], from: lightDay(game), to: calendar.startOfDay(for: other)).day ?? 99
                    return gap >= 0 && gap <= 2
                }
            }
            if let game = games.filter({ lightDay($0) >= today && $0 < soon && !crowded($0) }).min() {
                let light = lightDay(game)
                let when = light == today ? "today" : calendar.isDate(light, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: today) ?? today)
                    ? "tomorrow" : weekday(light, calendar: calendar)
                effects.append(TwinPlanEffect(id: TwinInsightKind.recoveryAfterGames.rawValue,
                                              text: "You still feel a \(event) two days later, so after \(weekday(game, calendar: calendar))'s \(event), \(when) stays light on the legs too.",
                                              now: true, short: "\(when.prefix(1).uppercased() + when.dropFirst()) light on the legs"))
            } else {
                effects.append(TwinPlanEffect(id: TwinInsightKind.recoveryAfterGames.rawValue,
                                              text: "You still feel a \(event) two days later, so that day stays light on the legs too.",
                                              now: false))
            }
        }
        if let days = legRecoveryDays {
            if let left = legsReadyIn, left > 0, let ready = calendar.date(byAdding: .day, value: left, to: today) {
                let when = left == 1 ? "tomorrow" : weekday(ready, calendar: calendar)
                effects.append(TwinPlanEffect(id: "body.legs",
                                              text: "Your hard leg days get \(days) days to recover, so your legs are ready for hard work again \(when).",
                                              now: true, short: "Legs ready \(when)"))
            } else {
                effects.append(TwinPlanEffect(id: "body.legs", text: "Your hard leg days get \(days) days to recover, not the usual 3.", now: false))
            }
        }
        if steers.contains(.strengthNotSpeed) {
            effects.append(TwinPlanEffect(id: TwinInsightKind.strengthNotSpeed.rawValue,
                                          text: "Power and acceleration come first in your workouts.", now: false))
        }
        return effects
    }

    /// The one line that leads the page. Fixed priority, and each kind only
    /// while its cause lasts, so it doesn't flip every morning:
    /// pain that came back → a plan change happening this week → something
    /// learned this week → what matters most → the coach's read.
    public static func hero(lines: [KnowledgeLine], firstSeen: [String: Date], effects: [TwinPlanEffect],
                            insights: [TwinInsight], coachRead: String, now: Date, calendar: Calendar = .current) -> TwinHero {
        if let pain = lines.first(where: \.safety) {
            return TwinHero(kind: .safety, eyebrow: "Worth getting checked", text: pain.text, insight: nil, lineID: pain.id)
        }
        if let effect = effects.first(where: \.now) {
            return TwinHero(kind: .plan, eyebrow: "In your plan", text: effect.text, insight: nil)
        }
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        // The heart never leads the page: its note lives in the check-in.
        if let learned = lines.filter({ $0.id != "body.heart" && (firstSeen[$0.id] ?? .distantPast) > weekAgo })
            .max(by: { (firstSeen[$0.id] ?? .distantPast) < (firstSeen[$1.id] ?? .distantPast) }) {
            return TwinHero(kind: .learned, eyebrow: "New about you", text: learned.text, insight: nil, lineID: learned.id)
        }
        if let top = insights.first {
            return TwinHero(kind: .insight, eyebrow: "What matters most", text: top.headline, insight: top)
        }
        return TwinHero(kind: .read, eyebrow: "Your coach's read", text: coachRead, insight: nil)
    }

    /// The few things closest to known, first (goal gradient): a real count,
    /// never a head start. A pattern being checked is closest of all.
    public static func stillLearning(_ items: [LearningItem], limit: Int = 3) -> [LearningItem] {
        let ranked = items.enumerated().sorted { a, b in
            let ra = a.element.checking ? 2 : Double(min(a.element.have, a.element.need)) / Double(max(a.element.need, 1))
            let rb = b.element.checking ? 2 : Double(min(b.element.have, b.element.need)) / Double(max(b.element.need, 1))
            return ra == rb ? a.offset < b.offset : ra > rb
        }
        return Array(ranked.prefix(limit).map(\.element))
    }

    /// Fixed English day names (Foundation's names differ on Linux).
    static func weekday(_ date: Date, calendar: Calendar) -> String {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][(calendar.component(.weekday, from: date) - 1) % 7]
    }
}

/// "Your twin learned …" after an input (owner, 2026-11-27: "every button
/// almost you tap everything turns into the twin"): what this one input
/// added — a line known just now, else the progress of what it feeds. Never
/// a score; nothing when the input changed nothing the twin tracks.
public enum TwinLearned {
    /// What each input teaches (the knowledge engine's line and item ids).
    /// Only inputs that really move something the same day: a rated practice
    /// or game (the evening), and leg recovery needs the check-ins after.
    public enum Input: Sendable {
        case checkIn, gameRating, evening

        var feeds: [String] {
            switch self {
            case .checkIn: ["habits.sleep", "training.sleep", "body.legs"]
            case .gameRating: ["games.best"]
            case .evening: ["training.practice", "training.sleep", "games.best"]
            }
        }
    }

    public static let newPrefix = "Your twin learned something new: "

    public static func line(before: TwinKnowledge, after: TwinKnowledge, input: Input) -> String? {
        let known = Set(before.lines.map(\.id))
        // A new line from what this input feeds (pain has its own path and words).
        if let new = after.lines.first(where: { line in
            !known.contains(line.id) && !line.safety && input.feeds.contains { line.id == $0 || line.id.hasPrefix($0 + ".") }
        }) {
            return newPrefix + new.text
        }
        for id in input.feeds {
            guard let now = after.learning.first(where: { $0.id == id }) else { continue }
            let was = before.learning.first { $0.id == id }
            let moved = was.map { now.have > $0.have || (now.checking && !$0.checking) } ?? true
            guard moved else { continue }
            return "Your twin is learning \(lowercasedFirst(now.question)): \(lowercasedFirst(now.progress))."
        }
        return nil
    }

    static func lowercasedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }
}
