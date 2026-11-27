import SwiftData
import SwiftUI

/// Where the hub opens: the overview, straight on the add-a-game form
/// (Home's "+"), or on game prep (Home's game-day "Get your head ready").
enum CompetitionHubFocus {
    case overview, addGame, gamePrep
}

/// The competition hub — the one place for games: the next one (countdown and
/// the athlete's own read of their chance), adding one, what's coming up, game
/// prep (breathing, visualization), what to work on until then, the last
/// result, the record.
struct CompetitionHubView: View {
    let athlete: Athlete
    var onChanged: () -> Void = {}
    var opening: CompetitionHubFocus = .overview

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var results = CompetitionStore.results()
    @State private var chance: Double = 50
    @State private var editingResult = false
    @State private var reading: Briefing?
    @State private var adding = false
    /// The game being changed or deleted.
    @State private var editingGame: Competition?
    @State private var leaned = false
    @State private var routine: MindsetRoutine?
    @State private var showingVisualizationPaywall = false
    /// Bumped after a game is added, so the lists redraw.
    @State private var revision = 0

    /// Closes the edit sheet, then deletes the game (a view must never draw a
    /// deleted model) with its result and outlook; the plan rearranges.
    private func delete(_ game: Competition) {
        let context = modelContext
        CompetitionStore.forget(game.id)
        editingGame = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            context.delete(game)
            try? context.save()
            revision += 1
            results = CompetitionStore.results()
            if let next { chance = Double(CompetitionStore.outlooks()[next.id]?.chance ?? 50) }
            onChanged()
        }
    }

    private var family: SportFamily { AcademyContent.family(forSport: athlete.activeSport?.sportSlug) }
    /// Over once it has started and had two hours (midnight = time unknown:
    /// the athlete's usual start time).
    private func isOver(_ game: Competition) -> Bool {
        let calendar = Calendar.current
        let start = GameTime.start(game.date, usualMinutes: UserDefaults.standard.object(forKey: GameTime.usualStartKey) as? Int ?? GameTime.defaultUsualMinutes)
        return calendar.startOfDay(for: game.date) < calendar.startOfDay(for: .now) || start.addingTimeInterval(2 * 3600) < .now
    }
    private var upcoming: [Competition] { _ = revision; return AthleteStats.upcomingCompetitions(athlete).filter { !isOver($0) } }
    private var next: Competition? { upcoming.first }
    private var past: [Competition] {
        _ = revision
        return athlete.competitions.filter(isOver).sorted { $0.date > $1.date }
    }
    private var last: Competition? { past.first }
    private var daysToNext: Int? { next.map { AthleteStats.daysUntil($0.date) } }

    /// The twin's insights, read once (not on every redraw of the slider).
    @State private var twinInsights: [TwinInsightKind]?

    private var focus: [CompetitionFocus] {
        let lastResult = past.lazy.compactMap { results[$0.id] }.first
        return CompetitionCoach.focus(last: lastResult, insights: twinInsights ?? [], daysToNext: daysToNext, team: family.team)
    }

    /// What the athlete's best-rated games have in common, once the twin
    /// knows (≥ 10 rated, held twice; "goes with", never "because").
    @State private var bestGames: KnowledgeLine?

    private func loadTwinInsights() {
        let state = AcademyStore.load()
        let input = TwinInputBuilder.input(athlete: athlete, state: state)
        twinInsights = TwinAnalysis.report(input).insights.map(\.kind)
        bestGames = TwinKnowledgeStore.visible(TwinKnowledgeStore.current(athlete, state: state), state: state)
            .first { $0.id.hasPrefix("games.best.") }
    }

    /// Sections in the order they show; numbered by what is actually on screen.
    private enum Section: CaseIterable { case next, comingUp, gamePrep, focus, last, record }

    /// Game prep comes right under the next game on game day, and when the
    /// hub was opened for it.
    private var sections: [Section] {
        let prepFirst = opening == .gamePrep || daysToNext == 0
        var shown: [Section] = [.next]
        if prepFirst { shown.append(.gamePrep) }
        // V8: what to work on sits right under the countdown.
        shown.append(.focus)
        if upcoming.count > 1 { shown.append(.comingUp) }
        if !prepFirst { shown.append(.gamePrep) }
        shown.append(.last)
        if !past.isEmpty { shown.append(.record) }
        return shown
    }

    private func number(_ section: Section) -> Int {
        (sections.firstIndex(of: section) ?? 0) + 1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    // What the rating just taught the twin; tap closes the hub and opens it.
                    TwinPulseLine(sources: [.gameRating]) { dismiss() }
                    ForEach(sections, id: \.self) { section in
                        switch section {
                        case .next: nextSection
                        case .comingUp: comingUpSection
                        case .gamePrep: gamePrepSection
                        case .focus: focusSection
                        case .last: lastSection
                        case .record: historySection
                        }
                    }
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
                if opening == .addGame { adding = true }
                loadTwinInsights()
            }
            .fullScreenCover(item: $reading) { briefing in
                BriefingReaderView(briefing: briefing, insight: nil, alreadyRead: AcademyStore.load().read[briefing.id] != nil,
                                   familyID: AcademyContent.familyID(forSport: athlete.activeSport?.sportSlug))
            }
            .sheet(item: $editingGame) { game in
                NavigationStack {
                    ScrollView {
                        AddGameForm(athlete: athlete, family: family, editing: game, onDelete: delete) {
                            editingGame = nil
                            revision += 1
                            results = CompetitionStore.results()
                            onChanged()
                        }
                        .padding(24)
                    }
                    .background(AppBackground(.hero).ignoresSafeArea())
                    .navigationTitle("Edit \(family.event)")
                    .navigationBarTitleDisplayModeInline()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingGame = nil } }
                    }
                }
            }
            .sheet(isPresented: $editingResult, onDismiss: { results = CompetitionStore.results() }) {
                if let last {
                    CompetitionResultForm(competition: last, existing: results[last.id], family: family, athlete: athlete)
                }
            }
        }
    }

    // MARK: Next

    private var nextSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SpaceSection(number(.next), "Next \(family.event)") {
                if adding {
                    Button("Cancel") { adding = false }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.brightRed)
                }
            }
            if adding {
                AddGameForm(athlete: athlete, family: family) {
                    adding = false
                    revision += 1
                    if let next { chance = Double(CompetitionStore.outlooks()[next.id]?.chance ?? 50) }
                    onChanged()
                }
            } else if let next, let days = daysToNext {
                // V8: the countdown is the one thing to see — big, on the green games card.
                AuraCard(.game, focus: UnitPoint(x: 0.22, y: 0.42), radius: 210) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(kindWord(next.kind)) · \(next.isHome ? "Home" : "Away")")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink.opacity(0.8))
                        if days > 1 {
                            BigFigure("\(days)", unit: "days to go", size: 84)
                        } else {
                            Text(days == 0 ? "Today" : "Tomorrow")
                                .font(.system(size: 60, weight: .bold))
                                .tracking(-1.2)
                                .foregroundStyle(AppTheme.ink)
                        }
                        if let note = next.notes, !note.isEmpty {
                            Text(note)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(next.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).hour().minute()))
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink.opacity(0.75))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                .contentShape(Rectangle())
                .onTapGesture { editingGame = next }
                .accessibilityAction(named: "Edit") { editingGame = next }
                // The twin, where it helps: before the game, what your best ones share.
                if let bestGames {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AuraTone.mind.mark)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("From your twin")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AuraTone.mind.mark)
                            Text(bestGames.text)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            // Its basis says it goes with, never decides (T7).
                            Text(bestGames.basis)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassSurface(cornerRadius: 18)
                    .accessibilityElement(children: .combine)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Your chance")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                        Text("\(Int(chance))% · \(CompetitionCoach.chanceWord(Int(chance)))")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(AuraTone.game.mark)
                    }
                    Slider(value: $chance, in: 0...100, step: 5, onEditingChanged: { editing in
                        if !editing { CompetitionStore.save(CompetitionOutlook(id: next.id, chance: Int(chance))) }
                    })
                    .tint(AuraTone.game.mark)
                    Text("Your own read — how you rate it, not a prediction.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                }
                .padding(16)
                .glassSurface(cornerRadius: 18)
                HStack(spacing: 10) {
                    Button { editingGame = next } label: { Text("Edit or delete") }
                        .buttonStyle(.secondary)
                    Button { adding = true } label: { Text("Add another") }
                        .buttonStyle(.secondary)
                }
            } else {
                Text("Nothing planned yet.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                Button { adding = true } label: { HeroCTALabel("Add your next \(family.event)") }
                    .buttonStyle(.primary)
            }
        }
    }

    // MARK: Coming up

    /// Everything planned after the next one (added here, by Tell AthleteOS
    /// or from a team calendar).
    private var comingUpSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SpaceSection(number(.comingUp), "Coming up") { Text("\(upcoming.count - 1)") }
            ForEach(Array(upcoming.dropFirst().prefix(8))) { game in
                Button { editingGame = game } label: { HStack(spacing: 12) {
                    Text(game.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.telemetry(12))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(width: 96, alignment: .leading)
                    Text([kindWord(game.kind), game.isHome ? "Home" : "Away", game.notes].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.mutedText)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle()) }
                .buttonStyle(.pressable)
                .accessibilityHint("Edit or delete")
            }
        }
    }

    private func kindWord(_ kind: CompetitionKind) -> String {
        switch kind {
        case .tournament: "Tournament"
        case .meet: family.event == "game" ? "Meet" : (family.tokens["Event"] ?? "Meet")
        case .game: family.tokens["Event"] ?? "Game"
        }
    }

    // MARK: Game prep

    /// Nerves mean you care: two minutes of breathing (free), the guided
    /// visualization (Pro), and what went well lately, to read before it starts.
    private var gamePrepSection: some View {
        let wins = MindsetStore.reflections.map(\.win).filter { !$0.isEmpty }.prefix(3)
        return VStack(alignment: .leading, spacing: 12) {
            SpaceSection(number(.gamePrep), "Game prep")
            Text("Nerves are normal — they mean you care. These get you calm and sharp.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                Button { routine = .breathing } label: {
                    ListRow(systemImage: "wind", color: AppTheme.purple, title: "2-minute breathing", detail: "Calm your nerves or lock in")
                }
                .buttonStyle(.pressable)
                Divider().padding(.leading, 54)
                Button {
                    if ProAccess.isPro { routine = .visualization } else { showingVisualizationPaywall = true }
                } label: {
                    ListRow(systemImage: "eye", color: AppTheme.purple, title: "Visualization", detail: "5 minutes: play the \(family.event) in your head first")
                }
                .buttonStyle(.pressable)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .glassSurface(cornerRadius: 18)
            if !wins.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Went well lately")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.mutedText)
                    ForEach(Array(wins.enumerated()), id: \.offset) { _, win in
                        Text(win)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink)
                    }
                }
                .padding(.top, 4)
            }
        }
        .fullScreenCover(item: $routine) { routine in
            switch routine {
            case .breathing: BreathingView()
            case .visualization: VisualizationView(sportName: AthleteStats.sportName(athlete))
            }
        }
        .proFeature(isPresented: $showingVisualizationPaywall, athlete: athlete, feature: .visualization)
    }

    // MARK: Until the next one

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SpaceSection(number(.focus), "Until the next one") { Text("\(focus.count) things") }
            ForEach(Array(focus.enumerated()), id: \.element.id) { index, point in
                HStack(alignment: .top, spacing: 14) {
                    Text("\(index + 1)")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(AuraTone.game.mark)
                        .frame(width: 22, alignment: .leading)
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
                            .buttonStyle(.pressable)
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
            SpaceSection(number(.last), "Last \(family.event)") {
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
            SpaceSection(number(.record), "Record") {
                Text("\(record.wins)–\(record.draws)–\(record.losses)")
            }
            ForEach(past.prefix(8)) { competition in
                Button { editingGame = competition } label: { HStack {
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
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.mutedText)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle()) }
                .buttonStyle(.pressable)
                .accessibilityHint("Edit or delete")
            }
        }
    }
}

