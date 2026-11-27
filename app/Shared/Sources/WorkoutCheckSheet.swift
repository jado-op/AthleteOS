import SwiftData
import SwiftUI

/// After a workout from Apple Health (owner, 2026-11-20): a few taps, one
/// question at a time, the next time the app opens. How hard (Foster's
/// CR-10, the validated session rating), what it trained (regions, or the
/// exact exercises), how hard each part worked when more than one was
/// ticked, whether anything hurt (and where), then what the answer changed:
/// when each part is ready again and what the twin now shows. Every step can
/// be put off; the workout counts either way. Rules: `WorkoutTagging`;
/// saving: `HealthWorkoutInbox`.
struct WorkoutCheckSheet: View {
    let session: Session
    let catalogue: Catalogue
    let sports: [SportVisibility.Sport]
    /// Screenshots open later steps (`-sheet workoutCheckTrained|workoutCheckDone`).
    var startStep: Step = .effort
    let onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    enum Step: Hashable { case effort, trained, split, hurt, pain, done }

    @State private var step: Step = .effort
    @State private var rating: Int?
    @State private var regions: Set<GymRegion> = []
    @State private var cardio = false
    @State private var bands: [GymRegion: WorkoutTagging.Band] = [:]
    @State private var exercises: [CatalogueItem] = []
    @State private var hurt = false
    @State private var painAreas: Set<PainArea> = []
    @State private var painLevel: PainLevel = .some
    @State private var estimate: Int?
    @State private var heartRate: Int?
    @State private var pickingExercise = false
    @State private var confirmingRemove = false
    @State private var savedCount = 0
    @State private var prepared = false

    private var activity: String { HealthWorkoutInbox.activity(of: session) }

    private var device: String {
        let parts = (session.notes ?? "").components(separatedBy: " · from your ")
        return parts.count > 1 ? parts[1] : "watch"
    }

    private var when: String {
        let calendar = Calendar.current
        let day = calendar.isDateInToday(session.startedAt) ? "Today" : "Yesterday"
        return "\(day), \(session.startedAt.formatted(date: .omitted, time: .shortened))"
    }

    private var steps: [Step] {
        [.effort, .trained] + (regions.count > 1 ? [.split] : []) + [.hurt] + (hurt ? [.pain] : []) + [.done]
    }

    private var progress: Double {
        Double((steps.firstIndex(of: step) ?? 0) + 1) / Double(steps.count)
    }

    private var answer: WorkoutTagging.Answer {
        var picked: [GymRegion: WorkoutTagging.Band] = [:]
        for region in regions { picked[region] = bands[region] ?? defaultBand }
        return WorkoutTagging.Answer(rating: rating, regions: picked, cardio: cardio, hurt: hurt, exercises: exercises.map(\.slug))
    }

    var body: some View {
        page
            .animation(.easeInOut(duration: 0.22), value: step)
            .sensoryFeedback(.selection, trigger: rating)
            .sensoryFeedback(.success, trigger: savedCount)
            .sheet(isPresented: $pickingExercise) {
                ExercisePickerSheet(catalogue: catalogue, sports: sports) { item in
                    if !exercises.contains(where: { $0.slug == item.slug }) { exercises.append(item) }
                    regions.formUnion(Self.regions(of: item))
                }
            }
            .confirmationDialog("Not a training session?", isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button("Remove it", role: .destructive) {
                    HealthWorkoutInbox.remove(session, context: modelContext)
                    finish()
                }
            } message: {
                Text("It won't count as today's training, and AthleteOS won't add it again.")
            }
            .onAppear(perform: prepare)
    }

