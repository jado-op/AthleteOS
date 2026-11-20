import Charts
import SwiftUI

// "Your last 7 days" (owner, 2026-11-20): the twin's body, coloured by how
// hard each muscle group worked this week, with the week's numbers from
// Apple Health as callouts around it. Look (docs/TWIN-WEEK-DESIGN.md):
// restraint — black, one warm heat scale, hairlines, big light numbers,
// no boxes, motion only when something happens.

/// The week's groups turned into what the body shows and says.
enum TwinHeat {
    /// Drawable muscle slug → band.
    static func map(_ weeks: [MuscleTraining.GroupWeek]) -> [String: WorkoutTagging.Band] {
        var heat: [String: WorkoutTagging.Band] = [:]
        for week in weeks {
            for slug in week.group.drawableMuscles { heat[slug] = max(heat[slug] ?? week.band, week.band) }
        }
        return heat
    }

    /// The hardest band in each region that worked, hardest first.
    static func regionBands(_ weeks: [MuscleTraining.GroupWeek]) -> [(region: GymRegion, band: WorkoutTagging.Band)] {
        let found: [(region: GymRegion, band: WorkoutTagging.Band)] = [GymRegion.lower, .upper, .core].compactMap { region in
            let groups = MuscleTraining.groups(of: region)
            let bands = weeks.filter { groups.contains($0.group) }.map(\.band)
            guard let top = bands.max() else { return nil }
            return (region, top)
        }
        return found.sorted { $0.band > $1.band }
    }

    /// "Legs worked very hard. Core solid, upper body light."
    static func sentence(_ weeks: [MuscleTraining.GroupWeek]) -> String {
        let regions = regionBands(weeks)
        guard let lead = regions.first else { return "A rested week so far." }
        let name = MuscleTraining.capitalized(lead.region.title)
        var text: String
        switch lead.band {
        case .veryHard: text = "\(name) worked very hard."
        case .solid: text = "\(name) had a solid week."
        case .light: text = "\(name) had a light week."
        }
        let rest = regions.dropFirst().map { "\($0.region.title) \($0.band.title.lowercased())" }
        if !rest.isEmpty { text += " " + MuscleTraining.capitalized(rest.joined(separator: ", ")) + "." }
        return text
    }

    static func region(of group: MuscleGroup) -> GymRegion {
        [GymRegion.upper, .lower, .core].first { MuscleTraining.groups(of: $0).contains(group) } ?? .core
    }
}

/// The twin page's way in: a calm dark plate with the heat body glowing in it.
struct TwinWeekCard: View {
    let heat: [String: WorkoutTagging.Band]
    let sentence: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your last 7 days")
                        .font(.system(size: 24, weight: .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(AppTheme.ink)
                    Text(sentence)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Text("Open")
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(Color.white, in: Capsule())
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
                TrainingBodyView(brightness: [:], showsLabels: false, facing: .front, heat: heat)
                    .frame(width: 84, height: 168)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    Color(rgb: 0x0C0C0F)
                    RadialGradient(colors: [AuraTone.training.mark.opacity(0.16), .clear], center: UnitPoint(x: 0.82, y: 0.5),
                                   startRadius: 0, endRadius: 150)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1) }
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Shows how hard each part of your body worked, and your week's numbers")
    }
}

/// A hairline from a callout to the body that draws itself in.
private struct LeaderLine: Shape {
    var start: CGPoint
    var end: CGPoint
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        // Out level first, then to the body: the product-callout bend.
        path.addLine(to: CGPoint(x: start.x + (end.x - start.x) * 0.45, y: start.y))
        path.addLine(to: end)
        return path.trimmedPath(from: 0, to: progress)
    }
}

/// A callout's place on the stage.
private struct Placed: Identifiable {
    let stat: TwinWeek.Stat
    let point: CGPoint
    let left: Bool
    var id: String { stat.id }
}

