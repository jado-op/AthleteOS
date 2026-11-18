import SwiftUI

/// "Exercises by muscle" (Workout tab): tap a muscle group on the body, see
/// which exercises train it as a main mover, grouped by what they build —
/// strength, power, injury prevention… (docs/TRAINING-RESEARCH.md §2). One
/// tap on an exercise opens how it's done.
struct MuscleExercisesSheet: View {
    let catalogue: Catalogue
    let athlete: Athlete?
    let onOpen: (CatalogueItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var group: MuscleGroup = .glutes

    /// Base exercises only (variants live on each exercise's page), plus the
    /// athlete's own sport drills.
    private var items: [CatalogueItem] {
        let sport = athlete?.activeSport?.sportSlug
        return catalogue.itemsBySlug.values.filter { item in
            item.baseSlug == nil && (item.kind == "exercise" || (sport != nil && item.itemSportSlug == sport))
        }
    }

    /// The group's exercises by quality, in the order a session runs them.
    private struct QualityGroupRows: Identifiable {
        let quality: TrainingQuality
        let items: [CatalogueItem]
        var id: String { quality.rawValue }
    }

    private var sections: [QualityGroupRows] {
        let matching = items.filter { $0.planProfile.works(group, primaryOnly: true) }
        let byQuality = Dictionary(grouping: matching) { $0.planProfile.trains }
        return TrainingQuality.allCases.compactMap { quality -> QualityGroupRows? in
            guard let list = byQuality[quality], !list.isEmpty else { return nil }
            return QualityGroupRows(quality: quality, items: list.sorted { $0.name < $1.name })
        }
    }

    private var highlight: [String: Double] {
        var out: [String: Double] = [:]
        for muscle in muscles where MuscleGroup(region: muscle.region) == group {
            out[muscle.drawable ? muscle.id : (muscle.renderVia ?? muscle.id)] = 1
        }
        return out
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Headline([.soft("What trains your "), .strong(group.name), .soft("?")], size: 30)
                    HStack(spacing: 12) {
                        MuscleMapView(side: .front, weights: highlight).frame(height: 200)
                        MuscleMapView(side: .back, weights: highlight).frame(height: 200)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                    groupChips
                    let found = sections
                    if found.isEmpty {
                        Text(catalogue.itemsBySlug.isEmpty ? "Your exercises are still downloading." : "Nothing in your library trains this as a main muscle.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    ForEach(found) { section in
                        qualitySection(section.quality, section.items)
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .appScreen()
            .toolbar {
                CloseToolbarItem { dismiss() }
            }
        }
    }

    private var groupChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(MuscleGroup.allCases) { value in
                Button { withAnimation(.easeInOut(duration: 0.2)) { group = value } } label: {
                    Chip(value.title, isSelected: group == value)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func qualitySection(_ quality: TrainingQuality, _ list: [CatalogueItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(quality.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Text("\(list.count)")
                    .font(.telemetry(12))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .accessibilityAddTraits(.isHeader)
            Text(quality.howItsTrained)
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(list.prefix(12)) { item in
                    Button { onOpen(item) } label: {
                        ListRow(systemImage: item.kind == "drill" ? "sportscourt" : "figure.strengthtraining.functional",
                                color: AuraTone.training.mark, title: item.name,
                                detail: muscleLine(item.planProfile))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .glassSurface()
        }
    }

    /// "Main: glutes, quads · helps: hamstrings".
    private func muscleLine(_ profile: ExerciseProfile) -> String {
        let main = profile.primaryMuscles.map(FocusMuscle.title).joined(separator: ", ")
        let helps = profile.secondaryMuscles.prefix(3).map(FocusMuscle.title).joined(separator: ", ")
        return helps.isEmpty ? main.capitalizedFirst : "\(main.capitalizedFirst) · helps: \(helps)"
    }
}

extension String {
    // Used by the muscle sheet's rows.
    /// "glutes, quads" → "Glutes, quads".
    var capitalizedFirst: String { String(prefix(1)).uppercased() + String(dropFirst()) }
}
