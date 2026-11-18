import SwiftUI

// MARK: - Design V8 (owner, 2026-11-18)
//
// Big, short sentences that carry the whole message ("Good evening, Dominik.
// Today: 45 min — 1 of 4 done."), tap to dig deeper. Colour has a job: each
// kind of thing has its own card colour, and the soft aura inside a card sits
// behind the one number or word the eye should land on. Nothing decorative
// without a function. Black canvas, white type, one bright action per screen.

/// What a card is about — its colour says it before the words do.
public enum AuraTone: String, Sendable, CaseIterable {
    /// Training, workouts, load: ember orange.
    case training
    /// Body: check-in, readiness, sleep, recovery: deep blue.
    case body
    /// Mind and the twin: reflection, Academy, briefings, lessons: magenta.
    case mind
    /// Competitions and games: sage green.
    case game
    /// Everything else: a quiet dark plate.
    case calm

    /// The card's own gradient, top-leading to bottom-trailing.
    var base: [Color] {
        switch self {
        case .training: [Color(rgb: 0x6E1404), Color(rgb: 0xD9480F), Color(rgb: 0xF97316)]
        case .body: [Color(rgb: 0x081A5C), Color(rgb: 0x1E40AF), Color(rgb: 0x3B6FE0)]
        case .mind: [Color(rgb: 0x4A0D3A), Color(rgb: 0x9D2B7A), Color(rgb: 0xD46BAE)]
        case .game: [Color(rgb: 0x0F2A22), Color(rgb: 0x2F5D4E), Color(rgb: 0x6E9583)]
        case .calm: [Color(rgb: 0x111114), Color(rgb: 0x17171B)]
        }
    }

    /// The aura behind the focal point: brightest in the middle, fading out.
    var aura: [Color] {
        switch self {
        case .training: [Color(rgb: 0xFFB45C).opacity(0.85), Color(rgb: 0xFF7A1A).opacity(0.35), .clear]
        case .body: [Color(rgb: 0x9CC3FF).opacity(0.75), Color(rgb: 0x4F7DFF).opacity(0.3), .clear]
        case .mind: [Color(rgb: 0xFF8AC8).opacity(0.7), Color(rgb: 0xE11D74).opacity(0.35), .clear]
        case .game: [Color(rgb: 0xD9F99D).opacity(0.6), Color(rgb: 0x84CC16).opacity(0.22), .clear]
        case .calm: [Color.white.opacity(0.05), .clear]
        }
    }

    /// The colour used for a small mark (a dot, a bar) of this kind on black.
    public var mark: Color {
        switch self {
        case .training: Color(rgb: 0xFB7A35)
        case .body: Color(rgb: 0x6E9BFF)
        case .mind: Color(rgb: 0xE879C0)
        case .game: Color(rgb: 0xA3D9A5)
        case .calm: Color.white.opacity(0.6)
        }
    }
}

/// The card background: the tone's gradient with the aura on the focal point.
public struct AuraBackground: View {
    let tone: AuraTone
    let focus: UnitPoint
    let radius: CGFloat

    public init(_ tone: AuraTone, focus: UnitPoint = .center, radius: CGFloat = 190) {
        self.tone = tone
        self.focus = focus
        self.radius = radius
    }

    public var body: some View {
        ZStack {
            LinearGradient(colors: tone.base, startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: tone.aura, center: focus, startRadius: 0, endRadius: radius)
        }
        .accessibilityHidden(true)
    }
}

/// A coloured card: one job, one focal point, tap for more.
public struct AuraCard<Content: View>: View {
    let tone: AuraTone
    let focus: UnitPoint
    let radius: CGFloat
    let padding: CGFloat
    let content: Content

    public init(_ tone: AuraTone, focus: UnitPoint = .center, radius: CGFloat = 190, padding: CGFloat = 22,
                @ViewBuilder content: () -> Content) {
        self.tone = tone
        self.focus = focus
        self.radius = radius
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity)
            .background(AuraBackground(tone, focus: focus, radius: radius))
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(Color.white.opacity(tone == .calm ? 0.06 : 0.12), lineWidth: 1)
            }
    }
}

