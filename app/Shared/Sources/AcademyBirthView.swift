import SwiftUI

/// One Academy question: a knowledge check locks after the first answer and
/// shows the right one; a reflection has no right answer and can be changed.
struct AcademyQuestionCard: View {
    let question: AcademyQuestion
    let accent: Color
    @Binding var chosen: Int?

    enum RowState { case plain, selected, right, wrong }

    private var revealed: Bool { question.kind == .knowledge && chosen != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(question.kind == .knowledge ? "Check" : "About you — no right answer")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(question.kind == .knowledge ? accent : AppTheme.purple)
            Text(question.prompt)
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    Button {
                        guard !revealed else { return }
                        withAnimation(.easeInOut(duration: 0.2)) { chosen = index }
                    } label: {
                        row(option.text, state: state(of: index))
                    }
                    .buttonStyle(.plain)
                }
            }
            if revealed, let chosen, let explain = question.explain {
                VStack(alignment: .leading, spacing: 6) {
                    Text(question.options[chosen].correct ? "Right." : "Not quite.")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(explain)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func state(of option: Int) -> RowState {
        if revealed {
            if option == question.correctIndex { return .right }
            return option == chosen ? .wrong : .plain
        }
        return option == chosen ? .selected : .plain
    }

    private func row(_ text: String, state: RowState) -> some View {
        let edge: Color = switch state {
        case .plain: Color.white.opacity(0.10)
        case .selected: AppTheme.brightRed.opacity(0.8)
        case .right: AppTheme.green.opacity(0.8)
        case .wrong: Color.white.opacity(0.28)
        }
        return HStack(spacing: 12) {
            Text(text)
                .font(.body.weight(.medium))
                .foregroundStyle(state == .wrong ? AppTheme.secondaryText : AppTheme.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            switch state {
            case .right: Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.green)
            case .selected: Image(systemName: "circle.inset.filled").foregroundStyle(AppTheme.brightRed)
            case .wrong, .plain: EmptyView()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .glassSurface(cornerRadius: 18)
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(edge, lineWidth: 1) }
    }
}

/// The twin is born (docs/ACADEMY-PLAN.md §2): what to grow first, how it
/// looks, eight honest answers — then the reveal. Sport, position, level and
/// season come from the athlete's profile, so they aren't asked again.
struct AcademyBirthView: View {
    let sportSlug: String?
    /// "Your twin · Soccer · Midfielder"
    let summary: String

    @Environment(\.dismiss) private var dismiss
    @State private var step = Step.intro
    @State private var goals: [TwinPillar] = []
    @State private var look = AcademyStore.load().appearance ?? .standard
    @State private var answers: [String: Int] = [:]
    @State private var born: AcademyState?

    enum Step: Equatable {
        case intro, goals, look
        case question(Int)
        case reveal
    }

    private let baseline = AcademyContent.baseline

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                content
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            footer
        }
        .background(AppBackground(.hero).ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    // MARK: Chrome

    private var progress: Double {
        switch step {
        case .intro: 0.05
        case .goals: 0.15
        case .look: 0.3
        case .question(let index): 0.3 + 0.65 * Double(index + 1) / Double(max(baseline.count, 1))
        case .reveal: 1
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .opacity(step == .reveal ? 0 : 1)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(AppTheme.brightRed).frame(width: proxy.size.width * progress)
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var canContinue: Bool {
        switch step {
        case .goals: !goals.isEmpty
        case .question(let index): baseline.indices.contains(index) && answers[baseline[index].id] != nil
        default: true
        }
    }

    private var footer: some View {
        Button(action: advance) {
            HeroCTALabel(step == .intro ? "Start" : (step == .reveal ? "Done" : "Continue"))
        }
        .buttonStyle(.primary)
        .disabled(!canContinue)
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private func advance() {
        switch step {
        case .intro: step = .goals
        case .goals: step = .look
        case .look: step = baseline.isEmpty ? .reveal : .question(0)
        case .question(let index):
            if index + 1 < baseline.count { step = .question(index + 1) } else { finish() }
        case .reveal: dismiss()
        }
    }

    private func finish() {
        let state = AcademyStore.born(AcademyStore.load(), appearance: look, goals: goals, baseline: baseline,
                                      answers: answers, at: .now)
        AcademyStore.save(state)
        AcademyEvent.log(.twinBorn)
        born = state
        step = .reveal
    }

    private var twinSnapshot: TwinSnapshot {
        TwinScoring.snapshot(born?.ledger ?? [], sportAreas: AcademyContent.areas(forSport: sportSlug))
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .intro: intro
        case .goals: goalPicker
        case .look: lookPicker
        case .question(let index):
            if baseline.indices.contains(index) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Question \(index + 1) of \(baseline.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.mutedText)
                    AcademyQuestionCard(question: baseline[index], accent: AppTheme.brightRed,
                                        chosen: Binding(get: { answers[baseline[index].id] },
                                                        set: { answers[baseline[index].id] = $0 }))
                }
                .id(index)
                .transition(.opacity)
            }
        case .reveal: reveal
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            DigitalTwinView(state: TwinVisualState(appearance: look, sportSlug: sportSlug, snapshot: twinSnapshot,
                                                   dormant: true, showsGauges: false))
                .frame(height: 330)
            Text("Create your digital twin")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(AppTheme.ink)
            Text("Your twin is you as an athlete: your body, fuel, recovery, mind, legends and game sense. Every lesson and every honest answer shapes it, and it decides what you learn next.")
                .font(.body)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Label(summary, systemImage: "sportscourt.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Label("Only you can see your twin and your answers.", systemImage: "hand.raised.fill")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private var goalPicker: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What do you want to grow first?")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppTheme.ink)
            Text("Pick up to three. Your next lessons lean towards them.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
            VStack(spacing: 10) {
                ForEach(TwinPillar.allCases) { pillar in
                    let picked = goals.contains(pillar)
                    Button {
                        if picked { goals.removeAll { $0 == pillar } } else if goals.count < 3 { goals.append(pillar) }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: pillar.systemImage)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(pillar.color)
                                .frame(width: 40, height: 40)
                                .background(pillar.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pillar.title).font(.body.weight(.semibold)).foregroundStyle(AppTheme.ink)
                                Text(pillar.subtitle).font(.footnote).foregroundStyle(AppTheme.secondaryText)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(picked ? pillar.color : AppTheme.mutedText)
                        }
                        .padding(12)
                        .glassSurface(cornerRadius: 18, tint: picked ? pillar.color : nil)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(picked ? .isSelected : [])
                }
            }
        }
    }

    private var lookPicker: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Make it yours")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppTheme.ink)
            DigitalTwinView(state: TwinVisualState(appearance: look, sportSlug: sportSlug, snapshot: twinSnapshot, showsGauges: false))
                .frame(height: 300)
            VStack(alignment: .leading, spacing: 10) {
                Text("Build").font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.secondaryText)
                HStack(spacing: 8) {
                    ForEach(TwinAppearance.Build.allCases, id: \.self) { build in
                        Button { look.build = build } label: {
                            Text(build.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(Capsule().fill(look.build == build ? AppTheme.brand.opacity(0.4) : Color.white.opacity(0.05)))
                                .overlay { Capsule().strokeBorder(Color.white.opacity(look.build == build ? 0.3 : 0.1), lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            swatches("Skin tone", TwinAppearance.skinTones, selected: look.skin) { look.skin = $0 }
            swatches("Hair", TwinAppearance.hairColours, selected: look.hair) { look.hair = $0 }
            swatches("Kit", TwinAppearance.kitColours, selected: look.kit) { look.kit = $0 }
            swatches("Kit accent", TwinAppearance.kitColours, selected: look.kitSecondary) { look.kitSecondary = $0 }
        }
    }

    private func swatches(_ title: String, _ colours: [String], selected: String, pick: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.secondaryText)
            HStack(spacing: 10) {
                ForEach(colours, id: \.self) { hex in
                    Button { pick(hex) } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 34, height: 34)
                            .overlay { Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1) }
                            .padding(3)
                            .overlay { Circle().strokeBorder(AppTheme.brightRed, lineWidth: selected == hex ? 2 : 0) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title) colour")
                    .accessibilityAddTraits(selected == hex ? .isSelected : [])
                }
            }
        }
    }

    private var reveal: some View {
        let twin = twinSnapshot
        return VStack(spacing: 16) {
            DigitalTwinView(state: TwinVisualState(appearance: look, sportSlug: sportSlug, snapshot: twin, mode: .levelUp,
                                                   gains: Dictionary(uniqueKeysWithValues: TwinPillar.allCases.map { ($0, twin.score($0).total) })))
                .frame(height: 480)
                .padding(.horizontal, -22)
            Text("Your twin is born")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(AppTheme.ink)
            Text("This is your starting point. Every lesson and honest answer from here shapes it.")
                .font(.body)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
    }
}

/// Before vs now: the twin as it was born beside the twin today.
struct TwinCompareSheet: View {
    let state: AcademyState
    let sportSlug: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let areas = AcademyContent.areas(forSport: sportSlug)
        let then = TwinScoring.snapshot(state.ledger, sportAreas: areas, until: state.bornAt ?? .distantPast)
        let now = TwinScoring.snapshot(state.ledger, sportAreas: areas)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 8) {
                        twinColumn("Born", detail: state.bornAt?.formatted(.dateTime.month(.abbreviated).day()) ?? "", snapshot: then)
                        twinColumn("Today", detail: "Overall \(now.overall)", snapshot: now)
                    }
                    VStack(spacing: 0) {
                        ForEach(TwinPillar.allCases) { pillar in
                            let before = then.score(pillar).total
                            let after = now.score(pillar).total
                            HStack {
                                Label(pillar.title, systemImage: pillar.systemImage)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(pillar.color)
                                Spacer()
                                Text("\(before) → \(after)")
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(AppTheme.ink)
                                if after > before {
                                    Text("+\(after - before)")
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(pillar.color)
                                }
                            }
                            .padding(.vertical, 10)
                        }
                    }
                }
                .padding(20)
            }
            .background(AppBackground(.subtle).ignoresSafeArea())
            .navigationTitle("Before vs now")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func twinColumn(_ title: String, detail: String, snapshot: TwinSnapshot) -> some View {
        VStack(spacing: 6) {
            DigitalTwinView(state: TwinVisualState(appearance: state.look, sportSlug: sportSlug, snapshot: snapshot, showsGauges: false))
                .frame(height: 300)
            Text(title).font(.headline).foregroundStyle(AppTheme.ink)
            Text(detail).font(.footnote).foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}
