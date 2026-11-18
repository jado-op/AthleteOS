import CryptoKit
import Foundation
import SwiftData

/// Backs up everything the athlete builds up in the app and shares it
/// across their phones, so a new phone (or a reinstall) comes back exactly
/// as it was: profile, sports, games, saved skill plans, and every
/// setting and bit of progress kept outside SwiftData (Campus XP and
/// lessons, day status, practice days, reminders, tips seen…).
///
/// Each piece is one JSON document on the server (`/sync/state`), last
/// write wins by `updatedAt`; settings are split into small groups
/// (`settings.campus`, `settings.schedule`…) so changes to different
/// things on two phones don't overwrite each other. This device remembers, per document, a hash
/// of what it last synced and when that version was written — a changed
/// hash means "edited here since", so the document gets a fresh timestamp
/// and is pushed; an unchanged one takes the server's copy if the server's
/// is newer. A document this device has never synced (new phone) always
/// takes the server's copy when there is one.
///
/// Check-ins and logged sessions already go up row by row (`SyncQueue`);
/// `restoreRows` brings them back down by `clientId`.
@MainActor
public enum CloudSync {
    // MARK: - What is backed up

    /// UserDefaults keys that belong to the athlete (not to this device).
    static let settingsKeys: Set<String> = [
        "dayStatus.v1", "reminderSettings", "home.introSeen", "appTourSeen",
        "libraryOpened", "gameStartMinutes", "weightUnit",
        "freeSportSwitchDates", "muscleWorkoutStarts",
    ]
    /// Whole families of athlete keys, including ones later features add.
    static let settingsPrefixes = ["campus.", "schedule.", "plans.", "progress.", "profile.", "tip.", "mindset.", "benchmark.", "calendar.", "safety.", "league.", "academyTwin."]

    static func isSettingKey(_ key: String) -> Bool {
        settingGroup(of: key) != nil
    }

    /// Settings are backed up in small groups (one document each), so a
    /// Campus lesson finished on one phone and practice days changed on
    /// another both survive.
    static func settingGroup(of key: String) -> String? {
        if let prefix = settingsPrefixes.first(where: { key.hasPrefix($0) }) { return String(prefix.dropLast()) }
        return settingsKeys.contains(key) ? "app" : nil
    }

    static var settingGroups: [String] { ["app"] + settingsPrefixes.map { String($0.dropLast()) } }

    private static let metaKey = "cloud.meta"
    private static let lastRowPullKey = "cloud.lastRowPull"

    // MARK: - Running a sync

