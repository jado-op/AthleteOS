import Foundation
#if canImport(FoundationModels) && os(iOS) && !APP_EXTENSION
import FoundationModels
#endif

/// "Tell AthleteOS" with real language understanding: Apple's on-device
/// language model reads what the athlete wrote and lists the changes. The
/// text never leaves the phone. On phones without Apple Intelligence (or with
/// it switched off) `TellParser`'s rules read it instead.
///
/// The model only proposes; everything it returns is checked here (known
/// kinds, real dates near today, known body areas and goals) and the athlete
/// still confirms each change. The rules always run too, so a knock to the
/// head or sharp pain is never missed.
enum TellModelReader {
    static var isAvailable: Bool {
        #if canImport(FoundationModels) && os(iOS) && !APP_EXTENSION
        if #available(iOS 26.0, *) { return SystemLanguageModel.default.isAvailable }
        #endif
        return false
    }

    /// Nil when the model isn't there or couldn't read it (the rules' result stands).
    static func read(_ text: String, now: Date = .now, calendar: Calendar = .current) async -> TellParser.Result? {
        #if canImport(FoundationModels) && os(iOS) && !APP_EXTENSION
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            return await ModelReading.read(text, now: now, calendar: calendar)
        }
        #endif
        return nil
    }

    /// The model's items, checked and turned into proposals. Foundation-only
    /// so the rules for what counts stay in one readable place.
    struct Item {
        var kind: String
        var day: String
        var time: String
        var days: Int
        var areas: [String]
        var level: String
        var goals: [String]
        var opponent: String
        var words: String
    }

    static let kinds = ["game", "tournament", "race", "pain", "headKnock", "examWeek", "sick", "travel", "holiday",
                        "preSeasonStart", "seasonStart", "seasonEnd", "goals", "notUnderstood"]
    static let areas = ["head", "neck", "shoulder", "chest", "arm", "back", "core", "hip", "leg", "knee", "ankle"]
    static let goals = ["acceleration", "maxSpeed", "agility", "strength", "power", "verticalJump", "conditioning", "aerobicFitness",
                        "mobility", "sportSkill", "recovery", "confidence", "focus"]

    static func proposals(from items: [Item], rules: TellParser.Result, now: Date, calendar: Calendar) -> TellParser.Result {
        let today = calendar.startOfDay(for: now)
        let format = DateFormatter()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"
        func day(_ text: String) -> Date? {
            guard let date = format.date(from: text.trimmingCharacters(in: .whitespaces)) else { return nil }
            let start = calendar.startOfDay(for: date)
            // A real day near now: a week back at most, about a year ahead at most.
            guard let earliest = calendar.date(byAdding: .day, value: -7, to: today),
                  let latest = calendar.date(byAdding: .day, value: 400, to: today),
                  start >= earliest, start <= latest else { return nil }
            return start
        }

        var out: [TellParser.Proposal] = []
        var goals: [String] = []
        var unread: [String] = []
        for item in items {
            let when = day(item.day)
            switch item.kind {
            case "game", "tournament", "race":
                guard let date = when else { unread.append(item.words); continue }
                var at = date
                var hasTime = false
                let parts = item.time.split(separator: ":").compactMap { Int($0) }
                if parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]),
                   let timed = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date) {
                    at = timed
                    hasTime = true
                }
                let kind: TellParser.CompetitionWord = item.kind == "game" ? .game : item.kind == "tournament" ? .tournament : .meet
                let name = item.opponent.trimmingCharacters(in: .whitespacesAndNewlines)
                out.append(.competition(date: at, kind: kind, note: name.isEmpty ? nil : "vs. \(name)", hasTime: hasTime))
            case "pain":
                let known = item.areas.filter { areas.contains($0) && $0 != "head" }
                guard !known.isEmpty else { unread.append(item.words); continue }
                out.append(.pain(areas: known, level: ["little", "some", "lot"].contains(item.level) ? item.level : "some"))
            case "headKnock":
                out.append(.headKnock)
            case "examWeek":
                out.append(.examWeek(when ?? today))
            case "sick", "travel", "holiday":
                let fallback = item.kind == "sick" ? 2 : item.kind == "travel" ? 1 : 7
                out.append(.dayStatus(item.kind, from: when ?? today, days: (1...30).contains(item.days) ? item.days : fallback))
            case "preSeasonStart", "seasonStart", "seasonEnd":
                guard let date = when else { unread.append(item.words); continue }
                out.append(.season(item.kind == "preSeasonStart" ? "pre" : item.kind == "seasonStart" ? "in" : "end", from: date))
            case "goals":
                for goal in item.goals where self.goals.contains(goal) && !goals.contains(goal) { goals.append(goal) }
            default:
                if !item.words.isEmpty { unread.append(item.words) }
            }
        }
        if !goals.isEmpty { out.append(.goals(Array(goals.prefix(3)))) }
        // Safety never depends on the model: the rules' head knock and pain warnings stay.
        if rules.proposals.contains(.headKnock), !out.contains(.headKnock) { out.append(.headKnock) }
        var seen: [TellParser.Proposal] = []
        for p in out where !seen.contains(p) { seen.append(p) }
        return TellParser.Result(proposals: seen, safety: rules.safety ?? (seen.contains(.headKnock)
            ? "Hit your head? Stop training and tell an adult. A doctor clears you to play again." : nil),
            unread: unread.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    /// Today and the next three weeks written out, so the model never has to count days.
    static func calendarLines(now: Date, calendar: Calendar) -> String {
        let format = DateFormatter()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "EEEE yyyy-MM-dd"
        let today = calendar.startOfDay(for: now)
        return (0..<21).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today).map { (offset == 0 ? "Today: " : offset == 1 ? "Tomorrow: " : "") + format.string(from: $0) }
        }.joined(separator: "\n")
    }
}

