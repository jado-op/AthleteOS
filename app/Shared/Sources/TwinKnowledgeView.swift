import SwiftUI

/// The twin page's card: "What I know about you", with how much it knows.
struct TwinKnowledgeCard: View {
    let known: Int
    let learning: Int
    let first: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Text("What I know about you")
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(AppTheme.ink)
                Text(first ?? "I'm still learning you. Every check-in, practice and game teaches me something.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(known == 0 ? "See what I'm learning" : "\(known) things · \(learning) still learning")
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(Color.white, in: Capsule())
                .padding(.top, 4)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    Color(rgb: 0x0C0C0F)
                    RadialGradient(colors: [AuraTone.mind.mark.opacity(0.18), .clear], center: UnitPoint(x: 0.9, y: 0.1),
                                   startRadius: 0, endRadius: 170)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1) }
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens what your twin has learned about you from your own data")
    }
}

/// "What I know about you" (docs/TWIN-RESEARCH.md): the athlete's portrait
/// in short sentences by area, each with where it comes from; what the twin
/// is still learning and what it needs; last month's letter; and "That's
/// not right" on every line (T13). Only the athlete sees this.
struct TwinKnowledgeView: View {
    let athlete: Athlete

    @Environment(\.dismiss) private var dismiss
    @State private var knowledge = TwinKnowledge(lines: [], learning: [], legRecoveryDays: nil)
    @State private var state = AcademyState()
    @State private var letter: TwinLetter?
    @State private var correcting: KnowledgeLine?

    private var lines: [KnowledgeLine] { TwinKnowledgeStore.visible(knowledge, state: state) }
    private var hiddenCount: Int { knowledge.lines.filter { state.knowledgeHidden?[$0.id] != nil && !$0.safety }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What I know about you")
                            .font(.system(size: 34, weight: .bold))
                            .tracking(-0.6)
                            .foregroundStyle(AppTheme.ink)
                        Text("Worked out on your phone from your own check-ins, practices, games and workouts. Only you see it. Compared only with you — never with anyone else.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let letter { letterCard(letter) }
                    ForEach(KnowledgeLine.Area.allCases, id: \.self) { area in
                        let inArea = lines.filter { $0.area == area }
                        if !inArea.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                SectionLabel(area.title)
                                ForEach(inArea) { line in row(line) }
                            }
                        }
                    }
                    if !knowledge.learning.isEmpty { learningSection }
                    if hiddenCount > 0 {
                        Button {
                            TwinKnowledgeStore.showHidden()
                            reload()
                        } label: {
                            Text("Show \(hiddenCount) hidden \(hiddenCount == 1 ? "line" : "lines") again")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.secondary)
                    }
                    Text("It says what goes together in your data, never what causes what. A pattern is only said once it has held more than once.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .appScreen()
            .navigationTitle("")
            .navigationBarTitleDisplayModeInline()
            .toolbar { CloseToolbarItem { dismiss() } }
            .onAppear(perform: reload)
            .confirmationDialog("Not right?", isPresented: Binding(get: { correcting != nil }, set: { if !$0 { correcting = nil } }),
                                titleVisibility: .visible, presenting: correcting) { line in
                Button("Hide this — it's not right") {
                    TwinKnowledgeStore.hide(line.id)
                    reload()
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Your twin only sees your data, so it can miss what you know. Hidden lines stay hidden; you can bring them back below.")
            }
        }
    }

    private func reload() {
        state = AcademyStore.load()
        knowledge = TwinKnowledgeStore.current(athlete, state: state)
        state = TwinKnowledgeStore.noteFirstSeen(knowledge.lines)
        letter = TwinKnowledgeStore.letter(knowledge, state: state)
    }

    private func row(_ line: KnowledgeLine) -> some View {
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
            HStack(alignment: .firstTextBaseline) {
                Text(line.basis)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if !line.safety {
                    Button("Not right?") { correcting = line }
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

    private var learningSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Still learning")
            Text("I won't guess. These open up as your data grows.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
            ForEach(knowledge.learning) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.question)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text(item.progress)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                    if !item.checking {
                        ProgressView(value: Double(min(item.have, item.need)), total: Double(max(item.need, 1)))
                            .tint(AuraTone.mind.mark)
                            .accessibilityHidden(true)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface()
            }
        }
    }

    private func letterCard(_ letter: TwinLetter) -> some View {
        AuraCard(.mind, focus: UnitPoint(x: 0.85, y: 0.15), radius: 200) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(letter.monthName): what I learned about you")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Spacer(minLength: 8)
                    Button {
                        TwinKnowledgeStore.closeLetter(letter.month)
                        withAnimation { self.letter = nil }
                    } label: {
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
