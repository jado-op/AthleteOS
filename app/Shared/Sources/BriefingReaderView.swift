import SwiftUI

/// A briefing: a long read from the coach, laid out like a good magazine —
/// a reading serif, chapters, the athlete's own chart where the text talks
/// about it, a worked example, and one protocol for the week.
struct BriefingReaderView: View {
    let briefing: Briefing
    /// The insight that made the coach assign it (its "why" and chart).
    let insight: TwinInsight?
    let alreadyRead: Bool
    /// The athlete's sport family: its examples and its words.
    let familyID: String

    @Environment(\.dismiss) private var dismiss

    private var family: SportFamily { AcademyContent.pack.families[familyID] ?? .general }
    private func words(_ text: String?) -> String { family.fill(text ?? "") }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    ForEach(Array(briefing.chapters.enumerated()), id: \.offset) { index, chapter in
                        chapterView(index, chapter)
                    }
                    ending
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(AppTheme.background.ignoresSafeArea())
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            Spacer()
            Text("\(briefing.minutes) min read · \(briefing.chapters.count) chapters")
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppTheme.mutedText)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Briefing · \(briefing.topic.title)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(briefing.topic.color)
            Text(words(briefing.title))
                .font(.system(size: 36, weight: .semibold))
                .tracking(-1)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(words(briefing.dek))
                .font(.reading(20))
                .lineSpacing(5)
                .foregroundStyle(AppTheme.ink.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            if let insight {
                HStack(alignment: .top, spacing: 0) {
                    Rectangle().fill(AppTheme.brand).frame(width: 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Why your coach gave you this")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text(insight.why)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    Spacer(minLength: 0)
                }
                .background(AppTheme.brand.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 6)
            }
            Text("AthleteOS Coach\(briefing.sources.isEmpty ? "" : " · with sources")")
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedText)
        }
        .padding(.top, 26)
    }

    private func chapterView(_ index: Int, _ chapter: BriefingChapter) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Chapter \(index + 1)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedText)
                Text(words(chapter.title))
                    .font(.system(size: 25, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(Array(chapter.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .padding(.top, 48)
    }

    @ViewBuilder
    private func blockView(_ block: BriefingBlock) -> some View {
        let resolved = block.resolved(for: familyID)
        switch block.kind {
        case .p:
            Text(words(resolved.text))
                .font(.reading(18))
                .lineSpacing(7)
                .foregroundStyle(AppTheme.ink.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        case .h:
            Text(words(resolved.text))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .padding(.top, 10)
                .fixedSize(horizontal: false, vertical: true)
        case .quote:
            Text(words(resolved.text))
                .font(.system(size: 24, weight: .medium))
                .tracking(-0.4)
                .lineSpacing(4)
                .foregroundStyle(AppTheme.ink)
                .padding(.vertical, 14)
                .padding(.leading, 16)
                .overlay(alignment: .leading) { Rectangle().fill(briefing.topic.color).frame(width: 2) }
                .fixedSize(horizontal: false, vertical: true)
        case .example:
            VStack(alignment: .leading, spacing: 8) {
                Text("Example")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(briefing.topic.color)
                Text(words(resolved.title))
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(words(resolved.text))
                    .font(.reading(16))
                    .lineSpacing(5)
                    .foregroundStyle(AppTheme.ink.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1) }
        case .yourData:
            if let evidence = insight?.evidence {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your data")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.brightRed)
                    TwinEvidenceChart(evidence: evidence).frame(height: 110)
                }
                .padding(16)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1) }
            }
        case .protocol:
            VStack(alignment: .leading, spacing: 14) {
                Text(words(block.title ?? "Your week"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                ForEach(Array((block.steps ?? []).enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(AppTheme.background)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(briefing.topic.color))
                        Text(words(step))
                            .font(.body)
                            .foregroundStyle(AppTheme.ink.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: 20, tint: briefing.topic.color)
        }
    }

    private var ending: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !briefing.sources.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sources")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.mutedText)
                    ForEach(briefing.sources, id: \.url) { source in
                        Text(source.detail)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            followUps
            Text("This briefing teaches; it doesn't diagnose. If something hurts, or something feels heavy for a while, talk to a parent, your coach or a doctor.")
                .font(.footnote)
                .foregroundStyle(AppTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if !alreadyRead {
                    AcademyStore.save(AcademyStore.reading(briefing.id, in: AcademyStore.load(), at: .now))
                    AcademyEvent.log(.lessonCompleted)
                }
                dismiss()
            } label: {
                HeroCTALabel(alreadyRead ? "Close" : "I've read it")
            }
            .buttonStyle(.primary)
        }
        .padding(.top, 48)
    }
}

// MARK: - Short follow-ups

extension BriefingReaderView {
    /// The Campus area that goes with each briefing topic.
    static func campusArea(for topic: BriefingTopic) -> String {
        switch topic {
        case .recovery: "sleep"
        case .strength: "training-science"
        case .mind: "psychology"
        case .fuel: "nutrition"
        }
    }

    /// Two short lessons from the matching Campus area, not yet learned:
    /// the briefing is the main read, these are the quick follow-ups.
    @ViewBuilder
    var followUps: some View {
        let learned = CampusProgress.learned(UserDefaults.standard.string(forKey: CampusProgress.learnedKey) ?? "")
        let lessons = campusTopics.first { $0.id == Self.campusArea(for: briefing.topic) }?
            .lessons.filter { !learned.contains($0.id) }.prefix(2) ?? []
        if !lessons.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Short follow-ups")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedText)
                ForEach(Array(lessons)) { lesson in
                    Button {
                        CampusLaunch.shared.pendingLessonID = lesson.id
                        dismiss()
                        // Open the lessons once the reader has gone.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(600))
                            AcademyNavigation.shared.showingLessons = true
                        }
                    } label: {
                        ListRow(systemImage: "book.closed", color: AppTheme.brightRed, title: lesson.title,
                                detail: "\(lesson.minutes) min lesson")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
