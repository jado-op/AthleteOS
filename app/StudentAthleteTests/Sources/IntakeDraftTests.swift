import XCTest
#if canImport(Engine)
@testable import Engine
#endif

/// "Create my twin": a first interview closed half-way is kept as a draft and
/// only creates the twin when finished; edits can clear an answer.
final class IntakeDraftTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_795_000_000)

    func testClosingHalfWayKeepsADraftWithoutCreatingTheTwin() {
        let state = AcademyStore.savingDraft(["drive": "mastery", "pressure": "", "goal": "  Start every game "],
                                             at: "mistake", in: AcademyState(), date: now)
        XCTAssertNil(state.intakeDoneAt, "the twin is only created when the interview is done")
        XCTAssertTrue(state.intake.isEmpty)
        XCTAssertEqual(state.intakeDraft?.answers, ["drive": "mastery", "goal": "Start every game"])
        XCTAssertEqual(state.intakeDraft?.questionID, "mistake")
    }

    func testNothingAnsweredLeavesNoDraft() {
        let state = AcademyStore.savingDraft(["drive": "", "goal": "   "], at: "drive", in: AcademyState(), date: now)
        XCTAssertNil(state.intakeDraft)
    }

    func testFinishingCreatesTheTwinAndDropsTheDraft() {
        var state = AcademyStore.savingDraft(["drive": "mastery"], at: "pressure", in: AcademyState(), date: now)
        state = AcademyStore.answering(["drive": "mastery", "pressure": "narrow"], in: state, at: now)
        XCTAssertEqual(state.intakeDoneAt, now)
        XCTAssertNil(state.intakeDraft)
        XCTAssertEqual(state.intake, ["drive": "mastery", "pressure": "narrow"])
    }

    func testAfterTheTwinExistsDraftsAreIgnored() {
        let done = AcademyStore.answering(["drive": "mastery"], in: AcademyState(), at: now)
        let state = AcademyStore.savingDraft(["drive": "winning"], at: "drive", in: done, date: now)
        XCTAssertEqual(state, done)
    }

    func testAClearedChoiceIsRemovedOnSave() {
        let done = AcademyStore.answering(["drive": "mastery", "pressure": "narrow"], in: AcademyState(), at: now)
        let edited = AcademyStore.answering(["drive": "", "pressure": "tense"], in: done, at: now.addingTimeInterval(60))
        XCTAssertEqual(edited.intake, ["pressure": "tense"])
        XCTAssertEqual(edited.intakeDoneAt, now, "editing keeps the twin's creation date")
    }

    func testFreeTextIsCappedAtTheLimit() {
        let long = String(repeating: "a", count: AcademyStore.freeTextLimit + 50)
        let state = AcademyStore.answering(["goal": long], in: AcademyState(), at: now)
        XCTAssertEqual(state.intake["goal"]?.count, AcademyStore.freeTextLimit)
    }

    func testAnsweredCountOnlyCountsRealAnswersToTheseQuestions() {
        let answers = ["drive": "mastery", "pressure": "", "goal": "  ", "old": "x"]
        XCTAssertEqual(AcademyStore.answeredCount(answers, of: ["drive", "pressure", "goal"]), 1)
    }

    func testStateSavedBeforeDraftsStillLoads() throws {
        // A v3 state written by the earlier build, without `intakeDraft`.
        let json = #"{"version":3,"intake":{"drive":"mastery"},"read":{},"performances":[]}"#
        let state = try JSONDecoder().decode(AcademyState.self, from: Data(json.utf8))
        XCTAssertEqual(state.intake, ["drive": "mastery"])
        XCTAssertNil(state.intakeDraft)
    }

    func testDraftSurvivesSaveAndLoad() {
        let defaults = UserDefaults(suiteName: "IntakeDraftTests")!
        defaults.removePersistentDomain(forName: "IntakeDraftTests")
        let state = AcademyStore.savingDraft(["drive": "team"], at: "pressure", in: AcademyState(), date: now)
        AcademyStore.save(state, defaults)
        XCTAssertEqual(AcademyStore.load(defaults).intakeDraft, state.intakeDraft)
        defaults.removePersistentDomain(forName: "IntakeDraftTests")
    }
}
