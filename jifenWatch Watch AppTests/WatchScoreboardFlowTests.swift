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

    // MARK: - 续赛浮条文案

    func testBasketballTrainingResumeUsesScoringWording() {
        let now = Date()
        let trainingSession = WatchResumeSession(
            startedAt: now,
            scoreLine: "2/3 = 67%",
            emoji: "🏀",
            payload: .basketballTraining(
                mode: .twoPoint,
                history: [
                    WatchBasketballTrainingShot(points: 2, made: true, timestamp: now)
                ]
            )
        )
        let matchSession = WatchResumeSession(
            startedAt: now,
            scoreLine: "1 : 0",
            emoji: "🎱",
            payload: .nineBall(
                state: NineBallChaseState.initial(
                    playerCount: 2,
                    playerNames: ["选手 1", "选手 2"]
                ),
                undoStates: []
            )
        )

        XCTAssertTrue(trainingSession.isTrainingSession)
        XCTAssertFalse(matchSession.isTrainingSession)
        XCTAssertEqual(
            trainingSession.resumeActionTitle,
            NSLocalizedString("watch_continue_scoring", value: "继续计分", comment: "")
        )
        XCTAssertEqual(
            trainingSession.discardActionTitle,
            NSLocalizedString("watch_resume_discard_training", value: "放弃未完成训练", comment: "")
        )
        XCTAssertEqual(
            matchSession.resumeActionTitle,
            NSLocalizedString("watch_continue_match", value: "继续比赛", comment: "")
        )
        XCTAssertEqual(
            matchSession.discardActionTitle,
            NSLocalizedString("watch_resume_discard", value: "放弃未完成比赛", comment: "")
        )
        XCTAssertNotEqual(trainingSession.resumeActionTitle, matchSession.resumeActionTitle)
        XCTAssertNotEqual(trainingSession.discardActionTitle, matchSession.discardActionTitle)
    }

    // MARK: - 支持页与微信群二维码分语言路由

    func testSupportLinksAndWeChatGroupLocaleRouting() {
        let zhHans = Locale(identifier: "zh-Hans-CN")
        let zhHant = Locale(identifier: "zh-Hant-TW")
        let enUS = Locale(identifier: "en-US")
        let jaJP = Locale(identifier: "ja-JP")

        XCTAssertTrue(WatchSupportLink.isSimplifiedChinese(locale: zhHans))
        XCTAssertFalse(WatchSupportLink.isSimplifiedChinese(locale: zhHant))
        XCTAssertFalse(WatchSupportLink.isSimplifiedChinese(locale: enUS))
        XCTAssertFalse(WatchSupportLink.isSimplifiedChinese(locale: jaJP))

        XCTAssertTrue(WatchSupportLink.showsWeChatGroup(locale: zhHans))
        XCTAssertTrue(WatchSupportLink.showsWeChatGroup(locale: zhHant))
        XCTAssertFalse(WatchSupportLink.showsWeChatGroup(locale: enUS))
        XCTAssertFalse(WatchSupportLink.showsWeChatGroup(locale: jaJP))

        XCTAssertEqual(WatchSupportLink.contact(for: zhHans), "https://jifenqi.com/contact")
        XCTAssertEqual(WatchSupportLink.feedback(for: zhHans), "https://jifenqi.com/feedback")
        XCTAssertEqual(WatchSupportLink.contactQRImageName(for: zhHans), "watch_contact_qr")
        XCTAssertEqual(WatchSupportLink.feedbackQRImageName(for: zhHans), "watch_feedback_qr")

        for intl in [zhHant, enUS, jaJP] {
            XCTAssertEqual(WatchSupportLink.contact(for: intl), "https://iscoreboard.live/contact")
            XCTAssertEqual(WatchSupportLink.feedback(for: intl), "https://iscoreboard.live/feedback")
            XCTAssertEqual(WatchSupportLink.contactQRImageName(for: intl), "watch_contact_qr_intl")
            XCTAssertEqual(WatchSupportLink.feedbackQRImageName(for: intl), "watch_feedback_qr_intl")
        }

        XCTAssertEqual(WatchSupportLink.wechatGroup, "https://c.weixin.com/g/n1ltxDV-Ogi46YYG")
    }

    // MARK: - 联动确认页按表盘尺寸自适应

    func testLinkedSetupConfirmationLayoutScalesAcrossWatchSizes() {
        let compact40 = WatchLinkedSetupConfirmationLayout.resolve(screenSize: CGSize(width: 162, height: 197))
        let medium44 = WatchLinkedSetupConfirmationLayout.resolve(screenSize: CGSize(width: 184, height: 224))
        let large46 = WatchLinkedSetupConfirmationLayout.resolve(screenSize: CGSize(width: 208, height: 248))
        let ultra49 = WatchLinkedSetupConfirmationLayout.resolve(screenSize: CGSize(width: 205, height: 251))

        XCTAssertEqual(compact40.tier, .compact)
        XCTAssertEqual(medium44.tier, .medium)
        XCTAssertEqual(large46.tier, .large)
        XCTAssertEqual(ultra49.tier, .large)

        XCTAssertLessThan(compact40.iconSize, medium44.iconSize)
        XCTAssertLessThan(medium44.iconSize, ultra49.iconSize)
        XCTAssertLessThan(compact40.summaryFontSize, medium44.summaryFontSize)
        XCTAssertLessThan(medium44.summaryFontSize, ultra49.summaryFontSize)
        XCTAssertLessThan(compact40.nameFontSize, ultra49.nameFontSize)
        XCTAssertLessThan(compact40.sectionSpacing, ultra49.sectionSpacing)
        XCTAssertLessThan(compact40.actionDiameter, ultra49.actionDiameter)
    }

    // MARK: - 休息状态与 OfficialBreakState 双向映射

    func testWatchRestStateMapsToAndFromOfficialBreakState() {
        let started = Date(timeIntervalSince1970: 1_735_000_000)
        let midGame = WatchRestState(
            kind: .midGame,
            title: "局中休息",
            durationSeconds: 60,
            startedAt: started,
            triggerID: "badminton-mid-1-11"
        )
        let mappedMid = midGame.officialBreakState(for: .badminton)
        XCTAssertEqual(mappedMid?.sport, .badminton)
        XCTAssertEqual(mappedMid?.kind, .midGame)
        XCTAssertEqual(mappedMid?.durationSeconds, 60)
        XCTAssertEqual(mappedMid?.startedWallClockMilliseconds, 1_735_000_000_000)
        XCTAssertTrue(mappedMid?.isRunning == true)

        let betweenSets = WatchRestState(
            kind: .betweenSets,
            title: "局间休息",
            durationSeconds: 120,
            startedAt: started,
            triggerID: "set-1"
        )
        let mappedBadmintonSet = betweenSets.officialBreakState(for: .badmintonDoubles)
        XCTAssertEqual(mappedBadmintonSet?.sport, .badminton)
        XCTAssertEqual(mappedBadmintonSet?.kind, .gameBreak)
        XCTAssertEqual(mappedBadmintonSet?.durationSeconds, 120)

        let mappedTennisSet = betweenSets.officialBreakState(for: .tennisDoubles)
        XCTAssertEqual(mappedTennisSet?.sport, .tennis)
        XCTAssertEqual(mappedTennisSet?.kind, .setBreak)
        XCTAssertEqual(mappedTennisSet?.durationSeconds, 120)

        let restoredMid = WatchRestState.fromOfficialBreak(mappedMid, now: started.addingTimeInterval(10))
        XCTAssertEqual(restoredMid?.kind, .midGame)
        XCTAssertEqual(restoredMid?.durationSeconds, 60)
        XCTAssertEqual(restoredMid?.remainingSeconds(at: started.addingTimeInterval(10)), 50)

        let medical = OfficialBreakState(
            sport: .badminton,
            kind: .medical,
            durationSeconds: 0,
            nowMilliseconds: 1_735_000_000_000,
            countUp: true
        )
        let restoredMedical = WatchRestState.fromOfficialBreak(medical, now: started.addingTimeInterval(90))
        XCTAssertEqual(restoredMedical?.countUp, true)
        XCTAssertEqual(restoredMedical?.elapsedSeconds(at: started.addingTimeInterval(90)), 90)

        var stopped = mappedMid
        stopped?.isRunning = false
        XCTAssertNil(WatchRestState.fromOfficialBreak(stopped, now: started))
        XCTAssertNil(WatchRestState.fromOfficialBreak(nil, now: started))
    }
}
