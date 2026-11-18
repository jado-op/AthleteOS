import SwiftUI
#if os(iOS)
import UIKit
#endif

/// AthleteOS V5: a cinematic performance environment — near-black space,
/// violet light behind frosted glass, oversized type, precise data. Violet
/// behaves like light (glows, reflections, selected marks), not like paint.
/// Always dark (the app forces the dark appearance).
public enum AppTheme {
    public static let background = Color(rgb: 0x050608)
    public static let backgroundSecondary = Color(rgb: 0x080A0D)
    /// A glass surface's tint (the blur comes from `glassSurface`).
    public static let card = Color(red: 18 / 255, green: 18 / 255, blue: 22 / 255).opacity(0.45)
    /// Unselected chips/options, ring tracks, thumbnail wells: a whisper of white.
    public static let fill = Color.white.opacity(0.08)
    /// Primary text.
    public static let ink = Color.white
    /// Light surfaces and marks on dark: "starlight" (V7), the same plate as the
    /// primary button and every selected chip (kept opaque: it's also used as a tint).
    public static let accent = Color(rgb: 0xEEEAFE)
    public static let starlight = Color(rgb: 0xEEEAFE)
    /// Text and glyphs drawn on `accent`.
    public static let onAccent = Color(rgb: 0x050608)
    public static let secondaryText = Color.white.opacity(0.58)
    public static let mutedText = Color.white.opacity(0.34)
    /// Glass borders and dividers.
    public static let hairline = Color.white.opacity(0.08)

    // The signature violet, as light (the names are from the red era).
    public static let brand = Color(rgb: 0x8B5CF6)
    public static let brightRed = Color(rgb: 0xA78BFA)
    public static let crimson = Color(rgb: 0x6D28D9)
    public static let atmosphere = Color(rgb: 0x1E1238)
    /// The second accent (rings, highlights): a soft lavender.
    public static let coral = Color(hex: "#C4B5FD")
    public static let orange = Color(hex: "#FF8A3D")
    public static let yellow = Color(hex: "#FACC15")
    public static let cyan = Color(hex: "#22D3EE")
    /// Was the old cobalt blue; a light grey mark on the dark canvas.
    public static let blue = Color(rgb: 0xE5E5E5)
    /// The one real blue — water, calm breathing, a Campus unit. Never a background.
    public static let water = Color(hex: "#1CB0F6")
    public static let waterDeep = Color(hex: "#1899D6")
    /// A solid dark surface with white on it.
    public static let solid = Color(rgb: 0x1A1B1F)
    /// Mind, sleep and reflection: indigo, so it never reads as the brand violet.
    public static let purple = Color(hex: "#818CF8")
    public static let green = Color(hex: "#22C55E")
    public static let amber = Color(hex: "#F59E0B")
    /// Gym in the activity colours, and the brand mark on data.
    public static let red = Color(hex: "#8B5CF6")
    /// Real warnings only: pain, head injury, emergency, stop.
    public static let danger = Color(hex: "#EF4444")

    /// Glass panels are rounder; controls stay compact.
    public static let cardCornerRadius: CGFloat = 24
    public static let controlCornerRadius: CGFloat = 14

    public static func color(for band: ReadinessBand?) -> Color {
        switch band {
        case .green: green
        case .amber: amber
        case .red: red
        case nil: secondaryText
        }
    }
}

extension Color {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
        #else
        Color(rgb: dark)
        #endif
    }

    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

#if os(iOS)
extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif

// MARK: - Surfaces

/// How much light a screen gets: the main screens (Home, Campus, Workout,
/// Progress, Me) glow; functional screens stay calm.
public enum Atmosphere: Sendable {
    case subtle, hero

    var strength: Double { self == .hero ? 1 : 0.45 }
}

/// Deep space (owner, 2026-11-18): a quiet, real starfield on near-black —
/// most stars faint, a few bright, a handful faintly blue or warm — and two
/// very soft nebulae. The sky follows the time of day (`SkyPalette`): plum
/// and rose at dawn, deep blue by day with the stars dimmed, violet and a warm
/// edge at dusk, near-black at night. Always dark. No sport lines behind content.
public struct AppBackground: View {
    let atmosphere: Atmosphere

