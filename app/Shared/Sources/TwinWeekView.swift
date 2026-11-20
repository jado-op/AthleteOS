import Charts
import SwiftUI

/// The twin page's way in: the body, faintly lit, and one line about the week.
struct TwinWeekCard: View {
    let brightness: [String: Double]
    let sentence: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your last 7 days")
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.5)
                        .foregroundStyle(.white)
                    Text(sentence)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                    Label("Open your twin", systemImage: "hand.tap.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.white, in: Capsule())
                        .padding(.top, 6)
                }
                Spacer(minLength: 0)
                TrainingBodyView(brightness: brightness, showsLabels: false, facing: .front)
                    .frame(width: 92, height: 172)
                    .shadow(color: AuraTone.training.mark.opacity(0.5), radius: 18)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AuraBackground(.mind, focus: UnitPoint(x: 0.85, y: 0.45), radius: 230))
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Shows your body and your week's numbers")
    }
}

/// "Your last 7 days" (owner, 2026-11-20): the body in the middle, lit by
/// the week's training, the week's numbers from Apple Health floating
/// around it, each tied by a line to the part of the body it belongs to.
/// Tap a number for its seven days; tap the body to turn it around.
struct TwinWeekView: View {
    let brightness: [String: Double]
    let sentence: String
    let readyLine: String?
    @ObservedObject var health: HealthInsightsViewModel
    let training: [TwinWeek.Training]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var facing: BodyAnatomy.Facing = .front
    @State private var spin: Double = 0
    @State private var selected: String?
    @State private var appeared = false

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
            .frame(height: 540)
            footer(stats)
        }
        .background {
            ZStack {
                AppTheme.background
                RadialGradient(colors: [AuraTone.mind.mark.opacity(0.28), AuraTone.training.mark.opacity(0.10), .clear],
                               center: UnitPoint(x: 0.5, y: 0.42), startRadius: 10, endRadius: 360)
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { appeared = true }
        }
        .task { await health.load() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            CircleIconButton(systemImage: "xmark", accessibilityLabel: "Close") { dismiss() }
            VStack(alignment: .leading, spacing: 2) {
                Text("Your last 7 days")
                    .font(.system(size: 26, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(AppTheme.ink)
                Text(range)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: The body and its numbers

    private func stage(_ stats: [TwinWeek.Stat], size: CGSize) -> some View {
        let columns = TwinWeek.columns(stats)
        let figureWidth = min(size.width * 0.36, size.height * 0.48)
        let figureHeight = figureWidth * muscleMapCanonicalHeight / muscleMapCanonicalWidth
        let figureOrigin = CGPoint(x: (size.width - figureWidth) / 2, y: (size.height - figureHeight) / 2)
        let bubbleWidth = (size.width - figureWidth) / 2 - 12
        let slots: [Double] = [0.14, 0.47, 0.80]

        return TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let floating = Self.place(columns, size: size, bubbleWidth: bubbleWidth, slots: slots, time: t)
            ZStack {
                // Lines from each number to its place on the body.
                Canvas { canvas, _ in
                    for entry in floating {
                        let start = CGPoint(x: entry.center.x + (entry.left ? bubbleWidth / 2 : -bubbleWidth / 2), y: entry.center.y)
                        let anchor = anchorPoint(entry.stat.anchor, left: entry.left, origin: figureOrigin,
                                                 width: figureWidth, height: figureHeight)
                        var path = Path()
                        path.move(to: start)
                        path.addQuadCurve(to: anchor, control: CGPoint(x: (start.x + anchor.x) / 2, y: start.y))
                        let tint = color(for: entry.stat).opacity(selected == nil || selected == entry.stat.id ? 0.7 : 0.18)
                        canvas.stroke(path, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.12), tint]),
                                                                  startPoint: start, endPoint: anchor),
                                      style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [3, 4]))
                        canvas.fill(Path(ellipseIn: CGRect(x: anchor.x - 3.5, y: anchor.y - 3.5, width: 7, height: 7)), with: .color(tint))
                    }
                }
                .opacity(appeared ? 1 : 0)
                .allowsHitTesting(false)

                Button {
                    // Turn away, swap sides out of sight, turn back in.
                    withAnimation(.easeIn(duration: 0.22)) { spin = 90 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                        facing = facing == .front ? .back : .front
                        spin = -90
                        withAnimation(.easeOut(duration: 0.3)) { spin = 0 }
                    }
                } label: {
                    TrainingBodyView(brightness: brightness, showsLabels: false, facing: facing)
                        .frame(width: figureWidth, height: figureHeight)
                        .rotation3DEffect(.degrees(spin), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                        .shadow(color: AuraTone.training.mark.opacity(0.35), radius: 24)
                }
                .buttonStyle(.plain)
                .position(x: size.width / 2, y: size.height / 2)
                .scaleEffect(appeared ? 1 : 0.9)
                .opacity(appeared ? 1 : 0)
                .accessibilityLabel(facing == .front ? "Your body from the front. Tap to turn around." : "Your body from the back. Tap to turn around.")

                ForEach(Array(floating.enumerated()), id: \.offset) { index, entry in
                    bubble(entry.stat, width: bubbleWidth)
                        .position(entry.center)
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared ? 1 : 0.6)
                        .animation(.spring(response: 0.55, dampingFraction: 0.75).delay(0.15 + Double(index) * 0.07), value: appeared)
                }
            }
        }
    }

    private struct Placed {
        let stat: TwinWeek.Stat
        let center: CGPoint
        let left: Bool
    }

    /// Each bubble's spot (three slots a side), drifting gently with time.
    private static func place(_ columns: (left: [TwinWeek.Stat], right: [TwinWeek.Stat]), size: CGSize, bubbleWidth: CGFloat,
                              slots: [Double], time: Double) -> [Placed] {
        var result: [Placed] = []
        for (index, stat) in columns.left.prefix(3).enumerated() {
            result.append(Placed(stat: stat, center: CGPoint(x: 8 + bubbleWidth / 2, y: size.height * slots[index]), left: true))
        }
        for (index, stat) in columns.right.prefix(3).enumerated() {
            result.append(Placed(stat: stat, center: CGPoint(x: size.width - 8 - bubbleWidth / 2, y: size.height * slots[index]), left: false))
        }
        return result.enumerated().map { index, entry in
            let phase = Double(index)
            let dx = CGFloat(cos(time * 0.55 + phase * 2.1)) * 3
            let dy = CGFloat(sin(time * 0.8 + phase * 1.3)) * 6
            return Placed(stat: entry.stat, center: CGPoint(x: entry.center.x + dx, y: entry.center.y + dy), left: entry.left)
        }
    }

    /// Where a line meets the body (fractions of the front figure).
    private func anchorPoint(_ anchor: TwinWeek.Anchor, left: Bool, origin: CGPoint, width: CGFloat, height: CGFloat) -> CGPoint {
        let x: Double
        switch anchor {
        case .arms: x = left ? 0.2 : 0.8
        case .legs: x = left ? 0.4 : 0.6
        default: x = left ? 0.46 : 0.54
        }
        return CGPoint(x: origin.x + width * x, y: origin.y + height * anchor.height)
    }

    private func color(for stat: TwinWeek.Stat) -> Color {
        switch stat.anchor {
        case .head: AuraTone.mind.mark
        case .chest: AuraTone.body.mark
        case .arms, .core: AuraTone.training.mark
        case .legs: AuraTone.game.mark
        }
    }

    private func bubble(_ stat: TwinWeek.Stat, width: CGFloat) -> some View {
        let isSelected = selected == stat.id
        let tint = color(for: stat)
        return Button {
            withAnimation(.snappy(duration: 0.25)) { selected = isSelected ? nil : stat.id }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Label(stat.title, systemImage: stat.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(stat.value)
                        .font(.system(size: 26, weight: .light).monospacedDigit())
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(stat.unit)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if let change = stat.change {
                    Text(change)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(width: width, alignment: .leading)
            .background(isSelected ? tint.opacity(0.2) : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? tint : Color.white.opacity(0.14), lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the seven days")
    }

    // MARK: Below the body

    @ViewBuilder private func footer(_ stats: [TwinWeek.Stat]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let stat = stats.first(where: { $0.id == selected }) {
                    chart(stat)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    Text(sentence)
                        .font(.system(size: 20, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let readyLine {
                        Text(readyLine)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Tap a number for its seven days. Tap your body to turn it around.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedText)
                }
                if health.phase == .empty {
                    Button { Task { await health.connect() } } label: {
                        Label("Add sleep, heart and steps from Apple Health", systemImage: "heart.text.square")
                    }
                    .buttonStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private func chart(_ stat: TwinWeek.Stat) -> some View {
        let days = TwinWeek.days(now: .now)
        let points = zip(days, stat.days).compactMap { day, value in value.map { (day: day, value: $0) } }
        let tint = color(for: stat)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(stat.title, systemImage: stat.symbol)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Text(stat.change ?? "")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Chart {
                ForEach(points, id: \.day) { point in
                    BarMark(x: .value("Day", point.day, unit: .day), y: .value(stat.title, point.value), width: .ratio(0.55))
                        .foregroundStyle(tint.gradient)
                        .cornerRadius(5)
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
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
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
        .padding(16)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