#if canImport(FoundationModels) && os(iOS) && !APP_EXTENSION
@available(iOS 26.0, *)
@Generable
struct TellReadingOutput {
    @Guide(description: "One entry for each separate thing the athlete told you, in the order they said it. Greetings and filler get no entry.")
    var items: [TellReadingItem]
}

@available(iOS 26.0, *)
@Generable
struct TellReadingItem {
    @Guide(description: "One of: game, tournament, race, pain, headKnock, examWeek, sick, travel, holiday, preSeasonStart, seasonStart, seasonEnd, goals, notUnderstood")
    var kind: String
    @Guide(description: "The day it starts or happens as yyyy-MM-dd, worked out from the calendar given. Empty when the athlete gave no day.")
    var day: String
    @Guide(description: "Start time as HH:mm in 24-hour time, only for a game, tournament or race when the athlete said a time. Otherwise empty.")
    var time: String
    @Guide(description: "How many days it lasts (sick, travel, holiday), or 0 when not said.")
    var days: Int
    @Guide(description: "For pain only: body areas from head, neck, shoulder, chest, arm, back, core, hip, leg, knee, ankle. Otherwise empty.")
    var areas: [String]
    @Guide(description: "For pain only: little, some or lot. Otherwise empty.")
    var level: String
    @Guide(description: "For goals only: from acceleration, maxSpeed, agility, strength, power, verticalJump, conditioning, aerobicFitness, mobility, sportSkill, recovery, confidence, focus. Otherwise empty.")
    var goals: [String]
    @Guide(description: "For a game: the opponent's name if said, otherwise empty.")
    var opponent: String
    @Guide(description: "The athlete's own words this entry comes from.")
    var words: String
}

@available(iOS 26.0, *)
enum ModelReading {
    static let instructions = """
    You read short notes a young athlete (13 to 19) writes to their training app, in English or German, \
    and list what the app should change. Only list what the athlete really said; never guess a day they didn't give. \
    Kinds: game, tournament or race = a competition on a day. pain = something hurts (not the head). \
    headKnock = they hit their head or may have a concussion. examWeek = exams or tests at school. \
    sick, travel, holiday = days away from normal training (only when the athlete themselves is sick, travelling or on holiday; \
    "after the holidays" is a time, not a holiday). preSeasonStart = preparation training for the season begins \
    (pre-season, dryland, training camp, Vorbereitung). seasonStart = the competition season itself begins. \
    seasonEnd = the season ends or the off-season begins. goals = what they want to get better at. \
    notUnderstood = anything else they said that the app can't act on; copy their words. \
    Christmas holidays end around 7 January. "First week of" a month starts on its 1st, "mid" on the 15th, "end of" on the 22nd.
    """

    static func read(_ text: String, now: Date, calendar: Calendar) async -> TellParser.Result? {
        let rules = TellParser.parse(text, now: now, calendar: calendar)
        let session = LanguageModelSession(instructions: instructions)
        let prompt = """
        Calendar:
        \(TellModelReader.calendarLines(now: now, calendar: calendar))

        The athlete wrote:
        \(text)
        """
        do {
            let response = try await session.respond(to: prompt, generating: TellReadingOutput.self)
            let items = response.content.items.map {
                TellModelReader.Item(kind: $0.kind, day: $0.day, time: $0.time, days: $0.days, areas: $0.areas, level: $0.level,
                                     goals: $0.goals, opponent: $0.opponent, words: $0.words)
            }
            return TellModelReader.proposals(from: items, rules: rules, now: now, calendar: calendar)
        } catch {
            return nil
        }
    }
}
#endif
