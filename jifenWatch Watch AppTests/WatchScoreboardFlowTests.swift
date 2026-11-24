import XCTest
import ScoreCore
import SessionCore
@testable import jifenWatch_Watch_App

/// 计分流程端到端测试：加分 → 局末 → 比赛结束 → 撤销。
/// 覆盖此前完全没有单测的「引擎驱动计分」路径（原 89 个测试集中在 setup / rest / doubles 配置层）。
@MainActor
final class WatchScoreboardFlowTests: XCTestCase {

    /// 走生产同一条构造路径（ScoreboardSessionFactory），避免测试里手搓 session
    /// 与真实计分板的 reducer/participants 装配产生偏差。
    private func makeCore(
        rules: RallyRuleSet,
        gameType: GameType = .pingpong,
        openingServer: MatchSide = .left
    ) throws -> ScoreSessionCore<RallyMatchReducer> {
        try XCTUnwrap(ScoreboardSessionFactory.rally(
            gameType: gameType,
            leftName: "A",
            rightName: "B",
            rules: rules,
            openingServer: openingServer
        ))
    }

    private func point(_ core: ScoreSessionCore<RallyMatchReducer>, _ side: MatchSide) async -> RallyMatchState {
        let result = await core.dispatch(
            actorId: "watch",
            intent: .pointWon(side),
            at: Int64(Date().timeIntervalSince1970 * 1_000)
        )
        guard case .accepted(let session, _) = result else {
            XCTFail("point should be accepted")
            return await core.snapshot().state
        }
        return session.state
    }

    // MARK: - 加分

    func testScoringAccumulatesPointsAndTracksServingSide() async throws {
        let core = try makeCore(rules: .pingPong(maxSets: 3, matchCompletionMode: .bestOf))

        var state = await point(core, .left)
        XCTAssertEqual(state.leftPoints, 1)
        XCTAssertEqual(state.rightPoints, 0)
        XCTAssertEqual(state.servingSide, .left, "得分方继续发球")

        state = await point(core, .right)
        XCTAssertEqual(state.leftPoints, 1)
        XCTAssertEqual(state.rightPoints, 1)
        XCTAssertEqual(state.servingSide, .right)
    }

    // MARK: - 局末

    func testSetCompletesAtTargetAndResetsPoints() async throws {
        let core = try makeCore(rules: .pingPong(maxSets: 3, matchCompletionMode: .bestOf))

        var state = await core.snapshot().state
        for _ in 0..<11 {
            state = await point(core, .left)
        }

        XCTAssertEqual(state.leftSets, 1, "11 分先到即赢下该局")
        XCTAssertEqual(state.rightSets, 0)
        XCTAssertEqual(state.leftPoints, 0, "新局分数归零")
        XCTAssertEqual(state.rightPoints, 0)
        XCTAssertFalse(state.finished, "三局两胜还需一局")
    }

    func testWinByTwoExtendsBeyondTarget() async throws {
        let core = try makeCore(rules: .pingPong(maxSets: 3, matchCompletionMode: .bestOf))

        // 10:10 后必须净胜两分
        for _ in 0..<10 { _ = await point(core, .left) }
        for _ in 0..<10 { _ = await point(core, .right) }

        var state = await point(core, .left)
        XCTAssertEqual(state.leftSets, 0, "11:10 不算赢，需净胜两分")

        state = await point(core, .left)
        XCTAssertEqual(state.leftSets, 1, "12:10 赢下该局")
    }

    // MARK: - 比赛结束

    func testMatchFinishesWhenSetsToWinReached() async throws {
        let core = try makeCore(rules: .pingPong(maxSets: 3, matchCompletionMode: .bestOf))

        for _ in 0..<2 {
            for _ in 0..<11 {
                _ = await point(core, .left)
            }
        }

        let state = await core.snapshot().state
        XCTAssertEqual(state.leftSets, 2)
        XCTAssertTrue(state.finished, "三局两胜先到 2 局即结束")
    }

