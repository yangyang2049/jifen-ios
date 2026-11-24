import XCTest
@testable import LinkCore
import ScoreCore

final class LinkedFootballSnapshotTests: XCTestCase {
    func testFootballSnapshotRoundTripsThroughCodable() throws {
        let state = LinkedFootballState(
            leftName: "主队",
            rightName: "客队",
            leftScore: 2,
            rightScore: 1,
            timer: FootballTimerStateV2(
                stage: 2,
                halfLengthSeconds: 45 * 60,
                elapsedSeconds: 300,
                isRunning: true,
                savedWallClockMilliseconds: 1_000,
                stoppageSeconds: [0, 120, 0, 0]
            ),
            kickedOff: true,
            finished: false
        )
        let snapshot = LinkedScoreboardSnapshot.football(state)
        let decoded = try JSONDecoder().decode(
            LinkedScoreboardSnapshot.self,
            from: try JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.footballState, state)
        XCTAssertNil(decoded.snookerState)
    }

    func testFootballSetupCarriesTheInitialSnapshot() throws {
        let state = LinkedFootballState(leftName: "A", rightName: "B")
        let setup = LinkedScoreboardSetup(
            gameType: .football,
            initialSnapshot: .football(state),
            participantNames: ["A", "B"]
        )
        let decoded = try JSONDecoder().decode(
            LinkedScoreboardSetup.self,
            from: try JSONEncoder().encode(setup)
        )
        XCTAssertEqual(decoded.gameType, .football)
        XCTAssertEqual(decoded.initialSnapshot?.footballState, state)
    }
}