/// The one add-a-game form (§10: "Add a game → the week visibly
/// rearranges"): the day, the start time when known, the type, home or away,
/// and a note. Shown inside the Competitions hub.
struct AddGameForm: View {
    let athlete: Athlete
    let family: SportFamily
    /// A game to change instead of adding a new one (date, time, type, place, note; or delete it).
    var editing: Competition? = nil
    /// Deleting is the owner's job (it closes the sheet before the model goes).
    var onDelete: ((Competition) -> Void)? = nil
    let onSaved: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var day = Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now
    @State private var knowsTime = false
    @State private var time = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: .now) ?? .now
    @State private var kind: CompetitionKind = .game
    @State private var isHome = true
    @State private var notes = ""
    @State private var loaded = false
    @State private var confirmingDelete = false

    /// New games start today at the earliest; an existing one can be moved anywhere.
    private var earliestDay: Date { editing == nil ? Calendar.current.startOfDay(for: .now) : .distantPast }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(editing == nil ? "Your week rearranges around it — heavy work early, sharp and fresh on the day."
                                : "Change anything — your week rearranges around the new day.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            DatePicker("Day", selection: $day, in: earliestDay..., displayedComponents: .date)
                .labelsHidden()
                .calendarDatePickerStyle()
                .tint(AppTheme.brightRed)
                .padding(10)
                .glassSurface(cornerRadius: 18)
            VStack(alignment: .leading, spacing: 10) {
                Toggle("I know the start time", isOn: $knowsTime)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .tint(AppTheme.brightRed)
                if knowsTime {
                    DatePicker("Starts at", selection: $time, displayedComponents: .hourAndMinute)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.ink)
                }
            }
            group("Type") {
                HStack(spacing: 8) {
                    chip(family.tokens["Event"] ?? "Game", on: kind == .game) { kind = .game }
                    chip("Tournament", on: kind == .tournament) { kind = .tournament }
                    chip("Meet", on: kind == .meet) { kind = .meet }
                }
            }
            group("Where") {
                HStack(spacing: 8) {
                    chip("Home", on: isHome) { isHome = true }
                    chip("Away", on: !isHome) { isHome = false }
                }
            }
            group("Note") {
                TextField("Opponent or event (optional)", text: $notes)
                    .padding(14)
                    .glassSurface(cornerRadius: 14)
            }
            Button(action: save) { HeroCTALabel(editing == nil ? "Save" : "Save changes") }
                .buttonStyle(.primary)
            if editing != nil, onDelete != nil {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label("Delete this \(family.event)", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.pressable)
                .confirmationDialog("Delete this \(family.event)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive, action: delete)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your plan around it goes back to normal. Its result and notes are deleted too.")
                }
            }
        }
        .onAppear(perform: load)
    }

    /// Fills the form from the game being changed (once).
    private func load() {
        guard !loaded, let game = editing else { return }
        loaded = true
        let calendar = Calendar.current
        day = game.date
        let minutes = calendar.component(.hour, from: game.date) * 60 + calendar.component(.minute, from: game.date)
        knowsTime = minutes > 0
        if knowsTime { time = game.date }
        kind = game.kind
        isHome = game.isHome
        notes = game.notes ?? ""
    }

    private func delete() {
        guard let game = editing else { return }
        onDelete?(game)
    }

    /// Midnight means "time unknown" (the usual start time is used then).
    private var date: Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard knowsTime else { return start }
        let minutes = calendar.component(.hour, from: time) * 60 + calendar.component(.minute, from: time)
        return calendar.date(byAdding: .minute, value: max(1, minutes), to: start) ?? start
    }

    private func save() {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if let game = editing {
            game.date = date
            game.kind = kind
            game.isHome = isHome
            game.notes = trimmed.isEmpty ? nil : trimmed
            try? modelContext.save()
            onSaved()
            return
        }
        modelContext.insert(Competition(sportSlug: athlete.activeSport?.sportSlug ?? "general", date: date, kind: kind, isHome: isHome,
                                        notes: trimmed.isEmpty ? nil : trimmed, athlete: athlete))
        try? modelContext.save()
        onSaved()
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.secondaryText)
            content()
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(on ? Color(rgb: 0x0B0B14) : AppTheme.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(on ? AppTheme.accent : Color.white.opacity(0.04)))
                .overlay { Capsule().strokeBorder(Color.white.opacity(on ? 0 : 0.12), lineWidth: 1) }
        }
        .buttonStyle(.pressable)
    }
}

