import Foundation

/// The Mindset level: a 2-minute evening reflection ("one win, one
/// lesson") and the pre-game routines (breathing, visualization). Everything is kept in
/// UserDefaults under `mindset.` so it is backed up with the athlete's
/// settings (CloudSync) and comes back on a new phone.

/// One evening's reflection.
public struct Reflection: Codable, Sendable, Equatable, Identifiable {
    /// The calendar day, YYYY-MM-DD.
    public var day: String
    public var win: String
    public var lesson: String
    /// 1 (rough day) … 5 (great day), optional.
    public var feeling: Int?
    // The evening check-in (V3): mostly taps, one optional sentence.
    /// How hard was today: 1 easy … 4 very hard.
    public var hardness: Int?
    /// How the body feels: 1 fresh … 4 very sore.
    public var body: Int?
    /// How practice went: 1 tough … 4 great (nil: no practice).
    public var practice: Int?
    public var wentWell: [String]?
    public var needsWork: [String]?
    /// "What did you learn today?" — the one optional written answer.
    public var learned: String?
    public var id: String { day }
}

/// Tap answers for the evening check-in.
public enum EveningOptions {
    public static let hardness = ["Easy", "Normal", "Hard", "Very hard"]
    /// 4 is "Something hurt": the evening says to tell a coach or parent.
    public static let body = ["Good", "Tired", "Very tired", "Something hurt"]
    public static let practice = ["Poor", "Okay", "Good", "Great"]
    public static let areas = ["Effort", "Focus", "Technique", "Speed", "Strength", "Decisions", "Communication", "Confidence", "Recovery"]
}

public enum MindsetRoutine: String, Codable, Sendable {
    case breathing, visualization
}

/// Where the Mindset things live (backed up under `mindset.`).
public enum MindsetStore {
    static let reflectionsKey = "mindset.reflections"
    static let routinesKey = "mindset.routines"
    static let cueWordKey = "mindset.cueWord"

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // Reflections (the last 120 days are kept).

    public static var reflections: [Reflection] {
        get { load([Reflection].self, reflectionsKey) ?? [] }
        set { save(Array(newValue.sorted { $0.day > $1.day }.prefix(120)), reflectionsKey) }
    }

    public static func reflection(on date: Date, calendar: Calendar = .current) -> Reflection? {
        let key = dayKey(date, calendar: calendar)
        return reflections.first { $0.day == key }
    }

    public static func saveReflection(win: String, lesson: String, feeling: Int?, on date: Date = .now, calendar: Calendar = .current) {
        let key = dayKey(date, calendar: calendar)
        var all = reflections.filter { $0.day != key }
        all.append(Reflection(day: key, win: win, lesson: lesson, feeling: feeling))
        reflections = all
    }

    /// Saves the evening check-in. "What went well" and "what needs work"
    /// also become the win and lesson the Mindset page shows.
    public static func saveEvening(hardness: Int?, body: Int?, practice: Int?, wentWell: [String], needsWork: [String],
                                   learned: String?, on date: Date = .now, calendar: Calendar = .current) {
        let key = dayKey(date, calendar: calendar)
        var all = reflections.filter { $0.day != key }
        let note = learned?.trimmingCharacters(in: .whitespacesAndNewlines)
        all.append(Reflection(
            day: key,
            win: wentWell.isEmpty ? (note ?? "") : wentWell.joined(separator: ", "),
            lesson: needsWork.isEmpty ? "" : needsWork.joined(separator: ", "),
            feeling: practice.map { $0 + 1 }, hardness: hardness, body: body, practice: practice,
            wentWell: wentWell, needsWork: needsWork, learned: (note?.isEmpty ?? true) ? nil : note
        ))
        reflections = all
    }

    /// Last evening's answers, for today's plan (ADAPT).
    public static func yesterdaySignal(now: Date = .now, calendar: Calendar = .current) -> EveningSignal? {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
              let reflection = reflection(on: yesterday, calendar: calendar),
              reflection.hardness != nil || reflection.body != nil else { return nil }
        return EveningSignal(hardness: reflection.hardness, body: reflection.body)
    }

