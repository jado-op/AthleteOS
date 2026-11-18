import SwiftData
import SwiftUI

/// §15 onboarding after sign-in: "pick your sport, then position → season
/// dates (with sensible defaults per sport, editable) → equipment you
/// actually have access to → do you train under a coach → downloads your
/// sport pack." Only the sport choice is required; everything else has a
/// sensible default and a Skip.
@MainActor
public struct SetupFlowView: View {
    let athlete: Athlete
    @Environment(\.modelContext) private var modelContext

    private enum Step: Int, CaseIterable {
        case sport, position, season, equipment, finishing
    }

    @State private var step: Step = .sport
    @State private var sportSlug: String?
    @State private var positionSlug: String?
    @State private var formatSlug: String?
    @State private var seasonStart = Date.now
    @State private var seasonEnd = Date.now
    @State private var equipment: Set<String> = []
    @State private var trainsUnderCoach: Bool?
    @State private var finishingMessage = "Building your plan…"

    public init(athlete: Athlete) {
        self.athlete = athlete
    }

    private var sport: SportInfo? { sportSlug.flatMap { allSportsBySlug[$0] } }

    /// One bar across the whole first run: age and sign-in filled the first 40%.
    private var progress: Double {
        0.4 + 0.6 * Double(step.rawValue + 1) / Double(Step.allCases.count - 1)
    }

    public var body: some View {
        Group {
            switch step {
            case .sport:
                StepScaffold(
                    progress: progress, title: "What's your sport?", subtitle: "Your plan is built around it. Add more sports later in Me.",
                    buttonEnabled: sportSlug != nil, onContinue: chooseSport
                ) {
                    SportChooser(selection: $sportSlug)
                }
            case .position:
                StepScaffold(
                    progress: progress, title: sport?.positions.isEmpty == false ? "What position do you play?" : "How do you play?",
                    subtitle: sport?.positions.isEmpty == false ? "Each position needs different things — a goalkeeper trains differently from a midfielder." : "Your plan uses the drills for the way you play.",
                    onBack: { go(.sport) }, onContinue: { go(.season) }
                ) {
                    if let sport {
                        PositionChooser(sport: sport, selection: $positionSlug, format: $formatSlug)
                    }
                }
            case .season:
                StepScaffold(
                    progress: progress, title: "When's your season?", subtitle: "We filled in the usual dates for \(sport?.name ?? "your sport"). Adjust them to your team's.",
                    onBack: { go(sport?.hasRoleChoice == true ? .position : .sport) }, onContinue: { go(.equipment) }
                ) {
                    SeasonEditor(start: $seasonStart, end: $seasonEnd)
                }
            case .equipment:
                StepScaffold(
                    progress: progress, title: "What can you train with?", subtitle: "Only pick what you actually have access to. Nothing is fine too.",
                    buttonTitle: "Finish setup", onBack: { go(.season) }, onContinue: finish
                ) {
                    EquipmentChooser(selection: $equipment)
                }
            case .finishing:
                finishingView
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    private var finishingView: some View {
        VStack(spacing: 22) {
            Spacer()
            RingView(progress: 0.75, color: AppTheme.ink, lineWidth: 10) {
                Image(systemName: sportSlug.map(SportIcon.name(for:)) ?? "sportscourt.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(AppTheme.ink)
            }
            .frame(width: 130, height: 130)
            Text(finishingMessage)
                .font(.title2.bold())
                .foregroundStyle(AppTheme.ink)
            Text("Downloading your \(sport?.name ?? "sport") library and generating this week.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            ProgressView()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .appScreen()
    }

    private func go(_ next: Step) {
        step = next
    }

    private func chooseSport() {
        guard let sport else { return }
        let defaults = SeasonDefaults.dates(for: sport)
        seasonStart = defaults.start
        seasonEnd = defaults.end
        positionSlug = nil
        formatSlug = nil
        go(sport.hasRoleChoice ? .position : .season)
    }

    private func finish() {
        guard let sport else { return }
        go(.finishing)
        Task {
            // The library downloads in the background; a slow signal never
            // holds the first plan for more than a few seconds (the sport's
            // profile is compiled in).
            let context = modelContext
            Task { await SportPackInstaller.install(slug: sport.slug, context: context) }
            for _ in 0..<10 {
                if (try? DownloadedPackRecorder(context: context).isDownloaded(slug: sport.slug, atLeastVersion: 0)) == true { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            athlete.equipmentAvailable = Array(equipment).sorted()
            athlete.trainsUnderCoach = trainsUnderCoach ?? false
            modelContext.insert(AthleteSport(
                sportSlug: sport.slug, positionSlug: positionSlug, formatSlug: formatSlug,
                seasonStart: seasonStart, seasonEnd: seasonEnd, isPrimary: true, athlete: athlete
            ))
            try? modelContext.save()
        }
    }
}

/// Downloads one sport's pack if it can. §3 offline-first: the sport's
/// profile is compiled in, so a failed download never blocks anything.
@MainActor
enum SportPackInstaller {
    static func install(slug: String, context: ModelContext) async {
        let client = APIClient(baseURL: AppConfig.backendBaseURL)
        let downloader = PackDownloader(client: client, packsDirectory: AppConfig.packsDirectory())
        guard let manifest = try? await downloader.fetchManifest() else { return }
        for pack in manifest.packs where pack.slug == slug || pack.slug == "core" {
            if (try? await downloader.download(slug: pack.slug, manifest: manifest)) != nil {
                try? DownloadedPackRecorder(context: context).record(slug: pack.slug, version: pack.version)
            }
        }
    }
}
