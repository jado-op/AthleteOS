import SwiftUI

// The Digital Twin (docs/ACADEMY-PLAN.md §3): the athlete's own figure as a
// hologram, showing what the Academy has built. Everything it shows comes in
// through `TwinVisualState`, so a real 3D model can replace the drawing later
// without touching the screens around it.

extension TwinPillar {
    /// Pillar accents: violet stays the brand light; Mind keeps its indigo.
    var color: Color {
        switch self {
        case .body: AppTheme.brightRed
        case .fuel: AppTheme.orange
        case .recovery: AppTheme.cyan
        case .mind: AppTheme.purple
        case .legends: AppTheme.yellow
        case .sportIQ: AppTheme.green
        }
    }
}

enum TwinMode: Equatable {
    case idle
    /// One bright pass after a lesson.
    case levelUp
}

/// Everything the twin shows.
struct TwinVisualState: Equatable {
    var appearance: TwinAppearance
    var sportSlug: String?
    var snapshot: TwinSnapshot
    var mode: TwinMode = .idle

    func level(_ pillar: TwinPillar) -> Double { Double(snapshot.score(pillar).total) / Double(TwinScoring.maximum) }
}

/// What a tap on the twin opens.
enum TwinTarget: Hashable, Identifiable {
    case pillar(TwinPillar)
    case area(String)

    var id: String {
        switch self {
        case .pillar(let pillar): "pillar.\(pillar.rawValue)"
        case .area(let area): "area.\(area)"
        }
    }
}

/// The standing figure the twin is drawn from, placed once.
@MainActor
enum TwinRig {
    static let patternSlug = "stand-breathe"
    /// Turned a little, so it reads as a body in space, not a cut-out.
    static let yaw = 28.0

    struct Figure {
        let playback: RigPlayback
        let skeleton: RigSkeleton
        let frame: CGRect
    }

    private static var cached: Figure?

    static func figure() -> Figure? {
        if let cached { return cached }
        guard let pattern = posePatternsBySlug[patternSlug] else { return nil }
        let playback = RigPlayback(pattern, view: yaw)
        let skeleton = playback.still(0)
        var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
        for shape in RigShapes.scene(skeleton, playback: playback, glow: [:], palette: RigPalette.forScheme(.dark), scheme: .dark)
        where shape.depth > -1e5 && !shape.isBall {
            for p in shape.points {
                minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
        }
        guard minX.isFinite, maxX > minX, maxY > minY else { return nil }
        let pad = 10.0
        let figure = Figure(playback: playback, skeleton: skeleton,
                            frame: CGRect(x: minX - pad, y: minY - pad, width: maxX - minX + pad * 2, height: maxY - minY + pad * 2))
        cached = figure
        return figure
    }

    /// The athlete's own colours on the rig.
    static func palette(_ look: TwinAppearance) -> RigPalette {
        var palette = RigPalette.forScheme(.dark)
        palette.skinNear = look.skin
        palette.skinFar = shade(look.skin, 0.78)
        palette.hair = look.hair
        palette.shirtNear = look.kit
        palette.shirtFar = shade(look.kit, 0.7)
        palette.shortsNear = look.kitSecondary
        palette.shortsFar = shade(look.kitSecondary, 0.7)
        palette.glow = "#A78BFA"
        return palette
    }

    /// A hex colour made darker (factor < 1).
    nonisolated static func shade(_ hex: String, _ factor: Double) -> String {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return hex }
        func part(_ shift: UInt32) -> Int { Int((Double((value >> shift) & 0xFF) * factor).rounded()) }
        return String(format: "#%02X%02X%02X", part(16), part(8), part(0))
    }
}

/// Where the figure sits in a view of a given size (the same framing
/// RigCanvas uses), with the build's width applied around the centre.
struct TwinGeometry {
    let transform: CGAffineTransform
    let scale: CGFloat
    let size: CGSize
    let width: Double