    public init(_ atmosphere: Atmosphere = .subtle, sportSlug: String? = nil) {
        self.atmosphere = atmosphere
    }

    public var body: some View {
        TimelineView(.everyMinute) { context in
            sky(SkyPalette.at(context.date))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func sky(_ palette: SkyPalette) -> some View {
        let k = atmosphere.strength
        let stars = Starfield.stars
        return Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                Gradient(colors: [palette.top.color, palette.bottom.color]),
                center: CGPoint(x: size.width / 2, y: size.height * 0.2), startRadius: 0, endRadius: max(size.width, size.height) * 0.95))
            // Nebulae: one high on the right, one low on the left.
            for (x, y, r, tone, alpha) in [(0.88, 0.05, 0.62, palette.nebulaHigh, palette.nebulaHighAlpha * k),
                                          (0.08, 0.72, 0.7, palette.nebulaLow, palette.nebulaLowAlpha * k)] {
                let centre = CGPoint(x: size.width * x, y: size.height * y)
                let radius = size.width * r
                context.fill(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)),
                             with: .radialGradient(Gradient(colors: [tone.color.opacity(alpha), .clear]), center: centre, startRadius: 0, endRadius: radius))
            }
            // Stars, scattered over a fixed 400 × 900 tile repeated down long screens.
            var tileY: CGFloat = 0
            for _ in 0..<12 where tileY < size.height {
                for star in stars {
                    let x = star.x * size.width, y = tileY + star.y * 900
                    guard y < size.height else { continue }
                    let rect = CGRect(x: x - star.size / 2, y: y - star.size / 2, width: star.size, height: star.size)
                    context.fill(Path(ellipseIn: rect), with: .color(star.color.opacity(star.alpha * palette.stars)))
                    if star.size > 1.4 {
                        context.fill(Path(ellipseIn: rect.insetBy(dx: -2.5, dy: -2.5)), with: .color(Color(rgb: 0xC8BEFF).opacity(0.07 * palette.stars)))
                    }
                }
                tileY += 900
            }
        }
    }
}

/// The sky's colours at an hour of the day, blended between anchors.
public struct SkyPalette: Equatable, Sendable {
    public struct Tone: Equatable, Sendable {
        var r: Double, g: Double, b: Double

        init(_ hex: UInt32) {
            r = Double((hex >> 16) & 0xFF) / 255
            g = Double((hex >> 8) & 0xFF) / 255
            b = Double(hex & 0xFF) / 255
        }

        init(r: Double, g: Double, b: Double) {
            self.r = r
            self.g = g
            self.b = b
        }

        var color: Color { Color(red: r, green: g, blue: b) }

        func mixed(_ other: Tone, _ t: Double) -> Tone {
            Tone(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
        }
    }

    var top: Tone
    var bottom: Tone
    var nebulaHigh: Tone
    var nebulaHighAlpha: Double
    var nebulaLow: Tone
    var nebulaLowAlpha: Double
    /// How bright the stars are (dimmed by day).
    var stars: Double

    static let night = SkyPalette(top: Tone(0x070816), bottom: Tone(0x020309), nebulaHigh: Tone(0x5B21B6), nebulaHighAlpha: 0.30,
                                  nebulaLow: Tone(0x312E81), nebulaLowAlpha: 0.18, stars: 1)
    static let dawn = SkyPalette(top: Tone(0x1C1030), bottom: Tone(0x07050D), nebulaHigh: Tone(0xA8558F), nebulaHighAlpha: 0.30,
                                 nebulaLow: Tone(0xD97706), nebulaLowAlpha: 0.10, stars: 0.55)
    static let day = SkyPalette(top: Tone(0x0C1733), bottom: Tone(0x040915), nebulaHigh: Tone(0x2563EB), nebulaHighAlpha: 0.24,
                                nebulaLow: Tone(0x7C3AED), nebulaLowAlpha: 0.12, stars: 0.35)
    static let dusk = SkyPalette(top: Tone(0x1A0E2C), bottom: Tone(0x07040D), nebulaHigh: Tone(0x7C3AED), nebulaHighAlpha: 0.34,
                                 nebulaLow: Tone(0xEA580C), nebulaLowAlpha: 0.11, stars: 0.7)

