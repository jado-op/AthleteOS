import Foundation

// V6 workout engine, part 2: from a decision to a session
// (docs/VERSION-6.md §6–§8). Blocks in a fixed order, few exercises chosen
// for a purpose, doses by role, and a time model that matches real sessions.

/// The parts of a session, in the order they're done.
public enum SessionBlock: String, Codable, Sendable, CaseIterable {
    case prep, power, skill, primaryStrength, secondaryStrength, accessory, conditioning, mobility, cooldown

    public var title: String {
        switch self {
        case .prep: "Movement prep"
        case .power: "Power & speed"
        case .skill: "Your sport"
        case .primaryStrength: "Main strength"
        case .secondaryStrength: "Secondary strength"
        case .accessory: "Trunk & resilience"
        case .conditioning: "Conditioning"
        case .mobility: "Mobility"
        case .cooldown: "Cool-down"
        }
    }
}

/// Who the session is for: what they can do and what they own.
public struct AthleteKit: Sendable {
    public var catalogue: Catalogue
    public var sport: SportInfo?
    public var positionSlug: String?
    public var formatSlug: String?
    public var equipment: Set<String>
    public var trainsUnderCoach: Bool
    /// Exercises to leave out when there's another choice (yesterday's).
    public var avoidSlugs: Set<String>
    /// Jump contacts still allowed this week.
    public var contactsLeft: Int
    public var seed: String

    public init(catalogue: Catalogue, sport: SportInfo?, positionSlug: String? = nil, formatSlug: String? = nil,
                equipment: Set<String>, trainsUnderCoach: Bool = false, avoidSlugs: Set<String> = [], contactsLeft: Int = 100,
                seed: String = "") {
        self.catalogue = catalogue
        self.sport = sport
        self.positionSlug = positionSlug
        self.formatSlug = formatSlug
        self.equipment = equipment
        self.trainsUnderCoach = trainsUnderCoach
        self.avoidSlugs = avoidSlugs
        self.contactsLeft = contactsLeft
        self.seed = seed
    }
}

public enum SessionBuilder {
    /// Groups that protect the areas a sport loads most.
    static let resilienceGroups: [String: [String]] = [
        "hamstrings": ["hamstring-eccentric"], "groin": ["hip-adductor"], "hips": ["hip-adductor", "hip-activation"], "hip-flexors": ["hip-adductor"],
        "knees": ["knee-isometric", "knee-eccentric"], "knee": ["knee-isometric"], "front-knee": ["knee-isometric"],
        "ankles": ["calf-ankle"], "shins": ["calf-ankle"], "achilles": ["calf-ankle"],
        "shoulder": ["shoulder-health"], "shoulders": ["shoulder-health"], "elbow": ["shoulder-health"], "elbows": ["shoulder-health"],
        "upper-back": ["shoulder-health"], "lower-back": ["back-extension", "anti-extension"], "neck": ["neck"],
        "wrists": ["grip"], "wrist": ["grip"], "lead-wrist": ["grip"], "forearms": ["grip"], "fingers": ["grip"],
    ]
    static let trunkGroups = ["anti-rotation", "anti-extension", "anti-lateral", "rotation", "carry"]

    public static func build(_ decision: SessionDecision, day: TrainingDay, kit: AthleteKit) -> GeneratedSession {
        var state = BuildState(decision: decision, day: day, kit: kit)
        switch decision.sessionType {
        case .gymDevelopment:
            if let focus = decision.gymFocus, let gym = day.gym { state.focusedGym(focus, gym) } else { state.gymDay() }
        case .afterPractice: state.afterPractice()
        case .primer: state.primer()
        case .conditioning: state.conditioningSession()
        case .recovery: state.recovery()
        case .mobility: state.mobility(decision.mobilityPurpose ?? .targeted)
        case .travel: state.travel()
        case .rest: break
        }
        state.fit()
        return state.session()
    }

    /// Seconds one planned item takes, sets, rest and setup included.
    public static func seconds(_ item: GeneratedPlannedItem) -> Int {
        let dose = item.dose
        let sides = dose.perSide == true ? 2 : 1
        let work: Int
        switch dose.kind {
        case "reps": work = (dose.reps ?? 8) * (item.block == .primaryStrength || item.block == .secondaryStrength ? 4 : 3) * sides
        case "time": work = (dose.seconds ?? 30) * sides
        case "distance": work = Int((dose.metres ?? 20) / 4) + 15
        case plyometricDoseKind: work = (dose.contacts ?? 5) * 2 * sides
        default: work = 30
        }
        let setup = item.block == .prep || item.block == .mobility || item.block == .cooldown ? 10
            : item.block == .primaryStrength || item.block == .secondaryStrength ? 75 : 45
        return dose.sets * work + max(0, dose.sets - 1) * item.restSec + setup
    }
}

private struct BuildState {
    let decision: SessionDecision
    let day: TrainingDay
    let kit: AthleteKit
    var rng: SeededGenerator
    var picks: [(item: CatalogueItem, block: SessionBlock, why: String, quality: String)] = []
    var conditioning: ConditioningPrescription?
    var contactsLeft: Int
    let qualityWeight: [String: Double]
    /// Training stage (docs/TRAINING-RESEARCH.md §1).
    let stage: TrainingStage
    /// Reasons the builder adds to the decision's (an injury-prevention staple, pull balance…).
    var addedReasons: [PlanReason] = []
    /// A jump was left out because the session's landings were used up.
    var landingsLimited = false
    /// The sport's preventable injuries, most important first.
    let risks: [InjuryRisk]

    /// One candidate: the item, its profile and its relevance — worked out once per build.
    struct Candidate {
        let item: CatalogueItem
        let profile: ExerciseProfile
        let score: Double
    }

    /// Everything this athlete may do in this session, best first. Built once
    /// per build: which items fit never changes between picks; only `used`
    /// and the jump budget do.
    let pool: [Candidate]

    init(decision: SessionDecision, day: TrainingDay, kit: AthleteKit) {
        self.decision = decision
        self.day = day
        self.kit = kit
        rng = SeededGenerator(seed: "\(kit.seed)|\(decision.sessionType.rawValue)")
        stage = decision.stage ?? day.stage
        // Per-session landings by stage, a quarter fewer in season — inside the weekly cap.
        let inSeason = day.phase == .inSeason || day.phase == .postSeason
        let sessionCap = inSeason ? stage.sessionLandingCap * 3 / 4 : stage.sessionLandingCap
        contactsLeft = min(kit.contactsLeft, sessionCap)
        risks = InjuryPrevention.risks(sport: kit.sport?.slug, demands: day.demands)
        var weights = kit.sport?.qualityProfile ?? [:]
        if let position = kit.positionSlug, let profile = kit.sport?.positions.first(where: { $0.slug == position })?.qualityProfile {
            for (q, w) in profile { weights[q] = (weights[q] ?? 0) + w }
        }
        for goal in day.goals {
            for (q, c) in Capacity.fromQuality where c == goal { weights[q] = (weights[q] ?? 0) + 0.6 }
        }
        qualityWeight = weights
        var candidates: [Candidate] = []
        for item in kit.catalogue.itemsBySlug.values {
            let profile = item.planProfile
            guard Self.fits(item, profile, decision: decision, day: day, kit: kit) else { continue }
            candidates.append(Candidate(item: item, profile: profile, score: Self.relevance(item, weights: weights, day: day, kit: kit)))
        }
        candidates.sort { (lhs: Candidate, rhs: Candidate) -> Bool in
            lhs.score != rhs.score ? lhs.score > rhs.score : lhs.item.slug < rhs.item.slug
        }
        pool = candidates
    }

