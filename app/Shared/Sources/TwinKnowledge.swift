import Foundation

/// "What I know about you" (owner, 2026-11-27: the twin should be a great
/// feature with "more information and knowledge about him inside of it").
/// A portrait of the athlete from their own data, in short sentences grouped
/// by area, plus what the twin is still learning. Rules: `docs/TWIN-RESEARCH.md`
/// (T1–T15). In short:
/// - Nothing is said before its minimum data (T1); until then a line says
///   what's missing ("4 of 10 rated games"), never a direction.
/// - The athlete is compared only with their own usual (T2), on a short,
///   fixed list of factors (T4), with counts instead of statistics (T5).
/// - A pattern must hold now *and* before the last few cases (T6); otherwise
///   it is still "checking", with no direction given.
/// - "Goes with", never "causes" (T7). Pain that comes back is always "show
///   it to an athletic trainer, physio or doctor" (T9). Never a score.
/// Foundation only (harness); `TwinInputBuilder` gathers the data.
public struct KnowledgeInput: Sendable {
    public struct RatedGame: Sendable {
        public var date: Date
        /// The athlete's own 1 (poorly) … 5 (great), never the result (research §1).
        public var rating: Int
        public init(date: Date, rating: Int) { self.date = date; self.rating = rating }
    }

    public struct Pain: Sendable {
        public var date: Date
        public var areas: [String]
        public init(date: Date, areas: [String]) { self.date = date; self.areas = areas }
    }

    /// How hard one body region worked in a session (CR-10, from the workout check).
    public struct RegionEffort: Sendable {
        public var date: Date
        public var region: String
        public var effort: Int
        public init(date: Date, region: String, effort: Int) { self.date = date; self.region = region; self.effort = effort }
    }

    public var base: TwinInput
    public var ratedGames: [RatedGame]
    public var pains: [Pain]
    public var efforts: [RegionEffort]
    /// Days the athlete said were exams, travel or sick: left out of the
    /// sleep comparisons (they shorten sleep and lower practice alike).
    public var excludedDays: Set<Date>

    public init(base: TwinInput, ratedGames: [RatedGame] = [], pains: [Pain] = [], efforts: [RegionEffort] = [], excludedDays: Set<Date> = []) {
        self.base = base
        self.ratedGames = ratedGames
        self.pains = pains
        self.efforts = efforts
        self.excludedDays = excludedDays
    }
}

public struct KnowledgeLine: Identifiable, Equatable, Sendable, Codable {
    public enum Area: String, CaseIterable, Sendable, Codable {
        case body, training, games, mind, habits

        public var title: String {
            switch self {
            case .body: "Your body"
            case .training: "Your training"
            case .games: "Your games"
            case .mind: "Your mind"
            case .habits: "Your habits"
            }
        }
    }

    /// Stable, so a correction ("That's not right") sticks to the same line.
    public var id: String
    public var area: Area
    /// The sentence: "You usually sleep about 7 h 40 min."
    public var text: String
    /// Where it comes from, in counts: "median of 26 nights".
    public var basis: String
    /// Show it to someone (pain that came back).
    public var safety: Bool = false

    public init(id: String, area: Area, text: String, basis: String, safety: Bool = false) {
        self.id = id
        self.area = area
        self.text = text
        self.basis = basis
        self.safety = safety
    }
}

/// Something the twin can't say yet, and what it needs (T1).
public struct LearningItem: Identifiable, Equatable, Sendable, Codable {
    public var id: String
    public var area: KnowledgeLine.Area
    /// "What your best games have in common"
    public var question: String
    public var have: Int
    public var need: Int
    /// "rated games"
    public var unit: String
    /// A pattern seen once, waiting for the next cases to agree (T6).
    public var checking: Bool = false

    public var progress: String {
        checking ? "Checking it against your next \(need - have) \(unit)" : "\(min(have, need)) of \(need) \(unit) so far"
    }
}

public struct TwinKnowledge: Equatable, Sendable {
    public var lines: [KnowledgeLine]
    public var learning: [LearningItem]
    /// Days the athlete's legs usually need after their hardest sessions,
    /// when that is longer than the planner assumes (T10: only ever longer).
    public var legRecoveryDays: Int?

    public func lines(in area: KnowledgeLine.Area) -> [KnowledgeLine] { lines.filter { $0.area == area } }
}

