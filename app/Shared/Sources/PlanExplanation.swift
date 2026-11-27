import Foundation

/// "Why this plan?" (docs/VERSION-6.md §9): the decision in plain words. It
/// only explains what SessionPlanner decided — it never decides anything.
/// Copy style (§22): a calm performance coach. Simple, precise.
public struct PlanExplanation: Sendable, Equatable, Codable {
    public struct Part: Sendable, Equatable, Codable {
        public var question: String
        public var answer: String
    }

    /// One or two sentences shown on the workout.
    public var summary: String
    /// The ten questions, answered (§9), for "More about this plan".
    public var parts: [Part]

    public static func make(decision: SessionDecision, day: TrainingDay, items: [GeneratedPlannedItem], catalogue: Catalogue,
                            conditioning: ConditioningPrescription?) -> PlanExplanation {
        let r = Set(decision.reasons)
        let targets = list(decision.primaryTargets.map(\.title))
        var parts: [Part] = []
        func add(_ q: String, _ a: String?) { if let a, !a.isEmpty { parts.append(Part(question: q, answer: a)) } }

        // What practice already did.
        var practiceCovered: String?
        if let practice = day.practice {
            var gave: [String] = []
            if day.demands.practiceLegLoad >= 2 || practice == .hard { gave.append(practice == .hard ? "substantial lower-body" : "lower-body") }
            if day.demands.practiceConditioning >= 2 { gave.append("conditioning") }
            practiceCovered = gave.isEmpty ? "Practice trained your sport skills today." : "Practice already gave you \(list(gave)) load today."
        }

        // Summary.
        var summary: String
        switch decision.sessionType {
        case .afterPractice:
            summary = (practiceCovered ?? "You trained with the team today.") + " "
            if r.contains(.strengthAfterPractice) {
                summary += "This week has no free day away from your games, so your strength session comes after practice: \(targets), longer than the usual add-on, with few leg sets so you still recover."
            } else if r.contains(.weeklyHeavyLegs) {
                summary += "Your legs haven't lifted for a week, so this short session adds one heavy leg lift with few sets: enough to keep your strength, not enough to slow your recovery."
            } else {
                summary += decision.legBudget >= 2
                    ? "This short session adds \(targets) with only a little leg work, so you still recover."
                    : "This short session focuses on \(targets) without adding unnecessary leg fatigue."
            }
            if r.contains(.choseGym) { summary += " You said gym too: after a full practice, this is the gym part — more would only add fatigue." }
        case .gymDevelopment:
            summary = r.contains(.choseGym)
                ? (day.practice != nil ? "You said gym after a short, easy practice, so this is a full development session: \(targets)."
                    : "You said gym today, so this is your main development session: \(targets).")
                : day.practice != nil ? "After practice, this is your development session: \(targets)."
                : "No practice today, so this is your main development session: \(targets)."
            if r.contains(.gameYesterday) { summary += " You played yesterday, so the legs get less and the upper body more." }
            else if r.contains(.gameWithin48h) { summary += " Leg volume is lower because you compete in two days." }
            else if r.contains(.lowerBodyTrainedRecently) { summary += " Your legs worked hard recently, so lower-body lifting is lighter." }
            else if r.contains(.belowNormalReadiness) { summary += " Your check-in was below your normal, so there's less volume today." }
            else if r.contains(.returnAfterIllness) { summary += " You're coming back from being sick, so it's lighter than usual." }
            else if r.contains(.inSeason) { summary += " In season the aim is to keep strength, so sets are lower." }
            // The athlete's own gym session: its focus and why, first.
            if let focus = decision.gymFocus {
                let note = decision.gymNote ?? "\(focus.title) today, your choice."
                summary = note + " The anchor lifts stay the same for four weeks so you can see them go up; the rest changes every session."
                    + (decision.conditioning != nil && decision.conditioningMinutes > 0 ? " It ends with \(decision.conditioningMinutes) minutes of conditioning on a bike or rower." : "")
            }
        case .primer:
            summary = r.contains(.choseGym)
                ? "You said gym, and you compete tomorrow — so it's a short, sharp session instead of a full one. You'll feel quick, not tired."
                : "You compete tomorrow. A short, sharp session keeps you feeling quick without adding fatigue."
        case .conditioning:
            summary = "Your sport isn't giving you enough \((decision.conditioning ?? .aerobicBase).title.lowercased()) right now, so this is a programmed conditioning session."
        case .recovery:
            if r.contains(.gameYesterday) { summary = "You played yesterday. Today is easy movement — recovery is part of the plan." }
            else if r.contains(.reflectionSomethingHurt) { summary = "You said something hurt last night, so today is gentle movement only. If it still hurts, tell a coach or athletic trainer." }
            else if r.contains(.lowReadiness) { summary = "Your check-in says you're well below your normal. Easy movement today is the right call." }
            else if r.contains(.manyDaysInARow) { summary = "You've trained many days in a row. Today is easy, so the hard days keep working." }
            else if r.contains(.returnAfterIllness) { summary = "You're just back from being sick. Easy movement first; training builds back up over the next days." }
            else { summary = "Today is easy movement. Recovery is part of the plan." }
            if r.contains(.choseGymMadeLighter) { summary = "You said gym, but your body needs an easy day first. " + summary }
        case .mobility:
            switch decision.mobilityPurpose ?? .targeted {
            case .preTraining: summary = r.contains(.gameToday) ? "Game day: a short movement prep, then save everything for the game." : "Movement prep: raise your temperature and get the joints moving before you train."
            case .targeted: summary = "Range for the areas your sport loads most."
            case .recovery: summary = practiceCovered.map { "\($0) Easy movement now helps you feel fresher tomorrow." } ?? "Easy movement to feel fresher. It isn't training."
            case .eveningDownshift: summary = "A calm few minutes before bed: slower movement and slower breathing."
            }
            if r.contains(.choseLight) { summary = "You said something light today. " + summary }
            else if r.contains(.choseGymMadeLighter) { summary = (r.contains(.gameToday) ? "You said gym, but the game is today's training. " : "You said gym, but your body needs an easy day first. ") + summary }
        case .travel:
            summary = "Away from home: strength with no equipment, so the week stays on track."
        case .rest:
            if r.contains(.choseRest) { summary = "You chose a rest day. Rest is part of the plan — it never costs you anything."; break }
            summary = r.contains(.manyDaysInARow) ? "You've trained many days in a row. Rest today is part of the plan."
                : r.contains(.gameTomorrow) ? "You compete tomorrow. Resting today is the best preparation."
                : "Rest is part of the plan today. Doing nothing is the right thing to do."
        }

        // What the athlete told AthleteOS (tired legs, sprint-heavy practice,
        // equipment, time): the first thing it changed goes in the summary.
        let told = contextLines(r, day: day, decision: decision)
        if let first = told.first, decision.sessionType != .rest { summary += " " + first }
        if told.count > 1 { add("What did you tell AthleteOS?", told.joined(separator: " ")) }

        // 1. Why train today?
        // What the athlete told AthleteOS about today: their word wins over the schedule.
        let said = DayChoice.order.filter { day.said.contains($0) && $0 != .auto }
        if !said.isEmpty {
            var answer = "You said: \(list(said.map(\.shortTitle))) today. Your word wins over the schedule."
            if r.contains(.choseGymMadeLighter) { answer += " Safety still comes first, so the session is lighter than a full gym day." }
            add("What did you tell AthleteOS?", answer)
        }
        let whyToday: String
        if decision.sessionType == .rest {
            whyToday = r.contains(.choseRest) ? "You chose a rest day: fitness is built in the recovery between sessions."
                : "Today is a planned rest day: fitness is built in the recovery between sessions."
        } else if decision.sessionType == .recovery {
            whyToday = "Easy movement helps you recover faster than lying still. It isn't meant to make you tired."
        } else if r.contains(.choseLight) {
            whyToday = "You asked for something light. Easy movement keeps you loose without adding fatigue."
        } else if r.contains(.choseGym) && decision.sessionType == .gymDevelopment {
            whyToday = "You chose the gym today — a good day to build strength and power."
        } else if day.practice != nil {
            whyToday = "Practice trains your sport. A short supplement fills what practice doesn't train."
        } else {
            whyToday = "There's no practice today, which makes it the best day for development work."
        }
        add("Why train today?", whyToday)
        // 2. Why this session type?
        if !day.painAreas.isEmpty {
            let areas = day.painAreas.map { $0.title.lowercased() }.sorted().joined(separator: ", ")
            add("What about the pain?", "Nothing today loads your \(areas). Train around it, not through it — if it's sharp, swelling or getting worse, stop and get it checked.")
        }
        add("Why this kind of session?", sessionTypeReason(decision, r))
        // 3. Why this duration?
        add("Why this long?", durationReason(decision, day, r))
        // 4. Why these qualities?
        if !decision.primaryTargets.isEmpty {
            var answer = "Main focus: \(targets)."
            if !decision.maintain.isEmpty { answer += " Kept up with less volume: \(list(decision.maintain.map(\.title)))." }
            add("Why these qualities?", answer)
        }
        // What it builds: qualities and the muscles that do the work.
        add("What does it build?", builds(items, catalogue: catalogue))
        // How hard: by training stage and today's check-in (reps in reserve, never failure).
        if [.gymDevelopment, .afterPractice, .travel, .primer].contains(decision.sessionType) {
            add("How hard should it feel?", effort(decision, day, r))
        }
        // 5. Why these exercises?
        let byBlock = Dictionary(grouping: items.filter { $0.block != nil }, by: { $0.block! })
        let exercises = SessionBlock.allCases.compactMap { block -> String? in
            guard let picked = byBlock[block], let first = picked.first else { return nil }
            let names = picked.compactMap { catalogue.item($0.itemSlug)?.name }
            return "\(block.title) — \(list(names)): \(first.rationale)"
        }
        add("Why these exercises?", exercises.joined(separator: "\n"))
        // 6. Why this order?
        // Told from the blocks actually built (a recovery day has no "heaviest strength work").
        let blocks = Set(items.compactMap(\.block))
        var order: [String] = []
        if blocks.contains(.power) { order.append("fast and explosive work first, while you're fresh") }
        if blocks.contains(.skill) { order.append("your sport's drill while you're still sharp") }
        if blocks.contains(.primaryStrength) { order.append("then the heaviest strength work") }
        if blocks.contains(.secondaryStrength) || blocks.contains(.accessory) { order.append("then smaller exercises") }
        if blocks.contains(.conditioning) { order.append(blocks.contains(.primaryStrength) ? "and conditioning last so it doesn't blunt the strength work" : "then the conditioning") }
        if order.count >= 2 {
            let text = order.joined(separator: ", ")
            add("Why this order?", text.prefix(1).uppercased() + text.dropFirst() + ".")
        }
        // 7. What did practice already train?
        add("What did practice already train?", practiceCovered)
        // 8. What are we avoiding?
        if !decision.avoidToday.isEmpty {
            add("What are we avoiding today?", "Not today: \(list(decision.avoidToday.map(\.phrase))). Good exercise, wrong day.")
        }
        // 9. How does it fit your goals?
        if !day.goals.isEmpty {
            let hits = day.goals.filter { decision.primaryTargets.contains($0) || decision.maintain.contains($0) }
            add("How does it fit your goals?", hits.isEmpty
                ? "Your goal of \(day.goals[0].title) gets its turn on another day this week — today's job is different."
                : "It trains \(list(hits.map(\.title))), which you chose as a development goal.")
        }
        // What the twin knows about this athlete that changed today.
        var twin: [String] = []
        if r.contains(.twinSlowGameRecovery) { twin.append("you usually still feel a game two days later, so today stays light on the legs") }
        if r.contains(.twinLoadSpike) { twin.append("your training load jumped this week, so there's a little less volume and no hard conditioning") }
        if r.contains(.twinSpeedFocus) { twin.append("your strength is rising faster than your speed, so power and acceleration come first") }
        if !twin.isEmpty {
            let text = twin.joined(separator: "; ")
            add("What does your twin change?", "From your own data: " + text + ".")
        }
        // The evidence-based rules that shaped this session.
        var behind: [String] = []
        if r.contains(.inSeasonKeepIntensity) { behind.append("In season the sets go down but the weight stays honest: one strength session a week is enough to keep what you built.") }
        if r.contains(.strengthBeforeCardio) { behind.append("Lifting first, conditioning after — on a bike or rower where possible, because running straight after leg work gets in the way of strength more than cycling.") }
        if r.contains(.sportInjuryRisk) { behind.append("Your sport has a well-known injury risk, and this session includes the exercise that measurably lowers it.") }
        if r.contains(.pullBalancesPush) { behind.append("A little more pulling than pressing keeps the shoulders healthy.") }
        if r.contains(.taper) { behind.append("A tournament or meet is coming: half the sets at the same weights, so you arrive strong and fresh.") }
        if r.contains(.jumpsYesterday) { behind.append("You jumped yesterday. Today's fast work is throws, because legs need about 48 hours between jump sessions.") }
        if r.contains(.landingsCapped) { behind.append("Jumps are capped at what you're ready to land in one session; more come as your training age grows.") }
        if !behind.isEmpty { add("What's behind it?", behind.joined(separator: " ")) }
        // 10. How does it progress?
        add("How does this build on last time?", progression(decision, day))
        if let conditioning {
            add("Conditioning", "\(conditioning.type.title): \(conditioning.summary).")
        }
        return PlanExplanation(summary: summary, parts: parts)
    }

