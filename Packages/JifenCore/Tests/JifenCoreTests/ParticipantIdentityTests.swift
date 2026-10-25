import XCTest
@testable import ScoreCore

final class ParticipantIdentityTests: XCTestCase {
    func testAliasLimitAndHiddenNamesStillConsumeCapacity() throws {
        var ledger = ParticipantIdentityLedger()
        let first = try ledger.link(name: "  Yang   Yang ")
        XCTAssertEqual(try ledger.link(name: "yang yang").id, first.id)
        _ = try ledger.link(name: "YY"); _ = try ledger.link(name: "小杨")
        ledger.setVisible(aliasId: first.id, visible: false)
        XCTAssertThrowsError(try ledger.link(name: "第四个"))
        ledger.unlink(aliasId: first.id)
        XCTAssertNoThrow(try ledger.link(name: "第四个"))
    }

    func testUnlinkOnlyRevokesAliasHistoryAndKeepsExplicitSelections() throws {
        var ledger = ParticipantIdentityLedger()
        let alias = try ledger.link(name: "YY")
        ledger.linkClaims([.init(libraryId: ledger.libraryId, recordKey: "old", seatKey: "left", aliasId: alias.id, nameSnapshot: "YY")])
        try ledger.register(recordKey: "new", selections: ["left": .init(name: "YY", personRef: ledger.person)])
        ledger.setVisible(aliasId: alias.id, visible: false)
        XCTAssertEqual(ledger.personalSeats(recordKey: "old"), ["left"])
        ledger.unlink(aliasId: alias.id)
        XCTAssertTrue(ledger.personalSeats(recordKey: "old").isEmpty)
        XCTAssertEqual(ledger.personalSeats(recordKey: "new"), ["left"])
    }

    func testSamePersonCannotOccupyTwoSeatsButOrdinaryNamesCanMatch() throws {
        var ledger = ParticipantIdentityLedger()
        XCTAssertThrowsError(try ledger.register(recordKey: "double", selections: [
            "left-top": .init(name: "杨扬", personRef: ledger.person),
            "left-bottom": .init(name: "YY", personRef: ledger.person)]))
        XCTAssertNoThrow(try ledger.register(recordKey: "ordinary", selections: [
            "left": .init(name: "小林"), "right": .init(name: "小林")]))
        let typed = ParticipantIdentityRules.retainingIdentity(.init(name: "YY", personRef: ledger.person), afterEditing: "别人")
        XCTAssertNil(typed.personRef)
    }

    func testAccountAdoptionPreservesSnapshotsAndRejectsAnotherAccount() throws {
        var ledger = ParticipantIdentityLedger()
        try ledger.register(recordKey: "record", selections: ["left": .init(name: "我", personRef: ledger.person)])
        let account = ParticipantPersonRef(id: "person-a", kind: .account)
        try ledger.adopt(accountId: "a", personRef: account)
        XCTAssertEqual(ledger.recordSelections["record"]?["left"]?.name, "我")
        XCTAssertEqual(ledger.recordSelections["record"]?["left"]?.personRef, account)
        XCTAssertThrowsError(try ledger.adopt(accountId: "b", personRef: .init(id: "person-b", kind: .account)))
    }

    func testTeamNamesAndRevokedClaimsCannotBeReactivatedImplicitly() throws {
        var ledger = ParticipantIdentityLedger()
        XCTAssertThrowsError(try ledger.link(name: "红队", participantKind: "TEAM"))
        var claim = ParticipantHistoricalClaim(libraryId: ledger.libraryId, recordKey: "old", seatKey: "left", nameSnapshot: "YY", revoked: true, revision: 2)
        ledger.linkClaims([claim]); claim.revoked = false; claim.revision = 1
        ledger.linkClaims([claim])
        XCTAssertTrue(ledger.claims[0].revoked)
    }
}