    /// Slugs already in the session (kept in step with `picks`; read for every item on every pick).
    var used: Set<String> = []
    /// Sets added to a block when the session came out short (§7: more good
    /// sets before more exercises).
    var extraSets: [SessionBlock: Int] = [:]

    // MARK: Eligibility

    /// Whether the athlete may get this item in this session at all.
    static func fits(_ item: CatalogueItem, _ p: ExerciseProfile, decision: SessionDecision, day: TrainingDay, kit: AthleteKit) -> Bool {
        guard item.fits(sport: kit.sport?.slug, position: kit.positionSlug, format: kit.formatSlug),
              PlanGenerator.isEligibleForEquipment(item, available: kit.equipment),
              kit.trainsUnderCoach || !item.isCoached,
              item.minAge <= day.age,
              day.experience.allows(item),
              !PainFilter.loads(item, areas: day.painAreas) else { return false }
        let restful = ["prep", "mobility", "recovery"].contains(p.role)
        if !restful {
            let primerStart = decision.sessionType == .primer && p.group == "sprint-accel"
            if p.isLower, p.legLoad > decision.legBudget, p.role != "trunk", !primerStart { return false }
            if decision.avoids(.highImpact), p.impact >= 2, !primerStart { return false }
            if decision.avoids(.maxSprinting), p.group == "sprint-maxv" { return false }
            if decision.avoids(.heavyLowerBody), p.isLower, p.fatigue >= 4 { return false }
            if decision.avoids(.newHardExercises) || day.age < 15, p.technique >= 3 { return false }
        }
        if p.impact >= 3, day.age < 13 { return false }
        return true
    }

    static func relevance(_ item: CatalogueItem, weights: [String: Double], day: TrainingDay, kit: AthleteKit) -> Double {
        var score = 0.0
        for (q, amount) in item.qualities { score += amount * (weights[q] ?? 0.1) }
        if item.itemSportSlug != nil, item.itemSportSlug == kit.sport?.slug { score += 0.2 }
        // Learn the base movement before its variants.
        if item.baseSlug != nil { score -= day.experience == .experienced ? 0.15 : 0.6 }
        if kit.avoidSlugs.contains(item.slug) { score -= 0.6 }
        return score
    }

    /// Picks one exercise matching `filter`, best for the athlete first, with
    /// a little variety among the top few. Returns whether it found one.
    @discardableResult
    mutating func pick(_ block: SessionBlock, why: String, pool poolSize: Int = 3, _ filter: (CatalogueItem, ExerciseProfile) -> Bool) -> Bool {
        // An "explosive" tempo variant is power work, never a strength or trunk exercise.
        let strengthBlock = [.primaryStrength, .secondaryStrength, .accessory].contains(block)
        // Foundation stage: more variety among good choices (diversified
        // practice when young — Güllich 2022, Côté's DMSP).
        let size = stage == .foundation && block != .skill ? max(poolSize, 5) : poolSize
        var matching: [Candidate] = []
        var skippedForLandings = false
        for candidate in pool {
            if matching.count == size { break }
            if used.contains(candidate.item.slug) { continue }
            if strengthBlock, candidate.item.variant?.tempo == "explosive" { continue }
            guard filter(candidate.item, candidate.profile) else { continue }
            if Self.landings(candidate.item, candidate.profile, sets: 1) > 0, contactsLeft < Self.landings(candidate.item, candidate.profile, sets: 3) {
                skippedForLandings = true
                continue
            }
            matching.append(candidate)
        }
        if matching.isEmpty, skippedForLandings { landingsLimited = true }
        guard !matching.isEmpty else { return false }
        let item: CatalogueItem = matching[Int(rng.next() % UInt64(matching.count))].item
        let best = item.qualities.max { (a: (key: String, value: Double), b: (key: String, value: Double)) -> Bool in
            a.value != b.value ? a.value < b.value : a.key > b.key
        }
        let quality: String = best?.key ?? ""
        picks.append((item, block, why, quality))
        used.insert(item.slug)
        // Charged at the sets it will actually get (power: up to 4).
        contactsLeft -= Self.landings(item, item.planProfile, sets: block == .power ? (decision.sessionType == .primer ? 2 : 4) : 3)
        return true
    }

    /// Jump landings for `sets` sets: plyometric contacts, or the reps of a
    /// jump exercise dosed in reps (countermovement, broad jumps…).
    static func landings(_ item: CatalogueItem, _ profile: ExerciseProfile, sets: Int) -> Int {
        if item.defaultDose.kind == plyometricDoseKind { return (item.defaultDose.contacts ?? 5) * sets }
        if profile.group.hasPrefix("jump"), item.defaultDose.kind == "reps" { return min(item.defaultDose.reps ?? 5, 5) * sets }
        return 0
    }

    @discardableResult
    mutating func pickGroup(_ block: SessionBlock, _ groups: [String], role: String? = nil, why: String, pool: Int = 3) -> Bool {
        for group in groups {
            if pick(block, why: why, pool: pool, { _, p in p.group == group && (role == nil || p.role == role) }) { return true }
        }
        return false
    }

    var loadAreas: [String] { kit.sport?.commonLoadAreas ?? [] }

    // MARK: Session types

    mutating func prep(count: Int, upperFocus: Bool, fast: Bool) {
        pickGroup(.prep, ["mobility-flow"], why: "Opens hips, hamstrings and upper back in one movement.")
        pickGroup(.prep, ["mobility-hip", "mobility-ankle"], role: "prep", why: "Range at the hips and ankles before you load them.")
        if upperFocus {
            pickGroup(.prep, ["shoulder-health", "mobility-shoulder"], role: "prep", why: "Wakes up the shoulder blade before pressing and pulling.")
        } else {
            pickGroup(.prep, ["hip-activation"], why: "Switches on the glutes that keep the knees in line.")
        }
        if count >= 4 {
            if fast, !decision.avoids(.highImpact) {
                pickGroup(.prep, ["sprint-mechanics", "sprint-accel-drill"], why: "Rhythm and posture: the bridge from warm-up to fast work.")
            } else {
                pickGroup(.prep, ["crawl", "hip-activation", "shoulder-health"], why: "Gets the whole body working together.")
            }
        }
    }