    /// Reflections in the week containing `date`.
    public static func reflectionDays(inWeekOf date: Date, calendar: Calendar = .current) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return 0 }
        let keys = Set((0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }.map { dayKey($0, calendar: calendar) })
        return reflections.filter { keys.contains($0.day) }.count
    }

    // Pre-game routines.

    private static var routineLog: [String: [String]] {
        get { load([String: [String]].self, routinesKey) ?? [:] }
        set {
            let kept = newValue.keys.sorted().suffix(60)
            save(newValue.filter { kept.contains($0.key) }, routinesKey)
        }
    }

    public static func logRoutine(_ routine: MindsetRoutine, on date: Date = .now, calendar: Calendar = .current) {
        var all = routineLog
        all[dayKey(date, calendar: calendar), default: []].append(routine.rawValue)
        routineLog = all
    }

    public static func routines(inWeekOf date: Date, calendar: Calendar = .current) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return 0 }
        let keys = Set((0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }.map { dayKey($0, calendar: calendar) })
        return routineLog.filter { keys.contains($0.key) }.reduce(0) { $0 + $1.value.count }
    }

    /// The word the athlete says to reset after a mistake.
    public static var cueWord: String {
        get { UserDefaults.standard.string(forKey: cueWordKey) ?? "Next" }
        set { UserDefaults.standard.set(newValue, forKey: cueWordKey) }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func save<T: Encodable>(_ value: T, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }
}

// MARK: - Pre-game routines

/// Guided breathing. "Calm" (in 4, out 6: a long exhale slows the heart and
/// settles nerves) for before a game; "Focus" (box breathing, 4-4-4-4) to
/// lock in.
public enum BreathingPattern: String, CaseIterable, Sendable, Identifiable {
    case calm, focus

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .calm: "Calm down"
        case .focus: "Lock in"
        }
    }

    public var explanation: String {
        switch self {
        case .calm: "Breathe in for 4, out slowly for 6. The long breath out slows your heart and settles nerves."
        case .focus: "Box breathing: in 4, hold 4, out 4, hold 4. Used by athletes to get calm and sharp at the same time."
        }
    }

    /// (what to do, seconds, lungs filling up?) for one breath.
    public var phases: [(label: String, seconds: Double, expand: Bool)] {
        switch self {
        case .calm: [("Breathe in", 4, true), ("Breathe out slowly", 6, false)]
        case .focus: [("Breathe in", 4, true), ("Hold", 4, true), ("Breathe out", 4, false), ("Hold", 4, false)]
        }
    }

    public var cycleSeconds: Double { phases.reduce(0) { $0 + $1.seconds } }

    /// The phase at `elapsed` seconds into the exercise.
    public func phase(at elapsed: Double) -> (index: Int, label: String, progress: Double, expand: Bool) {
        var t = elapsed.truncatingRemainder(dividingBy: cycleSeconds)
        for (index, phase) in phases.enumerated() {
            if t < phase.seconds { return (index, phase.label, t / phase.seconds, phase.expand) }
            t -= phase.seconds
        }
        let last = phases[phases.count - 1]
        return (phases.count - 1, last.label, 1, last.expand)
    }
}

/// The game-day visualization, step by step.
public struct VisualizationStep: Sendable, Equatable {
    public let title: String
    public let text: String
    public let seconds: Int
}

public enum GameDayVisualization {
    public static func steps(sportName: String, cueWord: String) -> [VisualizationStep] {
        let place = sportName.isEmpty ? "where you play" : "where you play \(sportName.lowercased())"
        return [
            VisualizationStep(title: "Get comfortable", text: "Sit or lie down somewhere quiet. Close your eyes. Take three slow breaths, longer out than in.", seconds: 25),
            VisualizationStep(title: "See the place", text: "Picture \(place): the lights, the sounds, the smell, your teammates, the crowd. Make it as real as you can.", seconds: 40),
            VisualizationStep(title: "Your warm-up", text: "Feel yourself warming up: loose, quick, strong. Your body is ready.", seconds: 30),
            VisualizationStep(title: "Your first three plays", text: "See yourself doing your first three actions well — through your own eyes, at real speed. Feel the ball, the ground, your breath.", seconds: 60),
            VisualizationStep(title: "A mistake, and your reset", text: "Now something goes wrong. See it. Take one breath, say \"\(cueWord)\" in your head, and see yourself doing the very next play well.", seconds: 45),
            VisualizationStep(title: "Your best moment", text: "Picture the play you want to make today. See it, feel it, hear it. Enjoy it.", seconds: 40),
            VisualizationStep(title: "Ready", text: "Take one last deep breath. Say \"\(cueWord)\". Open your eyes — you've already played it once. Go play.", seconds: 15),
        ]
    }
}
