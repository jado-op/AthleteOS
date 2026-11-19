import SwiftUI

// "More insights into your health" (owner, 2026-11-19; was "What your Suunto
// sees"): the twin's health dashboard, powered only by Apple Health. The twin
// shows its first cards and opens the whole page; every card exists only when
// Health holds recent data for it (`HealthWidgetRegistry`).

/// Lays out one section's widgets: the big ones full width, the rest as tiles.
struct HealthSectionView: View {
    let section: HealthSection
    let snapshot: HealthSnapshot
    let age: Int
    let readinessDays: [(date: Date, band: ReadinessBand?)]
    let openMetric: (HealthMetric) -> Void
    let openRoute: (HealthWorkout) -> Void

    private var full: [HealthWidgetKind] {
        section.widgets.filter { kind in
            if case .metric(let metric) = kind { return metric.isFeatured }
            return true
        }
    }

    private var tiles: [HealthMetric] {
        section.widgets.compactMap { kind in
            if case .metric(let metric) = kind, !metric.isFeatured { return metric }
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(full) { kind in
                HealthWidgetView(kind: kind, snapshot: snapshot, age: age, readinessDays: readinessDays,
                                 openMetric: openMetric, openRoute: openRoute)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
            if !tiles.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(tiles) { metric in
                        if let series = snapshot.series[metric], let summary = snapshot.summary(metric) {
                            HealthMetricTile(summary: summary, series: series) { openMetric(metric) }
                                .transition(.opacity)
                        }
                    }
                }
            }
        }
    }
}

/// One widget, by kind.
struct HealthWidgetView: View {
    let kind: HealthWidgetKind
    let snapshot: HealthSnapshot
    let age: Int
    let readinessDays: [(date: Date, band: ReadinessBand?)]
    let openMetric: (HealthMetric) -> Void
    let openRoute: (HealthWorkout) -> Void

    var body: some View {
        switch kind {
        case .recovery:
            HealthRecoveryWidget(reading: HealthRecovery.read(snapshot), readinessDays: readinessDays)
        case .sleep:
            HealthSleepWidget(nights: snapshot.nights)
        case .sleepSchedule:
            if let summary = SleepSchedule.summary(snapshot.nights, now: .now, calendar: .current) {
                HealthSleepScheduleWidget(nights: snapshot.nights, summary: summary)
            }
        case .workouts:
            HealthWorkoutsWidget(workouts: snapshot.workouts, age: age, openRoute: openRoute)
        case .metric(let metric):
            if let series = snapshot.series[metric], let summary = snapshot.summary(metric) {
                if metric.isFeatured {
                    HealthMetricCard(summary: summary, series: series) { openMetric(metric) }
                } else {
                    HealthMetricTile(summary: summary, series: series) { openMetric(metric) }
                }
            }
        }
    }
}

/// The whole page, pushed from the twin.
struct MoreHealthInsightsView: View {
    @ObservedObject var model: HealthInsightsViewModel
    let age: Int
    let readinessDays: [(date: Date, band: ReadinessBand?)]

    @Environment(\.scenePhase) private var scenePhase
    @State private var openMetric: HealthMetric?
    @State private var openRoute: HealthWorkout?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Headline([.soft("More insights into "), .strong("your health.")], size: 34)
                if let measured = HealthTime.updated(model.snapshot.lastMeasured, prefix: "last measured") {
                    Text("From Apple Health · " + measured)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.mutedText)
                        .padding(.top, 10)
                }
                content.padding(.top, 28)
                Text("Only what your watch, band, phone or apps write to Apple Health. Each number is compared with your own usual, never with anyone else, and never a diagnosis. Health data stays on your phone.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 36)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .animation(.smooth(duration: 0.35), value: model.sections)
        }
        .scrollIndicators(.hidden)
        .appScreen()
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayModeInline()
        .refreshable { await model.load(force: true) }
        .task { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
        .sheet(item: $openMetric) { metric in
            if let series = model.snapshot.series[metric], let summary = model.snapshot.summary(metric) {
                HealthMetricDetail(summary: summary, series: series)
            }
        }
        .sheet(item: $openRoute) { workout in HealthRouteSheet(workout: workout) }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            HStack {
                Spacer()
                ProgressView().tint(AppTheme.ink)
                Spacer()
            }
            .padding(.vertical, 60)
        case .unavailable:
            HealthEmptyState(available: false) {}
        case .empty:
            HealthEmptyState(available: true) { await model.connect() }
        case .ready:
            VStack(alignment: .leading, spacing: 40) {
                ForEach(model.sections) { section in
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(section.category.title)
                        HealthSectionView(section: section, snapshot: model.snapshot, age: age, readinessDays: readinessDays,
                                          openMetric: { openMetric = $0 }, openRoute: { openRoute = $0 })
                    }
                    .transition(.opacity)
                }
            }
        }
    }
}

