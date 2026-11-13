import SwiftUI

/// §9 job 2 — how an exercise looks: a 3D athlete in the movement's key
/// positions (a sit-up lying down, then sitting up), with the equipment in
/// hand, the bench or bar or bike it uses, and the muscles the item works
/// glowing on the body. The positions are pictures that cross-fade into each
/// other; the movement between them is never played.
///
/// The maths lives in RigEngine.swift and the drawing in RigShapes.swift;
/// both mirror content/src/rig3d.js and rigDraw.js, which the content tests
/// check for feet on the floor, joints in range and nothing through the floor.
public struct RigPoseView: View {
    private let pattern: PosePatternInfo
    private let muscles: [String: Double]
    private let animated: Bool
    @Environment(\.colorScheme) private var colorScheme
    /// Which of the stills is showing.
    @State private var shown = 0

    /// How long each position stays, fade included, and the fade itself.
    private static let stepSeconds = 1.5
    private static let fadeSeconds = 0.5

    public init(pattern: PosePatternInfo, muscles: [String: Double] = [:], animated: Bool = true) {
        self.pattern = pattern
        self.muscles = muscles
        self.animated = animated
    }

    public var body: some View {
        let playback = RigPlaybackCache.playback(for: pattern)
        let glow = RigMuscleRegion.glow(for: muscles)
        let palette = RigPalette.forScheme(colorScheme)
        let stills = animated ? playback.stills : [RigFraming.thumbIndex(for: playback)]
        let visible = shown < stills.count ? shown : 0
        ZStack {
            ForEach(Array(stills.enumerated()), id: \.offset) { entry in
                let skeleton = playback.still(entry.element)
                let frame = RigFraming.bounds(for: playback, keyframe: entry.element)
                Canvas { context, size in
                    RigCanvas.draw(RigShapes.scene(skeleton, playback: playback, glow: glow, palette: palette, scheme: colorScheme), in: &context,
                                   size: size, frame: frame, ground: playback.info.fixture?.kind != "water" ? Color(hex: palette.ground) : nil)
                }
                .opacity(entry.offset == visible ? 1 : 0)
            }
        }
        .clipped() // water and backdrops are drawn wider than the view
        .accessibilityHidden(true) // decorative alongside the item's own text
        .task(id: "\(pattern.id)-\(stills.count)") {
            shown = 0
            let count = stills.count
            guard count > 1 else { return }
            for _ in 0..<200_000 {
                do {
                    try await Task.sleep(nanoseconds: UInt64(Self.stepSeconds * 1_000_000_000))
                } catch {
                    return
                }
                withAnimation(.easeInOut(duration: Self.fadeSeconds)) { shown = (shown + 1) % count }
            }
        }
    }

}

