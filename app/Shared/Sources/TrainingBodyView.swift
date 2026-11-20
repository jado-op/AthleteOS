import SwiftUI

/// The athlete's body, front and back, with every muscle lit in the V8
/// training ember by how much it has been trained (`MuscleTraining.Report.brightness`):
/// the most trained muscle is solid, less trained ones fainter, untrained
/// ones only a hairline outline. The anatomy is the muscle map's (every muscle
/// its own shape); the look is the old twin hologram, quietened for the
/// "space" design — hairlines, no glow, no motion.
struct TrainingBodyView: View {
    /// Drawable muscle slug → 0…1.
    let brightness: [String: Double]
    /// One group in focus: its muscles lit, the rest dimmed.
    var focus: MuscleGroup? = nil
    /// Small labels under each figure.
    var showsLabels = true

    /// One side only (the twin's week view turns the body around).
    var facing: BodyAnatomy.Facing? = nil
    /// The twin's heat body: drawable muscle slug → how hard it worked this
    /// week; every other muscle drawn rested. Replaces `brightness` when set.
    var heat: [String: WorkoutTagging.Band]? = nil
    /// Tapping a muscle (its drawable slug).
    var onTapMuscle: ((String) -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let facing {
                figure(facing, label: facing == .front ? "Front" : "Back")
            } else {
                figure(.front, label: "Front")
                figure(.back, label: "Back")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func figure(_ facing: BodyAnatomy.Facing, label: String) -> some View {
        VStack(spacing: 6) {
            BodyFigureCanvas(facing: facing, brightness: brightness, focus: focus?.drawableMuscles, heat: heat)
                .aspectRatio(muscleMapCanonicalWidth / muscleMapCanonicalHeight, contentMode: .fit)
                .overlay {
                    if let onTapMuscle {
                        GeometryReader { proxy in
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture(coordinateSpace: .local) { location in
                                    if let slug = BodyAnatomy.muscle(at: location, in: proxy.size, facing: facing) { onTapMuscle(slug) }
                                }
                        }
                    }
                }
            if showsLabels {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedText)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var accessibilityText: String {
        let lit = brightness.filter { $0.value > 0 }
        guard !lit.isEmpty else { return "Body map: nothing trained yet" }
        let groups = MuscleGroup.allCases.filter { group in group.drawableMuscles.contains { (lit[$0] ?? 0) >= 0.5 } }
        return groups.isEmpty ? "Body map" : "Body map. Most trained: " + groups.map(\.name).joined(separator: ", ")
    }
}

/// One side of the body.
private struct BodyFigureCanvas: View {
    let facing: BodyAnatomy.Facing
    let brightness: [String: Double]
    let focus: Set<String>?
    var heat: [String: WorkoutTagging.Band]? = nil

    var body: some View {
        let muscles = BodyAnatomy.muscles(facing)
        let details = BodyAnatomy.details(facing)
        let outline = BodyAnatomy.outline
        let head = BodyAnatomy.head
        // V8: trained muscles glow in the training (ember) colour.
        let ember = AuraTone.training.mark
        Canvas { context, size in
            let scale = min(size.width / muscleMapCanonicalWidth, size.height / muscleMapCanonicalHeight)
            let x0 = (size.width - muscleMapCanonicalWidth * scale) / 2
            let y0 = (size.height - muscleMapCanonicalHeight * scale) / 2
            let t = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: x0, ty: y0)
            let lavender = Color(hex: "#FFD9C2")
            var whole = outline.applying(t)
            whole.addPath(head.applying(t))

            // The heat body: every muscle filled on one warm scale that only
            // gets brighter with effort (rested graphite → deep ember → ember →
            // bright peach), hairline seams between them.
            if let heat {
                context.fill(whole, with: .color(HeatScale.body))
                for muscle in muscles {
                    let path = muscle.path.applying(t)
                    let inFocus = focus.map { $0.contains(muscle.slug) } ?? true
                    let band = heat[muscle.slug]
                    context.fill(path, with: .color(HeatScale.color(band).opacity(inFocus ? 1 : 0.28)))
                    context.stroke(path, with: .color(Color.black.opacity(0.55)), lineWidth: 0.22 * scale)
                    if inFocus, focus != nil {
                        context.stroke(path, with: .color(Color.white.opacity(0.9)), lineWidth: 0.35 * scale)
                    }
                }
                context.stroke(whole, with: .color(Color.white.opacity(0.22)), lineWidth: 0.25 * scale)
                return
            }

            // A faint body of light.
            context.fill(whole, with: .color(ember.opacity(0.05)))

            // Every muscle: a hairline; trained ones filled by how much.
            for muscle in muscles {
                let path = muscle.path.applying(t)
                let level = brightness[muscle.slug] ?? 0
                let inFocus = focus.map { $0.contains(muscle.slug) } ?? true
                if level > 0 {
                    // 0.18 … 0.95: the least trained muscle still reads as trained.
                    let alpha = (0.18 + 0.77 * level) * (inFocus ? 1 : 0.22)
                    context.fill(path, with: .color(ember.opacity(alpha)))
                    context.stroke(path, with: .color(lavender.opacity(inFocus ? 0.2 + 0.35 * level : 0.08)), lineWidth: 0.2 * scale)
                } else {
                    // Untrained: an outline, a little brighter when it is the group in focus.
                    let strong = focus != nil && inFocus
                    context.stroke(path, with: .color(lavender.opacity(strong ? 0.6 : 0.09)),
                                   style: StrokeStyle(lineWidth: (strong ? 0.35 : 0.2) * scale, dash: strong ? [1.2 * scale, 0.9 * scale] : []))
                }
            }
            // Anatomy detail lines only where the eye is meant to look (a group in focus).
            if focus != nil {
                for detail in details {
                    context.stroke(detail.applying(t), with: .color(lavender.opacity(0.08)), lineWidth: 0.16 * scale)
                }
            }
            // The silhouette's hairline.
            context.stroke(whole, with: .color(lavender.opacity(0.4)), lineWidth: 0.3 * scale)
        }
    }
}

/// The twin's heat scale (owner, 2026-11-20: "how hard you worked each
/// muscle group by colour"). One hue whose lightness rises with effort, as
/// sequential data should be drawn: readable for colour-blind athletes and in
/// grey, never a rainbow (docs/TWIN-WEEK-DESIGN.md).
enum HeatScale {
    static let body = Color(rgb: 0x101013)
    static let rested = Color(rgb: 0x2A2A30)

    static func color(_ band: WorkoutTagging.Band?) -> Color {
        switch band {
        case nil: rested
        case .light?: Color(rgb: 0x7C2D12)
        case .solid?: Color(rgb: 0xEA6A1F)
        case .veryHard?: Color(rgb: 0xFFC08A)
        }
    }

    static func word(_ band: WorkoutTagging.Band?) -> String {
        band.map(\.title) ?? "Rested"
    }
}

/// The anatomy, parsed once into paths in the canonical 100 × 200 space.
@MainActor
enum BodyAnatomy {
    /// The drawable muscle under a point of a figure drawn at `size`.
    static func muscle(at point: CGPoint, in size: CGSize, facing: Facing) -> String? {
        let scale = min(size.width / muscleMapCanonicalWidth, size.height / muscleMapCanonicalHeight)
        guard scale > 0 else { return nil }
        let x0 = (size.width - muscleMapCanonicalWidth * scale) / 2
        let y0 = (size.height - muscleMapCanonicalHeight * scale) / 2
        let canonical = CGPoint(x: (point.x - x0) / scale, y: (point.y - y0) / scale)
        if let hit = muscles(facing).last(where: { $0.path.contains(canonical) }) { return hit.slug }
        // A near miss on a thin muscle: the closest one within a few units.
        let near = muscles(facing).map { muscle -> (String, CGFloat) in
            let box = muscle.path.boundingRect
            let dx = max(box.minX - canonical.x, 0, canonical.x - box.maxX)
            let dy = max(box.minY - canonical.y, 0, canonical.y - box.maxY)
            return (muscle.slug, (dx * dx + dy * dy).squareRoot())
        }.min { $0.1 < $1.1 }
        return near.flatMap { $0.1 < 3 ? $0.0 : nil }
    }

    enum Facing: String { case front, back }

    struct Muscle {
        let slug: String
        let path: Path
    }

    private static var muscleCache: [Facing: [Muscle]] = [:]
    private static var detailCache: [Facing: [Path]] = [:]
    private static var outlineCache: Path?

    static var outline: Path {
        if let outlineCache { return outlineCache }
        let path = SVGPathParser.path(from: anatomyOutlinePath)
        outlineCache = path
        return path
    }

    static var head: Path {
        Path(ellipseIn: CGRect(x: anatomyHead.cx - anatomyHead.rx, y: anatomyHead.cy - anatomyHead.ry,
                               width: anatomyHead.rx * 2, height: anatomyHead.ry * 2))
    }

    static func muscles(_ facing: Facing) -> [Muscle] {
        if let hit = muscleCache[facing] { return hit }
        let made = muscleMapPaths.keys.sorted().compactMap { key -> Muscle? in
            let parts = key.split(separator: ".")
            guard parts.count == 3, parts[1] == facing.rawValue, let d = muscleMapPaths[key] else { return nil }
            return Muscle(slug: String(parts[0]), path: SVGPathParser.path(from: d))
        }
        muscleCache[facing] = made
        return made
    }

    static func details(_ facing: Facing) -> [Path] {
        if let hit = detailCache[facing] { return hit }
        let made = (facing == .front ? anatomyDetailPathsFront : anatomyDetailPathsBack).map { SVGPathParser.path(from: $0) }
        detailCache[facing] = made
        return made
    }
}