    /// (minute of the day, palette); wraps around midnight.
    static let anchors: [(minute: Int, palette: SkyPalette)] = [
        (0, .night), (300, .night),       // until 5:00 night
        (390, .dawn), (450, .dawn),       // 6:30–7:30 dawn
        (600, .day), (960, .day),         // 10:00–16:00 day
        (1110, .dusk), (1200, .dusk),     // 18:30–20:00 dusk
        (1320, .night), (1440, .night),   // from 22:00 night
    ]

    public static func at(_ date: Date, calendar: Calendar = .current) -> SkyPalette {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return at(minute: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    public static func at(minute: Int) -> SkyPalette {
        let m = ((minute % 1440) + 1440) % 1440
        for index in 0..<(anchors.count - 1) {
            let (from, to) = (anchors[index], anchors[index + 1])
            guard m >= from.minute, m <= to.minute else { continue }
            let span = Double(to.minute - from.minute)
            let t = span == 0 ? 0 : Double(m - from.minute) / span
            return from.palette.mixed(to.palette, t)
        }
        return .night
    }

    func mixed(_ other: SkyPalette, _ t: Double) -> SkyPalette {
        let t = min(max(t, 0), 1)
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        return SkyPalette(top: top.mixed(other.top, t), bottom: bottom.mixed(other.bottom, t),
                          nebulaHigh: nebulaHigh.mixed(other.nebulaHigh, t), nebulaHighAlpha: lerp(nebulaHighAlpha, other.nebulaHighAlpha),
                          nebulaLow: nebulaLow.mixed(other.nebulaLow, t), nebulaLowAlpha: lerp(nebulaLowAlpha, other.nebulaLowAlpha),
                          stars: lerp(stars, other.stars))
    }
}

/// The stars, placed once (a fixed seed, so every screen shows the same sky).
enum Starfield {
    struct Star: Sendable {
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let alpha: Double
        let color: Color
    }

    static let stars: [Star] = {
        var seed: UInt64 = 11
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(UInt64(1) << 31)
        }
        var out: [Star] = []
        for _ in 0..<380 {
            let x = next(), y = next(), magnitude = next(), alpha = next(), hue = next()
            let bright = magnitude > 0.985
            let size: CGFloat = bright ? 1.6 : (magnitude > 0.9 ? 1.1 : 0.7)
            let color: Color = hue < 0.12 ? Color(rgb: 0xBECDFF) : (hue < 0.18 ? Color(rgb: 0xFFE2C8) : .white)
            out.append(Star(x: x, y: y, size: size, alpha: bright ? 0.85 : 0.16 + alpha * 0.42, color: color))
        }
        return out
    }()
}

/// Mission-control type: telemetry lines and numbers in the monospaced face.
public extension Font {
    static func telemetry(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// A number on the instrument panel: the value in the monospaced face, a
/// small label under it. Words ("Normal") stay in the regular face.
public struct TelemetryStat: View {
    let value: String
    let label: String
    var accent: Color? = nil

    public init(_ value: String, _ label: String, accent: Color? = nil) {
        self.value = value
        self.label = label
        self.accent = accent
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(value.contains(where: \.isNumber) ? .telemetry(24, weight: .medium) : .system(size: 22, weight: .semibold))
                .foregroundStyle(accent ?? AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A numbered section: "01  Today ……… 1 of 4 done", on a hairline.
public struct SpaceSection<Trailing: View>: View {
    let number: Int
    let title: String
    let trailing: Trailing

    public init(_ number: Int, _ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.number = number
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(spacing: 14) {
            Rectangle().fill(AppTheme.hairline).frame(height: 1)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(format: "%02d", number))
                    .font(.telemetry(11))
                    .foregroundStyle(AppTheme.brightRed.opacity(0.9))
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                trailing
                    .font(.telemetry(11.5))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }
}

private struct CardBackground: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .glassSurface()
    }
}

public extension View {
    /// A frosted glass panel: the light behind shows through.
    func cardStyle(padding: CGFloat = 16) -> some View {
        modifier(CardBackground(padding: padding))
    }

    /// Frosted glass: blur, a translucent dark tint, a 1 px white edge that
    /// catches the light at the top, a soft shadow. `tint` lights it from
    /// behind (a red bloom for the thing that matters).
    func glassSurface(cornerRadius: CGFloat = AppTheme.cardCornerRadius, tint: Color? = nil) -> some View {
        // Space panels: a faint, nearly transparent plate with a hairline edge —
        // the sky stays visible behind; `tint` lights the top edge for what matters.
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background {
            ZStack {
                shape.fill(Color(rgb: 0x0A0B14).opacity(0.72))
                shape.fill(Color.white.opacity(0.025))
                if let tint {
                    shape.fill(LinearGradient(colors: [tint.opacity(0.13), tint.opacity(0)], startPoint: .top, endPoint: .center))
                }
            }
        }
        .overlay {
            shape.strokeBorder(LinearGradient(colors: [(tint ?? .white).opacity(tint == nil ? 0.11 : 0.35), .white.opacity(0.05)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
    }

    /// A small floating glass capsule (top controls, chips on the hero).
    func glassCapsule() -> some View {
        background {
            ZStack {
                Capsule().fill(Color(rgb: 0x0A0B14).opacity(0.8))
                Capsule().fill(Color.white.opacity(0.03))
            }
        }
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
    }

    /// The standard screen canvas, full-bleed. The status bar gets its own
    /// backdrop, so scrolled content never sits under the clock, and every
    /// scroll view ends with room to spare above the tab bar.
    func appScreen(_ atmosphere: Atmosphere = .subtle, sportSlug: String? = nil) -> some View {
        background(AppBackground(atmosphere, sportSlug: sportSlug))
            .overlay(alignment: .top) {
                AppTheme.background.opacity(0.96)
                    .frame(height: 0)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
            .contentMargins(.bottom, 24, for: .scrollContent)
            .modifier(ReadableWidth())
    }
}

/// On iPad (regular width) the content keeps a readable column in the
/// middle instead of stretching edge to edge. Phones are unchanged.
struct ReadableWidth: ViewModifier {
    static let maxWidth: CGFloat = 680
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        if sizeClass == .regular {
            GeometryReader { geometry in
                content.contentMargins(.horizontal, max(0, (geometry.size.width - Self.maxWidth) / 2), for: .scrollContent)
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - Buttons

/// The primary action: a glass capsule lit red from behind — calm, tactile,
/// never a flat red block.
public struct PrimaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration)
    }

    private struct PrimaryButtonBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.headline.weight(.semibold))
                // One line, never wrapped: shrink a little first; a row of
                // buttons that still doesn't fit stacks instead (ButtonRow).
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 18)
                // Starlight: a bright plate with dark type — the one thing on
                // the screen to press. Violet stays light, never a fill.
                .foregroundStyle(Color(rgb: 0x0B0B14))
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Capsule().fill(Color(rgb: 0xEEEAFE)))
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 0.5) }
                .shadow(color: Color(rgb: 0xC4B5FD).opacity(isEnabled ? 0.22 : 0), radius: 16, x: 0, y: 4)
                .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.3)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        }
    }
}

/// The quieter secondary action: transparent with a thin light edge.
public struct SecondaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 18)
            .foregroundStyle(AppTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.white.opacity(0.04), in: Capsule())
            .overlay { Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1) }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Buttons side by side when every label fits on one line, stacked