    /// Pull, merge and push every document. Quietly does nothing when not
    /// signed in or offline; returns whether it reached the server.
    @discardableResult
    public static func sync(
        athlete: Athlete, context: ModelContext, apiClient: APIClient,
        tokenStore: any TokenStore = KeychainTokenStore(), now: Date = .now
    ) async -> Bool {
        guard !DemoData.isEnabled, let token = try? tokenStore.read() else { return false }
        retireMealsBackupOnce()
        // Deletions first ("Delete twin" made offline), so they can't come back.
        for key in pendingDeletes {
            guard (try? await apiClient.deleteState(key, sessionToken: token)) != nil else { return false }
            pendingDeletes.removeAll { $0 == key }
        }
        // "Delete twin": a marker (a date, no content) so the athlete's other
        // phones delete their copy too instead of pushing it back.
        if let deletedAt = twinDeletedAt {
            let marker = try? JSONSerialization.data(withJSONObject: ["at": deletedAt.timeIntervalSince1970])
            guard let marker, (try? await apiClient.pushState([twinMarkerKey: .init(json: marker, updatedAt: deletedAt)], sessionToken: token)) != nil
            else { return false }
            twinDeletedAt = nil
        }
        guard let remote = try? await apiClient.fetchState(sessionToken: token) else { return false }
        // The fetch suspended; the athlete may have logged out meanwhile.
        guard !athlete.isDeleted, athlete.modelContext != nil else { return false }

        var meta = loadMeta()
        // Deleted on another phone after this one last synced its twin: delete it here too.
        if let marker = remote[twinMarkerKey], remote[twinKey] == nil,
           (meta[twinKey]?.updatedAt ?? .distantPast) < marker.updatedAt {
            AcademyStore.delete()
            meta[twinKey] = nil
        }
        var toPush: [String: APIClient.SyncedDoc] = [:]
        for (key, local) in exportAll(athlete: athlete, now: now) {
            // Private groups go up sealed (CloudSeal); without a key they stay on this phone.
            // A sealed backup already on the server: wait for its key (iCloud
            // Keychain may still be bringing it) rather than making a new one.
            let sealedOnServer = remote[key].map { CloudSeal.isEnvelope($0.json) } ?? false
            let sealKey = CloudSeal.isSealed(documentKey: key) ? CloudSeal.key(createIfMissing: !sealedOnServer) : nil
            if CloudSeal.isSealed(documentKey: key), sealKey == nil { continue }
            var server = remote[key]
            var serverIsPlain = false
            if let sealKey, let stored = server {
                if CloudSeal.isEnvelope(stored.json) {
                    // Sealed with a key this phone doesn't have: leave it alone.
                    guard let plain = CloudSeal.open(stored.json, key: sealKey) else { continue }
                    server = .init(json: plain, updatedAt: stored.updatedAt)
                } else {
                    serverIsPlain = true
                }
            }
            // Nothing private to keep: don't create an (empty) backup.
            if sealKey != nil, server == nil, local == Data("{}".utf8) { meta[key] = nil; continue }
            let hash = digest(local)
            let known = meta[key]
            let localStamp: Date? = known.map { $0.hash == hash ? $0.updatedAt : now }
            if let server, localStamp.map({ server.updatedAt > $0 }) ?? true {
                // A new phone, or another phone saved a newer copy: take it.
                apply(key, server.json, athlete: athlete, context: context, now: now)
                meta[key] = Meta(hash: digest(export(key, athlete: athlete, now: now)), updatedAt: server.updatedAt)
            } else if let stamp = localStamp ?? (server == nil ? now : nil), server.map({ stamp > $0.updatedAt }) ?? true {
                toPush[key] = .init(json: local, updatedAt: stamp)
            } else if let localStamp {
                meta[key] = Meta(hash: hash, updatedAt: localStamp)
            }
            if serverIsPlain, toPush[key] == nil, let stored = server {
                // Backed up before sealing existed: replace it with a sealed copy.
                toPush[key] = .init(json: export(key, athlete: athlete, now: now),
                                    updatedAt: max(now, stored.updatedAt.addingTimeInterval(0.01)))
            }
        }
        try? context.save()
        saveMeta(meta)

        guard !toPush.isEmpty else { return true }
        var outgoing: [String: APIClient.SyncedDoc] = [:]
        for (key, doc) in toPush {
            if CloudSeal.isSealed(documentKey: key) {
                guard let sealKey = CloudSeal.key(), let sealed = CloudSeal.seal(doc.json, key: sealKey) else { continue }
                outgoing[key] = .init(json: sealed, updatedAt: doc.updatedAt)
            } else {
                outgoing[key] = doc
            }
        }
        guard let returned = try? await apiClient.pushState(outgoing, sessionToken: token) else { return false }
        guard !athlete.isDeleted, athlete.modelContext != nil else { return false }
        var winners: [String: APIClient.SyncedDoc] = [:]
        for (key, doc) in returned {
            if CloudSeal.isSealed(documentKey: key), CloudSeal.isEnvelope(doc.json) {
                guard let sealKey = CloudSeal.key(createIfMissing: false), let plain = CloudSeal.open(doc.json, key: sealKey) else { continue }
                winners[key] = .init(json: plain, updatedAt: doc.updatedAt)
            } else {
                winners[key] = doc
            }
        }
        for (key, sent) in toPush where outgoing[key] != nil {
            guard let winner = winners[key] else { continue }
            if winner.updatedAt.timeIntervalSince(sent.updatedAt) > 0.001 {
                // Another phone wrote a newer copy between our pull and push.
                apply(key, winner.json, athlete: athlete, context: context, now: now)
                meta[key] = Meta(hash: digest(export(key, athlete: athlete, now: now)), updatedAt: winner.updatedAt)
            } else {
                // Ours won. Remember the server's own timestamp (it keeps
                // milliseconds), so the next sync sees the two as equal.
                meta[key] = Meta(hash: digest(sent.json), updatedAt: winner.updatedAt)
            }
        }
        try? context.save()
        saveMeta(meta)
        return true
    }

