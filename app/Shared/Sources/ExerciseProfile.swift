import Foundation

/// V6 exercise knowledge (docs/VERSION-6.md §10): what an exercise is for
/// the planner. Authored in content/src/profiles.js and shipped in the packs.
public struct ExerciseProfile: Codable, Sendable, Hashable {
    public struct Conditioning: Codable, Sendable, Hashable {
        /// aerobic-base · aerobic-power · tempo · repeated-sprint · anaerobic
        public let type: String
        /// run · bike · row · rope · bodyweight · stairs · sled
        public let modality: String
    }

    /// squat · hinge · push · pull · carry · rotation · anti-rotation ·
    /// unilateral-lower · jump · throw · sprint · deceleration ·
    /// change-of-direction · locomotion · conditioning · mobility · isolation ·
    /// balance · breathing · skill
    public let pattern: String
    /// prep · power · speed · primary · secondary · accessory · trunk ·
    /// conditioning · mobility · recovery · skill
    public let role: String
    /// lower · upper · trunk
    public let regions: [String]
    /// 1 (barely any) … 5 (a heavy compound, a hard interval set).
    public let fatigue: Int
    /// 0 none … 3 high (jumps, max sprints).
    public let impact: Int
    /// 1 simple … 3 needs coaching.
    public let technique: Int
    /// 0 … 3: how much it adds to tired legs.
    public let legLoad: Int
    /// Exercises in the same group can stand in for each other.
    public let group: String
    public let conditioning: Conditioning?
    /// What it trains (docs/TRAINING-RESEARCH.md §2): a `TrainingQuality` raw
    /// value. Optional: packs built before it existed don't carry it, and a
    /// newer pack may name a quality this build doesn't know (see `trains`).
    public let quality: String?
    /// The energy system that pays for it: an `EnergySystem` raw value.
    public let energy: String?
    /// Primary and secondary muscles, in the focus vocabulary (`focusMuscleOrder`).
    public let muscles: MuscleFocus?

    public struct MuscleFocus: Codable, Sendable, Hashable {
        public let primary: [String]
        public let secondary: [String]

        public init(primary: [String], secondary: [String] = []) {
            self.primary = primary
            self.secondary = secondary
        }
    }

    public init(pattern: String, role: String, regions: [String], fatigue: Int, impact: Int, technique: Int,
                legLoad: Int, group: String, conditioning: Conditioning? = nil, quality: String? = nil,
                energy: String? = nil, muscles: MuscleFocus? = nil) {
        self.pattern = pattern
        self.role = role
        self.regions = regions
        self.fatigue = fatigue
        self.impact = impact
        self.technique = technique
        self.legLoad = legLoad
        self.group = group
        self.conditioning = conditioning
        self.quality = quality
        self.energy = energy
        self.muscles = muscles
    }

    public var isLower: Bool { regions.contains("lower") }
    public var isUpper: Bool { regions.contains("upper") }

    /// The quality it trains: the pack's, or one worked out from its role and
    /// pattern for a pack that predates it.
    public var trains: TrainingQuality {
        if let quality, let known = TrainingQuality(rawValue: quality) { return known }
        if let conditioning {
            switch conditioning.type {
            case "repeated-sprint": return .repeatedSprint
            case "anaerobic": return .anaerobic
            default: return .aerobic
            }
        }
        switch role {
        case "speed": return pattern == "change-of-direction" ? .changeOfDirection : .acceleration
        case "power":
            if pattern == "deceleration" { return .deceleration }
            return group == "reactive-hop" ? .reactive : .speedStrength
        case "primary": return .maxStrength
        case "secondary": return .maxStrength
        case "trunk": return .stability
        case "mobility", "prep": return .mobility
        case "recovery": return .recovery
        case "conditioning": return .aerobic
        default: return pattern == "balance" ? .stability : .injuryPrevention
        }
    }

    public var energySystem: EnergySystem? {
        energy.flatMap(EnergySystem.init(rawValue:)) ?? trains.defaultEnergy
    }

