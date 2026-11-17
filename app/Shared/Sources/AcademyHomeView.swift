import SwiftUI

/// The Academy tab (docs/ACADEMY-PLAN.md): the Digital Twin as the hero, the
/// next three lessons with the reason for each, the six pillars, and the
/// always-available "Need to talk to someone?".
struct AcademyHomeView: View {
    let athlete: Athlete

    @State private var state = AcademyState()
    @State private var target: TwinTarget?
    @State private var playing: AcademyLesson?
    @State private var showingSupport = false

    private var sportSlug: String? { athlete.activeSport?.sportSlug }

    private var learner: AcademyLearner {
        AcademyLearner(
            sportSlug: sportSlug,
            sportName: sportSlug == nil ? nil : AthleteStats.sportName(athlete),
            age: PlanGenerator.ageInYears(birthDate: athlete.birthDate, now: .now),
            phase: athlete.activeSport.map { PhaseCalculator.phase(today: .now, seasonStart: $0.seasonStart, seasonEnd: $0.seasonEnd) },
            goals: state.goals, completed: state.completedIDs)
    }

    private var snapshot: TwinSnapshot {
        TwinScoring.snapshot(state.ledger, sportAreas: AcademyContent.areas(forSport: sportSlug))
    }

    var body: some View {
        let twin = snapshot
        let recommendations = AcademyRecommender.recommend(AcademyContent.lessons, snapshot: twin, learner: learner)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 48) {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        hero(twin)
                        pillarGrid(twin)
                    }
                    nextSection(recommendations)
                    pillarList(twin)
                    supportRow
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .appScreen(.hero, sportSlug: sportSlug)
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            state = AcademyStore.load()
            AcademyEvent.log(.twinViewed)
        }
        .sheet(item: $target) { target in
            AcademyAreaSheet(target: target, snapshot: twin, learner: learner) { lesson in
                self.target = nil
                playing = lesson
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingSupport) { SupportSheet() }
        .fullScreenCover(item: $playing, onDismiss: { state = AcademyStore.load() }) { lesson in
            AcademyLessonView(lesson: lesson, sportSlug: sportSlug)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ProfileButton(name: athlete.displayName)
            Text("Academy")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
        }
        .padding(.top, 8)
    }

    private func hero(_ twin: TwinSnapshot) -> some View {
        VStack(spacing: 6) {
            DigitalTwinView(state: TwinVisualState(appearance: state.look, sportSlug: sportSlug, snapshot: twin)) { tapped in
                AcademyEvent.log(.bodyZoneTapped)
                target = tapped
            }
            .frame(height: 420)
            Text(state.ledger.isEmpty ? "Every lesson you finish shapes your twin." : "Tap your twin to see each area.")
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedText)
        }
        .frame(maxWidth: .infinity)
    }

    /// The six pillars as small glass blocks: a big number, the pillar's name.
    private func pillarGrid(_ twin: TwinSnapshot) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(TwinPillar.allCases) { pillar in
                Button { target = .pillar(pillar) } label: {
                    GlassMetric(value: "\(twin.score(pillar).total)", label: pillar.title,
                                height: pillar.rawValue.count.isMultiple(of: 2) ? 72 : 80, accent: pillar.color)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func nextSection(_ recommendations: [AcademyRecommendation]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Next for you")
            if recommendations.isEmpty {
                Text("You've finished every lesson for now. New ones arrive with updates.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recommendations.enumerated()), id: \.element.id) { index, recommendation in
                        Button { playing = recommendation.lesson } label: {
                            ListRow(systemImage: recommendation.lesson.pillar.systemImage, color: recommendation.lesson.pillar.color,
                                    title: recommendation.lesson.title,
                                    detail: "\(recommendation.reason) · \(recommendation.lesson.minutes) min")
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                        if index < recommendations.count - 1 { Divider().padding(.leading, 54).opacity(0.5) }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .glassSurface(tint: AppTheme.brand)
            }
        }
    }

    private func pillarList(_ twin: TwinSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Pillars", subtitle: "Knowledge from lessons, habits from your own answers.")
            VStack(spacing: 0) {
                ForEach(TwinPillar.allCases) { pillar in
                    Button { target = .pillar(pillar) } label: {
                        ListRow(systemImage: pillar.systemImage, color: pillar.color, title: pillar.title, detail: pillar.subtitle) {
                            Text("\(twin.score(pillar).total)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(AppTheme.ink)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var supportRow: some View {
        Button { showingSupport = true } label: {
            ListRow(systemImage: "bubble.left.and.bubble.right.fill", color: AppTheme.purple, title: "Need to talk to someone?",
                    detail: "Free, confidential help — any time")
        }
        .buttonStyle(.plain)
        .padding(.bottom, 20)
    }
}

/// A tapped body area or pillar: its score in two halves, and the lesson
/// that would raise it.
struct AcademyAreaSheet: View {
    let target: TwinTarget
    let snapshot: TwinSnapshot
    let learner: AcademyLearner
    let onStart: (AcademyLesson) -> Void

    private var pillar: TwinPillar {
        switch target {
        case .pillar(let pillar): pillar
        case .area: .body
        }
    }

    private var title: String {
        switch target {
        case .pillar(let pillar): pillar.title
        case .area(let area): TwinBodyAreas.name(area)
        }
    }

    private var detail: String {
        switch target {
        case .pillar(let pillar): pillar.onTheTwin
        case .area(let area):
            snapshot.bodyAreas[area, default: 0] > 0
                ? "Lit up by what you've learned about your body."
                : (AcademyContent.areas(forSport: learner.sportSlug).contains(area)
                    ? "A key area for your sport — it lights up as your Body knowledge grows."
                    : "Part of your Body pillar.")
        }
    }

    var body: some View {
        let score = snapshot.score(pillar)
        let next = AcademyRecommender.next(for: pillar, AcademyContent.lessons, snapshot: snapshot, learner: learner)
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    GlassMetric(value: "\(score.total)", label: "\(pillar.title) score", height: 92, accent: pillar.color)
                    GlassMetric(value: "\(score.knowledge)", label: "Knowledge", height: 76)
                    GlassMetric(value: "\(score.habits)", label: "Habits & mindset", height: 76)
                }
                if pillar == .mind { egoBalance }
                if pillar == .legends { traits }
                if let next {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Next lesson for this")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.mutedText)
                        Text(next.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        Button { onStart(next) } label: { HeroCTALabel("Start · \(next.minutes) min") }
                            .buttonStyle(.primary)
                    }
                } else {
                    Text("You've finished every \(pillar.title) lesson for now.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .padding(24)
        }
        .background(AppTheme.background.ignoresSafeArea())
    }

    private var egoBalance: some View {
        let balance = snapshot.egoBalance
        let words = abs(balance) < 0.2 ? "Balanced: confident in the game, open to learning after it."
            : (balance < 0 ? "Leaning to confidence — remember to ask what you can learn."
                : "Leaning to humility — back yourself in the big moments.")
        return VStack(alignment: .leading, spacing: 6) {
            Text("Confidence and humility")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Text(words)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private var traits: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Legend traits")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            if snapshot.traits.isEmpty {
                Text("Legends lessons unlock traits like resilience and vision.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            ForEach(snapshot.traits.compactMap(AcademyContent.trait), id: \.id) { trait in
                HStack(spacing: 10) {
                    Circle().strokeBorder(AppTheme.yellow, lineWidth: 1.5).frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(trait.title).font(.body.weight(.semibold)).foregroundStyle(AppTheme.ink)
                        Text(trait.detail).font(.footnote).foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }
        }
    }
}

/// "Need to talk to someone?" — the helpline for the phone's country
/// (SupportResources), a trusted adult, and the emergency number.
struct SupportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    private let resource = SupportResources.resource(region: Locale.current.region?.identifier)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("You don't have to sort it out alone. Talking helps — to a parent, a coach, a teacher, or someone at a helpline.")
                        .font(.body)
                        .foregroundStyle(AppTheme.secondaryText)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(resource.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        if let display = resource.display {
                            Text(display)
                                .font(.system(size: 40, weight: .bold).monospacedDigit())
                                .foregroundStyle(AppTheme.ink)
                        }
                        Text(resource.detail)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                        if let phone = resource.phone, let url = URL(string: "tel:\(phone)") {
                            Button { openURL(url) } label: { HeroCTALabel("Call \(resource.display ?? phone)") }
                                .buttonStyle(.primary)
                                .padding(.top, 6)
                        }
                        if let website = resource.website, let url = URL(string: website) {
                            Button("Website") { openURL(url) }
                                .buttonStyle(.secondary)
                        }
                    }
                    .cardStyle(padding: 18)
                    Text("In an emergency, or if you think about hurting yourself, call \(resource.emergency) now.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.danger)
                    Text("Academy lessons about the mind teach mental skills for sport. They are not therapy.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedText)
                }
                .padding(24)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Need to talk?")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