/// The twin's section: the morning, last night and the heart, then the way
/// into the whole page.
struct HealthInsightsSection: View {
    @ObservedObject var model: HealthInsightsViewModel
    let age: Int
    let readinessDays: [(date: Date, band: ReadinessBand?)]
    let openAll: () -> Void

    @State private var openMetric: HealthMetric?
    @State private var openRoute: HealthWorkout?

    /// The first cards: recovery and sleep when there, then up to two heart tiles.
    private var preview: [HealthWidgetKind] {
        let shown = model.widgets
        var picked = shown.filter { $0 == .recovery || $0 == .sleep }
        if picked.isEmpty, let first = shown.first(where: { kind in
            if case .metric(let metric) = kind { return metric.isFeatured }
            return kind == .workouts
        }) {
            picked.append(first)
        }
        return picked
    }

    private var previewTiles: [HealthMetric] {
        let candidates: [HealthMetric] = [.restingHeartRate, .heartRateVariability, .exerciseMinutes, .steps, .bloodOxygen, .vo2Max]
        let shown = Set(model.widgets)
        return Array(candidates.filter { shown.contains(.metric($0)) && !preview.contains(.metric($0)) }.prefix(2))
    }

    var body: some View {
        switch model.phase {
        case .loading, .unavailable:
            EmptyView()
        case .empty:
            VStack(alignment: .leading, spacing: 14) {
                Headline([.soft("More insights into "), .strong("your health.")], size: 30)
                HealthEmptyState(available: true, compact: true) { await model.connect() }
            }
        case .ready:
            VStack(alignment: .leading, spacing: 14) {
                Headline([.soft("More insights into "), .strong("your health.")], size: 30)
                    .padding(.bottom, 4)
                ForEach(preview) { kind in
                    HealthWidgetView(kind: kind, snapshot: model.snapshot, age: age, readinessDays: readinessDays,
                                     openMetric: { openMetric = $0 }, openRoute: { openRoute = $0 })
                }
                if !previewTiles.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(previewTiles) { metric in
                            if let series = model.snapshot.series[metric], let summary = model.snapshot.summary(metric) {
                                HealthMetricTile(summary: summary, series: series) { openMetric = metric }
                            }
                        }
                    }
                    .id("health-tiles")
                }
                Button(action: openAll) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("All your health insights")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                            Text(countLine)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1) }
                }
                .buttonStyle(.plain)
            }
            .sheet(item: $openMetric) { metric in
                if let series = model.snapshot.series[metric], let summary = model.snapshot.summary(metric) {
                    HealthMetricDetail(summary: summary, series: series)
                }
            }
            .sheet(item: $openRoute) { workout in HealthRouteSheet(workout: workout) }
        }
    }

    /// "Sleep, heart, activity and body · 14 measurements"
    private var countLine: String {
        let names = model.sections.map { $0.category.title.lowercased() }.filter { $0 != "this morning" }
        let list: String
        switch names.count {
        case 0: list = ""
        case 1: list = names[0]
        default: list = names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
        let count = model.widgets.count
        let cards = "\(count) \(count == 1 ? "card" : "cards")"
        guard let first = list.first else { return cards }
        let capitalised = String(first).uppercased() + String(list.dropFirst())
        return capitalised + " · " + cards
    }
}

/// The one empty state: how data gets into Apple Health, and the switch to allow it.
struct HealthEmptyState: View {
    let available: Bool
    var compact = false
    let connect: () async -> Void

    @State private var working = false

    var body: some View {
        AuraCard(.calm, padding: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(AuraTone.training.mark)
                Text(available ? "Nothing from Apple Health yet." : "Apple Health isn't on this device.")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if available {
                    VStack(alignment: .leading, spacing: 10) {
                        step(1, "Allow AthleteOS to read your Health data.")
                        step(2, "Let your watch or band's app write to Apple Health: Apple Watch does it by itself; Garmin Connect, Suunto, Fitbit, Polar Flow, COROS, Oura or WHOOP in their own settings.")
                        if !compact {
                            step(3, "Cards appear here as soon as data arrives: only the ones your devices actually measure.")
                        }
                    }
                    Button(working ? "Connecting…" : "Allow in Apple Health") {
                        working = true
                        Task {
                            await connect()
                            working = false
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(working)
                    Text("Already allowed? Check Settings → Health → Data Access & Devices → AthleteOS.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Health insights need an iPhone with the Health app. Everything else in AthleteOS works as usual.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.secondaryText)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