    /// Main movers, known focus names only.
    public var primaryMuscles: [String] { (muscles?.primary ?? []).filter { focusMuscleSlugs[$0] != nil } }
    public var secondaryMuscles: [String] { (muscles?.secondary ?? []).filter { focusMuscleSlugs[$0] != nil } }

    /// What it builds, in a few words: "single-leg strength", "power".
    public var buildsPhrase: String {
        switch trains {
        case .maxStrength:
            if pattern == "unilateral-lower" || group.hasPrefix("single-leg") { return "single-leg strength" }
            if isLower { return "leg strength" }
            if isUpper { return "upper-body strength" }
            return "strength"
        case .stability:
            return role == "trunk" || regions == ["trunk"] ? "trunk control" : "balance"
        default:
            return trains.phrase
        }
    }

    /// "Power · glutes, quads" — what an exercise row says it trains.
    public var trainsLabel: String {
        let names = primaryMuscles.prefix(2).map(FocusMuscle.title)
        return names.isEmpty ? trains.title : "\(trains.title) · \(names.joined(separator: ", "))"
    }

    /// Whether it trains a muscle group (the body map's), as a main or helping mover.
    public func works(_ group: MuscleGroup, primaryOnly: Bool = false) -> Bool {
        (primaryOnly ? primaryMuscles : primaryMuscles + secondaryMuscles).contains { FocusMuscle.group($0) == group }
    }
}

/// The main physical quality an exercise develops (docs/TRAINING-RESEARCH.md §2).
public enum TrainingQuality: String, CaseIterable, Codable, Sendable {
    case maxStrength = "max-strength"
    /// Heavy and fast (cleans, loaded jumps): the force end of power.
    case strengthSpeed = "strength-speed"
    /// Light and fast (jumps, throws): the velocity end of power.
    case speedStrength = "speed-strength"
    /// Short ground contacts that use the stretch-shortening cycle.
    case reactive
    case acceleration
    case maxVelocity = "max-velocity"
    case changeOfDirection = "change-of-direction"
    /// Braking and landing.
    case deceleration
    case hypertrophy
    case strengthEndurance = "strength-endurance"
    case aerobic
    case anaerobic
    case repeatedSprint = "repeated-sprint"
    case mobility
    case stability
    case injuryPrevention = "injury-prevention"
    case recovery

    public var title: String {
        switch self {
        case .maxStrength: "Strength"
        case .strengthSpeed: "Heavy power"
        case .speedStrength: "Power"
        case .reactive: "Reactive power"
        case .acceleration: "Acceleration"
        case .maxVelocity: "Top speed"
        case .changeOfDirection: "Change of direction"
        case .deceleration: "Braking and landing"
        case .hypertrophy: "Muscle"
        case .strengthEndurance: "Strength endurance"
        case .aerobic: "Aerobic fitness"
        case .anaerobic: "Anaerobic capacity"
        case .repeatedSprint: "Repeat sprints"
        case .mobility: "Mobility"
        case .stability: "Stability"
        case .injuryPrevention: "Injury prevention"
        case .recovery: "Recovery"
        }
    }

    /// Lower case, for a sentence.
    public var phrase: String {
        switch self {
        case .strengthSpeed, .speedStrength: "power"
        case .injuryPrevention: "injury resilience"
        case .repeatedSprint: "repeat-sprint fitness"
        default: title.lowercased()
        }
    }