    /// What the athlete told AthleteOS, as it changed today — one calm sentence each.
    public static func contextLines(_ r: Set<PlanReason>, day: TrainingDay, decision: SessionDecision) -> [String] {
        var lines: [String] = []
        let named = day.context.fatigueRegions.filter { $0.gymRegions.contains(.lower) || $0 == .wholeBody }
        let regions = named.isEmpty ? "your legs" : list(named.map(\.phrase))
        let are = named.count == 1 && [.wholeBody, .core, .back, .chest, .upperBody].contains(named[0]) ? "is" : "are"
        let sprint = r.contains(.recentHighSprintExposure)
        if r.contains(.highLowerBodyFatigue) {
            lines.append(sprint
                ? "Practice gave you a lot of sprinting, and you said \(regions) \(are) still very tired. Today stays away from hard leg work, jumps and sprints."
                : "You said \(regions) \(are) still very tired, so today stays away from hard leg work, jumps and sprints.")
        } else if r.contains(.lowerBodyFatigue) {
            lines.append(sprint
                ? "Practice gave you a lot of sprinting, and \(regions) \(are) still a bit tired, so leg work is lighter and there's no sprinting."
                : "You said \(regions) \(are) a bit tired, so leg work is lighter today.")
        } else if sprint {
            lines.append("Practice already gave you a lot of sprinting, so there's no sprinting or hard conditioning here.")
        }
        if r.contains(.highUpperBodyFatigue) { lines.append("You said your upper body is tired, so no heavy pressing or pulling today.") }
        if r.contains(.practiceCoveredConditioning), !sprint { lines.append("Practice already covered the conditioning, so none is added.") }
        if r.contains(.availableTimeToday) {
            lines.append("You said you have \(day.context.minutes ?? decision.durationTarget) minutes, so the session is built for that time: the most important work first, the rest left out.")
        }
        if r.contains(.limitedEquipment) { lines.append("You told AthleteOS what equipment you have these days, so every exercise uses only that.") }
        return lines
    }

