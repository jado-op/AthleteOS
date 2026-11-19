import SwiftData
import SwiftUI

/// Me (a sheet from the profile button): the profile with the one streak,
/// Development Goals, then grouped menu cards whose rows open focused edit
/// sheets — training setup, health and safety, team and family, settings,
/// subscription, your data and the account. Trends, tests and exercise
/// progress live in the Academy (Progress → Trends, Performances).
struct MeView: View {
    let athlete: Athlete
    let onPlanInputsChanged: () -> Void
    /// Me opens as a sheet from the profile button; this closes it.
    var onClose: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @State private var activeSheet: MeSheet?
    @State private var showingDeleteConfirmation = false
    @State private var showingGuestDelete = false
    @State private var linking = false
    @State private var linkMessage: String?
    @State private var showingLogOutConfirmation = false
    @State private var isDeleting = false
    @State private var isLoggingOut = false
    @State private var accountProblem: AccountProblem?

    /// Something went wrong logging out or deleting — said plainly, with
    /// the one thing to do about it.
    enum AccountProblem: String, Identifiable {
        case notBackedUp, deleteFailed, notSignedIn
        var id: String { rawValue }
        var title: String {
            switch self {
            case .notBackedUp: "Not everything is backed up"
            case .deleteFailed: "Your account was NOT deleted"
            case .notSignedIn: "You're not signed in on this phone"
            }
        }
        var message: String {
            switch self {
            case .notBackedUp: "We couldn't reach the server, so your latest workouts and progress are only on this phone. Connect to the internet and try again — or log out anyway and lose what isn't backed up."
            case .deleteFailed: "We couldn't reach the server, so nothing was deleted. Connect to the internet and try again."
            case .notSignedIn: "Log out, sign in with Apple again, then delete your account."
            }
        }
    }

    private var apiClient: APIClient { APIClient(baseURL: AppConfig.backendBaseURL) }

    private func takePushRoute() {
        guard let raw = PushRoute.shared.meSheet else { return }
        PushRoute.shared.meSheet = nil
        if let sheet = MeSheet(rawValue: raw) { activeSheet = sheet }
    }

    enum MeSheet: String, Identifiable {
        case sport, season, equipment, experience, name, checkIns, dataExport, shared, reminders, health, sports, help, team, coach, parent, safety, struggles, schedule, decisions, emergency, suunto
        var id: String { rawValue }
    }

