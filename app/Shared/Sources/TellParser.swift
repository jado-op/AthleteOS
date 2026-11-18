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
        /// Development goals (Struggle raw values), most important first.
        case goals([String])
    }

    public enum CompetitionWord: String, Sendable { case game, tournament, meet }

    public struct Result: Sendable, Equatable {
        public var proposals: [Proposal]
        /// Something worrying was mentioned (head, sharp pain): show the safety line.
        public var safety: String?
    }

    public static func parse(_ text: String, now: Date = .now, calendar: Calendar = .current) -> Result {
        let lower = text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
        var proposals: [Proposal] = []
        var safety: String?
        // Sentences end at . ! ? ; followed by a space or the end — "24.11." stays one date.
        let marked = lower.replacingOccurrences(of: #"[.!?;]+(\s+|$)"#, with: "\n", options: .regularExpression)
        let sentences = marked.split(separator: "\n").map(String.init)
        var goals: [String] = []

        for sentence in sentences {
            let words = tokens(sentence)
            let date = findDate(sentence, words: words, now: now, calendar: calendar)

            // A competition on a day.
            if let kind = competitionWord(words, sentence), let day = date?.day {
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

            // Exams.
            if containsAny(words, sentence, ["exam", "exams", "midterm", "midterms", "finals week", "prüfung", "prüfungen", "klausur", "klausuren", "schularbeit", "schularbeiten", "abitur", "test at school", "tests at school"]) {
                let day = date?.day ?? now
                proposals.append(.examWeek(day))
            }

            // Sick, travel, holiday.
            if containsAny(words, sentence, ["sick", "ill", "flu", "fever", "a cold", "krank", "erkältet", "erkältung", "fieber", "grippe"]) {
                proposals.append(.dayStatus("sick", from: date?.day ?? calendar.startOfDay(for: now), days: forDays(sentence) ?? 2))
            } else if containsAny(words, sentence, ["travel", "travelling", "traveling", "flight", "flying", "trip", "reise", "reisen", "flug", "fliege", "unterwegs"]) {
                proposals.append(.dayStatus("travel", from: date?.day ?? calendar.startOfDay(for: now), days: forDays(sentence) ?? 1))
            } else if containsAny(words, sentence, ["vacation", "holiday", "holidays", "urlaub", "ferien"]) {
                proposals.append(.dayStatus("holiday", from: date?.day ?? calendar.startOfDay(for: now), days: forDays(sentence) ?? 7))
            }

            // Goals: "I want to get faster", "ich will stärker werden".
            if containsAny(words, sentence, ["want", "wanna", "goal", "goals", "improve", "better", "become", "get", "work", "möchte", "will", "ziel", "ziele", "verbessern", "besser", "werden"]) {
                for (keys, goal) in goalWords where containsAny(words, sentence, keys) && !goals.contains(goal) {
                    goals.append(goal)
                }
            }
        }
        if !goals.isEmpty { proposals.append(.goals(Array(goals.prefix(3)))) }
        return Result(proposals: dedupe(proposals), safety: safety)
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

    static func findDate(_ sentence: String, words: [String], now: Date, calendar: Calendar) -> FoundDate? {
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
        // 24.11. / 24/11 / 24.11.2026
        if let match = sentence.range(of: #"\b(\d{1,2})[./](\d{1,2})(?:[./](\d{2,4}))?"#, options: .regularExpression) {
            let parts = sentence[match].split(whereSeparator: { $0 == "." || $0 == "/" }).compactMap { Int($0) }
            if parts.count >= 2, let date = upcoming(day: parts[0], month: parts[1], year: parts.count > 2 ? parts[2] : nil, now: today, calendar: calendar) {
                return FoundDate(day: date)
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
            let usable = names.filter { $0.count > 2 || sentence.contains("\($0).") }
            if usable.contains(where: { words.contains($0) }) {
                return FoundDate(day: nextWeekday(number, after: today, skipThisWeek: skip, calendar: calendar))
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
        for p in proposals where !out.contains(p) { out.append(p) }
        return out
    }
}
