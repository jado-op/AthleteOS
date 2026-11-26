import SwiftUI

/// The Academy tab: two pages under one quiet switch (owner, 2026-11-19) —
/// Twin (the athlete as widgets, with Trends) and Campus (questions that form
/// a picture of them, the lessons and long reads). The training calendar is in
/// the Workout tab (owner, 2026-11-26).
enum AcademyPage: String, CaseIterable, Sendable {
    case twin, campus

    var title: String {
        switch self {
        case .twin: "Twin"
        case .campus: "Campus"
        }
    }
}

@MainActor
final class AcademyNavigation: ObservableObject {
    static let shared = AcademyNavigation()
    @Published var page: AcademyPage = .twin
    /// Set to open the Campus page (e.g. a lesson picked in a briefing).
    @Published var showingLessons = false
    /// A briefing to open (Home's "Next step · read").
    @Published var pendingBriefingID: String?
    /// Home's "Meet your twin": open the interview.
    @Published var pendingInterview = false
}

/// The Workout tab's own routes: the training calendar (what you did lives
/// next to what to do; owner, 2026-11-26 — it left the Academy).
@MainActor
final class WorkoutNavigation: ObservableObject {
    static let shared = WorkoutNavigation()
    @Published var showingCalendar = false
}

/// The top of every page: the profile button and the Twin · Campus switch.
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
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, 12)
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
            case .campus: CampusPage(athlete: athlete)
            }
        }
        .onAppear(perform: openLessonsIfAsked)
        .onChange(of: navigation.showingLessons) { openLessonsIfAsked() }
    }

    /// Old routes asked for the lessons sheet: they open the Campus page now.
    private func openLessonsIfAsked() {
        guard navigation.showingLessons else { return }
        navigation.showingLessons = false
        withAnimation(.easeInOut(duration: 0.2)) { navigation.page = .campus }
    }
}
