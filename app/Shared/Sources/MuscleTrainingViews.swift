import SwiftData
import SwiftUI

extension MuscleTraining {
    /// Every logged set of the athlete, resolved against the catalogue.
    /// Sets whose exercise isn't in the catalogue (removed, or still loading)
    /// can't be placed on the body and are left out.
    @MainActor
    static func loggedSets(_ sessions: [Session], catalogue: Catalogue) -> [LoggedSet] {
        let imported = HealthWorkoutInbox.imported
        return sessions.flatMap { session -> [LoggedSet] in
            // A workout from Apple Health: what the athlete said it trained.
            if imported[session.clientId] != nil { return HealthWorkoutInbox.bodyMapSets(session, catalogue: catalogue) }
            return session.sets.compactMap { set -> LoggedSet? in
                guard let item = catalogue.item(set.itemSlug) else { return nil }
                return LoggedSet(date: session.startedAt, exercise: item.name, muscles: item.muscles,
                                 effort: Double(session.sessionRPE ?? 5))
            }
        }
    }
}

/// The top of the Workout tab: the body map with what was trained most, and
/// a one-line summary under it. Tap to walk through every muscle group.
struct MuscleTrainingSection: View {
    let athlete: Athlete
    let catalogue: Catalogue

    @State private var report: MuscleTraining.Report?
    @State private var showingDetail = false

    /// Changes whenever a set is logged or the catalogue finishes loading.
    private var inputKey: String {
        "\(catalogue.itemsBySlug.count)-\(athlete.sessions.count)-\(athlete.sessions.reduce(0) { $0 + $1.sets.count })-\(HealthWorkoutInbox.revision)"
    }

    var body: some View {
        Button { if report != nil { showingDetail = true } } label: {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader("Your body")
                TrainingBodyView(brightness: report?.brightness ?? [:], showsLabels: false)
                    .frame(maxWidth: 340)
                    .frame(height: 250)
                    .frame(maxWidth: .infinity)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(report?.summary ?? " ")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if report?.hasHistory == true {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.mutedText)
                            .accessibilityHidden(true)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your training by muscle group. \(report?.summary ?? "")")
        .accessibilityHint(report?.hasHistory == true ? "Opens each muscle group in turn" : "")
        .task(id: inputKey) { recompute() }
        .fullScreenCover(isPresented: $showingDetail) {
            if let report { MuscleTrainingDetailView(report: report) }
        }
    }

    private func recompute() {
        // Until the catalogue has loaded, no set can be placed: show nothing yet
        // rather than "no workouts logged".
        guard !catalogue.itemsBySlug.isEmpty else { report = nil; return }
        report = MuscleTraining.report(MuscleTraining.loggedSets(athlete.sessions, catalogue: catalogue), now: .now)
    }
}

/// The walkthrough: an overview, then one muscle group per page — most
/// trained first — with Back and Next, like the twin interview.
struct MuscleTrainingDetailView: View {
    let report: MuscleTraining.Report

    @Environment(\.dismiss) private var dismiss
    /// 0 = overview, 1… = the groups in report order.
    @State private var page = 0

    private var pages: Int { report.groups.count + 1 }
    private var isLast: Bool { page == pages - 1 }
    private var group: MuscleTraining.GroupStats? { page > 0 && page <= report.groups.count ? report.groups[page - 1] : nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                Group {
                    if let group { groupPage(group).id(group.group) } else { overview }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            footer
        }
        .background(AppTheme.background.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: page)
    }

    // MARK: Header and footer

