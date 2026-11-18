import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - Emergency card

/// Allergies, medical notes and who to call — filled in together with a
/// parent. Kept on this phone only (never uploaded or backed up): the app,
/// the Watch and an optional Lock Screen widget show it to someone helping.
public struct EmergencyCard: Codable, Sendable, Equatable {
    public struct Contact: Codable, Sendable, Equatable, Identifiable, Hashable {
        public var id = UUID()
        public var name: String
        public var relation: String
        public var phone: String

        public init(name: String = "", relation: String = "", phone: String = "") {
            self.name = name
            self.relation = relation
            self.phone = phone
        }
    }

    public var name = ""
    public var allergies = ""
    public var medicalNotes = ""
    public var medications = ""
    public var contacts: [Contact] = []

    public init() {}

    public var isEmpty: Bool {
        name.isEmpty && allergies.isEmpty && medicalNotes.isEmpty && medications.isEmpty && contacts.allSatisfy { $0.phone.isEmpty }
    }

    /// File in the shared container so the widget can read it.
    static var fileURL: URL? { AppIdentifiers.sharedContainer?.appending(path: "emergency-card.json") }

    public static func load() -> EmergencyCard {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return EmergencyCard() }
        return (try? JSONDecoder().decode(EmergencyCard.self, from: data)) ?? EmergencyCard()
    }

    public func save() {
        guard let url = Self.fileURL else { return }
        if isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}

/// Me → Emergency card.
struct EmergencyCardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var card = EmergencyCard.load()
    @State private var editing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ScreenTitle("Emergency card", subtitle: "For someone helping you. Fill it in with a parent.")
                    if card.isEmpty && !editing {
                        Text("Nothing on it yet.").font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                    }
                    if editing {
                        EmergencyCardEditor(card: $card)
                    } else if !card.isEmpty {
                        EmergencyCardDisplay(card: card)
                    }
                    Button(editing ? "Save" : (card.isEmpty ? "Fill it in" : "Change")) {
                        if editing {
                            card.contacts.removeAll { $0.name.isEmpty && $0.phone.isEmpty }
                            card.save()
                            reloadWidgets()
                        }
                        editing.toggle()
                    }
                    .buttonStyle(.primary)
                    Text("Kept on this phone only — never uploaded or backed up. Add the Emergency widget to your Lock Screen so others can see it without unlocking. Also fill in Medical ID in Apple's Health app: emergency services can read that from the lock screen.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .containerRelativeFrame(.horizontal)
            }
            .appScreen()
            .toolbar { CloseToolbarItem { dismiss() } }
        }
    }

    private func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

struct EmergencyCardDisplay: View {
    let card: EmergencyCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !card.name.isEmpty { field("Name", card.name) }
            if !card.allergies.isEmpty { field("Allergies", card.allergies) }
            if !card.medications.isEmpty { field("Medications", card.medications) }
            if !card.medicalNotes.isEmpty { field("Medical notes", card.medicalNotes) }
            ForEach(card.contacts) { contact in
                field(contact.relation.isEmpty ? "Call" : "Call · \(contact.relation)", "\(contact.name)  \(contact.phone)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(AppTheme.secondaryText)
            Text(value).font(.body.weight(.semibold)).foregroundStyle(AppTheme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct EmergencyCardEditor: View {
    @Binding var card: EmergencyCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            input("Name", text: $card.name)
            input("Allergies (e.g. peanuts, penicillin)", text: $card.allergies)
            input("Medications", text: $card.medications)
            input("Medical notes (e.g. asthma, inhaler in bag)", text: $card.medicalNotes)
            Text("Who to call").font(.headline).foregroundStyle(AppTheme.ink)
            ForEach($card.contacts) { $contact in
                VStack(spacing: 8) {
                    input("Name", text: $contact.name)
                    input("Relation (e.g. Mom)", text: $contact.relation)
                    input("Phone", text: $contact.phone)
                }
                .padding(.bottom, 6)
            }
            if card.contacts.count < 3 {
                Button("Add a contact") { card.contacts.append(EmergencyCard.Contact()) }
                    .buttonStyle(.secondary)
            }
        }
    }

    private func input(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .padding(14)
            .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
    }
}

// MARK: - Season review

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

struct SeasonReviewSheet: View {
    let athlete: Athlete
    let sport: AthleteSport
    let sessions: [Session]
    @Environment(\.dismiss) private var dismiss
    @State private var learned = ""
    @State private var enjoyed: Set<String> = []
    @State private var tooMuch: Set<String> = []
    @State private var next = ""

    private var seasonSessions: [Session] { sessions.filter { $0.startedAt >= sport.seasonStart && $0.startedAt <= sport.seasonEnd.addingTimeInterval(86_400) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ScreenTitle("Your season", subtitle: "\(allSportsBySlug[sport.sportSlug]?.name ?? "Your sport") · what it was like for you.")
                    HStack(spacing: 10) {
                        figure("\(seasonSessions.count)", "workouts")
                        figure("\(seasonSessions.reduce(0) { $0 + $1.minutes } / 60) h", "trained")
                        figure("\(PracticeLogStore.logs.filter { $0.day >= DayKey.of(sport.seasonStart) && $0.day <= DayKey.of(sport.seasonEnd) }.count)", "practices logged")
                    }
                    question("What did you learn this season?", text: $learned, hint: "One thing is plenty.")
                    chips("What did you enjoy?", SeasonReviewStore.enjoyedOptions, $enjoyed)
                    chips("What felt like too much?", SeasonReviewStore.tooMuchOptions, $tooMuch)
                    question("What do you want next?", text: $next, hint: "A goal, a break, another sport — anything.")
                    Button("Save my review") {
                        SeasonReviewStore.save(SeasonReview(season: SeasonReviewStore.season(for: sport), learned: learned.trimmingCharacters(in: .whitespacesAndNewlines),
                                                            enjoyed: SeasonReviewStore.enjoyedOptions.filter { enjoyed.contains($0) },
                                                            tooMuch: SeasonReviewStore.tooMuchOptions.filter { tooMuch.contains($0) },
                                                            next: next.trimmingCharacters(in: .whitespacesAndNewlines), writtenAt: .now))
                        dismiss()
                    }
                    .buttonStyle(.primary)
                    Text("Private: only you see it. A season counts as a success when you stayed healthy and want to carry on — not only when you won.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .containerRelativeFrame(.horizontal)
            }
            .appScreen()
            .toolbar { CloseToolbarItem { dismiss() } }
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.bold)).foregroundStyle(AppTheme.ink)
            Text(label).font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 12)
    }

    private func question(_ title: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(AppTheme.ink)
            TextField(hint, text: text, axis: .vertical)
                .lineLimit(2...5)
                .padding(14)
                .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        }
    }

    private func chips(_ title: String, _ options: [String], _ selection: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(AppTheme.ink)
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
}