    /// Brings logged sessions and check-ins down from the server and adds
    /// any this phone doesn't have (matched by `clientId`, marked synced so
    /// they're never pushed back). `full` fetches everything — a new phone;
    /// otherwise only the last two weeks, at most every few hours, so a
    /// workout logged on another phone shows up here too.
    public static func restoreRows(
        athlete: Athlete, context: ModelContext, apiClient: APIClient, full: Bool,
        tokenStore: any TokenStore = KeychainTokenStore(), now: Date = .now
    ) async {
        guard !DemoData.isEnabled, let token = try? tokenStore.read() else { return }
        let defaults = UserDefaults.standard
        let last = defaults.object(forKey: lastRowPullKey) as? Date
        if !full, let last, now.timeIntervalSince(last) < 4 * 3600 { return }
        let since = full ? nil : Calendar.current.date(byAdding: .day, value: -14, to: now)

        guard let checkIns = try? await apiClient.fetchCheckIns(since: since, sessionToken: token),
              let sessions = try? await apiClient.fetchSessions(since: since, sessionToken: token),
              !athlete.isDeleted, athlete.modelContext != nil else { return }
        mergeCheckIns(checkIns, into: athlete, context: context, now: now)
        mergeSessions(sessions, into: athlete, context: context, now: now)
        try? context.save()
        defaults.set(now, forKey: lastRowPullKey)
    }

    // MARK: - Rows

    static func mergeCheckIns(_ remote: [APIClient.RemoteCheckIn], into athlete: Athlete, context: ModelContext, now: Date, calendar: Calendar = .current) {
        let known = Set(athlete.checkIns.map(\.clientId))
        for row in remote where !known.contains(row.clientId) {
            guard let date = day(row.date, calendar: calendar) else { continue }
            // One check-in per day: a local one for the same day wins.
            if athlete.checkIns.contains(where: { calendar.isDate($0.date, inSameDayAs: date) }) { continue }
            let checkIn = CheckIn(
                date: date, sleepQuality: row.sleepQuality, sleepHours: row.sleepHours, soreness: row.soreness,
                sorenessAreas: row.sorenessAreas ?? [], energy: row.energy, stress: row.stress,
                readinessBand: row.readinessBand.flatMap(ReadinessBand.init(rawValue:)), readinessZ: row.readinessZ,
                clientId: row.clientId, athlete: athlete
            )
            checkIn.syncedAt = now
            context.insert(checkIn)
        }
    }

    private static let discardedSessionsKey = "cloud.discardedSessions"

    /// A workout the athlete discarded: never brought back by a restore.
    static func discard(sessionClientId: String) {
        var ids = UserDefaults.standard.stringArray(forKey: discardedSessionsKey) ?? []
        if !ids.contains(sessionClientId) { ids.append(sessionClientId) }
        UserDefaults.standard.set(Array(ids.suffix(200)), forKey: discardedSessionsKey)
    }

    static func mergeSessions(_ remote: [APIClient.RemoteSession], into athlete: Athlete, context: ModelContext, now: Date) {
        let known = Set(athlete.sessions.map(\.clientId)).union(UserDefaults.standard.stringArray(forKey: discardedSessionsKey) ?? [])
        for row in remote where !known.contains(row.clientId) {
            // An empty open workout uploaded by an older app: not a real session.
            guard row.endedAt != nil || !row.sets.isEmpty else { continue }
            guard let startedAt = APIClient.parseTimestamp(row.startedAt) else { continue }
            let session = Session(
                startedAt: startedAt, endedAt: row.endedAt.flatMap(APIClient.parseTimestamp),
                sessionRPE: row.sessionRPE, minutes: row.minutes,
                source: SessionSource(rawValue: row.source) ?? .phone,
                healthKitWorkoutId: row.healthKitWorkoutId, notes: row.notes,
                clientId: row.clientId, syncedAt: now, athlete: athlete
            )
            context.insert(session)
            for set in row.sets {
                context.insert(SetLog(
                    itemSlug: set.itemSlug, setIndex: set.setIndex, reps: set.reps, weightKg: set.weightKg,
                    seconds: set.seconds, distanceM: set.distanceM, contacts: set.contacts, side: set.side,
                    clientId: set.clientId, session: session
                ))
            }
        }
    }

    private static func day(_ string: String, calendar: Calendar) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    // MARK: - Documents

    struct ProfileDoc: Codable, Equatable {
        var displayName: String?
        var birthDate: Date
        var unitSystem: String
        var trainsUnderCoach: Bool
        var equipmentAvailable: [String]
    }