    mutating func powerBlock(count: Int) {
        let targets = decision.primaryTargets
        var placed = 0
        // Foundation stage, or a sport that tears knee ligaments: learn to land
        // before jumping higher (Lloyd & Oliver 2012; Petushek 2019).
        if !decision.avoids(.highImpact), stage == .foundation || (risks.first == .knee && stage != .performance), placed < count,
           pickGroup(.power, ["landing", "decel"], why: "Landing and braking first: soft, quiet, knees over toes — the skill every jump is built on.") {
            placed += 1
        }
        if targets.contains(.acceleration), placed < count,
           pickGroup(.power, ["sprint-accel", "sprint-accel-resisted"], why: "Short sprints while you're fresh: acceleration is trained at full speed or not at all.") { placed += 1 }
        if targets.contains(.speed), placed < count,
           pickGroup(.power, ["sprint-maxv"], why: "A few fast runs to build top speed — full rest between.") { placed += 1 }
        if (targets.contains(.power) || placed < count), placed < count {
            let lateral = (day.demands.weights[.coordination] ?? 0) >= 0.7
            // Performance stage: the heavier end of power too (loaded jumps,
            // Olympic pulls) — force–velocity work for athletes with a strength base.
            let heavy = stage == .performance && !decision.avoids(.heavyLowerBody) ? ["olympic"] : []
            let groups = decision.avoids(.highImpact)
                ? ["throw-rotational", "throw-overhead", "throw-chest", "hinge-ballistic"]
                : heavy + (lateral ? ["jump-lateral", "jump-vertical", "jump-horizontal"] : ["jump-vertical", "jump-horizontal", "jump-lateral"]) + ["throw-rotational", "throw-overhead"]
            if pickGroup(.power, groups, why: "Explosive work goes first, before fatigue blunts it.") { placed += 1 }
        }
        if placed < count, (day.demands.weights[.power] ?? 0) >= 0.5 || (qualityWeight["rotational-power"] ?? 0) > 0.5 {
            pickGroup(.power, ["throw-rotational", "throw-overhead", "throw-chest"], why: "Throws train power with almost no impact on the legs.")
        }
    }

    /// One drill of the athlete's own sport — for their position when there
    /// is one (owner's rule: every session has at least one).
    mutating func skillBlock(why: String) {
        guard let sport = kit.sport?.slug else { return }
        if let position = kit.positionSlug,
           pick(.skill, why: "A drill for your position — the job you do in your sport.", { item, profile in
               profile.role == "skill" && item.itemSportSlug == sport && (item.positions?.contains(position) ?? false)
           }) { return }
        pick(.skill, why: why) { item, profile in
            profile.role == "skill" && item.itemSportSlug == sport && (item.positions?.isEmpty ?? true)
        }
    }

    func lowerGroups(_ pattern: String?) -> [String] {
        pattern == "hinge" ? ["hinge-bilateral", "hinge-hip-extension", "single-leg-hip", "hinge-ballistic"]
            : ["squat-bilateral", "single-leg-knee", "single-leg-lateral"]
    }

    /// Planes alternate day to day: rows as well as pull-downs, overhead as
    /// well as bench (before, the first plane with any candidate always won).
    func upperGroups(_ pattern: String?) -> [String] {
        let odd = (Calendar.current.ordinality(of: .day, in: .era, for: day.date) ?? 0) % 2 == 1
        if pattern == "pull" { return odd ? ["pull-horizontal", "pull-vertical"] : ["pull-vertical", "pull-horizontal"] }
        return odd ? ["push-vertical", "push-horizontal", "push-incline"] : ["push-horizontal", "push-vertical", "push-incline"]
    }

    // MARK: The athlete's own gym session (focus + length)

    /// Picks the anchor for a slot: the same lift for the whole four-week block
    /// (its own seed, and yesterday's penalty ignored), unless it stalled —
    /// then the next lift of the same family, a new angle on the same job.
    @discardableResult
    mutating func pickAnchor(_ slot: GymSlots.Slot, seed: String, stalled: Set<String>) -> Bool {
        for group in slot.groups {
            var matching: [Candidate] = []
            for candidate in pool where candidate.profile.group == group && !used.contains(candidate.item.slug) {
                if candidate.item.variant?.tempo == "explosive" { continue }
                if Self.landings(candidate.item, candidate.profile, sets: 3) > 0 { continue }
                matching.append(candidate)
            }
            guard !matching.isEmpty else { continue }
            // Stable order: relevance without the "trained yesterday" penalty.
            matching.sort { lhs, rhs in
                let l = lhs.score + (kit.avoidSlugs.contains(lhs.item.slug) ? 0.6 : 0)
                let r = rhs.score + (kit.avoidSlugs.contains(rhs.item.slug) ? 0.6 : 0)
                return l != r ? l > r : lhs.item.slug < rhs.item.slug
            }
            var choices = Array(matching.prefix(2))
            if choices.count > 1, choices.contains(where: { stalled.contains($0.item.slug) }) {
                choices.removeAll { stalled.contains($0.item.slug) }
            }
            var anchorRng = SeededGenerator(seed: "\(seed)|\(group)")
            let item = choices[Int(anchorRng.next() % UInt64(choices.count))].item
            let replaced = matching.prefix(2).contains { stalled.contains($0.item.slug) } && !stalled.contains(item.slug)
            let why = replaced ? slot.why + " New variation: the last one stopped going up." : slot.why
            let quality = item.qualities.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? ""
            picks.append((item, slot.block, why, quality))
            used.insert(item.slug)
            return true
        }
        return false
    }

    /// One rotating accessory from the families, never last session's when
    /// there's another choice.
    @discardableResult
    mutating func pickAccessory(_ groups: [String], avoid: Set<String>, why: String) -> Bool {
        if pick(.accessory, why: why, pool: 4, { item, profile in groups.contains(profile.group) && !avoid.contains(item.slug) }) { return true }
        return pick(.accessory, why: why, pool: 4) { _, profile in groups.contains(profile.group) }
    }