public enum TwinKnowledgeEngine {
    /// The planner assumes legs are ready again on day 3 (72 h, GymAdvisor).
    public static let defaultLegRecoveryDays = 3

    public static func build(_ input: KnowledgeInput, calendar: Calendar = .current) -> TwinKnowledge {
        var lines: [KnowledgeLine] = []
        var learning: [LearningItem] = []
        func add(_ result: Result) {
            switch result {
            case .line(let line): lines.append(line)
            case .learning(let item): learning.append(item)
            case .lines(let many): lines.append(contentsOf: many)
            case .none: break
            }
        }
        add(usualSleep(input, calendar: calendar))
        add(trainingRhythm(input, calendar: calendar))
        add(bestGames(input, calendar: calendar))
        let recovery = legRecovery(input, calendar: calendar)
        add(recovery.result)
        add(painReturns(input, calendar: calendar))
        add(sleepAndPractice(input, calendar: calendar))
        return TwinKnowledge(lines: lines, learning: learning,
                             legRecoveryDays: recovery.days.flatMap { $0 > defaultLegRecoveryDays ? $0 : nil })
    }

    enum Result {
        case line(KnowledgeLine)
        case lines([KnowledgeLine])
        case learning(LearningItem)
        case none
    }

    // MARK: - Helpers

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    static func mean(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }

    /// "7 h 40 min", "8 h".
    static func hours(_ value: Double) -> String {
        let minutes = Int((value * 60).rounded())
        let rounded = (minutes + 2) / 5 * 5
        return rounded % 60 == 0 ? "\(rounded / 60) h" : "\(rounded / 60) h \(rounded % 60) min"
    }

    static func dayKey(_ date: Date, _ calendar: Calendar) -> Date { calendar.startOfDay(for: date) }

