import Foundation

/// What the athlete's logged sets did to their body: which muscle groups get
/// the most work, how often, and how long since each was trained. Pure and
/// rule-based (no AI), every number traceable to logged sets — the Workout
/// tab's body map, its one-line summary and the group-by-group walkthrough
/// all read this.
///
/// How a set counts:
/// - Every catalogue item lists its muscles with a weight (1 = the main
///   mover, ~0.5 = clearly helps, below 0.5 = only stabilises).
/// - A set gives each muscle weighted ≥ 0.5 that much credit; stabilisers
///   get none (a squat is not a core workout).
/// - A group gets the strongest credit of its muscles in that set, so a set
///   that hits two quad muscles still counts as one quad set, not two.
/// - "Sets a week" and "times a week" cover the last four weeks (or since the
///   first logged set, if that is more recent).
/// - The body map's brightness is recency-weighted load: each credit halves
///   every 14 days, so a muscle left alone fades.
public enum MuscleTraining {
    /// The window for sets and frequency.
    public static let windowDays = 28
    /// The brightness looks back this far, halving every `halfLifeDays`.
    public static let fadeDays = 56
    public static let halfLifeDays = 14.0
    /// Below this a muscle only stabilises and gets no credit.
    public static let minimumWeight = 0.5

    /// One logged set, resolved against the catalogue.
    public struct LoggedSet: Sendable, Equatable {
        public let date: Date
        public let exercise: String
        /// Muscle slug → weight, from the catalogue item.
        public let muscles: [String: Double]

        public init(date: Date, exercise: String, muscles: [String: Double]) {
            self.date = date
            self.exercise = exercise
            self.muscles = muscles
        }
    }

    /// The muscle groups a body region stands for, as the gym planner splits them.
    public static func groups(of region: GymRegion) -> Set<MuscleGroup> {
        switch region {
        case .upper: [.chest, .shoulders, .upperBack, .arms]
        case .lower: [.glutes, .quads, .hamstrings, .calves]
        case .core: [.core]
        }
    }

    /// A workout the athlete described by region ("legs, very hard" — from
    /// Apple Health, with no exercises): sets on every drawable muscle of
    /// that region, each a main mover, so the body map and the group
    /// walkthrough show it. `WorkoutTagging.bodyMapSets` says how many.
    public static func regionSets(date: Date, label: String, bands: [GymRegion: WorkoutTagging.Band]) -> [LoggedSet] {
        bands.sorted { $0.key.rawValue < $1.key.rawValue }.flatMap { region, band -> [LoggedSet] in
            let groups = groups(of: region)
            let slugs = muscles.filter { info in info.drawable && MuscleGroup(region: info.region).map(groups.contains) == true }
                .map(\.id)
            guard !slugs.isEmpty else { return [] }
            let set = LoggedSet(date: date, exercise: label, muscles: Dictionary(uniqueKeysWithValues: slugs.map { ($0, 1.0) }))
            return Array(repeating: set, count: WorkoutTagging.bodyMapSets(band))
        }
    }

    /// An exercise and the weighted sets it gave a group.
    public struct ExerciseShare: Sendable, Equatable {
        public let name: String
        public let sets: Double
    }

    public struct GroupStats: Sendable, Equatable, Identifiable {
        public let group: MuscleGroup
        /// Weighted sets in the window.
        public let sets: Double
        public let setsPerWeek: Double
        /// Days in the window with at least one full set's worth of work.
        public let daysTrained: Int
        public let timesPerWeek: Double
        /// The last day it got real work (any time, not only the window).
        public let lastTrained: Date?
        public let daysSince: Int?
        /// Share of all group work in the window, 0…1.
        public let share: Double
        /// Exercises that trained it most in the window, with their weighted sets.
        public let topExercises: [ExerciseShare]
        /// 1 = most trained group … count.
        public let rank: Int

        public var id: MuscleGroup { group }
    }

    public struct Report: Sendable, Equatable {
        /// Most trained first; every group, trained or not.
        public let groups: [GroupStats]
        /// Drawable muscle slug → brightness 0…1 (1 = the most loaded muscle).
        public let brightness: [String: Double]
        /// Workouts (days with logged sets) and sets in the window.
        public let workouts: Int
        public let totalSets: Int
        public let weeks: Double
        /// Anything ever logged.
        public let hasHistory: Bool
        public let summary: String

        public func stats(_ group: MuscleGroup) -> GroupStats? { groups.first { $0.group == group } }
    }

    // MARK: The analysis

    public static func report(_ sets: [LoggedSet], now: Date, calendar: Calendar = .current) -> Report {
        let today = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: today) ?? today
        let fadeStart = calendar.date(byAdding: .day, value: -(fadeDays - 1), to: today) ?? today
        let past = sets.filter { $0.date <= now }
        let inWindow = past.filter { $0.date >= windowStart }