    /// The athlete's own gym session: prep, (power), a drill of their sport,
    /// the anchors of the focus, rotating accessories, and — in the full
    /// version — a conditioning finisher and a cool-down.
    mutating func focusedGym(_ focus: GymFocus, _ gym: GymRequest) {
        let length = gym.length
        let lowerHeavy = (focus == .lower || focus == .full) && decision.legBudget >= 2
        prep(count: length == .quick ? 2 : length == .standard ? 3 : 4, upperFocus: focus == .upper || focus == .core || !lowerHeavy,
             fast: lowerHeavy && length != .quick)
        // Power before strength, while fresh: legs and full body get a jump or
        // sprint; upper body a throw (no landings).
        if length != .quick, day.readiness >= .normal {
            if lowerHeavy, !decision.primaryTargets.filter({ [.power, .acceleration, .speed].contains($0) }).isEmpty {
                powerBlock(count: length == .full ? 2 : 1)
            } else if focus == .upper {
                pickGroup(.power, ["throw-chest", "throw-overhead", "throw-rotational", "push-vertical-power"], why: "Explosive upper-body work first, while you're fresh.")
            }
        }
        skillBlock(why: "A drill of your sport while you're fresh: skill and strength in one session.")
        // Anchors: quick keeps the first two, longer sessions all of them.
        let slots = GymSlots.anchors(focus, legBudget: decision.legBudget)
        let anchorCount = length == .quick ? min(2, slots.count) : slots.count
        let seed = "\(gym.anchorSeed)|\(focus.rawValue)"
        for slot in slots.prefix(anchorCount) { pickAnchor(slot, seed: seed, stalled: gym.stalledAnchors) }
        // Accessories: fresh every session, from the focus's families.
        let accessoryCount: Int
        switch length {
        case .quick: accessoryCount = focus == .core ? 2 : 0
        case .standard: accessoryCount = 3
        case .full: accessoryCount = 5
        }
        let families = GymSlots.accessories(focus)
        let offset = Int(rng.next() % UInt64(max(families.count, 1)))
        var added = 0
        for step in 0..<families.count where added < accessoryCount {
            let groups = families[(offset + step) % families.count]
            if groups.allSatisfy({ group in ["hamstring-eccentric", "single-leg-lateral", "calf-ankle", "hip-adductor", "knee-isometric", "knee-eccentric", "hinge-hip-extension", "single-leg-hip"].contains(group) }),
               decision.legBudget < 1 { continue }
            if pickAccessory(groups, avoid: gym.lastAccessories, why: accessoryWhy(groups.first ?? "")) { added += 1 }
        }
        // Every session that isn't core-only still carries one trunk exercise and the sport's injury staple.
        if focus != .core {
            if length != .quick || focus == .full {
                pickGroup(.accessory, ["anti-rotation", "anti-extension", "anti-lateral", "carry"], role: "trunk",
                          why: "A trunk that resists movement passes force from legs to arms.")
            }
        }
        // The sport's proven prevention work is a fixed part of the region it
        // protects, not a rotating slot (Part 2, A18–A21): Nordics and Copenhagens
        // on leg days, shoulder work on upper days. Low volume is enough
        // (Cuthbert 2020), so even a quick session keeps the first one.
        if !regionStaples(focus, limit: length == .quick ? 1 : 2), length != .quick, focus != .core {
            _ = injuryStaple(rotate: 0)
        }
        if focus == .upper || focus == .full { balancePulling() }
        if length == .full {
            conditioningBlock()
            pickGroup(.cooldown, ["mobility-hip", "mobility-thoracic", "breathing"], why: "A few easy minutes to start recovering.")
        }
    }

    /// The sport's injury staples that belong to today's focus: hamstring and
    /// groin with the legs, shoulder with the upper body. Returns whether any was added.
    mutating func regionStaples(_ focus: GymFocus, limit: Int) -> Bool {
        var wanted: [InjuryRisk] = []
        if focus == .lower || focus == .full, decision.legBudget >= 1 { wanted += risks.filter { $0 == .hamstring || $0 == .groin } }
        if focus == .upper || focus == .full { wanted += risks.filter { $0 == .shoulder } }
        var added = 0
        for risk in wanted where added < limit {
            if picks.contains(where: { risk.groups.contains($0.item.planProfile.group) }) { added += 1; continue }
            if pickGroup(.accessory, risk.groups, why: risk.why) {
                if !addedReasons.contains(.sportInjuryRisk) { addedReasons.append(.sportInjuryRisk) }
                added += 1
            }
        }
        return added > 0
    }

    func accessoryWhy(_ group: String) -> String {
        switch group {
        case "hamstring-eccentric": "Strong hamstrings when they lengthen — the best-proven way to prevent hamstring strains."
        case "single-leg-lateral": "Sideways strength for cutting and changing direction."
        case "calf-ankle": "Calves and ankles that soak up every landing."
        case "hip-adductor": "Inner-thigh strength protects the groin."
        case "knee-isometric", "knee-eccentric": "Knee strength that keeps tendons healthy."
        case "hinge-hip-extension", "single-leg-hip": "Glutes and hamstrings, the engine of sprinting."
        case "push-incline", "push-vertical": "A second pressing angle, so the shoulders get strong all round."
        case "shoulder-health": "Small shoulder muscles that keep throwing and contact safe."
        case "arm-isolation": "Arms: a little extra for elbows that hold up to the work."
        case "pull-horizontal", "pull-vertical": "More pulling: the upper back holds your posture under load."
        case "grip": "Grip strength for holding on, catching and lifting more."
        case "neck": "Neck strength lowers the risk from hits and falls."
        case "rotation": "Rotation with control: throwing, swinging and striking."
        case "carry": "Carries: the whole trunk working while you walk."
        case "back-extension": "The lower back's own strength, so it holds up."
        case "anti-rotation", "anti-lateral": "Trunk from another direction."
        case "balance": "Control on one leg."
        default: "Rotates every session, so the work stays fresh."
        }
    }

    mutating func gymDay() {
        let upperOnly = decision.legBudget < 2
        prep(count: 4, upperFocus: upperOnly, fast: !decision.primaryTargets.filter { [.power, .acceleration, .speed].contains($0) }.isEmpty)
        if !decision.primaryTargets.filter({ [.power, .acceleration, .speed].contains($0) }).isEmpty {
            powerBlock(count: decision.durationTarget >= 55 ? 2 : 1)
        }
        skillBlock(why: "A drill of your sport while you're fresh: skill and strength in one session.")
        // Main strength: one lower pattern and one upper, alternating through the week.
        if !upperOnly {
            if !pickGroup(.primaryStrength, lowerGroups(decision.lowerPattern), role: "primary",
                          why: decision.lowerPattern == "hinge" ? "Hip-hinge strength: the engine for sprinting and jumping." : "Squat strength: the base for acceleration, jumping and landing.") {
                pickGroup(.primaryStrength, lowerGroups(decision.lowerPattern), why: "Lower-body strength for your sport.")
            }
        }
        pickGroup(.primaryStrength, upperGroups(decision.upperPattern), role: "primary",
                  why: decision.upperPattern == "pull" ? "Pulling strength balances all the pushing and throwing in sport." : "Upper-body pressing strength.")
        // Secondary: the other patterns.
        if upperOnly {
            pickGroup(.primaryStrength, upperGroups(decision.upperPattern == "pull" ? "push" : "pull"), role: "primary", why: "The opposite upper-body pattern, so both sides stay balanced.")
        } else if !decision.avoids(.highVolumeLowerBody) {
            let secondaryLower = decision.lowerPattern == "hinge" ? ["single-leg-knee", "single-leg-lateral"] : ["single-leg-hip", "hinge-hip-extension", "hamstring-eccentric"]
            pickGroup(.secondaryStrength, secondaryLower, why: "One leg at a time — how you actually run, cut and land.")
        }
        pickGroup(.secondaryStrength, upperGroups(decision.upperPattern == "pull" ? "push" : "pull"),
                  why: "The opposite upper-body pattern, so both sides stay balanced.")
        trunkAndResilience(count: 2)
        if decision.primaryTargets.contains(.balance) || day.goals.first == .balance {
            pickGroup(.accessory, ["balance"], why: "For your balance goal: control on one leg.")
        }
        balancePulling()
        conditioningBlock()
    }

