import SwiftUI

/// The Academy tab holds the athlete's twin and their progress (owner,
/// 2026-11-18: Campus and Progress are no longer tabs). One quiet switch at
/// the top — Twin | Progress — and Campus's short lessons one row away in
/// the twin's library. Anything that used to open the Campus or Progress
/// tab lands here (MainTabView).
enum AcademyPage: String, CaseIterable, Sendable {
    case twin, progress

    var title: String {
        switch self {
        case .twin: "Twin"
        case .progress: "Progress"
        }
    }
}

@MainActor
final class AcademyNavigation: ObservableObject {
    static let shared = AcademyNavigation()
    @Published var page: AcademyPage = .twin
    /// Campus's short lessons, opened over the Academy.
    @Published var showingLessons = false
    /// A briefing to open (Home's "Next step · read").
    @Published var pendingBriefingID: String?
}

/// The top of both pages: the profile button and the Twin | Progress switch.
struct AcademyPageSwitcher: View {
    let name: String?
    @ObservedObject private var navigation = AcademyNavigation.shared

    var body: some View {
        HStack(spacing: 12) {
            ProfileButton(name: name)
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                ForEach(AcademyPage.allCases, id: \.self) { page in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { navigation.page = page }
                    } label: {
                        Text(page.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(navigation.page == page ? Color(rgb: 0x0B0B14) : AppTheme.ink.opacity(0.8))
                            .padding(.horizontal, 16)
                            .frame(height: 32)
                            .background(Capsule().fill(navigation.page == page ? AppTheme.starlight : .clear))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(navigation.page == page ? .isSelected : [])
                }
            }
            .padding(3)
            .glassCapsule()
            Spacer(minLength: 0)
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.top, 8)
    }
}

struct AcademyTabView: View {
    let athlete: Athlete
    let week: GeneratedWeek?
    let onPlanInputsChanged: () -> Void
    @ObservedObject private var navigation = AcademyNavigation.shared

    var body: some View {
        Group {
            switch navigation.page {
            case .twin: AcademyHomeView(athlete: athlete)
            case .progress: ProgressTabView(athlete: athlete, week: week, onPlanInputsChanged: onPlanInputsChanged)
            }
        }
        .sheet(isPresented: $navigation.showingLessons) {
            CampusView(athlete: athlete)
                .overlay(alignment: .topTrailing) {
                    Button { navigation.showingLessons = false } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                            .frame(width: 36, height: 36)
                            .glassCapsule()
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Close")
                    .buttonStyle(.plain)
                    .padding(.top, 14)
                    .padding(.trailing, 20)
                    .accessibilityLabel("Close lessons")
                }
        }
    }
}
