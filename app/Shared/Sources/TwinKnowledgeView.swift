import SwiftUI

// The pieces of the Twin page's portrait (docs/TWIN-RESEARCH.md, TwinPage):
// a line the twin knows, an insight from the analysis, something still
// being learned, last month's letter. One look for all of them, so the
// athlete reads one portrait, not two analysts.

/// "In your plan: …" — what this line changes, said where the fact is.
struct PlanEffectNote: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "calendar")
                .font(.footnote.weight(.semibold))
                .accessibilityHidden(true)
            Text("In your plan: " + text)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(AuraTone.training.mark)
    }
}

/// A line the twin knows, with its basis and "Not right?" (T13; pain lines
/// can't be hidden — showing it to someone is the safety rule, T9).
struct KnowledgeRow: View {
    let line: KnowledgeLine
    let effect: String?
    let notRight: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if line.safety {
                    Image(systemName: "cross.case.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.danger)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                }
                Text(line.text)
                    .font(.body)
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if let effect { PlanEffectNote(text: effect) }
            HStack(alignment: .firstTextBaseline) {
                Text(line.basis)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if !line.safety {
                    Button("Not right?", action: notRight)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(minHeight: 44)
                        .buttonStyle(.pressable)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, line.safety ? 16 : 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
    }
}

/// Something the analysis found: the sentence, how it moved, what it changes
/// in the plan, the athlete's own chart and numbers on a tap, and the
/// briefing the coach assigned. Something that works has no briefing.
struct TwinInsightRow: View {
    let insight: TwinInsight
    let effect: String?
    let read: Bool
    let openBriefing: (Briefing) -> Void

    @State private var open = false

    private var tint: Color { insight.positive ? AppTheme.green : insight.kind.topic?.color ?? AuraTone.mind.mark }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(tint).frame(width: 7, height: 7).accessibilityHidden(true)
                Text(insight.positive ? "Working for you" : insight.strength == .strong ? "Strong pattern" : "Emerging")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer(minLength: 8)
                if let trend = insight.trend, trend != .steady {
                    Text(trend.label)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            Text(insight.headline)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if insight.positive, !insight.detail.isEmpty {
                Text(insight.detail)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let effect { PlanEffectNote(text: effect) }
            if !insight.positive {
                Button { withAnimation(.easeInOut(duration: 0.25)) { open.toggle() } } label: {
                    HStack(spacing: 6) {
                        Text(open ? "Hide the numbers" : "The numbers")
                        Image(systemName: open ? "chevron.up" : "chevron.down").font(.caption.weight(.bold))
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                if open {
                    VStack(alignment: .leading, spacing: 8) {
                        if let evidence = insight.evidence {
                            TwinEvidenceChart(evidence: evidence, tint: tint).frame(height: 110)
                        }
                        Text(insight.detail)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("From \(insight.basis)")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedText)
                    }
                    .transition(.opacity)
                }
            }
            if let briefing = insight.briefing {
                Button {
                    AcademyEvent.log(.insightOpened)
                    openBriefing(briefing)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(read ? "Read again: \(briefing.title)" : "Read \u{201C}\(briefing.title)\u{201D}")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                                .multilineTextAlignment(.leading)
                            Text(read ? "You read it · the coach's pick" : "The coach's pick · \(briefing.minutes) min")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: read ? "checkmark" : "arrow.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                    }
                    .padding(14)
                    .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.pressable)
                .padding(.top, 2)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
    }
}

/// Something the twin can't say yet: the question, a real count (never a
/// head start, never a %), and the one thing that adds what's missing.
struct LearningRow: View {
    let question: String
    let progress: String
    /// nil for a pattern being checked (no bar: it's waiting, not filling).
    let fraction: Double?
    let actionTitle: String?
    let action: () -> Void

    /// One slim line (redesign 2026-11-28: the page was busy): the question,
    /// how far, a thin bar, and the one thing to do as a text link.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let fraction {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(AuraTone.mind.mark).frame(width: max(4, geo.size.width * min(1, max(0, fraction))))
                    }
                }
                .frame(height: 4)
                .accessibilityHidden(true)
            }
            Text(progress)
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(actionTitle)
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AuraTone.mind.mark)
                    .frame(minHeight: 32)
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Last month's letter (T15), on the Twin page in the first ten days of a month.
struct TwinLetterCard: View {
    let letter: TwinLetter
    let close: () -> Void

    var body: some View {
        AuraCard(.mind, focus: UnitPoint(x: 0.85, y: 0.15), radius: 200) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(letter.monthName): what I learned about you")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Spacer(minLength: 8)
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Close the letter")
                }
                if letter.learned.isEmpty {
                    Text("Nothing new I can say for sure yet — I'd rather wait than guess.")
                        .font(.body)
                        .foregroundStyle(AppTheme.ink)
                } else {
                    ForEach(letter.learned) { line in
                        Text("· \(line.text)")
                            .font(.body)
                            .foregroundStyle(AppTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !letter.unsure.isEmpty {
                    Text("Still unsure: " + letter.unsure.map { $0.question.lowercased() }.joined(separator: "; ") + ".")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Anything wrong? Tap “Not right?” on that line below.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