    mutating func trunkAndResilience(count: Int) {
        let offset = Int((Calendar.current.ordinality(of: .day, in: .era, for: day.date) ?? 0) % SessionBuilder.trunkGroups.count)
        let rotated = Array(SessionBuilder.trunkGroups[offset...] + SessionBuilder.trunkGroups[..<offset])
        pickGroup(.accessory, rotated, role: "trunk", why: "A trunk that resists movement passes force from legs to arms.")
        guard count > 1 else { return }
        // First the sport's proven injury-prevention exercise (Nordics, Copenhagen,
        // landing, shoulder, balance — docs/TRAINING-RESEARCH.md §5): on a gym day the
        // most important one, after practice rotating through the sport's risks.
        if injuryStaple(rotate: decision.sessionType != .gymDevelopment ? offset : 0) { return }
        // The protected area rotates day to day through the sport's load areas,
        // and the reason names the area actually protected.
        let areas = loadAreas.isEmpty ? [] : Array(loadAreas[(offset % loadAreas.count)...] + loadAreas[..<(offset % loadAreas.count)])
        for area in areas {
            let groups = (SessionBuilder.resilienceGroups[area] ?? []).filter { group in !picks.contains { $0.item.planProfile.group == group } }
            if !groups.isEmpty, pickGroup(.accessory, groups, why: "Protects your \(area.replacingOccurrences(of: "-", with: " ")), which your sport loads a lot.") { return }
        }
        pickGroup(.accessory, ["hamstring-eccentric", "shoulder-health", "calf-ankle"], why: "Small strength that prevents common injuries.")
    }

    /// One exercise for the sport's preventable injuries, unless the session
    /// already has one for that risk. Returns whether it added one.
    mutating func injuryStaple(rotate: Int) -> Bool {
        guard !risks.isEmpty else { return false }
        let start = rotate % risks.count
        for risk in Array(risks[start...] + risks[..<start]) {
            if picks.contains(where: { risk.groups.contains($0.item.planProfile.group) }) { continue }
            if pickGroup(.accessory, risk.groups, why: risk.why) {
                if !addedReasons.contains(.sportInjuryRisk) { addedReasons.append(.sportInjuryRisk) }
                return true
            }
        }
        return false
    }

    /// More pulling than pressing (shoulder health): when the session's
    /// pressing muscles out-work the upper back, add one pulling accessory.
    mutating func balancePulling() {
        var push = 0, pull = 0
        for pick in picks where ![.prep, .mobility, .cooldown].contains(pick.block) {
            let p = pick.item.planProfile
            let main = Set(p.primaryMuscles)
            if p.isUpper, !main.isDisjoint(with: ["chest", "front-delts", "triceps"]) { push += 1 }
            if p.isUpper, !main.isDisjoint(with: ["lats", "upper-back", "rear-delts", "rotator-cuff"]) { pull += 1 }
        }
        guard push > pull else { return }
        if pickGroup(.accessory, ["shoulder-health", "pull-horizontal"], why: "More pulling than pressing keeps the shoulders healthy and balanced.") {
            addedReasons.append(.pullBalancesPush)
        }
    }

    mutating func conditioningBlock() {
        guard let type = decision.conditioning, decision.conditioningMinutes > 0 else { return }
        let lowImpact = decision.avoids(.highImpact) || decision.legBudget < 2
        let catalogue = kit.catalogue, equipment = kit.equipment, pain = day.painAreas
        let age = day.age, experience = day.experience, coached = kit.trainsUnderCoach
        // The same limits as every other exercise: equipment, pain, age, coaching, experience.
        let usable: (String) -> Bool = { slug in catalogue.item(slug).map { item in
            PlanGenerator.isEligibleForEquipment(item, available: equipment) && !PainFilter.loads(item, areas: pain)
                && item.minAge <= age && (coached || !item.isCoached) && experience.allows(item)
        } ?? false }
        guard let rx = ConditioningEngine.prescribe(type, minutes: decision.conditioningMinutes, lowImpact: lowImpact, age: day.age,
                                                    experience: day.experience,
                                                    afterLifting: decision.reasons.contains(.strengthBeforeCardio), usable: usable),
              let item = kit.catalogue.item(rx.itemSlug) else { return }
        conditioning = rx
        picks.append((item, .conditioning, "\(type.title): \(rx.summary).", item.qualities.max { $0.value < $1.value }?.key ?? ""))
        used.insert(item.slug)
    }

    mutating func afterPractice() {
        skillBlock(why: "One focused drill of your sport — a few clean reps, not more volume.")
        if decision.primaryTargets.contains(.strength), decision.legBudget >= 2 {
            pickGroup(.secondaryStrength, ["single-leg-knee", "single-leg-hip", "hinge-hip-extension"],
                      why: "A little single-leg strength — low volume, because practice already used your legs.")
        }
        if !pickGroup(.primaryStrength, upperGroups(decision.upperPattern), role: "primary", why: "Practice rarely trains the upper body: this is where it gets strong.") {
            pickGroup(.primaryStrength, upperGroups(decision.upperPattern), why: "Upper-body strength practice doesn't give you.")
        }
        pickGroup(.secondaryStrength, upperGroups(decision.upperPattern == "pull" ? "push" : "pull"), why: "The opposite pattern keeps the shoulders balanced.")
        trunkAndResilience(count: 2)
        if decision.legBudget == 1, !loadAreas.contains("hamstrings") {
            pickGroup(.accessory, ["knee-isometric", "calf-ankle"], why: "Gentle strength for knees and ankles that adds little fatigue.")
        }
    }

    mutating func primer() {
        prep(count: 4, upperFocus: false, fast: true)
        // Sprint starts only where the sport sprints; everyone gets a sharp drill of their own sport.
        if (day.demands.weights[.acceleration] ?? 0) >= 0.4 || (day.demands.weights[.speed] ?? 0) >= 0.4 {
            pickGroup(.power, ["sprint-accel"], why: "Two or three short, fast starts to feel quick for tomorrow — not to get tired.")
        }
        skillBlock(why: "A few sharp reps of your sport's skill to feel ready for tomorrow.")
        pickGroup(.power, ["throw-rotational", "throw-overhead", "throw-chest"], why: "A few crisp throws wake up the nervous system with no leg cost.")
        pickGroup(.primaryStrength, upperGroups(decision.upperPattern), why: "Light upper-body strength: maintained, never tiring.")
        pickGroup(.accessory, ["anti-rotation", "anti-extension"], role: "trunk", why: "Trunk control, low effort.")
    }

    mutating func conditioningSession() {
        prep(count: 3, upperFocus: false, fast: decision.conditioning == .repeatedSprint)
        conditioningBlock()
        pickGroup(.cooldown, ["mobility-hip", "mobility-hamstring"], role: "mobility", why: "Easy range after running.")
        pickGroup(.cooldown, ["breathing"], why: "Slow breathing brings the heart rate down.")
    }

