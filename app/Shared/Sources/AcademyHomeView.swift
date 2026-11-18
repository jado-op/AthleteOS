import SwiftUI

/// The Academy tab (docs/ACADEMY-PLAN.md): the Digital Twin on its stage as
/// the hero, one clear next lesson, the six pillars, before vs now, and the
/// always-available "Need to talk to someone?". Before the twin exists, the
/// stage shows its outline and one button: create it.
struct AcademyHomeView: View {
    let athlete: Athlete

    @State private var state = AcademyState()
    @State private var target: TwinTarget?
    @State private var playing: AcademyLesson?
    @State private var showingSupport = false
    @State private var showingBirth = false
    @State private var showingCompare = false

    private var sportSlug: String? { athlete.activeSport?.sportSlug }
    private var born: Bool { state.bornAt != nil }

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

    /// "Your twin · Soccer · Midfielder"
    private var eyebrow: String {
        var parts = ["Your twin"]
        if let slug = sportSlug {
            parts.append(AthleteStats.sportName(athlete))
            if let position = athlete.activeSport?.positionSlug,
               let name = allSportsBySlug[slug]?.positions.first(where: { $0.slug == position })?.name {
                parts.append(name)
            }
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let twin = snapshot
        let recommendations = AcademyRecommender.recommend(AcademyContent.lessons, snapshot: twin, learner: learner)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        DigitalTwinView(state: TwinVisualState(appearance: state.look, sportSlug: sportSlug, snapshot: twin,
                                                               dormant: !born)) { tapped in
                            if born {
                                AcademyEvent.log(.bodyZoneTapped)
                                target = tapped
                            } else {
                                showingBirth = true
                            }
                        }
                        .frame(height: 500)
                        .padding(.horizontal, -20)
                    }
                    if born {
                        if let first = recommendations.first { nextCard(first) } else { upToDate }
                    } else {
                        birthCard
                    }
                    let more = born ? Array(recommendations.dropFirst()) : recommendations
                    if !more.isEmpty { lessonRows(more, title: born ? "Also for you" : "Lessons") }
                    pillarList(twin)
                    if born { compareRow }
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
            // Screenshots: `-tab academy -sheet birth` opens the twin's birth.
            if DemoData.initialTab == .academy, DemoData.initialSheet == "birth" { showingBirth = true }
        }
        .sheet(item: $target) { target in
            AcademyAreaSheet(target: target, snapshot: twin, learner: learner) { lesson in
                self.target = nil
                playing = lesson
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingSupport) { SupportSheet() }
        .sheet(isPresented: $showingCompare) {
            TwinCompareSheet(state: state, sportSlug: sportSlug)
        }
        .fullScreenCover(item: $playing, onDismiss: { state = AcademyStore.load() }) { lesson in
            AcademyLessonView(lesson: lesson, sportSlug: sportSlug)
        }
        .fullScreenCover(isPresented: $showingBirth, onDismiss: { state = AcademyStore.load() }) {
            AcademyBirthView(sportSlug: sportSlug, summary: eyebrow)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                ProfileButton(name: athlete.displayName)
                Text("Academy")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
            }
            Text(eyebrow)
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.leading, 52)
        }
        .padding(.top, 8)
    }

    // MARK: The one next step

    private var birthCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Create your twin")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.ink)
            Text("Two minutes: how it looks, what you want to grow, eight honest answers. Only you can see it.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button { showingBirth = true } label: { HeroCTALabel("Create my twin") }
                .buttonStyle(.primary)
                .padding(.top, 8)
        }
        .cardStyle(padding: 18)
    }

    private func nextCard(_ recommendation: AcademyRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Next for you", systemImage: recommendation.lesson.pillar.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(recommendation.lesson.pillar.color)
            Text(recommendation.lesson.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(recommendation.reason) · \(recommendation.lesson.minutes) min")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
            Button { playing = recommendation.lesson } label: { HeroCTALabel("Start") }
                .buttonStyle(.primary)
                .padding(.top, 10)
        }
        .padding(18)
        .glassSurface(tint: recommendation.lesson.pillar.color)
    }

    private var upToDate: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("You're up to date")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Text("You've finished every lesson for now. New ones arrive with updates.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func lessonRows(_ recommendations: [AcademyRecommendation], title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title)
            VStack(spacing: 0) {
                ForEach(recommendations) { recommendation in
                    Button { playing = recommendation.lesson } label: {
                        ListRow(systemImage: recommendation.lesson.pillar.systemImage, color: recommendation.lesson.pillar.color,
                                title: recommendation.lesson.title,
                                detail: "\(recommendation.reason) · \(recommendation.lesson.minutes) min")
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: Pillars, before vs now, support

    private func pillarList(_ twin: TwinSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Pillars", subtitle: "Knowledge from lessons, habits from your own answers.")
            VStack(spacing: 0) {
                ForEach(TwinPillar.allCases) { pillar in
                    Button { target = .pillar(pillar) } label: { pillarRow(pillar, score: twin.score(pillar)) }
                        .buttonStyle(.plain)
                        .disabled(!born)
                }
            }
        }
    }

    private func pillarRow(_ pillar: TwinPillar, score: TwinPillarScore) -> some View {
        HStack(spacing: 14) {
            Image(systemName: pillar.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(pillar.color)
                .frame(width: 40, height: 40)
                .background(pillar.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(pillar.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Spacer(minLength: 8)
                    Text(born ? "\(score.total)" : "–")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(AppTheme.ink)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(pillar.color.opacity(0.85))
                            .frame(width: proxy.size.width * CGFloat(score.total) / CGFloat(TwinScoring.maximum))
                    }
                }
                .frame(height: 4)
                Text(pillar.subtitle)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var compareRow: some View {
        Button { showingCompare = true } label: {
            ListRow(systemImage: "arrow.left.and.right", color: AppTheme.brightRed, title: "Before vs now",
                    detail: "Your twin when it was born, and today")
        }
        .buttonStyle(.plain)
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