    @ViewBuilder private var page: some View {
        switch step {
        case .effort:
            QuestionPage(progress: progress, question: "How hard was it overall?",
                         hint: "Think of the whole session, not just the end.",
                         buttonTitle: rating == nil ? nil : "Next", onClose: later, onButton: { go(.trained) }, tone: .training) {
                workoutCard
                effortScale
                ButtonRow {
                    Button(action: later) { Label("Ask me later", systemImage: "clock") }
                        .buttonStyle(.secondary)
                    Button { confirmingRemove = true } label: { Label("Not training", systemImage: "xmark.circle") }
                        .buttonStyle(.secondary)
                }
                .padding(.top, 6)
            }
        case .trained:
            QuestionPage(progress: progress, question: "What did it train?", hint: "Tick everything that worked. Your gym plan rests what you trained.",
                         buttonTitle: "Next", buttonEnabled: !regions.isEmpty || cardio, onClose: later, onBack: { go(.effort) },
                         onButton: { go(regions.count > 1 ? .split : .hurt) }, tone: .training) {
                regionGrid
                Button { cardio.toggle() } label: {
                    OptionRow(title: "Mostly running or cardio", subtitle: "Counts for your legs, a little easier", systemImage: "heart.fill",
                              isSelected: cardio)
                }
                .buttonStyle(.pressable)
                exerciseList
            }
        case .split:
            QuestionPage(progress: progress, question: "Which part worked hardest?", hint: "Each part rests as long as its effort needs.",
                         buttonTitle: "Next", onClose: later, onBack: { go(.trained) }, onButton: { go(.hurt) }, tone: .training) {
                ForEach([GymRegion.lower, .upper, .core].filter { regions.contains($0) }, id: \.self) { region in
                    bandPicker(region)
                }
            }
        case .hurt:
            QuestionPage(progress: progress, question: "Did anything hurt?", hint: "Pain, not the usual muscle burn.",
                         buttonTitle: nil, onClose: later, onBack: { go(regions.count > 1 ? .split : .trained) }, tone: .training) {
                HStack(spacing: 10) {
                    Button { hurt = false; save() } label: {
                        IconTile(symbol: "checkmark.circle.fill", title: "All good", detail: "Nothing hurt", tint: AuraTone.game.mark, isSelected: false)
                    }
                    .buttonStyle(.pressable)
                    Button { hurt = true; go(.pain) } label: {
                        IconTile(symbol: "bandage.fill", title: "Something hurt", detail: "Tell us where", tint: AppTheme.danger, isSelected: false)
                    }
                    .buttonStyle(.pressable)
                }
            }
        case .pain:
            QuestionPage(progress: progress, question: "Where does it hurt?", hint: "Tap every spot. This goes into today's pain check.",
                         buttonTitle: "Save", buttonEnabled: !painAreas.isEmpty, onClose: later, onBack: { hurt = false; go(.hurt) },
                         onButton: save, tone: .training) {
                WrapLayout(spacing: 8) {
                    ForEach(PainArea.allCases) { area in
                        Button {
                            if painAreas.contains(area) { painAreas.remove(area) } else { painAreas.insert(area) }
                        } label: {
                            Chip(area.title, isSelected: painAreas.contains(area))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("How much?")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                    .padding(.top, 6)
                ChoiceGrid(PainLevel.allCases, title: { $0.title }, isSelected: { $0 == painLevel }) { painLevel = $0 }
                Label("Stop that movement and get it checked. Tomorrow's plan stays lighter.", systemImage: "cross.case.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .done:
            QuestionPage(progress: 1, question: "Saved.", hint: "Here's what it changed.", buttonTitle: "Done",
                         onClose: finish, onButton: finish, tone: .training) {
                summary
            }
        }
    }

    // MARK: The workout

    private var workoutCard: some View {
        AuraCard(.training, focus: .topTrailing, radius: 240, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: WorkoutTagging.symbol(forActivity: activity))
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Color.white.opacity(0.16), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(activity)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        Text("\(when) · \(device)")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline, spacing: 22) {
                    stat("\(session.minutes)", unit: "min")
                    if let heartRate { stat("\(heartRate)", unit: "bpm avg") }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func stat(_ value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 34, weight: .light).monospacedDigit())
                .foregroundStyle(.white)
            Text(unit)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: Effort

    private var effortScale: some View {
        EffortScale(rating: $rating, estimate: estimate,
                    estimateNote: estimate.map { "Your heart rate suggests about \($0) (the dot). How it felt decides." })
    }

    /// Easy blue → steady teal → working ember → very hard red-orange → maximal red.
    static func color(_ rating: Int) -> Color {
        switch rating {
        case ...2: Color(rgb: 0x6E9BFF)
        case 3, 4: Color(rgb: 0x4FD1C5)
        case 5, 6: Color(rgb: 0xFB923C)
        case 7, 8: Color(rgb: 0xF2542D)
        default: Color(rgb: 0xE11D48)
        }
    }

    static func color(band: WorkoutTagging.Band) -> Color {
        switch band {
        case .light: color(2)
        case .solid: color(5)
        case .veryHard: color(8)
        }
    }

    // MARK: What it trained

    private struct RegionChoice: Identifiable {
        let region: GymRegion?
        let symbol: String
        let title: String
        let detail: String
        var id: String { region?.rawValue ?? "full" }
    }

    private static let choices: [RegionChoice] = [
        RegionChoice(region: .upper, symbol: "figure.arms.open", title: "Upper body", detail: "Chest, back, shoulders, arms"),
        RegionChoice(region: .lower, symbol: "figure.step.training", title: "Legs", detail: "Quads, glutes, hamstrings, calves"),
        RegionChoice(region: .core, symbol: "figure.core.training", title: "Core", detail: "Abs and trunk"),
        RegionChoice(region: nil, symbol: "figure.strengthtraining.functional", title: "Full body", detail: "A bit of everything"),
    ]

    private static func symbol(_ region: GymRegion) -> String {
        choices.first { $0.region == region }?.symbol ?? "figure.walk"
    }

    private var regionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(Self.choices) { choice in
                let selected = choice.region.map { regions.contains($0) } ?? (regions.count == GymRegion.allCases.count)
                Button {
                    if let region = choice.region {
                        if regions.contains(region) { regions.remove(region) } else { regions.insert(region) }
                    } else {
                        regions = regions.count == GymRegion.allCases.count ? [] : Set(GymRegion.allCases)
                    }
                } label: {
                    IconTile(symbol: choice.symbol, title: choice.title, detail: choice.detail, tint: AuraTone.training.mark, isSelected: selected)
                }
                .buttonStyle(.pressable)
            }
        }
        .sensoryFeedback(.selection, trigger: regions)
    }

    @ViewBuilder private var exerciseList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !exercises.isEmpty {
                Text("Exercises")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                WrapLayout(spacing: 8) {
                    ForEach(exercises) { item in
                        Button {
                            exercises.removeAll { $0.slug == item.slug }
                        } label: {
                            HStack(spacing: 6) {
                                Text(item.name).lineLimit(1)
                                Image(systemName: "xmark").font(.caption.weight(.bold))
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(AuraTone.training.mark.opacity(0.2), in: Capsule())
                            .overlay { Capsule().strokeBorder(AuraTone.training.mark.opacity(0.6), lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(item.name)")
                    }
                }
            }
            Button { pickingExercise = true } label: {
                Label(exercises.isEmpty ? "Add the exact exercises" : "Add another exercise", systemImage: "plus")
            }
            .buttonStyle(.secondary)
        }
        .padding(.top, 4)
    }

    // MARK: Per-part effort

    private func bandPicker(_ region: GymRegion) -> some View {
        let chosen = bands[region] ?? defaultBand
        return VStack(alignment: .leading, spacing: 10) {
            Label(MuscleTraining.capitalized(region.title), systemImage: Self.symbol(region))
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            HStack(spacing: 6) {
                ForEach(WorkoutTagging.Band.allCases, id: \.self) { band in
                    let selected = chosen == band
                    Button { bands[region] = band } label: {
                        Text(band.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(selected ? Color.black : AppTheme.ink)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(selected ? Self.color(band: band) : Color.white.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(4)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .animation(.snappy(duration: 0.18), value: chosen)
        }
    }

    // MARK: What it changed

    private var summary: some View {
        let ready = WorkoutTagging.readyAfter(answer, minutes: session.minutes)
        return VStack(alignment: .leading, spacing: 14) {
            AuraCard(.training, focus: .topLeading, radius: 230, padding: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(rating.map(String.init) ?? "–")
                            .font(.system(size: 60, weight: .light).monospacedDigit())
                            .foregroundStyle(.white)
                        Text(rating.map(WorkoutTagging.word) ?? "Not rated")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Text("\(session.minutes) min of \(activity.lowercased()), counted as today's training.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !ready.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ready for hard work again")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    ForEach(ready, id: \.region) { entry in
                        ListRow(systemImage: Self.symbol(entry.region), color: AuraTone.training.mark,
                                title: MuscleTraining.capitalized(entry.region.title)) {
                            Text(readyText(entry.days))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.08), in: Capsule())
                        }
                    }
                }
            }
            ListRow(systemImage: "figure.stand.line.dotted.figure.stand", color: AuraTone.mind.mark, title: "In your twin",
                    detail: "Body map and weekly training updated") { EmptyView() }
            if hurt {
                Label("Stop that movement and get it checked. Tomorrow's plan stays lighter.", systemImage: "cross.case.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func readyText(_ days: Int) -> String {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: session.startedAt)) ?? .now
        if day <= calendar.startOfDay(for: .now) { return "Ready now" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide))
    }

    private var defaultBand: WorkoutTagging.Band { WorkoutTagging.band(forRating: rating ?? 5) }

    // MARK: Actions

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        step = startStep
        if regions.isEmpty { regions = WorkoutTagging.guessedRegions(activity: activity) }
        if WorkoutTagging.kind(ofActivity: activity) == .cardio { cardio = true }
        // The import's heart-rate estimate, shown as a hint, never pre-picked.
        if HealthWorkoutInbox.answer(for: session) == nil { estimate = session.sessionRPE }
        if let id = session.healthKitWorkoutId,
           let average = ExternalWorkoutStore.recent.first(where: { $0.id == id })?.averageHeartRate {
            heartRate = Int(average.rounded())
        }
        if DemoData.isEnabled, startStep != .effort {
            rating = 7
            regions = [.lower, .core]
            bands[.core] = .light
        }
    }

    private func go(_ next: Step) { step = next }

    private func save() {
        if !DemoData.isEnabled {
            HealthWorkoutInbox.save(answer, for: session, painAreas: Array(painAreas), painLevel: painLevel, context: modelContext)
        }
        savedCount += 1
        go(.done)
    }

    /// "Ask me later" (and ✕ before saving): asked again in a few hours.
    private func later() {
        HealthWorkoutInbox.later(session)
        finish()
    }

    private func finish() {
        onDone()
        dismiss()
    }

    /// The regions an exercise works, from its profile (as the gym planner reads them).
    static func regions(of item: CatalogueItem) -> Set<GymRegion> {
        let profile = item.planProfile
        var result: Set<GymRegion> = []
        if profile.isLower { result.insert(.lower) }
        if profile.isUpper, !profile.isLower { result.insert(.upper) }
        if profile.role == "trunk" { result.insert(.core) }
        return result
    }
}

/// A big square choice with an icon: tinted edge and glow when picked.
struct IconTile: View {
    let symbol: String
    let title: String
    let detail: String?
    let tint: Color
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : tint)
                    .frame(width: 48, height: 48)
                    .background(isSelected ? tint : tint.opacity(0.16), in: Circle())
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? tint : AppTheme.mutedText)
            }
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(isSelected ? tint.opacity(0.18) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isSelected ? tint : Color.white.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.18), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The session-effort scale (CR-10, Foster): the chosen number big in its
/// colour with Foster's word and how it feels; 0–10 tiles tinted from easy
/// blue to maximal red. Shared by the workout check and the evening's practice.
struct EffortScale: View {
    @Binding var rating: Int?
    /// A measured hint (heart rate), shown as a dot — never pre-picked.
    var estimate: Int?
    var estimateNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let rating {
                    Text("\(rating)")
                        .font(.system(size: 64, weight: .light).monospacedDigit())
                        .foregroundStyle(WorkoutCheckSheet.color(rating))
                        .contentTransition(.numericText())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(rating.map(WorkoutTagging.word) ?? "Pick a number")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(rating.map(WorkoutTagging.feel) ?? "0 is rest, 10 is the hardest you can go.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .animation(.snappy(duration: 0.2), value: rating)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(0...10, id: \.self) { value in
                    tile(value)
                }
            }
            if let estimateNote {
                Label(estimateNote, systemImage: "heart.text.square")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tile(_ value: Int) -> some View {
        let selected = rating == value
        let color = WorkoutCheckSheet.color(value)
        return Button { rating = value } label: {
            Text("\(value)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(selected ? Color.black : color)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(selected ? color : color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(color.opacity(selected ? 0 : 0.35), lineWidth: 1)
                }
                .overlay(alignment: .topTrailing) {
                    if estimate == value {
                        Circle().fill(selected ? Color.black : Color.white).frame(width: 6, height: 6).padding(7)
                    }
                }
                .scaleEffect(selected ? 1.06 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value), \(WorkoutTagging.word(value))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