    init(frame: CGRect, size: CGSize, width: Double) {
        let scale = min(size.width / frame.width, size.height / frame.height)
        let offsetX = (size.width - frame.width * scale) / 2 - frame.minX * scale
        let offsetY = (size.height - frame.height * scale) / 2 - frame.minY * scale
        self.scale = scale
        self.size = size
        self.width = width
        let centreX = size.width / 2
        transform = CGAffineTransform(translationX: offsetX, y: offsetY).scaledBy(x: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: -centreX, y: 0))
            .concatenating(CGAffineTransform(scaleX: width, y: 1))
            .concatenating(CGAffineTransform(translationX: centreX, y: 0))
    }

    func point(_ p: V3) -> CGPoint { RigShapes.P(p).applying(transform) }
}

struct DigitalTwinView: View {
    let state: TwinVisualState
    var onTap: ((TwinTarget) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: CGFloat = 1.2

    var body: some View {
        GeometryReader { proxy in
            if let figure = TwinRig.figure() {
                let geometry = TwinGeometry(frame: figure.frame, size: proxy.size, width: state.appearance.build.width)
                TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
                    let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    scene(figure, geometry, time: time)
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    if let target = target(at: location, figure: figure, geometry: geometry) { onTap?(target) }
                }
            } else {
                Image(systemName: "figure.stand")
                    .font(.system(size: 140, weight: .ultraLight))
                    .foregroundStyle(AppTheme.brightRed.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your digital twin")
        .accessibilityValue(TwinPillar.allCases.map { "\($0.title) \(state.snapshot.score($0).total)" }.joined(separator: ", "))
        .onAppear {
            guard state.mode == .levelUp, !reduceMotion else { return }
            sweep = 1.2
            withAnimation(.easeInOut(duration: 1.6).delay(0.3)) { sweep = -0.2 }
        }
    }

    // MARK: Drawing

    private func scene(_ figure: TwinRig.Figure, _ geometry: TwinGeometry, time: Double) -> some View {
        let s = figure.skeleton
        let head = geometry.point(s.head)
        let chest = geometry.point(s.neckBase)
        let pelvis = geometry.point(s.pelvis)
        let feet = geometry.point((s.L.ankle + s.R.ankle) / 2)
        let height = max(feet.y - head.y, 1)
        let breathe = 1 + 0.006 * sin(time * 2 * .pi / 5)
        let fuel = state.level(.fuel), recovery = state.level(.recovery), mind = state.level(.mind), iq = state.level(.sportIQ)
        return ZStack {
            aura(centre: CGPoint(x: chest.x, y: (chest.y + pelvis.y) / 2), radius: height * 0.62, fuel: fuel, time: time)
            platform(at: feet, width: height * 0.62)
            legendRings(around: pelvis, height: height, time: time)
            figureCanvas(figure, geometry, recovery: recovery)
                .scaleEffect(x: 1, y: breathe, anchor: .bottom)
            headGlow(at: head, height: height, mind: mind)
            visionScan(at: head, height: height, iq: iq, time: time)
            scanLine(width: geometry.size.width, top: head.y - height * 0.08, height: height * 1.16, recovery: recovery, time: time)
            if state.mode == .levelUp { levelUpSweep(width: geometry.size.width, top: head.y - height * 0.1, height: height * 1.2) }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .overlay(alignment: .trailing) { battery(recovery).padding(.trailing, 6).offset(y: chest.y - geometry.size.height / 2 + height * 0.12) }
        .overlay(alignment: .bottomLeading) { egoMeter.padding(.leading, 4).padding(.bottom, 4) }
    }

    private func figureCanvas(_ figure: TwinRig.Figure, _ geometry: TwinGeometry, recovery: Double) -> some View {
        let palette = TwinRig.palette(state.appearance)
        let shapes = RigShapes.scene(figure.skeleton, playback: figure.playback, glow: state.snapshot.bodyAreas, palette: palette, scheme: .dark)
            .filter { $0.depth > -1e5 && !$0.isBall }
        let glow = Color(hex: palette.glow)
        let edge = AppTheme.brightRed.opacity(0.32 + 0.4 * recovery)
        let transform = geometry.transform
        let scale = geometry.scale
        return Canvas { context, _ in
            for shape in shapes where shape.points.count >= 2 {
                var path = Path()
                path.addLines(shape.points)
                path.closeSubpath()
                let placed = path.applying(transform)
                if let width = shape.stroke {
                    context.stroke(placed, with: .color(shape.color.opacity(shape.opacity * 0.7)), lineWidth: width * scale * 0.5)
                } else if shape.color == glow {
                    // The muscle glow: bright, with a soft bloom.
                    context.drawLayer { layer in
                        layer.addFilter(.blur(radius: 5))
                        layer.fill(placed, with: .color(glow.opacity(min(1, shape.opacity * 1.1))))
                    }
                    context.fill(placed, with: .color(glow.opacity(shape.opacity * 0.85)))
                } else {
                    // Hologram: the body faint, its edges lit.
                    context.fill(placed, with: .color(shape.color.opacity(shape.opacity * 0.42)))
                    context.stroke(placed, with: .color(edge), lineWidth: 0.7)
                }
            }
        }
    }

    private func aura(centre: CGPoint, radius: CGFloat, fuel: Double, time: Double) -> some View {
        let pulse = 1 + 0.03 * sin(time * 2 * .pi / 6)
        return Circle()
            .fill(RadialGradient(colors: [AppTheme.orange.opacity(0.06 + 0.30 * fuel), AppTheme.brand.opacity(0.10 + 0.18 * fuel), .clear],
                                 center: .center, startRadius: 0, endRadius: radius))
            .frame(width: radius * 2, height: radius * 2)
            .scaleEffect(pulse)
            .position(centre)
            .allowsHitTesting(false)
    }

    private func platform(at feet: CGPoint, width: CGFloat) -> some View {
        ZStack {
            Ellipse().fill(RadialGradient(colors: [AppTheme.brand.opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: width / 2))
            Ellipse().strokeBorder(LinearGradient(colors: [AppTheme.brightRed.opacity(0.7), AppTheme.brand.opacity(0.1)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .frame(width: width, height: width * 0.22)
        .position(x: feet.x, y: feet.y + 4)
        .allowsHitTesting(false)
    }

    private func legendRings(around pelvis: CGPoint, height: CGFloat, time: Double) -> some View {
        ForEach(Array(state.snapshot.traits.prefix(4).enumerated()), id: \.offset) { index, _ in
            let width = height * (0.62 + 0.12 * CGFloat(index))
            Ellipse()
                .stroke(AppTheme.yellow.opacity(0.55 - 0.08 * Double(index)),
                        style: StrokeStyle(lineWidth: 1.2, dash: [10, 6], dashPhase: CGFloat(time * 8) * (index.isMultiple(of: 2) ? 1 : -1)))
                .frame(width: width, height: width * 0.2)
                .position(x: pelvis.x, y: pelvis.y - height * (0.05 + 0.13 * CGFloat(index)))
                .allowsHitTesting(false)
        }
    }

    private func headGlow(at head: CGPoint, height: CGFloat, mind: Double) -> some View {
        let radius = height * (0.08 + 0.1 * mind)
        return Circle()
            .fill(RadialGradient(colors: [AppTheme.purple.opacity(0.18 + 0.5 * mind), .clear], center: .center, startRadius: 0, endRadius: radius))
            .frame(width: radius * 2, height: radius * 2)
            .position(head)
            .allowsHitTesting(false)
    }

    private func visionScan(at head: CGPoint, height: CGFloat, iq: Double, time: Double) -> some View {
        let radius = height * (0.13 + 0.09 * iq)
        let span = 30 + 90 * iq
        let centreAngle = -20 + 25 * sin(time * 2 * .pi / 4)
        return Path { path in
            path.addArc(center: head, radius: radius, startAngle: .degrees(centreAngle - span / 2),
                        endAngle: .degrees(centreAngle + span / 2), clockwise: false)
        }
        .stroke(AppTheme.green.opacity(0.18 + 0.55 * iq), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .allowsHitTesting(false)
    }

    private func scanLine(width: CGFloat, top: CGFloat, height: CGFloat, recovery: Double, time: Double) -> some View {
        let cycle = 4.5
        let phase = CGFloat(time.truncatingRemainder(dividingBy: cycle) / cycle)
        // A tired twin flickers a little; a recovered one scans clean.
        let flicker = recovery < 0.4 ? 0.04 * sin(time * 37) : 0
        return LinearGradient(colors: [.clear, AppTheme.brightRed.opacity(0.10 + flicker), .clear], startPoint: .top, endPoint: .bottom)
            .frame(width: width * 0.8, height: 26)
            .position(x: width / 2, y: top + phase * height)
            .allowsHitTesting(false)
    }

    private func levelUpSweep(width: CGFloat, top: CGFloat, height: CGFloat) -> some View {
        LinearGradient(colors: [.clear, AppTheme.brightRed.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
            .frame(width: width * 0.8, height: 60)
            .position(x: width / 2, y: top + sweep * height)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }

    private func battery(_ level: Double) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(AppTheme.cyan.opacity(0.6), lineWidth: 1)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(AppTheme.cyan.opacity(0.75))
                    .frame(height: max(2, 52 * level))
                    .padding(3)
            }
            .frame(width: 16, height: 58)
            Image(systemName: "bolt.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(AppTheme.cyan.opacity(0.8))
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?(.pillar(.recovery)) }
        .accessibilityHidden(true)
    }

    /// Confidence ↔ humility: a dot on a short track, balanced in the middle.
    private var egoMeter: some View {
        let balance = state.snapshot.egoBalance
        return VStack(alignment: .leading, spacing: 4) {
            ZStack {
                Capsule().fill(Color.white.opacity(0.10)).frame(width: 72, height: 3)
                Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1, height: 8)
                Circle().fill(AppTheme.purple).frame(width: 9, height: 9).offset(x: 32 * balance)
            }
            .frame(width: 76, height: 10)
            HStack(spacing: 0) {
                Text("Confidence")
                Spacer(minLength: 4)
                Text("Humility")
            }
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(AppTheme.mutedText)
            .frame(width: 76)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?(.pillar(.mind)) }
        .accessibilityHidden(true)
    }

    // MARK: Taps

    /// The body part under a tap: the nearest bone, if the tap is on the body.
    private func target(at location: CGPoint, figure: TwinRig.Figure, geometry: TwinGeometry) -> TwinTarget? {
        let s = figure.skeleton
        let head = geometry.point(s.head)
        let feet = geometry.point((s.L.ankle + s.R.ankle) / 2)
        let height = max(feet.y - head.y, 1)
        if hypot(location.x - head.x, location.y - head.y) < height * 0.09 { return .pillar(.mind) }
        let areas = AcademyContent.areas(forSport: state.sportSlug)
        let thigh = (areas.firstIndex(of: "thighBack") ?? 99) < (areas.firstIndex(of: "thighFront") ?? 99) ? "thighBack" : "thighFront"
        var best: (distance: CGFloat, area: String)?
        func consider(_ a: V3, _ b: V3, _ pick: (CGFloat) -> String) {
            let p = geometry.point(a), q = geometry.point(b)
            let (distance, t) = Self.distance(from: location, toSegment: p, q)
            if distance < (best?.distance ?? .infinity) { best = (distance, pick(t)) }
        }
        consider(s.neckBase, s.pelvis) { $0 < 0.45 ? "chest" : ($0 < 0.85 ? "abs" : "glutes") }
        for limb in [s.L, s.R] {
            consider(limb.shoulder, limb.elbow) { $0 < 0.3 ? "shoulderCap" : "upperArmFront" }
            consider(limb.elbow, limb.wrist) { _ in "forearm" }
            consider(limb.hip, limb.knee) { $0 < 0.15 ? "glutes" : thigh }
            consider(limb.knee, limb.ankle) { _ in "shinBack" }
            consider(limb.ankle, limb.toe) { _ in "foot" }
        }
        guard let best, best.distance < height * 0.07 else { return nil }
        return .area(best.area)
    }

    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> (CGFloat, CGFloat) {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return (hypot(p.x - a.x, p.y - a.y), 0) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        let x = a.x + t * dx, y = a.y + t * dy
        return (hypot(p.x - x, p.y - y), t)
    }
}