    struct SportDoc: Codable, Equatable {
        var id: String
        var sportSlug: String
        var positionSlug: String?
        var formatSlug: String?
        var seasonStart: Date
        var seasonEnd: Date
        var isPrimary: Bool
    }

    struct CompetitionDoc: Codable, Equatable {
        var id: String
        var sportSlug: String
        var date: Date
        var kind: String
        var isHome: Bool
        var notes: String?
    }

    struct SkillBlockDoc: Codable, Equatable {
        var id: String
        var sportSlug: String
        var skillSlug: String
        var targetDate: Date
        var generatedAt: Date
        var seed: String
    }

    /// A UserDefaults value in JSON: what `@AppStorage` and the stores here write.
    enum SettingValue: Codable, Equatable {
        case bool(Bool)
        case number(Double)
        case string(String)
        case strings([String])
        case numbers([Double])
        case data(Data)

        init?(_ object: Any) {
            switch object {
            case let data as Data: self = .data(data)
            case let string as String: self = .string(string)
            case let number as NSNumber:
                if CFGetTypeID(number) == CFBooleanGetTypeID() { self = .bool(number.boolValue) }
                else if number.doubleValue.isFinite { self = .number(number.doubleValue) }
                else { return nil }
            case let strings as [String]: self = .strings(strings)
            case let numbers as [NSNumber] where numbers.allSatisfy({ $0.doubleValue.isFinite }): self = .numbers(numbers.map(\.doubleValue))
            default: return nil
            }
        }

        /// The value to put back into UserDefaults — whole numbers as Int so
        /// `integer(forKey:)` and `array(forKey:) as? [Int]` still work.
        var object: Any {
            switch self {
            case .bool(let value): return value
            case .number(let value): return Self.whole(value) ?? value
            case .string(let value): return value
            case .strings(let value): return value
            case .numbers(let values):
                let ints = values.compactMap(Self.whole)
                return ints.count == values.count ? ints as Any : values as Any
            case .data(let value): return value
            }
        }

        private static func whole(_ value: Double) -> Int? {
            value.rounded() == value && abs(value) < 9e15 ? Int(value) : nil
        }

