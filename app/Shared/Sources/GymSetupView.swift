import SwiftUI

/// Tap Gym: what to train and for how long (owner, 2026-11-19). "You pick"
/// lets AthleteOS choose from what was trained when; the athlete's own pick
/// always wins — a focus that isn't ideal today says why, but stays open.
struct GymSetupView: View {
    let athlete: Athlete
    let catalogue: Catalogue
    let onStart: (GeneratedSession) -> Void
    var onPreview: ((GeneratedSession) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var focus: GymFocus = .auto
    @State private var length: GymLength = .standard
    @State private var advice: GymAdvice?
    @State private var session: GeneratedSession?
    @State private var showingAll = false
    @State private var loaded = false
    @State private var lastTime: [String: String] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Headline([.strong("Gym. "), .soft("What do you want to train?")], size: 34)
                    adviceCard
                    focusGrid
                    lengthPicker
                    summary
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) { startBar }
            .appScreen()
            .toolbar { CloseToolbarItem { dismiss() } }
            .onAppear(perform: load)
            .onChange(of: focus) { _, _ in rebuild() }
            .onChange(of: length) { _, _ in rebuild() }
        }
    }

    // MARK: - Pieces

    /// "You pick": the advisor's choice and its reason, on an ember card.
    @ViewBuilder
    private var adviceCard: some View {
        if let advice {
            Button { withAnimation(.easeInOut(duration: 0.2)) { focus = .auto } } label: {
                AuraCard(.training, focus: UnitPoint(x: 0.15, y: 0.3), radius: 200, padding: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("You pick", systemImage: "sparkles")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.ink.opacity(0.85))
                            Spacer()
                            if focus == .auto {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(AppTheme.ink)
                            }
                        }
                        Text(advice.focus.title)
                            .font(.system(size: 32, weight: .bold))
                            .tracking(-0.7)
                            .foregroundStyle(AppTheme.ink)
                        Text(advice.reason)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(Color.white.opacity(focus == .auto ? 0.8 : 0), lineWidth: 2)
                }
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Let AthleteOS pick: \(advice.focus.title). \(advice.reason)")
            .accessibilityAddTraits(focus == .auto ? .isSelected : [])
        }
    }

    private var focusGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Or choose yourself")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(GymFocus.choices) { option in
                    Button { withAnimation(.easeInOut(duration: 0.2)) { focus = option } } label: {
                        focusTile(option)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityAddTraits(focus == option ? .isSelected : [])
                }
            }
        }
    }

    private func focusTile(_ option: GymFocus) -> some View {
        let selected = focus == option
        let warning = advice?.notToday[option]
        return VStack(alignment: .leading, spacing: 8) {
            Image(systemName: option.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(selected ? Color.black : AuraTone.training.mark)
            Spacer(minLength: 0)
            Text(option.title)
                .font(.headline)
                .foregroundStyle(selected ? Color.black : AppTheme.ink)
            Text(warning ?? anchorsLine(option))
                .font(.caption)
                .foregroundStyle(selected ? Color.black.opacity(0.65) : (warning == nil ? AppTheme.secondaryText : AuraTone.training.mark))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .padding(16)
        .background(selected ? Color.white : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(selected ? 0 : 0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func anchorsLine(_ option: GymFocus) -> String {
        switch option {
        case .upper: "Press, row, pull-up, overhead"
        case .lower: "Squat, hinge, one leg"
        case .core: "Anti-arch, anti-twist, carries"
        case .full: "Squat, press, row, hinge"
        case .auto: ""
        }
    }

    private var lengthPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("How long")
            HStack(spacing: 10) {
                ForEach(GymLength.allCases) { option in
                    Button { withAnimation(.easeInOut(duration: 0.2)) { length = option } } label: {
                        VStack(spacing: 2) {
                            Text("\(option.minutes)")
                                .font(.system(size: 28, weight: .light).monospacedDigit())
                            Text(option.title)
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(length == option ? Color.black : AppTheme.ink)
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(length == option ? Color.white : Color.white.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("\(option.title), \(option.minutes) minutes")
                    .accessibilityAddTraits(length == option ? .isSelected : [])
                }
            }
            Text(length.detail)
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    /// The session it builds: title, minutes, and the exercises — anchors marked.
    @ViewBuilder
    private var summary: some View {
        if let session {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(session.title) {
                    Text("\(session.estimatedMinutes) min")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText)
                }
                if let note = session.decision?.gymNote, focus != .auto {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                let items = showingAll ? session.items : Array(session.items.prefix(6))
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items, id: \.order) { item in
                        let anchor = item.rationale.hasPrefix("Anchor")
                        HStack(spacing: 12) {
                            Circle()
                                .fill(anchor ? AuraTone.training.mark : Color.white.opacity(0.25))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(catalogue.item(item.itemSlug)?.name ?? displayName(forSlug: item.itemSlug))
                                    .font(.body.weight(anchor ? .semibold : .regular))
                                    .foregroundStyle(AppTheme.ink)
                                    .lineLimit(1)
                                // The number the anchor is chasing.
                                if anchor, let last = lastTime[item.itemSlug] {
                                    Text("Last time \(last)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(AuraTone.training.mark)
                                }
                            }
                            Spacer(minLength: 8)
                            Text(DoseFormatter.text(item.dose))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(AppTheme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
                if session.items.count > 6 {
                    Button(showingAll ? "Show less" : "All \(session.items.count) exercises") {
                        withAnimation(.easeInOut(duration: 0.2)) { showingAll.toggle() }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(minHeight: 44)
                }
                HStack(spacing: 8) {
                    Circle().fill(AuraTone.training.mark).frame(width: 8, height: 8)
                    Text("Anchor lifts stay the same for four weeks, so you can see them go up. The rest changes every time.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if loaded {
            Text("Nothing fits your equipment for this yet. Add some in Me → Equipment.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private var startBar: some View {
        ButtonRow {
            Button {
                guard let session else { return }
                dismiss()
                onStart(session)
            } label: { HeroCTALabel("Start") }
                .buttonStyle(.primary)
                .disabled(session == nil)
            if let onPreview {
                Button("Details") {
                    guard let session else { return }
                    dismiss()
                    onPreview(session)
                }
                .buttonStyle(.secondary)
                .disabled(session == nil)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(AppTheme.background.opacity(0.92).ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Building

    private func load() {
        guard !loaded else { return }
        if let day = TodayEngine.trainingDay(athlete, sessions: athlete.sessions, catalogue: catalogue, plannedGymDay: true) {
            advice = GymHistoryBuilder.request(athlete, day: day, catalogue: catalogue).1
        }
        let saved = GymChoiceStore.choice(on: .now)
        focus = saved?.focus ?? .auto
        length = saved?.length ?? GymChoiceStore.lastLength ?? advice?.length ?? .standard
        loaded = true
        rebuild()
    }

    private func rebuild() {
        guard loaded else { return }
        GymChoiceStore.save(.init(focus: focus, length: length))
        session = TodayEngine.session(.gymDevelopment, athlete: athlete, sessions: athlete.sessions, catalogue: catalogue, plannedGymDay: true)
        lastTime = Self.lastTime(for: Set(session?.items.filter { $0.rationale.hasPrefix("Anchor") }.map(\.itemSlug) ?? []),
                                 sessions: athlete.sessions)
    }

    /// The best set of each anchor's most recent session: "60 kg × 8" (or "× 12"
    /// without a weight), so the athlete walks in knowing the number to beat.
    static func lastTime(for slugs: Set<String>, sessions: [Session]) -> [String: String] {
        guard !slugs.isEmpty else { return [:] }
        let unit = WeightUnit.current
        var found: [String: String] = [:]
        for session in sessions.sorted(by: { $0.startedAt > $1.startedAt }) {
            for slug in slugs where found[slug] == nil {
                let sets = session.sets.filter { $0.itemSlug == slug }
                guard !sets.isEmpty else { continue }
                let best = sets.max { (($0.weightKg ?? 0), ($0.reps ?? 0)) < (($1.weightKg ?? 0), ($1.reps ?? 0)) }
                if let best {
                    if let kg = best.weightKg, kg > 0 {
                        found[slug] = "\(unit.format(kg: kg)) × \(best.reps ?? 0)"
                    } else if let reps = best.reps {
                        found[slug] = "× \(reps)"
                    } else if let seconds = best.seconds {
                        found[slug] = "\(seconds) s"
                    }
                }
            }
            if found.count == slugs.count { break }
        }
        return found
    }
}
