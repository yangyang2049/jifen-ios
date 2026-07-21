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
            participants: [.init(id: "p1", name: "A", score: 30, rank: 1, role: "landlord")],
            operationCode: "doudizhu_settle_round",
            summary: "round"
        )

        let decoded = try JSONDecoder().decode(DetailedScoreAction.self, from: JSONEncoder().encode(action))
        XCTAssertEqual(decoded, action)
        XCTAssertEqual(decoded.scores, [10, 20, 30, 40])
        XCTAssertEqual(decoded.setScores, [1, 2, 3, 4])
    }

    func testImportedActionMayOmitTimestamp() throws {
        let action = DetailedScoreAction(type: .scoreChanged, scores: [1, 0])
        let decoded = try JSONDecoder().decode(DetailedScoreAction.self, from: JSONEncoder().encode(action))
        XCTAssertNil(decoded.epochMilliseconds)
    }
}