/// How the last competition went: result, score, how you played, what went
/// well, what to improve. Feeds "until the next one".
struct CompetitionResultForm: View {
    let competition: Competition
    let existing: CompetitionResult?
    let family: SportFamily
    /// Whose twin learns from the rating ("Your twin is learning …").
    var athlete: Athlete? = nil

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
                                        .background(Circle().fill(n == rating ? AppTheme.accent : Color.white.opacity(0.05)))
                                        .overlay { Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
                                }
                                .buttonStyle(.pressable)
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
        var twinBefore: TwinKnowledge?
        if let athlete { twinBefore = TwinPulse.before(athlete) }
        CompetitionStore.save(CompetitionResult(
            id: competition.id, outcome: outcome, placement: outcome == .placed ? placement : nil,
            score: score.trimmingCharacters(in: .whitespaces).isEmpty ? nil : score.trimmingCharacters(in: .whitespaces),
            rating: rating, wentWell: EveningOptions.areas.filter(wentWell.contains), toImprove: EveningOptions.areas.filter(toImprove.contains),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note))
        AcademyEvent.log(.reflectionSubmitted)
        if let athlete, let twinBefore { TwinPulse.after(athlete, before: twinBefore, input: .gameRating) }
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
                .background(Capsule().fill(on ? AppTheme.accent : Color.white.opacity(0.04)))
                .overlay { Capsule().strokeBorder(Color.white.opacity(on ? 0 : 0.12), lineWidth: 1) }
        }
        .buttonStyle(.pressable)
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

extension View {
    /// A month-grid date picker on iPhone; watchOS has no graphical style, so
    /// it keeps the platform default there.
    @ViewBuilder
    func calendarDatePickerStyle() -> some View {
        #if os(iOS)
        datePickerStyle(.graphical)
        #else
        self
        #endif
    }
}
