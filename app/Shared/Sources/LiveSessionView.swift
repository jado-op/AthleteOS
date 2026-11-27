import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

/// §15: "The live session screen gets the most attention after Today:
/// current item with its pose animation and muscle map, prefilled targets
/// from last time, big steppers, an automatic rest timer, collapsible cues,
/// next and previous. One-handed, sweaty-hands, glanceable, screen stays
/// awake. It ends with the single RPE question and nothing else."
///
/// Started from today's plan it walks that plan item by item; started empty
/// ("Log a workout") it's a free log where exercises are added as you go.
@MainActor
public struct LiveSessionView: View {
    let athlete: Athlete
    let apiClient: APIClient
    let planned: GeneratedSession?
    /// Which kind of workout this is, for the Progress calendar's colours.
    let kind: WorkoutKind?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var session: Session?
    @State private var catalogue = Catalogue()
    @State private var queue: [GeneratedPlannedItem] = []
    @State private var index = 0
    /// Sets logged per queue position (an exercise that appears twice counts twice).
    @State private var setsLogged: [Int: Int] = [:]
    /// Positions the athlete skipped (count as done for finishing).
    @State private var skipped: Set<Int> = []
    /// The picker replaces the current exercise instead of adding one.
    @State private var swapping = false
    @State private var reps = 8
    @State private var weightKg: Double = 0
    @State private var seconds = 30
    @State private var distanceM: Double = 20
    @State private var contacts = 10
    @State private var restRemaining = 0
    @State private var restTotal = 0
    /// When the rest ends — the clock follows this, so a locked phone doesn't pause it.
    @State private var restEndsAt: Date?
    @Environment(\.scenePhase) private var scenePhase
    @State private var restTask: Task<Void, Never>?
    @State private var showingCues = false
    @State private var showingPicker = false
    @State private var showingList = false
    @State private var showingEndOptions = false
    @State private var showingRPE = false
    @State private var rpe = 6
    @State private var loggedCount = 0
    @State private var restEndedCount = 0
    @State private var startedAt = Date.now
    /// Why today's target differs from last time (progressive overload).
    @State private var targetNote: String?
    /// "Last time: 3 × 8 · 40 kg" — what this exercise was the last time.
    @State private var lastTimeNote: String?
    /// "New best: 45 kg" after a set heavier than ever before.
    @State private var bestNote: String?
    @State private var bestCount = 0
    @State private var heartRate: HeartRateSummary?
    /// Talking mid-workout (owner, 2026-11-27): what was heard, shown for a moment.
    @State private var voiceNote: String?
    @State private var voiceNoteCount = 0
    /// "My knee hurts": the stop-and-get-checked prompt for that place.
    @State private var painHeard: PainArea?
    #if os(iOS) && !APP_EXTENSION
    @StateObject private var voice = WorkoutVoiceListener()
    #endif
    @AppStorage(WeightUnit.storageKey) private var unitRaw = WeightUnit.current.rawValue

    private var unit: WeightUnit { WeightUnit(rawValue: unitRaw) ?? .kg }

    /// Every planned set is logged — time to finish.
    private var allDone: Bool {
        !queue.isEmpty && queue.indices.allSatisfy { isFinished($0) }
    }

    private func isFinished(_ position: Int) -> Bool {
        skipped.contains(position) || setsLogged[position, default: 0] >= queue[position].dose.sets
    }

    /// An interrupted workout to carry on: its sets stay, the rest continues.
    let resuming: Session?

    public init(athlete: Athlete, apiClient: APIClient, planned: GeneratedSession? = nil, kind: WorkoutKind? = nil,
                resuming: Session? = nil) {
        self.resuming = resuming
        self.athlete = athlete
        self.apiClient = apiClient
        self.planned = planned
        self.kind = kind
    }

    private var current: GeneratedPlannedItem? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    private var currentItem: CatalogueItem? {
        current.flatMap { catalogue.item($0.itemSlug) }
    }

    private var totalTargetSets: Int {
        max(queue.reduce(0) { $0 + $1.dose.sets }, 1)
    }

