import XCTest
@testable import jifen

/// 小组预览解码：查无此组时服务端返回 sport 空串，解码不得抛错（对齐后端契约 v1「状态码口径」）。
final class GroupPreviewDecodingTests: XCTestCase {

    func testLegacyGameCannotInventFrozenRulesOrSeats() throws {
        let snapshot = try JSONDecoder().decode(GroupGameSnapshot.self, from: Data("""
        {"gameId":"game","groupId":"group","activityId":"activity","clientSessionId":"session","format":"singles","state":"started","rules":null,"participants":null}
        """.utf8))
        XCTAssertFalse(snapshot.hasValidFrozenConfiguration(groupID: "group", gameID: "game", sport: .badminton))
    }

    func testFrozenGameRequiresExactDistinctSeatsAndMatchingRules() {
        let rules = GroupMatchRules(sport: .badminton, maxSets: 3, matchCompletionMode: "best_of", pointsToWinSet: 21, pointCap: 30, winByTwo: true, useRallyScoring: false, gamesPerSet: 6, tieBreakPoints: 7, setScoringMode: "regular", usesNoAdScoring: false)
        var game = GroupGameSnapshot(gameId: "game", groupId: "group", activityId: "activity", clientSessionId: "session", format: .singles, state: "started", rules: rules, participants: [.init(memberId: "one", side: "A", seat: 0), .init(memberId: "two", side: "B", seat: 0)])
        func valid(_ value: GroupGameSnapshot) -> Bool { value.hasValidFrozenConfiguration(groupID: "group", gameID: "game", sport: .badminton) }
        XCTAssertTrue(valid(game))
        XCTAssertFalse(game.hasValidFrozenConfiguration(groupID: "other", gameID: "game", sport: .badminton))
        XCTAssertFalse(game.hasValidFrozenConfiguration(groupID: "group", gameID: "other", sport: .badminton))
        XCTAssertFalse(game.hasValidFrozenConfiguration(groupID: "group", gameID: "game", sport: .tennis))
        let original = game
        game.participants?[1].memberId = "one"; XCTAssertFalse(valid(game))
        game = original; game.participants?[1].side = "A"; XCTAssertFalse(valid(game))
        game = original; game.participants?[1].seat = 1; XCTAssertFalse(valid(game))
        game = original; game.participants?[1].memberId = "  "; XCTAssertFalse(valid(game))
        game = original; game.format = .doubles; XCTAssertFalse(valid(game))
        game = original; game.rules?.version = 2; XCTAssertFalse(valid(game))
        game = original; game.format = .doubles
        game.participants = [.init(memberId: "one", side: "A", seat: 0), .init(memberId: "two", side: "A", seat: 1), .init(memberId: "three", side: "B", seat: 0), .init(memberId: "four", side: "B", seat: 1)]
        XCTAssertTrue(valid(game))
    }

    @MainActor func testReturnedAccountStillRejectsAnOldRequestGeneration() {
        let store = GroupStore(observeConnectivity: false)
        store.sessionDidChange(userID: "unit-group-a")
        let revision = store.identityRevision
        XCTAssertTrue(store.matchesIdentity("unit-group-a", revision: revision))
        store.sessionDidChange(userID: "unit-group-b")
        XCTAssertFalse(store.matchesIdentity("unit-group-a", revision: revision))
        store.sessionDidChange(userID: "unit-group-a")
        XCTAssertFalse(store.matchesIdentity("unit-group-a", revision: revision))
        store.sessionDidChange(userID: nil)
    }

    private func decode(_ json: String) throws -> GroupPreview {
        try JSONDecoder().decode(GroupPreview.self, from: Data(json.utf8))
    }

    func testNotFoundPreviewDecodesWithNilSport() throws {
        let preview = try decode("""
        {"groupNo":"12345678","name":"","description":"","sport":"","memberCount":0,"joinPolicy":"","availability":"not_found"}
        """)
        XCTAssertEqual(preview.availability, "not_found")
        XCTAssertNil(preview.sport)
        XCTAssertEqual(preview.groupNo, "12345678")
    }

    func testKnownAvailabilityStillMapsSport() throws {
        let preview = try decode("""
        {"groupNo":"87654321","name":"周末球局","description":"三点开始","sport":"table_tennis","memberCount":6,"joinPolicy":"approval","availability":"available"}
        """)
        XCTAssertEqual(preview.sport, .tableTennis)
        XCTAssertEqual(preview.memberCount, 6)
        XCTAssertEqual(preview.joinPolicy, "approval")
    }

    func testMissingKeysFallBackToEmpty() throws {
        let preview = try decode("""
        {"availability":"archived"}
        """)
        XCTAssertEqual(preview.availability, "archived")
        XCTAssertNil(preview.sport)
        XCTAssertTrue(preview.name.isEmpty)
        XCTAssertEqual(preview.memberCount, 0)
    }
}
