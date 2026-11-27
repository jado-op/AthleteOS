import Foundation

/// Talking to AthleteOS mid-workout (owner, 2026-11-27: "talk to it mid
/// workout"): hands full, the phone on the floor, the athlete says what they
/// would tell a coach. The words are recognised on the phone (never sent
/// anywhere) and read here into one of a few commands. Pain always wins: a
/// sentence that mentions pain is read as pain, whatever else it says.
public enum WorkoutVoiceCommand: Equatable, Sendable {
    /// "That was heavy", "too hard", "lighter".
    case lighter
    /// "Too easy", "heavier", "more weight".
    case heavier
    /// "Two more", "one more set".
    case moreSets(Int)
    /// "Skip", "next exercise".
    case skip
    /// "Done", "set done", "log it".
    case logSet
    /// "My knee hurts": stop that exercise and get it checked (never a diagnosis).
    case pain(PainArea)

    /// What the coach-like reply says on screen, so the athlete sees it was heard.
    public var heard: String {
        switch self {
        case .lighter: "Lighter for the next set"
        case .heavier: "A step up for the next set"
        case .moreSets(let n): n == 1 ? "One more set" : "\(n) more sets"
        case .skip: "Skipped"
        case .logSet: "Set logged"
        case .pain(let area): area == .other ? "Pain: stop this exercise" : "\(area.title) pain: stop this exercise"
        }
    }

    /// The newest command in what was just said, or nil. `text` is the
    /// newest stretch of speech only (the listener cuts what it already used).
    public static func parse(_ text: String) -> WorkoutVoiceCommand? {
        let lower = " " + text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ") + " "
        func has(_ phrases: [String]) -> Bool { phrases.contains { lower.contains(" \($0) ") } }

        // Safety first: any pain word, with the body part when there is one.
        if has(["pain", "hurts", "hurt", "hurting", "painful", "injured", "tweaked", "pulled", "schmerz", "schmerzen", "tut weh", "weh", "verletzt", "gezerrt"])
            || (has(["ouch", "aua"]) && area(in: lower) != nil) {
            return .pain(area(in: lower) ?? .other)
        }
        if has(["skip", "skip it", "skip this", "next exercise", "überspringen", "nächste übung"]) { return .skip }
        if let n = more(in: lower) { return .moreSets(n) }
        if has(["too heavy", "that was heavy", "was heavy", "so heavy", "really heavy", "heavy", "too hard", "lighter", "less weight",
                "go lighter", "zu schwer", "schwer", "leichter", "weniger gewicht"]) {
            return .lighter
        }
        if has(["too easy", "too light", "easy", "heavier", "more weight", "go heavier", "zu leicht", "leicht", "schwerer", "mehr gewicht"]) {
            return .heavier
        }
        if has(["done", "set done", "log it", "log set", "finished", "fertig", "satz fertig", "geschafft"]) { return .logSet }
        return nil
    }

    /// "two more", "one more set", "noch zwei", "noch einen satz".
    static func more(in lower: String) -> Int? {
        let numbers: [(String, Int)] = [("one", 1), ("two", 2), ("three", 3), ("1", 1), ("2", 2), ("3", 3),
                                        ("einen", 1), ("eins", 1), ("ein", 1), ("zwei", 2), ("drei", 3)]
        for (word, n) in numbers {
            if lower.contains(" \(word) more ") || lower.contains(" noch \(word) ") { return n }
        }
        if lower.contains(" one more ") || lower.contains(" another set ") || lower.contains(" another one ")
            || lower.contains(" noch mal ") || lower.contains(" nochmal ") { return 1 }
        return nil
    }

    /// The body part named, if any (EN + DE).
    static func area(in lower: String) -> PainArea? {
        let words: [(PainArea, [String])] = [
            (.head, ["head", "kopf", "dizzy", "schwindelig"]),
            (.neck, ["neck", "nacken", "hals"]),
            (.shoulder, ["shoulder", "shoulders", "schulter"]),
            (.chest, ["chest", "brust"]),
            (.arm, ["arm", "arms", "elbow", "wrist", "hand", "ellbogen", "handgelenk"]),
            (.back, ["back", "lower back", "rücken", "kreuz"]),
            (.core, ["stomach", "side", "abs", "bauch"]),
            (.hip, ["hip", "groin", "hüfte", "leiste"]),
            (.knee, ["knee", "knees", "knie"]),
            (.ankle, ["ankle", "foot", "feet", "achilles", "knöchel", "fuß", "fuss", "sprunggelenk"]),
            (.leg, ["leg", "thigh", "calf", "hamstring", "quad", "bein", "oberschenkel", "wade"]),
        ]
        for (area, names) in words where names.contains(where: { lower.contains(" \($0) ") }) { return area }
        return nil
    }
}
