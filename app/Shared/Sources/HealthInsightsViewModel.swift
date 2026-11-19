import Combine
import Foundation

/// A section of the health insights page.
struct HealthSection: Identifiable, Equatable {
    let category: HealthCategory
    let widgets: [HealthWidgetKind]
    var id: String { category.rawValue }
}

/// The health insights page's state: loads the snapshot, lays out only the
/// widgets with data, and reloads when Health reports a change (debounced so
/// a burst of samples is one reload).
@MainActor
final class HealthInsightsViewModel: ObservableObject {
    enum Phase: Equatable {
        /// First read in progress.
        case loading
        /// No Health on this device (some iPads).
        case unavailable
        /// Health is there but returned nothing: not allowed yet, or nothing recorded.
        case empty
        case ready
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var snapshot: HealthSnapshot = .empty
    @Published private(set) var sections: [HealthSection] = []

    private var changes: AnyCancellable?
    private var loading = false

    init() {
        changes = NotificationCenter.default.publisher(for: HealthDataRepository.didChange)
            .debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.load() }
            }
    }

    /// Every widget shown, in page order.
    var widgets: [HealthWidgetKind] { sections.flatMap(\.widgets) }

    func load(force: Bool = false) async {
        if DemoData.isEnabled {
            apply(HealthDemo.snapshot())
            return
        }
        guard HealthKitManager.shared.isAvailable else {
            phase = .unavailable
            return
        }
        guard !loading else { return }
        loading = true
        let snapshot = await HealthDataRepository.shared.snapshot(force: force)
        loading = false
        apply(snapshot)
    }

    /// Asks for Health access (Apple's sheet), then reads again.
    func connect() async {
        await HealthKitManager.shared.requestAuthorization()
        UserDefaults.standard.set(true, forKey: "healthPermissionAsked")
        await HealthDataRepository.shared.reset()
        HealthSync.startIfAllowed()
        await load(force: true)
    }

    private func apply(_ snapshot: HealthSnapshot) {
        self.snapshot = snapshot
        let shown = HealthWidgetRegistry.sections(in: snapshot).map { HealthSection(category: $0.category, widgets: $0.widgets) }
        if shown != sections { sections = shown }
        phase = shown.isEmpty ? .empty : .ready
    }
}
