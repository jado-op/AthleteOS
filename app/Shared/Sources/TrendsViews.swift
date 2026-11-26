import Charts
import SwiftData
import SwiftUI

/// The one Trends block (Progress → Trends): the last 30 days in numbers,
/// then sleep and training load over time. §11: "Chart sleep against
/// training load… make that chart the first thing on the trends screen."
/// What the numbers mean is the twin's job (one analyst, not two).
struct TrendsSheet: View {
    let athlete: Athlete
    let sessions: [Session]
    @Environment(\.dismiss) private var dismiss

    private var thirtyDays: ThirtyDays {
        ProgressInsights.lastThirtyDays(
            sessions: sessions.map { (date: $0.startedAt, minutes: $0.minutes) },
            practiceDays: PracticeLogStore.logs.map(\.day),
            checkIns: athlete.checkIns.map { ProgressInsights.CheckInPoint(date: $0.date, sleepHours: $0.sleepHours, energy: $0.energy, soreness: $0.soreness) },
            needsWork: MindsetStore.reflections.compactMap(\.needsWork)
        )
    }

    private var missingDays: Int {
        let calendar = Calendar.current
        let checkIns = Set(athlete.checkIns.map { DayKey.of($0.date, calendar: calendar) })
        let trained = Set(sessions.map { DayKey.of($0.startedAt, calendar: calendar) })
        let practices = Set(PracticeLogStore.logs.map(\.day))
        return (1...14).filter { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: .now) else { return false }
            let key = DayKey.of(day, calendar: calendar)
            return !checkIns.contains(key) && !trained.contains(key) && !practices.contains(key)
        }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    thirtyDaysSection
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel("Sleep") { Text("14 days") }
                        SleepTrendCard(checkIns: athlete.checkIns)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel("How hard you've trained") { Text("28 days") }
                        LoadTrendCard(summary: LoadCalculator.summarize(sessions.map {
                            LoadSample(date: $0.startedAt, minutes: $0.minutes, rpe: $0.sessionRPE)
                        }))
                    }
                    if missingDays > 0 {
                        // Missing isn't zero (Backend Knowledge System §9).
                        Text("No data on \(missingDays) of the last 14 days. Those days show as empty, but that means unknown, not rest.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
        }
    }

    private func headline(_ summary: ThirtyDays) -> [Headline.Part] {
        var parts: [Headline.Part] = [
            .strong(countedNoun(summary.trainingDays, "training day")), .soft(" in the last 30, "),
            .strong("\(summary.minutes / 60)h \(summary.minutes % 60)m"), .soft(" in workouts"),
        ]
        if let sleep = summary.averageSleep {
            parts.append(.soft(", "))
            parts.append(.strong(String(format: "%.1f h", sleep)))
            parts.append(.soft(" of sleep a night."))
        } else {
            parts.append(.soft("."))
        }
        return parts
    }

    private var thirtyDaysSection: some View {
        let summary = thirtyDays
        return VStack(alignment: .leading, spacing: 14) {
            // V8: the 30 days in one sentence — the numbers in white, the words between them dimmed.
            Headline(headline(summary), size: 32)
        }
    }
}

/// Sleep quality over the last 14 days, from the morning check-ins.
struct SleepTrendCard: View {
    let checkIns: [CheckIn]

    private var recent: [CheckIn] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        return checkIns.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
    }

    private var average: Double? {
        guard !recent.isEmpty else { return nil }
        return Double(recent.reduce(0) { $0 + $1.sleepQuality }) / Double(recent.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let average {
                FigureStat(average.formatted(.number.precision(.fractionLength(1))), unit: "/ 5", label: "average sleep quality", size: 44)
            }
            if recent.isEmpty {
                Text("Check in each morning and your sleep trend appears here. Teen athletes need roughly 8–10 hours — it's the highest-leverage habit there is.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Chart(recent, id: \.id) { checkIn in
                    BarMark(
                        x: .value("Day", checkIn.date, unit: .day),
                        y: .value("Sleep", checkIn.sleepQuality)
                    )
                    .foregroundStyle(AuraTone.body.mark.gradient)
                    .cornerRadius(5)
                }
                .chartYScale(domain: 0...5)
                .chartYAxis {
                    AxisMarks(values: [1, 3, 5]) { _ in
                        AxisGridLine().foregroundStyle(AppTheme.hairline)
                        AxisValueLabel()
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .frame(height: 150)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassSurface(cornerRadius: 18)
    }
}

/// Training load: each day how hard it felt × how long, against the usual day.
struct LoadTrendCard: View {
    let summary: LoadSummary

    private var hasData: Bool { summary.daily.contains { $0.load > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FigureStat("\(summary.acute)", label: "load this week", size: 44)
            Text("Each bar is a day: how hard it felt × how long. Dashed line = your usual day.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if hasData {
                Chart {
                    ForEach(Array(summary.daily.enumerated()), id: \.offset) { _, day in
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Load", day.load))
                            .foregroundStyle(AuraTone.training.mark.gradient)
                            .cornerRadius(3)
                    }
                    RuleMark(y: .value("Weekly average per day", summary.chronicWeekly / 7))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 150)
            }
            if let message = summary.message {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: summary.isSharpJump ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(summary.isSharpJump ? AppTheme.amber : AppTheme.green)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                }
            } else {
                Text(hasData ? "Your four-week comparison unlocks after three weeks of logging." : "Finish a session and rate how hard it was — your load chart starts there.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassSurface(cornerRadius: 18)
    }
}
