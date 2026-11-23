import Foundation

/// "Tell AthleteOS": the athlete writes in their own words — "tournament on
/// Saturday, my knee hurts a bit, exams next week, I want to get faster" —
/// and this reads it and proposes changes to the app (a competition, a pain
/// report, an exam week, a day status, development goals). Rule-based, on
/// the phone, English and German. Nothing changes until the athlete confirms.
public enum TellParser {
    /// What the text asks the app to change. Ids are plain strings so this
    /// file stays Foundation-only (the app maps them to PainArea, Struggle…).
    public enum Proposal: Hashable, Sendable {
        /// A competition on a day (and time, when given).
        case competition(date: Date, kind: CompetitionWord, note: String?, hasTime: Bool)
        /// Pain in these areas (PainArea raw values) at a level ("little", "some", "lot").
        case pain(areas: [String], level: String)
        /// A knock to the head: training pauses until a doctor clears it.
        case headKnock
        /// The week of this date is an exam week.
        case examWeek(Date)
        /// A day status ("sick", "travel", "holiday") from a day, for some days.
        case dayStatus(String, from: Date, days: Int)
        /// No gym (holiday flat, hotel, gym closed): bodyweight-only workouts on these days.
        case noGym(from: Date, days: Int)
        /// Team practice cancelled (`happening` false) or added (true) on these days.
        case practice(from: Date, days: Int, happening: Bool)
        /// Development goals (Struggle raw values), most important first.
        case goals([String])
        /// The season calendar: "pre" (pre-season training starts), "in" (the
        /// season itself starts) or "end" (the season ends) on this day.
        case season(String, from: Date)
        /// Body regions (ContextRegion raw values) feel tired on a day: 1 a little, 2 tired, 3 very.
        case fatigue(day: Date, regions: [String], level: Int)
        /// What practice (or a game) gave on a day (ContextQuality raw values): 1 light, 2 normal, 3 a lot.
        case training(day: Date, qualities: [String], level: Int)
        /// The athlete's own workout on a day: movement patterns and qualities, the words they used,
        /// how hard (1 easy, 2 solid, 3 hard) and how long when they said it.
        case workout(day: Date, patterns: [String], qualities: [String], names: [String], level: Int, minutes: Int?)
        /// Only this equipment (`equipmentLevelByTag` keys) on these days.
        case equipment(from: Date, days: Int, tags: [String])
        /// Minutes available on a day.
        case time(day: Date, minutes: Int)
    }

    public enum CompetitionWord: String, Sendable { case game, tournament, meet }

    public struct Result: Sendable, Equatable {
        public var proposals: [Proposal]
        /// Something worrying was mentioned (head, sharp pain): show the safety line.
        public var safety: String?
        /// Sentences it couldn't turn into anything — shown honestly, never dropped silently.
        public var unread: [String] = []
    }

