import SwiftUI

/// Me → Apple Health (owner, 2026-11-19): the one way data from a watch, band
/// or app comes in. What is arriving, from whom, and how to let a device write
/// to Health. No brand gets its own connection: Apple Watch, Garmin, Suunto,
/// Fitbit and the rest are all read the same way.
struct HealthConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = HealthInsightsViewModel()
    @State private var working = false

    /// Who wrote the data, newest measurement first ("Apple Watch", "Garmin Connect").
    private var sources: [String] {
        let snapshot = model.snapshot
        let named = snapshot.series.values.sorted { ($0.latestDate ?? .distantPast) > ($1.latestDate ?? .distantPast) }
            .compactMap(\.latestSource) + snapshot.workouts.map(\.source)
        var seen: Set<String> = []
        return named.filter { seen.insert($0).inserted }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Headline([.strong("Apple Health."), .soft(" Every watch, band and app, one way in.")], size: 30)
                    status
                    setup
                    Text("AthleteOS connects to no watch maker directly. It reads what your devices write to Apple Health, only on this phone, and never sends it to our server, to coaches or to parents.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .containerRelativeFrame(.horizontal)
            }
            .appScreen()
            .toolbar { CloseToolbarItem { dismiss() } }
            .task { await model.load() }
        }
    }

    // MARK: What is arriving

    @ViewBuilder private var status: some View {
        AuraCard(.body, focus: UnitPoint(x: 0.85, y: 0.2), radius: 220, padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.phase == .ready ? "Connected" : (model.phase == .loading ? "Checking…" : "Not seen yet"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.ink.opacity(0.75))
                switch model.phase {
                case .ready:
                    BigFigure("\(model.widgets.count)", unit: model.widgets.count == 1 ? "insight" : "insights", size: 52)
                    Text(model.sections.map(\.category.title).joined(separator: " · "))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink.opacity(0.9))
                    if !sources.isEmpty {
                        Text("From " + sources.prefix(4).joined(separator: ", ") + ".")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("They're in your twin, under More insights into your health.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.ink.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                case .unavailable:
                    Text("Apple Health isn't on this device.")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                default:
                    Text("Nothing from Apple Health yet.")
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.6)
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Letting a device in

    private var setup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set it up once").font(.title3.weight(.semibold)).foregroundStyle(AppTheme.ink)
            step(1, "Allow AthleteOS to read Health: sleep, heart, activity, workouts and body measurements.")
            step(2, "Apple Watch writes to Health by itself. For any other watch, band or ring, turn on Apple Health in its own app (Garmin Connect, Suunto, Fitbit, Polar Flow, COROS, Oura, WHOOP…) and allow it to write.")
            step(3, "That's all. New data shows up by itself, and only what your devices actually measure.")
            // Once data arrives the athlete has allowed it; changes go through Settings.
            if model.phase != .ready {
                Button(working ? "Connecting…" : "Allow in Apple Health") {
                    working = true
                    Task {
                        await model.connect()
                        working = false
                    }
                }
                .buttonStyle(.secondary)
                .disabled(working || !HealthKitManager.shared.isAvailable)
            }
            Text("Changed your mind? Settings → Health → Data Access & Devices → AthleteOS.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(AppTheme.secondaryText)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
