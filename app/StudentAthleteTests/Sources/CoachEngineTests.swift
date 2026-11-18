import XCTest

final class CoachEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: now)!
    }

    private func item(_ slug: String, muscles: [String: Double], qualities: [String: Double] = ["lower-body-strength": 1.0]) -> CatalogueItem {
        CatalogueItem(
            slug: slug, name: slug.capitalized, kind: "exercise", qualities: qualities, muscles: muscles,
            equipment: [], surface: "anywhere", minAge: 13, supervisionLevel: "SELF",
            setup: [], execution: [], cues: [], mistakes: [], progressions: [], regressions: [], substitutes: [],
            defaultDose: Dose(kind: "reps", sets: 3, reps: 8), restSeconds: 60, startPose: "hinge", endPose: "hinge",
            unilateralEligible: nil, tempoEligible: nil, prop: nil, variant: nil, baseSlug: nil,
            constraintAxes: nil, equipmentChain: nil, unilateralPosePattern: nil, unilateralStabilityQuality: nil,
            itemSportSlug: nil
        )
    }

    private var catalogue: Catalogue {
        let items = [
            item("curl", muscles: ["biceps-brachii": 1.0, "brachialis": 0.5], qualities: ["upper-body-pull": 1.0]),
            item("squat", muscles: ["rectus-femoris": 1.0]),
        ]
        return Catalogue(itemsBySlug: Dictionary(uniqueKeysWithValues: items.map { ($0.slug, $0) }))
    }

    /// The original app idea: "you've only trained arms lately" — the
    /// balance is computed from the sets actually logged.
    func testArmsOnlyTrainingIsAllArmsInTheBalance() {
        let armSessions = (1...4).map { offset in
            CoachSession(date: day(-offset), minutes: 30, rpe: 6, sets: Array(repeating: CoachSet(itemSlug: "curl", reps: 10, weightKg: 12), count: 4))
        }
        let balance = CoachEngine.muscleBalance(sessions: armSessions, catalogue: catalogue, now: now)
        XCTAssertEqual(balance[.arm] ?? 0, 1, accuracy: 0.0001, "all logged volume was arms")
        XCTAssertNil(balance[.quadriceps])
    }

    func testOnlyTheLastTwoWeeksCount() {
        let sessions = [
            CoachSession(date: day(-30), minutes: 40, rpe: 7, sets: [CoachSet(itemSlug: "curl", reps: 5)]),
            CoachSession(date: day(-2), minutes: 40, rpe: 7, sets: [CoachSet(itemSlug: "squat", reps: 5, weightKg: 70)]),
        ]
        let balance = CoachEngine.muscleBalance(sessions: sessions, catalogue: catalogue, now: now)
        XCTAssertEqual(balance[.quadriceps] ?? 0, 1, accuracy: 0.0001)
        XCTAssertTrue(CoachEngine.muscleBalance(sessions: [], catalogue: catalogue, now: now).isEmpty)
    }
}
