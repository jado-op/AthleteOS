import SwiftData
import SwiftUI

/// "Tell AthleteOS": write what's going on in your own words; the app reads it
/// (TellParser, on the phone) and proposes how to change itself — a
/// competition, a pain report, an exam week, a day status, goals. Nothing
/// changes until the athlete ticks it and taps Apply.
struct TellView: View {
    let athlete: Athlete
    /// For "Plan adjusted": today's decision before and after the change.
    var catalogue: Catalogue = Catalogue()
    var plannedGymDay = false
    var onChanged: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var text = ""
    @State private var skipped: Set<Int> = []
    @State private var applied: [String]?
    /// Today's plan before → after, when the change moved it (nil: unchanged or unknown).
    @State private var adjusted: (before: String, now: String, why: String?)?
    /// Remind the evening before and each morning of days away (on by default: the athlete asked).
    @State private var remind = true
    /// A told workout was saved as training (shown on the done screen).
    @State private var savedWorkout = false
    /// What AthleteOS is using from earlier (shown under the empty editor).
    @State private var remembered: [AthleteContextEvent] = []
    /// What the on-device language model read (nil: the rules' reading shows).
    @State private var modelResult: TellParser.Result?
    @State private var reading = false
    @FocusState private var writing: Bool

    private var result: TellParser.Result { modelResult ?? TellParser.parse(text) }
    private var family: SportFamily { AcademyContent.family(forSport: athlete.activeSport?.sportSlug) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let applied {
                        done(applied)
                    } else {
                        editor
                        proposals
                    }
                }
                .padding(24)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground(.subtle).ignoresSafeArea())
            .navigationTitle("Tell AthleteOS")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(applied == nil ? "Cancel" : "Done") { dismiss() } }
            }
            .onAppear {
                // Said to Siri ("Tell AthleteOS my legs are dead"): the words are already here to confirm.
                if text.isEmpty, let said = IntentRoute.takeTellText() { text = said }
                remembered = AthleteContextStore.remembered()
                writing = true
            }
            .task(id: text) { await readWithModel() }
        }
    }

    /// When the athlete pauses typing, Apple's on-device model reads the whole
    /// text (TellModelReader); until then — and on phones without it — the rules do.
    private func readWithModel() async {
        modelResult = nil
        reading = false
        guard TellModelReader.isAvailable, text.trimmingCharacters(in: .whitespacesAndNewlines).count > 8 else { return }
        try? await Task.sleep(for: .milliseconds(900))
        guard !Task.isCancelled else { return }
        reading = true
        let read = await TellModelReader.read(text)
        guard !Task.isCancelled else { return }
        reading = false
        if let read {
            skipped = []
            modelResult = read
        }
    }

    private var editor: some View {
        // V8: calm — one big question, then a big, quiet place to write.
        VStack(alignment: .leading, spacing: 14) {
            Headline([.strong("What's going on?"), .soft(" Practice, tired legs, games, no gym, time, pain, exams — in your words. The app adjusts.")], size: 30)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("e.g. Practice was brutal, tons of sprints, my legs are cooked. Only 30 minutes tomorrow. Match on Saturday at 4pm.")
                        .font(.title3)
                        .foregroundStyle(AppTheme.mutedText)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                }
                TextField("", text: $text, axis: .vertical)
                    .accessibilityLabel("What's going on")
                    .lineLimit(5...12)
                    .font(.title3)
                    .foregroundStyle(AppTheme.ink)
                    .focused($writing)
                    .onChange(of: text) { skipped = [] }
            }
            .padding(18)
            .frame(minHeight: 170, alignment: .topLeading)
            .glassSurface(cornerRadius: 24)
            HStack(spacing: 8) {
                if reading { ProgressView().controlSize(.small) }
                Text(reading ? "Reading…" : "Read on your phone. Nothing is sent anywhere.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedText)
            }
            if text.isEmpty { starters }
            if text.isEmpty, !remembered.isEmpty { rememberedList }
        }
    }

    /// One tap to start the usual things (Tell is the one place to add anything;
    /// owner, 2026-11-26): the sentence begins, the athlete finishes it.
    private var starters: some View {
        let game = family.event.lowercased()
        let items: [(String, String, String)] = [
            ("figure.strengthtraining.traditional", "Did a workout", "Did a workout today: "),
            ("person.3.fill", "Practice was…", "Practice today was "),
            ("figure.walk", "Legs feel…", "My legs feel "),
            ("sportscourt.fill", "Next \(game)", "\(family.tokens["Event"] ?? "Game") on "),
            ("trophy.fill", "Result", "We "),
            ("bandage.fill", "Something hurts", "Pain in my "),
            ("house.fill", "No gym", "No gym "),
            ("bed.double.fill", "Sick", "I'm sick today"),
        ]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.1) { item in
                    Button {
                        text = item.2
                        writing = true
                    } label: {
                        Label(item.1, systemImage: item.0)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .glassCapsule()
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }

    /// What the app is going by right now, from earlier: told once, used until it
    /// ends — and removable when it's wrong or over.
    private var rememberedList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AthleteOS remembers")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.top, 14)
            ForEach(remembered) { event in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(event.kind == .fatigue ? AuraTone.body.mark : AuraTone.training.mark).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.reported.first ?? "")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(rememberedWhen(event))
                            .font(.caption)
                            .foregroundStyle(AppTheme.mutedText)
                    }
                    Spacer(minLength: 8)
                    Button {
                        AthleteContextStore.remove(event.id)
                        withAnimation { remembered = AthleteContextStore.remembered() }
                        NotificationCenter.default.post(name: WeeklyPlan.inputsChanged, object: nil)
                        onChanged()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(AppTheme.mutedText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Forget: \(event.reported.first ?? "")")
                }
            }
        }
    }

    private func rememberedWhen(_ event: AthleteContextEvent) -> String {
        let told = relative(event.from)
        switch event.kind {
        case .fatigue: return "Told \(told) · asked each morning until it's back to normal"
        case .equipment: return "Until \(day(event.until ?? event.from, time: false))"
        case .time: return relative(event.from).prefix(1).uppercased() + relative(event.from).dropFirst()
        case .exposure: return "Counted \(told) · the plan doesn't repeat it"
        }
    }

    /// The proposals, a span ("holiday Friday until Monday") as one row per
    /// day so any single day can be unticked.
    private func changes(_ proposals: [TellParser.Proposal]) -> [TellParser.Proposal] {
        let calendar = Calendar.current
        func days(_ from: Date, _ count: Int) -> [Date] {
            (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: from)) }
        }
        var out: [TellParser.Proposal] = []
        for proposal in proposals {
            switch proposal {
            case .dayStatus(let status, let from, let count) where count > 1 && count <= 14:
                out += days(from, count).map { TellParser.Proposal.dayStatus(status, from: $0, days: 1) }
            case .noGym(let from, let count) where count > 1 && count <= 14:
                out += days(from, count).map { TellParser.Proposal.noGym(from: $0, days: 1) }
            case .practice(let from, let count, let happening) where count > 1 && count <= 14:
                out += days(from, count).map { TellParser.Proposal.practice(from: $0, days: 1, happening: happening) }
            default:
                out.append(proposal)
            }
        }
        return out
    }

    @ViewBuilder
    private var proposals: some View {
        let parsed = result
        let all = changes(parsed.proposals)
        let chosen = all.enumerated().filter { !skipped.contains($0.offset) }.map(\.element)
        if let safety = parsed.safety {
            Label(safety, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                // V8: the whole change in one sentence, then a row per day or thing.
                Headline(summary(chosen.isEmpty ? all : chosen), size: 28)
                    .padding(.top, 6)
                SectionLabel("What changes") { Text("\(chosen.count) of \(all.count)") }
                VStack(spacing: 0) {
                    ForEach(Array(all.enumerated()), id: \.offset) { index, proposal in
                        changeRow(proposal, on: !skipped.contains(index)) {
                            if skipped.contains(index) { skipped.remove(index) } else { skipped.insert(index) }
                        }
                    }
                }
                if chosen.contains(where: { awayKind($0) != nil }) {
                    Toggle(isOn: $remind) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Remind me")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                            Text("The evening before and each morning: today's bodyweight workout, if you feel like it.")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(AuraTone.training.mark)
                    .padding(.vertical, 6)
                }
                Button { apply(chosen) } label: {
                    HeroCTALabel(chosen.count == 1 ? "Apply" : "Apply \(chosen.count) changes")
                }
                .buttonStyle(.primary)
                .disabled(chosen.isEmpty)
                Text("Nothing is forced: workouts stay optional, and you can change any day later.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if !parsed.unread.isEmpty && !reading {
            VStack(alignment: .leading, spacing: 6) {
                Text(parsed.proposals.isEmpty ? "Nothing the app can change from that yet" : "Not used")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                ForEach(parsed.unread, id: \.self) { line in
                    Text("“\(line)”")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Tell works with days and what happens on them: games, practice and what it was like, how your body feels, workouts you did, the equipment and time you have, the season, pain, exams, being sick or away, and what you want to get better at.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One change: its colour mark, what changes, what that day looks like, a tick.
    private func changeRow(_ proposal: TellParser.Proposal, on: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(alignment: .center, spacing: 14) {
                Capsule()
                    .fill(color(proposal).opacity(on ? 1 : 0.3))
                    .frame(width: 4, height: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title(proposal))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(on ? AppTheme.ink : AppTheme.mutedText)
                        .multilineTextAlignment(.leading)
                    Text(detail(proposal))
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(on ? AppTheme.ink : AppTheme.mutedText)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// The activity colour of a change (V8).
    private func color(_ proposal: TellParser.Proposal) -> Color {
        switch proposal {
        case .competition, .result: AuraTone.game.mark
        case .pain, .headKnock: AppTheme.danger
        case .examWeek: AuraTone.mind.mark
        case .dayStatus(let status, _, _): status == "sick" ? AuraTone.calm.mark : AuraTone.training.mark
        case .noGym, .goals: AuraTone.training.mark
        case .practice, .season: AuraTone.body.mark
        case .fatigue: AuraTone.body.mark
        case .training, .workout, .equipment, .time: AuraTone.training.mark
        }
    }

    /// "holiday", "travel" or "noGym" for a day that gets a bodyweight workout (and a reminder).
    private func awayKind(_ proposal: TellParser.Proposal) -> String? {
        switch proposal {
        case .dayStatus(let status, _, _) where status == "holiday" || status == "travel": return status
        case .noGym: return "noGym"
        default: return nil
        }
    }

    /// The headline: the main change in white, what it means dimmed.
    private func summary(_ chosen: [TellParser.Proposal]) -> [Headline.Part] {
        let calendar = Calendar.current
        func span(_ days: [Date]) -> String {
            guard let first = days.min(), let last = days.max() else { return "" }
            let f = first.formatted(.dateTime.weekday(.abbreviated))
            return calendar.isDate(first, inSameDayAs: last) ? f : "\(f)–\(last.formatted(.dateTime.weekday(.abbreviated)))"
        }
        var away: [Date] = []
        var awayName = ""
        var sick: [Date] = []
        var noGym: [Date] = []
        for proposal in chosen {
            switch proposal {
            case .dayStatus(let status, let from, let days):
                let all = (0..<max(1, days)).compactMap { calendar.date(byAdding: .day, value: $0, to: from) }
                if status == "sick" { sick += all } else { away += all; awayName = status == "travel" ? "Away" : "Holiday" }
            case .noGym(let from, let days):
                noGym += (0..<max(1, days)).compactMap { calendar.date(byAdding: .day, value: $0, to: from) }
            default: break
            }
        }
        let others = chosen.count - chosen.filter { if case .dayStatus = $0 { true } else if case .noGym = $0 { true } else { false } }.count
        let more: Headline.Part = .soft(others > 0 ? " Plus \(others) more." : "")
        if !away.isEmpty {
            return [.strong("\(awayName) \(span(away))."), .soft(" A quick bodyweight workout each day — all optional."), more]
        }
        if !noGym.isEmpty {
            return [.strong("No gym \(span(noGym))."), .soft(" Your workouts switch to bodyweight."), more]
        }
        if !sick.isEmpty {
            return [.strong("Rest \(span(sick))."), .soft(" No training while you're sick."), more]
        }
        guard let first = chosen.first else { return [.soft("Nothing ticked.")] }
        return [.strong(title(first) + "."), .soft(chosen.count > 1 ? " Plus \(chosen.count - 1) more." : "")]
    }

    private func done(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Headline([.strong("Done. "), .soft("The app follows it from now on.")], size: 34)
            ForEach(lines, id: \.self) { line in
                Label(line, systemImage: "checkmark")
                    .font(.body)
                    .foregroundStyle(AppTheme.ink)
            }
            if savedWorkout {
                Label("Saved to your training: Progress, Training History and the body map count it.", systemImage: "figure.strengthtraining.traditional")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let adjusted {
                // V8: one card, the change in two lines and the reason under it.
                VStack(alignment: .leading, spacing: 12) {
                    Text("Plan adjusted")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AuraTone.training.mark)
                    if adjusted.before != adjusted.now {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Before").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.mutedText)
                            Text(adjusted.before).font(.body).foregroundStyle(AppTheme.secondaryText).strikethrough(true, color: AppTheme.mutedText)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Now").font(.caption.weight(.semibold)).foregroundStyle(AppTheme.mutedText)
                            Text(adjusted.now).font(.title3.weight(.semibold)).foregroundStyle(AppTheme.ink)
                        }
                    }
                    if let why = adjusted.why {
                        Text(why)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
            Button { dismiss() } label: { HeroCTALabel("Close") }
                .buttonStyle(.primary)
                .padding(.top, 8)
        }
    }

    // MARK: Words

    private func day(_ date: Date, time: Bool) -> String {
        time ? date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
            : date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private func kindWord(_ kind: TellParser.CompetitionWord) -> String {
        switch kind {
        case .game: family.event
        case .tournament: "tournament"
        case .meet: family.event == "game" ? "meet" : family.event
        }
    }

    private func title(_ proposal: TellParser.Proposal) -> String {
        switch proposal {
        case .competition(let date, let kind, let note, let time):
            return "Add a \(kindWord(kind)) · \(day(date, time: time))\(note.map { " · \($0)" } ?? "")"
        case .pain(let areas, let level):
            let names = areas.compactMap { PainArea(rawValue: $0)?.title.lowercased() }.joined(separator: ", ")
            return "Report pain: \(names) (\((PainLevel(rawValue: level) ?? .some).title.lowercased()))"
        case .headKnock:
            return "Pause training — possible head injury"
        case .examWeek(let date):
            return "Exam week from \(day(ScheduleStore.weekStart(of: date), time: false))"
        case .dayStatus(let status, let from, let days):
            let name = status == "travel" ? "Away" : DayStatus(rawValue: status)?.title ?? status
            if days == 1 { return "\(day(from, time: false)) · \(status == "sick" ? "Sick" : name)" }
            return "\(name) from \(day(from, time: false)) for \(days) days"
        case .noGym(let from, let days):
            if days == 1 { return "\(day(from, time: false)) · No gym" }
            return "No gym from \(day(from, time: false)) for \(days) days"
        case .practice(let from, let days, let happening):
            let what = happening ? "Team practice" : "No team practice"
            return days == 1 ? "\(day(from, time: false)) · \(what)" : "\(what) from \(day(from, time: false)) for \(days) days"
        case .goals(let goals):
            return "Goals: " + goals.compactMap { Struggle(rawValue: $0)?.title }.joined(separator: ", ")
        case .season(let part, let from):
            switch part {
            case "pre": return "Pre-season training from \(day(from, time: false))"
            case "end": return "Season ends \(day(from, time: false))"
            default: return "Season starts \(day(from, time: false))"
            }
        case .fatigue(let date, let regions, let level):
            let names = regions.compactMap(ContextRegion.init(rawValue:)).map { $0.phrase.replacingOccurrences(of: "your ", with: "") }
            let word = level >= 3 ? "very tired" : level == 2 ? "tired" : "a little tired"
            let text = PlanExplanation.list(names)
            return "\(text.prefix(1).uppercased() + text.dropFirst()) \(word) · \(relative(date))"
        case .training(let date, let qualities, let level):
            let parts = qualities.compactMap(ContextQuality.init(rawValue:)).filter { $0 != .skill || qualities.count == 1 }
                .map { $0 == .lowRunning ? "little running" : (level >= 3 ? "a lot of \($0.title)" : $0.title) }
            let load = level >= 3 ? "Hard practice" : level <= 1 ? "Light practice" : "Practice"
            return parts.isEmpty ? "\(load) · \(relative(date))" : "\(load): \(PlanExplanation.list(parts)) · \(relative(date))"
        case .workout(let date, _, _, let names, let level, let minutes):
            var facts: [String] = []
            if level >= 3 { facts.append("hard") } else if level <= 1 { facts.append("easy") }
            if let minutes { facts.append(minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes) min") }
            let what = names.isEmpty ? "Your workout" : "Your workout: \(PlanExplanation.list(names))"
            return ([what] + facts + [relative(date)]).joined(separator: " · ")
        case .equipment(let from, let days, let tags):
            let names = equipmentNames(tags)
            let when = days == 1 ? day(from, time: false) : "\(day(from, time: false)) – \(day(Calendar.current.date(byAdding: .day, value: days - 1, to: from) ?? from, time: false))"
            return "Only \(PlanExplanation.list(names)) · \(when)"
        case .time(let date, let minutes):
            return "\(minutes >= 90 ? "Plenty of time" : "\(minutes) minutes") · \(day(date, time: false))"
        case .result(let date, let outcome, let score, let placement, let rating):
            let result = CompetitionResult(id: "", outcome: CompetitionResult.Outcome(rawValue: outcome) ?? .win, placement: placement,
                                           score: score, rating: rating ?? 3)
            let played = rating.map { $0 >= 5 ? "played great" : $0 == 4 ? "played well" : $0 <= 2 ? "not your best game" : "played okay" }
            return (["Result: \(result.summary)"] + (played.map { [$0] } ?? []) + [relative(date)]).joined(separator: " · ")
        }
    }

    /// "today", "yesterday", or the date.
    private func relative(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInYesterday(date) { return "yesterday" }
        return day(date, time: false)
    }

    private func equipmentNames(_ tags: [String]) -> [String] {
        let names: [String: String] = ["dumbbell": "dumbbells", "barbell": "a barbell", "bench": "a bench", "cable-machine": "cables",
                                       "band": "bands", "kettlebell": "kettlebells", "pull-up-bar": "a pull-up bar", "box": "a box",
                                       "med-ball": "a med ball", "lat-pulldown": "machines"]
        var out: [String] = []
        for tag in tags { if let name = names[tag], !out.contains(name) { out.append(name) } }
        return out.isEmpty ? ["bodyweight"] : out
    }

    private func detail(_ proposal: TellParser.Proposal) -> String {
        switch proposal {
        case .competition: "Your training tapers for it; it shows up in Competitions and on Home."
        case .pain: "Today's training leaves it alone. Sharp or getting worse: stop and get it checked."
        case .headKnock: "No training until a doctor clears you. Tell a parent or coach today."
        case .examWeek: "Fewer, shorter sessions that week — time and sleep for studying."
        case .dayStatus(let status, _, _):
            status == "sick" ? "No training. Rest and recover — it never counts against you."
                : "Bodyweight workout, about 20 min — only if you feel like it."
        case .noGym: "Your planned workout with bodyweight exercises only. Skip it or do more — your call."
        case .practice(_, _, let happening):
            happening ? "Counted as practice; the gym part that day gets lighter." : "Your plan uses the free day — or rest, your call."
        case .goals: "Your training leans towards them (up to three)."
        case .season(let part, _):
            part == "pre" ? "Strength and speed for the season ahead from then; until then you build in the off-season."
                : part == "end" ? "A few lighter weeks after it, then building again."
                : "Training switches to short sessions that keep what you built, fresh for competitions."
        case .fatigue:
            "Leg or upper-body work stays lighter while it lasts. The morning check-in asks how it feels until it's back to normal."
        case .training:
            "Counted as what practice gave you, so the gym doesn't repeat it."
        case .workout:
            "Counted in your training: the next gym session knows what you already did."
        case .equipment:
            "Workouts on those days use only this. Your usual setup comes back by itself afterwards."
        case .time(_, let minutes):
            minutes >= 90 ? "Room for the full session." : "The session is built for that time — the most important work first."
        case .result:
            "Saved in Competitions with your record; add what went well there. The next focus points build on it."
        }
    }

    // MARK: Apply

    /// The check-in's "What's on today?" answer for that day, kept in step with what
    /// was told after it (the engine reads that answer first): practice on or off,
    /// how hard it was, a game. Nothing when the day has no answer.
    private func markSaidDay(_ date: Date, practice: Bool? = nil, intensity: PracticeIntensity? = nil, game: Bool = false) {
        guard let said = DayChoiceStore.answer(on: date), !said.isAuto else { return }
        var choices = said.choices
        if let practice { if practice { choices.insert(.practice) } else { choices.remove(.practice) } }
        if game { choices.insert(.game) }
        if practice == true || game { choices.subtract(DayChoice.allCases.filter(\.standsAlone)) }
        guard !choices.isEmpty else {
            DayChoiceStore.set(nil, on: date)
            return
        }
        let level = choices.contains(.practice) ? (intensity ?? said.practice ?? .normal) : nil
        DayChoiceStore.set(DayAnswer(choices: choices, practice: level), on: date)
    }

    /// "We won 3-1": onto that day's competition (or the one just before, told the
    /// morning after), or a new one for the day; what the athlete already wrote stays.
    private func saveResult(day date: Date, outcome: String, score: String?, placement: Int?, rating: Int?) {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let recent = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        let target: Competition
        if let same = athlete.competitions.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
            target = same
        } else if calendar.isDateInToday(day),
                  let before = athlete.competitions.filter({ $0.date >= recent && $0.date < day && CompetitionStore.results()[$0.id] == nil })
                      .max(by: { $0.date < $1.date }) {
            target = before
        } else {
            let created = Competition(sportSlug: athlete.activeSport?.sportSlug ?? "general", date: day, kind: outcome == "placed" ? .meet : .game,
                                      isHome: true, notes: nil, athlete: athlete)
            modelContext.insert(created)
            target = created
        }
        var result = CompetitionStore.results()[target.id]
            ?? CompetitionResult(id: target.id, outcome: .win, rating: rating ?? 3)
        result.outcome = CompetitionResult.Outcome(rawValue: outcome) ?? result.outcome
        if let score { result.score = score }
        if let placement { result.placement = placement }
        if let rating { result.rating = rating }
        result.savedAt = .now
        CompetitionStore.save(result)
        try? modelContext.save()
    }

    private func apply(_ proposals: [TellParser.Proposal]) {
        var lines: [String] = []
        let calendar = Calendar.current
        var statusDays: [(DayStatus, Date)] = []
        var awayDays: [(day: Date, kind: String)] = []
        // A head knock goes last, so no other status can replace the pause;
        // and nothing typed here lifts a pause that is already on.
        let paused = DayStatusStore.status() == .concussion
        // `proposals` are already the ticked changes.
        let chosen = proposals
        let isKnock: (TellParser.Proposal) -> Bool = { if case .headKnock = $0 { true } else { false } }
        // Pre-season before the season start, so a season day told together wins.
        let isPre: (TellParser.Proposal) -> Bool = { if case .season("pre", _) = $0 { true } else { false } }
        let ordered = chosen.filter(isPre) + chosen.filter { !isKnock($0) && !isPre($0) } + chosen.filter(isKnock)
        let toldSeasonStart = chosen.contains { if case .season("in", _) = $0 { true } else { false } }
        var exposures: [Date: UUID] = [:]
        var fatigues: [TellParser.Proposal] = []
        // Day statuses are confirmed only when they are really saved (not past, not replaced by a head knock).
        var statusLines: [String] = []
        var pastStatus = false
        let before = planLine()
        for proposal in ordered {
            switch proposal {
            case .competition(let date, let kind, let note, _):
                let stored: CompetitionKind = switch kind {
                case .game: .game
                case .tournament: .tournament
                case .meet: .meet
                }
                markSaidDay(date, game: true)
                // Told again ("match Saturday 4pm"): the one already there gets the time and note.
                if let same = athlete.competitions.first(where: { calendar.isDate($0.date, inSameDayAs: date) && $0.kind == stored }) {
                    if case .competition(_, _, _, true) = proposal { same.date = date }
                    if let note, !note.isEmpty { same.notes = note }
                    try? modelContext.save()
                    lines.append(title(proposal))
                    continue
                }
                modelContext.insert(Competition(sportSlug: athlete.activeSport?.sportSlug ?? "general", date: date, kind: stored,
                                                isHome: true, notes: note, athlete: athlete))
                try? modelContext.save()
            case .pain(let areas, let level):
                // Added to today's report, never replacing it; the higher level wins.
                let new = areas.compactMap(PainArea.init(rawValue:))
                let told = PainLevel(rawValue: level) ?? .some
                let today = PainStore.report()
                let merged = (today?.areas ?? []) + new.filter { !(today?.areas ?? []).contains($0) }
                let order: [PainLevel] = [.little, .some, .lot]
                let higher = max(order.firstIndex(of: told) ?? 1, today.flatMap { order.firstIndex(of: $0.level) } ?? 0)
                PainStore.set(PainReport(day: DayKey.of(.now), areas: merged, level: order[higher]))
                HealthShare.send(kind: "pain", areas: merged, level: order[higher])
            case .headKnock:
                DayStatusStore.set(.concussion, days: nil)
                HealthShare.send(kind: "paused")
            case .examWeek(let date):
                ScheduleStore.setManualExamWeek(date, true)
            case .dayStatus(let status, let from, let days):
                guard !paused else {
                    lines.append("Training stays paused until a doctor clears you")
                    continue
                }
                guard let kind = DayStatus(rawValue: status) else { continue }
                var future = false
                for offset in 0..<max(1, min(days, 31)) {
                    guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: from)) else { continue }
                    // Days already over stay as they were.
                    if day < calendar.startOfDay(for: .now) { pastStatus = true; continue }
                    statusDays.append((kind, day))
                    future = true
                }
                if future { statusLines.append(title(proposal)) }
                continue
            case .noGym(let from, let days):
                NoGymDays.add(from: from, days: days)
                for offset in 0..<max(1, min(days, 31)) {
                    if let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: from)) { awayDays.append((day: day, kind: "noGym")) }
                }
            case .practice(let from, let days, let happening):
                for offset in 0..<max(1, min(days, 31)) {
                    if let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: from)) {
                        PracticeOverride.set(happening, on: DayKey.of(day, calendar: calendar))
                        markSaidDay(day, practice: happening)
                    }
                }
            case .goals(let goals):
                var merged = goals.compactMap(Struggle.init(rawValue:))
                for goal in Struggles.selected where !merged.contains(goal) { merged.append(goal) }
                Struggles.selected = Array(merged.prefix(Struggles.maximum))
            case .season(let part, let from):
                guard let sport = athlete.activeSport else { continue }
                func weeks(_ n: Int, _ date: Date) -> Date { calendar.date(byAdding: .day, value: 7 * n, to: date) ?? date }
                switch part {
                case "pre":
                    PreSeasonStore.start = from
                    // The season itself comes after pre-season; if it isn't set that way yet, assume about eight weeks.
                    if !toldSeasonStart && sport.seasonStart <= from {
                        sport.seasonStart = weeks(8, from)
                    }
                case "end":
                    sport.seasonEnd = from
                    if sport.seasonStart >= from { sport.seasonStart = weeks(-16, from) }
                default:
                    sport.seasonStart = from
                    if let pre = PreSeasonStore.start, pre >= from { PreSeasonStore.start = nil }
                }
                if sport.seasonEnd <= weeks(4, sport.seasonStart) { sport.seasonEnd = weeks(20, sport.seasonStart) }
                try? modelContext.save()
            case .training(let date, let qualities, let level):
                let event = AthleteContextEvent(from: calendar.startOfDay(for: date), kind: .exposure, source: .tellAthleteOS,
                                                reported: [title(proposal)], qualities: qualities.compactMap(ContextQuality.init(rawValue:)),
                                                level: level, practice: true)
                AthleteContextStore.add(event)
                exposures[calendar.startOfDay(for: date)] = event.id
                markSaidDay(date, intensity: level >= 3 ? .hard : level <= 1 ? .light : .normal)
            case .workout(let date, let patterns, let qualities, let names, let level, let minutes):
                // Saved as training (Training History, "Training done", body map), and as context for the plan.
                HealthWorkoutInbox.logTold(day: date, names: names, patterns: patterns, qualities: qualities, level: level,
                                           minutes: minutes, athlete: athlete, context: modelContext)
                savedWorkout = true
                AthleteContextStore.add(AthleteContextEvent(from: calendar.startOfDay(for: date), kind: .exposure, source: .tellAthleteOS,
                                                            reported: [title(proposal)], qualities: qualities.compactMap(ContextQuality.init(rawValue:)),
                                                            level: level, patterns: patterns, minutes: minutes))
            case .fatigue:
                // After the exposures, so tired legs link to the practice that tired them.
                fatigues.append(proposal)
            case .equipment(let from, let days, let tags):
                let start = calendar.startOfDay(for: from)
                AthleteContextStore.add(AthleteContextEvent(from: start, until: calendar.date(byAdding: .day, value: max(0, days - 1), to: start),
                                                            kind: .equipment, source: .tellAthleteOS, reported: [title(proposal)], equipment: tags))
            case .result(let date, let outcome, let score, let placement, let rating):
                saveResult(day: date, outcome: outcome, score: score, placement: placement, rating: rating)
            case .time(let date, let minutes):
                let start = calendar.startOfDay(for: date)
                AthleteContextStore.add(AthleteContextEvent(from: start, until: start, kind: .time, source: .tellAthleteOS,
                                                            reported: [title(proposal)], minutes: minutes))
            }
            lines.append(title(proposal))
        }
        for case .fatigue(let date, let regions, let level) in fatigues {
            let day = calendar.startOfDay(for: date)
            AthleteContextStore.add(AthleteContextEvent(from: day, kind: .fatigue, source: .tellAthleteOS, reported: [title(.fatigue(day: date, regions: regions, level: level))],
                                                        regions: regions.compactMap(ContextRegion.init(rawValue:)), level: level,
                                                        relatedID: exposures[day]))
        }
        // Day statuses: consecutive days of one kind become one span (today's starts now, later ones wait).
        // A head knock told now keeps training paused: no other status replaces it.
        let sortedDays = chosen.contains(where: isKnock) ? [] : statusDays.sorted { $0.1 < $1.1 }
        if !chosen.contains(where: isKnock) { lines += statusLines }
        if pastStatus { lines.append("Days already over stay as they were") }
        var index = 0
        while index < sortedDays.count {
            let (status, start) = sortedDays[index]
            var count = 1
            while index + count < sortedDays.count, sortedDays[index + count].0 == status,
                  let next = calendar.date(byAdding: .day, value: count, to: start),
                  calendar.isDate(sortedDays[index + count].1, inSameDayAs: next) {
                count += 1
            }
            DayStatusStore.schedule(status, from: start, days: count)
            if status == .travel || status == .holiday {
                for offset in 0..<count {
                    if let day = calendar.date(byAdding: .day, value: offset, to: start) { awayDays.append((day: day, kind: status.rawValue)) }
                }
            }
            index += count
        }
        #if canImport(UserNotifications)
        if remind, !awayDays.isEmpty {
            let days = awayDays
            Task { await AwayReminders.schedule(days: days) }
        }
        #endif
        NotificationCenter.default.post(name: WeeklyPlan.inputsChanged, object: nil)
        onChanged()
        // What it did to today's plan, in one line (only when it changed).
        if let before, let after = planLine(), before.title != after.title || after.why != before.why, let why = after.why ?? before.why {
            adjusted = (before.title, after.title, before.title == after.title ? why : (after.why ?? why))
        }
        var shown: [String] = []
        for line in lines where !shown.contains(line) { shown.append(line) }
        withAnimation { applied = shown }
    }

    /// Today's plan in a few words, and the first thing the athlete told that shaped it.
    private func planLine() -> (title: String, why: String?)? {
        guard TodayEngine.isAvailable(catalogue),
              let result = TodayEngine.decision(athlete: athlete, sessions: athlete.sessions, catalogue: catalogue,
                                                plannedGymDay: plannedGymDay) else { return nil }
        let (decision, day) = result
        var title = decision.sessionType.title
        if let focus = decision.gymFocus { title += " · \(focus.title)" }
        else if decision.legBudget <= 1, [.gymDevelopment, .afterPractice].contains(decision.sessionType) { title += " · light on the legs" }
        return (title, PlanExplanation.contextLines(Set(decision.reasons), day: day, decision: decision).first)
    }
}
