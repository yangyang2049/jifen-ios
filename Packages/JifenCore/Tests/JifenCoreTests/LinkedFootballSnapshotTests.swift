import XCTest
@testable import LinkCore
import ScoreCore

/// M4：联动足球快照直接携带 `FootballMatchState`，时钟锚点、分秒余量与
/// 补时/换边/完赛标记必须无损往返。
final class LinkedFootballSnapshotTests: XCTestCase {
    func testFootballSnapshotRoundTripsThroughCodable() throws {
        let state = FootballMatchState(
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
            stoppageHistory: [120],
            isFiveAside: false,
            kickedOff: true,
            sidesSwapped: true,
            finished: false,
            elapsedSubsecondMilliseconds: 640
        )
        let snapshot = LinkedScoreboardSnapshot.football(state)
        let decoded = try JSONDecoder().decode(
            LinkedScoreboardSnapshot.self,
            from: try JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.footballState, state)
        // 时钟锚点与分秒余量必须原样到达对端。
        XCTAssertEqual(decoded.footballState?.timer.savedWallClockMilliseconds, 1_000)
        XCTAssertEqual(decoded.footballState?.elapsedSubsecondMilliseconds, 640)
        XCTAssertEqual(decoded.footballState?.timer.stoppageSeconds, [0, 120, 0, 0])
        XCTAssertEqual(decoded.footballState?.stoppageHistory, [120])
        XCTAssertTrue(decoded.footballState?.sidesSwapped == true)
        XCTAssertNil(decoded.snookerState)
    }

    func testFootballSetupCarriesTheInitialSnapshot() throws {
        let state = FootballMatchState(leftName: "A", rightName: "B")
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