    private var header: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Close")
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(AppTheme.ink)
                        .frame(width: proxy.size.width * CGFloat(page + 1) / CGFloat(pages))
                }
            }
            .frame(height: 4)
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue(group.map { "\($0.group.title), \(page) of \(report.groups.count)" } ?? "Overview")
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if page > 0 {
                Button { page -= 1 } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .frame(width: 52, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .foregroundStyle(AppTheme.secondaryText)
                .glassCapsule()
                .accessibilityLabel("Previous")
            }
            Button { if isLast { dismiss() } else { page += 1 } } label: {
                HeroCTALabel(nextTitle)
            }
            .buttonStyle(.primary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var nextTitle: String {
        if isLast { return "Done" }
        return "Next: \(report.groups[page].group.title)"
    }

    // MARK: Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: 22) {
            Headline([.strong("Your training"), .soft(" over the last four weeks.")], size: 34)
            TrainingBodyView(brightness: report.brightness)
                .frame(height: 300)
            Text(report.summary)
                .font(.body)
                .foregroundStyle(AppTheme.ink.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                FigureStat("\(report.workouts)", label: "workouts")
                FigureStat("\(report.totalSets)", label: "sets")
                FigureStat(String(format: "%.1f", report.weeks), label: "weeks")
            }
            ranking
            howItsCounted
        }
    }

    /// Every group as a bar, most trained first.
    private var ranking: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("By muscle group") { Text("share") }
            ForEach(report.groups) { stats in
                HStack(spacing: 12) {
                    Text(stats.group.title)
                        .font(.subheadline)
                        .foregroundStyle(stats.sets > 0 ? AppTheme.ink : AppTheme.mutedText)
                        .frame(width: 118, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.06))
                            Capsule().fill(AuraTone.training.mark.opacity(0.35 + 0.6 * relative(stats)))
                                .frame(width: max(stats.sets > 0 ? 4 : 0, proxy.size.width * relative(stats)))
                        }
                    }
                    .frame(height: 6)
                    Text(percent(stats.share))
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(width: 40, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var howItsCounted: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How it's counted")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            Text("Each logged set counts for the muscles that do the work — fully for the main mover, partly for helpers, not at all for muscles that only stabilise. Brighter means more work; recent sets count more.")
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: One group

    private func groupPage(_ stats: MuscleTraining.GroupStats) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("\(stats.rank) of \(report.groups.count) · \(rankWord(stats))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            Headline([.strong(stats.group.title)], size: 36)
            TrainingBodyView(brightness: report.brightness, focus: stats.group)
                .frame(height: 300)
            Text(line(stats))
                .font(.body)
                .foregroundStyle(AppTheme.ink.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 16) {
                FigureStat(setsPerWeek(stats), label: "sets a week")
                FigureStat(stats.daysTrained == 0 ? "0" : String(format: "%.1f×", stats.timesPerWeek), label: "a week")
                FigureStat(stats.daysSince.map { $0 == 0 ? "Today" : "\($0) d" } ?? "—", label: "since last")
                FigureStat(percent(stats.share), label: "of training")
            }
            if !stats.topExercises.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Trained by") { Text("sets") }
                    ForEach(stats.topExercises, id: \.name) { exercise in
                        HStack {
                            Text(exercise.name)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.ink)
                            Spacer(minLength: 12)
                            Text(String(format: "%.1f", exercise.sets))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    // MARK: Wording

    /// One factual line per group, from the numbers alone.
    private func line(_ stats: MuscleTraining.GroupStats) -> String {
        let name = stats.group.title
        guard stats.sets > 0 else {
            if let days = stats.daysSince {
                return "\(name): not trained in the last four weeks. Last worked \(MuscleTraining.ago(days))."
            }
            return "\(name): not trained since you started logging."
        }
        let last = stats.daysSince.map { " Last worked \(MuscleTraining.ago($0))." } ?? ""
        if stats.daysTrained == 0 {
            return "\(name) \(stats.group.plural ? "only get" : "only gets") a little work, as a helper in other exercises.\(last)"
        }
        return "\(name): \(MuscleTraining.frequency(stats.timesPerWeek)).\(last)"
    }

    private func rankWord(_ stats: MuscleTraining.GroupStats) -> String {
        if stats.sets == 0 { return "Not trained lately" }
        if stats.rank == 1 { return "Most trained" }
        if stats.rank == report.groups.filter({ $0.sets > 0 }).count { return "Least trained" }
        return "Trained"
    }

    private func setsPerWeek(_ stats: MuscleTraining.GroupStats) -> String {
        if stats.sets == 0 { return "0" }
        if stats.setsPerWeek < 1 { return "<1" }
        return "\(Int(stats.setsPerWeek.rounded()))"
    }

    private func percent(_ share: Double) -> String {
        share > 0 && share < 0.01 ? "<1%" : "\(Int((share * 100).rounded()))%"
    }

    private func relative(_ stats: MuscleTraining.GroupStats) -> Double {
        let top = report.groups.first?.sets ?? 0
        return top > 0 ? stats.sets / top : 0
    }
}
