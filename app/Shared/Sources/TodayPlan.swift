import Foundation

/// Home's answer to "what do I do now?" (docs/CLARITY-PLAN.md): today as a
/// short numbered plan — check-in, the game or practice, the workout, a
/// lesson, the reflection — and the one step that is next. Rules only; Home
/// draws it (HomeView.swift).
public struct TodayPlan: Sendable, Equatable {
    public enum Step: String, Sendable, CaseIterable {
        case checkIn, game, practice, workout, rest, lesson, reflection
    }

    /// `info`: part of the day but nothing to tick off (a rest day).
    public enum RowState: String, Sendable {
        case done, now, open, info
    }

    public struct Row: Sendable, Equatable, Identifiable {
        public let step: Step
        public let state: RowState
        /// Its place among the steps that can be done (a rest day has none).
        public let number: Int?
        public var id: String { step.rawValue }
    }

    /// Why nothing needs doing right now.
    public enum Waiting: String, Sendable {
        /// Team practice is still to come, or on.
        case practice
        case restDay
        /// Sick: no training today.
        case recover
        /// The day's work is done; the reflection waits for the evening.
        case reflectTonight
        /// Everything is done, the reflection too.
        case clear
    }

    public enum Next: Sendable, Equatable {
        case checkIn, game, workout, lesson, reflection
        case waiting(Waiting)
        case dayComplete, sleep

        /// One word per state, so Home can tell when it changed.
        public var key: String {
            switch self {
            case .checkIn: "checkIn"
            case .game: "game"
            case .workout: "workout"
            case .lesson: "lesson"
            case .reflection: "reflection"
            case .waiting(let reason): "waiting-\(reason.rawValue)"
            case .dayComplete: "dayComplete"
            case .sleep: "sleep"
            }
        }
    }

    public enum FixedKind: String, Sendable {
        case game, practice
    }

    /// The day's fixed point — a game, or team practice — in minutes after
    /// midnight where the athlete told us.
    public struct FixedPoint: Sendable, Equatable {
        public let kind: FixedKind
        public let start: Int?
        public let end: Int?

        public init(kind: FixedKind, start: Int?, end: Int? = nil) {
            self.kind = kind
            self.start = start
            self.end = end
        }

        /// A game without an end takes two hours, practice an hour and a
        /// half; without any time it counts as over once it is evening.
        public func isOver(at minute: Int) -> Bool {
            if let end { return minute >= end }
            if let start { return minute >= start + (kind == .game ? 120 : 90) }
            return minute >= TodayPlan.eveningStart
        }

        public func hasBegun(at minute: Int) -> Bool {
            if let start { return minute >= start }
            return isOver(at: minute)
        }
    }

    public struct Input: Sendable, Equatable {
        /// Minutes after midnight, now.
        public var minute: Int
        public var checkedIn: Bool
        public var reflected: Bool
        public var learned: Bool
        public var lessonAvailable: Bool
        public var fixed: FixedPoint?
        public var workoutPlanned: Bool
        public var workoutDone: Bool
        public var practiceLogged: Bool
        public var sick: Bool

        public init(minute: Int, checkedIn: Bool = false, reflected: Bool = false, learned: Bool = false, lessonAvailable: Bool = true,
                    fixed: FixedPoint? = nil, workoutPlanned: Bool = false, workoutDone: Bool = false, practiceLogged: Bool = false,
                    sick: Bool = false) {
            self.minute = minute
            self.checkedIn = checkedIn
            self.reflected = reflected
            self.learned = learned
            self.lessonAvailable = lessonAvailable
            self.fixed = fixed
            self.workoutPlanned = workoutPlanned
            self.workoutDone = workoutDone
            self.practiceLogged = practiceLogged
            self.sick = sick
        }
    }

    public let rows: [Row]
    public let next: Next

    /// The steps that can be ticked off, and how many are.
    public var total: Int { rows.filter { $0.state != .info }.count }
    public var doneCount: Int { rows.filter { $0.state == .done }.count }

    /// The parts of the day, as Home's light has them (DayPhase).
    public static let nightEnd = 5 * 60
    public static let eveningStart = 17 * 60 + 30
    /// From here on a workout is no longer the next step: the evening is for winding down.
    public static let workoutCutoff = 21 * 60

    public static func make(_ input: Input) -> TodayPlan {
        let next = nextStep(input)
        var steps: [(step: Step, state: RowState)] = []

        steps.append((.checkIn, input.checkedIn ? .done : next == .checkIn ? .now : .open))
        if let fixed = input.fixed {
            switch fixed.kind {
            case .game:
                steps.append((.game, fixed.isOver(at: input.minute) ? .done : next == .game ? .now : .open))
            case .practice:
                let done = input.practiceLogged || fixed.isOver(at: input.minute)
                steps.append((.practice, done ? .done : next == .waiting(.practice) ? .now : .open))
            }
        }
        if input.workoutPlanned || input.workoutDone {
            steps.append((.workout, input.workoutDone ? .done : next == .workout ? .now : .open))
        } else if input.fixed == nil {
            steps.append((.rest, .info))
        }
        if input.lessonAvailable || input.learned {
            steps.append((.lesson, input.learned ? .done : next == .lesson ? .now : .open))
        }
        steps.append((.reflection, input.reflected ? .done : next == .reflection ? .now : .open))

        var number = 0
        let rows = steps.map { entry -> Row in
            if entry.state == .info { return Row(step: entry.step, state: entry.state, number: nil) }
            number += 1
            return Row(step: entry.step, state: entry.state, number: number)
        }
        return TodayPlan(rows: rows, next: next)
    }

    private static func nextStep(_ input: Input) -> Next {
        let minute = input.minute
        if minute < nightEnd {
            return input.reflected || input.workoutDone ? .dayComplete : .sleep
        }
        let evening = minute >= eveningStart
        if evening, input.reflected { return .dayComplete }
        if !input.checkedIn, !evening { return .checkIn }

        let fixedOver = input.fixed.map { $0.isOver(at: minute) } ?? true
        if let fixed = input.fixed, fixed.kind == .game, !fixedOver { return .game }

        // After practice when its time is known; any time when it isn't.
        let timeUnknown = input.fixed.map { $0.start == nil && $0.end == nil } ?? false
        if input.workoutPlanned, !input.workoutDone, fixedOver || timeUnknown, minute < workoutCutoff { return .workout }
        if evening, fixedOver { return .reflection }
        if input.lessonAvailable, !input.learned { return .lesson }

        if input.reflected { return .waiting(.clear) }
        if input.sick { return .waiting(.recover) }
        if input.fixed != nil, !fixedOver { return .waiting(.practice) }
        if input.fixed == nil, !input.workoutPlanned, !input.workoutDone { return .waiting(.restDay) }
        return .waiting(.reflectTonight)
    }
}
