import SwiftData
import SwiftUI

/// The competition hub: the next one (countdown and the athlete's own read of
/// their chance), what to work on until then, the last result, the record.
struct CompetitionHubView: View {
    let athlete: Athlete
    var onChanged: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var results = CompetitionStore.results()
    @State private var chance: Double = 50
    @State private var editingResult = false
    @State private var reading: Briefing?
    @State private var adding = false
    @State private var newDate = Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now
    @State private var newNote = ""
    @State private var leaned = false

    private var family: SportFamily { AcademyContent.family(forSport: athlete.activeSport?.sportSlug) }
    /// Over once it has started and had two hours (midnight = time unknown:
    /// the athlete's usual start time).
    private func isOver(_ game: Competition) -> Bool {
        let calendar = Calendar.current
        let start = GameTime.start(game.date, usualMinutes: UserDefaults.standard.object(forKey: GameTime.usualStartKey) as? Int ?? GameTime.defaultUsualMinutes)
        return calendar.startOfDay(for: game.date) < calendar.startOfDay(for: .now) || start.addingTimeInterval(2 * 3600) < .now
    }
    private var next: Competition? { AthleteStats.upcomingCompetitions(athlete).first { !isOver($0) } }
    private var past: [Competition] {
        athlete.competitions.filter(isOver).sorted { $0.date > $1.date }
    }
    private var last: Competition? { past.first }
    private var daysToNext: Int? { next.map { AthleteStats.daysUntil($0.date) } }

    /// The twin's insights, read once (not on every redraw of the slider).
    @State private var twinInsights: [TwinInsightKind]?

    private var focus: [CompetitionFocus] {
        let lastResult = past.lazy.compactMap { results[$0.id] }.first
        return CompetitionCoach.focus(last: lastResult, insights: twinInsights ?? [], daysToNext: daysToNext, team: family.team)
    }

