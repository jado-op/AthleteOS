import SwiftData
import SwiftUI

/// After a workout from Apple Health (owner, 2026-11-20): a few taps, one
/// question at a time, the next time the app opens. How hard (Foster's
/// CR-10, the validated session rating), what it trained (regions, or the
/// exact exercises), how hard each part worked when more than one was
/// ticked, and whether anything hurt. Every step can be skipped; the workout
/// counts either way. Rules: `WorkoutTagging`; saving: `HealthWorkoutInbox`.
struct WorkoutCheckSheet: View {
    let session: Session
    let catalogue: Catalogue
    let sports: [SportVisibility.Sport]
    let onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    enum Step: Hashable { case effort, trained, split, hurt }

    @State private var step: Step = .effort
    @State private var rating: Int?
    @State private var regions: Set<GymRegion> = []
    @State private var cardio = false
    @State private var bands: [GymRegion: WorkoutTagging.Band] = [:]
    @State private var exercises: [CatalogueItem] = []
    @State private var pickingExercise = false
    @State private var confirmingRemove = false

    /// "Strength training · from your Apple Watch" → "Strength training".
    private var activity: String { HealthWorkoutInbox.activity(of: session) }

    private var device: String {
        let parts = (session.notes ?? "").components(separatedBy: " · from your ")
        return parts.count > 1 ? parts[1] : "watch"
    }

    private var when: String {
        let calendar = Calendar.current
        let day = calendar.isDateInToday(session.startedAt) ? "today" : "yesterday"
        return "\(day) at \(session.startedAt.formatted(date: .omitted, time: .shortened))"
    }

    private var steps: [Step] {
        [.effort, .trained] + (regions.count > 1 ? [.split] : []) + [.hurt]
    }

    private var progress: Double {
        Double((steps.firstIndex(of: step) ?? 0) + 1) / Double(steps.count + 1)
    }

    var body: some View {
        page
            .animation(.easeInOut(duration: 0.2), value: step)
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
            .onAppear {
                if regions.isEmpty { regions = WorkoutTagging.guessedRegions(activity: activity) }
                if WorkoutTagging.kind(ofActivity: activity) == .cardio { cardio = true }
            }
    }

    @ViewBuilder private var page: some View {
        switch step {
        case .effort:
            QuestionPage(progress: progress, question: "How hard was it overall?",
                         hint: "Your \(session.minutes)-min \(activity.lowercased()) from your \(device), \(when). Think of the whole session, not just the end.",
                         buttonTitle: rating == nil ? nil : "Next", onClose: later, onButton: { go(.trained) }, tone: .training) {
                effortScale
                quietButton("Not a training session") { confirmingRemove = true }
                quietButton("Ask me later") { later() }
            }
        case .trained:
            QuestionPage(progress: progress, question: "What did it train?", hint: "Tick everything that worked. It tells your gym plan what needs rest.",
                         buttonTitle: "Next", onClose: later, onBack: { go(.effort) }, onButton: { go(regions.count > 1 ? .split : .hurt) },
                         tone: .training) {
                ChoiceGrid(GymRegion.allCases.map { Optional($0) } + [nil], title: { ($0?.title).map(MuscleTraining.capitalized) ?? "Full body" },
                           isSelected: { region in region.map { regions.contains($0) } ?? (regions.count == GymRegion.allCases.count) }) { region in
                    if let region {
                        if regions.contains(region) { regions.remove(region) } else { regions.insert(region) }
                    } else {
                        regions = regions.count == GymRegion.allCases.count ? [] : Set(GymRegion.allCases)
                    }
                }
                Button { cardio.toggle() } label: {
                    OptionRow(title: "Mostly running or cardio", subtitle: "Counts for your legs, a little easier", isSelected: cardio)
                }
                .buttonStyle(.plain)
                exerciseList
            }
        case .split:
            QuestionPage(progress: progress, question: "Which part worked hardest?", hint: "Optional. Each part rests as long as its effort needs.",
                         buttonTitle: "Next", onClose: later, onBack: { go(.trained) }, onButton: { go(.hurt) }, tone: .training) {
                ForEach(GymRegion.allCases.filter { regions.contains($0) }, id: \.self) { region in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(MuscleTraining.capitalized(region.title)).font(.headline).foregroundStyle(AppTheme.ink)
                        HStack(spacing: 8) {
                            ForEach(WorkoutTagging.Band.allCases, id: \.self) { band in
                                Button { bands[region] = band } label: {
                                    Chip(band.title, isSelected: (bands[region] ?? defaultBand) == band)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        case .hurt:
            QuestionPage(progress: progress, question: "Did anything hurt?", hint: "Pain, not the usual muscle burn.",
                         buttonTitle: nil, onClose: later, onBack: { go(regions.count > 1 ? .split : .trained) }, tone: .training) {
                ChoiceGrid([false, true], title: { $0 ? "Yes" : "No" }, isSelected: { _ in false }) { hurt in
                    save(hurt: hurt)
                }
                Text("If something hurts, stop that movement and get it checked. Tomorrow's plan stays lighter.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Pieces

    /// 0–10 in two rows, the validated word under the chosen number.
    private var effortScale: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(0...10, id: \.self) { value in
                    Button { rating = value } label: {
                        Text("\(value)")
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(rating == value ? AppTheme.background : AppTheme.ink)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(rating == value ? AppTheme.ink : AppTheme.fill,
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(value), \(WorkoutTagging.word(value))")
                }
            }
            Text(rating.map(WorkoutTagging.word) ?? "0 is rest, 10 is the hardest you can go.")
                .font(rating == nil ? .subheadline : .title2.weight(.bold))
                .foregroundStyle(rating == nil ? AppTheme.secondaryText : AppTheme.ink)
                .animation(nil, value: rating)
        }
    }

    @ViewBuilder private var exerciseList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(exercises) { item in
                HStack {
                    Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
                    Spacer()
                    Button {
                        exercises.removeAll { $0.slug == item.slug }
                    } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(AppTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(item.name)")
                }
            }
            Button { pickingExercise = true } label: {
                Label(exercises.isEmpty ? "Or pick the exact exercises" : "Add another exercise", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private func quietButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var defaultBand: WorkoutTagging.Band { WorkoutTagging.band(forRating: rating ?? 5) }

    // MARK: Actions

    private func go(_ next: Step) { step = next }

    private func save(hurt: Bool) {
        var picked: [GymRegion: WorkoutTagging.Band] = [:]
        for region in regions { picked[region] = bands[region] ?? defaultBand }
        let answer = WorkoutTagging.Answer(rating: rating, regions: picked, cardio: cardio, hurt: hurt,
                                           exercises: exercises.map(\.slug))
        HealthWorkoutInbox.save(answer, for: session, context: modelContext)
        finish()
    }

    private func later() {
        HealthWorkoutInbox.skip(session)
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