/// otherwise — so big text never squeezes a label onto two lines.
public struct ButtonRow<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    public init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) { content }
            VStack(spacing: 10) { content }
        }
    }
}

public extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

public extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Popup buttons
//
// One rule for every popup: top left an ✕ closes it (anything not saved is
// discarded); top right a ✓ saves and closes, only where there's something
// to save; ‹ only goes back a page inside a flow. No "Done" or "Cancel" text.

/// ✕ in a popup's navigation bar.
public struct CloseToolbarItem: ToolbarContent {
    let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: action) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
            }
            .accessibilityLabel("Close")
        }
    }
}

/// ✓ in a popup's navigation bar: saves and closes.
public struct ConfirmToolbarItem: ToolbarContent {
    let enabled: Bool
    let accessibilityLabel: String
    let action: () -> Void

    public init(enabled: Bool = true, accessibilityLabel: String = "Save", action: @escaping () -> Void) {
        self.enabled = enabled
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button(action: action) {
                Image(systemName: "checkmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(enabled ? AppTheme.ink : AppTheme.secondaryText)
            }
            .disabled(!enabled)
            .accessibilityLabel(accessibilityLabel)
        }
    }
}

/// ✓ at the top right of a full-page popup (StepScaffold): saves and closes.
public struct ConfirmCircleButton: View {
    let enabled: Bool
    let action: () -> Void