    mutating func recovery() {
        conditioningBlock()
        pickGroup(.mobility, ["soft-tissue", "mobility-spine"], why: "Easy movement helps you feel fresher — it isn't training.")
        pickGroup(.mobility, ["mobility-hip"], role: "mobility", why: "Keeps the hips moving after a hard day.")
        pickGroup(.mobility, ["mobility-thoracic", "mobility-hamstring"], why: "Loosens the upper back and hamstrings.")
        pickGroup(.cooldown, ["breathing"], why: "Slow breathing switches your body into recovery mode.")
    }

    mutating func mobility(_ purpose: MobilityPurpose) {
        switch purpose {
        case .preTraining:
            prep(count: 4, upperFocus: loadAreas.contains { ["shoulder", "shoulders", "elbow", "upper-back"].contains($0) }, fast: true)
            pickGroup(.prep, ["sprint-mechanics"], why: "Quick feet before you go.")
        case .targeted:
            for area in loadAreas.prefix(2) {
                let group = ["hamstrings": "mobility-hamstring", "hips": "mobility-hip", "hip-flexors": "mobility-hip", "groin": "mobility-hip",
                             "ankles": "mobility-ankle", "shoulder": "mobility-shoulder", "shoulders": "mobility-shoulder",
                             "upper-back": "mobility-thoracic", "lower-back": "mobility-spine"][area] ?? "mobility-hip"
                pickGroup(.mobility, [group, "mobility-hip"], why: "Range for your \(area.replacingOccurrences(of: "-", with: " ")), which your sport loads.")
            }
            pickGroup(.mobility, ["mobility-flow"], why: "Moves everything once.")
            pickGroup(.mobility, ["mobility-thoracic"], why: "Upper-back rotation for throwing, swinging and breathing.")
            pickGroup(.mobility, ["mobility-ankle", "mobility-hip"], why: "Ankle and hip range for squatting and landing.")
        case .recovery:
            pickGroup(.mobility, ["soft-tissue", "mobility-spine"], why: "Easy movement to feel fresher.")
            pickGroup(.mobility, ["mobility-hip"], role: "mobility", why: "Gentle hip range.")
            pickGroup(.mobility, ["mobility-thoracic"], why: "Opens the upper back.")
            pickGroup(.cooldown, ["breathing"], why: "Slow breathing switches your body into recovery mode.")
        case .eveningDownshift:
            pickGroup(.mobility, ["mobility-spine"], why: "Moves the spine gently after a day of sitting and training.")
            pickGroup(.mobility, ["mobility-thoracic"], why: "Opens the chest and upper back.")
            pickGroup(.mobility, ["mobility-hip"], role: "mobility", why: "A long, easy hold for the hips.")
            pickGroup(.cooldown, ["breathing"], why: "Slow breathing before bed helps you fall asleep.")
        }
    }

    mutating func travel() {
        pickGroup(.prep, ["mobility-flow"], why: "Loosens up after sitting in a car, bus or plane.")
        skillBlock(why: "A drill of your sport you can do anywhere.")
        pickGroup(.primaryStrength, ["single-leg-knee", "squat-bilateral"], why: "Leg strength with no equipment.")
        pickGroup(.primaryStrength, ["push-horizontal"], why: "Push-ups: upper-body strength anywhere.")
        pickGroup(.secondaryStrength, ["hinge-hip-extension", "single-leg-hip"], why: "Glutes and hamstrings, no weights needed.")
        pickGroup(.accessory, ["anti-extension", "anti-lateral"], role: "trunk", why: "Trunk strength on the floor of a hotel room.")
        balancePulling()
    }

    // MARK: Dosing