    /// How it's trained, in one line — the reason the dose looks the way it does.
    public var howItsTrained: String {
        switch self {
        case .maxStrength: "Heavy enough that the last reps are hard but clean — stop with 2–3 reps left, rest fully."
        case .strengthSpeed: "Moderate weight moved as fast as possible: few reps, long rest, stop if it slows."
        case .speedStrength: "Every rep at full intent and full speed. Few reps, long rest — tired reps teach slow."
        case .reactive: "Quick, stiff contacts off the ground. Few of them, fully fresh — quality, not fatigue."
        case .acceleration: "Short all-out sprints from a start, with full rest between."
        case .maxVelocity: "A build-up, then a few seconds at top speed. Full rest; stop when you slow down."
        case .changeOfDirection: "Sharp plants and cuts at game speed, rested enough to stay sharp."
        case .deceleration: "Braking and landing with control: hold each landing, knees over toes."
        case .hypertrophy: "Moderate weight, 8–15 controlled reps, close to — not at — failure."
        case .strengthEndurance: "Longer sets with steady form; stop when the form changes."
        case .aerobic: "Easy enough to talk, or steady hard intervals — it builds the engine that recovers you."
        case .anaerobic: "Short, very hard efforts with long easy recoveries."
        case .repeatedSprint: "Repeated short sprints with short rests: like the hardest minutes of a game."
        case .mobility: "Slow and controlled through the full range."
        case .stability: "Hold positions against movement; quality over time."
        case .injuryPrevention: "Small, regular doses — the effect comes from doing it every week."
        case .recovery: "Easy and calm — you should feel better afterwards."
        }
    }

    public var isFast: Bool { [.strengthSpeed, .speedStrength, .reactive, .acceleration, .maxVelocity, .changeOfDirection].contains(self) }

    var defaultEnergy: EnergySystem? {
        switch self {
        case .strengthSpeed, .speedStrength, .reactive, .acceleration, .maxVelocity, .changeOfDirection, .deceleration: .alactic
        case .aerobic: .aerobic
        case .anaerobic: .glycolytic
        case .repeatedSprint: .mixed
        default: nil
        }
    }
}

/// Which energy system pays for the work (conditioning and fast work).
public enum EnergySystem: String, CaseIterable, Codable, Sendable {
    /// Phosphocreatine: all-out efforts up to ~10 s, full recovery in minutes.
    case alactic
    /// Hard efforts of roughly 20 s to 2 min.
    case glycolytic
    case aerobic
    /// Repeated short efforts: fast energy for the effort, aerobic for the recovery.
    case mixed

    public var title: String {
        switch self {
        case .alactic: "Short and explosive"
        case .glycolytic: "Hard and burning"
        case .aerobic: "Aerobic"
        case .mixed: "Repeated efforts"
        }
    }
}

/// The focus muscle words ("glutes", "lats") — generated from content/src/profiles.js.
public enum FocusMuscle {
    /// "glutes", "outer hips", "front shoulders".
    public static func title(_ slug: String) -> String {
        switch slug {
        case "glute-med": "outer hips"
        case "front-delts": "front shoulders"
        case "side-delts": "side shoulders"
        case "rear-delts": "rear shoulders"
        case "serratus": "serratus"
        default: slug.replacingOccurrences(of: "-", with: " ")
        }
    }

    /// The body map's group for a focus muscle (nil: the neck).
    public static func group(_ slug: String) -> MuscleGroup? {
        guard let first = focusMuscleSlugs[slug]?.first, let info = musclesBySlug[first] else { return nil }
        return MuscleGroup(region: info.region)
    }

    /// The focus muscles drawn in a body-map group, head to toe.
    public static func inGroup(_ group: MuscleGroup) -> [String] {
        focusMuscleOrder.filter { self.group($0) == group }
    }
}

/// What a session as a whole builds, from its exercises' profiles.
public enum SessionTrains {
    /// "power", "single-leg strength", … — main work only, in session order, at most `limit`.
    public static func builds(_ items: [GeneratedPlannedItem], catalogue: Catalogue, limit: Int = 3) -> [String] {
        var out: [String] = []
        // Warm-up and cool-down aren't what a session builds; the sport's drill is skill work.
        let warmUp: Set<SessionBlock> = [.prep, .cooldown, .skill]
        let main = items.filter { item in item.block.map { !warmUp.contains($0) } ?? true }
        for item in main.sorted(by: { $0.order < $1.order }) {
            guard let profile = catalogue.item(item.itemSlug)?.planProfile else { continue }
            if item.block == .mobility, main.contains(where: { $0.block != .mobility && $0.block != nil }) { continue }
            let phrase = profile.buildsPhrase
            if !out.contains(phrase) { out.append(phrase) }
        }
        return Array(out.prefix(limit))
    }

