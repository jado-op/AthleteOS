import SwiftData
import SwiftUI

/// At the end of a season (§21): what you learned, what you enjoyed, what
/// felt like too much, what's next — next to the season's numbers. Success
/// can be a healthier schedule or simply carrying on, not only results.
public struct SeasonReview: Codable, Sendable, Equatable, Identifiable {
    public var id: String { season }
    /// sportSlug:YYYY-MM-DD of the season's end.
    public var season: String
    public var learned: String
    public var enjoyed: [String]
    public var tooMuch: [String]
    public var next: String
    public var writtenAt: Date
}

public enum SeasonReviewStore {
    static let key = "mindset.seasonReviews"

    public static var all: [SeasonReview] {
        get { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([SeasonReview].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    public static func season(for sport: AthleteSport) -> String { "\(sport.sportSlug):\(DayKey.of(sport.seasonEnd))" }

    /// Due from the season's last week until a month after it, until written.
    @MainActor
    public static func due(_ athlete: Athlete, now: Date = .now) -> AthleteSport? {
        guard let sport = athlete.activeSport else { return nil }
        let end = sport.seasonEnd
        guard now >= end.addingTimeInterval(-7 * 86_400), now <= end.addingTimeInterval(30 * 86_400) else { return nil }
        return all.contains { $0.season == season(for: sport) } ? nil : sport
    }

    public static func save(_ review: SeasonReview) {
        all = all.filter { $0.season != review.season } + [review]
    }

    static let enjoyedOptions = ["Games", "Practice", "My team", "Getting stronger", "Learning skills", "Competing", "Friends", "Coaching"]
    static let tooMuchOptions = ["Too many sessions", "Too little rest", "School and sport together", "Travel", "Pressure", "Nothing was too much"]
}

/// The one Season review: the season's numbers, four questions (what you
/// learned, enjoyed, what felt like too much, what's next), the PDF report
/// and (Pro) the recruiting profile to share, and past reviews. Opened from
/// Home when a season ends, from Progress, and from search.
struct SeasonReviewSheet: View {
    let athlete: Athlete
    let sessions: [Session]
    let catalogue: Catalogue

    @Environment(\.dismiss) private var dismiss
    @State private var learned = ""
    @State private var enjoyed: Set<String> = []
    @State private var tooMuch: Set<String> = []
    @State private var next = ""
    @State private var savedAt: Date?
    @State private var reviews = SeasonReviewStore.all
    #if os(iOS)
    @State private var details = RecruitingDetails.saved
    @State private var showingPaywall = false
    #endif

    private var sport: AthleteSport? { athlete.activeSport }
    private var sportName: String { sport.flatMap { allSportsBySlug[$0.sportSlug]?.name } ?? "Your sport" }
    private var currentSeason: String? { sport.map(SeasonReviewStore.season(for:)) }
    private var pastReviews: [SeasonReview] {
        reviews.filter { $0.season != currentSeason }.sorted { $0.writtenAt > $1.writtenAt }
    }

    /// From the season's start (or three months back before it has begun) to today.
    private var from: Date {
        if let sport, sport.seasonStart < .now { return sport.seasonStart }
        return Calendar.current.date(byAdding: .month, value: -3, to: .now) ?? .now
    }

    private var report: AthleteReport {
        let info = sport.flatMap { allSportsBySlug[$0.sportSlug] }
        let position = sport?.positionSlug.flatMap { slug in info?.positions.first { $0.slug == slug }?.name }
        let names = sessions.flatMap { $0.sets.map(\.itemSlug) }.map { catalogue.item($0)?.name ?? displayName(forSlug: $0) }
        return AthleteReport.make(AthleteReport.Input(
            name: athlete.displayName, sport: info?.name ?? "My sport", position: position,
            age: PlanGenerator.ageInYears(birthDate: athlete.birthDate, now: .now),
            sessionDates: sessions.map(\.startedAt), sessionMinutes: sessions.map(\.minutes), exerciseNames: names,
            practiceDays: PracticeLogStore.logs.map(\.day), checkInDates: athlete.checkIns.map(\.date),
            sleepHours: athlete.checkIns.filter { $0.date >= from }.compactMap(\.sleepHours),
            lessons: CampusProgress.newLessonDates().filter { $0 >= from }.count,
            results: BenchmarkStore.results, tests: BenchmarkCatalog.tests(for: sport?.sportSlug)
        ), from: from, to: .now)
    }

    var body: some View {
        let current = report
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    ScreenTitle("Season review", subtitle: "\(sportName) · what it was like for you.")
                    numbersSection(current)
                    if let sport { questionsSection(sport) }
                    if !pastReviews.isEmpty { pastSection }
                    #if os(iOS)
                    shareSection(current)
                    #endif
                    Text("Your answers are private: only you see them, and they're never in the PDF. A season counts as a success when you stayed healthy and want to carry on — not only when you won.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
            .appScreen()
            .toolbar { CloseToolbarItem { dismiss() } }
            .onAppear(perform: prefill)
            #if os(iOS)
            .proFeature(isPresented: $showingPaywall, athlete: athlete, feature: .dataExport)
            #endif
        }
    }

    private func prefill() {
        guard let currentSeason, let existing = reviews.first(where: { $0.season == currentSeason }) else { return }
        learned = existing.learned
        enjoyed = Set(existing.enjoyed)
        tooMuch = Set(existing.tooMuch)
        next = existing.next
        savedAt = existing.writtenAt
    }

    // MARK: Numbers

    private func numbersSection(_ current: AthleteReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SpaceSection(1, "Your season") {
                Text("since \(current.from.formatted(.dateTime.month(.abbreviated).day()))")
            }
            HStack(alignment: .top, spacing: 6) {
                TelemetryStat("\(current.workouts)", "workouts")
                    .frame(maxWidth: .infinity, alignment: .leading)
                TelemetryStat("\(current.minutes / 60) h", "trained")
                    .frame(maxWidth: .infinity, alignment: .leading)
                TelemetryStat("\(current.practices)", "practices logged")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Questions

    private func questionsSection(_ sport: AthleteSport) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            SpaceSection(2, "Looking back") {
                if let savedAt { Text("saved \(savedAt.formatted(.dateTime.month(.abbreviated).day()))") }
            }
            question("What did you learn this season?", text: $learned, hint: "One thing is plenty.")
            chips("What did you enjoy?", SeasonReviewStore.enjoyedOptions, $enjoyed)
            chips("What felt like too much?", SeasonReviewStore.tooMuchOptions, $tooMuch)
            question("What do you want next?", text: $next, hint: "A goal, a break, another sport — anything.")
            Button {
                let review = SeasonReview(season: SeasonReviewStore.season(for: sport), learned: learned.trimmingCharacters(in: .whitespacesAndNewlines),
                                          enjoyed: SeasonReviewStore.enjoyedOptions.filter { enjoyed.contains($0) },
                                          tooMuch: SeasonReviewStore.tooMuchOptions.filter { tooMuch.contains($0) },
                                          next: next.trimmingCharacters(in: .whitespacesAndNewlines), writtenAt: .now)
                SeasonReviewStore.save(review)
                reviews = SeasonReviewStore.all
                savedAt = review.writtenAt
            } label: {
                HeroCTALabel(savedAt == nil ? "Save my review" : "Save changes")
            }
            .buttonStyle(.primary)
        }
    }

    private func question(_ title: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
            TextField(hint, text: text, axis: .vertical)
                .lineLimit(2...5)
                .padding(14)
                .glassSurface(cornerRadius: 14)
        }
    }

    private func chips(_ title: String, _ options: [String], _ selection: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.ink)
            WrapLayout(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button {
                        if selection.wrappedValue.contains(option) { selection.wrappedValue.remove(option) } else { selection.wrappedValue.insert(option) }
                    } label: { Chip(option, isSelected: selection.wrappedValue.contains(option)) }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Past reviews

    private var pastSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SpaceSection(3, "Past seasons") { Text("\(pastReviews.count)") }
            ForEach(pastReviews) { review in
                VStack(alignment: .leading, spacing: 4) {
                    Text(review.writtenAt.formatted(.dateTime.month(.wide).year()))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    if !review.learned.isEmpty {
                        Text("Learned: " + review.learned).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                    }
                    if !review.enjoyed.isEmpty {
                        Text("Enjoyed: " + review.enjoyed.joined(separator: ", ")).font(.footnote).foregroundStyle(AppTheme.secondaryText)
                    }
                    if !review.next.isEmpty {
                        Text("Next: " + review.next).font(.footnote).foregroundStyle(AppTheme.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.hairline).frame(height: 1) }
            }
        }
    }

    // MARK: Share

    #if os(iOS)
    /// The season as a one-page PDF for a coach or parent, and (Pro) the
    /// recruiting profile for college coaches. Numbers only, never the answers above.
    private func shareSection(_ current: AthleteReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SpaceSection(pastReviews.isEmpty ? 3 : 4, "Share")
            if let pdf = ReportRenderer.pdf(ReportPage(report: current), fileName: "AthleteOS report.pdf") {
                ShareLink(item: pdf) {
                    Label("PDF for a coach or parent", systemImage: "doc.richtext")
                }
                .buttonStyle(.secondary)
            }
            Text("Recruiting profile")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .padding(.top, 6)
            Text("Tests, training and your details, for college coaches.")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
            if ProAccess.isPro {
                recruitingCard(current)
            } else {
                Button("See what Pro adds") { showingPaywall = true }
                    .buttonStyle(.secondary)
            }
        }
    }

    private func recruitingCard(_ current: AthleteReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper(value: Binding(get: { details.graduationYear ?? Calendar.current.component(.year, from: .now) + 1 },
                                   set: { details.graduationYear = $0 }), in: 2024...2040) {
                Text("Class of \(details.graduationYear.map(String.init) ?? "—")")
            }
            Stepper(value: Binding(get: { details.heightCm ?? 170 }, set: { details.heightCm = $0 }), in: 120...230) {
                Text("Height: \(details.heightCm.map { Measure.height(cm: $0) } ?? "—")")
            }
            TextField("School (optional)", text: Binding(get: { details.school ?? "" }, set: { details.school = $0.isEmpty ? nil : $0 }))
            TextField("Highlight video link (optional)", text: Binding(get: { details.highlights ?? "" }, set: { details.highlights = $0.isEmpty ? nil : $0 }))
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
            Text("Only in the file you share. Don't add a phone number or address.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
            if let pdf = ReportRenderer.pdf(ReportPage(report: current, recruiting: details), fileName: "AthleteOS profile.pdf") {
                ShareLink(item: pdf) { Label("Share profile (PDF)", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.primary)
            }
        }
        .foregroundStyle(AppTheme.ink)
        .padding(16)
        .glassSurface(cornerRadius: 18)
        .onChange(of: details) { _, new in RecruitingDetails.saved = new }
    }
    #endif
}
