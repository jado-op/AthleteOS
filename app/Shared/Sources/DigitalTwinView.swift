import SwiftUI

// The Digital Twin (docs/ACADEMY-PLAN.md §3): the athlete as an anatomical
// hologram — the muscle map's 100 × 200 body (every muscle its own shape,
// front and back) drawn as light, with the six pillars as gauges around it,
// each wired to the part of the body it belongs to. Everything it shows comes
// in through `TwinVisualState`, so a 3D model can replace the drawing later.

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

enum TwinFacing: String {
    case front, back
}

/// Everything the twin shows.
struct TwinVisualState: Equatable {
    var appearance: TwinAppearance
    var sportSlug: String?
    var snapshot: TwinSnapshot
    var mode: TwinMode = .idle
    /// Pillar gains to show on the gauges after a lesson.
    var gains: [TwinPillar: Int] = [:]
    /// Not born yet: a dim outline waiting to be created.
    var dormant = false
    /// Gauges around the twin (off for small previews).
    var showsGauges = true

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

/// The anatomy, parsed once into paths in the canonical 100 × 200 space.
@MainActor
enum TwinAnatomy {
    struct Muscle {
        let slug: String
        let path: Path
    }

    private static var muscleCache: [TwinFacing: [Muscle]] = [:]
    private static var detailCache: [TwinFacing: [Path]] = [:]
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

    static func muscles(_ facing: TwinFacing) -> [Muscle] {
        if let hit = muscleCache[facing] { return hit }
        let made = muscleMapPaths.keys.sorted().compactMap { key -> Muscle? in
            let parts = key.split(separator: ".")
            guard parts.count == 3, parts[1] == facing.rawValue, let d = muscleMapPaths[key] else { return nil }
            return Muscle(slug: String(parts[0]), path: SVGPathParser.path(from: d))
        }
        muscleCache[facing] = made
        return made
    }

    static func details(_ facing: TwinFacing) -> [Path] {
        if let hit = detailCache[facing] { return hit }
        let made = (facing == .front ? anatomyDetailPathsFront : anatomyDetailPathsBack).map { SVGPathParser.path(from: $0) }
        detailCache[facing] = made
        return made
    }
}

/// Where everything sits on a stage of a given size.
struct TwinLayout {
    let size: CGSize
    /// Canonical units → points.
    let scale: CGFloat
    let figure: CGAffineTransform
    /// Stage proportions are designed at 390 pt wide.
    let unit: CGFloat

    init(size: CGSize, build: Double) {
        self.size = size
        unit = size.width / 390
        scale = size.height * 0.86 / CGFloat(muscleMapCanonicalHeight)
        let x0 = size.width / 2 - 50 * scale * build
        figure = CGAffineTransform(a: scale * build, b: 0, c: 0, d: scale, tx: x0, ty: size.height * 0.044)
    }

    func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y).applying(figure) }

    var feet: CGPoint { CGPoint(x: size.width / 2, y: point(50, 200).y - 4) }
    var head: CGPoint { point(anatomyHead.cx, anatomyHead.cy) }

    /// The gauges: three down each side.
    func node(_ pillar: TwinPillar) -> CGPoint {
        let left = max(36, 48 * unit), right = size.width - left
        switch pillar {
        case .mind: return CGPoint(x: left, y: size.height * 0.14)
        case .sportIQ: return CGPoint(x: right, y: size.height * 0.14)
        case .recovery: return CGPoint(x: left, y: size.height * 0.40)
        case .fuel: return CGPoint(x: right, y: size.height * 0.40)
        case .body: return CGPoint(x: left, y: size.height * 0.66)
        case .legends: return CGPoint(x: right, y: size.height * 0.66)
        }
    }

    /// Where each gauge's line meets the body: the mind and vision at the
    /// head, recovery at the heart, fuel at the stomach, body at the thigh,
    /// legends on the platform the twin stands on.
    func anchor(_ pillar: TwinPillar) -> CGPoint {
        switch pillar {
        case .mind: point(anatomyHead.cx - 4, anatomyHead.cy - 2)
        case .sportIQ: point(anatomyHead.cx + 5, anatomyHead.cy - 3)
        case .recovery: point(44, 44)
        case .fuel: point(54, 68)
        case .body: point(41, 118)
        case .legends: CGPoint(x: feet.x + 70 * unit, y: feet.y + 6 * unit)
        }
    }
}