    /// Weighted sets per body-map group in a session (main mover 1, helper 0.5).
    public static func sets(_ items: [GeneratedPlannedItem], catalogue: Catalogue) -> [MuscleGroup: Double] {
        var out: [MuscleGroup: Double] = [:]
        for item in items {
            guard let profile = catalogue.item(item.itemSlug)?.planProfile else { continue }
            var credit: [MuscleGroup: Double] = [:]
            for slug in profile.primaryMuscles { if let g = FocusMuscle.group(slug) { credit[g] = 1 } }
            for slug in profile.secondaryMuscles { if let g = FocusMuscle.group(slug), credit[g] == nil { credit[g] = 0.5 } }
            for (g, c) in credit { out[g, default: 0] += c * Double(item.dose.sets) }
        }
        return out
    }
}

extension CatalogueItem {
    /// The pack's profile, or — for a pack downloaded before profiles
    /// existed — a conservative one from the item's qualities.
    public var planProfile: ExerciseProfile {
        if let profile { return profile }
        let top = qualities.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? ""
        let jumps = defaultDose.kind == plyometricDoseKind
        if kind == "drill" {
            return ExerciseProfile(pattern: "skill", role: "skill", regions: ["lower"], fatigue: 2, impact: jumps ? 3 : 1,
                                   technique: 2, legLoad: 2, group: "skill-\(itemSportSlug ?? "general")")
        }
        switch top {
        case "acceleration", "max-velocity", "change-of-direction", "lateral-power", "deceleration":
            return ExerciseProfile(pattern: "sprint", role: "speed", regions: ["lower"], fatigue: 2, impact: 2, technique: 1, legLoad: 2, group: "speed")
        case "vertical-power", "horizontal-power", "rotational-power", "overhead-power", "reactive-strength":
            return ExerciseProfile(pattern: jumps ? "jump" : "throw", role: "power", regions: ["lower"], fatigue: 2, impact: jumps ? 3 : 0,
                                   technique: 1, legLoad: jumps ? 2 : 1, group: "power")
        case "aerobic-base", "anaerobic-capacity", "repeat-sprint":
            return ExerciseProfile(pattern: "conditioning", role: "conditioning", regions: ["lower"], fatigue: 3, impact: 2, technique: 1,
                                   legLoad: 2, group: "conditioning-interval", conditioning: .init(type: "aerobic-power", modality: "run"))
        case "lower-body-strength":
            return ExerciseProfile(pattern: "squat", role: "secondary", regions: ["lower"], fatigue: 3, impact: 0, technique: 1, legLoad: 2, group: "squat-bilateral")
        case "upper-body-push":
            return ExerciseProfile(pattern: "push", role: "secondary", regions: ["upper"], fatigue: 2, impact: 0, technique: 1, legLoad: 0, group: "push-horizontal")
        case "upper-body-pull":
            return ExerciseProfile(pattern: "pull", role: "secondary", regions: ["upper"], fatigue: 2, impact: 0, technique: 1, legLoad: 0, group: "pull-horizontal")
        case "trunk-anti-rotation":
            return ExerciseProfile(pattern: "anti-rotation", role: "trunk", regions: ["trunk"], fatigue: 1, impact: 0, technique: 1, legLoad: 0, group: "anti-rotation")
        case "hip-mobility":
            return ExerciseProfile(pattern: "mobility", role: "mobility", regions: ["lower"], fatigue: 1, impact: 0, technique: 1, legLoad: 0, group: "mobility-hip")
        default:
            return ExerciseProfile(pattern: "isolation", role: "accessory", regions: ["lower"], fatigue: 1, impact: 0, technique: 1, legLoad: 1, group: "accessory")
        }
    }
}
