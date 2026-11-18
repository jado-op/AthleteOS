import SwiftUI

// MARK: - Back after illness (8)

/// The few days after being sick (§13: reassess, conservative template —
/// draft, not yet expert-reviewed). Two days of light movement, then three
/// lighter days; any fever or feeling worse means stop and rest again.
public enum IllnessReturn {
    static let key = "dayStatus.lastSickEnd"
    public static let days = 5

    public static func markRecovered(on date: Date = .now, calendar: Calendar = .current) {
        UserDefaults.standard.set(DayKey.of(date, calendar: calendar), forKey: key)
    }

    /// Day 1… of the return, nil when not returning.
    public static func day(on date: Date = .now, calendar: Calendar = .current) -> Int? {
        // A "sick" status that simply ran out ends the illness too.
        if DayStatusStore.storedStatus == .sick, let until = DayStatusStore.until,
           calendar.startOfDay(for: until) < calendar.startOfDay(for: date),
           let after = calendar.date(byAdding: .day, value: 1, to: until) {
            let stored = UserDefaults.standard.string(forKey: key) ?? ""
            if stored < DayKey.of(after, calendar: calendar) { markRecovered(on: after, calendar: calendar) }
        }
        guard let key = UserDefaults.standard.string(forKey: key) else { return nil }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let end = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        let days = (calendar.dateComponents([.day], from: end, to: calendar.startOfDay(for: date)).day ?? 0) + 1
        return days >= 1 && days <= Self.days ? days : nil
    }

    public static func reason(day: Int) -> String {
        day <= 2
            ? "Back after being ill: day \(day) of \(days), light movement only. Fever or feeling worse? Stop and rest."
            : "Back after being ill: day \(day) of \(days), a lighter day. Fever or feeling worse? Stop and rest."
    }
}

// MARK: - School hours (13)

/// When school ends on each weekday, so a long school day (or an exam
/// today) keeps added training short.
public enum SchoolHours {
    static let key = "schedule.schoolEnds"

    /// Weekday (1 = Sunday) → minutes after midnight school ends.
    public static var ends: [Int: Int] {
        get {
            let entries = UserDefaults.standard.stringArray(forKey: key) ?? []
            return Dictionary(uniqueKeysWithValues: entries.compactMap { entry -> (Int, Int)? in
                let parts = entry.split(separator: "=").compactMap { Int($0) }
                return parts.count == 2 ? (parts[0], parts[1]) : nil
            })
        }
        set { UserDefaults.standard.set(newValue.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }, forKey: key) }
    }

    /// School ending at 4:30 pm or later counts as a long day.
    public static let longDayFrom = 16 * 60 + 30

    public static func isLongDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        (ends[calendar.component(.weekday, from: date)] ?? 0) >= longDayFrom
    }
}

struct SchoolHoursSection: View {
    let onChanged: () -> Void
    @State private var ends = SchoolHours.ends

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("School hours", subtitle: "A long school day keeps added training short.")
            VStack(spacing: 0) {
                ForEach([2, 3, 4, 5, 6], id: \.self) { weekday in
                    HStack {
                        Text(Calendar.current.weekdaySymbols[weekday - 1]).font(.body).foregroundStyle(AppTheme.ink)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { ends[weekday] ?? 0 },
                            set: { value in
                                if value == 0 { ends[weekday] = nil } else { ends[weekday] = value }
                                SchoolHours.ends = ends
                                onChanged()
                            }
                        )) {
                            Text("Not set").tag(0)
                            ForEach(Array(stride(from: 12 * 60, through: 18 * 60, by: 30)), id: \.self) { minutes in
                                Text(PracticeTime(start: minutes, end: minutes).label.components(separatedBy: " – ").first ?? "").tag(minutes)
                            }
                        }
                        .labelsHidden()
                    }
                    .frame(minHeight: 48)
                }
            }
            .cardStyle(padding: 12)
        }
    }
}

// MARK: - Tournament and travel mode (16)

/// Away tournaments: the time difference, sleep, between games and a
/// hotel-room workout — in one place.
struct TournamentModeView: View {
    let onHotelWorkout: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("travel.timeZone") private var timeZoneID = TimeZone.current.identifier

    private static let zones = ["America/Los_Angeles", "America/Denver", "America/Chicago", "America/New_York", "Europe/London",
                                "Europe/Berlin", "Asia/Tokyo", "Australia/Sydney"]

    private var hoursDifference: Int {
        let there = TimeZone(identifier: timeZoneID) ?? .current
        return (there.secondsFromGMT() - TimeZone.current.secondsFromGMT()) / 3600
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ScreenTitle("Tournament & travel", subtitle: "Everything for a trip with games, in one place.")
                    section("Where are you going?") {
                        Picker("Time zone", selection: $timeZoneID) {
                            Text("Same time zone").tag(TimeZone.current.identifier)
                            ForEach(Self.zones, id: \.self) { zone in
                                Text(zone.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone).tag(zone)
                            }
                        }
                        Text(timeText).font(.subheadline).foregroundStyle(AppTheme.ink).fixedSize(horizontal: false, vertical: true)
                    }
                    section("Between games") {
                        bullets([
                            "Drink water between games.",
                            "Feet up and easy movement — no extra workout during a tournament.",
                            "Feeling faint, sick or dizzy in the heat? Stop, cool down, tell an adult.",
                        ])
                    }
                    section("Sleep away from home") {
                        bullets([
                            "Same bedtime routine as at home: it tells your body it's night.",
                            "Bring what helps: earplugs, eye mask, your pillow.",
                            "A short nap (20–30 min) early in the afternoon is fine; long late naps make the night harder.",
                        ])
                    }
                    Button("Hotel-room workout") { dismiss(); onHotelWorkout() }
                        .buttonStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .containerRelativeFrame(.horizontal)
            }
            .appScreen()
            .toolbar { CloseToolbarItem { dismiss() } }
        }
    }

    private var timeText: String {
        let h = hoursDifference
        if h == 0 { return "No time difference: keep your normal routine." }
        let way = h > 0 ? "ahead" : "behind"
        let shift = h > 0 ? "earlier" : "later"
        return "\(abs(h)) hour\(abs(h) == 1 ? "" : "s") \(way). A few days before you leave, go to bed and get up about an hour \(shift) each day. When you arrive, get outside in daylight in the morning and eat at local times."
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(AppTheme.ink)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func bullets(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(lines, id: \.self) { line in
                Text("• " + line).font(.subheadline).foregroundStyle(AppTheme.ink).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