    public init(enabled: Bool = true, action: @escaping () -> Void) {
        self.enabled = enabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(enabled ? AppTheme.onAccent : AppTheme.secondaryText)
                .frame(width: 46, height: 46)
                .background(enabled ? AppTheme.accent : AppTheme.fill, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("Save")
    }
}

/// A round gray icon button (back chevron and toolbar icons).
public struct CircleIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    public init(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .frame(width: 46, height: 46)
                .background(AppTheme.fill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Rings

/// A progress ring with anything centred inside it.
public struct RingView<Center: View>: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat
    let center: Center

    public init(progress: Double, color: Color, lineWidth: CGFloat = 8, @ViewBuilder center: () -> Center) {
        self.progress = progress
        self.color = color
        self.lineWidth = lineWidth
        self.center = center()
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.fill, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)
            center
        }
    }
}

/// A small stat card: a bold value, a gray label, and a ring with an
/// icon underneath.
public struct RingStatCard: View {
    let value: String
    let label: String
    let progress: Double
    let color: Color
    let systemImage: String
    /// One line saying what the number means or what tapping does.
    let caption: String?

    public init(value: String, label: String, progress: Double, color: Color, systemImage: String, caption: String? = nil) {
        self.value = value
        self.label = label
        self.progress = progress
        self.color = color
        self.systemImage = systemImage
        self.caption = caption
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(2, reservesSpace: true)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            RingView(progress: progress, color: color, lineWidth: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 58, height: 58)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)" + (caption.map { ". \($0)" } ?? ""))
    }
}

// MARK: - Choices

public extension View {
    /// A choice's surface: selected is lit red from within (a red glass tint
    /// and a red edge), unselected is a whisper of glass with a hairline.
    func selectableSurface<S: InsettableShape>(_ selected: Bool, shape: S) -> some View {
        background(selected ? AppTheme.brand.opacity(0.22) : Color.white.opacity(0.05), in: shape)
            .overlay { shape.strokeBorder(selected ? AppTheme.brightRed.opacity(0.75) : AppTheme.hairline, lineWidth: 1) }
            .shadow(color: AppTheme.brand.opacity(selected ? 0.25 : 0), radius: 12, x: 0, y: 4)
    }
}