/// The big sentence: the words that matter in white, the words that only
/// connect them dimmed, small symbols inline. Short, and it says everything.
public struct Headline: View {
    public enum Part: Sendable {
        case strong(String)
        case soft(String)
        case icon(String)
    }

    let parts: [Part]
    let size: CGFloat

    public init(_ parts: [Part], size: CGFloat = 34) {
        self.parts = parts
        self.size = size
    }

    public var body: some View {
        text
            .font(.system(size: size, weight: .bold))
            .tracking(-0.7)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var text: Text {
        var result = Text("")
        for part in parts {
            switch part {
            case .strong(let words): result = result + Text(words).foregroundColor(AppTheme.ink)
            case .soft(let words): result = result + Text(words).foregroundColor(AppTheme.ink.opacity(0.42))
            case .icon(let name): result = result + Text(Image(systemName: name)).foregroundColor(AppTheme.ink.opacity(0.85))
            }
        }
        return result
    }
}

/// A big number with its unit: light and large, digits that don't jump.
public struct BigFigure: View {
    let value: String
    let unit: String
    let size: CGFloat

    public init(_ value: String, unit: String = "", size: CGFloat = 72) {
        self.value = value
        self.unit = unit
        self.size = size
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(.system(size: size, weight: .light))
                .monospacedDigit()
                .tracking(-1.5)
                .foregroundStyle(AppTheme.ink)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: max(15, size * 0.24), weight: .semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.7))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A small coloured tile: a label, a big value, a word — tap to open it.
public struct MetricTile: View {
    let tone: AuraTone
    let label: String
    let value: String
    let unit: String
    let note: String?

    public init(_ tone: AuraTone, label: String, value: String, unit: String = "", note: String? = nil) {
        self.tone = tone
        self.label = label
        self.value = value
        self.unit = unit
        self.note = note
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.ink.opacity(0.8))
                .lineLimit(1)
            Spacer(minLength: 10)
            HStack(alignment: .lastTextBaseline) {
                BigFigure(value, unit: unit, size: 34)
                Spacer(minLength: 4)
                if let note {
                    Text(note)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.ink.opacity(0.75))
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .background(AuraBackground(tone, focus: UnitPoint(x: 0.8, y: 0.75), radius: 110))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A big ring around one figure (V8): the focal point of a live set or a rest —
/// sits on an AuraCard, white ring on the card's colour, the figure light and big.
public struct RingTimer: View {
    let progress: Double
    let value: String
    let unit: String
    let caption: String
    let size: CGFloat

    public init(progress: Double, value: String, unit: String = "", caption: String, size: CGFloat = 220) {
        self.progress = progress
        self.value = value
        self.unit = unit
        self.caption = caption
        self.size = size
    }

    public var body: some View {
        let lineWidth = max(8, size * 0.055)
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(Color.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.5), value: progress)
            VStack(spacing: 2) {
                Text(caption)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.75))
                BigFigure(value, unit: unit, size: size * 0.3)
            }
            .padding(lineWidth * 2)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption): \(value) \(unit)")
    }
}

/// The floating tab bar: a dark pill, the open tab a white circle.
struct PillTabBar: View {
    @Binding var selection: AppTab
    let items: [(tab: AppTab, title: String, symbol: String)]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.title) { item in
                let selected = selection == item.tab
                Button {
                    selection = item.tab
                } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(selected ? Color.black : Color.white.opacity(0.62))
                        .frame(width: 58, height: 52)
                        .background(Capsule().fill(selected ? Color.white : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .animation(.easeOut(duration: 0.2), value: selected)
            }
        }
        .padding(6)
        .background(Capsule().fill(Color(rgb: 0x141417).opacity(0.94)))
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1) }
        .shadow(color: .black.opacity(0.5), radius: 18, x: 0, y: 8)
    }
}