        // Weeks covered: four, or fewer when the first set is more recent.
        let first = past.map(\.date).min()
        let spanDays: Int = {
            guard let first else { return windowDays }
            let since = (calendar.dateComponents([.day], from: calendar.startOfDay(for: first), to: today).day ?? 0) + 1
            return min(windowDays, max(7, since))
        }()
        let weeks = Double(spanDays) / 7

        // Per group: weighted sets, credit per day, per exercise; last real day ever.
        var groupSets: [MuscleGroup: Double] = [:]
        var groupDays: [MuscleGroup: [Date: Double]] = [:]
        var groupExercises: [MuscleGroup: [String: Double]] = [:]
        var lastTrained: [MuscleGroup: Date] = [:]
        for set in past {
            let day = calendar.startOfDay(for: set.date)
            for (group, credit) in groupCredits(set.muscles) where credit > 0 {
                if lastTrained[group].map({ day > $0 }) ?? true { lastTrained[group] = day }
                guard set.date >= windowStart else { continue }
                groupSets[group, default: 0] += credit
                groupDays[group, default: [:]][day, default: 0] += credit
                groupExercises[group, default: [:]][set.exercise, default: 0] += credit
            }
        }
        let total = groupSets.values.reduce(0, +)

        let unranked = MuscleGroup.allCases.map { group -> (MuscleGroup, Double) in (group, groupSets[group] ?? 0) }
        // Most trained first; ties: the more recently trained, then the body's order.
        let ordered = unranked.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            let la = lastTrained[a.0] ?? .distantPast, lb = lastTrained[b.0] ?? .distantPast
            if la != lb { return la > lb }
            return a.0.order < b.0.order
        }
        let groups = ordered.enumerated().map { index, entry -> GroupStats in
            let (group, sets) = entry
            let days = (groupDays[group] ?? [:]).values.filter { $0 >= 1 }.count
            let last = lastTrained[group]
            let since = last.flatMap { calendar.dateComponents([.day], from: $0, to: today).day }
            let top = (groupExercises[group] ?? [:]).sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .prefix(3).map { ExerciseShare(name: $0.key, sets: $0.value) }
            return GroupStats(group: group, sets: sets, setsPerWeek: sets / weeks, daysTrained: days,
                              timesPerWeek: Double(days) / weeks, lastTrained: last, daysSince: since,
                              share: total > 0 ? sets / total : 0, topExercises: Array(top), rank: index + 1)
        }

        // Brightness: recency-weighted load per drawable muscle.
        var load: [String: Double] = [:]
        for set in past where set.date >= fadeStart {
            let age = Double(calendar.dateComponents([.day], from: calendar.startOfDay(for: set.date), to: today).day ?? 0)
            let fade = pow(0.5, max(0, age) / halfLifeDays)
            for (muscle, credit) in drawableCredits(set.muscles) {
                load[muscle, default: 0] += credit * fade
            }
        }
        let peak = load.values.max() ?? 0
        let brightness = peak > 0 ? load.mapValues { $0 / peak } : [:]

        let workoutDays = Set(inWindow.map { calendar.startOfDay(for: $0.date) }).count
        let partial = Report(groups: groups, brightness: brightness, workouts: workoutDays, totalSets: inWindow.count,
                             weeks: weeks, hasHistory: !past.isEmpty, summary: "")
        return Report(groups: groups, brightness: brightness, workouts: workoutDays, totalSets: inWindow.count,
                      weeks: weeks, hasHistory: !past.isEmpty, summary: summary(partial))
    }

    /// One set's credit per group: the strongest of the group's muscles that
    /// really work (weight ≥ 0.5), capped at one set.
    static func groupCredits(_ muscles: [String: Double]) -> [MuscleGroup: Double] {
        var credits: [MuscleGroup: Double] = [:]
        for (slug, weight) in muscles where weight >= minimumWeight {
            guard let region = musclesBySlug[slug]?.region, let group = MuscleGroup(region: region) else { continue }
            credits[group] = max(credits[group] ?? 0, min(weight, 1))
        }
        return credits
    }

    /// One set's credit per drawable muscle (non-drawable muscles show
    /// through their stand-in, like on the exercise muscle map).
    static func drawableCredits(_ muscles: [String: Double]) -> [String: Double] {
        var credits: [String: Double] = [:]
        for (slug, weight) in muscles where weight >= minimumWeight {
            guard let info = musclesBySlug[slug] else { continue }
            let target = info.drawable ? info.id : (info.renderVia ?? info.id)
            credits[target] = max(credits[target] ?? 0, min(weight, 1))
        }
        return credits
    }

    // MARK: The summary

    /// One or two short sentences: what gets the most work and how often,
    /// what gets the least or has waited longest. Plain rules, no AI.
    static func summary(_ report: Report) -> String {
        guard report.hasHistory else {
            return "No workouts logged yet. Log one and your body map fills in here."
        }
        let trained = report.groups.filter { $0.sets > 0 }
        guard let top = trained.first else {
            let recent = report.groups.filter { $0.daysSince != nil }.min { ($0.daysSince ?? 0) < ($1.daysSince ?? 0) }
            if let recent, let days = recent.daysSince {
                let verb = recent.group.plural ? "were" : "was"
                return "No workouts in the last four weeks. Your \(recent.group.name) \(verb) trained last, \(ago(days))."
            }
            return "No workouts in the last four weeks."
        }

        // Sentence 1: the most trained group (and a close second), and how often.
        var leaders = [top]
        if trained.count > 1, trained[1].sets >= top.sets * 0.75 { leaders.append(trained[1]) }
        let leaderNames = list(leaders.map(\.group.name))
        let first = "Most of your training goes to your \(leaderNames), \(frequency(top.timesPerWeek))."

        // Sentence 2: what's been left out, or what gets the least.
        let untrained = report.groups.filter { $0.sets == 0 }
        let second: String
        if !untrained.isEmpty {
            // Longest waiting first: never trained, then the oldest last day.
            let waiting = untrained.sorted { ($0.daysSince ?? .max) > ($1.daysSince ?? .max) }
            let names = waiting.map(\.group.name)
            let shown = names.count > 2 ? "\(names[0]), \(names[1]) and \(names.count - 2) more" : list(names)
            let plural = names.count > 1 || waiting[0].group.plural
            second = "\(capitalized(shown)) \(plural ? "haven't" : "hasn't") been trained in four weeks."
        } else if let least = report.groups.last, least.group != top.group {
            let when = least.daysSince.map { ", last \(ago($0))" } ?? ""
            second = "\(capitalized(least.group.name)) \(least.group.plural ? "get" : "gets") the least\(when)."
        } else {
            second = ""
        }
        return second.isEmpty ? first : "\(first) \(second)"
    }

    /// "about twice a week"
    public static func frequency(_ perWeek: Double) -> String {
        switch perWeek {
        case ..<0.75: return "less than once a week"
        case ..<1.5: return "about once a week"
        case ..<2.5: return "about twice a week"
        default: return "about \(Int(perWeek.rounded())) times a week"
        }
    }

    /// "today", "yesterday", "12 days ago"
    public static func ago(_ days: Int) -> String {
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        default: return "\(days) days ago"
        }
    }

    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }

    static func capitalized(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }
}

