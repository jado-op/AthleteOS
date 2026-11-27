import SwiftUI

/// What the athlete answered about practice on Home (`PracticeRoutine`).
@MainActor
enum PracticeAnswers {
    static let answeredKey = "schedule.practiceAsked"
    static let declinedKey = "schedule.routineDeclinedUntil"

    static func answered(_ day: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: answeredKey) ?? []).contains(day)
    }

    /// Went: a practice log (how it went stays "not said", 0); didn't go: no
    /// practice that day, so the calendar stops showing it from the schedule.
    static func save(_ answer: PracticeRoutine.Answer, on date: Date, sportSlug: String?, calendar: Calendar = .current) {
        let day = DayKey.of(date, calendar: calendar)
        if let hard = answer.hard {
            if let sportSlug {
                PracticeLogStore.save(PracticeLog(day: day, sportSlug: sportSlug, types: [], hard: hard, went: 0, mood: 0,
                                                  note: "Confirmed the next morning"))
            }
        } else {
            PracticeOverride.set(false, on: day)
        }
        let kept = ((UserDefaults.standard.stringArray(forKey: answeredKey) ?? []) + [day]).suffix(30)
        UserDefaults.standard.set(Array(kept), forKey: answeredKey)
        NotificationCenter.default.post(name: WeeklyPlan.inputsChanged, object: nil)
    }

    static var routineDeclinedUntil: Date? {
        UserDefaults.standard.object(forKey: declinedKey) as? Date
    }

    /// "No": the same offer stays away for six weeks (P16).
    static func declineRoutine(now: Date = .now) {
        UserDefaults.standard.set(now.addingTimeInterval(Double(PracticeRoutine.declineDays) * 86_400), forKey: declinedKey)
    }
}

/// "Yesterday's practice?" — one tap, the next morning only (P17).
struct PracticeAskCard: View {
    let day: Date
    let answer: (PracticeRoutine.Answer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Yesterday's practice", systemImage: "person.3.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            Text("It was on your schedule. How was it?")
                .font(.body)
                .foregroundStyle(AppTheme.ink)
            HStack(spacing: 8) {
                ForEach(PracticeRoutine.Answer.allCases, id: \.self) { option in
                    Button { answer(option) } label: {
                        Text(option.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
    }
}

/// "Practice on Tuesday and Thursday?" — offered from the logs, never assumed (P14).
struct RoutineOfferCard: View {
    let weekdays: Set<Int>
    let decide: (Bool) -> Void
    let adjust: () -> Void

    var body: some View {
        AuraCard(.body, focus: UnitPoint(x: 0.85, y: 0.2), radius: 180) {
            VStack(alignment: .leading, spacing: 14) {
                Headline([.icon("person.3.fill"), .strong(" Practice on \(PracticeRoutine.names(weekdays))?"),
                          .soft(" You've logged it there most weeks.")], size: 24)
                Text("Say yes and your gym days plan around it.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink.opacity(0.75))
                HStack(spacing: 8) {
                    Button("Yes") { decide(true) }
                        .buttonStyle(.primary)
                    Button("Not quite") { adjust() }
                        .buttonStyle(.secondary)
                    Button("No") { decide(false) }
                        .buttonStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