    static func short(_ date: Date, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    /// Sleep by the morning it was reported on.
    static func sleepByDay(_ input: KnowledgeInput, _ calendar: Calendar) -> [Date: Double] {
        var byDay: [Date: Double] = [:]
        for morning in input.base.mornings {
            if let sleep = morning.sleepHours, sleep > 0 { byDay[dayKey(morning.date, calendar)] = sleep }
        }
        return byDay
    }

    // MARK: - Habits

    /// "You usually sleep about 7 h 40 min" — the median of the last 28 nights (T2).
    static func usualSleep(_ input: KnowledgeInput, calendar: Calendar) -> Result {
        let since = calendar.date(byAdding: .day, value: -28, to: input.base.now) ?? input.base.now
        let nights = input.base.mornings.filter { $0.date >= since }.compactMap { $0.sleepHours }.filter { $0 > 0 }
        let need = 7
        guard nights.count >= need, let usual = median(nights) else {
            return .learning(LearningItem(id: "habits.sleep", area: .habits, question: "How much you usually sleep",
                                          have: nights.count, need: need, unit: "nights"))
        }
        return .line(KnowledgeLine(id: "habits.sleep", area: .habits, text: "You usually sleep about \(hours(usual)).",
                                   basis: "Middle value of your last \(nights.count) nights"))
    }

    /// "You train about 3 times a week, plus 2 team practices" — last 4 weeks.
    static func trainingRhythm(_ input: KnowledgeInput, calendar: Calendar) -> Result {
        let now = input.base.now
        guard let since = calendar.date(byAdding: .day, value: -28, to: now) else { return .none }
        let first = (input.base.sessions + input.base.practices.map(\.date)).min()
        let daysKnown = first.map { calendar.dateComponents([.day], from: $0, to: now).day ?? 0 } ?? 0
        guard daysKnown >= 14 else {
            return .learning(LearningItem(id: "training.rhythm", area: .training, question: "Your usual training week",
                                          have: max(0, daysKnown), need: 14, unit: "days"))
        }
        let weeks = Double(min(daysKnown, 28)) / 7
        let sessionDays = Set(input.base.sessions.filter { $0 >= since }.map { dayKey($0, calendar) }).count
        let practiceDays = Set(input.base.practices.filter { $0.date >= since }.map { dayKey($0.date, calendar) }).count
        let perWeek = Int((Double(sessionDays) / weeks).rounded())
        let practices = Int((Double(practiceDays) / weeks).rounded())
        var text = perWeek == 0 ? "No workouts logged in the last few weeks" : "You train about \(perWeek) \(perWeek == 1 ? "time" : "times") a week"
        if practices > 0 { text += ", plus \(practices) team \(practices == 1 ? "practice" : "practices")" }
        return .line(KnowledgeLine(id: "training.rhythm", area: .training, text: text + ".",
                                   basis: "\(sessionDays) workout days and \(practiceDays) logged practices in the last \(Int(weeks.rounded())) weeks"))
    }

    // MARK: - Games (research §1)

    struct GameFacts {
        var rating: Int
        var sleep: Double?
        var energy: Double?
        var soreness: Double?
        var stress: Double?
        var hardestPractice: Double?
        var heavyLegs: Bool
    }

    static func gameFacts(_ input: KnowledgeInput, calendar: Calendar) -> [GameFacts] {
        let sleep = sleepByDay(input, calendar)
        var morningByDay: [Date: TwinInput.Morning] = [:]
        for morning in input.base.mornings { morningByDay[dayKey(morning.date, calendar)] = morning }
        return input.ratedGames.sorted { $0.date < $1.date }.map { game in
            let day = dayKey(game.date, calendar)
            let before = calendar.date(byAdding: .day, value: -1, to: day) ?? day
            let twoNights = [sleep[day], sleep[before]].compactMap { $0 }
            let morning = morningByDay[day]
            let windowStart = calendar.date(byAdding: .day, value: -2, to: day) ?? day
            let practice = input.base.practices.filter { $0.date >= windowStart && $0.date < day }.map { Double($0.hard) }.max()
            let legs = input.efforts.contains { $0.region == "legs" && $0.effort >= 7 && $0.date >= windowStart && $0.date < game.date }
            return GameFacts(rating: game.rating, sleep: twoNights.count == 2 ? mean(twoNights) : nil,
                             energy: morning.map { Double($0.energy) }, soreness: morning.map { Double($0.soreness) },
                             stress: morning.flatMap { $0.stress > 0 ? Double($0.stress) : nil },
                             hardestPractice: practice, heavyLegs: legs)
        }
    }

    struct Factor {
        let id: String
        let value: (GameFacts) -> Double?
        /// Smallest difference worth saying (sleep 30 min, scales 1 point).
        let minimum: Double
        /// The one direction looked for, declared in advance (T4): best games
        /// above (true) or below (false) the athlete's median. The other
        /// direction is never tested — and some (less sleep, harder practice,
        /// heavy legs before good games) would invite the wrong habit anyway.
        let bestHigher: Bool
        let say: (_ best: Double, _ others: Double, _ count: Int) -> String
    }

    /// Five factors, one direction each (T4; research §1).
    static let gameFactors: [Factor] = [
        Factor(id: "sleep", value: { $0.sleep }, minimum: 0.5, bestHigher: true) { best, others, count in
            "Your \(count) best-rated games so far all came after two nights of \(hours(best)) or more sleep. Your other games averaged \(hours(others))."
        },
        Factor(id: "soreness", value: { $0.soreness }, minimum: 1, bestHigher: true) { _, _, count in
            "Your \(count) best-rated games came on mornings you felt more sore than on your other game days — some soreness doesn't decide your game."
        },
        Factor(id: "stress", value: { $0.stress }, minimum: 1, bestHigher: true) { _, _, count in
            "Your \(count) best-rated games came on more nervous mornings than your other game days — nerves can go with playing well."
        },
        Factor(id: "practice", value: { $0.hardestPractice }, minimum: 1, bestHigher: false) { _, _, count in
            "Your \(count) best-rated games all came after easier practices in the two days before."
        },
        Factor(id: "legs", value: { $0.heavyLegs ? 1 : 0 }, minimum: 0.5, bestHigher: false) { _, _, count in
            "None of your \(count) best-rated games came within two days of a hard leg session."
        }
    ]

    /// Who counts as "best": the top third by the athlete's own rating, never
    /// more than half the games; nil when ratings are too alike to tell.
    static func bestIndices(_ games: [GameFacts]) -> Set<Int>? {
        let ranked = games.indices.sorted { games[$0].rating > games[$1].rating }
        let target = max(3, games.count / 3)
        guard ranked.count >= target + 3 else { return nil }
        let cut = games[ranked[target - 1]].rating
        let withTies = ranked.filter { games[$0].rating >= cut }
        let strict = ranked.filter { games[$0].rating > cut }
        let chosen = withTies.count <= games.count / 2 ? withTies : strict
        return chosen.count >= 3 ? Set(chosen) : nil
    }

    /// The factors where every best game sits on its declared side of the
    /// athlete's own median, far enough from the others to matter.
    static func patterns(_ games: [GameFacts], best chosen: Set<Int>) -> [(factor: Factor, best: Double, others: Double, count: Int)] {
        let best = chosen.sorted().map { games[$0] }
        let others = games.indices.filter { !chosen.contains($0) }.map { games[$0] }
        var found: [(Factor, Double, Double, Int)] = []
        for factor in gameFactors {
            let all = games.compactMap(factor.value)
            let bestValues = best.compactMap(factor.value)
            let otherValues = others.compactMap(factor.value)
            guard bestValues.count == best.count, otherValues.count >= 3, let mid = median(all) else { continue }
            let bestMean = mean(bestValues), otherMean = mean(otherValues)
            let gap = factor.bestHigher ? bestMean - otherMean : otherMean - bestMean
            guard gap >= factor.minimum else { continue }
            let side = factor.bestHigher ? bestValues.allSatisfy({ $0 > mid }) : bestValues.allSatisfy({ $0 < mid })
            if side { found.append((factor, factor.bestHigher ? (bestValues.min() ?? bestMean) : (bestValues.max() ?? bestMean), otherMean, best.count)) }
        }
        return found
    }

    static let minimumRatedGames = 10
    /// A pattern must also have held before the last this-many games (T6).
    static let replicationGames = 3

    static func bestGames(_ input: KnowledgeInput, calendar: Calendar) -> Result {
        let games = gameFacts(input, calendar: calendar)
        let question = "What your best games have in common"
        guard games.count >= minimumRatedGames else {
            return .learning(LearningItem(id: "games.best", area: .games, question: question,
                                          have: games.count, need: minimumRatedGames, unit: "rated games"))
        }
        guard let best = bestIndices(games) else {
            // Every game rated about the same: nothing can stand out.
            return .learning(LearningItem(id: "games.best", area: .games, question: question + " (your ratings are very alike so far)",
                                          have: games.count, need: games.count + replicationGames, unit: "rated games", checking: true))
        }
        let now = patterns(games, best: best)
        let earlierGames = Array(games.dropLast(replicationGames))
        let earlier = earlierGames.count >= minimumRatedGames ? bestIndices(earlierGames).map { patterns(earlierGames, best: $0) } ?? [] : []
        // New evidence, not the same games again (T6): one of the newest
        // games must itself be a best game that agrees.
        let newestBest = best.contains { $0 >= games.count - replicationGames }
        let held = newestBest ? now.filter { pattern in earlier.contains { $0.factor.id == pattern.factor.id } } : []
        if held.isEmpty {
            // Something showed up once, or nothing yet: no direction either way.
            return .learning(LearningItem(id: "games.best", area: .games, question: question,
                                          have: games.count, need: games.count + replicationGames,
                                          unit: "rated games", checking: true))
        }
        return .lines(held.prefix(2).map { pattern in
            KnowledgeLine(id: "games.best.\(pattern.factor.id)", area: .games,
                          text: pattern.factor.say(pattern.best, pattern.others, pattern.count),
                          basis: "Your \(games.count) rated games; it held again in your newest ones. It goes with playing well — it doesn't decide it.")
        })
    }

    // MARK: - Body (research §2, §4)

    /// Days until the athlete's soreness is back to their usual after a hard
    /// leg session (effort ≥ 7). Needs 4 such sessions with answers after.
    static func legRecovery(_ input: KnowledgeInput, calendar: Calendar) -> (result: Result, days: Int?) {
        var soreness: [Date: Int] = [:]
        for morning in input.base.mornings { soreness[dayKey(morning.date, calendar)] = morning.soreness }
        guard let usual = median(input.base.mornings.sorted { $0.date < $1.date }.suffix(28).map { Double($0.soreness) }) else {
            return (.learning(LearningItem(id: "body.legs", area: .body, question: "How long your legs take to recover",
                                           have: 0, need: 4, unit: "hard leg sessions")), nil)
        }
        let hard = input.efforts.filter { $0.region == "legs" && $0.effort >= 7 }.sorted { $0.date < $1.date }
        var episodes: [Int] = []
        var lastDay: Date?
        let hardDays = Set(hard.map { dayKey($0.date, calendar) })
        let gameDays = Set(input.base.games.map { dayKey($0, calendar) })
        for effort in hard {
            let day = dayKey(effort.date, calendar)
            if let lastDay, day == lastDay { continue }
            lastDay = day
            let window = (1...4).compactMap { calendar.date(byAdding: .day, value: $0, to: day) }
            // Another hard leg session or a game in the window: that soreness
            // isn't this session's, so the episode says nothing.
            guard window.count == 4, !window.contains(where: { hardDays.contains($0) || gameDays.contains($0) }) else { continue }
            let after = window.map { soreness[$0] }
            guard after.prefix(3).compactMap({ $0 }).count >= 2 else { continue }
            // The first answered day soreness is back at or below usual. Still
            // above on day 4 = "5 or later"; never answered as back = unknown.
            if let back = after.enumerated().first(where: { $0.element.map { Double($0) <= usual } ?? false }) {
                episodes.append(back.offset + 1)
            } else if let fourth = after[3], Double(fourth) > usual {
                episodes.append(5)
            }
        }
        guard episodes.count >= 4, let personal = median(episodes.map(Double.init)) else {
            return (.learning(LearningItem(id: "body.legs", area: .body, question: "How long your legs take to recover",
                                           have: episodes.count, need: 4, unit: "hard leg sessions with check-ins after")), nil)
        }
        let days = Int(personal.rounded(.up))
        let recent = episodes.suffix(4)
        // A direction only when at least 3 of the last 4 point the same way.
        let longer = days > defaultLegRecoveryDays && recent.filter { $0 >= defaultLegRecoveryDays + 1 }.count >= 3
        let shorter = days < defaultLegRecoveryDays && recent.filter { $0 <= defaultLegRecoveryDays - 1 }.count >= 3
        let agree = episodes.filter { longer ? $0 >= days : $0 <= days }.count
        guard longer || shorter else {
            return (.line(KnowledgeLine(id: "body.legs", area: .body,
                                        text: "After your hardest leg days your legs usually feel normal again by day \(defaultLegRecoveryDays) — what your plan expects.",
                                        basis: "\(episodes.count) hard leg sessions with check-ins after")), defaultLegRecoveryDays)
        }
        let text = longer
            ? "After your hardest leg days your legs usually feel normal again on day \(min(days, 5))\(days >= 5 ? " or later" : ""), not day \(defaultLegRecoveryDays) (\(agree) of \(episodes.count) times). Your plan gives them that extra day."
            : "After your hardest leg days your legs usually feel normal again by day \(days) (\(agree) of \(episodes.count) times). Your plan still keeps \(defaultLegRecoveryDays) days between heavy leg sessions."
        return (.line(KnowledgeLine(id: "body.legs", area: .body, text: text,
                                    basis: "\(episodes.count) hard leg sessions and your soreness answers on the days after")), longer ? days : nil)
    }

    /// Pain in the same area on two separate occasions within 8 weeks (T9).
    static func painReturns(_ input: KnowledgeInput, calendar: Calendar) -> Result {
        guard let since = calendar.date(byAdding: .day, value: -56, to: input.base.now) else { return .none }
        var lines: [KnowledgeLine] = []
        let areas = Set(input.pains.flatMap(\.areas)).sorted()
        for area in areas {
            let days = input.pains.filter { $0.date >= since && $0.areas.contains(area) }.map { dayKey($0.date, calendar) }.sorted()
            // Separate occasions: at least 3 pain-free days between them.
            var occasions: [(start: Date, end: Date)] = []
            for day in days {
                if let current = occasions.last, let gap = calendar.dateComponents([.day], from: current.end, to: day).day, gap <= 3 {
                    occasions[occasions.count - 1].end = day
                } else {
                    occasions.append((day, day))
                }
            }
            let subject = painSubject(area)
            if occasions.count >= 2 {
                let dates = occasions.suffix(3).map { short($0.start, calendar) }
                let joined = dates.count == 2 ? "\(dates[0]) and \(dates[1])" : "\(dates[0]), \(dates[1]) and \(dates[2])"
                lines.append(KnowledgeLine(id: "body.pain.\(area)", area: .body,
                                           text: "\(subject) hurt again: \(joined). Pain that comes back is worth showing to an athletic trainer, physio or doctor.",
                                           basis: "Your check-ins in the last 8 weeks", safety: true))
            } else if let only = occasions.first, let span = calendar.dateComponents([.day], from: only.start, to: only.end).day, span >= 10 {
                // Pain that never really stopped is the same message, sooner.
                lines.append(KnowledgeLine(id: "body.pain.\(area)", area: .body,
                                           text: "\(subject) has hurt on and off since \(short(only.start, calendar)). Pain that lasts is worth showing to an athletic trainer, physio or doctor.",
                                           basis: "Your check-ins in the last 8 weeks", safety: true))
            }
        }
        return lines.isEmpty ? .none : .lines(lines)
    }

    /// "Your knee", "Your thigh or calf".
    static func painSubject(_ area: String) -> String {
        switch area {
        case "leg": "Your thigh or calf"
        case "arm": "Your arm or wrist"
        case "core": "Your stomach or side"
        case "hip": "Your hip or groin"
        case "ankle": "Your ankle or foot"
        case "other": "The spot you marked \"somewhere else\""
        default: "Your \(area)"
        }
    }

    // MARK: - Training (research §6)

    static func sleepAndPractice(_ input: KnowledgeInput, calendar: Calendar) -> Result {
        let sleep = sleepByDay(input, calendar)
        let excluded = Set(input.excludedDays.map { dayKey($0, calendar) })
        let pairs = input.base.practices.compactMap { practice -> (date: Date, sleep: Double, went: Double)? in
            let day = dayKey(practice.date, calendar)
            guard practice.went > 0, !excluded.contains(day), let slept = sleep[day] else { return nil }
            return (day, slept, Double(practice.went))
        }.sorted { $0.date < $1.date }
        guard let usual = median(pairs.map(\.sleep)) else {
            return .learning(LearningItem(id: "training.sleep", area: .training, question: "Whether short nights change your practices",
                                          have: 0, need: 20, unit: "practices with sleep logged"))
        }
        let isShort = { (value: Double) in value <= usual - 1 }
        let shortCount = pairs.filter { isShort($0.sleep) }.count
        guard pairs.count >= 20, shortCount >= 5 else {
            let have = pairs.count >= 20 ? shortCount : pairs.count
            return .learning(LearningItem(id: "training.sleep", area: .training, question: "Whether short nights change your practices",
                                          have: have, need: pairs.count >= 20 ? 5 : 20,
                                          unit: pairs.count >= 20 ? "short nights before a practice" : "practices with sleep logged"))
        }
        func gap(_ set: ArraySlice<(date: Date, sleep: Double, went: Double)>) -> Double? {
            let short = set.filter { isShort($0.sleep) }.map(\.went)
            let rest = set.filter { !isShort($0.sleep) }.map(\.went)
            guard !short.isEmpty, !rest.isEmpty else { return nil }
            return mean(short) - mean(rest)
        }
        // Replication (research §6): the same direction in each of the last
        // two 4-week halves, not just overall.
        let now = input.base.now
        let fourWeeksAgo = calendar.date(byAdding: .day, value: -28, to: now) ?? now
        let eightWeeksAgo = calendar.date(byAdding: .day, value: -56, to: now) ?? now
        let older = pairs.filter { $0.date >= eightWeeksAgo && $0.date < fourWeeksAgo }
        let newer = pairs.filter { $0.date >= fourWeeksAgo }
        let all = gap(pairs[...])
        let first = gap(older[...]), second = gap(newer[...])
        let usualWent = mean(pairs.filter { !isShort($0.sleep) }.map(\.went))
        let lower = pairs.filter { isShort($0.sleep) && $0.went < usualWent }.count
        if let all, let first, let second, all <= -0.5, first < 0, second < 0 {
            let step = all <= -1 ? "about a step" : "a little"
            return .line(KnowledgeLine(id: "training.sleep", area: .training,
                                       text: "On days after short nights you rated practice \(step) lower (\(lower) of \(shortCount) times).",
                                       basis: "\(pairs.count) practices; short = an hour under your usual \(hours(usual)). Exam, travel and sick days left out."))
        }
        // No difference yet is not "short sleep is fine" — it is "keep watching".
        // Different in the two halves, or the other way round: keep watching.
        return .learning(LearningItem(id: "training.sleep", area: .training, question: "Whether short nights change your practices",
                                      have: pairs.count, need: pairs.count + 8, unit: "practices", checking: true))
    }
}
