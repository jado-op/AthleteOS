import Charts
import SwiftData
import SwiftUI

/// The original idea's "track your gym progress": every exercise you've
/// logged, with its best set, and a chart of that exercise over time.
struct ExerciseProgressListView: View {
    let sessions: [Session]
    let catalogue: Catalogue
    @Environment(\.dismiss) private var dismiss

    struct ExerciseSummary: Identifiable {
        let slug: String
        let name: String
        let sessionCount: Int
        let totalSets: Int
        /// nil when the sets carry no number (done, nothing measured).
        let best: String?
        var id: String { slug }
    }

    private var summaries: [ExerciseSummary] {
        var bySlug: [String: [SetLog]] = [:]
        for session in sessions {
            for set in session.sets {
                bySlug[set.itemSlug, default: []].append(set)
            }
        }
        return bySlug.map { slug, sets in
            ExerciseSummary(
                slug: slug,
                name: catalogue.item(slug)?.name ?? displayName(forSlug: slug),
                sessionCount: Set(sets.compactMap { $0.session?.id }).count,
                totalSets: sets.count,
                best: ExerciseProgress.bestLabel(sets)
            )
        }
        .sorted { $0.totalSets > $1.totalSets }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ScreenTitle("Exercise progress", subtitle: "Your best sets, and how they've moved.")
                    if summaries.isEmpty {
                        Text("Log a session and every exercise you do shows up here with its own progress chart.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .cardStyle()
                    }
                    ForEach(summaries) { summary in
                        NavigationLink {
                            ExerciseProgressDetailView(slug: summary.slug, name: summary.name, sessions: sessions, item: catalogue.item(summary.slug))
                        } label: {
                            HStack(spacing: 14) {
                                ItemThumbnail(item: catalogue.item(summary.slug), size: 56)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(summary.name)
                                        .font(.headline)
                                        .foregroundStyle(AppTheme.ink)
                                        .multilineTextAlignment(.leading)
                                    Text("\(countedNoun(summary.sessionCount, "session")) · \(countedNoun(summary.totalSets, "set"))")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                                Spacer(minLength: 0)
                                if let best = summary.best {
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(best)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(AppTheme.ink)
                                        Text("best")
                                            .font(.caption2)
                                            .foregroundStyle(AppTheme.secondaryText)
                                    }
                                }
                            }
                            .cardStyle(padding: 12)
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

enum ExerciseProgress {
    /// The single number that best describes a set for this kind of dose.
    static func value(_ set: SetLog) -> Double {
        if let weight = set.weightKg, weight > 0 { return WeightUnit.current.value(kg: weight) }
        if let reps = set.reps { return Double(reps) }
        if let seconds = set.seconds { return Double(seconds) }
        if let distance = set.distanceM { return distance }
        return Double(set.contacts ?? 0)
    }

    static func unit(_ sets: [SetLog]) -> String {
        if sets.contains(where: { ($0.weightKg ?? 0) > 0 }) { return WeightUnit.current.rawValue }
        if sets.contains(where: { $0.reps != nil }) { return "reps" }
        if sets.contains(where: { $0.seconds != nil }) { return "s" }
        if sets.contains(where: { $0.distanceM != nil }) { return "m" }
        return "contacts"
    }

    /// nil when no set has a number above zero — "0 contacts best" says nothing.
    static func bestLabel(_ sets: [SetLog]) -> String? {
        let best = sets.map(value).max() ?? 0
        guard best > 0 else { return nil }
        return "\(best.formatted(.number.precision(.fractionLength(0...1)))) \(unit(sets))"
    }
}

struct ExerciseProgressDetailView: View {
    let slug: String
    let name: String
    let sessions: [Session]
    let item: CatalogueItem?

    struct Point: Identifiable {
        let date: Date
        let value: Double
        let sets: Int
        var id: Date { date }
    }

    private var sets: [SetLog] {
        sessions.flatMap(\.sets).filter { $0.itemSlug == slug }
    }

    private var points: [Point] {
        sessions
            .filter { session in session.sets.contains { $0.itemSlug == slug } }
            .map { session in
                let mine = session.sets.filter { $0.itemSlug == slug }
                return Point(date: session.startedAt, value: mine.map(ExerciseProgress.value).max() ?? 0, sets: mine.count)
            }
            .sorted { $0.date < $1.date }
    }

    private var unit: String { ExerciseProgress.unit(sets) }

    private var change: Double? {
        guard let first = points.first?.value, let last = points.last?.value, points.count >= 2, first > 0 else { return nil }
        return last / first - 1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenTitle(name, subtitle: "\(countedNoun(points.count, "session"))\(ExerciseProgress.bestLabel(sets).map { " · best \($0)" } ?? "")")

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text((points.last?.value ?? 0).formatted(.number.precision(.fractionLength(0...1))))
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                        Text(unit)
                            .font(.headline)
                            .foregroundStyle(AppTheme.secondaryText)
                        Spacer()
                        if let change {
                            Tag("\(change >= 0 ? "+" : "")\(Int((change * 100).rounded()))% since first", color: change >= 0 ? AppTheme.green : AppTheme.secondaryText)
                        }
                    }
                    Chart(points) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Best", point.value))
                            .foregroundStyle(AppTheme.ink)
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Date", point.date), y: .value("Best", point.value))
                            .foregroundStyle(AppTheme.brand)
                        AreaMark(x: .value("Date", point.date), y: .value("Best", point.value))
                            .foregroundStyle(AppTheme.brand.opacity(0.08).gradient)
                            .interpolationMethod(.catmullRom)
                    }
                    .frame(height: 200)
                }
                .cardStyle()

                if let item {
                    NavigationLink {
                        ItemDetailView(item: item)
                    } label: {
                        HStack {
                            Label("How to do it", systemImage: "play.circle.fill")
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        .cardStyle(padding: 16)
                    }
                    .buttonStyle(.plain)
                }

                SectionTitle("History")
                ForEach(points.reversed()) { point in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(point.date.formatted(.dateTime.weekday(.abbreviated).month().day()))
                                .font(.subheadline.bold())
                                .foregroundStyle(AppTheme.ink)
                            Text(countedNoun(point.sets, "set"))
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer()
                        Text("\(point.value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                    }
                    .cardStyle(padding: 14)
                }
            }
            .padding(20)
        }
        .appScreen()
    }
}