/// A big rounded choice row: red when selected, soft gray when not.
public struct OptionRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String?
    let isSelected: Bool

    public init(title: String, subtitle: String? = nil, systemImage: String? = nil, isSelected: Bool) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isSelected = isSelected
    }

    public var body: some View {
        HStack(spacing: 14) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(isSelected ? AppTheme.brand.opacity(0.2) : AppTheme.fill, in: Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .opacity(0.75)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(AppTheme.ink)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .selectableSurface(isSelected, shape: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One row of a list card (Home's TODAY, Me's settings): a tinted icon, a
/// title, one short detail, and what's on the right (a time, a tick, a chevron).
public struct ListRow<Trailing: View>: View {
    let systemImage: String
    let color: Color
    let title: String
    let detail: String?
    let trailing: Trailing

    public init(systemImage: String, color: Color = AppTheme.ink, title: String, detail: String? = nil,
                @ViewBuilder trailing: () -> Trailing = { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(AppTheme.secondaryText) }) {
        self.systemImage = systemImage
        self.color = color
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.leading)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

/// A big answer for a one-tap question (check-in, reflection): the answers
/// share the width, two to a row when they don't fit on one.
public struct ChoiceGrid<Option: Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    let isSelected: (Option) -> Bool
    let onTap: (Option) -> Void

    public init(_ options: [Option], title: @escaping (Option) -> String, isSelected: @escaping (Option) -> Bool, onTap: @escaping (Option) -> Void) {
        self.options = options
        self.title = title
        self.isSelected = isSelected
        self.onTap = onTap
    }

    public var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            ForEach(options, id: \.self) { option in
                let selected = isSelected(option)
                Button { onTap(option) } label: {
                    Text(title(option))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(AppTheme.ink)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .selectableSurface(selected, shape: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// A calm one-question-at-a-time flow (check-in, reflection): close and a
/// thin progress bar on top, the question big, its answers, one button.
public struct QuestionPage<Content: View>: View {
    let progress: Double
    let question: String
    let hint: String?
    let buttonTitle: String?
    let buttonEnabled: Bool
    let onClose: () -> Void
    let onBack: (() -> Void)?
    let onButton: () -> Void
    let content: Content

    public init(progress: Double, question: String, hint: String? = nil, buttonTitle: String? = "Next", buttonEnabled: Bool = true,
                onClose: @escaping () -> Void, onBack: (() -> Void)? = nil, onButton: @escaping () -> Void = {},
                @ViewBuilder content: () -> Content) {
        self.progress = progress
        self.question = question
        self.hint = hint
        self.buttonTitle = buttonTitle
        self.buttonEnabled = buttonEnabled
        self.onClose = onClose
        self.onBack = onBack
        self.onButton = onButton
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if let onBack {
                    CircleIconButton(systemImage: "chevron.left", accessibilityLabel: "Back", action: onBack)
                } else {
                    CircleIconButton(systemImage: "xmark", accessibilityLabel: "Close", action: onClose)
                }
                StepProgressBar(progress: progress)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(question)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        if let hint {
                            Text(hint)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
            if let buttonTitle {
                Button(buttonTitle, action: onButton)
                    .buttonStyle(.primary)
                    .disabled(!buttonEnabled)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
        .appScreen()
    }
}

/// Static chips that wrap (e.g. the athlete's development goals).
struct FlowChips: View {
    let titles: [String]

    init(_ titles: [String]) {
        self.titles = titles
    }

    var body: some View {
        WrapLayout(spacing: 8) {
            ForEach(titles, id: \.self) { title in
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppTheme.fill, in: Capsule())
            }
        }
    }
}

/// A small capsule chip, for filters and 1–5 scales.
public struct Chip: View {
    let title: String
    let isSelected: Bool

    public init(_ title: String, isSelected: Bool) {
        self.title = title
        self.isSelected = isSelected
    }

    public var body: some View {
        Text(title)
            .font(.headline)
            .lineLimit(1)
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .selectableSurface(isSelected, shape: Capsule())
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A small tinted label, e.g. a quality or phase name.
public struct Tag: View {
    let title: String
    let color: Color

    public init(_ title: String, color: Color = AppTheme.secondaryText) {
        self.title = title
        self.color = color
    }

    public var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Layout helpers

/// A screen title: very large, bold, left-aligned, inside the scroll
/// content rather than in a navigation bar.
public struct ScreenTitle: View {
    let title: String
    let subtitle: String?

    public init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // V3 type scale: page 32 bold, section 22 semibold, card 18–20,
            // body 15–17, secondary 14–15.
            Text(title)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(AppTheme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A section heading with a one-line explanation under it, so every block
/// on a screen says what it is for.
public struct SectionHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing

    public init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        // Space: each section starts on a hairline, the title calm, the
        // subtitle a quiet line — the content carries the screen.
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(AppTheme.hairline).frame(height: 1)
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                trailing
            }
        }
        .padding(.top, 10)
    }
}

public struct SectionTitle: View {
    let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(AppTheme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A thin capsule progress bar, as at the top of every onboarding step.
public struct StepProgressBar: View {
    let progress: Double

    public init(progress: Double) {
        self.progress = progress
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(AppTheme.fill)
                Capsule()
                    .fill(AppTheme.accent)
                    .frame(width: proxy.size.width * max(0, min(1, progress)))
                    .animation(.easeOut(duration: 0.3), value: progress)
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("Step progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

/// The frame every onboarding-style step uses: back button and progress bar
/// on top, a big left-aligned title, the content, and a primary button pinned
/// to the bottom.
public struct StepScaffold<Content: View>: View {
    let progress: Double?
    let title: String
    let subtitle: String?
    let buttonTitle: String
    let buttonEnabled: Bool
    let onBack: (() -> Void)?
    let onClose: (() -> Void)?
    let onConfirm: (() -> Void)?
    let onContinue: (() -> Void)?
    let content: Content

    /// `onBack` ‹ goes back a page; `onClose` ✕ closes the popup;
    /// `onConfirm` ✓ saves and closes; `onContinue` is the big button at
    /// the bottom (Next, Build my plan…), left out when ✓ saves.
    public init(
        progress: Double? = nil, title: String, subtitle: String? = nil,
        buttonTitle: String = "Continue", buttonEnabled: Bool = true,
        onBack: (() -> Void)? = nil, onClose: (() -> Void)? = nil, onConfirm: (() -> Void)? = nil,
        onContinue: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.progress = progress
        self.title = title
        self.subtitle = subtitle
        self.buttonTitle = buttonTitle
        self.buttonEnabled = buttonEnabled
        self.onBack = onBack
        self.onClose = onClose
        self.onConfirm = onConfirm
        self.onContinue = onContinue
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                if let onBack {
                    CircleIconButton(systemImage: "chevron.left", accessibilityLabel: "Back", action: onBack)
                } else if let onClose {
                    CircleIconButton(systemImage: "xmark", accessibilityLabel: "Close", action: onClose)
                }
                if let progress {
                    StepProgressBar(progress: progress)
                } else {
                    Spacer(minLength: 0)
                }
                if let onConfirm {
                    ConfirmCircleButton(enabled: buttonEnabled, action: onConfirm)
                }
            }
            .frame(minHeight: 40)
            .padding(.horizontal, 24)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ScreenTitle(title, subtitle: subtitle)
                    content
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }

            if let onContinue {
                Button(buttonTitle, action: onContinue)
                    .buttonStyle(.primary)
                    .disabled(!buttonEnabled)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
        }
        .appScreen()
    }
}

/// A thumbnail well: the item's pose on a gray rounded square, used in every
/// exercise list row.
public struct ItemThumbnail: View {
    let item: CatalogueItem?
    let size: CGFloat

    public init(item: CatalogueItem?, size: CGFloat = 64) {
        self.item = item
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.fill)
            if let pattern = item?.posePattern {
                RigStillView(pattern: pattern)
                    .padding(4)
            } else {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title2)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// "1 set", "3 sets".
public func countedNoun(_ n: Int, _ singular: String, plural: String? = nil) -> String {
    "\(n) \(n == 1 ? singular : (plural ?? singular + "s"))"
}

/// Human-readable dose, e.g. "3 × 8", "3 × 20s", "2 × 10 contacts".
public enum DoseFormatter {
    /// In plain words: "3 sets of 8 reps", "2 sets of 30 seconds each side".
    public static func text(_ dose: Dose) -> String {
        let perSide = dose.perSide == true ? " each side" : ""
        let sets = countedNoun(dose.sets, "set")
        switch dose.kind {
        case "reps": return "\(sets) of \(countedNoun(dose.reps ?? 0, "rep"))\(perSide)"
        case "time": return "\(sets) of \(duration(dose.seconds ?? 0))\(perSide)"
        case "distance": return "\(dose.sets == 1 ? "1 time" : "\(dose.sets) times") \(Measure.distance(m: dose.metres ?? 0))"
        case "contacts": return "\(sets) of \(dose.contacts ?? 0) jumps"
        default: return sets
        }
    }

    /// "30 seconds", "1 minute", "1 min 30 s".
    public static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) seconds" }
        let m = seconds / 60, s = seconds % 60
        if s == 0 { return m == 1 ? "1 minute" : "\(m) minutes" }
        return "\(m) min \(s) s"
    }

    /// "Rest 90 seconds between sets".
    public static func rest(_ seconds: Int) -> String {
        seconds <= 0 ? "No rest needed" : "Rest \(duration(seconds)) between sets"
    }
}

/// A catalogue slug turned into a readable name when the item itself isn't
/// downloaded (e.g. a substitute from another sport's pack).
public func displayName(forSlug slug: String) -> String {
    slug.replacingOccurrences(of: "-", with: " ").capitalized
}

// MARK: - Units

/// Pounds or kilograms. Everything is stored in kg; this is only how it's
/// shown and stepped. Defaults to the phone's region (lb in the US).
public enum WeightUnit: String, Sendable, CaseIterable {
    case kg, lb

    public static let storageKey = "weightUnit"
    private static let kgPerLb = 0.45359237

    public static var current: WeightUnit {
        if let raw = UserDefaults.standard.string(forKey: storageKey), let unit = WeightUnit(rawValue: raw) { return unit }
        return Locale.current.measurementSystem == .us ? .lb : .kg
    }

    public func value(kg: Double) -> Double {
        self == .kg ? kg : kg / Self.kgPerLb
    }

    public func kg(from value: Double) -> Double {
        self == .kg ? value : value * Self.kgPerLb
    }

    /// One tap of the weight stepper, in kg.
    public var stepKg: Double {
        self == .kg ? 2.5 : 5 * Self.kgPerLb
    }

    public func format(kg: Double) -> String {
        let shown = value(kg: kg)
        let rounded = self == .lb ? shown.rounded() : (shown * 2).rounded() / 2
        return "\(rounded.formatted(.number.precision(.fractionLength(0...1)))) \(rawValue)"
    }
}

/// Lengths and distances in the athlete's units: imperial when weights are
/// in pounds (one choice for the whole app). Stored values stay metric.
public enum Measure {
    public static var imperial: Bool { WeightUnit.current == .lb }

    /// A jump or a throw: "47 cm" / "18.5 in".
    public static func length(cm: Double, imperial: Bool = Measure.imperial) -> String {
        imperial ? "\((cm / 2.54).formatted(.number.precision(.fractionLength(0...1)))) in" : "\(Int(cm.rounded())) cm"
    }

    /// A drill or a sprint: "20 m" / "22 yd".
    public static func distance(m: Double, imperial: Bool = Measure.imperial) -> String {
        imperial ? "\(Int((m / 0.9144).rounded())) yd" : "\(Int(m.rounded())) m"
    }

    /// A body height: "175 cm" / "5 ft 9 in".
    public static func height(cm: Int, imperial: Bool = Measure.imperial) -> String {
        guard imperial else { return "\(cm) cm" }
        let inches = Int((Double(cm) / 2.54).rounded())
        return "\(inches / 12) ft \(inches % 12) in"
    }

    /// What the athlete types for a length, back to centimetres.
    public static func centimetres(fromTyped value: Double, imperial: Bool = Measure.imperial) -> Double {
        imperial ? value * 2.54 : value
    }
}
