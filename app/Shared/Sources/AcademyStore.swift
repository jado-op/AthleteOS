import Foundation

/// The athlete's Academy data on this phone. Private to the athlete: it is
/// never part of the parent summary, coach or team data, and its key is
/// outside every CloudSync group (the encrypted backup is a later step).
public enum AcademyStore {
    static let key = "academyTwin.state.v3"
    /// Earlier Academy versions, cleared on first load.
    static let oldKeys = ["academyTwin.state.v1"]

    public static func load(_ defaults: UserDefaults = .standard) -> AcademyState {
        for old in oldKeys where defaults.object(forKey: old) != nil { defaults.removeObject(forKey: old) }
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(AcademyState.self, from: data) else { return AcademyState() }
        return state
    }

    public static func save(_ state: AcademyState, _ defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }

    /// Deletes the twin's data on this phone (interview, reads, performances).
    public static func delete(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    /// The interview answered (or edited): answers replace earlier ones; an
    /// empty answer ("" — a cleared choice or text) removes it. Finishing
    /// also drops any half-way draft.
    public static func answering(_ answers: [String: String], in state: AcademyState, at date: Date) -> AcademyState {
        var next = state
        for (id, value) in answers {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            next.intake[id] = trimmed.isEmpty ? nil : String(trimmed.prefix(freeTextLimit))
        }
        if next.intakeDoneAt == nil { next.intakeDoneAt = date }
        next.intakeDraft = nil
        return next
    }

    /// Longest free-text answer kept (the field stops there too).
    public static let freeTextLimit = 280

    /// A first interview closed before the end: keep the answers so far and
    /// where to pick up, without creating the twin yet. Nothing answered →
    /// no draft. After the first interview, edits are saved with `answering`.
    public static func savingDraft(_ answers: [String: String], at questionID: String?, in state: AcademyState,
                                   date: Date) -> AcademyState {
        var next = state
        guard next.intakeDoneAt == nil else { return state }
        let kept = answers.compactMapValues { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : String(trimmed.prefix(freeTextLimit))
        }
        next.intakeDraft = kept.isEmpty ? nil : IntakeDraft(answers: kept, questionID: questionID, savedAt: date)
        return next
    }

    /// How many of these questions have an answer.
    public static func answeredCount(_ answers: [String: String], of questionIDs: [String]) -> Int {
        questionIDs.filter { !(answers[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }.count
    }

    public static func reading(_ briefingID: String, in state: AcademyState, at date: Date) -> AcademyState {
        var next = state
        if next.read[briefingID] == nil { next.read[briefingID] = date }
        return next
    }

    /// A new performance, or a new result for one with the same name.
    public static func recording(_ name: String, unit: String, higherIsBetter: Bool, value: Double, at date: Date,
                                 in state: AcademyState) -> AcademyState {
        var next = state
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, value.isFinite else { return state }
        if let index = next.performances.firstIndex(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) {
            next.performances[index].entries.append(.init(date: date, value: value))
            next.performances[index].entries.sort { $0.date < $1.date }
        } else {
            next.performances.append(CustomPerformance(name: clean, unit: unit, higherIsBetter: higherIsBetter,
                                                       entries: [.init(date: date, value: value)]))
        }
        return next
    }

    public static func removingPerformance(_ id: String, in state: AcademyState) -> AcademyState {
        var next = state
        next.performances.removeAll { $0.id == id }
        return next
    }
}

/// Privacy-friendly usage events: counted on this phone only (UsageCounts),
/// never uploaded, never with an answer, a reflection text or an identifier.
public enum AcademyEvent: String, CaseIterable, Sendable {
    case twinViewed = "twin_viewed"
    case insightOpened = "insight_opened"
    case lessonCompleted = "lesson_completed"
    case reflectionSubmitted = "reflection_submitted"
    case twinBorn = "twin_born"

    public static func log(_ event: AcademyEvent, _ defaults: UserDefaults = .standard) {
        UsageCounts.count("academy.\(event.rawValue)", defaults)
    }
}

/// Who may read briefings, and how many. The beta is free and unlimited; a
/// limit for free accounts can be switched on here later. Separate from
/// Campus's limit.
public enum AcademyAccess {
    /// nil = unlimited (the beta).
    public static let freeBriefingsPerWeek: Int? = nil

    public static func canOpen(readThisWeek: Int, isPro: Bool, limit: Int? = freeBriefingsPerWeek) -> Bool {
        guard let limit, !isPro else { return true }
        return readThisWeek < limit
    }
}