struct DigitalTwinView: View {
    let state: TwinVisualState
    var onTap: ((TwinTarget) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var facing: TwinFacing = .front
    @State private var turn: Double = 0
    @State private var sweep: CGFloat = 1.2
    /// The motion runs only while the twin is on screen: a twin in a tab
    /// that isn't showing must not keep the app busy (battery, and UI tests
    /// wait for the app to go idle).
    @State private var onScreen = false

    var body: some View {
        GeometryReader { proxy in
            let layout = TwinLayout(size: proxy.size, build: state.appearance.build.width)
            ZStack {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || !onScreen)) { timeline in
                    let time = reduceMotion || !onScreen ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    ZStack {
                        stage(layout, time: time)
                        figure(layout, time: time)
                            .rotation3DEffect(.degrees(turn), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                if let target = target(at: location, layout: layout) { onTap?(target) }
                            }
                    }
                }
                if state.showsGauges {
                    ForEach(TwinPillar.allCases) { pillar in
                        let point = layout.node(pillar)
                        TwinGauge(pillar: pillar, value: state.snapshot.score(pillar).total, gain: state.gains[pillar],
                                  dormant: state.dormant) { onTap?(.pillar(pillar)) }
                            .position(x: point.x, y: point.y + 9 * layout.unit)
                    }
                    facingToggle.position(x: proxy.size.width / 2, y: proxy.size.height - 12)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your digital twin")
        .onDisappear { onScreen = false }
        .onAppear {
            onScreen = true
            guard state.mode == .levelUp, !reduceMotion else { return }
            sweep = 1.2
            withAnimation(.easeInOut(duration: 1.6).delay(0.3)) { sweep = -0.2 }
        }
    }

    // MARK: Front / back

    private var facingToggle: some View {
        HStack(spacing: 2) {
            ForEach([TwinFacing.front, .back], id: \.self) { side in
                Text(side == .front ? "Front" : "Back")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(facing == side ? AppTheme.ink : AppTheme.secondaryText)
                    .frame(width: 46, height: 22)
                    .background(Capsule().fill(facing == side ? AppTheme.brand.opacity(0.45) : .clear))
            }
        }
        .padding(2)
        .glassCapsule()
        .contentShape(Capsule())
        .onTapGesture(perform: flip)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Showing the \(facing.rawValue). Turn the twin around.")
        .accessibilityAddTraits(.isButton)
    }

    /// Turns the twin around: a quarter turn out, the other side, a quarter turn in.
    private func flip() {
        let next: TwinFacing = facing == .front ? .back : .front
        guard !reduceMotion else { facing = next; return }
        withAnimation(.easeIn(duration: 0.18)) { turn = 90 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            facing = next
            turn = -90
            withAnimation(.easeOut(duration: 0.22)) { turn = 0 }
        }
    }

    // MARK: Stage: light, platform, legend rings, gauge wires

    private func stage(_ layout: TwinLayout, time: Double) -> some View {
        let fuel = state.level(.fuel)
        let traits = state.snapshot.traits.count
        let kit = Color(hex: state.appearance.kit)
        let dormant = state.dormant
        let gauges = state.showsGauges
        let wires = TwinPillar.allCases.map { (color: $0.color, node: layout.node($0), anchor: layout.anchor($0)) }
        return Canvas { context, size in
            let u = layout.unit
            let centre = CGPoint(x: size.width / 2, y: size.height * 0.46)
            // Energy aura (Fuel).
            let radius = size.height * 0.46
            context.fill(Path(ellipseIn: CGRect(x: centre.x - radius * 0.78, y: centre.y - radius, width: radius * 1.56, height: radius * 2)),
                         with: .radialGradient(Gradient(stops: [
                            .init(color: AppTheme.orange.opacity(dormant ? 0.02 : 0.05 + 0.25 * fuel), location: 0),
                            .init(color: AppTheme.brand.opacity(0.10 + 0.15 * fuel), location: 0.45),
                            .init(color: .clear, location: 1),
                         ]), center: centre, startRadius: 0, endRadius: radius))
            // A soft beam up from the platform.
            let feet = layout.feet
            var beam = Path()
            beam.move(to: CGPoint(x: feet.x - 75 * u, y: feet.y + 4))
            beam.addLine(to: CGPoint(x: feet.x - 45 * u, y: size.height * 0.08))
            beam.addLine(to: CGPoint(x: feet.x + 45 * u, y: size.height * 0.08))
            beam.addLine(to: CGPoint(x: feet.x + 75 * u, y: feet.y + 4))
            beam.closeSubpath()
            context.fill(beam, with: .linearGradient(Gradient(colors: [AppTheme.brand.opacity(0), AppTheme.brand.opacity(0.09)]),
                                                    startPoint: CGPoint(x: 0, y: size.height * 0.08), endPoint: CGPoint(x: 0, y: feet.y)))
            // The platform.
            func ring(_ rx: CGFloat, _ ry: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: feet.x - rx * u, y: feet.y - ry * u, width: rx * 2 * u, height: ry * 2 * u))
            }
            context.fill(ring(120, 20), with: .radialGradient(Gradient(colors: [AppTheme.brand.opacity(0.22), .clear]),
                                                             center: feet, startRadius: 0, endRadius: 120 * u))
            context.stroke(ring(104, 15), with: .color(AppTheme.brightRed.opacity(0.55)), lineWidth: 1)
            context.stroke(ring(84, 11), with: .color(AppTheme.brightRed.opacity(0.3)),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 4], dashPhase: CGFloat(time * 6)))
            context.stroke(ring(128, 19), with: .color(kit.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [40, 10], dashPhase: CGFloat(-time * 10)))
            // Legend traits orbit the platform.
            for index in 0..<min(traits, 4) {
                let i = CGFloat(index)
                context.stroke(ring(142 + i * 12, 23 + i * 2), with: .color(AppTheme.yellow.opacity(0.55 - 0.1 * Double(index))),
                               style: StrokeStyle(lineWidth: 1, dash: [10, 6], dashPhase: CGFloat(time * 8) * (index.isMultiple(of: 2) ? 1 : -1)))
            }
            // Each gauge wired to its place on the body.
            guard gauges else { return }
            for wire in wires {
                let edge = CGPoint(x: wire.node.x + (wire.node.x < size.width / 2 ? 27 : -27) * u, y: wire.node.y)
                var line = Path()
                line.move(to: edge)
                line.addLine(to: CGPoint(x: (edge.x + wire.anchor.x) / 2, y: edge.y))
                line.addLine(to: wire.anchor)
                context.stroke(line, with: .color(wire.color.opacity(dormant ? 0.15 : 0.45)), lineWidth: 0.8)
                context.fill(Path(ellipseIn: CGRect(x: wire.anchor.x - 2.4, y: wire.anchor.y - 2.4, width: 4.8, height: 4.8)),
                             with: .color(wire.color.opacity(dormant ? 0.3 : 1)))
                context.stroke(Path(ellipseIn: CGRect(x: wire.anchor.x - 6, y: wire.anchor.y - 6, width: 12, height: 12)),
                               with: .color(wire.color.opacity(0.5)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: The body

    private func figure(_ layout: TwinLayout, time: Double) -> some View {
        let muscles = TwinAnatomy.muscles(facing)
        let details = TwinAnatomy.details(facing)
        let outline = TwinAnatomy.outline
        let head = TwinAnatomy.head
        let glow = state.dormant ? [:] : AcademyContent.muscleGlow(state.snapshot.bodyAreas)
        let sport = Set(AcademyContent.areas(forSport: state.sportSlug).flatMap { AcademyContent.muscles(forArea: $0) })
        let look = state.appearance
        let mind = state.level(.mind), iq = state.level(.sportIQ)
        let dormant = state.dormant
        let levelUp = state.mode == .levelUp
        let sweep = sweep
        // A slow back-and-forth for the vision arc (still when motion is off).
        let drift = time == 0 ? 0 : sin(time * 2 * .pi / 5) * 12
        return Canvas { context, size in
            let t = layout.figure
            let s = layout.scale
            let body = outline.applying(t)
            let skull = head.applying(t)
            var whole = body
            whole.addPath(skull)
            let box = whole.boundingRect
            let lavender = Color(hex: "#C4B5FD"), pale = Color(hex: "#DDD6FE")
            if dormant { context.opacity = 0.55 }

            // Base: a faint body of light, tinted by the athlete's skin tone.
            context.fill(whole, with: .color(Color(hex: look.skin).opacity(0.10)))
            context.fill(whole, with: .linearGradient(Gradient(colors: [AppTheme.brightRed.opacity(0.16), AppTheme.crimson.opacity(0.04)]),
                                                     startPoint: CGPoint(x: box.midX, y: box.minY), endPoint: CGPoint(x: box.midX, y: box.maxY)))
            // Hair: the top of the head in the athlete's colour.
            context.drawLayer { layer in
                layer.clip(to: skull)
                let top = skull.boundingRect
                layer.fill(Path(CGRect(x: top.minX, y: top.minY, width: top.width, height: top.height * 0.36)),
                           with: .color(Color(hex: look.hair).opacity(0.45)))
            }

            // Every muscle as an outline; the sport's key muscles a little brighter.
            for muscle in muscles where glow[muscle.slug] == nil {
                let path = muscle.path.applying(t)
                let key = sport.contains(muscle.slug)
                context.fill(path, with: .color(AppTheme.brand.opacity(key ? 0.07 : 0.035)))
                context.stroke(path, with: .color(lavender.opacity(key ? 0.5 : 0.26)), lineWidth: 0.22 * s)
            }
            for detail in details {
                context.stroke(detail.applying(t), with: .color(lavender.opacity(0.18)), lineWidth: 0.18 * s)
            }

            // What the athlete has learned lights up, with a bloom.
            let lit = muscles.compactMap { muscle in glow[muscle.slug].map { (path: muscle.path.applying(t), level: $0) } }
            func drawLit(_ target: inout GraphicsContext) {
                for entry in lit {
                    let b = entry.path.boundingRect
                    target.fill(entry.path, with: .linearGradient(
                        Gradient(colors: [lavender.opacity(0.22 + 0.55 * entry.level), AppTheme.brand.opacity(0.22 + 0.55 * entry.level),
                                          Color(hex: "#5B21B6").opacity(0.22 + 0.55 * entry.level)]),
                        startPoint: CGPoint(x: b.minX, y: b.minY), endPoint: CGPoint(x: b.maxX, y: b.maxY)))
                    target.stroke(entry.path, with: .color(pale.opacity(0.45 + 0.45 * entry.level)), lineWidth: 0.25 * s)
                }
            }
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 3))
                drawLit(&layer)
            }
            drawLit(&context)

            // Hologram scan lines and the moving scan band, inside the body.
            context.drawLayer { layer in
                layer.clip(to: whole)
                var lines = Path()
                var y = box.minY
                for _ in 0..<400 where y < box.maxY {
                    lines.addRect(CGRect(x: box.minX, y: y, width: box.width, height: 1))
                    y += 3
                }
                layer.fill(lines, with: .color(lavender.opacity(0.10)))
                let cycle = 4.5
                let phase = CGFloat(time.truncatingRemainder(dividingBy: cycle) / cycle)
                layer.fill(Path(CGRect(x: box.minX, y: box.minY + phase * box.height, width: box.width, height: 18)),
                           with: .color(lavender.opacity(0.10)))
                if levelUp {
                    layer.fill(Path(CGRect(x: box.minX, y: box.minY + sweep * box.height - 30, width: box.width, height: 60)),
                               with: .linearGradient(Gradient(colors: [.clear, AppTheme.brightRed.opacity(0.6), .clear]),
                                                     startPoint: CGPoint(x: 0, y: box.minY + sweep * box.height - 30),
                                                     endPoint: CGPoint(x: 0, y: box.minY + sweep * box.height + 30)))
                }
            }

            // The rim of light.
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 3))
                layer.stroke(whole, with: .color(AppTheme.brightRed.opacity(0.9)), lineWidth: 1.2)
            }
            context.stroke(whole, with: .color(pale.opacity(0.85)), lineWidth: 0.8)

            // Mind: a glow around the head. Sport IQ: the vision arc above it.
            let centre = layout.head
            let k = layout.unit
            let glowRadius = CGFloat(20 + 16 * mind) * k * 1.4
            context.fill(Path(ellipseIn: CGRect(x: centre.x - glowRadius, y: centre.y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)),
                         with: .radialGradient(Gradient(colors: [AppTheme.purple.opacity(dormant ? 0.05 : 0.14 + 0.36 * mind), .clear]),
                                               center: centre, startRadius: 0, endRadius: glowRadius))
            let arcRadius = CGFloat(34 + 16 * iq) * k
            let span = 40 + 90 * iq
            var arc = Path()
            arc.addArc(center: centre, radius: arcRadius, startAngle: .degrees(-90 - span / 2 + drift),
                       endAngle: .degrees(-90 + span / 2 + drift), clockwise: false)
            context.stroke(arc, with: .color(AppTheme.green.opacity(dormant ? 0.1 : 0.25 + 0.5 * iq)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }

    // MARK: Taps

    /// The head opens Mind; a muscle opens its body area; the rest of the body opens Body.
    private func target(at location: CGPoint, layout: TwinLayout) -> TwinTarget? {
        let canonical = location.applying(layout.figure.inverted())
        if TwinAnatomy.head.contains(canonical) { return .pillar(.mind) }
        for muscle in TwinAnatomy.muscles(facing) where muscle.path.contains(canonical) {
            if let area = AcademyContent.area(ofMuscle: muscle.slug) { return .area(area) }
        }
        return TwinAnatomy.outline.contains(canonical) ? .pillar(.body) : nil
    }
}

/// One pillar's gauge: a ring filled to its score, the number inside, the name below.
struct TwinGauge: View {
    let pillar: TwinPillar
    let value: Int
    var gain: Int? = nil
    var dormant = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(pillar.color.opacity(dormant ? 0.04 : 0.16)).frame(width: 60, height: 60).blur(radius: 8)
                    Circle().fill(Color(red: 14 / 255, green: 14 / 255, blue: 18 / 255).opacity(0.85))
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: CGFloat(value) / CGFloat(TwinScoring.maximum))
                        .stroke(pillar.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(dormant ? "–" : "\(value)")
                        .font(.system(size: 17, weight: .bold).monospacedDigit())
                        .foregroundStyle(AppTheme.ink)
                }
                .frame(width: 42, height: 42)
                .overlay(alignment: .top) {
                    if let gain, gain > 0 {
                        Text("+\(gain)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.background)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(pillar.color))
                            .offset(y: -16)
                    }
                }
                Text(pillar.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(pillar.color)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pillar.title)
        .accessibilityValue(dormant ? "Not started" : "\(value) of 100")
        .accessibilityAddTraits(.isButton)
    }
}