struct TwinWeekView: View {
    let weeks: [MuscleTraining.GroupWeek]
    let recovering: [(region: GymRegion, days: Int)]
    @ObservedObject var health: HealthInsightsViewModel
    let training: [TwinWeek.Training]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var facing: BodyAnatomy.Facing = .front
    @State private var rotation: Double = 0
    @State private var selectedStat: String?
    @State private var selectedGroup: MuscleGroup?
    @State private var drawn: CGFloat = 0
    @State private var shown = false

    private var heat: [String: WorkoutTagging.Band] { TwinHeat.map(weeks) }

    private var stats: [TwinWeek.Stat] {
        TwinWeek.stats(snapshot: health.snapshot, training: training, now: .now)
    }

    private var range: String {
        let days = TwinWeek.days(now: .now)
        guard let first = days.first, let last = days.last else { return "" }
        return first.formatted(.dateTime.day().month(.abbreviated)) + " – " + last.formatted(.dateTime.day().month(.abbreviated))
    }

    var body: some View {
        let stats = stats
        VStack(spacing: 0) {
            header
            GeometryReader { proxy in
                stage(stats, size: proxy.size)
            }
            .frame(height: 470)
            controls
                .padding(.top, 6)
            footer(stats)
        }
        .background {
            ZStack {
                Color.black
                RadialGradient(colors: [AuraTone.training.mark.opacity(0.09), .clear], center: UnitPoint(x: 0.5, y: 0.32),
                               startRadius: 0, endRadius: 260)
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: selectedGroup)
        .sensoryFeedback(.selection, trigger: selectedStat)
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.45)) { shown = true }
            withAnimation(.easeInOut(duration: reduceMotion ? 0 : 0.9).delay(reduceMotion ? 0 : 0.25)) { drawn = 1 }
        }
        .task { await health.load() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Your last 7 days")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(AppTheme.ink)
                Text(range)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer(minLength: 0)
            CircleIconButton(systemImage: "xmark", accessibilityLabel: "Close") { dismiss() }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }

    // MARK: The body and its callouts

    private func placements(_ stats: [TwinWeek.Stat], size: CGSize) -> [Placed] {
        let columns = TwinWeek.columns(stats)
        let slots: [CGFloat] = [0.1, 0.43, 0.76]
        var result: [Placed] = []
        for (index, stat) in columns.left.prefix(3).enumerated() {
            result.append(Placed(stat: stat, point: CGPoint(x: 22, y: size.height * slots[index]), left: true))
        }
        for (index, stat) in columns.right.prefix(3).enumerated() {
            result.append(Placed(stat: stat, point: CGPoint(x: size.width - 22, y: size.height * slots[index]), left: false))
        }
        return result
    }

    private func stage(_ stats: [TwinWeek.Stat], size: CGSize) -> some View {
        let figureHeight = min(size.height * 0.94, 440)
        let figureWidth = figureHeight * muscleMapCanonicalWidth / muscleMapCanonicalHeight
        let origin = CGPoint(x: (size.width - figureWidth) / 2, y: (size.height - figureHeight) / 2)
        let calloutWidth = max(90, (size.width - figureWidth) / 2 - 18)
        let placed = placements(stats, size: size)

        return ZStack(alignment: .topLeading) {
            ForEach(placed) { entry in
                let anchor = anchorPoint(entry.stat.anchor, left: entry.left, origin: origin, width: figureWidth, height: figureHeight)
                let start = CGPoint(x: entry.left ? entry.point.x + calloutWidth + 4 : entry.point.x - calloutWidth - 4, y: entry.point.y + 30)
                let isSelected = selectedStat == entry.stat.id
                let active = selectedStat == nil || isSelected
                LeaderLine(start: start, end: anchor, progress: drawn)
                    .stroke(Color.white.opacity(isSelected ? 0.85 : (active ? 0.28 : 0.1)), lineWidth: 0.75)
                Circle()
                    .strokeBorder(Color.white.opacity(active ? 0.8 : 0.2), lineWidth: 1)
                    .background(Circle().fill(Color.black))
                    .frame(width: 7, height: 7)
                    .position(anchor)
                    .opacity(Double(drawn))
            }
            .allowsHitTesting(false)

            TrainingBodyView(brightness: [:], focus: selectedGroup, showsLabels: false, facing: facing, heat: heat) { slug in
                tapped(slug)
            }
            .frame(width: figureWidth, height: figureHeight)
            .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
            .offset(x: origin.x, y: origin.y)
            .opacity(shown ? 1 : 0)
            .accessibilityLabel(bodyLabel)

            ForEach(Array(placed.enumerated()), id: \.element.id) { index, entry in
                callout(entry.stat, width: calloutWidth, left: entry.left)
                    .offset(x: entry.left ? entry.point.x : entry.point.x - calloutWidth, y: entry.point.y + (shown ? 0 : 6))
                    .opacity(shown ? 1 : 0)
                    .animation(.easeOut(duration: 0.5).delay(reduceMotion ? 0 : 0.35 + Double(index) * 0.06), value: shown)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var bodyLabel: String {
        let parts = TwinHeat.regionBands(weeks).map { "\($0.region.title) \($0.band.title.lowercased())" }
        let side = facing == .front ? "front" : "back"
        return "Your body from the \(side). " + (parts.isEmpty ? "Rested this week." : parts.joined(separator: ", ") + ".")
            + " Tap a muscle for its week."
    }

    /// Where a callout's line meets the body (fractions of the figure).
    private func anchorPoint(_ anchor: TwinWeek.Anchor, left: Bool, origin: CGPoint, width: CGFloat, height: CGFloat) -> CGPoint {
        let x: Double
        switch anchor {
        case .arms: x = left ? 0.25 : 0.75
        case .legs: x = left ? 0.4 : 0.6
        case .chest: x = left ? 0.42 : 0.58
        default: x = 0.5
        }
        return CGPoint(x: origin.x + width * x, y: origin.y + height * anchor.height)
    }

    private func callout(_ stat: TwinWeek.Stat, width: CGFloat, left: Bool) -> some View {
        let isSelected = selectedStat == stat.id
        let dimmed = selectedStat != nil && !isSelected
        return Button {
            withAnimation(.snappy(duration: 0.25)) {
                selectedGroup = nil
                selectedStat = isSelected ? nil : stat.id
            }
        } label: {
            VStack(alignment: left ? .leading : .trailing, spacing: 2) {
                Text(stat.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(stat.value)
                        .font(.system(size: 30, weight: .light).monospacedDigit())
                        .tracking(-0.8)
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(stat.unit)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if let change = stat.change {
                    Text(change)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(AppTheme.mutedText)
                        .lineLimit(2)
                        .multilineTextAlignment(left ? .leading : .trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: width, alignment: left ? .leading : .trailing)
            .opacity(dimmed ? 0.35 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the seven days")
    }

    // MARK: Front / back and the scale

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 2) {
                ForEach([BodyAnatomy.Facing.front, .back], id: \.self) { side in
                    let on = facing == side
                    Button { turn(to: side) } label: {
                        Text(side == .front ? "Front" : "Back")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(on ? Color.black : AppTheme.ink.opacity(0.8))
                            .frame(width: 72, height: 30)
                            .background(on ? Color.white : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Color.white.opacity(0.08), in: Capsule())
            .animation(.snappy(duration: 0.2), value: facing)

            HStack(spacing: 10) {
                ForEach(Array(Self.scale.enumerated()), id: \.offset) { _, band in
                    VStack(spacing: 6) {
                        Capsule().fill(HeatScale.color(band)).frame(height: 5)
                        Text(HeatScale.word(band))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 22)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Colour scale: rested, light, solid, very hard")
        }
    }

    private static let scale: [WorkoutTagging.Band?] = [nil, .light, .solid, .veryHard]

    private func turn(to side: BodyAnatomy.Facing) {
        guard side != facing else { return }
        guard !reduceMotion else { facing = side; return }
        withAnimation(.easeIn(duration: 0.2)) { rotation = 90 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            facing = side
            rotation = -90
            withAnimation(.easeOut(duration: 0.28)) { rotation = 0 }
        }
    }

    private func tapped(_ slug: String) {
        guard let group = MuscleGroup.allCases.first(where: { $0.drawableMuscles.contains(slug) }) else { return }
        withAnimation(.snappy(duration: 0.25)) {
            selectedStat = nil
            selectedGroup = selectedGroup == group ? nil : group
        }
    }

    // MARK: Below

    @ViewBuilder private func footer(_ stats: [TwinWeek.Stat]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let group = selectedGroup {
                    groupPanel(group)
                } else if let stat = stats.first(where: { $0.id == selectedStat }) {
                    chart(stat)
                } else {
                    Text(TwinHeat.sentence(weeks))
                        .font(.system(size: 21, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let ready = BodyStatusWidget.readyAgain(recovering) {
                        Text(ready)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Tap a muscle or a number for its week.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedText)
                    if health.phase == .empty {
                        Button { Task { await health.connect() } } label: {
                            Label("Add sleep, heart and steps from Apple Health", systemImage: "heart.text.square")
                        }
                        .buttonStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
    }

    private func groupPanel(_ group: MuscleGroup) -> some View {
        let week = weeks.first { $0.group == group }
        let region = TwinHeat.region(of: group)
        let ready = recovering.first { $0.region == region }
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .font(.system(size: 28, weight: .semibold))
                        .tracking(-0.5)
                        .foregroundStyle(AppTheme.ink)
                    HStack(spacing: 8) {
                        Circle().fill(HeatScale.color(week?.band)).frame(width: 9, height: 9)
                        Text(week.map { $0.band.title + " this week" } ?? "Rested this week")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink.opacity(0.85))
                    }
                }
                Spacer()
                Text(ready.map { readyText($0.days) } ?? "Ready now")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .overlay { Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1) }
            }
            if let week {
                HStack(spacing: 0) {
                    figure(HealthFormat.number(week.sets.rounded(), decimals: 0), "hard sets")
                    divider
                    figure("\(week.days)", week.days == 1 ? "day" : "days")
                    divider
                    figure(HealthFormat.number(week.effort, decimals: 1), "avg effort")
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(week.items.prefix(5).enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(HeatScale.color(WorkoutTagging.band(forRating: Int(item.effort.rounded()))))
                                .frame(width: 7, height: 7)
                            Text(item.exercise)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppTheme.ink)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(item.day.formatted(.dateTime.weekday(.abbreviated)) + " · effort " + HealthFormat.number(item.effort, decimals: 0))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        .frame(minHeight: 40)
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
                    }
                }
            } else {
                Text("Nothing worked your \(group.name) in the last 7 days.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.1)).frame(width: 0.5, height: 40)
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 30, weight: .light).monospacedDigit())
                .foregroundStyle(AppTheme.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func readyText(_ days: Int) -> String {
        if days <= 1 { return "Ready tomorrow" }
        let day = Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: .now)) ?? .now
        return "Ready " + day.formatted(.dateTime.weekday(.wide))
    }

    private func chart(_ stat: TwinWeek.Stat) -> some View {
        let days = TwinWeek.days(now: .now)
        let points = zip(days, stat.days).compactMap { day, value in value.map { (day: day, value: $0) } }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(stat.title)
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Text(stat.change ?? "")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Chart {
                ForEach(points, id: \.day) { point in
                    BarMark(x: .value("Day", point.day, unit: .day), y: .value(stat.title, point.value), width: .ratio(0.42))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .cornerRadius(3)
                }
            }
            .chartXScale(domain: (days.first ?? .now)...(Calendar.current.date(byAdding: .day, value: 1, to: days.last ?? .now) ?? .now))
            .chartXAxis {
                AxisMarks(values: days) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.07))
                    AxisValueLabel()
                }
            }
            .frame(height: 130)
            if points.isEmpty {
                Text("Nothing measured this week yet.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }
}
