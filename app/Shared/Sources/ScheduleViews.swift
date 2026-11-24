import SwiftData
import SwiftUI

/// "Your schedule": connected team and school calendars, practice days and
/// exam weeks — everything the week is built around, on one screen.
struct ScheduleSheet: View {
    let athlete: Athlete
    let onChanged: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var feeds = ScheduleStore.feeds
    @State private var imported = ScheduleStore.imported
    @State private var practiceDays = PracticeSchedule.weekdays
    @State private var examThisWeek = ScheduleStore.isManualExamWeek(.now)
    @State private var examNextWeek = ScheduleStore.isManualExamWeek(Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now)
    @State private var addingCalendar = false
    @State private var showingPaywall = false
    @State private var editingPracticeDays = false
    @State private var feedPendingRemoval: CalendarFeed?
    @State private var refreshing = false
    @State private var extras = ExtraPractices.all
    @State private var addingTraining = false
    @AppStorage(GameTime.usualStartKey) private var gameStartMinutes = GameTime.defaultUsualMinutes

    private var calendar: Calendar { .current }
    private var nextWeek: Date { calendar.date(byAdding: .day, value: 7, to: .now) ?? .now }

    private var upcoming: [ScheduleEvent] {
        let today = calendar.startOfDay(for: .now)
        return imported.events.filter { $0.start >= today && $0.kind != .other }.prefix(8).map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    calendarsSection
                    practiceSection
                    extraTrainingSection
                    gameTimeSection
                    examsSection
                    SchoolHoursSection(onChanged: onChanged)
                    if !upcoming.isEmpty { upcomingSection }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
            .appScreen()
            .toolbar {
                CloseToolbarItem { dismiss() }
            }
            .proFeature(isPresented: $showingPaywall, athlete: athlete, feature: .moreCalendars)
            .sheet(isPresented: $addingCalendar) {
                AddCalendarSheet(sportName: AthleteStats.sportName(athlete)) { feed, events in
                    feeds.append(feed)
                    ScheduleStore.feeds = feeds
                    imported.byFeed[feed.id] = events
                    imported.fetchedAt = .now
                    ScheduleStore.imported = imported
                    CalendarSync.applyGames(imported, athlete: athlete, context: modelContext)
                    addingCalendar = false
                    onChanged()
                }
            }
            .sheet(isPresented: $addingTraining, onDismiss: { extras = ExtraPractices.all }) {
                ExtraPracticeSheet { onChanged() }
            }
            .sheet(isPresented: $editingPracticeDays) {
                PracticeDaysSheet(selection: practiceDays) { days in
                    PracticeSchedule.weekdays = days
                    practiceDays = days
                    editingPracticeDays = false
                    onChanged()
                }
            }
            .confirmationDialog(
                "Disconnect this calendar?", isPresented: Binding(
                    get: { feedPendingRemoval != nil }, set: { if !$0 { feedPendingRemoval = nil } }
                ), titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    if let feed = feedPendingRemoval { remove(feed) }
                    feedPendingRemoval = nil
                }
                Button("Cancel", role: .cancel) { feedPendingRemoval = nil }
            } message: {
                Text("Its upcoming games, practices and exams are removed from your plan. Games you added yourself stay.")
            }
        }
    }

    // MARK: - Header

    /// V8: the week this screen sets up, in one sentence; how it's used, small.
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your schedule")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.secondaryText)
            Headline(headlineParts, size: 30)
            Text("Short workouts after practice, gym on free days, nothing heavy before games, lighter weeks during exams.")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var headlineParts: [Headline.Part] {
        var parts: [Headline.Part] = [.soft("Built around ")]
        parts.append(.strong(practiceDays.isEmpty ? "no set practice days" : "practice \(practiceDayNames)"))
        let games = upcoming.filter { $0.kind == .game }.count
        if games > 0 {
            parts += [.soft(", "), .strong(games == 1 ? "1 game ahead" : "\(games) games ahead")]
        }
        if examThisWeek {
            parts += [.soft(" and "), .strong("exams this week")]
        } else if examNextWeek {
            parts += [.soft(" and "), .strong("exams next week")]
        }
        parts.append(.soft("."))
        return parts
    }

    // MARK: - Calendars

    private var calendarsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Team & school calendars", subtitle: "Connect a calendar link once. Games with their times, away trips, practices (and cancelled ones) and exams come in by themselves and stay up to date.")
            ForEach(feeds) { feed in
                feedRow(feed)
            }
            // One calendar is free; school + club + more is Pro.
            let canAdd = ProGate.canAddCalendar(isPro: ProAccess.isPro, calendarCount: feeds.count)
            Button { if canAdd { addingCalendar = true } else { showingPaywall = true } } label: {
                Label(feeds.isEmpty ? "Connect a calendar" : "Connect another calendar", systemImage: "link.badge.plus")
            }
            .buttonStyle(.primary)
            if !feeds.isEmpty {
                Button {
                    refreshing = true
                    Task {
                        await CalendarSync.refresh(athlete: athlete, context: modelContext, force: true)
                        imported = ScheduleStore.imported
                        refreshing = false
                        onChanged()
                    }
                } label: {
                    Label(refreshing ? "Updating…" : "Update now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.secondary)
                .disabled(refreshing)
            }
        }
    }

    private func feedRow(_ feed: CalendarFeed) -> some View {
        let events = (imported.byFeed[feed.id] ?? []).filter { !$0.cancelled }
        let games = events.filter { $0.kind == .game }
        let parts = [
            games.isEmpty ? nil : "\(games.count) games (\(games.filter(\.isAway).count) away)",
            events.contains { $0.kind == .practice } ? "\(events.filter { $0.kind == .practice }.count) practices" : nil,
            events.contains { $0.kind == .exam } ? "\(events.filter { $0.kind == .exam }.count) exams" : nil,
        ].compactMap { $0 }
        return HStack(spacing: 14) {
            Image(systemName: feed.role == .team ? "sportscourt.fill" : "graduationcap.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.brand)
                .frame(width: 48, height: 48)
                .background(AppTheme.brand.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(feed.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(parts.isEmpty ? "Nothing found yet in the next months" : parts.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                if let fetched = imported.fetchedAt {
                    Text("Updated \(fetched.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
            Spacer(minLength: 0)
            Button { feedPendingRemoval = feed } label: {
                Image(systemName: "trash")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.red)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.red.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Disconnect \(feed.name)")
        }
        .cardStyle(padding: 14)
    }

    private func remove(_ feed: CalendarFeed) {
        feeds.removeAll { $0.id == feed.id }
        ScheduleStore.feeds = feeds
        imported.byFeed[feed.id] = nil
        ScheduleStore.imported = imported
        CalendarSync.applyGames(imported, athlete: athlete, context: modelContext)
        onChanged()
    }

    // MARK: - Practice

    private var practiceSection: some View {
        let fromCalendar = imported.events.contains { $0.kind == .practice }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Practice days", subtitle: fromCalendar
                ? "Your team calendar sets practice days and times — a cancelled practice turns that day into a gym day. These days are used for weeks the calendar has no practices in."
                : "Days with team practice get a short after-practice workout; gym sessions go on the other days.")
            Button { editingPracticeDays = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "calendar")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 48, height: 48)
                        .background(AppTheme.fill, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(practiceDays.isEmpty ? "Set my practice days" : practiceDayNames)
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        Text("Tap to change")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .cardStyle(padding: 14)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Extra trainings

    /// One-off team sessions (a weekend training, a camp day): each counts
    /// as a practice day, so the gym workout moves off it.
    private var extraTrainingSection: some View {
        let today = DayKey.of(.now, calendar: calendar)
        let coming = extras.filter { $0.day >= today }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Extra trainings", subtitle: "A one-off team session counts as a practice day.")
            if !coming.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(coming.enumerated()), id: \.element.id) { index, extra in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(extra.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)
                                Text([dayLabel(extra.day), extra.time?.label].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                            Spacer(minLength: 0)
                            Button {
                                ExtraPractices.all = ExtraPractices.all.filter { $0.id != extra.id }
                                extras = ExtraPractices.all
                                onChanged()
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(extra.title)")
                        }
                        if index < coming.count - 1 { Divider().overlay(AppTheme.hairline) }
                    }
                }
                .cardStyle(padding: 14)
            }
            Button { addingTraining = true } label: { Label("Add a training", systemImage: "plus") }
                .buttonStyle(.secondary)
        }
    }

    /// "2026-11-21" → "Sat, Nov 21".
    private func dayLabel(_ key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return key }
        return date.formatted(.dateTime.weekday(.abbreviated).month().day())
    }

    // MARK: - Game time

    /// Games from a calendar without a clock time (and games added by hand)
    /// start at this time: Home's game day and the reminders count from it.
    private var gameTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Usual game start", subtitle: "Used when a game has no time of its own.")
            DatePicker("Usual game start", selection: gameStartBinding, displayedComponents: .hourAndMinute)
                .tint(AppTheme.accent)
                .cardStyle(padding: 14)
                .onChange(of: gameStartMinutes) { onChanged() }
        }
    }

    private var gameStartBinding: Binding<Date> {
        Binding(
            get: {
                calendar.date(bySettingHour: gameStartMinutes / 60, minute: gameStartMinutes % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                gameStartMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private var practiceDayNames: String {
        let symbols = calendar.shortWeekdaySymbols
        // Monday first.
        return practiceDays.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }.map { symbols[($0 - 1) % 7] }.joined(separator: ", ")
    }

    // MARK: - Exams

    private var examsSection: some View {
        let calendarExams = imported.events.filter { $0.kind == .exam && !$0.cancelled && $0.start >= calendar.startOfDay(for: .now) }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Exams", subtitle: "Exam weeks get at most two shorter gym sessions, so you keep your strength and still have time to study and sleep.")
            examToggle("Exams this week", isOn: $examThisWeek, week: .now)
            examToggle("Exams next week", isOn: $examNextWeek, week: nextWeek)
            if !calendarExams.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("From your school calendar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                    ForEach(calendarExams.prefix(4)) { exam in
                        Label("\(exam.title) · \(exam.start.formatted(.dateTime.weekday(.abbreviated).month().day()))", systemImage: "book.closed.fill")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle(padding: 14)
            }
        }
    }

    private func examToggle(_ title: String, isOn: Binding<Bool>, week: Date) -> some View {
        Toggle(isOn: Binding(
            get: { isOn.wrappedValue },
            set: { value in
                isOn.wrappedValue = value
                ScheduleStore.setManualExamWeek(week, value)
                onChanged()
            }
        )) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
        }
        .tint(AppTheme.accent)
        .padding(.vertical, 6)
        .cardStyle(padding: 14)
    }

    // MARK: - Coming up

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Coming up from your calendars")
            VStack(spacing: 0) {
                ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, event in
                    ScheduleEventRow(event: event)
                    if index < upcoming.count - 1 { Divider().overlay(AppTheme.hairline) }
                }
            }
            .cardStyle(padding: 14)
        }
    }
}