    /// "Power, single-leg strength and trunk control — mostly glutes, quads and hamstrings."
    static func builds(_ items: [GeneratedPlannedItem], catalogue: Catalogue) -> String? {
        let qualities = SessionTrains.builds(items, catalogue: catalogue)
        guard !qualities.isEmpty else { return nil }
        let text = list(qualities)
        var answer = text.prefix(1).uppercased() + String(text.dropFirst())
        let groups = SessionTrains.sets(items.filter { ![.prep, .cooldown].contains($0.block) }, catalogue: catalogue)
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.order < $1.key.order }
            .prefix(3).map(\.key.name)
        if !groups.isEmpty { answer += " — most of the work for your \(list(Array(groups)))" }
        return answer + "."
    }

    static func effort(_ d: SessionDecision, _ day: TrainingDay, _ r: Set<PlanReason>) -> String {
        var text: String
        switch d.stage ?? day.stage {
        case .foundation:
            text = "You're building the base: perfect form, 3–4 reps left in every set, and many different movements. Athletes who reach the top usually learned to move in lots of ways first."
        case .development:
            text = "Stop each set with 2–3 good reps left. Strength comes first; power is built on top of it."
        case .performance:
            text = "You have the training age for more specific power and speed work. Fast work at full intent with full rest; strength sets stop 1–2 reps short — never to failure, and no max testing."
        }
        if r.contains(.belowNormalReadiness) || r.contains(.returnAfterIllness) {
            text += " Today one notch easier: leave an extra rep or two in the tank."
        }
        return text
    }

    static func sessionTypeReason(_ d: SessionDecision, _ r: Set<PlanReason>) -> String {
        switch d.sessionType {
        case .afterPractice: return "After practice your legs and lungs have worked. Upper-body strength, trunk and small injury-prevention work are what's missing."
        case .gymDevelopment: return "A day without practice or a game coming up: the time to build strength and power."
        case .primer: return "The day before competition: short, fast and light, so you feel sharp — not tired."
        case .conditioning: return r.contains(.sportProvidesConditioning) ? "Practice gives some conditioning, but not the kind your sport needs most." : "Your sport's practice doesn't build the fitness you need, so it's programmed here."
        case .recovery: return "Hard days only work if easy days are really easy."
        case .mobility: return "Mobility with a purpose: \((d.mobilityPurpose ?? .targeted).title.lowercased())."
        case .travel: return "No gym on the road, so bodyweight strength keeps the habit."
        case .rest: return "Rest is when the body adapts to the training."
        }
    }

    static func durationReason(_ d: SessionDecision, _ day: TrainingDay, _ r: Set<PlanReason>) -> String {
        guard d.durationTarget > 0 else { return "No session today." }
        var why: [String] = []
        switch d.sessionType {
        case .afterPractice: why.append("after practice, 15–35 minutes is enough")
        case .gymDevelopment: why.append("a development day is usually 45–75 minutes")
        default: break
        }
        if r.contains(.inSeason) { why.append("in season it's shorter") }
        if r.contains(.offSeason), d.sessionType == .gymDevelopment { why.append("the off-season has room for more") }
        if r.contains(.beginner) { why.append("you're new to lifting, so less is more") }
        if r.contains(.gameWithin48h) || r.contains(.gameTomorrow) { why.append("competition is close") }
        if r.contains(.belowNormalReadiness) { why.append("your check-in was below normal") }
        if r.contains(.examOrLongDay) { why.append("it's a long school day") }
        if r.contains(.limitedTime) { why.append("you have limited time") }
        if r.contains(.availableTimeToday) { why.append("that's the time you said you have today") }
        return "About \(d.durationTarget) minutes: " + (why.isEmpty ? "the right amount for today" : why.joined(separator: "; ")) + "."
    }

    static func progression(_ d: SessionDecision, _ day: TrainingDay) -> String? {
        guard [.gymDevelopment, .afterPractice].contains(d.sessionType) else { return nil }
        var parts: [String] = []
        if let lower = d.lowerPattern, d.legBudget >= 2 {
            parts.append(day.recent.lastLowerPattern == nil ? "The first \(lower) session of the week."
                : "Last time the main leg exercise was a \(day.recent.lastLowerPattern!); today it's a \(lower), so both get trained each week.")
        }
        if let upper = d.upperPattern {
            parts.append("The main upper-body pattern is \(upper)\(day.recent.lastUpperPattern.map { $0 != upper ? " (last time: \($0))" : "" } ?? "").")
        }
        parts.append("When every set feels smooth, add a little weight or a couple of reps next time.")
        return parts.joined(separator: " ")
    }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }
}

