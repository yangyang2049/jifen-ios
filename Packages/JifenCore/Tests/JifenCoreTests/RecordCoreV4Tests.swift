import RecordCore
import XCTest

final class RecordCoreV4Tests: XCTestCase {
    func testDetailedActionRoundTripsAllProjectFields() throws {
        let action = DetailedScoreAction(
            type: .roundFinished,
            epochMilliseconds: 1_700_000_000_123,
            team: .team3,
            scores: [10, 20, 30, 40, 50],
            setScores: [1, 2, 3, 4, 5],
            setNumber: 2,
            gameNumber: 7,
            roundNumber: 3,
            periodNumber: 4,
            scoreChange: -6,
            winner: .team3,
            loser: .team1,
            landlord: .team2,
            winners: [.team2, .team3],
            losers: [.team1],
            farmers: [.team2, .team3],
            participants: [.init(id: "p1", name: "A", score: 30, rank: 1, role: "landlord")],
            operationCode: "doudizhu_settle_round",
            operationPayload: "J",
            summary: "round"
        )

        let decoded = try JSONDecoder().decode(DetailedScoreAction.self, from: JSONEncoder().encode(action))
        XCTAssertEqual(decoded, action)
        XCTAssertEqual(decoded.scores, [10, 20, 30, 40])
        XCTAssertEqual(decoded.setScores, [1, 2, 3, 4])
        XCTAssertEqual(decoded.winners, [.team2, .team3])
        XCTAssertEqual(decoded.losers, [.team1])
        XCTAssertEqual(decoded.farmers, [.team2, .team3])
        XCTAssertEqual(decoded.operationPayload, "J")
    }

    func testImportedActionMayOmitTimestamp() throws {
        let action = DetailedScoreAction(type: .scoreChanged, scores: [1, 0])
        let decoded = try JSONDecoder().decode(DetailedScoreAction.self, from: JSONEncoder().encode(action))
        XCTAssertNil(decoded.epochMilliseconds)
    }

    /// Android/HarmonyOS name the football goal-clock fields verbatim, so a
    /// foreign payload must decode into them and survive re-encoding.
    func testFootballGoalClockFieldsSurviveForeignPayloadRoundTrip() throws {
        let payload = """
        [{"id":"3F16A4E4-8F3B-4C2A-9E6B-3B7C1D4E5F60","type":"scoreChanged","team":"team1",
          "scores":[1,0],"setScores":[],"participants":[],
          "scoreChange":1,"footballPeriod":2,"footballElapsedSeconds":480}]
        """
        let actions = try JSONDecoder().decode([DetailedScoreAction].self, from: Data(payload.utf8))
        XCTAssertEqual(actions.first?.footballPeriod, 2)
        XCTAssertEqual(actions.first?.footballElapsedSeconds, 480)

        let reEncoded = try JSONDecoder().decode(
            [DetailedScoreAction].self,
            from: JSONEncoder().encode(actions)
        )
        XCTAssertEqual(reEncoded, actions)

        let legacy = try JSONDecoder().decode(
            [DetailedScoreAction].self,
            from: Data(#"[{"id":"3F16A4E4-8F3B-4C2A-9E6B-3B7C1D4E5F60","type":"scoreChanged","scores":[1,0],"setScores":[],"participants":[]}]"#.utf8)
        )
        XCTAssertNil(legacy.first?.footballPeriod)
        XCTAssertNil(legacy.first?.footballElapsedSeconds)
    }
}