    private func loadTwinInsights() {
        let input = TwinInputBuilder.input(athlete: athlete, state: AcademyStore.load())
        twinInsights = TwinAnalysis.report(input).insights.map(\.kind)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    nextSection
                    focusSection
                    lastSection
                    if !past.isEmpty { historySection }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground(.hero).ignoresSafeArea())
            .navigationTitle(family.tokens["Events"] ?? "Competitions")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                if let next { chance = Double(CompetitionStore.outlooks()[next.id]?.chance ?? 50) }
                loadTwinInsights()
            }
            .fullScreenCover(item: $reading) { briefing in
                BriefingReaderView(briefing: briefing, insight: nil, alreadyRead: AcademyStore.load().read[briefing.id] != nil,
                                   familyID: AcademyContent.familyID(forSport: athlete.activeSport?.sportSlug))
            }
            .sheet(isPresented: $editingResult, onDismiss: { results = CompetitionStore.results() }) {
                if let last {
                    CompetitionResultForm(competition: last, existing: results[last.id], family: family)
                }
            }
        }
    }

    // MARK: Next

    private var nextSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SpaceSection(1, "Next \(family.event)") {
                if let next { Text(next.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())) }
            }
            if let next, let days = daysToNext {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(days == 0 ? "Today" : days == 1 ? "Tomorrow" : "\(days)")
                        .font(days > 1 ? .telemetry(56, weight: .medium) : .system(size: 44, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                    if days > 1 {
                        Text("days to go").font(.headline).foregroundStyle(AppTheme.secondaryText)
                    }
                }
                if let note = next.notes, !note.isEmpty {
                    Text(note).font(.title3.weight(.semibold)).foregroundStyle(AppTheme.ink)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Your chance")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                        Text("\(Int(chance))% · \(CompetitionCoach.chanceWord(Int(chance)))")
                            .font(.telemetry(13))
                            .foregroundStyle(AppTheme.brightRed)
                    }
                    Slider(value: $chance, in: 0...100, step: 5, onEditingChanged: { editing in
                        if !editing { CompetitionStore.save(CompetitionOutlook(id: next.id, chance: Int(chance))) }
                    })
                    .tint(AppTheme.brightRed)
                    Text("Your own read — how you rate it, not a prediction.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                }
                .padding(16)
                .glassSurface(cornerRadius: 18)
            } else if adding {
                addForm
            } else {
                Text("Nothing planned yet.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                Button { adding = true } label: { HeroCTALabel("Add your next \(family.event)") }
                    .buttonStyle(.primary)
            }
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("When", selection: $newDate, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                .foregroundStyle(AppTheme.ink)
            TextField("Opponent or event (optional)", text: $newNote)
                .padding(14)
                .glassSurface(cornerRadius: 14)
            Button {
                modelContext.insert(Competition(sportSlug: athlete.activeSport?.sportSlug ?? "general", date: newDate, kind: .game,
                                                isHome: true, notes: newNote.isEmpty ? nil : newNote, athlete: athlete))
                try? modelContext.save()
                adding = false
                onChanged()
            } label: { HeroCTALabel("Save") }
                .buttonStyle(.primary)
        }
    }

    // MARK: Until the next one

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SpaceSection(2, "Until the next one") { Text("\(focus.count) things") }
            ForEach(Array(focus.enumerated()), id: \.element.id) { index, point in
                HStack(alignment: .top, spacing: 14) {
                    Text(String(format: "%02d", index + 1))
                        .font(.telemetry(12))
                        .foregroundStyle(AppTheme.brightRed)
                        .padding(.top, 3)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(family.fill(point.title))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text(family.fill(point.detail))
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if let id = point.briefingID, let briefing = AcademyContent.briefing(id) {
                            Button { reading = briefing } label: {
                                Text("Read: \(briefing.title) →")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(AppTheme.brightRed)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            let goals = focus.compactMap { $0.goal.flatMap(Struggle.init(rawValue:)) }
            if !goals.isEmpty {
                Button {
                    var merged = goals
                    for goal in Struggles.selected where !merged.contains(goal) { merged.append(goal) }
                    Struggles.selected = Array(merged.prefix(Struggles.maximum))
                    leaned = true
                    onChanged()
                } label: {
                    Text(leaned ? "Your training leans this way now" : "Lean my training this way")
                }
                .buttonStyle(.secondary)
                .disabled(leaned)
            }
        }
    }

    // MARK: Last result

    private var lastSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SpaceSection(3, "Last \(family.event)") {
                if let last { Text(last.date.formatted(.dateTime.day().month(.abbreviated))) }
            }
            if let last {
                if let result = results[last.id] {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(result.summary)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                        HStack(spacing: 6) {
                            ForEach(1...5, id: \.self) { n in
                                Circle().fill(n <= result.rating ? AppTheme.brightRed : Color.white.opacity(0.12)).frame(width: 8, height: 8)
                            }
                            Text("how you played").font(.caption).foregroundStyle(AppTheme.secondaryText)
                        }
                        if !result.wentWell.isEmpty {
                            Text("Went well: \(result.wentWell.joined(separator: ", "))")
                                .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                        }
                        if !result.toImprove.isEmpty {
                            Text("To improve: \(result.toImprove.joined(separator: ", "))")
                                .font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                        }
                        Button("Edit") { editingResult = true }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.brightRed)
                    }
                } else {
                    Text("How did it go? Two minutes now make the next one better.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                    Button { editingResult = true } label: { HeroCTALabel("Add your result") }
                        .buttonStyle(.primary)
                }
            } else {
                Text("Your results show up here after your first \(family.event).")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    // MARK: History

    private var historySection: some View {
        let known = past.compactMap { results[$0.id] }
        let record = CompetitionCoach.record(known)
        return VStack(alignment: .leading, spacing: 12) {
            SpaceSection(4, "Record") {
                Text("\(record.wins)–\(record.draws)–\(record.losses)")
            }
            ForEach(past.prefix(8)) { competition in
                HStack {
                    Text(competition.date.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.telemetry(12))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(width: 64, alignment: .leading)
                    Text(competition.notes ?? family.tokens["Event"] ?? "Game")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                    Spacer()
                    Text(results[competition.id]?.summary ?? "–")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                }
                .padding(.vertical, 6)
            }
        }
    }
}

/// How the last competition went: result, score, how you played, what went
/// well, what to improve. Feeds "until the next one".
struct CompetitionResultForm: View {
    let competition: Competition
    let existing: CompetitionResult?
    let family: SportFamily

    @Environment(\.dismiss) private var dismiss
    @State private var outcome: CompetitionResult.Outcome = .win
    @State private var placement = 1
    @State private var score = ""
    @State private var rating = 3
    @State private var wentWell: Set<String> = []
    @State private var toImprove: Set<String> = []
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    group("Result") {
                        HStack(spacing: 8) {
                            ForEach(CompetitionResult.Outcome.allCases, id: \.self) { option in
                                chip(option.title, on: outcome == option) { outcome = option }
                            }
                        }
                        if outcome == .placed {
                            Stepper("Place: \(CompetitionCoach.ordinal(placement))", value: $placement, in: 1...200)
                                .foregroundStyle(AppTheme.ink)
                        }
                        TextField(outcome == .placed ? "Time or score (optional)" : "Score (optional)", text: $score)
                            .padding(14)
                            .glassSurface(cornerRadius: 14)
                    }
                    group("How you played") {
                        HStack(spacing: 10) {
                            ForEach(1...5, id: \.self) { n in
                                Button { rating = n } label: {
                                    Text("\(n)")
                                        .font(.telemetry(16, weight: .medium))
                                        .foregroundStyle(n == rating ? Color(rgb: 0x0B0B14) : AppTheme.ink)
                                        .frame(width: 44, height: 44)
                                        .background(Circle().fill(n == rating ? Color(rgb: 0xEEEAFE) : Color.white.opacity(0.05)))
                                        .overlay { Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text("1 poorly · 5 your best").font(.caption).foregroundStyle(AppTheme.mutedText)
                    }
                    group("Went well") { areaChips($wentWell) }
                    group("To improve") { areaChips($toImprove) }
                    group("Note") {
                        TextField("Anything to remember (optional)", text: $note, axis: .vertical)
                            .lineLimit(2...4)
                            .padding(14)
                            .glassSurface(cornerRadius: 14)
                    }
                    Button(action: save) { HeroCTALabel("Save") }
                        .buttonStyle(.primary)
                }
                .padding(24)
            }
            .background(AppBackground(.subtle).ignoresSafeArea())
            .navigationTitle("Your \(family.event)")
            .navigationBarTitleDisplayModeInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear {
                guard let existing else { return }
                outcome = existing.outcome
                placement = existing.placement ?? 1
                score = existing.score ?? ""
                rating = existing.rating
                wentWell = Set(existing.wentWell)
                toImprove = Set(existing.toImprove)
                note = existing.note ?? ""
            }
        }
    }

    private func save() {
        CompetitionStore.save(CompetitionResult(
            id: competition.id, outcome: outcome, placement: outcome == .placed ? placement : nil,
            score: score.trimmingCharacters(in: .whitespaces).isEmpty ? nil : score.trimmingCharacters(in: .whitespaces),
            rating: rating, wentWell: EveningOptions.areas.filter(wentWell.contains), toImprove: EveningOptions.areas.filter(toImprove.contains),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note))
        AcademyEvent.log(.reflectionSubmitted)
        dismiss()
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.secondaryText)
            content()
        }
    }

    private func areaChips(_ selection: Binding<Set<String>>) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
            ForEach(EveningOptions.areas, id: \.self) { area in
                chip(area, on: selection.wrappedValue.contains(area)) {
                    if selection.wrappedValue.contains(area) { selection.wrappedValue.remove(area) } else { selection.wrappedValue.insert(area) }
                }
            }
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(on ? Color(rgb: 0x0B0B14) : AppTheme.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(on ? Color(rgb: 0xEEEAFE) : Color.white.opacity(0.04)))
                .overlay { Capsule().strokeBorder(Color.white.opacity(on ? 0 : 0.12), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Inline titles on iOS; watchOS has no display modes.
    @ViewBuilder
    func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