    private var totalLogged: Int {
        setsLogged.values.reduce(0, +)
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
            if let current {
                // V8, one screen: everything a set needs is visible without
                // scrolling — what it is, how it looks, the set and the dose,
                // what comes next. Details open on a tap.
                VStack(alignment: .leading, spacing: 14) {
                    itemHeader(current)
                    figurePanel
                        .frame(minHeight: 96, maxHeight: .infinity)
                    statusCard(current)
                    if restRemaining == 0 && !allDone {
                        doseControls(current)
                    }
                    nextRow
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .animation(.easeInOut(duration: 0.3), value: restRemaining > 0)
                .animation(.easeInOut(duration: 0.3), value: index)
                bottomBar(current)
            } else {
                emptyState
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .appScreen()
        .sensoryFeedback(.success, trigger: loggedCount)
        .sensoryFeedback(.warning, trigger: restEndedCount)
        .task { await start() }
        // Locked or left during a rest: one alert when it's over (none while watching).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { RestAlarm.cancel() } else if restRemaining > 0 { RestAlarm.schedule(at: restEndsAt) }
        }
        .onDisappear {
            restTask?.cancel()
            setIdleTimerDisabled(false)
            #if os(iOS) && !APP_EXTENSION
            voice.stop()
            #endif
        }
        #if os(iOS) && !APP_EXTENSION
        .onAppear { voice.onCommand = { applyVoice($0) } }
        #endif
        .overlay(alignment: .top) {
            if let voiceNote {
                Label(voiceNote, systemImage: "waveform")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
                    .background(Color.black.opacity(0.85), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    .padding(.top, 64)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: voiceNote)
        .alert(painHeard == .head ? "Stop training now" : "Stop this exercise", isPresented: Binding(
            get: { painHeard != nil }, set: { if !$0 { painHeard = nil } })) {
            if painHeard != .head {
                Button("Skip this exercise") { recordPain(); skipCurrent() }
            }
            Button("End the workout", role: .destructive) {
                recordPain()
                if totalLogged == 0 { discard() } else { showingRPE = true }
            }
            Button("It's fine, keep going", role: .cancel) { painHeard = nil }
        } message: {
            Text(painHeard == .head
                 ? "A knock to the head or feeling dizzy means no more training today. Tell a coach or parent now."
                 : "Pain means stop. Tell a coach, athletic trainer or parent, and get it checked if it doesn't go away. Today's plan will leave it alone.")
        }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerSheet(catalogue: catalogue, sports: SportVisibility.sports(for: athlete)) { item in
                if swapping { swap(to: item) } else { add(item) }
                swapping = false
            }
        }
        .sheet(isPresented: $showingCues) {
            howToSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingList) {
            exerciseListSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingRPE) {
            RPEPromptView(rpe: $rpe, heartRate: heartRate, recap: recap(), onKeepTraining: { showingRPE = false }) { finish() }
                .task {
                    guard let session else { return }
                    let asked = rpe
                    heartRate = await HealthKitManager.shared.heartRate(from: session.startedAt, to: .now)
                    // A watch saw the effort: start the question from there — unless
                    // the athlete already picked a number.
                    if let heartRate, rpe == asked {
                        rpe = WearableLoad.effort(averageHeartRate: Double(heartRate.average), minutes: Int(Date.now.timeIntervalSince(session.startedAt) / 60),
                                                  age: PlanGenerator.ageInYears(birthDate: athlete.birthDate, now: .now))
                    }
                }
                .presentationDetents([.large])
                .interactiveDismissDisabled()
        }
        .confirmationDialog("End this session?", isPresented: $showingEndOptions, titleVisibility: .visible) {
            Button("Finish and save") { showingRPE = true }
            Button("Discard session", role: .destructive) { discard() }
            Button("Keep training", role: .cancel) {}
        }
    }

    // MARK: - Chrome

    /// Close, the whole workout as one segment per exercise, the clock,
    /// the list of exercises and Finish.
    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                CircleIconButton(systemImage: "xmark", accessibilityLabel: "End session") {
                    if totalLogged == 0 {
                        discard()
                    } else {
                        showingEndOptions = true
                    }
                }
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    Text(elapsedText(context.date))
                        .font(.system(size: 20, weight: .semibold).monospacedDigit())
                        .foregroundStyle(AppTheme.ink)
                }
                .accessibilityLabel("Time")
                Spacer()
                #if os(iOS) && !APP_EXTENSION
                CircleIconButton(systemImage: voice.isListening ? "mic.fill" : "mic",
                                 accessibilityLabel: voice.isListening ? "Stop listening" : "Talk to AthleteOS") {
                    let wasListening = voice.isListening
                    voice.toggle()
                    if !wasListening { showVoiceNote("Listening: say \u{201C}that was heavy\u{201D}, \u{201C}two more\u{201D}, \u{201C}skip\u{201D}") }
                }
                .onChange(of: voice.status) { _, status in
                    if case .unavailable(let reason) = status { showVoiceNote(reason) }
                }
                #endif
                if !queue.isEmpty {
                    CircleIconButton(systemImage: "list.bullet", accessibilityLabel: "All exercises") { showingList = true }
                }
                Button(totalLogged == 0 ? "Close" : "Finish") {
                    if totalLogged == 0 { discard() } else { showingRPE = true }
                }
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
                .frame(minWidth: 44, minHeight: 44)
            }
            if !queue.isEmpty {
                segments
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// One bar per exercise, filling set by set; the current one in ember.
    private var segments: some View {
        HStack(spacing: 4) {
            ForEach(Array(queue.enumerated()), id: \.offset) { position, item in
                let fraction = Double(min(setsLogged[position, default: 0], max(item.dose.sets, 1))) / Double(max(item.dose.sets, 1))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(position == index ? 0.28 : 0.14))
                        Capsule()
                            .fill(skipped.contains(position) && fraction < 1 ? Color.white.opacity(0.3) : AuraTone.training.mark)
                            .frame(width: geo.size.width * (skipped.contains(position) && fraction < 1 ? 1 : fraction))
                    }
                }
                .frame(height: 5)
            }
        }
        .animation(.easeOut(duration: 0.4), value: totalLogged)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exercise \(index + 1) of \(queue.count), \(totalLogged) of \(totalTargetSets) sets done")
    }

    private func elapsedText(_ now: Date) -> String {
        let total = Int(now.timeIntervalSince(startedAt))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "3 of 8 · Power", the name big, and one small note (a best, a target
    /// or last time). Swap, skip, add and units live in the menu.
    private func itemHeader(_ current: GeneratedPlannedItem) -> some View {
        let done = setsLogged[index, default: 0]
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(index + 1) of \(queue.count)")
                        .foregroundStyle(AppTheme.secondaryText)
                    if let whyLine {
                        Text("·").foregroundStyle(AppTheme.secondaryText)
                        Text(whyLine).foregroundStyle(AuraTone.training.mark)
                    }
                }
                .font(.subheadline.weight(.semibold))
                Text(currentItem?.name ?? displayName(forSlug: current.itemSlug))
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.7)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                    .id(current.itemSlug)
                    .transition(.opacity)
                if let bestNote {
                    Label(bestNote, systemImage: "trophy.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.amber)
                        .lineLimit(1)
                        .sensoryFeedback(.success, trigger: bestCount)
                } else if let note = (done == 0 ? (targetNote ?? lastTimeNote) : nil) {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
            exerciseMenu(done: done)
        }
    }

    @ViewBuilder
    private func exerciseMenu(done: Int) -> some View {
        #if os(iOS)
        Menu {
            if !isFinished(index) {
                if done == 0 {
                    Button { swapping = true; showingPicker = true } label: { Label("Swap exercise", systemImage: "arrow.triangle.2.circlepath") }
                }
                Button { skipCurrent() } label: { Label("Skip exercise", systemImage: "forward.end") }
            }
            Button { showingPicker = true } label: { Label("Add an exercise", systemImage: "plus") }
            Button { showingCues = true } label: { Label("How to do it", systemImage: "figure.mixed.cardio") }
            Picker("Weights in", selection: $unitRaw) {
                ForEach(WeightUnit.allCases, id: \.self) { option in
                    Text(option == .lb ? "Pounds (lb)" : "Kilograms (kg)").tag(option.rawValue)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.08), in: Circle())
        }
        .accessibilityLabel("Exercise options")
        #else
        Button { showingCues = true } label: {
            Image(systemName: "ellipsis")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
        }
        .accessibilityLabel("How to do it")
        #endif
    }

    /// What the exercise is mainly for, in a word or two ("Power").
    private var whyLine: String? {
        guard let top = currentItem?.qualities.max(by: { $0.value < $1.value })?.key else { return nil }
        return qualitiesBySlug[top]?.shortName
    }

    /// How it looks: the moving figure big, the muscles it works small in the
    /// corner, the first coaching cue under it. Tap for every cue.
    private var figurePanel: some View {
        Button { showingCues = true } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                HStack(alignment: .bottom, spacing: 0) {
                    if let pattern = currentItem?.posePattern {
                        RigPoseView(pattern: pattern, muscles: currentItem?.muscles ?? [:])
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Spacer()
                    }
                    if let currentItem, !currentItem.muscles.isEmpty {
                        MuscleMapView(side: .front, weights: currentItem.muscles)
                            .frame(width: 58)
                            .padding(.bottom, 30)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 34)
                if let cue = currentItem?.cues.first {
                    HStack(spacing: 6) {
                        Text(cue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.75))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
            .id(current?.itemSlug)
            .transition(.opacity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("How to do it")
    }

    // MARK: - Logging

    /// The set, the rest or "all done": one coloured card, the ring on the
    /// left where the eye lands, the dose and what's next beside it.
    @ViewBuilder
    private func statusCard(_ current: GeneratedPlannedItem) -> some View {
        if allDone {
            AuraCard(.game, focus: UnitPoint(x: 0.15, y: 0.5), radius: 160, padding: 18) {
                HStack(spacing: 16) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 76, height: 76)
                        .background(Color.white.opacity(0.18), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Every set done.")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                        Text("Finish to save it — or add an exercise for more.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        } else if restRemaining > 0 {
            restCard
        } else {
            workCard(current)
        }
    }

    /// The working set: ember, the ring filling set by set.
    private func workCard(_ current: GeneratedPlannedItem) -> some View {
        let done = setsLogged[index, default: 0]
        let sets = max(current.dose.sets, 1)
        let finished = done >= current.dose.sets
        return AuraCard(.training, focus: UnitPoint(x: 0.18, y: 0.5), radius: 170, padding: 18) {
            HStack(spacing: 18) {
                RingTimer(progress: Double(min(done, sets)) / Double(sets),
                          value: finished ? "✓" : "\(min(done + 1, sets))",
                          unit: finished ? "" : "/\(sets)",
                          caption: "Set", size: 112)
                VStack(alignment: .leading, spacing: 6) {
                    Text(DoseFormatter.text(current.dose))
                        .font(.system(size: 24, weight: .bold).monospacedDigit())
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    if let line = workDetailLine(current, done: done) {
                        Text(line)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink.opacity(0.8))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                    if let effort = current.effort {
                        Text(effort)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.ink.opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// "Then: rest 90 s" — or the next exercise on the last set.
    private func workDetailLine(_ current: GeneratedPlannedItem, done: Int) -> String? {
        if done + 1 >= current.dose.sets, let next = nextOpenName {
            return "Then: \(next)"
        } else if current.restSec > 0, done < current.dose.sets {
            return "Then: rest \(current.restSec) s"
        }
        return nil
    }

    /// The next exercise still open after this one.
    private var nextOpenPosition: Int? {
        queue.indices.first(where: { $0 > index && !isFinished($0) })
            ?? queue.indices.first(where: { $0 != index && !isFinished($0) })
    }

    private var nextOpenName: String? {
        guard let next = nextOpenPosition else { return nil }
        return catalogue.item(queue[next].itemSlug)?.name ?? displayName(forSlug: queue[next].itemSlug)
    }

    /// What comes when the rest is over: "Next: set 3 of 4".
    private var restNextLine: String? {
        guard let current else { return nil }
        let done = setsLogged[index, default: 0]
        guard done < current.dose.sets else { return nextOpenName.map { "Next: \($0)" } }
        return "Next: set \(done + 1) of \(current.dose.sets)"
    }

    /// The rest: calm blue, the countdown inside the ring.
    private var restCard: some View {
        AuraCard(.body, focus: UnitPoint(x: 0.18, y: 0.5), radius: 170, padding: 18) {
            HStack(spacing: 18) {
                RingTimer(progress: restTotal > 0 ? Double(restRemaining) / Double(restTotal) : 0,
                          value: String(format: "%d:%02d", restRemaining / 60, restRemaining % 60),
                          caption: "Rest", size: 112)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Breathe. Shake it out.")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let restNextLine {
                        Text(restNextLine)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink.opacity(0.8))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                    Button {
                        restEndsAt = (restEndsAt ?? .now).addingTimeInterval(15)
                        restRemaining += 15
                        restTotal += 15
                        updateActivity()
                    } label: {
                        Text("+15 s")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 40)
                            .background(Color.black.opacity(0.24), in: Capsule())
                    }
                    .buttonStyle(.pressable)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Reps and weight side by side (or seconds, distance, contacts).
    @ViewBuilder
    private func doseControls(_ current: GeneratedPlannedItem) -> some View {
        switch current.dose.kind {
        case "reps":
            HStack(spacing: 12) {
                DoseStepper(label: "Reps", value: "\(reps)", onMinus: { reps = max(1, reps - 1) }, onPlus: { reps = min(100, reps + 1) })
                DoseStepper(label: "Weight added", value: weightKg < 0.1 ? "Bodyweight" : unit.format(kg: weightKg),
                            onMinus: { weightKg = max(0, weightKg - unit.stepKg) }, onPlus: { weightKg = min(400, weightKg + unit.stepKg) })
            }
        case "time":
            DoseStepper(label: "Seconds", value: "\(seconds)", onMinus: { seconds = max(5, seconds - 5) }, onPlus: { seconds = min(900, seconds + 5) })
        case "distance":
            DoseStepper(label: "Distance", value: Measure.distance(m: distanceM), onMinus: { distanceM = max(5, distanceM - 5) }, onPlus: { distanceM = min(2000, distanceM + 5) })
        case "contacts":
            DoseStepper(label: "Contacts", value: "\(contacts)", onMinus: { contacts = max(1, contacts - 1) }, onPlus: { contacts = min(100, contacts + 1) })
        default:
            EmptyView()
        }
    }

    /// One line: the exercise after this one and its dose. Tap for the list.
    @ViewBuilder
    private var nextRow: some View {
        if let next = nextOpenPosition, next != index {
            let item = queue[next]
            Button { showingList = true } label: {
                HStack(spacing: 10) {
                    Text("Up next")
                        .foregroundStyle(AppTheme.secondaryText)
                    Text(catalogue.item(item.itemSlug)?.name ?? displayName(forSlug: item.itemSlug))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(DoseFormatter.text(item.dose))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 36)
            }
            .buttonStyle(.plain)
        }
    }

    /// Every cue and mistake for the current exercise, with the figure.
    private var howToSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(currentItem?.name ?? "How to do it")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.7)
                    .foregroundStyle(AppTheme.ink)
                if let currentItem {
                    if let pattern = currentItem.posePattern {
                        HStack(spacing: 8) {
                            RigPoseView(pattern: pattern, muscles: currentItem.muscles)
                                .frame(maxWidth: .infinity)
                            if !currentItem.muscles.isEmpty {
                                MuscleMapView(side: .front, weights: currentItem.muscles)
                                    .frame(width: 80)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(height: 220)
                    }
                    if !currentItem.cues.isEmpty {
                        SectionLabel("Do")
                        ForEach(currentItem.cues, id: \.self) { cue in
                            Label(cue, systemImage: "checkmark")
                                .font(.body)
                                .foregroundStyle(AppTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !currentItem.mistakes.isEmpty {
                        SectionLabel("Avoid")
                        ForEach(currentItem.mistakes, id: \.self) { mistake in
                            Label(mistake, systemImage: "xmark")
                                .font(.body)
                                .foregroundStyle(AppTheme.ink.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
    }

    /// All exercises: tap one to go there; add another at the end.
    private var exerciseListSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("This workout")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.7)
                    .foregroundStyle(AppTheme.ink)
                    .padding(.bottom, 12)
                ForEach(Array(queue.enumerated()), id: \.offset) { position, item in
                    let done = setsLogged[position, default: 0]
                    let finished = done >= item.dose.sets
                    Button {
                        jump(to: position)
                        showingList = false
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(finished ? AppTheme.green : (position == index ? AuraTone.training.mark : Color.white.opacity(0.1)))
                                if finished {
                                    Image(systemName: "checkmark").font(.caption.weight(.heavy)).foregroundStyle(Color.black)
                                } else {
                                    Text("\(position + 1)").font(.footnote.weight(.bold)).foregroundStyle(AppTheme.ink)
                                }
                            }
                            .frame(width: 30, height: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(catalogue.item(item.itemSlug)?.name ?? displayName(forSlug: item.itemSlug))
                                    .font(.body.weight(position == index ? .bold : .regular))
                                    .foregroundStyle(AppTheme.ink)
                                    .lineLimit(1)
                                Text(skipped.contains(position) && !finished ? "Skipped" : "\(DoseFormatter.text(item.dose)) · \(done) of \(countedNoun(item.dose.sets, "set"))")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    showingList = false
                    showingPicker = true
                } label: {
                    Label("Add an exercise", systemImage: "plus")
                }
                .buttonStyle(.secondary)
                .padding(.top, 16)
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.background.ignoresSafeArea())
    }

    private func bottomBar(_ current: GeneratedPlannedItem) -> some View {
        HStack(spacing: 12) {
            CircleIconButton(systemImage: "chevron.left", accessibilityLabel: "Previous exercise") { jump(to: index - 1) }
                .disabled(index == 0)
                .opacity(index == 0 ? 0.4 : 1)
            if allDone {
                Button { showingRPE = true } label: { HeroCTALabel("Finish workout") }
                    .buttonStyle(.primary)
            } else if restRemaining > 0 {
                Button("Skip rest") { endRest(silently: true) }
                    .buttonStyle(.secondary)
            } else {
                Button { logSet(current) } label: { HeroCTALabel("Complete set") }
                    .buttonStyle(.primary)
            }
            CircleIconButton(systemImage: "chevron.right", accessibilityLabel: "Next exercise") { jump(to: index + 1) }
                .disabled(index >= queue.count - 1)
                .opacity(index >= queue.count - 1 ? 0.4 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Headline([.strong("Log a workout. "), .soft("Add exercises as you go — every set is saved the moment you log it, even offline.")], size: 34)
            Button {
                showingPicker = true
            } label: {
                HeroCTALabel("Add first exercise")
            }
            .buttonStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Actions

    private func start() async {
        catalogue = CatalogueLoader.load(from: AppConfig.packsDirectory())
        if session == nil, let resuming {
            // Carry on: the plan if there is one, else what was logged; logged sets count.
            session = resuming
            startedAt = resuming.startedAt
            let logged = Dictionary(grouping: resuming.sets, by: \.itemSlug).mapValues(\.count)
            if let planned {
                queue = planned.items
            } else {
                queue = logged.keys.sorted().map { slug in
                    let item = catalogue.item(slug)
                    var dose = item?.defaultDose ?? Dose(kind: "reps", sets: 3, reps: 8)
                    dose.sets = max(dose.sets, logged[slug] ?? 0)
                    return GeneratedPlannedItem(itemSlug: slug, order: 0, dose: dose, restSec: item?.restSeconds ?? 60, rationale: "", quality: "")
                }
            }
            var remaining = logged
            for (position, item) in queue.enumerated() {
                let count = min(remaining[item.itemSlug, default: 0], item.dose.sets)
                if count > 0 { setsLogged[position] = count; remaining[item.itemSlug, default: 0] -= count }
            }
            loggedCount = resuming.sets.count
            index = queue.indices.first { !isFinished($0) } ?? 0
            prefill()
        } else if session == nil {
            session = try? SessionLogger(modelContext: modelContext).startSession(athlete: athlete)
            if let session { SessionKinds.record(session.clientId, kind ?? (planned == nil ? nil : .gym)) }
            startedAt = session?.startedAt ?? .now
            queue = planned?.items ?? []
            prefill()
        }
        setIdleTimerDisabled(true)
        updateActivity()
    }

    /// Keeps the Lock Screen / Dynamic Island in step with the workout.
    private func updateActivity() {
        #if os(iOS) && !APP_EXTENSION
        guard let current else { return }
        let done = setsLogged[index, default: 0]
        let state = WorkoutActivityAttributes.ContentState(
            exercise: currentItem?.name ?? displayName(forSlug: current.itemSlug),
            detail: restRemaining > 0 ? "Rest" : "Set \(min(done + 1, current.dose.sets)) of \(current.dose.sets)",
            restEndsAt: restRemaining > 0 ? (restEndsAt ?? Date.now.addingTimeInterval(Double(restRemaining))) : nil,
            setsDone: totalLogged, setsTotal: totalTargetSets
        )
        WorkoutActivity.show(title: planned?.title ?? "Workout", state: state)
        #endif
    }

    private func endActivity() {
        #if os(iOS) && !APP_EXTENSION
        WorkoutActivity.end()
        #endif
    }

    // MARK: - Voice

    /// What the athlete said, done: the next set lighter or heavier, more sets,
    /// skip, log the set — and pain always stops the exercise first.
    private func applyVoice(_ command: WorkoutVoiceCommand) {
        guard let current else { return }
        let kind = current.dose.kind
        switch command {
        case .lighter, .heavier:
            let up = command == .heavier
            if kind == "reps", weightKg > 0 {
                weightKg = max(0, weightKg + (up ? 1 : -2) * unit.stepKg)
                showVoiceNote((up ? "A step up: " : "Lighter: ") + unit.format(kg: weightKg))
            } else if kind == "reps" {
                reps = max(1, reps + (up ? 2 : -2))
                showVoiceNote((up ? "More: " : "Fewer: ") + "\(reps) reps")
            } else if kind == "time" {
                seconds = max(5, seconds + (up ? 10 : -10))
                showVoiceNote((up ? "Longer: " : "Shorter: ") + "\(seconds) s")
            } else {
                showVoiceNote(command.heard)
            }
        case .moreSets(let n):
            let old = queue[index]
            var dose = old.dose
            dose.sets = min(dose.sets + n, 10)
            var item = GeneratedPlannedItem(itemSlug: old.itemSlug, order: old.order, dose: dose, restSec: old.restSec,
                                            rationale: old.rationale, quality: old.quality)
            item.block = old.block
            item.effort = old.effort
            queue[index] = item
            updateActivity()
            showVoiceNote(command.heard)
        case .skip:
            skipCurrent()
            showVoiceNote(command.heard)
        case .logSet:
            guard restRemaining == 0, !allDone else { return }
            logSet(current)
            showVoiceNote(command.heard)
        case .pain(let area):
            painHeard = area
            showVoiceNote(command.heard)
        }
    }

    private func showVoiceNote(_ text: String) {
        voiceNote = text
        voiceNoteCount += 1
        let shown = voiceNoteCount
        Task {
            try? await Task.sleep(for: .seconds(3))
            if voiceNoteCount == shown { voiceNote = nil }
        }
    }

    /// Pain said out loud is saved like pain in the check-in: today's plan
    /// and the next workouts leave that place alone.
    private func recordPain() {
        guard let area = painHeard else { return }
        let today = DayKey.of(.now)
        let existing = PainStore.report()
        let areas = Array(Set((existing?.areas ?? []) + [area]))
        PainStore.set(PainReport(day: today, areas: PainArea.allCases.filter { areas.contains($0) }, level: existing?.level ?? .some))
        painHeard = nil
    }

    /// Replaces the current exercise (nothing logged on it yet): same number
    /// of sets and rest, the new exercise's own reps or time.
    private func swap(to item: CatalogueItem) {
        guard queue.indices.contains(index), setsLogged[index, default: 0] == 0 else { return }
        let old = queue[index]
        var dose = item.defaultDose
        dose.sets = old.dose.sets
        var replacement = GeneratedPlannedItem(itemSlug: item.slug, order: old.order, dose: dose, restSec: old.restSec,
                                               rationale: old.rationale, quality: item.primaryQuality?.id ?? old.quality)
        replacement.block = old.block
        queue[index] = replacement
        prefill()
        updateActivity()
    }

    /// Leaves the current exercise out and moves to the next one still open.
    private func skipCurrent() {
        skipped.insert(index)
        endRest(silently: true)
        if let next = queue.indices.first(where: { $0 > index && !isFinished($0) }) ?? queue.indices.first(where: { !isFinished($0) }) {
            jump(to: next)
        } else {
            updateActivity()
        }
    }

    private func add(_ item: CatalogueItem) {
        queue.append(GeneratedPlannedItem(
            itemSlug: item.slug, order: queue.count, dose: item.defaultDose, restSec: item.restSeconds,
            rationale: "", quality: item.primaryQuality?.id ?? ""
        ))
        jump(to: queue.count - 1)
    }

    private func jump(to position: Int) {
        guard queue.indices.contains(position) else { return }
        withAnimation(.easeInOut(duration: 0.25)) { index = position }
        endRest(silently: true)
        showingCues = false
        prefill()
        updateActivity()
    }

    /// §15: "prefilled targets from last time" — the most recent logged set
    /// of this item wins; otherwise the plan's own dose. When last time went
    /// well, the target moves on a step (ProgressionEngine).
    private func prefill() {
        guard let current else { return }
        let slug = current.itemSlug
        let descriptor = FetchDescriptor<SetLog>(predicate: #Predicate { $0.itemSlug == slug })
        let earlier = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.session?.id != session?.id }
        // The last set of the most recent session (not any set of it).
        let previous = earlier.max {
            let a = $0.session?.startedAt ?? .distantPast, b = $1.session?.startedAt ?? .distantPast
            return a == b ? $0.setIndex < $1.setIndex : a < b
        }
        let lastSession = previous?.session
        let sameSession = earlier.filter { $0.session?.id == lastSession?.id && lastSession != nil }.sorted { $0.setIndex < $1.setIndex }
        // A set logged without a weight (the Watch) never wipes the weight used before.
        let lastWeight = earlier.filter { ($0.weightKg ?? 0) > 0 }
            .max { ($0.session?.startedAt ?? .distantPast, $0.setIndex) < ($1.session?.startedAt ?? .distantPast, $1.setIndex) }?.weightKg

        reps = previous?.reps ?? current.dose.reps ?? 8
        weightKg = lastWeight ?? 0
        lastTimeNote = Self.lastTime(sameSession, unit: unit)
        seconds = previous?.seconds ?? current.dose.seconds ?? 30
        distanceM = previous?.distanceM ?? current.dose.metres ?? 20
        contacts = previous?.contacts ?? current.dose.contacts ?? 10
        targetNote = nil

        guard let lastSession else { return }
        let lastSets = sameSession
            .map { LoggedSet(reps: $0.reps, weightKg: $0.weightKg, seconds: $0.seconds) }
        let age = PlanGenerator.ageInYears(birthDate: athlete.birthDate, now: .now)
        let calendar = Calendar.current
        let deload = athlete.activeSport.map { sport -> Bool in
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
            let phase = PhaseCalculator.phase(today: .now, seasonStart: sport.seasonStart, seasonEnd: sport.seasonEnd)
            return Deload.isDeloadWeek(weekStart: weekStart, anchor: athlete.createdAt, phase: phase)
        } ?? false
        // The session before that: progress needs two steady sessions in a row.
        let before = earlier.filter { ($0.session?.startedAt ?? .distantFuture) < lastSession.startedAt }
            .max { ($0.session?.startedAt ?? .distantPast) < ($1.session?.startedAt ?? .distantPast) }?.session
        let beforeSets = before.map { session in
            earlier.filter { $0.session?.id == session.id }.map { LoggedSet(reps: $0.reps, weightKg: $0.weightKg, seconds: $0.seconds) }
        }
        let painInArea = PainStore.report() != nil
        // Watch-measured sleep: a short run of nights holds the weight (Part 2, A27).
        let sleep = MeasuredSleepStore.recent()
        let shortSleep = (sleep?.average ?? 24) < 7 || (sleep?.lastNight ?? 24) < 6
        if let target = ProgressionEngine.next(last: lastSets, dose: current.dose, sessionRPE: lastSession.sessionRPE,
                                               isYouth: age < 18, stepKg: unit.stepKg, deload: deload,
                                               previous: beforeSets, previousRPE: before?.sessionRPE, painInArea: painInArea,
                                               shortSleep: shortSleep) {
            if let value = target.reps { reps = value }
            if let value = target.weightKg { weightKg = value }
            if let value = target.seconds { seconds = value }
            targetNote = target.note
        }
    }

    private func logSet(_ current: GeneratedPlannedItem) {
        guard let session else { return }
        let kind = current.dose.kind
        if kind == "reps", weightKg > 0 {
            let slug = current.itemSlug
            let descriptor = FetchDescriptor<SetLog>(predicate: #Predicate { $0.itemSlug == slug })
            let heaviest = ((try? modelContext.fetch(descriptor)) ?? []).compactMap(\.weightKg).max()
            if let heaviest, weightKg > heaviest + 0.01 {
                bestNote = "New best on \(currentItem?.name ?? displayName(forSlug: slug)): \(unit.format(kg: weightKg))"
                bestCount += 1
            }
        }
        let setIndex = setsLogged[index, default: 0]
        _ = try? SessionLogger(modelContext: modelContext).logSet(
            session: session, itemSlug: current.itemSlug, setIndex: setIndex,
            reps: kind == "reps" ? reps : nil,
            weightKg: kind == "reps" && weightKg > 0 ? weightKg : nil,
            seconds: kind == "time" ? seconds : nil,
            distanceM: kind == "distance" ? distanceM : nil,
            contacts: kind == "contacts" ? contacts : nil
        )
        setsLogged[index] = setIndex + 1
        loggedCount += 1

        if setIndex + 1 >= current.dose.sets,
           let next = queue.indices.first(where: { $0 > index && !isFinished($0) }) ?? queue.indices.first(where: { !isFinished($0) }) {
            // All sets done: move on to the next open exercise, resting on the way.
            jump(to: next)
            startRest(current.restSec)
        } else {
            startRest(current.restSec)
        }
    }

    /// "Last time: 3 × 8 · 40 kg", "Last time: 3 × 30 s".
    static func lastTime(_ sets: [SetLog], unit: WeightUnit) -> String? {
        guard let first = sets.first else { return nil }
        var text = "Last time: \(sets.count) × "
        if let reps = first.reps { text += "\(reps)" } else if let seconds = first.seconds { text += "\(seconds) s" }
        else if let metres = first.distanceM { text += "\(Int(metres)) m" } else if let contacts = first.contacts { text += "\(contacts)" } else { return nil }
        if let top = sets.compactMap(\.weightKg).filter({ $0 > 0 }).max() { text += " · " + unit.format(kg: top) }
        return text
    }

    private func startRest(_ duration: Int) {
        restTask?.cancel()
        // No rest to take (conditioning intervals) or nothing left to do.
        guard duration > 0, !allDone else {
            restRemaining = 0
            restEndsAt = nil
            updateActivity()
            return
        }
        restTotal = duration
        restRemaining = duration
        restEndsAt = Date.now.addingTimeInterval(Double(duration))
        updateActivity()
        restTask = Task {
            for _ in 0..<3600 {
                try? await Task.sleep(for: .milliseconds(500))
                if Task.isCancelled { return }
                // From the end time: right again the moment the phone is unlocked.
                restRemaining = max(0, Int(ceil((restEndsAt ?? .now).timeIntervalSinceNow)))
                if restRemaining == 0 { break }
            }
            restEndsAt = nil
            restEndedCount += 1
            updateActivity()
        }
    }

    private func endRest(silently: Bool) {
        restTask?.cancel()
        restRemaining = 0
        restEndsAt = nil
        RestAlarm.cancel()
        if !silently { restEndedCount += 1 }
        updateActivity()
    }

    /// What this session did, for the finish screen: minutes, sets, new bests,
    /// and each anchor lift against its last session — progress the athlete
    /// can see, never points.
    private func recap() -> SessionRecap {
        let minutes = max(1, Int(Date.now.timeIntervalSince(session?.startedAt ?? startedAt) / 60))
        var lines: [SessionRecap.Line] = []
        let todaySets = session?.sets ?? []
        var seen = Set<String>()
        for item in queue where item.rationale.hasPrefix("Anchor") && seen.insert(item.itemSlug).inserted {
            let slug = item.itemSlug
            let mine = todaySets.filter { $0.itemSlug == slug }
            guard let best = SessionRecap.best(mine) else { continue }
            let before = athlete.sessions
                .filter { $0.id != session?.id && $0.sets.contains { $0.itemSlug == slug } }
                .max { $0.startedAt < $1.startedAt }
            let previous = before.flatMap { SessionRecap.best($0.sets.filter { $0.itemSlug == slug }) }
            let name = catalogue.item(slug)?.name ?? displayName(forSlug: slug)
            lines.append(SessionRecap.line(name: name, best: best, previous: previous, unit: unit))
        }
        return SessionRecap(minutes: minutes, sets: totalLogged, bests: bestCount, lines: lines)
    }

    private func finish() {
        endActivity()
        guard let session else { return }
        try? SessionLogger(modelContext: modelContext).finishSession(session, sessionRPE: rpe)
        // Home says what the twin makes of it ("legs ready again Sunday").
        TwinPulse.afterWorkout(athlete, catalogue: catalogue)
        NotificationCenter.default.post(name: WeeklyPlan.inputsChanged, object: nil)
        let sessionRef = session
        let sportSlug = athlete.activeSport?.sportSlug
        Task {
            // §17: one Apple Health workout per session, never a duplicate —
            // saveWorkout returns the existing id if one is already stored.
            let id = await HealthKitManager.shared.saveWorkout(
                start: sessionRef.startedAt, end: sessionRef.endedAt ?? .now,
                sportSlug: sportSlug, existingId: sessionRef.healthKitWorkoutId
            )
            if let id, sessionRef.healthKitWorkoutId == nil {
                sessionRef.healthKitWorkoutId = id
                sessionRef.syncedAt = nil
                try? modelContext.save()
            }
            await SyncQueue(apiClient: apiClient, tokenStore: KeychainTokenStore(), modelContext: modelContext).drainPendingSessions()
        }
        dismiss()
    }

    private func discard() {
        endActivity()
        if let session {
            // Never restored from the backup later (it may have gone up already).
            CloudSync.discard(sessionClientId: session.clientId)
            modelContext.delete(session)
            try? modelContext.save()
        }
        dismiss()
    }

    private func setIdleTimerDisabled(_ disabled: Bool) {
        #if os(iOS) && !APP_EXTENSION
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}

/// A huge minus / value / plus row — built for sweaty thumbs.
struct BigStepper: View {
    let label: String
    let value: String
    let onMinus: () -> Void
    let onPlus: () -> Void

    var body: some View {
        HStack {
            Button(action: onMinus) {
                Image(systemName: "minus")
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 60, height: 60)
                    .background(AppTheme.fill, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Decrease \(label.lowercased())")
            Spacer()
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 34, weight: .bold).monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer()
            Button(action: onPlus) {
                Image(systemName: "plus")
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.onAccent)
                    .frame(width: 60, height: 60)
                    .background(AppTheme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Increase \(label.lowercased())")
        }
        .cardStyle(padding: 14)
        .accessibilityElement(children: .contain)
        .accessibilityValue(value)
    }
}

/// V8 live-set stepper: small label, then minus · value · plus in one dark
/// capsule — two fit side by side so the whole set stays on one screen.
struct DoseStepper: View {
    let label: String
    let value: String
    let onMinus: () -> Void
    let onPlus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.leading, 6)
            HStack(spacing: 0) {
                Button(action: onMinus) {
                    Image(systemName: "minus")
                        .font(.headline)
                        .frame(width: 52, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Decrease \(label.lowercased())")
                Text(value)
                    .font(.system(size: 26, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(label)
                    .accessibilityValue(value)
                Button(action: onPlus) {
                    Image(systemName: "plus")
                        .font(.headline)
                        .foregroundStyle(Color.black)
                        .frame(width: 44, height: 44)
                        .background(Color.white, in: Circle())
                        .frame(width: 52, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Increase \(label.lowercased())")
            }
            .foregroundStyle(AppTheme.ink)
            .background(Color.white.opacity(0.08), in: Capsule())
            .animation(.snappy(duration: 0.2), value: value)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// Search the downloaded library and add an exercise to the session.
struct ExercisePickerSheet: View {
    let catalogue: Catalogue
    /// Whose drills may show (SportVisibility): never another sport's.
    let sports: [SportVisibility.Sport]
    let onPick: (CatalogueItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var group: QualityGroup?

    private var items: [CatalogueItem] {
        let filtered = catalogue.itemsBySlug.values
            .filter { (group == nil || $0.primaryQuality?.group == group) && SportVisibility.isVisible($0, sports: sports) }
            .sorted { $0.name < $1.name }
        return CatalogueSearch.rank(filtered, query: searchText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ScreenTitle("Add exercise")
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(AppTheme.secondaryText)
                        TextField("Search", text: $searchText)
                    }
                    .padding(14)
                    .background(AppTheme.card, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button { group = nil } label: { Chip("All", isSelected: group == nil) }
                                .buttonStyle(.plain)
                            ForEach(QualityGroup.allCases, id: \.self) { value in
                                Button { group = value } label: { Chip(value.displayName, isSelected: group == value) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    ForEach(items) { item in
                        Button {
                            onPick(item)
                            dismiss()
                        } label: {
                            LibraryRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .appScreen()
            .toolbar {
                CloseToolbarItem { dismiss() }
            }
        }
    }
}

/// §11: "After every training session, exactly one more question: how hard
/// was that, 1–10?"
/// The finish screen's summary of one session.
struct SessionRecap {
    struct Line: Identifiable {
        let name: String
        let today: String
        let change: String?
        let up: Bool
        var id: String { name }
    }
    let minutes: Int
    let sets: Int
    let bests: Int
    let lines: [Line]

    /// The heaviest set (then the most reps).
    static func best(_ sets: [SetLog]) -> SetLog? {
        sets.max { (($0.weightKg ?? 0), ($0.reps ?? 0), ($0.seconds ?? 0)) < (($1.weightKg ?? 0), ($1.reps ?? 0), ($1.seconds ?? 0)) }
    }

    static func line(name: String, best: SetLog, previous: SetLog?, unit: WeightUnit) -> Line {
        let kg = best.weightKg ?? 0, reps = best.reps ?? 0
        let today = kg > 0 ? "\(unit.format(kg: kg)) × \(reps)" : best.seconds.map { "\($0) s" } ?? "× \(reps)"
        guard let previous else { return Line(name: name, today: today, change: "First time", up: false) }
        let lastKg = previous.weightKg ?? 0, lastReps = previous.reps ?? 0
        if kg > lastKg + 0.01 {
            return Line(name: name, today: today, change: "+\(unit.format(kg: kg - lastKg))", up: true)
        }
        if abs(kg - lastKg) < 0.01, reps > lastReps {
            return Line(name: name, today: today, change: "+\(reps - lastReps) rep\(reps - lastReps == 1 ? "" : "s")", up: true)
        }
        if let secs = best.seconds, let last = previous.seconds, secs > last {
            return Line(name: name, today: today, change: "+\(secs - last) s", up: true)
        }
        return Line(name: name, today: today, change: "Same as last time", up: false)
    }
}

struct RPEPromptView: View {
    @Binding var rpe: Int
    var heartRate: HeartRateSummary? = nil
    var recap: SessionRecap? = nil
    /// "Keep training": back to the workout (a mistaken Finish).
    var onKeepTraining: (() -> Void)? = nil
    let onDone: () -> Void

    private func description(_ value: Int) -> String {
        switch value {
        case 1...2: "Very easy — could chat the whole time"
        case 3...4: "Easy — breathing a little harder"
        case 5...6: "Moderate — working, still in control"
        case 7...8: "Hard — only a few words at a time"
        case 9: "Very hard — nearly everything you had"
        default: "Maximum — nothing left"
        }
    }

    private func recapFigure(_ value: String, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            BigFigure(value, unit: unit, size: 34)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func recapCard(_ recap: SessionRecap) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 0) {
                recapFigure("\(recap.minutes)", unit: "min", label: "Time")
                recapFigure("\(recap.sets)", unit: "", label: "Sets")
                recapFigure("\(recap.bests)", unit: "", label: recap.bests == 1 ? "New best" : "New bests")
            }
            if !recap.lines.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(recap.lines) { line in
                        HStack(spacing: 10) {
                            Text(line.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(line.today)
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(AppTheme.secondaryText)
                            if let change = line.change {
                                Text(change)
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(line.up ? Color.black : AppTheme.secondaryText)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(line.up ? Color.white : Color.white.opacity(0.08), in: Capsule())
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    var body: some View {
        StepScaffold(title: "How hard was that?", subtitle: "1 = very easy, 10 = the hardest you could do. It tells us how to plan your next days.", buttonTitle: "Save session", onBack: onKeepTraining, onContinue: onDone) {
            VStack(spacing: 18) {
                if let heartRate {
                    Label("Heart rate \(heartRate.average) bpm on average, \(heartRate.max) at the top", systemImage: "heart.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.red)
                        .frame(maxWidth: .infinity)
                }
                // V8: the one number on an ember card, its meaning under it.
                AuraCard(.training, focus: UnitPoint(x: 0.5, y: 0.4), radius: 170) {
                    VStack(spacing: 6) {
                        BigFigure("\(rpe)", unit: "of 10", size: 88)
                            .contentTransition(.numericText())
                        Text(description(rpe))
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(1...10, id: \.self) { value in
                        Button {
                            withAnimation(.snappy) { rpe = value }
                        } label: {
                            Text("\(value)")
                                .font(.headline)
                                .foregroundStyle(rpe == value ? Color.black : AppTheme.ink)
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .background(rpe == value ? Color.white : Color.white.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Effort \(value) of 10: \(description(value))")
                    }
                }
                if let recap {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel("This session")
                        recapCard(recap)
                    }
                    .padding(.top, 12)
                }
            }
        }
    }
}

/// A quiet alert when the rest is over and the phone is locked.
enum RestAlarm {
    static let identifier = "workout.rest-over"

    static func schedule(at date: Date?) {
        #if canImport(UserNotifications) && os(iOS)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard let date, date.timeIntervalSinceNow > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest's over"
        content.body = "Next set."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: date.timeIntervalSinceNow, repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        #endif
    }

    static func cancel() {
        #if canImport(UserNotifications) && os(iOS)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        #endif
    }
}