/// The ten groups the athlete sees (the neck is left out: it is never a
/// training target here).
public enum MuscleGroup: String, CaseIterable, Sendable, Identifiable {
    case chest, shoulders, upperBack, lowerBack, arms, core, glutes, quads, hamstrings, calves

    public var id: String { rawValue }

    public init?(region: MuscleRegion) {
        switch region {
        case .chest: self = .chest
        case .shoulder: self = .shoulders
        case .upperBack: self = .upperBack
        case .lowerBack: self = .lowerBack
        case .arm, .forearm: self = .arms
        case .trunk: self = .core
        case .hip: self = .glutes
        case .quadriceps: self = .quads
        case .hamstrings: self = .hamstrings
        case .calf, .foot: self = .calves
        case .neck: return nil
        }
    }

    public var regions: [MuscleRegion] {
        MuscleRegion.allCases.filter { MuscleGroup(region: $0) == self }
    }

    /// Lower case, for inside a sentence: "your quads".
    public var name: String {
        switch self {
        case .chest: "chest"
        case .shoulders: "shoulders"
        case .upperBack: "upper back"
        case .lowerBack: "lower back"
        case .arms: "arms"
        case .core: "core"
        case .glutes: "glutes"
        case .quads: "quads"
        case .hamstrings: "hamstrings"
        case .calves: "calves"
        }
    }

    /// "Glutes and hips" (the hip region also holds the hip flexors and adductors).
    public var title: String { self == .glutes ? "Glutes and hips" : MuscleTraining.capitalized(name) }

    var plural: Bool {
        switch self {
        case .chest, .upperBack, .lowerBack, .core: false
        default: true
        }
    }

    /// Head to toe, for ties.
    var order: Int { MuscleGroup.allCases.firstIndex(of: self) ?? 0 }

    /// Drawable muscle slugs in this group.
    public var drawableMuscles: Set<String> {
        Set(muscles.filter { MuscleGroup(region: $0.region) == self }
            .map { $0.drawable ? $0.id : ($0.renderVia ?? $0.id) })
    }
}