    func dose(_ item: CatalogueItem, block: SessionBlock) -> (Dose, Int, String?) {
        let youth = day.age < 18
        var dose = item.defaultDose
        let inSeason = day.phase == .inSeason || day.phase == .postSeason
        let easier = day.readiness == .belowNormal || day.illnessReturnDay != nil
        let profile = item.planProfile
        let quality = profile.trains
        var rest = 60
        var effort: String?
        switch block {
        case .prep, .mobility, .cooldown:
            dose.sets = dose.kind == "distance" ? 2 : 1
            if dose.kind == "reps" { dose.reps = min(dose.reps ?? 8, 10) }
            if dose.kind == "time" { dose.seconds = min(dose.seconds ?? 30, block == .prep ? 30 : 60) }
            if block == .mobility, decision.mobilityPurpose != .preTraining { dose.sets = min(item.defaultDose.sets, 2) }
            rest = block == .prep ? 10 : 15
        case .power:
            // Fast work is dosed by quality (docs/TRAINING-RESEARCH.md §3): few
            // reps at full intent, rest long enough that every rep stays fast.
            dose.sets = decision.sessionType == .primer ? 2 : (inSeason ? 3 : 4)
            if stage == .foundation { dose.sets = min(dose.sets, 3) }
            switch quality {
            case .strengthSpeed:
                if dose.kind == "reps" { dose.reps = min(dose.reps ?? 3, 3) }
                rest = 120
                effort = "Moderate weight, as fast as you can — stop the set if the bar slows."
            case .reactive:
                if dose.kind == plyometricDoseKind { dose.contacts = min(dose.contacts ?? 5, stage == .performance ? 8 : stage == .foundation ? 5 : 6) }
                if dose.kind == "reps" { dose.reps = min(dose.reps ?? 5, 5) }
                rest = 90
                effort = "Quick, stiff contacts — off the ground fast."
            case .acceleration, .maxVelocity, .changeOfDirection:
                if dose.kind == "reps" { dose.reps = min(dose.reps ?? 4, 4) }
                if dose.kind == "distance" { dose.metres = min(dose.metres ?? 20, quality == .maxVelocity ? 30 : 20) }
                rest = quality == .maxVelocity ? 150 : 120
                effort = "All-out with full rest — stop when you start to slow down."
            case .deceleration:
                if dose.kind == "reps" { dose.reps = min(dose.reps ?? 4, 5) }
                if dose.kind == plyometricDoseKind { dose.contacts = min(dose.contacts ?? 5, 5) }
                rest = 60
                effort = "Stick every landing for two seconds: quiet feet, knees over toes."
            default:
                if dose.kind == "reps" { dose.reps = min(dose.reps ?? 5, 5) }
                if dose.kind == plyometricDoseKind { dose.contacts = min(dose.contacts ?? 5, 6) }
                if dose.kind == "distance" { dose.metres = min(dose.metres ?? 20, 20) }
                rest = profile.pattern == "throw" ? 75 : 90
                effort = "Every rep at full intent — quality, not fatigue."
            }
        case .skill:
            // A drill of the athlete's own sport: its own dose, a little less in season.
            dose.sets = min(max(1, item.defaultDose.sets), inSeason || easier ? 2 : 3)
            rest = 45
        case .primaryStrength:
            switch day.experience {
            case .beginner: dose.sets = 3; dose.reps = 10; rest = 90
            case .intermediate: dose.sets = 3; dose.reps = 8; rest = 120
            case .experienced: dose.sets = youth ? 3 : 4; dose.reps = youth ? 6 : 5; rest = 150
            }
            if decision.sessionType == .afterPractice || decision.sessionType == .primer || decision.sessionType == .travel { dose.sets = 2; rest = min(rest, 90) }
            if inSeason || easier { dose.sets = max(2, dose.sets - 1) }
            // In season: fewer sets, but the reps stay heavy (Rønnestad 2011).
            if inSeason, day.experience != .beginner, quality == .maxStrength, let reps = dose.reps, dose.kind == "reps",
               !(item.defaultDose.load?.hasPrefix("bodyweight") ?? false) {
                dose.reps = max(youth ? 6 : 4, reps - 2)
            }
            effort = strengthEffort(primary: true, easier: easier)
            if item.planProfile.isLower, decision.avoids(.highVolumeLowerBody) { dose.sets = 2 }
            if dose.kind != "reps" { dose.reps = item.defaultDose.reps }
            // Bodyweight lifts: their own (higher) reps — 2 × 8 air squats isn't main strength.
            if item.defaultDose.load?.hasPrefix("bodyweight") ?? false, let own = item.defaultDose.reps {
                dose.reps = max(dose.reps ?? own, own)
            }
        case .secondaryStrength:
            dose.sets = day.experience == .beginner || inSeason || easier || decision.sessionType == .afterPractice ? 2 : 3
            if dose.kind == "reps" { dose.reps = day.experience == .experienced ? 8 : 10 }
            rest = 90
            effort = strengthEffort(primary: false, easier: easier)
        case .accessory:
            dose.sets = day.experience == .experienced && !inSeason ? 3 : 2
            if dose.kind == "reps" { dose.reps = min(max(dose.reps ?? 10, 8), 15) }
            rest = item.planProfile.role == "trunk" ? 40 : 45
            switch quality {
            case .injuryPrevention where profile.group == "hamstring-eccentric" || profile.group == "knee-eccentric":
                // Eccentric work: few, slow, high-quality reps (in season a small dose keeps the effect).
                if dose.kind == "reps" { dose.reps = min(item.defaultDose.reps ?? 6, 6) }
                dose.sets = inSeason || stage == .foundation ? 2 : 3
                rest = 90
                effort = "Lower as slowly as you can; it's fine to fall the last bit."
            case .injuryPrevention: effort = "Slow and controlled — small doses, every week."
            case .stability: effort = "Hold the position; stop when it starts to shake or sag."
            case .deceleration: effort = "Stick every landing for two seconds."
            default: break
            }
        case .conditioning:
            if let rx = conditioning {
                dose = Dose(kind: "time", sets: rx.reps, seconds: rx.workSeconds)
                rest = rx.restSeconds
                let first: String = String(rx.intensity.prefix(1)).uppercased()
                effort = first + String(rx.intensity.dropFirst()) + "."
            }
        }
        if let extra = extraSets[block] { dose.sets = max(1, min(dose.sets + extra, youth ? 3 : 4)) }
        if youth, dose.kind == "reps" {
            dose.sets = min(max(dose.sets, 1), 3)
            if let reps = dose.reps { dose.reps = min(max(reps, block == .prep || block == .power ? 1 : 6), 15) }
        }
        // Taper before a tournament or meet: half the sets, the same weights
        // and reps (Bosquet 2007; Part 2, A9). Last, so filling time can't undo it.
        if day.tapering, [.primaryStrength, .secondaryStrength, .accessory, .power].contains(block), dose.sets > 1 {
            dose.sets = (dose.sets + 1) / 2
            if dose.kind == plyometricDoseKind, let contacts = dose.contacts { dose.contacts = max(3, contacts / 2) }
        }
        return (dose, rest, effort)
    }

    /// How hard a strength set should feel: reps left in the tank (RIR,
    /// Helms et al. 2016) by stage and today's check-in. Never to failure; no
    /// maximum testing — the effort is felt, not a percentage of a max.
    func strengthEffort(primary: Bool, easier: Bool) -> String {
        if easier { return "Easier today: stop each set with 3–4 reps left." }
        switch stage {
        case .foundation: return "Light enough for perfect form — stop with 3–4 reps left."
        case .development: return "Stop each set with 2–3 good reps left."
        case .performance: return primary && day.age >= 18 ? "Hard: stop with 1–2 reps left." : "Stop each set with 2 good reps left."
        }
    }

    // MARK: Fitting the time

    /// Inside the fast block: landing skill, then sprints, then the reactive
    /// work, then jumps and throws — the most neurally demanding first.
    static func fastRank(_ profile: ExerciseProfile) -> Int {
        switch profile.trains {
        case .deceleration: 0
        case .acceleration, .maxVelocity, .changeOfDirection: 1
        case .reactive: 2
        case .strengthSpeed: 3
        default: profile.pattern == "throw" ? 5 : 4
        }
    }

