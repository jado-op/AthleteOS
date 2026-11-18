import XCTest

/// Things App Review looks for: using the app without an account
/// (guideline 5.1.1(v)). There are no leagues or other public rankings.
final class ReviewReadinessTests: XCTestCase {
    func testGuestsAreRecognisedAndSignedInAthletesAreNot() {
        let guest = Athlete(appleUserId: Athlete.guestPrefix + UUID().uuidString, birthDate: Date(timeIntervalSince1970: 1_100_000_000))
        let member = Athlete(appleUserId: "001234.abcdef.5678", birthDate: Date(timeIntervalSince1970: 1_100_000_000))
        XCTAssertTrue(guest.isGuest)
        XCTAssertFalse(member.isGuest)
    }
}