// MARK: - The short "because" (the lock screen, the morning card)

public extension PlanExplanation {
    /// What shaped the day, in at most two short phrases, most important first:
    /// "Game in 2 days · legs tired". Nil when nothing in particular did.
    /// `event` is the athlete's word for a competition ("Game", "Match", "Race").
    /// Reasons about the athlete's body, health or mood: never on a Lock
    /// Screen anyone nearby can read (docs/PLAN-CHANGES-RESEARCH.md P13).
    static let privateReasons: Set<PlanReason> = [
        .reflectionSomethingHurt, .returnAfterIllness, .highLowerBodyFatigue, .lowerBodyFatigue,
        .highUpperBodyFatigue, .lowReadiness, .belowNormalReadiness
    ]

    /// The same short because, without anything private.
    static func lockScreenBecause(_ reasons: [PlanReason], event: String = "Game") -> String? {
        because(reasons.filter { !privateReasons.contains($0) }, event: event)
    }

    static func because(_ reasons: [PlanReason], event: String = "Game") -> String? {
        let r = Set(reasons)
        let ordered: [(PlanReason, String)] = [
            (.gameToday, "\(event) today"),
            (.gameTomorrow, "\(event) tomorrow"),
            (.gameWithin48h, "\(event) in 2 days"),
            (.gameYesterday, "Played yesterday"),
            (.reflectionSomethingHurt, "Something hurt yesterday"),
            (.returnAfterIllness, "Back from being sick"),
            (.taper, "\(event) day close: fewer sets"),
            (.highLowerBodyFatigue, "Legs very tired"),
            (.lowerBodyFatigue, "Legs tired"),
            (.highUpperBodyFatigue, "Upper body tired"),
            (.lowReadiness, "Well below your normal"),
            (.belowNormalReadiness, "A bit below your normal"),
            (.hardTeamPractice, "Hard practice"),
            (.recentHighSprintExposure, "Lots of sprinting lately"),
            (.lowerBodyTrainedRecently, "Legs trained recently"),
            (.jumpsYesterday, "Jumped yesterday"),
            (.practiceCoveredConditioning, "Practice covered conditioning"),
            (.manyDaysInARow, "Many days in a row"),
            (.availableTimeToday, "The time you have"),
            (.limitedTime, "The time you have"),
            (.limitedEquipment, "The kit you have"),
            (.examOrLongDay, "A long school day"),
            (.choseGym, "You chose gym"),
            (.choseLight, "You chose light"),
            (.lightTeamPractice, "Light practice"),
            (.practiceToday, "Practice today"),
            (.strengthAfterPractice, "This week's strength session"),
            (.weeklyHeavyLegs, "A week without heavy legs"),
            (.conditioningGap, "Your sport needs more engine"),
            (.noPracticeToday, "No practice today"),
        ]
        var phrases: [String] = []
        for (reason, phrase) in ordered where r.contains(reason) && !phrases.contains(phrase) {
            phrases.append(phrase)
            if phrases.count == 2 { break }
        }
        return phrases.isEmpty ? nil : phrases.joined(separator: " · ")
    }
}
