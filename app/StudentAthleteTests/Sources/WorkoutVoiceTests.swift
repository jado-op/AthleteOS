import XCTest
#if canImport(Engine)
@testable import Engine
#endif

/// Talking mid-workout: what the athlete says becomes one command; pain always wins.
final class WorkoutVoiceTests: XCTestCase {
    func testWhatAnAthleteSaysBecomesACommand() {
        XCTAssertEqual(WorkoutVoiceCommand.parse("That was heavy"), .lighter)
        XCTAssertEqual(WorkoutVoiceCommand.parse("too easy"), .heavier)
        XCTAssertEqual(WorkoutVoiceCommand.parse("two more"), .moreSets(2))
        XCTAssertEqual(WorkoutVoiceCommand.parse("let's do one more set"), .moreSets(1))
        XCTAssertEqual(WorkoutVoiceCommand.parse("skip this one"), .skip)
        XCTAssertEqual(WorkoutVoiceCommand.parse("Done"), .logSet)
        XCTAssertNil(WorkoutVoiceCommand.parse("what's for dinner"))
    }

    func testPainAlwaysWinsAndNamesThePlace() {
        XCTAssertEqual(WorkoutVoiceCommand.parse("my knee feels off and it hurts"), .pain(.knee))
        XCTAssertEqual(WorkoutVoiceCommand.parse("that was heavy and my back hurts"), .pain(.back))
        XCTAssertEqual(WorkoutVoiceCommand.parse("pain"), .pain(.other))
        XCTAssertEqual(WorkoutVoiceCommand.parse("ouch my shoulder"), .pain(.shoulder))
    }

    func testGerman() {
        XCTAssertEqual(WorkoutVoiceCommand.parse("Das war zu schwer"), .lighter)
        XCTAssertEqual(WorkoutVoiceCommand.parse("zu leicht"), .heavier)
        XCTAssertEqual(WorkoutVoiceCommand.parse("noch zwei"), .moreSets(2))
        XCTAssertEqual(WorkoutVoiceCommand.parse("Mein Knie tut weh"), .pain(.knee))
        XCTAssertEqual(WorkoutVoiceCommand.parse("überspringen"), .skip)
    }
}
