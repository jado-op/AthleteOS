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
    @FocusState private var writing: Bool

    private var result: TellParser.Result { TellParser.parse(text) }
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
            Text("Read on your phone. Nothing is sent anywhere.")
                .font(.caption)
                .foregroundStyle(AppTheme.mutedText)
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
        } else if text.count > 12 {
            Text("Nothing to change from that yet. Try a day (\"Saturday\", \"24.11.\"), a body part that hurts, exams, or what you want to get better at.")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
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
        }
    }

    // MARK: Apply

    private func apply(_ proposals: [TellParser.Proposal]) {
        var lines: [String] = []
        for (index, proposal) in proposals.enumerated() where !skipped.contains(index) {
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
                PainStore.set(PainReport(day: DayKey.of(.now), areas: areas.compactMap(PainArea.init(rawValue:)),
                                         level: PainLevel(rawValue: level) ?? .some))
            case .headKnock:
                DayStatusStore.set(.concussion, days: nil)
            case .examWeek(let date):
                ScheduleStore.setManualExamWeek(date, true)
            case .dayStatus(let status, let from, let days):
                if let status = DayStatus(rawValue: status) { DayStatusStore.set(status, days: days, now: from) }
            case .goals(let goals):
                var merged = goals.compactMap(Struggle.init(rawValue:))
                for goal in Struggles.selected where !merged.contains(goal) { merged.append(goal) }
                Struggles.selected = Array(merged.prefix(Struggles.maximum))
            }
            lines.append(title(proposal))
        }
        onChanged()
        withAnimation { applied = lines }
    }
}
