import Foundation
import XCTest

final class EntitlementTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let start = Date(timeIntervalSince1970: 100_000)

    func testTrialStartsAtFirstOpenAndClaimDoesNotResetIt() {
        var rights = Entitlement(firstOpen: start, proStartedAt: start)
        XCTAssertFalse(Launch.freePeriod)
        XCTAssertTrue(rights.hasPro(at: start.addingTimeInterval(day * 29), free: false))
        XCTAssertFalse(rights.hasPro(at: start.addingTimeInterval(day * 30), free: false))
        rights.applyVerified(trial: true, originalDate: start.addingTimeInterval(day * 5), revoked: false)
        XCTAssertFalse(rights.hasPro(at: start.addingTimeInterval(day * 30), free: false))
    }

    func testRestoredTrialKeepsEarlierOriginalDate() {
        var rights = Entitlement(firstOpen: start.addingTimeInterval(day * 40))
        rights.applyVerified(trial: true, originalDate: start, revoked: false)
        XCTAssertEqual(rights.trialStart, start)
        XCTAssertFalse(rights.hasPro(at: start.addingTimeInterval(day * 40), free: false))
    }

    func testVerifiedBuyoutOfflineAndRevocation() throws {
        var rights = Entitlement(firstOpen: start)
        rights.applyVerified(trial: false, originalDate: start, revoked: false)
        rights.latestSeen = start.addingTimeInterval(day * 40)
        let cached = try JSONDecoder().decode(Entitlement.self, from: JSONEncoder().encode(rights))
        XCTAssertTrue(cached.hasPro(at: start, free: false))
        rights.applyVerified(trial: false, originalDate: start, revoked: true)
        XCTAssertFalse(rights.hasPro(at: start, free: false))
    }

    func testProSnapshotSurvivesLocalExpiryUntilFinish() throws {
        let rights = Entitlement(firstOpen: start)
        var board = Board()
        try board.play.active.put(Combatant(name: "A", score: 10, hp: 12, maxHP: 12))
        try board.play.active.start(pro: rights.hasPro(at: start))
        XCTAssertFalse(rights.hasPro(at: start.addingTimeInterval(day * 30), free: false))
        XCTAssertTrue(board.play.active.proInBattle)
        board.play.finish()
        board.play.nextEncounter()
        XCTAssertFalse(board.play.active.proInBattle)
    }

    func testRatingAtThirdDistinctDayThenOncePerVersionWhenIdle() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var review = ReviewProgress()
        review.recordUse(on: start, calendar: calendar)
        review.recordUse(on: start.addingTimeInterval(60), calendar: calendar)
        review.recordUse(on: start.addingTimeInterval(day), calendar: calendar)
        review.completedEncounter()
        XCTAssertFalse(review.takeRequest(version: "1", idle: true))
        review.recordUse(on: start.addingTimeInterval(day * 2), calendar: calendar)
        XCTAssertFalse(review.takeRequest(version: "1", idle: true))
        review.completedEncounter()
        XCTAssertFalse(review.takeRequest(version: "1", idle: false))
        XCTAssertTrue(review.takeRequest(version: "1", idle: true))
        XCTAssertFalse(review.takeRequest(version: "1", idle: true))
        XCTAssertTrue(review.takeRequest(version: "2", idle: true))
    }
}