    func testPlayAllModeRequiresAllSets() async throws {
        // playAll = leftSets + rightSets >= maxSets，即必须打满全部局数，
        // 不是「先到多数局」。与 bestOf 的差别就在这里。
        let core = try makeCore(rules: .pingPong(maxSets: 3, matchCompletionMode: .playAll))

        for _ in 0..<11 { _ = await point(core, .left) }
        var state = await core.snapshot().state
        XCTAssertEqual(state.leftSets, 1)
        XCTAssertFalse(state.finished, "playAll 赢下 1 局不结束")

        for _ in 0..<11 { _ = await point(core, .right) }
        state = await core.snapshot().state
        XCTAssertEqual(state.leftSets, 1)
        XCTAssertEqual(state.rightSets, 1)
        XCTAssertFalse(state.finished, "1:1 仍未打满 3 局")

        for _ in 0..<11 { _ = await point(core, .left) }
        state = await core.snapshot().state
        XCTAssertEqual(state.leftSets, 2)
        XCTAssertEqual(state.rightSets, 1)
        XCTAssertTrue(state.finished, "累计打满 3 局后结束")
    }

    // MARK: - 撤销

    func testUndoRevertsLastPoint() async throws {
        let core = try makeCore(rules: .pingPong(maxSets: 3, matchCompletionMode: .bestOf))

        _ = await point(core, .left)
        _ = await point(core, .left)
        let beforeUndo = await core.snapshot().state
        XCTAssertEqual(beforeUndo.leftPoints, 2)

        let undone = await core.undo(actorId: "watch")
        XCTAssertTrue(undone)
        let afterUndo = await core.snapshot().state
        XCTAssertEqual(afterUndo.leftPoints, 1, "撤销回退一分")
    }

    func testUndoRevertsThePointThatEndedTheSet() async throws {
        let core = try makeCore(rules: .pingPong(maxSets: 3, matchCompletionMode: .bestOf))

        for _ in 0..<11 { _ = await point(core, .left) }
        let afterSet = await core.snapshot().state
        XCTAssertEqual(afterSet.leftSets, 1)
        XCTAssertEqual(afterSet.leftPoints, 0, "新局从 0 开始")

        // 撤销的是「赢下该局的那一分」：局分回退、该局分数回到 10。
        _ = await core.undo(actorId: "watch")
        let state = await core.snapshot().state
        XCTAssertEqual(state.leftSets, 0, "局分回退")
        XCTAssertEqual(state.leftPoints, 10, "回到 10 分")
        XCTAssertFalse(state.finished)
    }

    // MARK: - 重置

    func testResetClearsScoreAndSets() async throws {
        let core = try makeCore(rules: .pingPong(maxSets: 3, matchCompletionMode: .bestOf))

        for _ in 0..<5 { _ = await point(core, .left) }
        _ = await core.dispatch(
            actorId: "watch",
            intent: .reset,
            at: Int64(Date().timeIntervalSince1970 * 1_000)
        )

        let state = await core.snapshot().state
        XCTAssertEqual(state.leftPoints, 0)
        XCTAssertEqual(state.rightPoints, 0)
        XCTAssertEqual(state.leftSets, 0)
        XCTAssertFalse(state.finished)
    }

    // MARK: - 官方休息期间禁止计分

    func testScoringRejectedDuringOfficialBreak() async throws {
        let core = try makeCore(rules: .badminton(maxSets: 3))

        // 通过 setOfficialBreakState 进入「休息进行中」
        let breakState = OfficialBreakState(
            sport: .badminton,
            kind: .midGame,
            durationSeconds: 60
        )
        _ = await core.dispatch(
            actorId: "watch",
            intent: .setOfficialBreakState(breakState),
            at: Int64(Date().timeIntervalSince1970 * 1_000)
        )

        let result = await core.dispatch(
            actorId: "watch",
            intent: .pointWon(.left),
            at: Int64(Date().timeIntervalSince1970 * 1_000)
        )
        if case .accepted = result {
            XCTFail("休息期间不应接受计分")
        }
    }
}