        private enum CodingKeys: String, CodingKey { case bool, number, string, strings, numbers, data }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let v = try c.decodeIfPresent(Bool.self, forKey: .bool) { self = .bool(v) }
            else if let v = try c.decodeIfPresent(Double.self, forKey: .number) { self = .number(v) }
            else if let v = try c.decodeIfPresent(String.self, forKey: .string) { self = .string(v) }
            else if let v = try c.decodeIfPresent([String].self, forKey: .strings) { self = .strings(v) }
            else if let v = try c.decodeIfPresent([Double].self, forKey: .numbers) { self = .numbers(v) }
            else { self = .data(try c.decode(Data.self, forKey: .data)) }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .bool(let v): try c.encode(v, forKey: .bool)
            case .number(let v): try c.encode(v, forKey: .number)
            case .string(let v): try c.encode(v, forKey: .string)
            case .strings(let v): try c.encode(v, forKey: .strings)
            case .numbers(let v): try c.encode(v, forKey: .numbers)
            case .data(let v): try c.encode(v, forKey: .data)
            }
        }
    }

    static var documentKeys: [String] {
        ["profile", "sports", "competitions", "skillBlocks", "summary"] + settingGroups.map { "settings.\($0)" }
    }

    static func exportAll(athlete: Athlete, now: Date) -> [String: Data] {
        Dictionary(uniqueKeysWithValues: documentKeys.map { ($0, export($0, athlete: athlete, now: now)) })
    }

    static func export(_ key: String, athlete: Athlete, now: Date) -> Data {
        switch key {
        case "profile":
            return encode(ProfileDoc(
                // The first name stays on this phone (it's only for the greeting).
                displayName: nil, birthDate: athlete.birthDate, unitSystem: athlete.unitSystem.rawValue,
                trainsUnderCoach: athlete.trainsUnderCoach, equipmentAvailable: athlete.equipmentAvailable.sorted()
            ))
        case "sports":
            return encode(athlete.sports.sorted { $0.id < $1.id }.map {
                SportDoc(id: $0.id, sportSlug: $0.sportSlug, positionSlug: $0.positionSlug, formatSlug: $0.formatSlug,
                         seasonStart: $0.seasonStart, seasonEnd: $0.seasonEnd, isPrimary: $0.isPrimary)
            })
        case "competitions":
            return encode(athlete.competitions.sorted { $0.id < $1.id }.map {
                CompetitionDoc(id: $0.id, sportSlug: $0.sportSlug, date: $0.date, kind: $0.kind.rawValue, isHome: $0.isHome, notes: $0.notes)
            })
        case "skillBlocks":
            return encode(athlete.skillBlocks.sorted { $0.id < $1.id }.map {
                SkillBlockDoc(id: $0.id, sportSlug: $0.sportSlug, skillSlug: $0.skillSlug, targetDate: $0.targetDate,
                              generatedAt: $0.generatedAt, seed: $0.seed)
            })
        case "summary":
            return encode(weekSummary(athlete: athlete, now: now))
        default:
            return encode(exportSettings(group: String(key.dropFirst("settings.".count))))
        }
    }

    /// This week in numbers, for the parent summary page (only numbers —
    /// never anything the athlete wrote). Read by the server, never applied
    /// back onto a phone.
    struct WeekSummaryDoc: Codable, Equatable {
        var week: String
        var campusLessons: Int
        var reflections: Int
        var focusDone: Int
        var focusTotal: Int
        var testHeadline: String?
    }

    static func weekSummary(athlete: Athlete, now: Date) -> WeekSummaryDoc {
        let focus = MindsetEngine.weeklyFocus(goals: MindsetStore.goals, weekStart: now)
        let tests = BenchmarkCatalog.tests(for: athlete.activeSport?.sportSlug)
        return WeekSummaryDoc(
            week: CampusLog.weekKey(now),
            campusLessons: CampusLog.lessons(inWeekOf: now),
            reflections: MindsetStore.reflectionDays(inWeekOf: now),
            focusDone: focus.filter { MindsetStore.isFocusDone($0.goal.id, week: now) }.count,
            focusTotal: focus.count,
            testHeadline: BenchmarkMath.headline(BenchmarkStore.results, tests: tests)
        )
    }

    static func exportSettings(group: String, _ defaults: UserDefaults = .standard) -> [String: SettingValue] {
        var out: [String: SettingValue] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where settingGroup(of: key) == group {
            if let setting = SettingValue(value) { out[key] = setting }
        }
        return out
    }

    static func apply(_ key: String, _ json: Data, athlete: Athlete, context: ModelContext, now: Date) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        switch key {
        case "profile":
            guard let doc = try? decoder.decode(ProfileDoc.self, from: json) else { return }
            if let name = doc.displayName { athlete.displayName = name }
            athlete.birthDate = doc.birthDate
            athlete.unitSystem = UnitSystem(rawValue: doc.unitSystem) ?? athlete.unitSystem
            athlete.trainsUnderCoach = doc.trainsUnderCoach
            athlete.equipmentAvailable = doc.equipmentAvailable
        case "sports":
            guard let docs = try? decoder.decode([SportDoc].self, from: json) else { return }
            let ids = Set(docs.map(\.id))
            for sport in athlete.sports where !ids.contains(sport.id) { context.delete(sport) }
            for doc in docs {
                if let sport = athlete.sports.first(where: { $0.id == doc.id }) {
                    sport.sportSlug = doc.sportSlug
                    sport.positionSlug = doc.positionSlug
                    sport.formatSlug = doc.formatSlug
                    sport.seasonStart = doc.seasonStart
                    sport.seasonEnd = doc.seasonEnd
                    sport.isPrimary = doc.isPrimary
                } else {
                    context.insert(AthleteSport(
                        id: doc.id, sportSlug: doc.sportSlug, positionSlug: doc.positionSlug, formatSlug: doc.formatSlug,
                        seasonStart: doc.seasonStart, seasonEnd: doc.seasonEnd, isPrimary: doc.isPrimary, athlete: athlete
                    ))
                }
            }
        case "competitions":
            guard let docs = try? decoder.decode([CompetitionDoc].self, from: json) else { return }
            let ids = Set(docs.map(\.id))
            for competition in athlete.competitions where !ids.contains(competition.id) { context.delete(competition) }
            for doc in docs {
                let kind = CompetitionKind(rawValue: doc.kind) ?? .game
                if let existing = athlete.competitions.first(where: { $0.id == doc.id }) {
                    existing.sportSlug = doc.sportSlug
                    existing.date = doc.date
                    existing.kind = kind
                    existing.isHome = doc.isHome
                    existing.notes = doc.notes
                } else {
                    context.insert(Competition(id: doc.id, sportSlug: doc.sportSlug, date: doc.date, kind: kind,
                                               isHome: doc.isHome, notes: doc.notes, athlete: athlete))
                }
            }
        case "skillBlocks":
            guard let docs = try? decoder.decode([SkillBlockDoc].self, from: json) else { return }
            let ids = Set(docs.map(\.id))
            for block in athlete.skillBlocks where !ids.contains(block.id) { context.delete(block) }
            let existing = Set(athlete.skillBlocks.map(\.id))
            for doc in docs where !existing.contains(doc.id) {
                context.insert(SkillBlock(id: doc.id, sportSlug: doc.sportSlug, skillSlug: doc.skillSlug, targetDate: doc.targetDate,
                                          generatedAt: doc.generatedAt, seed: doc.seed, athlete: athlete))
            }
        case "summary":
            return
        default:
            guard key.hasPrefix("settings."),
                  let settings = try? decoder.decode([String: SettingValue].self, from: json) else { return }
            applySettings(settings, group: String(key.dropFirst("settings.".count)))
        }
    }

    static func applySettings(_ settings: [String: SettingValue], group: String, to defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where settingGroup(of: key) == group && settings[key] == nil {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in settings where settingGroup(of: key) == group {
            defaults.set(value.object, forKey: key)
        }
    }

    private static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)) ?? Data("null".utf8)
    }

    // MARK: - Deleting a backup for real

    private static let pendingDeletesKey = "cloud.pendingDeletes"

    static var pendingDeletes: [String] {
        get { UserDefaults.standard.stringArray(forKey: pendingDeletesKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: pendingDeletesKey) }
    }

    /// Deletes one backed-up document on the server (the row is removed, not
    /// overwritten). Offline or signed out: queued, and done first on the next sync.
    /// Returns whether the server confirmed it.
    @discardableResult
    public static func deleteBackup(_ key: String, apiClient: APIClient = APIClient(baseURL: AppConfig.backendBaseURL),
                                    tokenStore: any TokenStore = KeychainTokenStore()) async -> Bool {
        var meta = loadMeta()
        meta[key] = nil
        saveMeta(meta)
        if !pendingDeletes.contains(key) { pendingDeletes.append(key) }
        guard !DemoData.isEnabled, let token = try? tokenStore.read(),
              (try? await apiClient.deleteState(key, sessionToken: token)) != nil else { return false }
        pendingDeletes.removeAll { $0 == key }
        return true
    }

    /// Food logging was retired: the old "meals" backup is deleted on the
    /// server once (queued like any other delete, so offline is fine), and
    /// the retired "training starts" time goes from this phone.
    private static let mealsRetiredKey = "cloud.mealsRetired"

    static func retireMealsBackupOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: mealsRetiredKey) else { return }
        var meta = loadMeta()
        meta["meals"] = nil
        saveMeta(meta)
        if !pendingDeletes.contains("meals") { pendingDeletes.append("meals") }
        defaults.removeObject(forKey: "trainingStartMinutes")
        defaults.set(true, forKey: mealsRetiredKey)
    }

    static let twinKey = "settings.academyTwin"
    static let twinMarkerKey = "deleted.academyTwin"
    private static let twinDeletedAtKey = "cloud.twinDeletedAt"

    /// A twin deletion still to be announced to the server (offline).
    static var twinDeletedAt: Date? {
        get { UserDefaults.standard.object(forKey: twinDeletedAtKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: twinDeletedAtKey) }
    }

    /// "Delete twin": the interview, briefings read and performances — on this
    /// phone and in the backup.
    @discardableResult
    public static func deleteTwin() async -> Bool {
        AcademyStore.delete()
        twinDeletedAt = .now
        return await deleteBackup(twinKey)
    }

    // MARK: - Bookkeeping

    struct Meta: Codable, Equatable {
        var hash: String
        var updatedAt: Date
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func loadMeta() -> [String: Meta] {
        guard let data = UserDefaults.standard.data(forKey: metaKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Meta].self, from: data)) ?? [:]
    }

    private static func saveMeta(_ meta: [String: Meta]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(meta), forKey: metaKey)
    }
}