/// A still frame for list thumbnails — the pattern's most telling keyframe.
struct RigStillView: View {
    let pattern: PosePatternInfo
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let playback = RigPlaybackCache.playback(for: pattern)
        let palette = RigPalette.forScheme(colorScheme)
        let thumb = RigFraming.thumbIndex(for: playback)
        let frame = RigFraming.bounds(for: playback, keyframe: thumb)
        let skeleton = playback.still(thumb)
        Canvas { context, size in
            RigCanvas.draw(RigShapes.scene(skeleton, playback: playback, glow: [:], palette: palette, scheme: colorScheme), in: &context,
                           size: size, frame: frame, ground: playback.info.fixture?.kind != "water" ? Color(hex: palette.ground) : nil)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

/// The camera box for each picture of a pattern (its stills and its
/// thumbnail). One box around all of them, so nothing jumps or zooms when one
/// fades into the next — except a movement that travels with nothing standing
/// on the ground (a long jump): there each picture is centred on the athlete,
/// at the same scale, so the body stays large.
@MainActor
enum RigFraming {
    private static var cache: [String: [Int: CGRect]] = [:]

    /// The keyframe list thumbnails show.
    static func thumbIndex(for playback: RigPlayback) -> Int {
        min(max(playback.info.thumb, 0), playback.info.keyframes.count - 1)
    }

    static func bounds(for playback: RigPlayback, keyframe: Int) -> CGRect {
        let all = boxes(for: playback)
        return all[keyframe] ?? all[thumbIndex(for: playback)] ?? CGRect(x: -50, y: -100, width: 100, height: 104)
    }

    private static func boxes(for playback: RigPlayback) -> [Int: CGRect] {
        if let hit = cache[playback.info.id] { return hit }
        var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
        let palette = RigPalette.forScheme(.light)
        var keyframes = playback.stills
        let thumb = thumbIndex(for: playback)
        if !keyframes.contains(thumb) { keyframes.append(thumb) }
        var spans: [Int: (low: Double, high: Double)] = [:]
        for keyframe in keyframes {
            var low = Double.infinity, high = -Double.infinity
            let s = playback.still(keyframe)
            for shape in RigShapes.scene(s, playback: playback, glow: [:], palette: palette) where shape.depth > -1e5 && !shape.isBall {
                for p in shape.points {
                    low = min(low, p.x); high = max(high, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y)
                }
            }
            spans[keyframe] = (low, high)
            minX = min(minX, low); maxX = max(maxX, high)
        }
        let pad = 4.0
        let top = minY - pad, height = max(maxY, 2) - minY + pad * 2
        let widest = spans.values.map { $0.high - $0.low }.max() ?? 0
        let centres = spans.values.map { ($0.low + $0.high) / 2 }
        let drift = (centres.max() ?? 0) - (centres.min() ?? 0)
        let travels = playback.info.fixture == nil && playback.info.cast == nil && drift > widest * 0.5
        var boxes: [Int: CGRect] = [:]
        for (keyframe, span) in spans {
            boxes[keyframe] = travels
                ? CGRect(x: (span.low + span.high) / 2 - widest / 2 - pad, y: top, width: widest + pad * 2, height: height)
                : CGRect(x: minX - pad, y: top, width: maxX - minX + pad * 2, height: height)
        }
        cache[playback.info.id] = boxes
        return boxes
    }
}

enum RigCanvas {
    static func draw(_ shapes: [RigShape], in context: inout GraphicsContext, size: CGSize, frame: CGRect, ground: Color?) {
        let scale = min(size.width / frame.width, size.height / frame.height)
        let offsetX = (size.width - frame.width * scale) / 2 - frame.minX * scale
        let offsetY = (size.height - frame.height * scale) / 2 - frame.minY * scale
        let transform = CGAffineTransform(translationX: offsetX, y: offsetY).scaledBy(x: scale, y: scale)
        if let ground {
            var line = Path()
            line.move(to: CGPoint(x: frame.minX, y: 0))
            line.addLine(to: CGPoint(x: frame.maxX, y: 0))
            context.stroke(line.applying(transform), with: .color(ground), lineWidth: 1.2)
        }
        for shape in shapes where shape.points.count >= 2 {
            var path = Path()
            path.addLines(shape.points)
            path.closeSubpath()
            let transformed = path.applying(transform)
            if let width = shape.stroke {
                context.stroke(transformed, with: .color(shape.color.opacity(shape.opacity)), lineWidth: width * scale * 0.5)
            } else {
                context.fill(transformed, with: .color(shape.color.opacity(shape.opacity)))
            }
        }
    }
}

/// Which body region a muscle glows on.
enum RigMuscleRegion: String {
    case thighFront, thighBack, thigh, shinFront, shinBack, chest, abs, upperBack, lowerBack, glutes
    case shoulderCap, upperArmFront, upperArmBack, forearm, neck, foot

    static func region(for muscleRegion: MuscleRegion, slug: String) -> RigMuscleRegion {
        switch slug {
        case "biceps-brachii", "brachialis": return .upperArmFront
        case "triceps-brachii": return .upperArmBack
        case "tibialis-anterior", "peroneals": return .shinFront
        case "gastrocnemius", "soleus": return .shinBack
        case "pectoralis-major", "pectoralis-minor", "serratus-anterior": return .chest
        case "iliopsoas", "tensor-fasciae-latae", "sartorius": return .thighFront
        case "adductors": return .thigh
        default: break
        }
        switch muscleRegion {
        case .neck: return .neck
        case .shoulder: return .shoulderCap
        case .upperBack: return .upperBack
        case .chest: return .chest
        case .lowerBack: return .lowerBack
        case .arm: return .upperArmFront
        case .forearm: return .forearm
        case .trunk: return .abs
        case .hip: return .glutes
        case .quadriceps: return .thighFront
        case .hamstrings: return .thighBack
        case .calf: return .shinBack
        case .foot: return .foot
        }
    }

    /// Region key → strongest role opacity for an item's muscles.
    static func glow(for muscles: [String: Double]) -> [String: Double] {
        var out: [String: Double] = [:]
        for (slug, weight) in muscles {
            guard let info = musclesBySlug[slug] else { continue }
            let key = region(for: info.region, slug: slug).rawValue
            out[key] = max(out[key] ?? 0, MuscleRole(weight: weight).opacity)
        }
        return out
    }
}

#Preview("Back squat") {
    if let pattern = posePatternsBySlug["back-squat"] {
        RigPoseView(pattern: pattern, muscles: ["rectus-femoris": 1, "gluteus-maximus": 1])
            .frame(height: 280)
            .padding()
    }
}

#Preview("Slap shot") {
    if let pattern = posePatternsBySlug["hockey-slap-shot"] {
        RigPoseView(pattern: pattern).frame(height: 280).padding()
    }
}
