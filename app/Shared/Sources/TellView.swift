import SwiftData
import SwiftUI

/// "Tell AthleteOS": write what's going on in your own words; the app reads it
/// (TellParser, on the phone) and proposes how to change itself — a
/// competition, a pain report, an exam week, a day status, goals. Nothing
/// changes until the athlete ticks it and taps Apply.
struct TellView: View {
    let athlete: Athlete
    var onChanged: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var text = ""
    @State private var skipped: Set<Int> = []
    @State private var applied: [String]?
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
            .onAppear { writing = true }
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
        VStack(alignment: .leading, spacing: 10) {
            Text("What's coming up, what hurts, what you want. Your words — the app adjusts.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("e.g. Match on Saturday at 4pm against Central. My knee hurts a bit. Exams next week. I want to get faster.")
                        .font(.body)
                        .foregroundStyle(AppTheme.mutedText)
                        .padding(.top, 2)
                }
                TextField("", text: $text, axis: .vertical)
                    .accessibilityLabel("What's going on")
                    .lineLimit(4...10)
                    .font(.body)
                    .foregroundStyle(AppTheme.ink)
                    .focused($writing)
                    .onChange(of: text) { skipped = [] }
            }
            .padding(16)
            .glassSurface(cornerRadius: 18)
            HStack(spacing: 8) {
                if reading { ProgressView().controlSize(.small) }
                Text(reading ? "Reading…" : "Read on your phone. Nothing is sent anywhere.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedText)
            }
        }
    }

    @ViewBuilder
    private var proposals: some View {
        let parsed = result
        if let safety = parsed.safety {
            Label(safety, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !parsed.proposals.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SpaceSection(1, "What changes") { Text("\(parsed.proposals.count - skipped.count) of \(parsed.proposals.count)") }
                ForEach(Array(parsed.proposals.enumerated()), id: \.offset) { index, proposal in
                    let on = !skipped.contains(index)
                    Button {
                        if on { skipped.insert(index) } else { skipped.remove(index) }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(on ? AppTheme.brightRed : AppTheme.mutedText)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(title(proposal))
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)
                                    .multilineTextAlignment(.leading)
                                Text(detail(proposal))
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .glassSurface(cornerRadius: 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                Button { apply(parsed.proposals) } label: {
                    HeroCTALabel("Apply \(parsed.proposals.count - skipped.count)")
                }
                .buttonStyle(.primary)
                .disabled(parsed.proposals.count == skipped.count)
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
                Text("Tell works with days and what happens on them: games, the season, pain, exams, being sick or away, and what you want to get better at.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func done(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Done")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            ForEach(lines, id: \.self) { line in
                Label(line, systemImage: "checkmark")
                    .font(.body)
                    .foregroundStyle(AppTheme.ink)
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
            let name = DayStatus(rawValue: status)?.title ?? status
            return "\(name) from \(day(from, time: false))\(days > 1 ? " for \(days) days" : "")"
        case .goals(let goals):
            return "Goals: " + goals.compactMap { Struggle(rawValue: $0)?.title }.joined(separator: ", ")
        case .season(let part, let from):
            switch part {
            case "pre": return "Pre-season training from \(day(from, time: false))"
            case "end": return "Season ends \(day(from, time: false))"
            default: return "Season starts \(day(from, time: false))"
            }
        }
    }

    private func detail(_ proposal: TellParser.Proposal) -> String {
        switch proposal {
        case .competition: "Your training tapers for it; it shows up in Competitions and on Home."
        case .pain: "Today's training leaves it alone. Sharp or getting worse: stop and get it checked."
        case .headKnock: "No training until a doctor clears you. Tell a parent or coach today."
        case .examWeek: "Fewer, shorter sessions that week — time and sleep for studying."
        case .dayStatus: "Your plan adjusts while it lasts; your streak is protected."
        case .goals: "Your training leans towards them (up to three)."
        case .season(let part, _):
            part == "pre" ? "Strength and speed for the season ahead from then; until then you build in the off-season."
                : part == "end" ? "A few lighter weeks after it, then building again."
                : "Training switches to short sessions that keep what you built, fresh for competitions."
        }
    }

    // MARK: Apply

    private func apply(_ proposals: [TellParser.Proposal]) {
        var lines: [String] = []
        // A head knock goes last, so no other status can replace the pause;
        // and nothing typed here lifts a pause that is already on.
        let paused = DayStatusStore.status() == .concussion
        let chosen = proposals.enumerated().filter { !skipped.contains($0.offset) }.map(\.element)
        let isKnock: (TellParser.Proposal) -> Bool = { if case .headKnock = $0 { true } else { false } }
        // Pre-season before the season start, so a season day told together wins.
        let isPre: (TellParser.Proposal) -> Bool = { if case .season("pre", _) = $0 { true } else { false } }
        let ordered = chosen.filter(isPre) + chosen.filter { !isKnock($0) && !isPre($0) } + chosen.filter(isKnock)
        let toldSeasonStart = chosen.contains { if case .season("in", _) = $0 { true } else { false } }
        for proposal in ordered {
            switch proposal {
            case .competition(let date, let kind, let note, _):
                let stored: CompetitionKind = switch kind {
                case .game: .game
                case .tournament: .tournament
                case .meet: .meet
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
                if let status = DayStatus(rawValue: status) { DayStatusStore.set(status, days: days, now: from) }
            case .goals(let goals):
                var merged = goals.compactMap(Struggle.init(rawValue:))
                for goal in Struggles.selected where !merged.contains(goal) { merged.append(goal) }
                Struggles.selected = Array(merged.prefix(Struggles.maximum))
            case .season(let part, let from):
                guard let sport = athlete.activeSport else { continue }
                let calendar = Calendar.current
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
            }
            lines.append(title(proposal))
        }
        onChanged()
        withAnimation { applied = lines }
    }
}
