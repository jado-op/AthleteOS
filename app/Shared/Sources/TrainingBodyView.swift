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
            BodyFigureCanvas(facing: facing, brightness: brightness, focus: focus?.drawableMuscles)
                .aspectRatio(muscleMapCanonicalWidth / muscleMapCanonicalHeight, contentMode: .fit)
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

/// The anatomy, parsed once into paths in the canonical 100 × 200 space.
@MainActor
enum BodyAnatomy {
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