    /// `locale` decides how "11/12" reads: 12 November where the month comes
    /// first (US), 11 December elsewhere.
    public static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> Result {
        let lower = expandGermanDayRanges(text.lowercased()
            .replacingOccurrences(of: "’", with: "'"))
        var proposals: [Proposal] = []
        var safety: String?
        // Sentences end at . ! ? ; followed by a space or the end — "24.11." stays one date.
        let marked = lower.replacingOccurrences(of: #"[.!?;]+(\s+|$)"#, with: "\n", options: .regularExpression)
        // "Guten Morgen", "good morning": a greeting, never "tomorrow".
        let sentences = marked.split(separator: "\n").map { withoutGreetings(String($0)) }
        var goals: [String] = []
        var unread: [String] = []
        var lastSeason: String?
        // A workout told over several sentences ("Had a workout today. Chest,
        // upper back and core. A bit of arms. Solid, 1 hour."): one report.
        var session: WorkoutDraft?

        for sentence in sentences {
            let words = tokens(sentence)
            let date = findDate(sentence, words: words, now: now, calendar: calendar, monthFirst: monthFirst(locale))
            // "Friday until Monday", "this weekend", "next week": a span of days.
            let range = findRange(sentence, words: words, now: now, calendar: calendar, monthFirst: monthFirst(locale))
            let today = calendar.startOfDay(for: now)
            let before = proposals.count
            let goalsBefore = goals.count
            var understood = false

            // The season calendar: "dryland starts the first week of December",
            // "season starts after the holidays", "Saison endet im März".
            if let part = seasonPart(words, sentence) {
                if let day = date?.day {
                    proposals.append(.season(part, from: day))
                    lastSeason = part
                }
                understood = true
            } else if let day = date?.day, lastSeason == "pre", words.count <= 6,
                      !proposals.contains(where: { if case .season("in", _) = $0 { true } else { false } }) {
                // "Dryland in December. After the holidays." — a bare day right
                // after pre-season reads as the season itself starting.
                proposals.append(.season("in", from: day))
                lastSeason = "in"
                understood = true
            }

            // A report about training that happened ("practice was brutal", "I did squats yesterday").
            let report = isReport(words, sentence)
            let past = pastDay(words, sentence, found: date?.day, now: now, calendar: calendar)
            // A competition on a day — not "the game was brutal" (that's a report).
            let competition = report && (date == nil || (date?.day ?? today) <= today) ? nil : competitionWord(words, sentence)
            if let kind = competition, let range, range.days > 1, range.days <= 4 {
                // "Tournament Friday to Sunday": one competition a day, the time on the first.
                for offset in 0..<range.days {
                    guard let day = calendar.date(byAdding: .day, value: offset, to: range.from) else { continue }
                    var when = day
                    var hasTime = false
                    if offset == 0, let (hour, minute) = findTime(sentence),
                       let timed = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) {
                        when = timed
                        hasTime = true
                    }
                    proposals.append(.competition(date: when, kind: kind, note: opponent(sentence), hasTime: hasTime))
                }
            } else if let kind = competition, let day = date?.day {
                var when = day
                var hasTime = false
                if let (hour, minute) = findTime(sentence),
                   let timed = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) {
                    when = timed
                    hasTime = true
                } else {
                    // Midnight means "time not known": the app uses the usual start time.
                    when = calendar.startOfDay(for: day)
                }
                proposals.append(.competition(date: when, kind: kind, note: opponent(sentence), hasTime: hasTime))
            }

            // Pain, or a knock to the head.
            if mentionsPain(sentence, words) {
                if containsAny(words, sentence, head) {
                    if !proposals.contains(.headKnock) { proposals.append(.headKnock) }
                    safety = "Hit your head? Stop training and tell an adult. A doctor clears you to play again."
                } else {
                    let areas = painAreas(words, sentence)
                    if !areas.isEmpty {
                        let level = painLevel(sentence)
                        proposals.append(.pain(areas: areas, level: level))
                        if level == "lot" || containsAny(words, sentence, ["sharp", "swollen", "swelling", "stechend", "geschwollen"]) {
                            safety = "Sharp pain, swelling, or pain that gets worse: stop and get it checked."
                        }
                    }
                }
            }

            // How the body feels, what training gave, the athlete's own workout,
            // equipment and time (the shared context: AthleteContext).
            for (regions, level) in fatigue(sentence) {
                proposals.append(.fatigue(day: past ?? today, regions: regions, level: level))
            }
            if report, let (qualities, level) = trainingReport(words, sentence) {
                proposals.append(.training(day: past ?? today, qualities: qualities, level: level))
            }
            let startsWorkout = startsOwnWorkout(words, sentence)
            if startsWorkout, let open = session, open.day != (past ?? open.day) {
                // Another day's workout: the first one is complete.
                proposals.append(open.proposal)
                session = nil
            }
            if startsWorkout || session != nil {
                let parts = workoutParts(sentence)
                let effort = workoutEffort(words, sentence)
                let minutes = sessionMinutes(sentence, words)
                if startsWorkout || !parts.names.isEmpty || effort != nil || minutes != nil {
                    var draft = session ?? WorkoutDraft(day: past ?? today)
                    draft.add(parts)
                    if let effort { draft.level = max(draft.level ?? effort, effort) }
                    if let minutes { draft.minutes = minutes }
                    session = draft
                    understood = true
                }
            }
            let tags = equipmentTags(words, sentence)
            if !tags.isEmpty, !report, containsAny(words, sentence, availabilityWords) {
                proposals.append(.equipment(from: range?.from ?? date?.day ?? today, days: range?.days ?? forDays(sentence) ?? 1, tags: tags))
            }
            if !report, let minutes = minutesAvailable(sentence, words) {
                proposals.append(.time(day: date?.day ?? today, minutes: minutes))
            }

            // Exams.
            if containsAny(words, sentence, ["exam", "exams", "midterm", "midterms", "finals week", "prüfung", "prüfungen", "klausur", "klausuren", "schularbeit", "schularbeiten", "abitur", "test at school", "tests at school"]) {
                let day = date?.day ?? now
                proposals.append(.examWeek(day))
            }

            // Sick, travel, holiday — over a span when one was given ("Friday until Monday").
            let spanFrom = range?.from ?? date?.day ?? today
            var hasStatus = false
            if containsAny(words, sentence, ["sick", "ill", "flu", "fever", "a cold", "krank", "erkältet", "erkältung", "fieber", "grippe"]) {
                proposals.append(.dayStatus("sick", from: spanFrom, days: range?.days ?? forDays(sentence) ?? 2))
            } else if containsAny(words, sentence, ["travel", "travelling", "traveling", "flight", "flying", "trip", "i'm away", "i am away", "be away", "going away", "reise", "reisen", "flug", "fliege", "unterwegs", "verreist", "nicht da"]) {
                proposals.append(.dayStatus("travel", from: spanFrom, days: range?.days ?? forDays(sentence) ?? 1))
                hasStatus = true
            } else if containsAny(words, sentence, ["vacation", "holiday", "holidays", "urlaub", "ferien"]) && !holidayIsOnlyADate(sentence)
                        && seasonPart(words, sentence) == nil {
                proposals.append(.dayStatus("holiday", from: spanFrom, days: range?.days ?? forDays(sentence) ?? 7))
                hasStatus = true
            }

            // No gym: bodyweight days. Travel and holiday already mean bodyweight.
            if !hasStatus, mentionsNoGym(sentence), equipmentTags(words, sentence).isEmpty || !containsAny(words, sentence, availabilityWords) {
                proposals.append(.noGym(from: spanFrom, days: range?.days ?? forDays(sentence) ?? 1))
            }

            // Team practice off or on, on a day or a span.
            if competition == nil, range != nil || date != nil, let happening = practiceChange(words, sentence), !(happening && report) {
                proposals.append(.practice(from: spanFrom, days: range?.days ?? forDays(sentence) ?? 1, happening: happening))
            }

            // Goals: "I want to get faster", "ich will stärker werden".
            if !report || containsAny(words, sentence, ["want", "wanna", "goal", "goals", "möchte", "ziel"]),
               containsAny(words, sentence, ["want", "wanna", "goal", "goals", "improve", "better", "become", "get", "work", "möchte", "will", "ziel", "ziele", "verbessern", "besser", "werden"]) {
                for (keys, goal) in goalWords where containsAny(words, sentence, keys) && !goals.contains(goal) {
                    goals.append(goal)
                }
            }

            if proposals.count == before && goals.count == goalsBefore && !understood && !isSmallTalk(words) {
                unread.append(sentence.trimmingCharacters(in: .whitespaces))
            }
        }
        if let session { proposals.append(session.proposal) }
        if !goals.isEmpty { proposals.append(.goals(Array(goals.prefix(3)))) }
        return Result(proposals: dedupe(proposals), safety: safety, unread: unread)
    }

    // MARK: Spans, gyms and practice

    static let noGymPhrases = [
        "no gym", "no real gym", "no proper gym", "not a real gym", "don't have a gym", "dont have a gym", "don't have a real gym",
        "dont have a real gym", "do not have a gym", "don't have access to a gym", "no access to a gym", "without a gym", "can't go to the gym",
        "cant go to the gym", "gym is closed", "gym closed", "no equipment", "without equipment", "no weights", "bodyweight only",
        "only bodyweight", "just bodyweight", "body weight only", "only my bodyweight", "own bodyweight", "hotel gym",
        "kein gym", "kein richtiges gym", "kein fitnessstudio", "kein studio", "keine geräte", "ohne geräte", "keine hanteln", "nur eigengewicht",
        "mit eigengewicht", "ohne gym", "fitnessstudio zu", "gym zu", "gym hat zu", "studio hat zu",
    ]

    static func mentionsNoGym(_ sentence: String) -> Bool { noGymPhrases.contains(where: sentence.contains) }

    /// false: practice is off ("no practice Friday"); true: practice is on ("extra practice Saturday"); nil: not about practice.
    static func practiceChange(_ words: [String], _ sentence: String) -> Bool? {
        let off = ["no practice", "no team practice", "practice is cancelled", "practice is canceled", "practice cancelled", "practice canceled",
                   "practice is off", "practice got cancelled", "practice got canceled", "skip practice", "skipping practice", "no training",
                   "kein training", "kein mannschaftstraining", "training fällt aus", "training ist abgesagt", "training abgesagt",
                   "fällt das training aus", "trainingsfrei", "kein vereinstraining"]
        if off.contains(where: sentence.contains) { return false }
        // "Training fällt morgen aus", "practice tomorrow is cancelled".
        if containsAny(words, sentence, ["training", "practice"]),
           containsAny(words, sentence, ["abgesagt", "cancelled", "canceled", "off"]) || (words.contains("fällt") && words.contains("aus")) { return false }
        let on = ["extra practice", "practice moved to", "practice is on", "we have practice", "i have practice", "have practice on",
                  "practice on", "practice at", "practice tomorrow", "practice today", "zusatztraining", "extra training", "training am",
                  "training ist am", "training verschoben auf", "haben training", "habe training", "training morgen", "training heute"]
        if on.contains(where: sentence.contains) { return true }
        return nil
    }

    /// "Fr bis Mo", "Fr-Mo": two-letter German days only read as days next to "bis" or a dash.
    static func expandGermanDayRanges(_ text: String) -> String {
        let names = ["mo": "montag", "di": "dienstag", "mi": "mittwoch", "do": "donnerstag", "fr": "freitag", "sa": "samstag", "so": "sonntag"]
        let pattern = #"\b(mo|di|mi|do|fr|sa|so)\.?\s*(bis|-|–)\s*(mo|di|mi|do|fr|sa|so)\b\.?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var out = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: out), let a = Range(match.range(at: 1), in: out), let b = Range(match.range(at: 3), in: out),
                  let first = names[String(out[a])], let last = names[String(out[b])] else { continue }
            out.replaceSubrange(whole, with: "\(first) bis \(last)")
        }
        return out
    }

    /// A span of days: "Friday until Monday", "from Fri to Sun", "until Sunday"
    /// (from today), "bis Sonntag", "this weekend", "next week".
    static func findRange(_ sentence: String, words: [String], now: Date, calendar: Calendar, monthFirst: Bool) -> (from: Date, days: Int)? {
        let today = calendar.startOfDay(for: now)
        func span(_ from: Date, _ to: Date) -> (from: Date, days: Int)? {
            guard let days = calendar.dateComponents([.day], from: from, to: to).day.map({ $0 + 1 }), (1...30).contains(days) else { return nil }
            return (from, days)
        }
        // Words that join two days. " to " and dashes need a day on both sides.
        let connectors: [(String, Bool)] = [(" until ", false), (" till ", false), (" til ", false), (" through ", true), (" thru ", true),
                                            (" to ", true), (" bis einschließlich ", false), (" bis zum ", false), (" bis ", false),
                                            (" - ", true), (" – ", true), ("-", true)]
        let skip: Set<String> = ["the", "next", "on", "am", "zum", "zur", "einschließlich", "including", "and", "this", "dem", "den", "kommenden"]
        for (connector, needsStart) in connectors {
            guard let hit = sentence.range(of: connector) else { continue }
            let left = String(sentence[..<hit.lowerBound])
            let right = String(sentence[hit.upperBound...])
            var rightWords = tokens(right)
            while let first = rightWords.first, skip.contains(first) { rightWords.removeFirst() }
            guard let head = rightWords.first else { continue }
            let leftDate = findDate(left, words: tokens(left), now: now, calendar: calendar, monthFirst: monthFirst)?.day
            if needsStart && leftDate == nil { continue }
            let start = leftDate ?? today
            var end: Date?
            if let weekday = weekdays.first(where: { $0.names.contains(head) && head.count >= 3 }) {
                end = nextWeekday(weekday.number, after: start, skipThisWeek: false, calendar: calendar)
            } else if head.first?.isNumber == true || months.contains(where: { $0.names.contains(head) })
                        || ["tomorrow", "morgen", "übermorgen", "today", "heute"].contains(head) {
                let rest = rightWords.prefix(4).joined(separator: " ")
                let raw = String(right.trimmingCharacters(in: .whitespaces).prefix(16))
                end = findDate(raw, words: tokens(rest), now: now, calendar: calendar, monthFirst: monthFirst)?.day
            }
            guard let last = end, last >= start, let found = span(start, last) else { continue }
            return found
        }
        let next = containsAny(words, sentence, ["next weekend", "nächstes wochenende", "nächsten wochenende", "kommendes wochenende"])
        if next || containsAny(words, sentence, ["this weekend", "over the weekend", "the weekend", "on the weekend", "at the weekend",
                                                 "übers wochenende", "über das wochenende", "am wochenende", "dieses wochenende", "wochenende"]) {
            let weekday = calendar.component(.weekday, from: today)
            if weekday == 1 && !next { return (today, 1) }
            let saturday = nextWeekday(7, after: today, skipThisWeek: next && weekday != 7, calendar: calendar)
            return (saturday, 2)
        }
        if containsAny(words, sentence, ["next week", "nächste woche", "nächsten woche", "kommende woche", "die ganze nächste woche"]) {
            let monday = calendar.dateInterval(of: .weekOfYear, for: calendar.date(byAdding: .day, value: 7, to: today) ?? today)?.start ?? today
            return (monday, 7)
        }
        return nil
    }

    // MARK: Context: body, training, equipment, time

    static let fatigueWords = ["cooked", "dead", "destroyed", "tired", "fatigued", "heavy", "sore", "wrecked", "toast", "shot", "exhausted",
                               "smoked", "fried", "gone", "jelly", "spent", "drained", "stiff", "tight", "beat",
                               "müde", "platt", "kaputt", "fertig", "muskelkater", "schwer", "tot", "durch", "erschöpft", "steif"]
    static let strongWords = ["cooked", "dead", "destroyed", "wrecked", "toast", "shot", "smoked", "fried", "gone", "jelly", "exhausted",
                              "very", "really", "super", "so", "extremely", "completely", "totally", "absolutely",
                              "platt", "kaputt", "fertig", "tot", "sehr", "total", "komplett", "extrem", "richtig"]
    static let mildWords = ["a bit", "a little", "slightly", "kind of", "kinda", "bisschen", "leicht", "etwas", "ein wenig"]

    /// Body regions for fatigue (ContextRegion raw values), most specific first.
    static let regionWords: [([String], String)] = [
        (["calf", "calves", "wade", "waden"], "calves"),
        (["hamstring", "hamstrings", "hammies", "beinbeuger"], "hamstrings"),
        (["quad", "quads", "oberschenkel"], "quads"),
        (["hip", "hips", "glutes", "hüfte", "hüften", "po"], "hips"),
        (["leg", "legs", "beine", "bein"], "legs"),
        (["upper body", "oberkörper"], "upperBody"),
        (["shoulder", "shoulders", "schulter", "schultern"], "shoulders"),
        (["arm", "arms", "biceps", "triceps", "arme"], "arms"),
        (["chest", "pecs", "brust"], "chest"),
        (["my back", "back is", "back feels", "lower back", "upper back", "rücken"], "back"),
        (["abs", "core", "bauch", "rumpf"], "core"),
        (["whole body", "my body", "everything", "ganzer körper", "körper", "alles"], "wholeBody"),
    ]

    /// "My legs are cooked", "calves really tired but upper body fine":
    /// each clause with a fatigue word and a region. Fine clauses add nothing.
    static func fatigue(_ sentence: String) -> [(regions: [String], level: Int)] {
        let clauses = sentence
            .replacingOccurrences(of: #"\b(but|aber|and|und|while|whereas|während)\b|,"#, with: "|", options: .regularExpression)
            .split(separator: "|").map { String($0) }
        var out: [(regions: [String], level: Int)] = []
        for clause in clauses {
            let words = tokens(clause)
            // Pain stays pain (its own safety path), never "tired".
            guard containsAny(words, clause, fatigueWords), !mentionsPain(clause, words),
                  !containsAny(words, clause, ["fine", "good", "great", "fresh", "ok", "okay", "gut", "fit", "frisch"]) else { continue }
            var regions: [String] = []
            for (keys, region) in regionWords where containsAny(words, clause, keys) {
                // "Calves" is enough; "legs" too when it's said on its own.
                if region == "legs", regions.contains(where: { ["calves", "hamstrings", "quads"].contains($0) }) { continue }
                if !regions.contains(region) { regions.append(region) }
            }
            guard !regions.isEmpty else { continue }
            let level = containsAny(words, clause, mildWords) ? 1 : containsAny(words, clause, strongWords) ? 3 : 2
            out.append((regions, level))
        }
        return out
    }

    /// Past-tense talk about a session: "practice was brutal", "we did lots of
    /// sprints", "I trained chest yesterday", "training war hart".
    static func isReport(_ words: [String], _ sentence: String) -> Bool {
        let past = ["was", "were", "did", "had", "ran", "trained", "lifted", "worked", "hit", "went", "got", "barely", "mostly",
                    "war", "waren", "hatten", "hatte", "habe", "haben", "gemacht", "trainiert", "gelaufen", "gesprintet", "yesterday", "gestern"]
        let session = ["practice", "training", "session", "workout", "game", "match", "scrimmage", "scrimmaging", "gym", "lift", "lifting",
                       "sprints", "sprinting", "conditioning", "spiel", "einheit", "leg day", "upper day", "squats", "bench", "deadlifts",
                       "rdls", "rows", "pull-ups", "pullups", "shooting", "drills", "skills", "ran", "running"]
        let intent = ["want", "wanna", "will", "going to", "gonna", "plan", "möchte", "werde", "should", "need to", "tomorrow", "morgen"]
        guard !containsAny(words, sentence, intent) else { return false }
        // "Tons of sprints and my legs are cooked": what practice was made of, said without a verb.
        let made = ["sprints", "sprinting", "suicides", "conditioning", "scrimmaging", "plyos", "laps", "shuttles", "sprinten", "läufe"]
        return (containsAny(words, sentence, past) && containsAny(words, sentence, session)) || containsAny(words, sentence, made)
    }

    /// "Yesterday", "last night", "gestern": the day before; a weekday in a report is the last one, not the next.
    static func pastDay(_ words: [String], _ sentence: String, found: Date?, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        if containsAny(words, sentence, ["yesterday", "last night", "gestern", "gestern abend"]) {
            return calendar.date(byAdding: .day, value: -1, to: today)
        }
        if containsAny(words, sentence, ["day before yesterday", "vorgestern"]) { return calendar.date(byAdding: .day, value: -2, to: today) }
        guard let found, found > today else { return found }
        // "I did squats on Monday" on a Wednesday: last Monday.
        let back = calendar.date(byAdding: .day, value: -7, to: found) ?? found
        return back <= today ? back : nil
    }

    /// What practice gave: "tons of sprints", "mostly conditioning", "barely ran, mostly shooting", "practice was brutal".
    static func trainingReport(_ words: [String], _ sentence: String) -> (qualities: [String], level: Int)? {
        // The athlete's own gym workout is read by `ownWorkout`.
        guard !containsAny(words, sentence, ["gym", "lifted", "lifting", "leg day", "upper day", "workout"]) || containsAny(words, sentence, ["practice", "training", "game", "match", "spiel"]) else { return nil }
        let lots = ["lots of", "lot of", "tons of", "ton of", "a ton", "a lot", "so much", "loads of", "so many", "a bunch of", "many", "endless", "nonstop", "non-stop",
                    "all practice", "the whole practice", "mostly", "brutal", "insane", "crazy", "killer", "viele", "sehr viel", "nur", "brutal"]
        let hard = ["brutal", "hard", "tough", "killer", "intense", "insane", "crazy", "rough", "heavy", "two hours", "2 hours",
                    "hart", "anstrengend", "heftig", "brutal"]
        let easy = ["easy", "light", "chill", "relaxed", "walkthrough", "walk-through", "locker", "leicht", "entspannt"]
        var qualities: [String] = []
        var level = 2
        if containsAny(words, sentence, ["barely ran", "didn't run", "did not run", "no running", "hardly ran", "not much running",
                                         "kaum gelaufen", "wenig gelaufen", "nicht gelaufen"]) {
            qualities += ["lowRunning", "skill"]
            level = 1
        }
        if containsAny(words, sentence, ["sprint", "sprints", "sprinting", "sprinted", "sprinten", "gesprintet", "suicides", "full-court", "full court",
                                         "scrimmage", "scrimmaging", "shuttles", "accelerations"]) {
            qualities.append("sprinting")
        }
        if containsAny(words, sentence, ["conditioning", "running", "ran a lot", "ran a ton", "ran so much", "laps", "suicides", "fitness", "kondition", "läufe", "ausdauer",
                                         "full-court", "full court", "intervals"]) && !qualities.contains("lowRunning") {
            qualities.append("conditioning")
        }
        if containsAny(words, sentence, ["jumps", "jumping", "plyos", "plyometrics", "box jumps", "sprünge", "springen", "sprungtraining"]) {
            qualities.append("jumping")
        }
        if containsAny(words, sentence, ["shooting", "skills", "technique", "drills", "tactics", "film", "technik", "taktik"]), !qualities.contains("skill") {
            qualities.append("skill")
            if !qualities.contains("sprinting") && !qualities.contains("conditioning") && containsAny(words, sentence, ["mostly", "just", "only", "nur", "hauptsächlich"]) {
                qualities.append("lowRunning")
                level = 1
            }
        }
        let sessionNamed = containsAny(words, sentence, ["practice", "training", "session", "game", "match", "scrimmage", "spiel", "einheit"])
        if containsAny(words, sentence, hard) || (containsAny(words, sentence, lots) && !qualities.isEmpty && !qualities.contains("lowRunning")) {
            level = 3
        } else if containsAny(words, sentence, easy) {
            level = 1
            if !qualities.contains("lowRunning") { qualities.append("lowRunning") }
        }
        guard !qualities.isEmpty || (sessionNamed && level != 2) else { return nil }
        return (qualities, level)
    }

    /// The athlete's own workout: "I did squats and RDLs", "trained chest and back yesterday", "hard leg workout".
    static func ownWorkout(_ words: [String], _ sentence: String) -> (patterns: [String], qualities: [String], names: [String], level: Int)? {
        guard containsAny(words, sentence, ["did", "trained", "lifted", "worked", "hit", "had", "leg day", "upper day", "workout", "session in the gym",
                                            "gemacht", "trainiert", "training gemacht"]),
              // Practice and games are read by `trainingReport`.
              !containsAny(words, sentence, ["practice", "game", "match", "scrimmage", "spiel"]) else { return nil }
        let lexicon: [([String], String, String)] = [
            (["bench", "bench press", "bankdrücken", "push-ups", "pushups", "push ups", "liegestütze", "incline", "dips", "chest", "brust", "flys"], "push", "upperStrength"),
            (["shoulder press", "overhead press", "ohp", "military press", "schulterdrücken", "shoulders", "schultern"], "push", "upperStrength"),
            (["rows", "rudern", "pull-ups", "pullups", "pull ups", "chin-ups", "chinups", "klimmzüge", "lat pulldown", "pulldowns",
              "latzug", "back", "rücken"], "pull", "upperStrength"),
            (["arms", "biceps", "triceps", "curls", "upper body", "oberkörper", "upper day"], "push", "upperStrength"),
            (["squats", "squat", "kniebeuge", "kniebeugen", "leg press", "beinpresse", "lunges", "ausfallschritte", "step-ups", "legs", "leg day",
              "leg workout", "beine", "beintraining"], "squat", "lowerStrength"),
            (["rdl", "rdls", "romanian deadlift", "deadlift", "deadlifts", "kreuzheben", "hip thrust", "hip thrusts", "hamstring curls", "good mornings"], "hinge", "lowerStrength"),
            (["abs", "core", "planks", "plank", "sit-ups", "situps", "crunches", "bauch", "rumpf"], "core", "core"),
        ]
        var patterns: [String] = []
        var qualities: [String] = []
        var names: [String] = []
        for (keys, pattern, quality) in lexicon {
            let hits = keys.filter { key in key.contains(" ") || key.contains("-") ? sentence.contains(key) : words.contains(key) }
            guard !hits.isEmpty else { continue }
            if pattern != "core", !patterns.contains(pattern) { patterns.append(pattern) }
            if !qualities.contains(quality) { qualities.append(quality) }
            for hit in hits where !names.contains(hit) { names.append(hit) }
        }
        guard !qualities.isEmpty else { return nil }
        // Only body parts named ("legs", "chest and back"): a workout only when
        // it says it trained them — not "we did sprints and my legs are cooked".
        let bodyParts: Set<String> = ["back", "rücken", "legs", "beine", "chest", "brust", "shoulders", "schultern", "arms", "upper body",
                                      "oberkörper", "abs", "core", "bauch", "rumpf"]
        if names.allSatisfy({ bodyParts.contains($0) }),
           !containsAny(words, sentence, ["trained", "worked", "hit", "train", "leg day", "upper day", "workout", "trainiert", "gemacht"]) { return nil }
        // "Back" alone is the body more often than the workout ("my back is tired").
        if qualities == ["upperStrength"], patterns == ["pull"], !containsAny(words, sentence, ["rows", "row", "pull-ups", "pullups", "chin-ups", "rudern",
                                                                                                    "klimmzüge", "chest and back", "back and"]),
           containsAny(words, sentence, ["my back", "back is", "back feels"]) { return nil }
        let level = containsAny(words, sentence, ["heavy", "hard", "brutal", "max", "intense", "schwer", "hart"]) ? 3 : 2
        return (patterns, qualities, names, level)
    }

    /// A workout being told over one or more sentences.
    struct WorkoutDraft {
        var day: Date
        var patterns: [String] = []
        var qualities: [String] = []
        var names: [String] = []
        var level: Int?
        var minutes: Int?

        mutating func add(_ parts: (patterns: [String], qualities: [String], names: [String])) {
            for p in parts.patterns where !patterns.contains(p) { patterns.append(p) }
            for q in parts.qualities where !qualities.contains(q) { qualities.append(q) }
            for n in parts.names where !names.contains(n) { names.append(n) }
        }

        var proposal: Proposal {
            .workout(day: day, patterns: patterns, qualities: qualities, names: names, level: level ?? 2, minutes: minutes)
        }
    }

    /// The sentence tells about the athlete's own workout (not team practice, not a plan).
    static func startsOwnWorkout(_ words: [String], _ sentence: String) -> Bool {
        let intent = ["want", "wanna", "will", "going to", "gonna", "plan", "should", "need to", "tomorrow", "möchte", "werde", "morgen", "remind"]
        guard !containsAny(words, sentence, intent),
              !containsAny(words, sentence, ["practice", "game", "match", "spiel", "scrimmage", "no gym", "kein gym", "no real gym"]) else { return false }
        if ownWorkout(words, sentence) != nil { return true }
        let named = ["workout", "work out", "worked out", "gym session", "went to the gym", "hit the gym", "was at the gym", "at the gym", "in the gym",
                     "lifted", "lifting", "leg day", "upper day", "push day", "pull day", "lift today", "weights", "krafttraining", "im gym",
                     "gym gemacht", "training im gym", "im fitnessstudio"]
        if containsAny(words, sentence, named) { return true }
        // "Gym today: bench, rows, curls", "gym this morning".
        if words.first == "gym" || (words.contains("gym") && containsAny(words, sentence, ["today", "yesterday", "this morning", "tonight", "earlier",
                                                                                           "heute", "gestern"])) { return true }
        // "Did 30 minutes on the bike", "went for a run": the athlete's own cardio.
        let did = ["did", "went", "had", "trained", "rode", "ran", "swam", "rowed", "biked", "cycled", "gemacht", "war", "bin"]
        return containsAny(words, sentence, did) && !workoutParts(sentence).names.isEmpty
            && workoutParts(sentence).qualities.contains("conditioning")
    }

    /// Body parts and exercises a workout trained, from the clauses that aren't
    /// about tiredness or pain ("legs are cooked" isn't what was trained).
    static func workoutParts(_ sentence: String) -> (patterns: [String], qualities: [String], names: [String]) {
        let clauses = sentence
            .replacingOccurrences(of: #"\b(but|aber)\b|,"#, with: "|", options: .regularExpression)
            .split(separator: "|").map { String($0) }
        let lexicon: [([String], String?, String)] = [
            (["chest", "pecs", "brust", "bench", "bench press", "bankdrücken", "push-ups", "pushups", "push ups", "liegestütze", "incline", "dips", "flys"], "push", "upperStrength"),
            (["shoulders", "shoulder", "delts", "schultern", "shoulder press", "overhead press", "ohp", "military press", "schulterdrücken"], "push", "upperStrength"),
            (["upper back", "back", "lats", "rücken", "rows", "rudern", "pull-ups", "pullups", "pull ups", "chin-ups", "chinups", "klimmzüge",
              "lat pulldown", "pulldowns", "latzug"], "pull", "upperStrength"),
            (["arms", "biceps", "triceps", "curls", "arme", "bizeps", "trizeps"], nil, "upperStrength"),
            (["upper body", "oberkörper"], "push", "upperStrength"),
            (["legs", "leg", "leg day", "quads", "glutes", "beine", "squats", "squat", "kniebeuge", "kniebeugen", "leg press", "beinpresse", "lunges",
              "ausfallschritte", "step-ups", "calves", "calf raises", "calf raise", "waden"], "squat", "lowerStrength"),
            (["hamstrings", "hamstring", "rdl", "rdls", "romanian deadlift", "deadlift", "deadlifts", "kreuzheben", "hip thrust", "hip thrusts",
              "good mornings"], "hinge", "lowerStrength"),
            (["core", "abs", "planks", "plank", "sit-ups", "situps", "crunches", "bauch", "rumpf"], nil, "core"),
            (["bike", "cycling", "cycled", "biked", "spinning", "run", "running", "jog", "jogging", "swim", "swam", "swimming",
              "rower", "rowing", "rowed", "elliptical", "treadmill", "stairmaster", "stair climber", "cardio", "intervals", "hiit",
              "radfahren", "laufen", "joggen", "schwimmen", "ergometer"], nil, "conditioning"),
        ]
        var patterns: [String] = []
        var qualities: [String] = []
        var names: [String] = []
        for clause in clauses {
            let words = tokens(clause)
            if mentionsPain(clause, words) { continue }
            if containsAny(words, clause, fatigueWords) && !containsAny(words, clause, ["workout", "trained", "did", "had"]) { continue }
            for (keys, pattern, quality) in lexicon {
                let found = keys.filter { key in key.contains(" ") || key.contains("-") ? clause.contains(key) : words.contains(key) }
                // "upper back" is one thing, not also "back"; "shoulder press" not also "shoulder".
                let hits = found.filter { hit in !found.contains { $0 != hit && $0.contains(hit) } }
                guard !hits.isEmpty else { continue }
                if let pattern, !patterns.contains(pattern) { patterns.append(pattern) }
                if !qualities.contains(quality) { qualities.append(quality) }
                for hit in hits where !names.contains(hit) && !names.contains(where: { $0.contains(hit) }) { names.append(hit) }
            }
        }
        return (patterns, qualities, names)
    }

    /// How hard the athlete said a workout was: 1 easy, 2 solid, 3 hard.
    static func workoutEffort(_ words: [String], _ sentence: String) -> Int? {
        if containsAny(words, sentence, ["brutal", "hard", "tough", "heavy", "intense", "killer", "insane", "max", "maxed", "crushed",
                                         "hart", "schwer", "anstrengend", "heftig"]) { return 3 }
        if containsAny(words, sentence, ["solid", "good", "decent", "normal", "moderate", "okay", "ok", "fine", "gut", "ordentlich", "normal"]) { return 2 }
        if containsAny(words, sentence, ["easy", "light", "chill", "relaxed", "short", "locker", "leicht", "kurz"]) { return 1 }
        return nil
    }

    /// How long a session was: "1 hour long", "45 minutes", "an hour and a half".
    static func sessionMinutes(_ sentence: String, _ words: [String]) -> Int? {
        if containsAny(words, sentence, ["an hour and a half", "one and a half hours", "1.5 hours", "eineinhalb stunden", "anderthalb stunden"]) { return 90 }
        if containsAny(words, sentence, ["half an hour", "half hour", "halbe stunde"]) { return 30 }
        if let match = sentence.range(of: #"(\d{1,3})\s*(minutes|minute|mins|min|minuten)\b"#, options: .regularExpression),
           let value = Int(sentence[match].prefix { $0.isNumber }), (5...240).contains(value) {
            return value
        }
        if let match = sentence.range(of: #"(\d)\s*(hours|hour|hrs|hr|stunden|stunde|h)\b"#, options: .regularExpression),
           let value = Int(sentence[match].prefix { $0.isNumber }), (1...4).contains(value) {
            return value * 60
        }
        if containsAny(words, sentence, ["an hour", "one hour", "eine stunde"]) { return 60 }
        return nil
    }

    static let availabilityWords = ["only", "just", "has", "have", "got", "there's", "there is", "with", "nur", "hat", "haben", "habe", "gibt"]

    /// Equipment named in a sentence, as catalogue equipment tags.
    static func equipmentTags(_ words: [String], _ sentence: String) -> [String] {
        let lexicon: [([String], [String])] = [
            (["dumbbell", "dumbbells", "db", "dbs", "kurzhantel", "kurzhanteln", "hanteln"], ["dumbbell"]),
            (["barbell", "barbells", "langhantel", "squat rack", "rack"], ["barbell", "rack", "weight-plate"]),
            (["bench", "bank", "hantelbank"], ["bench"]),
            (["cable", "cables", "cable machine", "kabelzug"], ["cable-machine"]),
            (["machines", "geräte"], ["cable-machine", "lat-pulldown", "leg-curl-machine"]),
            (["band", "bands", "resistance band", "resistance bands", "theraband", "bänder", "widerstandsband"], ["band", "mini-band"]),
            (["kettlebell", "kettlebells", "kb"], ["kettlebell"]),
            (["pull-up bar", "pullup bar", "chin-up bar", "klimmzugstange"], ["pull-up-bar"]),
            (["box", "plyo box"], ["box"]),
            (["med ball", "medicine ball", "medizinball"], ["med-ball"]),
        ]
        var tags: [String] = []
        for (keys, add) in lexicon where containsAny(words, sentence, keys) {
            for tag in add where !tags.contains(tag) { tags.append(tag) }
        }
        // "no dumbbells", "keine Hanteln": not available.
        if containsAny(words, sentence, ["no dumbbells", "no weights", "keine hanteln", "no bands"]) { return [] }
        return tags
    }

    /// "Only 30 minutes today", "I have an hour", "nur eine halbe Stunde", "plenty of time Saturday".
    static func minutesAvailable(_ sentence: String, _ words: [String]) -> Int? {
        guard containsAny(words, sentence, ["only", "just", "have", "got", "i've", "nur", "habe", "hab", "zeit", "time", "max", "maximum"]) else { return nil }
        // "Practice in 2 hours", "practice for 2 hours": when, or how long practice is — not free time.
        if sentence.range(of: #"\bin\s+\d"#, options: .regularExpression) != nil
            || ["practice for", "training for", "game for", "match for", "practice is", "training ist"].contains(where: sentence.contains) { return nil }
        if containsAny(words, sentence, ["plenty of time", "lots of time", "all the time", "viel zeit", "genug zeit"]) { return 90 }
        if containsAny(words, sentence, ["half an hour", "halbe stunde", "half hour"]) { return 30 }
        if containsAny(words, sentence, ["an hour and a half", "eineinhalb stunden", "anderthalb stunden", "1.5 hours"]) { return 90 }
        if let match = sentence.range(of: #"(\d{1,3})\s*(minutes|minute|mins|min|minuten)\b"#, options: .regularExpression),
           let value = Int(sentence[match].prefix { $0.isNumber }), (10...180).contains(value) {
            return value
        }
        if let match = sentence.range(of: #"(\d)\s*(hours|hour|stunden|stunde|h)\b"#, options: .regularExpression),
           let value = Int(sentence[match].prefix { $0.isNumber }), (1...3).contains(value) {
            return value * 60
        }
        if containsAny(words, sentence, ["an hour", "one hour", "eine stunde", "1 hour"]) { return 60 }
        return nil
    }

    // MARK: Season

    /// "pre", "in" or "end" when the sentence is about the season calendar.
    static func seasonPart(_ words: [String], _ sentence: String) -> String? {
        let pre = ["dryland", "dry land", "preseason", "pre-season", "pre season", "vorbereitung", "saisonvorbereitung", "vorbereitungsphase",
                   "training camp", "trainingslager", "trockentraining", "athletiktraining"]
        if containsAny(words, sentence, pre) { return "pre" }
        let off = ["off-season", "offseason", "off season", "season ends", "season is over", "season will end", "season finishes", "end of the season",
                   "end of season", "last game of the season", "saisonende", "saison endet", "saison ist vorbei", "saison vorbei", "ende der saison"]
        if containsAny(words, sentence, off) { return "end" }
        if containsAny(words, sentence, ["season", "saison", "saisonstart", "saisonbeginn"]) { return "in" }
        return nil
    }

    /// "After the holidays", "nach den Ferien": a time, not a holiday that starts now.
    static func holidayIsOnlyADate(_ sentence: String) -> Bool {
        let markers = ["after the", "before the", "until the", "till the", "nach den", "vor den", "bis zu den", "bis zu", "bis den"]
        let nouns = ["holiday", "holidays", "vacation", "break", "christmas holidays", "ferien", "weihnachtsferien", "urlaub"]
        return markers.contains { marker in nouns.contains { sentence.contains("\(marker) \($0)") } }
    }

    /// Greetings taken out before reading: "guten morgen" has "morgen"
    /// (tomorrow) in it, and none of them says anything about a day.
    static func withoutGreetings(_ sentence: String) -> String {
        let greetings = ["guten morgen", "good morning", "guten tag", "guten abend", "good afternoon", "good evening"]
        guard greetings.contains(where: sentence.contains) else { return sentence }
        var out = sentence
        for greeting in greetings { out = out.replacingOccurrences(of: greeting, with: " ") }
        return out.trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))
    }

    /// Whether the locale writes the month before the day ("11/24" in the US).
    static func monthFirst(_ locale: Locale) -> Bool {
        guard let format = DateFormatter.dateFormat(fromTemplate: "dM", options: 0, locale: locale),
              let month = format.firstIndex(of: "M"), let day = format.firstIndex(of: "d") else { return false }
        return month < day
    }

    /// "Hi", "thanks", "ok" — nothing to read, nothing to report as not understood.
    static func isSmallTalk(_ words: [String]) -> Bool {
        let filler: Set<String> = ["hi", "hey", "hello", "hallo", "servus", "moin", "yo", "ok", "okay", "thanks", "thank", "you", "danke", "so", "also", "and", "und", "bye", "tschüss"]
        return words.isEmpty || words.allSatisfy { filler.contains($0) }
    }

    // MARK: Words

    static let head = ["head", "concussion", "concussed", "kopf", "gehirnerschütterung"]

    static let goalWords: [([String], String)] = [
        (["faster", "speed", "quicker", "sprint", "first step", "schneller", "tempo", "antritt"], "acceleration"),
        (["top speed", "max speed", "endgeschwindigkeit"], "maxSpeed"),
        (["stronger", "strength", "strong", "stärker", "kraft"], "strength"),
        (["jump", "jumping", "vertical", "springen", "sprungkraft"], "verticalJump"),
        (["explosive", "power", "explosiv", "schnellkraft"], "power"),
        (["agility", "agile", "change direction", "wendig", "wendigkeit"], "agility"),
        (["endurance", "stamina", "fitter", "fitness", "ausdauer", "kondition"], "aerobicFitness"),
        (["flexible", "flexibility", "mobility", "beweglich", "beweglichkeit"], "mobility"),
        (["confidence", "confident", "nervous", "nerves", "selbstvertrauen", "selbstbewusst", "nervös"], "confidence"),
        (["focus", "focused", "concentrate", "concentration", "konzentration", "konzentrieren", "fokus"], "focus"),
        (["recover", "recovery", "erholung", "regeneration"], "recovery"),
        (["technique", "skill", "skills", "technik"], "sportSkill"),
    ]

    static let areaWords: [([String], String)] = [
        (["knee", "knees", "knie"], "knee"),
        (["ankle", "ankles", "foot", "feet", "heel", "achilles", "knöchel", "sprunggelenk", "fuß", "füße", "ferse", "achillessehne"], "ankle"),
        (["shoulder", "shoulders", "schulter", "schultern"], "shoulder"),
        // "back" alone is too often "since I got back".
        (["lower back", "upper back", "my back", "the back", "back hurts", "back pain", "back is", "spine", "rücken", "kreuz"], "back"),
        (["hip", "hips", "groin", "hüfte", "leiste"], "hip"),
        (["neck", "nacken", "hals"], "neck"),
        (["wrist", "elbow", "arm", "arms", "hand", "finger", "handgelenk", "ellbogen", "ellenbogen"], "arm"),
        (["thigh", "hamstring", "hamstrings", "quad", "quads", "calf", "calves", "shin", "shins", "leg", "legs", "oberschenkel", "wade", "waden", "schienbein", "bein", "beine"], "leg"),
        (["stomach", "side", "ribs", "abs", "bauch", "rippen"], "core"),
        (["chest", "brust"], "chest"),
    ]

    static func tokens(_ sentence: String) -> [String] {
        sentence.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "äöüß")).inverted).filter { !$0.isEmpty }
    }

    /// A word list matches whole words; a phrase with a space matches as text.
    static func containsAny(_ words: [String], _ sentence: String, _ keys: [String]) -> Bool {
        keys.contains { key in key.contains(" ") ? sentence.contains(key) : words.contains(key) }
    }

    static func competitionWord(_ words: [String], _ sentence: String) -> CompetitionWord? {
        if containsAny(words, sentence, ["tournament", "tourney", "turnier", "cup", "championship", "championships", "meisterschaft"]) { return .tournament }
        // "meet with my coach", "meet up": not a competition.
        let socialMeet = sentence.contains("meet with") || sentence.contains("meet up") || sentence.contains("meet my") || sentence.contains("to meet")
        if containsAny(words, sentence, ["race", "regatta", "rennen", "wettkampf", "competition", "lauf"])
            || (!socialMeet && containsAny(words, sentence, ["meet"])) { return .meet }
        // "Finals" at school are exams, not a final.
        let schoolFinals = containsAny(words, sentence, ["finals"]) && containsAny(words, sentence, ["exam", "exams", "school", "study", "studying", "class", "classes"])
        if schoolFinals { return nil }
        if containsAny(words, sentence, ["game", "match", "final", "finals", "playoff", "playoffs", "derby", "spiel", "finale", "tryout", "tryouts", "probetraining"]) { return .game }
        return nil
    }

    static func mentionsPain(_ sentence: String, _ words: [String]) -> Bool {
        containsAny(words, sentence, ["hurt", "hurts", "hurting", "pain", "painful", "injured", "injury", "sprained", "twisted", "pulled", "strained", "aches", "aching",
                                       "tut weh", "schmerz", "schmerzen", "schmerzt", "verletzt", "verletzung", "zwickt", "verstaucht", "gezerrt", "umgeknickt", "hit my head", "kopf gestoßen"])
    }

    static func painAreas(_ words: [String], _ sentence: String) -> [String] {
        areaWords.filter { containsAny(words, sentence, $0.0) }.map(\.1)
    }

    static func painLevel(_ sentence: String) -> String {
        let little = ["a bit", "a little", "slightly", "slight", "bit sore", "leicht", "etwas", "bisschen", "ein wenig", "zwickt"]
        let lot = ["really", "a lot", "very", "badly", "can't walk", "cannot walk", "stark", "sehr", "extrem", "kann nicht laufen"]
        if lot.contains(where: sentence.contains) { return "lot" }
        if little.contains(where: sentence.contains) { return "little" }
        return "some"
    }

    /// "vs Central", "against the Hawks", "gegen Bayern" → "vs. Central".
    static func opponent(_ sentence: String) -> String? {
        for marker in ["against ", "vs. ", "vs ", "versus ", "gegen "] {
            guard let range = sentence.range(of: marker) else { continue }
            let rest = sentence[range.upperBound...]
            let stop = ["on", "at", "this", "next", "tomorrow", "today", "am", "um", "morgen", "heute", "nächsten", "nächste", "and", "und"]
            var name: [String] = []
            for word in rest.split(separator: " ").map(String.init) {
                let clean = word.trimmingCharacters(in: .punctuationCharacters)
                if clean.isEmpty || stop.contains(clean) || clean.first?.isNumber == true || name.count == 3 { break }
                name.append(clean)
            }
            if !name.isEmpty { return "vs. " + name.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ") }
        }
        return nil
    }

    static func forDays(_ sentence: String) -> Int? {
        let patterns = [#"for (\d+) days?"#, #"(\d+) days?"#, #"für (\d+) tage?"#, #"(\d+) tage?"#]
        for pattern in patterns {
            if let match = sentence.range(of: pattern, options: .regularExpression) {
                let digits = sentence[match].filter(\.isNumber)
                if let days = Int(digits), (1...30).contains(days) { return days }
            }
        }
        if sentence.contains("for a week") || sentence.contains("eine woche") { return 7 }
        return nil
    }

    // MARK: Dates and times

    struct FoundDate { let day: Date }

    static let weekdays: [(names: [String], number: Int)] = [
        (["sunday", "sun", "sonntag", "so"], 1), (["monday", "mon", "montag", "mo"], 2), (["tuesday", "tue", "tues", "dienstag", "di"], 3),
        (["wednesday", "wed", "mittwoch", "mi"], 4), (["thursday", "thu", "thurs", "donnerstag", "do"], 5),
        (["friday", "fri", "freitag", "fr"], 6), (["saturday", "sat", "samstag", "sa", "sonnabend"], 7),
    ]

    static let months: [(names: [String], number: Int)] = [
        (["jan", "january", "januar", "jänner"], 1), (["feb", "february", "februar"], 2), (["mar", "march", "märz"], 3),
        (["apr", "april"], 4), (["may", "mai"], 5), (["jun", "june", "juni"], 6), (["jul", "july", "juli"], 7),
        (["aug", "august"], 8), (["sep", "sept", "september"], 9), (["oct", "october", "okt", "oktober"], 10),
        (["nov", "november"], 11), (["dec", "december", "dez", "dezember"], 12),
    ]

    static func findDate(_ sentence: String, words: [String], now: Date, calendar: Calendar, monthFirst: Bool = false) -> FoundDate? {
        let today = calendar.startOfDay(for: now)
        func add(_ days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: today) ?? today }
        if containsAny(words, sentence, ["day after tomorrow", "übermorgen"]) { return FoundDate(day: add(2)) }
        // "heute morgen" is this morning; "morgen" alone is tomorrow.
        if containsAny(words, sentence, ["today", "tonight", "heute"]) { return FoundDate(day: today) }
        if containsAny(words, sentence, ["tomorrow", "morgen"]) { return FoundDate(day: add(1)) }
        if let match = sentence.range(of: #"in (\d+) (days?|tagen)"#, options: .regularExpression),
           let days = Int(sentence[match].filter(\.isNumber)), days <= 120 {
            return FoundDate(day: add(days))
        }
        // 24.11. / 24/11 / 24.11.2026 — and 11/24 where the month comes first.
        if let match = sentence.range(of: #"\b(\d{1,2})[./](\d{1,2})(?:[./](\d{2,4}))?"#, options: .regularExpression) {
            let text = sentence[match]
            let parts = text.split(whereSeparator: { $0 == "." || $0 == "/" }).compactMap { Int($0) }
            if parts.count >= 2 {
                // Dots are always day first (24.11.); a slash follows the locale,
                // unless one of the numbers can only be the day (11/24, 24/11).
                var swap = monthFirst && text.contains("/")
                if parts[0] > 12 { swap = false } else if parts[1] > 12 { swap = true }
                let (d, m) = swap ? (parts[1], parts[0]) : (parts[0], parts[1])
                if let date = upcoming(day: d, month: m, year: parts.count > 2 ? parts[2] : nil, now: today, calendar: calendar) {
                    return FoundDate(day: date)
                }
            }
        }
        // "24 nov", "nov 24", "24th of november", "am 24. november"
        for (names, month) in months {
            for name in names where words.contains(name) {
                guard let index = words.firstIndex(of: name) else { continue }
                let neighbours = [index - 1, index + 1, index - 2].filter { words.indices.contains($0) }
                for n in neighbours {
                    let digits = words[n].filter(\.isNumber)
                    if let day = Int(digits), (1...31).contains(day),
                       let date = upcoming(day: day, month: month, year: nil, now: today, calendar: calendar) {
                        return FoundDate(day: date)
                    }
                }
            }
        }
        // "first week of December", "Anfang Dezember", "mid January", "Ende März", "in December".
        if let date = monthPhrase(sentence, words: words, today: today, calendar: calendar) { return FoundDate(day: date) }
        // "After the holidays / Christmas / New Year", "nach den Ferien": the first school week of January.
        let afterWinter = ["after the holidays", "after the christmas", "after christmas", "after new year", "after the new year", "after the winter break",
                           "nach den ferien", "nach den weihnachtsferien", "nach weihnachten", "nach neujahr", "nach silvester"]
        if afterWinter.contains(where: sentence.contains) {
            let month = calendar.component(.month, from: today)
            if month >= 10 || month == 1, let date = upcoming(day: 7, month: 1, year: nil, now: today, calendar: calendar) {
                return FoundDate(day: date)
            }
        }
        if containsAny(words, sentence, ["christmas", "weihnachten"]),
           let date = upcoming(day: 24, month: 12, year: nil, now: today, calendar: calendar) {
            return FoundDate(day: date)
        }
        // "next week" (exams): the Monday of next week.
        if containsAny(words, sentence, ["next week", "nächste woche", "nächsten woche", "kommende woche"]) {
            let start = calendar.dateInterval(of: .weekOfYear, for: add(7))?.start ?? add(7)
            return FoundDate(day: start)
        }
        if containsAny(words, sentence, ["this week", "diese woche"]) { return FoundDate(day: today) }
        if containsAny(words, sentence, ["weekend", "wochenende"]) {
            return FoundDate(day: nextWeekday(7, after: today, skipThisWeek: containsAny(words, sentence, ["next weekend", "nächstes wochenende", "nächsten wochenende"]), calendar: calendar))
        }
        // Weekday names ("on saturday", "next friday", "am samstag").
        let skip = containsAny(words, sentence, ["next", "nächsten", "nächste", "nächstes", "kommenden"])
        for (names, number) in weekdays {
            // Two-letter German abbreviations are too ambiguous unless followed by a dot ("Sa.").
            // "sat" and "sun" are words too ("I sat out", "in the sun"): only after
            // on / this / next / until, or with a dot ("Sat.").
            let usable = names.filter { name in
                if name.count <= 2 { return sentence.contains("\(name).") }
                if name == "sat" || name == "sun" {
                    return sentence.contains("\(name).") || ["on", "this", "next", "until", "till", "by"].contains { sentence.contains("\($0) \(name)") }
                }
                return true
            }
            if usable.contains(where: { words.contains($0) }) {
                return FoundDate(day: nextWeekday(number, after: today, skipThisWeek: skip, calendar: calendar))
            }
        }
        return nil
    }

    /// A month with a "which part" word: "first week of december" → 1 Dec,
    /// "mid january" → 15 Jan, "end of march" / "ende märz" → last week,
    /// "in december" / "im dezember" → 1 Dec. Only full month names
    /// ("may" alone is too often the verb).
    static func monthPhrase(_ sentence: String, words: [String], today: Date, calendar: Calendar) -> Date? {
        for (names, month) in months {
            for name in names where name.count >= 4 || name == "mai" {
                guard words.contains(name) else { continue }
                let parts: [([String], Int)] = [
                    (["first week of", "1st week of", "beginning of", "start of", "early", "anfang", "erste woche im", "ersten woche im", "erste \(name)woche", "ersten \(name)woche", "anfang des"], 1),
                    (["second week of", "2nd week of", "zweite woche im", "zweiten woche im"], 8),
                    (["mid", "mid-", "middle of", "mitte", "third week of", "3rd week of", "dritte woche im", "dritten woche im"], 15),
                    (["last week of", "fourth week of", "end of", "late", "ende", "letzte woche im", "letzten woche im"], 22),
                ]
                var day: Int?
                for (markers, value) in parts where markers.contains(where: { sentence.contains("\($0) \(name)") || sentence.contains("\($0)\(name)") }) {
                    day = value
                    break
                }
                if day == nil && name != "mai" && ["in \(name)", "im \(name)", "from \(name)", "ab \(name)", "starting \(name)", "until \(name)", "bis \(name)"].contains(where: sentence.contains) { day = 1 }
                if day == nil && name == "mai" && sentence.contains("im mai") { day = 1 }
                guard let start = day else { continue }
                // A month already under way ("end of November" in November) is this year's.
                let thisYear = calendar.component(.year, from: today)
                if let date = calendar.date(from: DateComponents(year: thisYear, month: month, day: start)),
                   calendar.component(.month, from: today) == month, date >= today || start > 1 { return max(date, today) }
                return upcoming(day: start, month: month, year: nil, now: today, calendar: calendar)
            }
        }
        return nil
    }

    /// The next such weekday from today (today counts); "next Friday" means the one after this week's.
    static func nextWeekday(_ weekday: Int, after today: Date, skipThisWeek: Bool, calendar: Calendar) -> Date {
        let current = calendar.component(.weekday, from: today)
        var ahead = (weekday - current + 7) % 7
        if skipThisWeek { ahead += 7 }
        return calendar.date(byAdding: .day, value: ahead, to: today) ?? today
    }

    static func upcoming(day: Int, month: Int, year: Int?, now: Date, calendar: Calendar) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let thisYear = calendar.component(.year, from: now)
        var full = year.map { $0 < 100 ? 2000 + $0 : $0 } ?? thisYear
        guard var date = calendar.date(from: DateComponents(year: full, month: month, day: day)) else { return nil }
        if year == nil && date < now {
            full += 1
            date = calendar.date(from: DateComponents(year: full, month: month, day: day)) ?? date
        }
        return date
    }

    /// "at 4pm", "at 16:30", "um 16 uhr", "um 9:30" → (hour, minute).
    static func findTime(_ sentence: String) -> (Int, Int)? {
        if let match = sentence.range(of: #"(\bat\b|\bum\b|@)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm|uhr)?\b"#, options: .regularExpression) {
            let text = String(sentence[match])
            let numbers = text.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
            guard var hour = numbers.first, hour <= 23 else { return nil }
            let minute = numbers.count > 1 ? numbers[1] : 0
            if text.hasSuffix("pm"), hour < 12 { hour += 12 }
            if text.hasSuffix("am"), hour == 12 { hour = 0 }
            // "at 4" with no am/pm in the afternoon range of sport: 1–7 means pm.
            if !text.hasSuffix("am") && !text.hasSuffix("pm") && !text.hasSuffix("uhr") && (1...7).contains(hour) { hour += 12 }
            guard minute < 60 else { return nil }
            return (hour, minute)
        }
        return nil
    }

    static func dedupe(_ proposals: [Proposal]) -> [Proposal] {
        var out: [Proposal] = []
        for p in proposals where !out.contains(p) {
            // "Practice was brutal. Tons of sprints…": one report for the day.
            if case .training(let day, let qualities, let level) = p,
               let index = out.firstIndex(where: { if case .training(let d, _, _) = $0 { d == day } else { false } }),
               case .training(_, let earlier, let earlierLevel) = out[index] {
                var merged = earlier
                for q in qualities where !merged.contains(q) { merged.append(q) }
                if max(level, earlierLevel) >= 2 { merged.removeAll { $0 == "lowRunning" } }
                out[index] = .training(day: day, qualities: merged, level: max(level, earlierLevel))
                continue
            }
            // Fatigue for the same day and regions: the stronger word.
            if case .fatigue(let day, let regions, let level) = p,
               let index = out.firstIndex(where: { if case .fatigue(let d, let r, _) = $0 { d == day && r == regions } else { false } }),
               case .fatigue(_, _, let earlier) = out[index] {
                out[index] = .fatigue(day: day, regions: regions, level: max(level, earlier))
                continue
            }
            out.append(p)
        }
        return out
    }
}