    private var athleteSport: AthleteSport? { athlete.activeSport }
    @AppStorage(WeightUnit.storageKey) private var weightUnitRaw = WeightUnit.current.rawValue
    private var sportInfo: SportInfo? { athleteSport.flatMap { allSportsBySlug[$0.sportSlug] } }
    private var positionName: String? {
        athleteSport?.positionSlug.flatMap { slug in sportInfo?.positions.first { $0.slug == slug }?.name }
    }
    private var age: Int {
        Calendar.current.dateComponents([.year], from: athlete.birthDate, to: .now).year ?? 0
    }
    private var phase: SeasonPhase? {
        athleteSport.map { PhaseCalculator.phase(today: .now, seasonStart: $0.seasonStart, seasonEnd: $0.seasonEnd) }
    }
    private var streak: Int {
        AthleteStats.streak(checkInDates: athlete.checkIns.map(\.date), sessionDates: sessions.map(\.startedAt))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    profileCard
                        .padding(.bottom, 16)
                    goalsCard

                    SectionHeader("Training setup")
                    menuCard {
                        menuRow(athlete.sports.count > 1 ? "Sports" : "Sport & position", icon: sportInfo.map { SportIcon.name(for: $0.slug) } ?? "sportscourt.fill", tint: AppTheme.brand,
                                detail: athlete.sports.count > 1
                                    ? "\(athlete.sports.count) sports"
                                    : [sportInfo?.name, positionName].compactMap { $0 }.joined(separator: " · ")) { activeSheet = .sports }
                        menuDivider
                        menuRow("Practice schedule", icon: "calendar.badge.clock", tint: AppTheme.orange,
                                detail: practiceDetail) { activeSheet = .schedule }
                        menuDivider
                        menuRow("Season dates", icon: "calendar", tint: AppTheme.ink,
                                detail: athlete.sports.count > 1 ? "\(sportInfo?.name ?? "") · \(seasonDetail)" : seasonDetail) { activeSheet = .season }
                        menuDivider
                        menuRow("Equipment", icon: "dumbbell.fill", tint: AppTheme.purple,
                                detail: athlete.equipmentAvailable.isEmpty ? "Bodyweight only" : "\(athlete.equipmentAvailable.count) items") { activeSheet = .equipment }
                        menuDivider
                        menuRow("Training experience", icon: "figure.strengthtraining.traditional", tint: AppTheme.coral,
                                detail: TrainingExperience.saved?.title ?? "Not set") { activeSheet = .experience }
                        menuDivider
                        coachToggleRow
                    }

                    SectionHeader("Health & safety")
                    menuCard {
                        menuRow("Apple Health", icon: "heart.fill", tint: AppTheme.red,
                                detail: !HealthKitManager.shared.isAvailable ? "Unavailable"
                                    : (UserDefaults.standard.bool(forKey: "healthPermissionAsked") ? "Set up" : "Connect")) { activeSheet = .health }
                        menuDivider
                        menuRow("Suunto", icon: "applewatch", tint: AuraTone.training.mark,
                                detail: SuuntoCloud.isConnected ? "Connected" : "Through Apple Health") { activeSheet = .suunto }
                        menuDivider
                        menuRow("Safety Center", icon: "cross.case.fill", tint: AppTheme.danger, detail: "Pain, head injury, illness") { activeSheet = .safety }
                        menuDivider
                        menuRow("Emergency card", icon: "staroflife.fill", tint: AppTheme.danger, detail: "Allergies, who to call") { activeSheet = .emergency }
                        menuDivider
                        menuRow("How AthleteOS decides", icon: "list.bullet.rectangle", tint: AppTheme.ink, detail: "Rules and sources") { activeSheet = .decisions }
                    }

                    SectionHeader("Team & family")
                    menuCard {
                        menuRow("My team", icon: "person.3.fill", tint: AppTheme.brand, detail: "Join with a code") { activeSheet = .team }
                        menuDivider
                        menuRow("Parent summary", icon: "house.fill", tint: AppTheme.green, detail: "Weekly") { activeSheet = .parent }
                        menuDivider
                        menuRow("Coach mode", icon: "whistle.fill", tint: AppTheme.orange, detail: "For coaches") { activeSheet = .coach }
                    }

                    SectionHeader("Settings")
                    menuCard {
                        menuRow("Help & app tour", icon: "questionmark.circle.fill", tint: AppTheme.ink, detail: "") { activeSheet = .help }
                        menuDivider
                        menuRow("Reminders", icon: "bell.fill", tint: AppTheme.amber,
                                detail: ReminderScheduler.settings.anyEnabled ? "On" : "Off") { activeSheet = .reminders }
                        menuDivider
                        menuRow("Weight units", icon: "scalemass.fill", tint: AppTheme.ink,
                                detail: weightUnitRaw == WeightUnit.lb.rawValue ? "lb · tap for kg" : "kg · tap for lb") {
                            weightUnitRaw = weightUnitRaw == WeightUnit.lb.rawValue ? WeightUnit.kg.rawValue : WeightUnit.lb.rawValue
                        }
                    }

                    #if os(iOS) && !APP_EXTENSION
                    SectionHeader("Subscription")
                    SubscriptionRow(athlete: athlete)
                        .cardStyle(padding: 16)
                    #endif

                    SectionHeader("Your data", subtitle: "It's yours: export it any time.")
                    menuCard {
                        menuRow("Export my data", icon: "square.and.arrow.up", tint: AppTheme.green, detail: "JSON") { activeSheet = .dataExport }
                        menuDivider
                        menuRow("Shared workouts", icon: "qrcode", tint: AppTheme.ink, detail: "Stop sharing") { activeSheet = .shared }
                        menuDivider
                        HStack(spacing: 14) {
                            menuIcon("icloud.fill", tint: AppTheme.blue)
                            Text("Backed up online")
                                .font(.body)
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            let pending = sessions.filter { $0.syncedAt == nil }.count + athlete.checkIns.filter { $0.syncedAt == nil }.count
                            Text(pending == 0 ? "All saved" : "\(pending) waiting to upload")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                        .padding(.vertical, 12)
                    }

                    SectionHeader("About")
                    menuCard {
                        linkRow("Privacy policy", icon: "hand.raised.fill", url: AppConfig.backendBaseURL.appending(path: "privacy"))
                        menuDivider
                        linkRow("Terms of use", icon: "doc.text.fill", url: AppConfig.backendBaseURL.appending(path: "terms"))
                        menuDivider
                        linkRow("Support", icon: "questionmark.circle.fill", url: AppConfig.backendBaseURL.appending(path: "support"))
                    }

                    if athlete.isGuest {
                        guestAccount
                    } else {
                    SectionHeader("Account", subtitle: "Logging out keeps your account, backed up online. Deleting removes it for good.")
                    Button {
                        showingLogOutConfirmation = true
                    } label: {
                        Text(isLoggingOut ? "Backing up and logging out…" : "Log out")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(AppTheme.fill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoggingOut || isDeleting)

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Text(isDeleting ? "Deleting…" : "Delete account")
                            .font(.headline)
                            .foregroundStyle(AppTheme.red)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(AppTheme.red.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoggingOut || isDeleting)
                    }

                    Text("AthleteOS \(BuildEvidence().version) (\(BuildEvidence().build))")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                // Exactly as wide as the screen, so nothing on it (a chart's
                // axis labels, big text) can make the page drift sideways.
                .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .appScreen(.hero, sportSlug: athleteSport?.sportSlug)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                if DemoData.initialTab == .me, let name = DemoData.initialSheet { activeSheet = MeSheet(rawValue: name) }
            }
            .onChange(of: activeSheet) { _, sheet in
                if let sheet { UsageCounts.count("me.\(sheet.rawValue)") }
            }
            // A tapped notification about a team or its health notes.
            .onAppear(perform: takePushRoute)

            .onChange(of: PushRoute.shared.meSheet) { takePushRoute() }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .sport: SportEditorSheet(athlete: athlete, onSaved: onPlanInputsChanged)
                case .season: SeasonEditorSheet(athlete: athlete, onSaved: onPlanInputsChanged)
                case .equipment: EquipmentEditorSheet(athlete: athlete, onSaved: onPlanInputsChanged)
                case .experience: ExperienceEditorSheet(onSaved: onPlanInputsChanged)
                case .name: NameEditorSheet(athlete: athlete)
                case .checkIns: CheckInHistoryView(checkIns: athlete.checkIns)
                case .dataExport: DataExportView(athlete: athlete, sessions: sessions)
                case .shared: SharedByMeView()
                case .reminders: RemindersSheet(athlete: athlete)
                case .health: HealthPermissionView()
                case .sports: SportsManagerSheet(athlete: athlete, onChanged: onPlanInputsChanged)
                case .help: HelpCenterView()
                case .team: MyTeamView()
                case .coach: CoachView()
                case .parent: ParentSummaryView()
                case .safety: SafetyCenterView()
                case .struggles: StrugglesSheet(onSaved: onPlanInputsChanged)
                case .decisions: DecisionsView()
                case .emergency: EmergencyCardView()
                case .schedule: ScheduleSheet(athlete: athlete, onChanged: onPlanInputsChanged)
                case .suunto: SuuntoView(sportSlug: athlete.activeSport?.sportSlug, birthDate: athlete.birthDate)
                }
            }
            .confirmationDialog("Delete your account?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { deleteAccount() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account, everything backed up on our server and everything on this phone, and removes AthleteOS from your Apple ID's Sign in with Apple list. It can't be undone.")
            }
            .confirmationDialog("Log out?", isPresented: $showingLogOutConfirmation, titleVisibility: .visible) {
                Button("Log out") { logOut(force: false) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("We back everything up first, then remove it from this phone. Sign in with Apple again — on this or any phone — to get it all back.")
            }
            .alert(
                accountProblem?.title ?? "", isPresented: Binding(
                    get: { accountProblem != nil }, set: { if !$0 { accountProblem = nil } }
                ), presenting: accountProblem
            ) { problem in
                if problem == .notBackedUp {
                    Button("Log out anyway", role: .destructive) { logOut(force: true) }
                    Button("Stay logged in", role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: { problem in
                Text(problem.message)
            }
        }
    }

    private var practiceDetail: String {
        guard PracticeSchedule.isSet else { return "Not set" }
        let symbols = Calendar.current.shortWeekdaySymbols
        let days = [2, 3, 4, 5, 6, 7, 1].filter { PracticeSchedule.weekdays.contains($0) }.map { symbols[$0 - 1] }
        return days.isEmpty ? "From your calendar" : days.joined(separator: ", ")
    }

    private var seasonDetail: String {
        guard let athleteSport else { return "" }
        return "\(athleteSport.seasonStart.formatted(.dateTime.month(.abbreviated).day())) – \(athleteSport.seasonEnd.formatted(.dateTime.month(.abbreviated).day()))"
    }

    // MARK: - Profile

    /// V8: the name big, then one sentence that says who this athlete is
    /// right now (sport, position, age, season); the one streak quietly under it.
    private var profileCard: some View {
        let hasName = athlete.displayName?.isEmpty == false
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                Text("Athlete profile")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedText)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    activeSheet = .sport
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 44, height: 44)
                        .glassCapsule()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit sport and position")
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                            .frame(width: 44, height: 44)
                            .glassCapsule()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
            }
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Button { activeSheet = .name } label: {
                        Text(athlete.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? "Add your name")
                            .font(.system(size: hasName ? 48 : 30, weight: .bold))
                            .foregroundStyle(hasName ? AppTheme.ink : AppTheme.secondaryText)
                            .lineLimit(2)
                            .minimumScaleFactor(0.6)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edit your first name")
                    Headline(profileLine, size: 22)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // The one streak (rest never breaks it), there quietly.
            Text(streak == 1 ? "1-day streak · rest days never break it" : "\(streak)-day streak · rest days never break it")
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(.top, 8)
    }

    /// "Soccer · goalkeeper · 16. In-season." — the strong words white.
    private var profileLine: [Headline.Part] {
        var parts: [Headline.Part] = []
        if let name = sportInfo?.name { parts.append(.strong(name)) }
        if let positionName { parts.append(.soft(parts.isEmpty ? positionName : " · \(positionName)")) }
        parts.append(.soft(parts.isEmpty ? "Age \(age). " : " · \(age). "))
        parts.append(.strong(AthleteStats.phaseLabel(phase)))
        parts.append(.soft("."))
        return parts
    }

    /// My Development Goals: what the plan leans towards.
    private var goalsCard: some View {
        Button { activeSheet = .struggles } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("My Development Goals")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Text("Edit")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                }
                let goals = Struggles.selected
                if goals.isEmpty {
                    Text("Choose what you want to develop. Your training leans towards it.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                } else {
                    FlowChips(goals.map(\.title))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle(padding: 20)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Menu rows

    private func menuCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .cardStyle(padding: 16)
    }

    private var menuDivider: some View {
        Divider().overlay(AppTheme.hairline).padding(.leading, 50)
    }

    private func menuIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func menuRow(_ title: String, icon: String, tint: Color, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                menuIcon(icon, tint: tint)
                Text(title)
                    .font(.body)
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func linkRow(_ title: String, icon: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 14) {
                menuIcon(icon, tint: AppTheme.secondaryText)
                Text(title)
                    .font(.body)
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(.vertical, 12)
        }
    }

    private var coachToggleRow: some View {
        Toggle(isOn: Binding(
            get: { athlete.trainsUnderCoach },
            set: { newValue in
                athlete.trainsUnderCoach = newValue
                try? modelContext.save()
                onPlanInputsChanged()
            }
        )) {
            HStack(spacing: 14) {
                menuIcon("person.2.fill", tint: AppTheme.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Train under a coach")
                        .font(.body)
                        .foregroundStyle(AppTheme.ink)
                    Text("Unlocks coached lifts")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .tint(AppTheme.green)
        .padding(.vertical, 8)
    }

    // MARK: - No account yet

    /// Using the app without an account: what signing in adds, the button,
    /// and deleting everything on this phone.
    private var guestAccount: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Account", subtitle: "You're using AthleteOS without an account — everything is on this phone only.")
            VStack(alignment: .leading, spacing: 10) {
                Text("Sign in to back up everything, use it on a new phone, join your coach's team, send a parent summary and share workouts.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let linkMessage {
                    Text(linkMessage).font(.footnote.weight(.semibold)).foregroundStyle(AppTheme.red)
                }
                if linking {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 56)
                } else {
                    AppleSignInButton(
                        onSuccess: { identityToken, rawNonce, authorizationCode in
                            linkAccount(identityToken: identityToken, rawNonce: rawNonce, authorizationCode: authorizationCode)
                        },
                        onFailure: { _ in linkMessage = "Sign in didn't finish — try again." }
                    )
                    .frame(height: 56)
                    .clipShape(Capsule())
                }
            }
            .cardStyle(padding: 16)
            Button(role: .destructive) {
                showingGuestDelete = true
            } label: {
                Text("Delete all my data")
                    .font(.headline)
                    .foregroundStyle(AppTheme.red)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(AppTheme.red.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .confirmationDialog("Delete everything on this phone?", isPresented: $showingGuestDelete, titleVisibility: .visible) {
                Button("Delete all my data", role: .destructive) {
                    let context = modelContext
                    Task { await LocalWipe.wipe(context: context) }
                }
            } message: {
                Text("Without an account nothing is backed up, so this can't be undone.")
            }
        }
    }

    /// Signs a guest in: the account is created with this phone's data (a
    /// new account keeps the same id), then everything is backed up — or, for
    /// an existing account, merged with what's already there.
    private func linkAccount(identityToken: String, rawNonce: String, authorizationCode: String?) {
        linking = true
        linkMessage = nil
        let context = modelContext
        let client = apiClient
        Task {
            do {
                let response = try await client.signInWithApple(
                    identityToken: identityToken, rawNonce: rawNonce, birthDate: athlete.birthDate,
                    authorizationCode: authorizationCode, athleteId: athlete.id
                )
                try? KeychainTokenStore().save(response.sessionToken)
                athlete.id = response.athlete.id
                athlete.appleUserId = response.athlete.appleUserId
                try? context.save()
                await CloudSync.sync(athlete: athlete, context: context, apiClient: client)
                await CloudSync.restoreRows(athlete: athlete, context: context, apiClient: client, full: true)
                linking = false
            } catch {
                linking = false
                linkMessage = "Couldn't sign in — check your connection and try again."
            }
        }
    }

    // MARK: - Delete

    /// Backs everything up, then removes it from this phone. If the backup
    /// can't finish, the athlete decides whether to lose what's only here.
    private func logOut(force: Bool) {
        isLoggingOut = true
        let context = modelContext
        let client = apiClient
        Task {
            if !force {
                let queue = SyncQueue(apiClient: client, tokenStore: KeychainTokenStore(), modelContext: context)
                let sessions = await queue.drainPendingSessions()
                let checkIns = await queue.drainPendingCheckIns()
                let backedUp = await CloudSync.sync(athlete: athlete, context: context, apiClient: client)
                guard backedUp, sessions.failed == 0, checkIns.failed == 0 else {
                    isLoggingOut = false
                    accountProblem = .notBackedUp
                    return
                }
            }
            await LocalWipe.wipe(context: context)
            isLoggingOut = false
        }
    }

    /// Deletes the account on the server first — which also revokes Sign in
    /// with Apple — and only then wipes this phone. If the server can't be
    /// reached, nothing is deleted and the athlete is told so.
    private func deleteAccount() {
        isDeleting = true
        let context = modelContext
        let client = apiClient
        Task {
            guard let token = try? KeychainTokenStore().read() else {
                isDeleting = false
                accountProblem = .notSignedIn
                return
            }
            do {
                try await client.deleteAccount(sessionToken: token)
            } catch APIClient.APIError.http(status: 401, _) {
                isDeleting = false
                accountProblem = .notSignedIn
                return
            } catch {
                isDeleting = false
                accountProblem = .deleteFailed
                return
            }
            await LocalWipe.wipe(context: context)
            isDeleting = false
        }
    }
}

// MARK: - Editors

struct SportEditorSheet: View {
    let athlete: Athlete
    let onSaved: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var sportSlug: String?
    @State private var positionSlug: String?
    @State private var formatSlug: String?
    @State private var choosingPosition = false

    private var sport: SportInfo? { sportSlug.flatMap { allSportsBySlug[$0] } }

    var body: some View {
        Group {
            if choosingPosition, let sport {
                StepScaffold(title: sport.positions.isEmpty ? "How you play" : "Position", subtitle: sport.name, onBack: { choosingPosition = false }, onConfirm: save) {
                    PositionChooser(sport: sport, selection: $positionSlug, format: $formatSlug)
                }
            } else {
                StepScaffold(title: "Your sport", buttonTitle: sport?.hasRoleChoice == true ? "Next" : "Save", buttonEnabled: sportSlug != nil,
                             onClose: { dismiss() }, onContinue: {
                    if sport?.hasRoleChoice == true {
                        if sportSlug != athlete.activeSport?.sportSlug { positionSlug = nil; formatSlug = nil }
                        choosingPosition = true
                    } else {
                        positionSlug = nil
                        formatSlug = nil
                        save()
                    }
                }) {
                    SportChooser(selection: $sportSlug)
                }
            }
        }
        .onAppear {
            sportSlug = athlete.activeSport?.sportSlug
            positionSlug = athlete.activeSport?.positionSlug
            formatSlug = athlete.activeSport?.formatSlug
        }
    }

    private func save() {
        guard let sport else { return }
        if let existing = athlete.activeSport {
            if existing.sportSlug != sport.slug {
                let defaults = SeasonDefaults.dates(for: sport)
                existing.seasonStart = defaults.start
                existing.seasonEnd = defaults.end
            }
            existing.sportSlug = sport.slug
            existing.positionSlug = positionSlug
            existing.formatSlug = formatSlug
        } else {
            let defaults = SeasonDefaults.dates(for: sport)
            modelContext.insert(AthleteSport(sportSlug: sport.slug, positionSlug: positionSlug, formatSlug: formatSlug, seasonStart: defaults.start, seasonEnd: defaults.end, isPrimary: true, athlete: athlete))
        }
        try? modelContext.save()
        let slug = sport.slug
        Task { await SportPackInstaller.install(slug: slug, context: modelContext) }
        onSaved()
        dismiss()
    }
}

struct SeasonEditorSheet: View {
    let athlete: Athlete
    let onSaved: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date.now
    @State private var end = Date.now

    var body: some View {
        StepScaffold(title: "Season dates", subtitle: "Your plan changes through the season — getting stronger before it, staying fresh during it, recovering after — based on these dates.", 
                     onClose: { dismiss() }, onConfirm: save) {
            SeasonEditor(start: $start, end: $end)
        }
        .onAppear {
            start = athlete.activeSport?.seasonStart ?? .now
            end = athlete.activeSport?.seasonEnd ?? .now
        }
    }

    private func save() {
        athlete.activeSport?.seasonStart = start
        athlete.activeSport?.seasonEnd = max(start, end)
        try? modelContext.save()
        onSaved()
        dismiss()
    }
}

struct EquipmentEditorSheet: View {
    let athlete: Athlete
    let onSaved: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<String> = []

    var body: some View {
        StepScaffold(title: "Equipment", subtitle: "Your plan only ever uses what you pick here.", 
                     onClose: { dismiss() }, onConfirm: save) {
            EquipmentChooser(selection: $selection)
        }
        .onAppear { selection = Set(athlete.equipmentAvailable) }
    }

    private func save() {
        athlete.equipmentAvailable = Array(selection).sorted()
        try? modelContext.save()
        onSaved()
        dismiss()
    }
}

/// How long the athlete has been lifting: changes sets, reps and jumps.
struct ExperienceEditorSheet: View {
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: TrainingExperience = .current

    var body: some View {
        StepScaffold(title: "Training experience", subtitle: "Your plan's sets, reps and jumps follow this.", 
                     onClose: { dismiss() }, onConfirm: save) {
            VStack(spacing: 10) {
                ForEach(TrainingExperience.allCases, id: \.self) { level in
                    Button { selection = level } label: {
                        OptionRow(title: level.title, subtitle: level.detail, isSelected: selection == level)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func save() {
        TrainingExperience.saved = selection
        onSaved()
        dismiss()
    }
}

/// An optional first name, only for the greeting on Home. It stays on this
/// phone: it isn't backed up or sent anywhere.
struct NameEditorSheet: View {
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        StepScaffold(title: "Your first name", subtitle: "Optional. Only used to greet you, and it stays on this phone.",
                     onClose: { dismiss() }, onConfirm: save) {
            TextField("First name", text: $name)
                .font(.title3.weight(.semibold))
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(save)
                .padding(.horizontal, 18)
                .frame(height: 56)
                .background(AppTheme.fill, in: RoundedRectangle(cornerRadius: AppTheme.controlCornerRadius, style: .continuous))
        }
        .onAppear { name = athlete.displayName ?? "" }
    }

    private func save() {
        let first = name.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").first.map(String.init) ?? ""
        athlete.displayName = first.isEmpty ? nil : String(first.prefix(30))
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Histories

struct CheckInHistoryView: View {
    let checkIns: [CheckIn]
    @Environment(\.dismiss) private var dismiss

    private var sorted: [CheckIn] { checkIns.sorted { $0.date > $1.date } }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ScreenTitle("Check-ins", subtitle: "\(checkIns.count) mornings logged")
                    if sorted.isEmpty {
                        Text("No check-ins yet. Your first one takes a few taps on Home.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryText)
                            .cardStyle()
                    }
                    // V8: each morning in words, not a grid of numbers.
                    ForEach(sorted) { checkIn in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(checkIn.date.formatted(.dateTime.weekday(.wide).month().day()))
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.ink)
                                Spacer()
                                if let band = checkIn.readinessBand {
                                    Text(Self.word(band))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AuraTone.body.mark)
                                }
                            }
                            Text(Self.summary(checkIn))
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                        Divider().overlay(AppTheme.hairline)
                    }
                }
                .padding(20)
            }
            .appScreen()
            .toolbar {
                CloseToolbarItem { dismiss() }
            }
        }
    }

    /// Readiness as a word, never a score.
    static func word(_ band: ReadinessBand) -> String {
        switch band {
        case .green: "Ready"
        case .amber: "Go easier"
        case .red: "Recover"
        }
    }

    /// "Slept well · a little sore · good energy · calm" (answers are 1…5).
    static func summary(_ checkIn: CheckIn) -> String {
        let sleep = checkIn.sleepQuality >= 4 ? "Slept well" : (checkIn.sleepQuality <= 2 ? "Slept badly" : "Slept okay")
        let sore = checkIn.soreness >= 4 ? "very sore" : (checkIn.soreness == 3 ? "sore" : (checkIn.soreness == 2 ? "a little sore" : "not sore"))
        let energy = checkIn.energy >= 4 ? "good energy" : (checkIn.energy <= 2 ? "low energy" : "okay energy")
        let stress = checkIn.stress >= 4 ? "stressed" : (checkIn.stress == 1 ? "calm" : "okay mood")
        return [sleep, sore, energy, stress].joined(separator: " · ")
    }
}

/// §15: "export for Pro" — here for everyone for now; the paywall milestone
/// gates it. Plain JSON of the athlete's own data, shared through the system
/// share sheet.
struct DataExportView: View {
    let athlete: Athlete
    let sessions: [Session]
    @Environment(\.dismiss) private var dismiss

    private var exportText: String {
        let iso = ISO8601DateFormatter()
        var checkIns: [[String: Any]] = []
        for checkIn in athlete.checkIns.sorted(by: { $0.date < $1.date }) {
            var row: [String: Any] = [:]
            row["date"] = iso.string(from: checkIn.date)
            row["sleep"] = checkIn.sleepQuality
            row["soreness"] = checkIn.soreness
            row["energy"] = checkIn.energy
            row["stress"] = checkIn.stress
            row["readiness"] = checkIn.readinessBand?.rawValue ?? ""
            checkIns.append(row)
        }
        var sessionRows: [[String: Any]] = []
        for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            var setRows: [[String: Any]] = []
            for set in session.sets.sorted(by: { $0.setIndex < $1.setIndex }) {
                var setRow: [String: Any] = ["item": set.itemSlug, "setIndex": set.setIndex]
                if let reps = set.reps { setRow["reps"] = reps }
                if let weight = set.weightKg { setRow["weightKg"] = weight }
                if let seconds = set.seconds { setRow["seconds"] = seconds }
                if let distance = set.distanceM { setRow["distanceM"] = distance }
                if let contacts = set.contacts { setRow["contacts"] = contacts }
                setRows.append(setRow)
            }
            var row: [String: Any] = ["startedAt": iso.string(from: session.startedAt), "minutes": session.minutes, "sets": setRows]
            if let rpe = session.sessionRPE { row["rpe"] = rpe }
            sessionRows.append(row)
        }
        var games: [[String: Any]] = []
        for game in athlete.competitions {
            games.append(["date": iso.string(from: game.date), "kind": game.kind.rawValue, "home": game.isHome])
        }
        // Why each day's plan looked the way it did, and reported pain (§29).
        let traces: [[String: Any]] = DecisionTraceStore.all().map { trace in
            ["day": trace.day, "decision": trace.decision.rawValue, "rules": trace.rules, "reasons": trace.reasonCodes,
             "unknown": trace.uncertainties, "shown": trace.selected, "release": trace.knowledgeRelease,
             "contentStatus": trace.contentStatus.rawValue, "inputs": trace.inputs]
        }
        let pain: [[String: Any]] = PainStore.all().map { ["day": $0.day, "areas": $0.areas.map(\.rawValue), "level": $0.level.rawValue] }
        let payload: [String: Any] = [
            "exportedAt": iso.string(from: .now),
            "sport": athlete.activeSport?.sportSlug ?? "",
            "checkIns": checkIns,
            "sessions": sessionRows,
            "games": games,
            "decisions": traces,
            "painReports": pain,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ScreenTitle("Export my data", subtitle: "Everything you've logged, in a file you own.")
                    HStack(spacing: 12) {
                        exportStat("\(sessions.count)", "sessions")
                        exportStat("\(sessions.reduce(0) { $0 + $1.sets.count })", "sets")
                        exportStat("\(athlete.checkIns.count)", "check-ins")
                    }
                    if !UsageCounts.all.isEmpty {
                        ShareLink(item: "AthleteOS app usage (counted on this phone only)\n\n" + UsageCounts.summary) {
                            Label("Share app usage with support", systemImage: "chart.bar")
                        }
                        .buttonStyle(.secondary)
                    }
                    ShareLink(item: exportText, preview: SharePreview("AthleteOS export")) {
                        Label("Share export", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .foregroundStyle(AppTheme.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(AppTheme.accent, in: Capsule())
                    }
                }
                .padding(20)
            }
            .appScreen()
            .toolbar {
                CloseToolbarItem { dismiss() }
            }
        }
    }

    private func exportStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(AppTheme.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 14)
    }
}