/// One calendar event: what it is, when, and home/away or cancelled.
struct ScheduleEventRow: View {
    let event: ScheduleEvent

    private var icon: String {
        switch event.kind {
        case .game: "sportscourt.fill"
        case .practice: "figure.run"
        case .exam: "book.closed.fill"
        case .other: "calendar"
        }
    }

    private var when: String {
        event.allDay
            ? event.start.formatted(.dateTime.weekday(.wide).month().day())
            : event.start.formatted(.dateTime.weekday(.wide).month().day().hour().minute())
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(event.cancelled ? AppTheme.secondaryText : AppTheme.brand)
                .frame(width: 36, height: 36)
                .background((event.cancelled ? AppTheme.fill : AppTheme.brand.opacity(0.12)), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(event.cancelled ? AppTheme.secondaryText : AppTheme.ink)
                    .strikethrough(event.cancelled)
                Text(when)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            Spacer(minLength: 0)
            if event.cancelled {
                Tag("Cancelled", color: AppTheme.red)
            } else if event.kind == .game {
                Tag(event.isAway ? "Away" : "Home", color: event.isAway ? AppTheme.orange : AppTheme.green)
            }
        }
        .padding(.vertical, 8)
    }
}

/// Connect a calendar by link, with plain steps for where to find it.
struct AddCalendarSheet: View {
    let sportName: String
    let onAdd: (CalendarFeed, [ScheduleEvent]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var role: CalendarFeed.Role = .team
    @State private var link = ""
    @State private var checking = false
    @State private var found: [ScheduleEvent]?
    /// The calendar that was checked: its events carry its id.
    @State private var checkedFeed: CalendarFeed?
    @State private var errorMessage: String?
    @State private var openGuide: Guide?
    /// Calendars on this phone (nil: not looked yet).
    @State private var phoneChoices: [PhoneCalendars.Choice]?
    @State private var phoneDenied = false

    enum Guide: String, CaseIterable, Identifiable {
        case teamSnap, gameChanger, sportsEngine, school, google, apple, hudl
        var id: String { rawValue }
        var title: String {
            switch self {
            case .teamSnap: "TeamSnap"
            case .gameChanger: "GameChanger"
            case .sportsEngine: "SportsEngine"
            case .school: "School or league website"
            case .google: "Google Calendar"
            case .apple: "Apple Calendar (iCloud)"
            case .hudl: "Hudl"
            }
        }
        var steps: [String] {
            switch self {
            case .teamSnap: [
                "Open TeamSnap and go to your team's Schedule.",
                "Tap the share or export button and choose \"Sync to calendar\" / \"Subscribe\".",
                "Copy the calendar link (it starts with webcal:// or https://) and paste it here.",
            ]
            case .gameChanger: [
                "Open GameChanger and go to your team's Schedule.",
                "Look for \"Sync\" or \"Subscribe to calendar\" — it gives a calendar link.",
                "Copy that link and paste it here. New games and changes come in by themselves.",
            ]
            case .sportsEngine: [
                "Open your team's page in SportsEngine (app or website) and go to Schedule.",
                "Tap \"Subscribe\" or \"Sync calendar\" and copy the iCal / webcal link.",
                "Paste it here.",
            ]
            case .school: [
                "Most school and league athletics sites (rSchoolToday, ArbiterLive, MaxPreps, school websites) have a calendar with a \"Subscribe\", \"iCal\" or \"Sync\" button.",
                "Copy the link it gives (it ends in .ics or starts with webcal://).",
                "Paste it here as your team or school calendar.",
            ]
            case .hudl: [
                "Hudl doesn't publish a calendar link, so it can't be connected.",
                "If your team also uses TeamSnap, GameChanger, SportsEngine or a school calendar, connect that instead.",
                "Otherwise add games by hand: the trophy on Home → Add a game.",
            ]
            case .google: [
                "On a computer, open calendar.google.com and point at the team or school calendar.",
                "Click ⋮ → Settings and sharing, scroll to \"Integrate calendar\".",
                "Copy \"Secret address in iCal format\" (ends in .ics) and paste it here.",
            ]
            case .apple: [
                "In the Calendar app, tap Calendars and the ⓘ next to the team or school calendar.",
                "Turn on \"Public Calendar\" and tap \"Share Link…\" → Copy.",
                "Paste the link (it starts with webcal://) here.",
            ]
            }
        }
    }

    private var feedName: String { role == .team ? (sportName.isEmpty ? "Team calendar" : "\(sportName) team") : "School calendar" }

    var body: some View {
        StepScaffold(
            title: "Connect a calendar",
            subtitle: "Paste the link to your team's or school's calendar. We only read it — nothing is ever changed or shared.",
            buttonTitle: found == nil ? (checking ? "Checking…" : "Check the link") : "Connect",
            buttonEnabled: !checking && (CalendarFeed.normalizedURL(link) != nil || (found != nil && checkedFeed.map(PhoneCalendars.isPhone) == true)),
            onClose: { dismiss() },
            onContinue: {
                if let found, let checkedFeed, checkedFeed.url == link || PhoneCalendars.isPhone(checkedFeed), checkedFeed.role == role {
                    onAdd(checkedFeed, found)
                } else {
                    check()
                }
            }
        ) {
            VStack(spacing: 10) {
                Button { role = .team; found = nil } label: {
                    OptionRow(title: "Team calendar", subtitle: "Games, away trips and practices", systemImage: "sportscourt.fill", isSelected: role == .team)
                }
                .buttonStyle(.plain)
                Button { role = .school; found = nil } label: {
                    OptionRow(title: "School calendar", subtitle: "Exams and tests", systemImage: "graduationcap.fill", isSelected: role == .school)
                }
                .buttonStyle(.plain)
            }

            phoneSection

            VStack(alignment: .leading, spacing: 8) {
                Text(phoneChoices?.isEmpty == false ? "Or paste a calendar link" : "Calendar link")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                TextField("webcal://… or https://…", text: $link)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .font(.body)
                    .padding(16)
                    .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .onChange(of: link) { found = nil; errorMessage = nil }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.red)
            }
            if let found {
                foundSummary(found)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Where do I find the link?")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                ForEach(Guide.allCases) { guide in
                    guideCard(guide)
                }
            }
        }
    }

    /// The quickest way in: a team or school calendar that already syncs to this phone.
    @ViewBuilder
    private var phoneSection: some View {
        #if os(iOS)
        VStack(alignment: .leading, spacing: 10) {
            if let choices = phoneChoices {
                Text("Calendars on this phone")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                if choices.isEmpty {
                    Text(phoneDenied ? "AthleteOS can't read your calendars. Allow it in Settings → AthleteOS → Calendars, or paste a link below."
                                     : "No calendars on this phone yet. Paste a link below.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(choices) { choice in
                    Button { pickPhone(choice) } label: {
                        OptionRow(title: choice.title, subtitle: choice.account.isEmpty ? "On this phone" : choice.account,
                                  systemImage: "calendar", isSelected: checkedFeed?.url == PhoneCalendars.prefix + choice.id)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button { lookOnPhone() } label: {
                    OptionRow(title: "Pick a calendar on this phone",
                              subtitle: "TeamSnap, GameChanger, your school or Google often sync here already — no link needed",
                              systemImage: "iphone", isSelected: false)
                }
                .buttonStyle(.plain)
            }
        }
        #endif
    }

    private func lookOnPhone() {
        Task {
            let allowed = await PhoneCalendars.requestAccess()
            phoneDenied = !allowed
            phoneChoices = allowed ? PhoneCalendars.choices() : []
        }
    }

    private func pickPhone(_ choice: PhoneCalendars.Choice) {
        let feed = CalendarFeed(url: PhoneCalendars.prefix + choice.id, name: choice.title, role: role)
        checking = true
        errorMessage = nil
        link = ""
        Task {
            do {
                found = try await feed.fetchEvents()
                checkedFeed = feed
            } catch {
                errorMessage = "That calendar couldn't be read. Try another one, or paste its link."
            }
            checking = false
        }
    }

    private func foundSummary(_ events: [ScheduleEvent]) -> some View {
        let live = events.filter { !$0.cancelled }
        let games = live.filter { $0.kind == .game }
        let lines = [
            games.isEmpty ? nil : "\(games.count) games — \(games.filter(\.isAway).count) away",
            live.contains { $0.kind == .practice } ? "\(live.filter { $0.kind == .practice }.count) practices" : nil,
            live.contains { $0.kind == .exam } ? "\(live.filter { $0.kind == .exam }.count) exams" : nil,
        ].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 8) {
            Label(lines.isEmpty ? "The link works, but nothing is on it for the next months." : "Found in the next months:", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(AppTheme.green)
            ForEach(lines, id: \.self) { line in
                Text("• \(line)")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink)
            }
            Text("Tap Connect to build your plan around it.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 16)
    }

    private func guideCard(_ guide: Guide) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { openGuide = openGuide == guide ? nil : guide } label: {
                HStack {
                    Text(guide.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Image(systemName: openGuide == guide ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if openGuide == guide {
                ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.subheadline.bold())
                            .foregroundStyle(AppTheme.onAccent)
                            .frame(width: 26, height: 26)
                            .background(AppTheme.accent, in: Circle())
                        Text(step)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .cardStyle(padding: 14)
    }

    private func check() {
        let feed = CalendarFeed(url: link, name: feedName, role: role)
        checking = true
        errorMessage = nil
        Task {
            do {
                let events = try await feed.fetchEvents()
                found = events
                checkedFeed = feed
            } catch {
                errorMessage = "That link didn't open a calendar. Check it's the full calendar link (webcal://, or https://… ending in .ics) and that you're online."
            }
            checking = false
        }
    }
}

// MARK: - Extra training

/// A one-off team training (a weekend session, a camp day).
struct ExtraPracticeSheet: View {
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var title = "Team training"
    @State private var start = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now) ?? .now
    @State private var end = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now) ?? .now

    var body: some View {
        StepScaffold(title: "Add a training", subtitle: "An extra team session. It counts as a practice day, so your gym workout moves off it.",
                     onClose: { dismiss() }, onConfirm: save) {
            DatePicker("Day", selection: $date, displayedComponents: .date)
                .font(.headline)
                .tint(AppTheme.accent)
            TextField("What is it?", text: $title)
                .font(.title3)
                .padding(16)
                .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack {
                DatePicker("From", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("To", selection: $end, displayedComponents: .hourAndMinute)
            }
            .font(.subheadline.weight(.semibold))
            .tint(AppTheme.accent)
        }
    }

    private func save() {
        let calendar = Calendar.current
        func minutes(_ date: Date) -> Int { calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date) }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        ExtraPractices.all = ExtraPractices.all + [ExtraPractice(day: DayKey.of(date), title: trimmed.isEmpty ? "Team training" : trimmed,
                                                               time: PracticeTime(start: minutes(start), end: max(minutes(end), minutes(start) + 15)))]
        onSaved()
        dismiss()
    }
}