    func planned() -> [GeneratedPlannedItem] {
        let order: [SessionBlock] = SessionBlock.allCases
        let sorted = picks.enumerated().sorted { lhs, rhs in
            let l = order.firstIndex(of: lhs.element.block) ?? 0, r = order.firstIndex(of: rhs.element.block) ?? 0
            if l != r { return l < r }
            if lhs.element.block == .power {
                let a = Self.fastRank(lhs.element.item.planProfile), b = Self.fastRank(rhs.element.item.planProfile)
                if a != b { return a < b }
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
        return sorted.enumerated().map { index, pick in
            let (dose, rest, effort) = dose(pick.item, block: pick.block)
            var item = GeneratedPlannedItem(itemSlug: pick.item.slug, order: index, dose: dose, restSec: rest, rationale: pick.why, quality: pick.quality)
            item.block = pick.block
            item.effort = effort
            return item
        }
    }

    func minutes(_ items: [GeneratedPlannedItem]) -> Int {
        let seconds = items.reduce(0) { total, item in
            item.block == .conditioning ? total + (conditioning?.minutes ?? 10) * 60 : total + SessionBuilder.seconds(item)
        }
        return Int((Double(seconds) / 60).rounded())
    }

    /// Trims to the target (drop the least important first), or — when
    /// there's lots of room — adds an accessory.
    mutating func fit() {
        let target = decision.durationTarget
        var guardCount = 0
        var trimmedHard = false
        while minutes(planned()) > target + 4, guardCount < 16 {
            guardCount += 1
            if let i = picks.lastIndex(where: { $0.block == .cooldown }), picks.filter({ $0.block == .cooldown }).count > 1 { picks.remove(at: i); continue }
            if picks.filter({ $0.block == .accessory }).count > 2, let i = picks.lastIndex(where: { $0.block == .accessory }) { picks.remove(at: i); continue }
            if picks.filter({ $0.block == .power }).count > 1, let i = picks.lastIndex(where: { $0.block == .power }) { picks.remove(at: i); continue }
            if picks.filter({ $0.block == .prep }).count > 3, let i = picks.lastIndex(where: { $0.block == .prep }) { picks.remove(at: i); continue }
            if picks.filter({ $0.block == .secondaryStrength }).count > 1, let i = picks.lastIndex(where: { $0.block == .secondaryStrength }) { picks.remove(at: i); continue }
            if picks.filter({ $0.block == .accessory }).count > 1, let i = picks.lastIndex(where: { $0.block == .accessory }) { picks.remove(at: i); continue }
            // Still too long for the time there is (a 20-minute day): fewer
            // sets first, then the smaller strength work, then the fast work.
            if extraSets[.secondaryStrength, default: 0] > -1, picks.contains(where: { $0.block == .secondaryStrength }) { extraSets[.secondaryStrength] = -1; trimmedHard = true; continue }
            if extraSets[.primaryStrength, default: 0] > -1, picks.contains(where: { $0.block == .primaryStrength }) { extraSets[.primaryStrength] = -1; trimmedHard = true; continue }
            if let i = picks.lastIndex(where: { $0.block == .secondaryStrength }) { picks.remove(at: i); trimmedHard = true; continue }
            if let i = picks.lastIndex(where: { $0.block == .power }) { picks.remove(at: i); trimmedHard = true; continue }
            if picks.filter({ $0.block == .prep }).count > 2, let i = picks.lastIndex(where: { $0.block == .prep }) { picks.remove(at: i); trimmedHard = true; continue }
            if let i = picks.lastIndex(where: { $0.block == .accessory }) { picks.remove(at: i); trimmedHard = true; continue }
            break
        }
        // Trimmed to fit: never grown back past the time.
        if trimmedHard { return }
        grow()
    }

    /// Fills a session that came out well short of its target with the
    /// next most useful thing for that kind of session — never filler.
    mutating func grow() {
        let target = decision.durationTarget
        func short(_ margin: Int) -> Bool { minutes(planned()) < target - margin }
        switch decision.sessionType {
        case .gymDevelopment where decision.gymFocus != nil:
            // The athlete's own focus: more good sets of the anchors, then one
            // more accessory of the same focus — never another body part.
            if short(8) { extraSets[.primaryStrength] = 1 }
            if short(8) { extraSets[.secondaryStrength] = 1 }
            if short(8), let focus = decision.gymFocus {
                for groups in GymSlots.accessories(focus) where short(8) {
                    pickAccessory(groups, avoid: day.gym?.lastAccessories ?? [], why: accessoryWhy(groups.first ?? ""))
                }
            }
            if short(5) { pickGroup(.cooldown, ["mobility-hip", "mobility-thoracic"], role: "mobility", why: "A couple of minutes of easy range to finish.") }
        case .gymDevelopment:
            // More good sets of the main work first, then more exercises.
            if short(8) { extraSets[.primaryStrength] = 1 }
            if short(8) { extraSets[.secondaryStrength] = 1 }
            if short(10), !decision.avoids(.highVolumeLowerBody), decision.legBudget >= 2,
               !picks.contains(where: { $0.block == .secondaryStrength && $0.item.planProfile.isLower }) {
                pickGroup(.secondaryStrength, ["single-leg-knee", "single-leg-hip", "single-leg-lateral"], why: "One leg at a time — how you actually run, cut and land.")
            }
            if short(8) { pickGroup(.accessory, ["carry", "hamstring-eccentric", "shoulder-health", "calf-ankle"], why: "Extra resilience work while there's time.") }
            if short(5) { pickGroup(.cooldown, ["mobility-hip", "mobility-thoracic"], role: "mobility", why: "A couple of minutes of easy range to finish.") }
        case .afterPractice:
            if short(6) { pickGroup(.accessory, ["shoulder-health", "grip", "neck"], why: "Small shoulder work that keeps throwing, tackling and falling safe.") }
            if short(6), decision.legBudget >= 1 { pickGroup(.accessory, ["hamstring-eccentric", "calf-ankle"], why: "Low-volume work that protects hamstrings and ankles.") }
            if short(6) { pickGroup(.accessory, ["anti-lateral", "anti-extension", "carry"], role: "trunk", why: "A second trunk exercise from a different direction.") }
            if short(4) { pickGroup(.cooldown, ["mobility-hip", "mobility-thoracic", "breathing"], why: "Easy range and slow breathing to start recovering.") }
            if short(4) { pickGroup(.cooldown, ["breathing", "mobility-spine"], why: "Slow breathing switches your body into recovery mode.") }
        case .primer:
            if short(6) { pickGroup(.cooldown, ["mobility-hip", "mobility-flow"], why: "Easy range to finish, nothing tiring.") }
        case .mobility where decision.mobilityPurpose != .preTraining:
            var guardCount = 0
            while short(3), guardCount < 2 {
                guardCount += 1
                let groups = decision.mobilityPurpose == .preTraining ? ["hip-activation", "sprint-mechanics", "mobility-ankle"]
                    : ["mobility-hamstring", "mobility-ankle", "mobility-shoulder", "mobility-hip", "mobility-spine"]
                if !pickGroup(.mobility, groups, why: "More easy range for the areas your sport loads.") { break }
            }
        default:
            break
        }
    }

    // MARK: Output

    func session() -> GeneratedSession {
        let items = planned()
        let title: String
        switch decision.sessionType {
        case .mobility: title = decision.mobilityPurpose?.title ?? "Mobility"
        case .conditioning: title = decision.conditioning?.title ?? "Conditioning"
        case .gymDevelopment where decision.gymFocus != nil:
            let focus = decision.gymFocus ?? .full
            title = focus == .lower && decision.legBudget < 2 ? "Legs, kept light" : focus.title
        case .gymDevelopment:
            let focus = decision.primaryTargets.first.map { $0 == .strength ? "Strength" : $0 == .upperStrength ? "Upper-body strength" : $0.title.capitalized } ?? "Development"
            title = "\(focus) day"
        default: title = decision.sessionType.title
        }
        var session = GeneratedSession(date: day.date, title: title, focusQualities: decision.primaryTargets.map(\.rawValue),
                                       estimatedMinutes: decision.sessionType == .rest ? 0 : max(5, minutes(items)), items: items)
        // What the builder itself decided joins the decision's reasons.
        var built = decision
        // Only what survived the time fit.
        let groups = Set(items.compactMap { kit.catalogue.item($0.itemSlug)?.planProfile.group })
        var extra = addedReasons.filter { reason in
            switch reason {
            case .sportInjuryRisk: return risks.contains { !groups.isDisjoint(with: $0.groups) }
            case .pullBalancesPush: return items.contains { $0.rationale.hasPrefix("More pulling than pressing") }
            default: return true
            }
        }
        if landingsLimited { extra.append(.landingsCapped) }
        for reason in extra where !built.reasons.contains(reason) { built.reasons.append(reason) }
        session.decision = built
        session.explanation = PlanExplanation.make(decision: built, day: day, items: items, catalogue: kit.catalogue, conditioning: conditioning)
        return session
    }
}
