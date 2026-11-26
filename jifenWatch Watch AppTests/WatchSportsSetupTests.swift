import XCTest
import UIKit
import LinkCore
import RecordCore
import ScoreCore
import SessionCore
@testable import jifenWatch_Watch_App

final class WatchSportsSetupTests: XCTestCase {
    private var defaults: UserDefaults!
    private var preferences: WatchPreferences!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "WatchSportsSetupTests")
        defaults.removePersistentDomain(forName: "WatchSportsSetupTests")
        preferences = WatchPreferences(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "WatchSportsSetupTests")
        defaults = nil
        preferences = nil
        super.tearDown()
    }

    /// WatchResumeSessionStore 的文件存储测试目录（每用例独立临时目录）。
    private func makeResumeStoreDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchSportsSetupTests.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testPickleballUsesTableTennisIcon() {
        XCTAssertEqual(WatchGameType.pickleball.icon, WatchGameType.pingpong.icon)
    }

    func testRegulationBasketballCasesAreRemovedFromWatchCatalog() {
        XCTAssertFalse(WatchHomeItem.allCases.map(\.rawValue).contains("basketball"))
        XCTAssertFalse(WatchHomeItem.allCases.map(\.rawValue).contains("three_basketball"))
        XCTAssertFalse(WatchSetupSport.allCases.map(\.rawValue).contains("basketball"))
        XCTAssertFalse(WatchSetupSport.allCases.map(\.rawValue).contains("three_basketball"))
        XCTAssertFalse(WatchGameType.allCases.map(\.rawValue).contains("basketball"))
        XCTAssertFalse(WatchGameType.allCases.map(\.rawValue).contains("three_basketball"))
    }

    func testGenericTimerRemainsOutsideWatchLocalCatalog() {
        XCTAssertFalse(WatchHomeItem.allCases.contains { $0.rawValue.localizedCaseInsensitiveContains("timer") })
        XCTAssertFalse(WatchSetupSport.allCases.contains { $0.rawValue.localizedCaseInsensitiveContains("timer") })
    }

    func testPickleballSinglesAndDoublesAlternateOpeningServerBetweenSets() throws {
        for sport in [WatchSetupSport.pickleball, .pickleballDoubles] {
            let draft = WatchSportsSetupDraft(sport: sport, preferences: preferences)
            let config = WatchScoreboardLaunchConfig(draft: draft)
            let state = try XCTUnwrap(WatchSetupPayloadMapper.rallyState(for: config))
            XCTAssertEqual(state.rules.nextSetServerModel, .alternateFromOpening)
        }
    }

    func testWatchRestPolicyMatchesCrossPlatformDurations() {
        XCTAssertEqual(WatchRestPolicy.betweenSetDuration(for: .pingpong), 60)
        XCTAssertEqual(WatchRestPolicy.betweenSetDuration(for: .pingpongDoubles), 60)
        XCTAssertEqual(WatchRestPolicy.betweenSetDuration(for: .badminton), 120)
        XCTAssertEqual(WatchRestPolicy.betweenSetDuration(for: .badmintonDoubles), 120)
        XCTAssertEqual(WatchRestPolicy.betweenSetDuration(for: .pickleball), 120)
        XCTAssertEqual(WatchRestPolicy.betweenSetDuration(for: .tennisDoubles), 120)
        XCTAssertNil(WatchRestPolicy.betweenSetDuration(for: .eightBall))
    }

    func testFinishedUndoCountdownIsThreeSecondsAndProgressTracksRemainingTime() {
        XCTAssertEqual(WatchTiming.finishedUndoCountdown, 3)
        let start = Date(timeIntervalSince1970: 100)
        let deadline = start.addingTimeInterval(3)
        XCTAssertEqual(
            WatchUndoCountdownStroke.remainingFraction(deadline: deadline, now: start, duration: 3),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WatchUndoCountdownStroke.remainingFraction(
                deadline: deadline,
                now: start.addingTimeInterval(1.5),
                duration: 3
            ),
            0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WatchUndoCountdownStroke.remainingFraction(deadline: deadline, now: deadline, duration: 3),
            0,
            accuracy: 0.001
        )
    }

    func testWatchLayoutUsesTwoPagePaddingTiers() {
        XCTAssertEqual(WatchLayout.serverIndicatorSize, 10)
        XCTAssertEqual(WatchLayout.serverIndicatorVerticalOffset(isHorizontal: true), 8)
        XCTAssertEqual(WatchLayout.serverIndicatorVerticalOffset(isHorizontal: false), 0)
        XCTAssertEqual(WatchLayout.overlayCloseButtonSize, 40)
        XCTAssertEqual(WatchLayout.dialogCloseIconSize, 20)
        XCTAssertEqual(WatchLayout.overlayActionButtonWidth(for: 187), 134)
        XCTAssertEqual(WatchLayout.overlayActionButtonWidth(for: 198), 144)
        for width: CGFloat in [162, 176, 184, 187, 190] {
            XCTAssertTrue(WatchLayout.isNarrowScreen(width: width))
            XCTAssertEqual(WatchLayout.pageHorizontalPadding(for: width), 6)
            XCTAssertEqual(WatchLayout.pillRowHorizontalPadding(for: width), 12)
            XCTAssertEqual(WatchLayout.recordRowHorizontalPadding(for: width), 12)
            XCTAssertEqual(WatchLayout.cardContentPadding(for: width), 12)
            XCTAssertEqual(WatchLayout.archeryScorePanelHorizontalPadding(for: width), 2)
        }
        for width: CGFloat in [198, 205, 208, 211] {
            XCTAssertFalse(WatchLayout.isNarrowScreen(width: width))
            XCTAssertEqual(WatchLayout.pageHorizontalPadding(for: width), 12)
            XCTAssertEqual(WatchLayout.pillRowHorizontalPadding(for: width), 16)
            XCTAssertEqual(WatchLayout.recordRowHorizontalPadding(for: width), 16)
            XCTAssertEqual(WatchLayout.cardContentPadding(for: width), 14)
            XCTAssertEqual(WatchLayout.archeryScorePanelHorizontalPadding(for: width), 4)
        }
        XCTAssertEqual(WatchLayout.archeryScoreButtonSize(for: 162), 38)
        XCTAssertEqual(WatchLayout.archeryScoreButtonSize(for: 176), 41)
        XCTAssertEqual(WatchLayout.archeryScoreButtonSize(for: 184), 42)
        XCTAssertEqual(WatchLayout.archeryScoreButtonSize(for: 187), 42)
        XCTAssertEqual(WatchLayout.archeryScoreButtonSize(for: 198), 45)
        XCTAssertEqual(WatchLayout.archeryScoreButtonSize(for: 205), 46)
        XCTAssertEqual(WatchLayout.snookerBallButtonSize(for: 162), 32)
        XCTAssertEqual(WatchLayout.snookerBallButtonSize(for: 176), 36)
        XCTAssertEqual(WatchLayout.snookerBallButtonSize(for: 187), 38)
        XCTAssertEqual(WatchLayout.snookerBallButtonSize(for: 198), 41)
        XCTAssertEqual(WatchLayout.snookerBallButtonSize(for: 205), 42)
    }

    func testBadmintonMidGameRestRoundsTargetUp() {
        XCTAssertEqual(WatchRestPolicy.badmintonMidGamePoint(pointsToWinSet: 21), 11)
        XCTAssertEqual(WatchRestPolicy.badmintonMidGamePoint(pointsToWinSet: 15), 8)
        XCTAssertEqual(WatchRestPolicy.badmintonMidGamePoint(pointsToWinSet: 1), 1)
    }

    func testRallyCompletedSetPresentationKeepsFinalPointForEveryBadmintonFormat() {
        for target in [11, 15, 21] {
            var rules = RallyRuleSet.badminton(maxSets: 3)
            rules.pointsToWinSet = target
            rules.pointCap = RallyRuleSet.badmintonPointCap(for: target)
            var state = RallyMatchEngine.initial(
                leftName: "A",
                rightName: "B",
                rules: rules
            )
            state.leftPoints = target - 1
            state.rightPoints = target - 2

            let result = RallyMatchReducer().reduce(
                state: state,
                intent: .pointWon(.left),
                at: 0
            )
            let presentation = WatchRallyCompletedSetPresentation.resolve(
                events: result.events,
                currentSidesSwapped: result.state.sidesSwapped
            )

            XCTAssertEqual(presentation?.leftPoints, target)
            XCTAssertEqual(presentation?.rightPoints, target - 2)
            XCTAssertEqual(presentation?.leftSets, 1)
            XCTAssertEqual(result.state.leftPoints, 0)
            XCTAssertEqual(result.state.rightPoints, 0)
        }
    }

    func testRallyCompletedMatchPresentationKeepsFinalPointBeforeFinishedOverlay() {
        var rules = RallyRuleSet.badminton(maxSets: 3)
        rules.pointsToWinSet = 15
        rules.pointCap = RallyRuleSet.badmintonPointCap(for: 15)
        var state = RallyMatchEngine.initial(
            leftName: "A",
            rightName: "B",
            rules: rules
        )
        state.leftSets = 1
        state.leftPoints = 14
        state.rightPoints = 13

        let result = RallyMatchReducer().reduce(
            state: state,
            intent: .pointWon(.left),
            at: 0
        )
        let presentation = WatchRallyCompletedSetPresentation.resolve(
            events: result.events,
            currentSidesSwapped: result.state.sidesSwapped
        )

        XCTAssertTrue(result.state.finished)
        XCTAssertEqual(presentation?.leftPoints, 15)
        XCTAssertEqual(presentation?.rightPoints, 13)
        XCTAssertEqual(presentation?.leftSets, 2)
    }

    func testTennisCompletedSetPresentationKeepsFinalGameScore() {
        let events: [TennisMatchEvent] = [
            .pointScored(side: .left, left: 4, right: 0),
            .gameCompleted(winner: .left, leftGames: 6, rightGames: 2, tieBreak: false),
            .setCompleted(
                winner: .left,
                setNumber: 1,
                leftGames: 6,
                rightGames: 2,
                leftSets: 1,
                rightSets: 0
            ),
            .sidesExchanged
        ]

        let presentation = WatchTennisCompletedSetPresentation.resolve(
            events: events,
            currentSidesSwapped: true
        )

        XCTAssertEqual(presentation?.leftGames, 6)
        XCTAssertEqual(presentation?.rightGames, 2)
        XCTAssertEqual(presentation?.leftSets, 1)
        XCTAssertEqual(presentation?.sidesSwapped, false)
    }

    func testRestCountdownClampsAtZero() {
        let start = Date(timeIntervalSince1970: 1_000)
        let state = WatchRestState(
            kind: .betweenSets,
            title: "Rest",
            durationSeconds: 60,
            startedAt: start,
            triggerID: "set-1"
        )
        XCTAssertEqual(state.remainingSeconds(at: start), 60)
        XCTAssertEqual(state.remainingSeconds(at: start.addingTimeInterval(14.9)), 46)
        XCTAssertEqual(state.remainingSeconds(at: start.addingTimeInterval(60)), 0)
        XCTAssertEqual(state.remainingSeconds(at: start.addingTimeInterval(120)), 0)
    }

    func testRestTriggerRegistryDoesNotRepeatUntilReleased() {
        var registry = WatchRestTriggerRegistry()

        XCTAssertTrue(registry.consume("set-1-point-11"))
        XCTAssertFalse(registry.consume("set-1-point-11"))

        registry.release("set-1-point-11")
        XCTAssertTrue(registry.consume("set-1-point-11"))

        registry.reset()
        XCTAssertTrue(registry.consume("set-1-point-11"))
    }

    func testBadmintonDoublesDisplayFollowsConsecutiveServeRotation() {
        let names = ["A", "C", "B", "D"]
        var rotation = createBadmintonDoublesRotation(servingTeam0: true)
        var doubles = RallyDoublesState(
            playerNames: names,
            rotation: .badminton(rotation)
        )

        let initial = WatchDoublesDisplayState.resolve(
            doubles: doubles,
            logicalSide: .left,
            screenSide: .left
        )
        XCTAssertEqual(initial.topPlayerIndex, 0)
        XCTAssertEqual(initial.bottomPlayerIndex, 2)
        XCTAssertEqual(initial.serverIsTop, false)

        rotation = advanceBadmintonDoublesRotation(
            current: rotation,
            scoringTeam0: true,
            nextTeam0Score: 1,
            nextTeam1Score: 0
        )
        doubles.rotation = .badminton(rotation)
        let afterFirstPoint = WatchDoublesDisplayState.resolve(
            doubles: doubles,
            logicalSide: .left,
            screenSide: .left
        )
        XCTAssertEqual(afterFirstPoint.topPlayerIndex, 2)
        XCTAssertEqual(afterFirstPoint.bottomPlayerIndex, 0)
        XCTAssertEqual(afterFirstPoint.serverIsTop, true)

        rotation = advanceBadmintonDoublesRotation(
            current: rotation,
            scoringTeam0: true,
            nextTeam0Score: 2,
            nextTeam1Score: 0
        )
        doubles.rotation = .badminton(rotation)
        let afterSecondPoint = WatchDoublesDisplayState.resolve(
            doubles: doubles,
            logicalSide: .left,
            screenSide: .left
        )
        XCTAssertEqual(afterSecondPoint.topPlayerIndex, 0)
        XCTAssertEqual(afterSecondPoint.bottomPlayerIndex, 2)
        XCTAssertEqual(afterSecondPoint.serverIsTop, false)
    }

    func testPickleballDoublesDisplaySwapsNamesAndMirrorsRightPanel() {
        var rotation = createPickleballDoublesRotation(servingTeam0: true)
        togglePickleballPartnerSwap(&rotation, servingTeam0: true)
        refreshPickleballDoublesSlots(&rotation, servingTeam0: true)
        let doubles = RallyDoublesState(
            playerNames: ["A", "C", "B", "D"],
            rotation: .pickleball(rotation)
        )

        let left = WatchDoublesDisplayState.resolve(
            doubles: doubles,
            logicalSide: .left,
            screenSide: .left
        )
        XCTAssertEqual(left.topPlayerIndex, 2)
        XCTAssertEqual(left.bottomPlayerIndex, 0)
        XCTAssertEqual(left.serverIsTop, false)

        let right = WatchDoublesDisplayState.resolve(
            doubles: doubles,
            logicalSide: .right,
            screenSide: .right
        )
        XCTAssertEqual(right.topPlayerIndex, 3)
        XCTAssertEqual(right.bottomPlayerIndex, 1)
        XCTAssertNil(right.serverIsTop)
    }

    func testPickleballDoublesServingArrowFollowsRightTeamName() {
        let doubles = RallyDoublesState.pickleball(
            playerNames: ["A", "C", "B", "D"],
            servingTeam0: false
        )

        let right = WatchDoublesDisplayState.resolve(
            doubles: doubles,
            logicalSide: .right,
            screenSide: .right
        )

        XCTAssertEqual(right.bottomPlayerIndex, doubles.serverSlotIndex)
        XCTAssertEqual(right.serverIsTop, false)
    }

    func testTennisDoublesServerSlotsForGamesAndTieBreak() {
        XCTAssertEqual(
            (0..<5).map {
                WatchTennisDoublesServing.serverSlot(
                    firstServer: .left,
                    completedGames: $0,
                    isTieBreak: false,
                    tieBreakPointsPlayed: 0
                )
            },
            [0, 1, 2, 3, 0]
        )
        XCTAssertEqual(
            (0..<8).map {
                WatchTennisDoublesServing.serverSlot(
                    firstServer: .right,
                    completedGames: 12,
                    isTieBreak: true,
                    tieBreakPointsPlayed: $0
                )
            },
            [1, 2, 2, 3, 3, 0, 0, 1]
        )
    }

    func testNineBallFoulAwardsOpponentForTwoPlayersAndDeductsForGroups() {
        // v1 累计计分语义：.chaseEvent 直接加减。v1 开局需显式 ruleVersion: 1，
        // 默认开局已是 ruleVersion 2（走 transfer 意图，见下方 V2 用例）。
        let reducer = NineBallChaseReducer()
        let two = reducer.reduce(
            state: .initial(config: .init(foul: 2), playerCount: 2, ruleVersion: 1),
            intent: .chaseEvent(player: 0, kind: .foul),
            at: 1
        ).state
        XCTAssertEqual(two.playerPoints[0], 0)
        XCTAssertEqual(two.playerPoints[1], 2)

        let four = reducer.reduce(
            state: .initial(config: .init(foul: 2), playerCount: 4, ruleVersion: 1),
            intent: .chaseEvent(player: 2, kind: .foul),
            at: 1
        ).state
        XCTAssertEqual(four.playerPoints[2], -2)
    }

    /// 手表默认开局（ruleVersion 2）：旧意图必须被拒，transfer 意图正确计分，
    /// 投影器产出与 chaseApplied 同口径的动作（见 P0 修复回归）。
    func testNineBallV2DefaultStateRejectsLegacyIntentAndScoresViaTransfer() {
        let reducer = NineBallChaseReducer()
        let legacy = reducer.reduce(
            state: .initial(config: .init(foul: 2), playerCount: 2),
            intent: .chaseEvent(player: 0, kind: .foul),
            at: 1
        )
        XCTAssertFalse(legacy.accepted)

        let result = reducer.reduce(
            state: .initial(config: .init(foul: 2), playerCount: 2),
            intent: .chaseTransfer(player: 0, kind: .foul, payer: nil, continuePlayer: nil),
            at: 1
        )
        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.state.playerPoints[0], -2)
        XCTAssertEqual(result.state.playerPoints[1], 2)

        let actions = ScoreActionProjector.nineBall(
            events: result.events,
            state: result.state,
            timestamp: Date(timeIntervalSince1970: 1)
        )
        XCTAssertEqual(actions.first?.type, .foul)
        XCTAssertEqual(actions.first?.operationCode, "nine_ball_foul")
        XCTAssertEqual(actions.first?.scoreChange, -2)
        XCTAssertEqual(actions.first?.participants.count, 2)
    }

    /// 手机联动九球比赛规则（ruleVersion 3 + tournament）下，reducer 拒绝
    /// .chaseTransfer，必须走 .tournamentEvent；且犯规投影应保留非零受分 delta。
    func testNineBallTournamentFoulAndWinProjectNonZeroDelta() {
        let reducer = NineBallChaseReducer()
        let config = NineBallChaseConfig(
            bigGold: 4,
            smallGold: 2,
            normalWin: 1,
            foul: 1,
            ruleFamily: .tournament,
            thirdFoul: 3,
            totalRacks: 9
        )
        let state = NineBallChaseState.initial(
            config: config,
            playerCount: 2,
            playerNames: ["甲", "乙"],
            ruleVersion: 3
        )
        XCTAssertTrue(state.isTournament)
        XCTAssertFalse(
            reducer.reduce(
                state: state,
                intent: .chaseTransfer(player: 0, kind: .foul, payer: nil, continuePlayer: nil),
                at: 1
            ).accepted
        )
        let foulResult = reducer.reduce(
            state: state,
            intent: .tournamentEvent(player: 0, kind: .foul),
            at: 2
        )
        XCTAssertTrue(foulResult.accepted)
        XCTAssertEqual(foulResult.state.playerPoints[0], 0)
        XCTAssertEqual(foulResult.state.playerPoints[1], 1)

        let actions = ScoreActionProjector.nineBall(
            events: foulResult.events,
            state: foulResult.state,
            timestamp: Date(timeIntervalSince1970: 2)
        )
        XCTAssertEqual(actions.first?.type, .foul)
        XCTAssertEqual(actions.first?.scoreChange, 1)
    }

    func testNineBallWatchSelectionPolicyMatchesPhoneRulesForTwoThreeAndFourPlayers() {
        let twoPlayer = NineBallChaseState.initial(
            config: NineBallChaseConfig(smallGoldAllPay: false),
            playerCount: 2,
            ruleVersion: 3,
            breakerPlayer: 0
        )
        XCTAssertFalse(WatchNineBallSelectionPolicy.isEventUnavailable(.bigGold, for: 0, in: twoPlayer))
        XCTAssertTrue(WatchNineBallSelectionPolicy.isEventUnavailable(.bigGold, for: 1, in: twoPlayer))
        XCTAssertTrue(WatchNineBallSelectionPolicy.isEventUnavailable(.smallGold, for: 0, in: twoPlayer))
        XCTAssertFalse(WatchNineBallSelectionPolicy.isEventUnavailable(.smallGold, for: 1, in: twoPlayer))
        for kind in twoPlayer.scoringKinds {
            XCTAssertNil(WatchNineBallSelectionPolicy.secondarySelectionMode(for: kind, player: 1, in: twoPlayer))
        }

        let threePlayerSingleSmall = NineBallChaseState.initial(
            config: NineBallChaseConfig(bigGold: 10, smallGold: 7, goldenNine: 4, normalWin: 4, foul: 1, smallGoldAllPay: false),
            playerCount: 3,
            ruleVersion: 3,
            breakerPlayer: 0
        )
        XCTAssertEqual(
            WatchNineBallSelectionPolicy.secondarySelectionMode(for: .normalWin, player: 1, in: threePlayerSingleSmall),
            .payer
        )
        XCTAssertEqual(
            WatchNineBallSelectionPolicy.secondarySelectionMode(for: .smallGold, player: 1, in: threePlayerSingleSmall),
            .payer
        )
        XCTAssertEqual(
            WatchNineBallSelectionPolicy.secondarySelectionMode(for: .smallGold, player: 0, in: threePlayerSingleSmall),
            .payer
        )
        XCTAssertEqual(
            WatchNineBallSelectionPolicy.secondarySelectionMode(for: .handoff, player: 0, in: threePlayerSingleSmall),
            .continuePlayer
        )
        XCTAssertNil(WatchNineBallSelectionPolicy.secondarySelectionMode(for: .bigGold, player: 0, in: threePlayerSingleSmall))
        XCTAssertNil(WatchNineBallSelectionPolicy.secondarySelectionMode(for: .goldenNine, player: 1, in: threePlayerSingleSmall))
        XCTAssertNil(WatchNineBallSelectionPolicy.secondarySelectionMode(for: .foul, player: 1, in: threePlayerSingleSmall))

        XCTAssertEqual(WatchNineBallSelectionPolicy.candidatePlayers(excluding: 1, in: threePlayerSingleSmall), [0, 2])
        XCTAssertEqual(
            WatchNineBallSelectionPolicy.recommendedPlayer(for: .payer, kind: .normalWin, actor: 0, in: threePlayerSingleSmall),
            2
        )
        XCTAssertEqual(
            WatchNineBallSelectionPolicy.recommendedPlayer(for: .payer, kind: .smallGold, actor: 2, in: threePlayerSingleSmall),
            0
        )
        XCTAssertEqual(
            WatchNineBallSelectionPolicy.recommendedPlayer(for: .payer, kind: .smallGold, actor: 0, in: threePlayerSingleSmall),
            2
        )
        XCTAssertEqual(
            WatchNineBallSelectionPolicy.recommendedPlayer(for: .continuePlayer, kind: .handoff, actor: 2, in: threePlayerSingleSmall),
            0
        )

        let fourPlayerAllPaySmall = NineBallChaseState.initial(
            config: NineBallChaseConfig(smallGoldAllPay: true),
            playerCount: 4,
            ruleVersion: 3,
            breakerPlayer: 1
        )
        XCTAssertNil(WatchNineBallSelectionPolicy.secondarySelectionMode(for: .smallGold, player: 2, in: fourPlayerAllPaySmall))
        XCTAssertEqual(
            WatchNineBallSelectionPolicy.secondarySelectionMode(for: .normalWin, player: 2, in: fourPlayerAllPaySmall),
            .payer
        )
        XCTAssertEqual(WatchNineBallSelectionPolicy.candidatePlayers(excluding: 2, in: fourPlayerAllPaySmall), [0, 1, 3])

        // End-to-end reducer check: explicit payer, explicit handoff continuePlayer, and setBreaker.
        let reducer = NineBallChaseReducer()
        let paid = reducer.reduce(
            state: threePlayerSingleSmall,
            intent: .chaseTransfer(player: 1, kind: .normalWin, payer: 2, continuePlayer: nil),
            at: 10
        )
        XCTAssertTrue(paid.accepted)
        XCTAssertEqual(paid.state.playerPoints.prefix(3), [0, 4, -4])
        XCTAssertEqual(paid.state.breakerPlayer, 2)

        let handoff = reducer.reduce(
            state: paid.state,
            intent: .chaseTransfer(player: 1, kind: .handoff, payer: nil, continuePlayer: 0),
            at: 20
        )
        XCTAssertTrue(handoff.accepted)
        XCTAssertEqual(handoff.state.playerPoints.prefix(3), [0, 4, -4])

        let changedBreaker = reducer.reduce(
            state: handoff.state,
            intent: .setBreaker(player: 0),
            at: 30
        )
        XCTAssertTrue(changedBreaker.accepted)
        XCTAssertEqual(changedBreaker.state.breakerPlayer, 0)
    }

    func testSnookerPanelIntentsCoverPotFoulHandoverAndFrameSettlement() {
        let reducer = SnookerReducer()
        var state = SnookerState.initial(striker: .left, maxFrames: 3)
        state = reducer.reduce(state: state, intent: .potBall(points: 1), at: 1).state
        XCTAssertEqual(state.leftScore, 1)
        XCTAssertEqual(state.redBallsRemaining, 14)
        state = reducer.reduce(
            state: state,
            intent: .foul(pointsToOpponent: 4, switchTurn: true),
            at: 2
        ).state
        XCTAssertEqual(state.rightScore, 4)
        XCTAssertEqual(state.striker, .right)
        state = reducer.reduce(state: state, intent: .handover, at: 3).state
        XCTAssertEqual(state.striker, .left)
        state = reducer.reduce(state: state, intent: .settleFrame(winner: .left), at: 4).state
        XCTAssertEqual(state.leftFrames, 1)
        XCTAssertEqual(state.currentFrame, 2)
    }

    func testSnookerFoulCanKeepFoulingSideAtTableAndRecordsChoice() {
        let reducer = SnookerReducer()
        let before = SnookerState.initial(striker: .left, maxFrames: 3)
        let intent = SnookerIntent.foulFromSide(
            side: .left,
            pointsToOpponent: 5,
            switchTurn: false
        )
        let result = reducer.reduce(state: before, intent: intent, at: 1)

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.state.rightScore, 5)
        XCTAssertEqual(result.state.striker, .left)
        XCTAssertFalse(result.events.contains { event in
            if case .turnChanged = event { return true }
            return false
        })

        let actions = ScoreActionProjector.snooker(
            intent: intent,
            events: result.events,
            state: result.state,
            timestamp: Date(timeIntervalSince1970: 1)
        )
        XCTAssertEqual(actions.first?.operationCode, "snooker_foul_continue")
    }

    func testSnookerBallAvailabilityAlternatesAndThenFollowsClearanceOrder() {
        let reducer = SnookerReducer()
        var state = SnookerState.initial(striker: .left, maxFrames: 3)

        XCTAssertEqual(
            SnookerBall.allCases.filter { WatchSnookerBallAvailability.isAvailable($0, in: state) },
            [.red]
        )

        state = reducer.reduce(state: state, intent: .potBall(points: 1), at: 1).state
        XCTAssertEqual(
            SnookerBall.allCases.filter { WatchSnookerBallAvailability.isAvailable($0, in: state) },
            [.yellow, .green, .brown, .blue, .pink, .black]
        )

        state = reducer.reduce(state: state, intent: .potBall(points: 7), at: 2).state
        XCTAssertEqual(
            SnookerBall.allCases.filter { WatchSnookerBallAvailability.isAvailable($0, in: state) },
            [.red]
        )

        state.redBallsRemaining = 0
        state.nextBallStage = .color
        state = reducer.reduce(state: state, intent: .potBall(points: 7), at: 3).state
        XCTAssertEqual(
            SnookerBall.allCases.filter { WatchSnookerBallAvailability.isAvailable($0, in: state) },
            [.yellow]
        )

        state = reducer.reduce(state: state, intent: .potBall(points: 2), at: 4).state
        XCTAssertEqual(
            SnookerBall.allCases.filter { WatchSnookerBallAvailability.isAvailable($0, in: state) },
            [.green]
        )
    }

    func testWatchHomePinningKeepsPinnedOrderAndDefaultOrderForTheRest() {
        let ordered = WatchHomePinning.orderedItems(
            pinnedItems: [.tennis, .badmintonDoubles]
        )

        XCTAssertEqual(Array(ordered.prefix(2)), [.tennis, .badmintonDoubles])
        XCTAssertEqual(
            Array(ordered.dropFirst(2)),
            WatchHomeItem.allCases.filter { ![.tennis, .badmintonDoubles].contains($0) }
        )
    }

    func testWatchHomePinningRejectsThirdItemAndRestoresUnpinnedDefaultPosition() {
        let pinned: [WatchHomeItem] = [.tennis, .badminton]

        XCTAssertNil(WatchHomePinning.adding(.pingpong, to: pinned))
        XCTAssertEqual(
            WatchHomePinning.removing(.tennis, from: pinned),
            [.badminton]
        )
        XCTAssertEqual(
            WatchHomePinning.orderedItems(pinnedItems: [.badminton]),
            [.badminton] + WatchHomeItem.allCases.filter { $0 != .badminton }
        )
    }

    func testWatchHomePinningFiltersUnknownAndDuplicateStoredIDs() {
        XCTAssertEqual(
            WatchHomePinning.normalizedItems(
                from: ["unknown", "tennis", "tennis", "pingpong", "badminton"]
            ),
            [.tennis, .pingpong]
        )
    }

    @MainActor
    func testResumeSessionPersistsWithinTTLAndExpiresAfter24Hours() {
        var currentDate = Date(timeIntervalSince1970: 10_000)
        let directory = makeResumeStoreDirectory()
        let store = WatchResumeSessionStore(directoryURL: directory, now: { currentDate })
        let sessionID = UUID()
        let link = WatchLinkResumeContext(
            handle: LinkedMatchHandle(sessionId: sessionID),
            setup: LinkedScoreboardSetup(gameType: .basketballTraining),
            revision: 3,
            latestAuthoritativeSnapshot: .basketballTraining(
                .init(mode: .free, startTime: currentDate, shots: [])
            ),
            detailedActions: [],
            completedMatchIds: [],
            pendingTerminalMessageIds: []
        )
        let shot = ShotTrainingShot(points: 2, made: true, timestamp: currentDate)
        store.save(WatchResumeSession(
            startedAt: currentDate.addingTimeInterval(-30),
            scoreLine: "2 / 1",
            emoji: "🏀",
            payload: trainingResumeFixture(mode: .free, startedAt: currentDate, shots: [shot]),
            linkHandle: link.handle
        ))
        // 落盘是 750ms 防抖的，跨实例持久化断言前先冲掉待写数据。
        store.flushPendingWrite()

        // Within TTL: session persists
        let restored = WatchResumeSessionStore(directoryURL: directory, now: { currentDate })
        XCTAssertEqual(restored.session?.scoreLine, "2 / 1")
        XCTAssertEqual(WatchScoreboardRoute(resumeSession: restored.session!)?.id, "basketballTraining-free")

        // Exactly 24 hours: still valid (boundary, > not >=)
        currentDate = currentDate.addingTimeInterval(24 * 60 * 60)
        restored.reload()
        XCTAssertNotNil(restored.session)

        // Beyond 24 hours: expired and silently cleared (no link context retained)
        currentDate = currentDate.addingTimeInterval(1)
        restored.reload()
        XCTAssertNil(restored.session)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("current.json").path
            )
        )
    }

    /// 750ms 防抖窗口内立即触发 reload()（例如退出计分板后立刻点击续玩条），
    /// 必须先冲刷待写数据，不能把内存里的最新续玩状态抹成 nil 或回滚旧分。
    @MainActor
    func testResumeSessionReloadFlushesPendingDebouncedWrite() {
        let currentDate = Date(timeIntervalSince1970: 20_000)
        let directory = makeResumeStoreDirectory()
        let store = WatchResumeSessionStore(directoryURL: directory, now: { currentDate })
        let shot = ShotTrainingShot(points: 3, made: true, timestamp: currentDate)
        store.save(WatchResumeSession(
            startedAt: currentDate.addingTimeInterval(-10),
            scoreLine: "3 / 1",
            emoji: "🏀",
            payload: trainingResumeFixture(mode: .free, startedAt: currentDate, shots: [shot])
        ))
        // 不手动 flushPendingWrite()，直接模拟 WatchRootView.resume(_:) 立刻 reload()
        store.reload()
        XCTAssertEqual(store.session?.scoreLine, "3 / 1")
        let fresh = WatchResumeSessionStore(directoryURL: directory, now: { currentDate })
        XCTAssertEqual(fresh.session?.scoreLine, "3 / 1")
    }

    @MainActor
    func testResumeSessionRefreshUsesLatestLinkedActionTimeline() throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let handle = LinkedMatchHandle(sessionId: UUID())
        let store = WatchResumeSessionStore(directoryURL: makeResumeStoreDirectory(), now: { now })
        store.save(WatchResumeSession(
            startedAt: now,
            scoreLine: "1 : 0",
            emoji: "🏸",
            payload: trainingResumeFixture(mode: .free, startedAt: now),
            actionLog: WatchScoreActionLog(startedAt: now),
            linkHandle: handle
        ))

        let remoteAction = DetailedScoreAction(
            type: .scoreChanged,
            epochMilliseconds: 20_500,
            team: .team1,
            scores: [1, 0],
            scoreChange: 1,
            operationCode: "point"
        )
        // 手机撤销了本地旧动作：checkpoint 显式携带删除 ID（M1 removedActionIDs）。
        let localRemovedID = try XCTUnwrap(store.session?.actionLog.detailedActions.last?.id)
        var history = LinkSnapshotHistory()
        history.noteRemoteRemovals([localRemovedID])
        var context = WatchLinkResumeContext(
            handle: handle,
            setup: LinkedScoreboardSetup(gameType: .badminton),
            revision: 2,
            latestAuthoritativeSnapshot: nil,
            detailedActions: [],
            completedMatchIds: [],
            pendingTerminalMessageIds: []
        )
        context.detailedActions = [remoteAction]
        context.actionHistory = history
        store.refreshLinkContext(context)

        let refreshedActions = try XCTUnwrap(store.session?.actionLog.detailedActions)
        XCTAssertEqual(refreshedActions.map(\.id), [remoteAction.id])
        XCTAssertEqual(refreshedActions.map(\.type), [.scoreChanged])
        XCTAssertEqual(refreshedActions.map(\.scores), [[1, 0]])
        XCTAssertEqual(refreshedActions.map(\.operationCode), ["point"])
    }

    func testPinnedHomeItemsPersistAndIgnoreLegacyLastSelectedItem() {
        preferences.setString(WatchHomeItem.snooker.rawValue, forKey: "watchLastSelectedGame")
        preferences.pinnedHomeItemIDs = [
            WatchHomeItem.pingpongDoubles.rawValue,
            WatchHomeItem.archery.rawValue
        ]

        let reloaded = WatchPreferences(defaults: defaults)
        let pinned = WatchHomePinning.normalizedItems(from: reloaded.pinnedHomeItemIDs)
        XCTAssertEqual(pinned, [.pingpongDoubles, .archery])
        XCTAssertEqual(
            Array(WatchHomePinning.orderedItems(pinnedItems: pinned).prefix(2)),
            [.pingpongDoubles, .archery]
        )
    }

    func testScoreboardKeepScreenOnDefaultsOnAndPersists() {
        XCTAssertTrue(preferences.scoreboardKeepScreenOn)

        preferences.scoreboardKeepScreenOn = false

        let reloaded = WatchPreferences(defaults: defaults)
        XCTAssertFalse(reloaded.scoreboardKeepScreenOn)
    }

    func testAndroid29Defaults() {
        let badminton = WatchSportsSetupDraft(sport: .badminton, preferences: preferences)
        XCTAssertEqual(badminton.maxSets, 3)
        XCTAssertEqual(badminton.pointsPerSet, 21)

        let pingpong = WatchSportsSetupDraft(sport: .pingpong, preferences: preferences)
        XCTAssertEqual(pingpong.maxSets, 5)
        XCTAssertEqual(pingpong.pointsPerSet, 11)

        let tennis = WatchSportsSetupDraft(sport: .tennis, preferences: preferences)
        XCTAssertEqual(tennis.maxSets, 3)
        XCTAssertEqual(tennis.tennisDeuceMode, "advantage")

        let pickleball = WatchSportsSetupDraft(sport: .pickleball, preferences: preferences)
        XCTAssertEqual(pickleball.maxSets, 3)
        XCTAssertEqual(pickleball.pickleballTargetScore, 11)
        XCTAssertFalse(pickleball.pickleballUseRallyScoring)

        let eightBall = WatchSportsSetupDraft(sport: .eightBall, preferences: preferences)
        XCTAssertEqual(eightBall.eightBallTargetRacks, 5)
        XCTAssertEqual(eightBall.eightBallHandicapBeneficiary, .none)

        let snooker = WatchSportsSetupDraft(sport: .snooker, preferences: preferences)
        XCTAssertEqual(snooker.maxSets, 1)
    }

    func testInvalidStoredValuesFallBackToDefaults() {
        defaults.set(2, forKey: "watchBadmintonSetupMaxSets")
        defaults.set(99, forKey: "watchPingpongSetupPointsPerSet")
        defaults.set("unexpected", forKey: "watchTennisSetupDeuceMode")
        defaults.set(13, forKey: "watchPickleballSetupTargetScore")

        XCTAssertEqual(
            WatchSportsSetupDraft(sport: .badminton, preferences: preferences).maxSets,
            3
        )
        XCTAssertEqual(
            WatchSportsSetupDraft(sport: .pingpong, preferences: preferences).pointsPerSet,
            11
        )
        XCTAssertEqual(
            WatchSportsSetupDraft(sport: .tennis, preferences: preferences).tennisDeuceMode,
            "advantage"
        )
        XCTAssertEqual(
            WatchSportsSetupDraft(sport: .pickleball, preferences: preferences).pickleballTargetScore,
            11
        )
    }

    func testRulesPersistButNamesDoNot() {
        var draft = WatchSportsSetupDraft(sport: .badminton, preferences: preferences)
        draft.maxSets = 5
        draft.pointsPerSet = 15
        draft.playerNames[0] = "Alice"
        draft.persistRules(to: preferences)

        let restored = WatchSportsSetupDraft(sport: .badminton, preferences: preferences)
        XCTAssertEqual(restored.maxSets, 5)
        XCTAssertEqual(restored.pointsPerSet, 15)
        XCTAssertTrue(restored.playerNames.allSatisfy(\.isEmpty))
    }

    func testExpandedPartialNamesAreRejected() {
        var draft = WatchSportsSetupDraft(sport: .badminton, preferences: preferences)
        draft.playerNames[0] = "Alice"
        XCTAssertFalse(draft.namesAreValid(whenExpanded: true))
        XCTAssertTrue(draft.namesAreValid(whenExpanded: false))

        draft.playerNames[1] = "Bob"
        XCTAssertTrue(draft.namesAreValid(whenExpanded: true))
    }

    func testNineBallCountIsClampedAndBlankNamesFallBack() {
        let low = WatchSportsSetupDraft(sport: .nineBall, playerCount: 1, preferences: preferences)
        let high = WatchSportsSetupDraft(sport: .nineBall, playerCount: 8, preferences: preferences)
        XCTAssertEqual(low.playerCount, 2)
        XCTAssertEqual(high.playerCount, 4)

        let config = WatchScoreboardLaunchConfig(draft: high)
        let names = WatchSetupPayloadMapper.resolvedPlayerNames(config)
        XCTAssertEqual(names.count, 4)
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
    }

    func testDoublesUIOrderMapsToCoreInterleavedSlots() {
        var draft = WatchSportsSetupDraft(sport: .badmintonDoubles, preferences: preferences)
        draft.playerNames = ["Red A", "Red B", "Blue A", "Blue B"]
        let state = WatchSetupPayloadMapper.rallyState(
            for: WatchScoreboardLaunchConfig(draft: draft)
        )
        XCTAssertEqual(
            state?.doubles?.playerNames,
            ["Red A", "Blue A", "Red B", "Blue B"]
        )
    }

    func testPingPongDoublesDefaultsToRedAServingBlueBReceiving() throws {
        var draft = WatchSportsSetupDraft(sport: .pingpongDoubles, preferences: preferences)
        draft.playerNames = ["Red A", "Red B", "Blue A", "Blue B"]
        let state = try XCTUnwrap(WatchSetupPayloadMapper.rallyState(
            for: WatchScoreboardLaunchConfig(draft: draft)
        ))

        XCTAssertEqual(state.doubles?.serverSlotIndex, 0)
        XCTAssertEqual(state.doubles?.receiverSlotIndex, 3)
        XCTAssertEqual(state.doubles?.serverName, "Red A")
        XCTAssertEqual(state.doubles?.receiverName, "Blue B")
    }

    func testSetupPayloadsPreserveEnteredNamesForEveryScoreboard() throws {
        func config(
            _ sport: WatchSetupSport,
            names: [String],
            playerCount: Int? = nil
        ) -> WatchScoreboardLaunchConfig {
            var draft = WatchSportsSetupDraft(
                sport: sport,
                playerCount: playerCount,
                preferences: preferences
            )
            for (index, name) in names.enumerated() where draft.playerNames.indices.contains(index) {
                draft.playerNames[index] = name
            }
            return WatchScoreboardLaunchConfig(draft: draft)
        }

        for sport in [WatchSetupSport.badminton, .pingpong, .pickleball] {
            let state = try XCTUnwrap(WatchSetupPayloadMapper.rallyState(
                for: config(sport, names: ["甲", "乙"])
            ))
            XCTAssertEqual(state.leftName, "甲")
            XCTAssertEqual(state.rightName, "乙")
        }

        for sport in [WatchSetupSport.badmintonDoubles, .pingpongDoubles, .pickleballDoubles] {
            let state = try XCTUnwrap(WatchSetupPayloadMapper.rallyState(
                for: config(sport, names: ["红A", "红B", "蓝A", "蓝B"])
            ))
            XCTAssertEqual(state.leftName, "红A / 红B")
            XCTAssertEqual(state.rightName, "蓝A / 蓝B")
            XCTAssertEqual(state.doubles?.playerNames, ["红A", "蓝A", "红B", "蓝B"])
        }

        let tennis = try XCTUnwrap(WatchSetupPayloadMapper.tennisState(
            for: config(.tennis, names: ["甲", "乙"])
        ))
        XCTAssertEqual(tennis.leftName, "甲")
        XCTAssertEqual(tennis.rightName, "乙")

        let tennisDoubles = try XCTUnwrap(WatchSetupPayloadMapper.tennisState(
            for: config(.tennisDoubles, names: ["红A", "红B", "蓝A", "蓝B"])
        ))
        XCTAssertEqual(tennisDoubles.leftName, "红A / 红B")
        XCTAssertEqual(tennisDoubles.rightName, "蓝A / 蓝B")
        XCTAssertEqual(tennisDoubles.doublesPlayerNames, ["红A", "蓝A", "红B", "蓝B"])

        let archery = try XCTUnwrap(WatchSetupPayloadMapper.archeryState(
            for: config(.archery, names: ["射手甲", "射手乙"])
        ))
        XCTAssertEqual(archery.leftName, "射手甲")
        XCTAssertEqual(archery.rightName, "射手乙")

        for sport in [WatchSetupSport.eightBall, .snooker] {
            let names = WatchSetupPayloadMapper.twoSideNames(
                for: config(sport, names: ["甲", "乙"])
            )
            XCTAssertEqual(names.left, "甲")
            XCTAssertEqual(names.right, "乙")
        }

        let nineBall = try XCTUnwrap(WatchSetupPayloadMapper.nineBallState(
            for: config(.nineBall, names: ["甲", "乙", "丙", "丁"], playerCount: 4)
        ))
        XCTAssertEqual(nineBall.playerNames, ["甲", "乙", "丙", "丁"])
    }

    func testEightBallHandicapResetsAndCaps() {
        var draft = WatchSportsSetupDraft(sport: .eightBall, preferences: preferences)
        draft.eightBallTargetRacks = 3
        draft.eightBallHandicapBeneficiary = .team2
        draft.eightBallHandicapRacks = 5
        draft.normalizeEightBallHandicap()
        XCTAssertEqual(draft.eightBallHandicapRacks, 2)

        draft.eightBallTargetRacks = 1
        draft.normalizeEightBallHandicap()
        XCTAssertEqual(draft.eightBallHandicapBeneficiary, .none)
        XCTAssertEqual(draft.eightBallHandicapRacks, 0)
    }

    func testEightBallHandicapMaximumTracksTargetRacks() {
        XCTAssertEqual(WatchSportsSetupDraft.maxEightBallHandicap(for: 1), 0)
        XCTAssertEqual(WatchSportsSetupDraft.maxEightBallHandicap(for: 5), 4)
        XCTAssertEqual(WatchSportsSetupDraft.maxEightBallHandicap(for: 9), 8)
    }

    func testEightBallKeepsAndroidHandicapDraftAndDefaultsChosenBeneficiaryToOne() {
        var draft = WatchSportsSetupDraft(sport: .eightBall, preferences: preferences)
        draft.eightBallTargetRacks = 5
        draft.eightBallHandicapBeneficiary = .none
        draft.eightBallHandicapRacks = 3
        draft.normalizeEightBallHandicap()
        XCTAssertEqual(draft.eightBallHandicapRacks, 3)

        draft.eightBallHandicapBeneficiary = .team1
        draft.eightBallHandicapRacks = 0
        draft.normalizeEightBallHandicap()
        XCTAssertEqual(draft.eightBallHandicapRacks, 1)
    }

    func testEightBallPresentationIncludesHandicapInDisplayedRacks() throws {
        var state = EightBallState.initial(
            targetPoints: 5,
            handicapRacks: 2,
            handicapBeneficiary: .right
        )

        XCTAssertEqual(WatchEightBallScorePresentation.displayedRacks(state: state, side: .left), 0)
        XCTAssertEqual(WatchEightBallScorePresentation.displayedRacks(state: state, side: .right), 2)
        XCTAssertNil(WatchEightBallScorePresentation.handicapText(state: state, side: .left))
        XCTAssertEqual(WatchEightBallScorePresentation.handicapText(state: state, side: .right), "+2")

        let result = EightBallReducer().reduce(
            state: state,
            intent: .addRack(.right),
            at: 1
        )
        XCTAssertTrue(result.accepted)
        state = result.state
        XCTAssertEqual(WatchEightBallScorePresentation.displayedRacks(state: state, side: .right), 3)
        XCTAssertEqual(WatchEightBallScorePresentation.handicapText(state: state, side: .right), "+2")
    }

    func testSnookerEvenFramesNormalizeUpInCore() {
        var draft = WatchSportsSetupDraft(sport: .snooker, preferences: preferences)
        draft.maxSets = 4
        let state = WatchSetupPayloadMapper.snookerState(
            for: WatchScoreboardLaunchConfig(draft: draft)
        )
        XCTAssertEqual(state?.maxFrames, 5)
    }

    func testSetupRulesReachScoreCoreState() {
        var badminton = WatchSportsSetupDraft(sport: .badminton, preferences: preferences)
        badminton.maxSets = 5
        badminton.pointsPerSet = 15
        let badmintonState = WatchSetupPayloadMapper.rallyState(
            for: WatchScoreboardLaunchConfig(draft: badminton)
        )
        XCTAssertEqual(badmintonState?.rules.maxSets, 5)
        XCTAssertEqual(badmintonState?.rules.pointsToWinSet, 15)
        XCTAssertEqual(badmintonState?.rules.pointCap, 21)

        for sport in [WatchSetupSport.badminton, .badmintonDoubles] {
            for (target, cap) in [(11, 15), (15, 21), (21, 30)] {
                var draft = WatchSportsSetupDraft(sport: sport, preferences: preferences)
                draft.pointsPerSet = target
                let state = WatchSetupPayloadMapper.rallyState(
                    for: WatchScoreboardLaunchConfig(draft: draft)
                )
                XCTAssertEqual(state?.rules.pointsToWinSet, target)
                XCTAssertEqual(state?.rules.pointCap, cap)
                XCTAssertEqual(state?.doubles != nil, sport == .badmintonDoubles)
            }
        }

        var pickleball = WatchSportsSetupDraft(sport: .pickleball, preferences: preferences)
        pickleball.pickleballTargetScore = 21
        pickleball.pickleballUseRallyScoring = true
        let pickleballState = WatchSetupPayloadMapper.rallyState(
            for: WatchScoreboardLaunchConfig(draft: pickleball)
        )
        XCTAssertEqual(pickleballState?.rules.pointsToWinSet, 21)
        XCTAssertEqual(pickleballState?.rules.useRallyScoring, true)

        var tennis = WatchSportsSetupDraft(sport: .tennis, preferences: preferences)
        tennis.tennisDeuceMode = "no_ad"
        let tennisState = WatchSetupPayloadMapper.tennisState(
            for: WatchScoreboardLaunchConfig(draft: tennis)
        )
        XCTAssertEqual(tennisState?.rules.usesNoAdScoring, true)

        var eightBall = WatchSportsSetupDraft(sport: .eightBall, preferences: preferences)
        eightBall.eightBallTargetRacks = 7
        eightBall.eightBallHandicapBeneficiary = .team2
        eightBall.eightBallHandicapRacks = 2
        let eightBallState = WatchSetupPayloadMapper.eightBallState(
            for: WatchScoreboardLaunchConfig(draft: eightBall)
        )
        XCTAssertEqual(eightBallState?.targetPoints, 7)
        XCTAssertEqual(eightBallState?.rightPoints, 2)
    }

    func testDoublesRecordListGroupsPartnersByTeam() {
        let record = WatchScoreboardRecord(canonical: CanonicalMatchRecord(
            id: "doubles-record",
            kind: .sport(.badmintonDoubles),
            source: .watchLocal,
            startEpochMilliseconds: 1_000_000,
            endEpochMilliseconds: 1_060_000,
            durationSeconds: 60,
            team1Name: "红方",
            team2Name: "蓝方",
            team1FinalScore: 21,
            team2FinalScore: 18,
            team1SetScore: 2,
            team2SetScore: 1,
            detailedActions: [],
            totalScoreChanges: 39,
            participants: [
                WatchRecordParticipant(name: "红A", score: 0),
                WatchRecordParticipant(name: "蓝A", score: 0),
                WatchRecordParticipant(name: "红B", score: 0),
                WatchRecordParticipant(name: "蓝B", score: 0)
            ]
        ))!

        let summary = WatchScoreboardRecordSummary(from: record)

        XCTAssertEqual(summary.doublesTeamNames?.left, "红A/红B")
        XCTAssertEqual(summary.doublesTeamNames?.right, "蓝A/蓝B")
        XCTAssertEqual(summary.listDisplayText, "红A/红B 2 - 蓝A/蓝B 1")
    }

    func testTennisTiebreakOnlyRecordListUsesPointsInsteadOfGames() {
        let record = WatchScoreboardRecord(canonical: CanonicalMatchRecord(
            id: "tennis-tiebreak-record",
            kind: .sport(.tennis),
            source: .watchLocal,
            startEpochMilliseconds: 1_000_000,
            endEpochMilliseconds: 1_060_000,
            durationSeconds: 60,
            team1Name: "甲",
            team2Name: "乙",
            team1FinalScore: 10,
            team2FinalScore: 8,
            team1SetScore: 0,
            team2SetScore: 0,
            detailedActions: [],
            totalScoreChanges: 18,
            projectConfiguration: [
                "setScoringMode": "tiebreak_only",
                "tieBreakPoints": "10"
            ]
        ))!

        let summary = WatchScoreboardRecordSummary(from: record)

        XCTAssertTrue(record.usesPointScoreForDisplay)
        XCTAssertEqual(summary.listDisplayText, "甲 10 - 8 乙")
    }

    func testMultiplayerRecordListKeepsIndividualScores() {
        let record = WatchScoreboardRecord(canonical: CanonicalMatchRecord(
            id: "multi-record",
            kind: .sport(.nineBall),
            source: .watchLocal,
            startEpochMilliseconds: 1_000_000,
            endEpochMilliseconds: 1_060_000,
            durationSeconds: 60,
            team1Name: "选手1",
            team2Name: "选手2",
            team1FinalScore: 8,
            team2FinalScore: 5,
            team1SetScore: 0,
            team2SetScore: 0,
            detailedActions: [],
            totalScoreChanges: 13,
            participants: [
                WatchRecordParticipant(name: "甲", score: 8),
                WatchRecordParticipant(name: "乙", score: 5),
                WatchRecordParticipant(name: "丙", score: 3),
                WatchRecordParticipant(name: "丁", score: 1)
            ]
        ))!

        let summary = WatchScoreboardRecordSummary(from: record)

        XCTAssertNil(summary.doublesTeamNames)
        XCTAssertEqual(summary.listDisplayText, "甲 8 · 乙 5 · 丙 3 · 丁 1")
    }

    func testSharedBasketballTrainingStateKeepsSixStatsInPackedRoundTrip() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let state = ShotTrainingState(
            mode: .free,
            startTime: timestamp,
            shots: [
                ShotTrainingShot(points: 1, made: true, timestamp: timestamp),
                ShotTrainingShot(points: 1, made: false, timestamp: timestamp),
                ShotTrainingShot(points: 2, made: true, timestamp: timestamp),
                ShotTrainingShot(points: 3, made: false, timestamp: timestamp)
            ]
        )
        let encoded = try JSONEncoder().encode(state)
        let roundTrip = try JSONDecoder().decode(ShotTrainingState.self, from: encoded)
        XCTAssertEqual(roundTrip, state)
        XCTAssertEqual(roundTrip.counts, ShotTrainingCounts(oneMade: 1, oneMiss: 1, twoMade: 1, threeMiss: 1))
    }

    func testActionLogUndoRemovesOnlyActionsCreatedByTheLocalMutation() {
        let start = Date(timeIntervalSince1970: 1_000)
        var log = WatchScoreActionLog(startedAt: start)
        let point = ScoreActionProjector.action(.scoreChanged, code: "point", scores: (1, 0), delta: 1,
                                                timestamp: start.addingTimeInterval(1))
        let set = ScoreActionProjector.action(.setFinished, code: "set_completed", scores: (1, 0),
                                              timestamp: start.addingTimeInterval(1))
        let finish = ScoreActionProjector.action(.matchFinished, code: "game_end", scores: (1, 0),
                                                 timestamp: start.addingTimeInterval(1))
        let otherPlayer = ScoreActionProjector.action(.scoreChanged, code: "point", scores: (0, 1), delta: 1,
                                                      timestamp: start.addingTimeInterval(0.5))
        log.beginUndoableMutation()
        log.append(contentsOf: [point, set, finish])
        log.merge(detailedActions: [otherPlayer])

        XCTAssertTrue(log.undo(at: start.addingTimeInterval(2), team1Score: 0, team2Score: 1))
        XCTAssertEqual(log.actions.map(\.type), [.matchStarted, .scoreChanged, .undo])
        XCTAssertEqual(log.actions[1].id, otherPlayer.id)
        XCTAssertEqual(log.scoreChangeCount, 1)
        XCTAssertFalse(log.merge(detailedActions: [point, set, finish]))
        XCTAssertFalse(log.actions.contains { $0.id == point.id })
    }

    func testRemoteActionTimelineRemovesOnlyExplicitIDsAndRejectsStaleReplay() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        var log = WatchScoreActionLog(startedAt: start)
        let watchPoint = ScoreActionProjector.action(.scoreChanged, code: "point", scores: (1, 0), delta: 1,
                                                     timestamp: start.addingTimeInterval(0.5))
        log.beginUndoableMutation()
        log.append(contentsOf: [watchPoint])

        let removed = Set(log.detailedActions.map(\.id))
        let offline = ScoreActionProjector.action(.scoreChanged, code: "offline_point", scores: (0, 1), delta: 1,
                                                   timestamp: start.addingTimeInterval(1))
        log.beginUndoableMutation()
        log.append(contentsOf: [offline])
        let replacement = DetailedScoreAction(
            type: .matchStarted,
            epochMilliseconds: 2_000,
            scores: [0, 0],
            operationCode: "game_start"
        )
        log.merge(detailedActions: [replacement], removing: removed)

        XCTAssertEqual(log.detailedActions.map(\.id), [replacement.id, offline.id])
        XCTAssertEqual(log.detailedActions.map(\.type), [.matchStarted, .scoreChanged])
        XCTAssertEqual(log.detailedActions.map(\.scores), [[0, 0], [0, 1]])
        XCTAssertEqual(log.detailedActions.map(\.operationCode), ["game_start", "offline_point"])
        XCTAssertEqual(log.scoreChangeCount, 1)

        let persisted = try JSONEncoder().encode(log)
        var restored = try JSONDecoder().decode(WatchScoreActionLog.self, from: persisted)
        XCTAssertFalse(restored.merge(detailedActions: [watchPoint, replacement, offline]))
        XCTAssertEqual(restored.actions.map(\.id), [replacement.id, offline.id])
        XCTAssertTrue(restored.undo(at: start.addingTimeInterval(2), team1Score: 0, team2Score: 0))
        XCTAssertEqual(restored.actions.map(\.type), [.matchStarted, .undo])
    }

    func testActionLogCountsScoringAdjustmentsButExcludesAdministrativeAndBasketballFouls() {
        var log = WatchScoreActionLog(startedAt: Date(timeIntervalSince1970: 1_000))
        log.append(contentsOf: [
            .init(type: .scoreChanged, scoreChange: 0, operationCode: "archery_miss"),
            .init(type: .scoreChanged, scoreChange: 0, operationCode: "point"),
            .init(type: .stateChanged, scoreChange: -1, operationCode: "edit_score"),
            .init(type: .stateChanged, scoreChange: 60, operationCode: "football_stoppage_add"),
            .init(type: .foul, scoreChange: -2, operationCode: "nine_ball_foul"),
            .init(type: .foul, scoreChange: 1, operationCode: "basketball_foul")
        ])
        XCTAssertEqual(log.scoreChangeCount, 3)
    }

    func testTiebreakOnlyTennisActionsOmitGamesMetadata() {
        var state = TennisMatchState(
            leftName: "甲",
            rightName: "乙",
            rules: TennisRuleSet(
                maxSets: 1,
                tieBreakPoints: 10,
                setScoringMode: .tiebreakOnly
            )
        )
        state.leftPoints = 10
        state.rightPoints = 8
        state.finished = true
        let actions = ScoreActionProjector.tennis(
            intent: .pointWon(.left),
            events: [
                .pointScored(side: .left, left: 10, right: 8),
                .matchFinished(winner: .left)
            ],
            state: state,
            timestamp: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(actions.map(\.scores), [[10, 8], [10, 8]])
        XCTAssertTrue(actions.allSatisfy { $0.setScores.isEmpty })
        XCTAssertTrue(actions.allSatisfy { $0.gameNumber == nil })

        var legacyLog = WatchScoreActionLog(startedAt: Date(timeIntervalSince1970: 900))
        let imported = ScoreActionProjector.action(.matchFinished, code: "game_end",
                                                   scores: (10, 8), sets: (0, 0), gameNumber: 1)
        legacyLog.append(contentsOf: [imported])
        legacyLog.omitSecondaryScores()
        XCTAssertTrue(legacyLog.actions.allSatisfy { $0.setScores.isEmpty && $0.gameNumber == nil })
        XCTAssertEqual(legacyLog.actions.last?.id, imported.id)
    }

    func testRallyProjectionKeepsScoreSetAndFinishOrder() {
        var state = RallyMatchEngine.initial(
            leftName: "红A/红B",
            rightName: "蓝A/蓝B",
            rules: .badminton(maxSets: 1)
        )
        state.leftSets = 1
        state.finished = true
        let actions = ScoreActionProjector.rally(
            intent: .pointWon(.left),
            events: [
                .pointScored(side: .left, leftPoints: 21, rightPoints: 19),
                .setCompleted(winner: .left, setNumber: 1, leftPoints: 21, rightPoints: 19, leftSets: 1, rightSets: 0),
                .matchFinished(winner: .left)
            ],
            state: state,
            timestamp: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(actions.map(\.type), [.scoreChanged, .setFinished, .matchFinished])
        XCTAssertEqual(actions.first?.team, .team1)
        XCTAssertEqual(actions[1].setNumber, 1)
    }

    func testSpecializedProjectorsKeepMissFoulAndParticipantIdentity() {
        let archery = ScoreActionProjector.archery(
            events: [
                .arrowScored(side: .right, points: 0, leftArrowSum: 9, rightArrowSum: 0),
                .arrowMissed(side: .right, leftArrowSum: 9, rightArrowSum: 0)
            ],
            state: ArcheryMatchState(leftName: "甲", rightName: "乙"),
            timestamp: Date()
        )
        XCTAssertEqual(archery.map(\.operationCode), ["archery_arrow", "archery_miss"])
        XCTAssertEqual(archery.first?.team, .team2)

        let seed = NineBallChaseState.initial(playerCount: 3, playerNames: ["甲", "乙", "丙"])
        let result = NineBallChaseReducer().reduce(
            state: seed,
            intent: .chaseTransfer(player: 2, kind: .foul, payer: nil, continuePlayer: nil),
            at: 1
        )
        let nineBall = ScoreActionProjector.nineBall(
            events: result.events,
            state: result.state,
            timestamp: Date()
        )
        XCTAssertEqual(nineBall.first?.type, .foul)
        XCTAssertEqual(nineBall.first?.roundNumber, 3)
        XCTAssertEqual(nineBall.first?.participants[2].name, "丙")
        XCTAssertLessThan(nineBall.first?.scoreChange ?? 0, 0)
    }

    func testAdaptiveScoreFontShrinksCompactAndThreeDigitScores() {
        XCTAssertEqual(
            WatchScoreTypography.adaptiveFontSize(
                baseSize: 64,
                scoreText: "29",
                minimumSize: 42,
                screenWidth: 187
            ),
            62
        )
        XCTAssertEqual(
            WatchScoreTypography.adaptiveFontSize(
                baseSize: 64,
                scoreText: "100",
                minimumSize: 42,
                screenWidth: 187
            ),
            51
        )
        XCTAssertEqual(
            WatchScoreTypography.adaptiveFontSize(
                baseSize: 64,
                scoreText: "1000",
                minimumSize: 42,
                screenWidth: 187
            ),
            42
        )
        XCTAssertEqual(
            WatchScoreTypography.adaptiveFontSize(
                baseSize: 64,
                scoreText: "100",
                minimumSize: 42,
                screenWidth: 198
            ),
            52
        )
    }

    func testDefaultParticipantFallbacksMatchPhonePolicy() {
        assertDefaultParticipantPair(.basketball, "team_a", "team_b")
        assertDefaultParticipantPair(.threeBasketball, "team_a", "team_b")
        assertDefaultParticipantPair(.volleyball, "team_a", "team_b")
        assertDefaultParticipantPair(.beachVolleyball, "team_a", "team_b")
        assertDefaultParticipantPair(.airVolleyball, "team_a", "team_b")
        assertDefaultParticipantPair(.guandan, "team_a", "team_b")
        assertDefaultParticipantPair(.shengji, "team_a", "team_b")
        assertDefaultParticipantPair(.football, "team_home", "team_away")
        assertDefaultParticipantPair(.archeryDual, "archer_a", "archer_b")
        assertDefaultParticipantPair(.pingpong, "player_a", "player_b")
        assertDefaultParticipantPair(.badminton, "player_a", "player_b")
        assertDefaultParticipantPair(.tennis, "player_a", "player_b")
        assertDefaultParticipantPair(.pickleball, "player_a", "player_b")
        assertDefaultParticipantPair(.foosball, "player_a", "player_b")
        assertDefaultParticipantPair(.billiards, "player_a", "player_b")
        assertDefaultParticipantPair(.eightBall, "player_a", "player_b")
        assertDefaultParticipantPair(.snooker, "player_a", "player_b")
        assertDefaultParticipantPair(.boxing, "watch_team_red", "watch_team_blue")
        assertDefaultParticipantPair(.simpleScore, "watch_team_red", "watch_team_blue")
        assertDefaultParticipantPair(.nineBall, "watch_setup_player_number", "watch_setup_player_number")
        assertDefaultParticipantPair(.doudizhu, "watch_setup_player_number", "watch_setup_player_number")
        assertDefaultParticipantPair(.uno, "watch_setup_player_number", "watch_setup_player_number")
        assertDefaultParticipantPair(.multiScoreboard, "watch_setup_player_number", "watch_setup_player_number")
    }

    func testLocalSetupPlaceholdersUseABAndDoublesColors() {
        XCTAssertEqual(
            WatchDefaultTeamNames.setupParticipantName(for: .archery, index: 0),
            NSLocalizedString("archer_a", comment: "")
        )
        XCTAssertEqual(
            WatchDefaultTeamNames.setupParticipantName(for: .archery, index: 1),
            NSLocalizedString("archer_b", comment: "")
        )
        XCTAssertEqual(
            WatchDefaultTeamNames.setupParticipantName(for: .pingpong, index: 0),
            NSLocalizedString("player_a", comment: "")
        )
        XCTAssertEqual(
            WatchDefaultTeamNames.setupParticipantName(for: .pingpong, index: 1),
            NSLocalizedString("player_b", comment: "")
        )
        XCTAssertEqual(
            (0..<4).map {
                WatchDefaultTeamNames.setupParticipantName(for: .pingpongDoubles, index: $0)
            },
            WatchDefaultTeamNames.doublesMembers
        )
        XCTAssertEqual(
            WatchDefaultTeamNames.fallback(for: ScoreCore.GameType.pingpongDoubles).members,
            WatchDefaultTeamNames.doublesMembers
        )

        for gameType in [
            ScoreCore.GameType.pingpongDoubles, .badmintonDoubles, .tennisDoubles,
            .pickleballDoubles, .foosballDoubles
        ] {
            let pair = WatchDefaultTeamNames.fallback(for: gameType)
            XCTAssertEqual(pair.members, WatchDefaultTeamNames.doublesMembers)
            XCTAssertFalse(pair.left.isEmpty)
            XCTAssertFalse(pair.right.isEmpty)
        }

        for sport in [
            WatchSetupSport.pingpongDoubles, .badmintonDoubles,
            .tennisDoubles, .pickleballDoubles
        ] {
            let draft = WatchSportsSetupDraft(sport: sport, preferences: preferences)
            let config = WatchScoreboardLaunchConfig(draft: draft)
            let localNames = WatchSetupPayloadMapper.twoSideNames(for: config)
            let canonical = WatchDefaultTeamNames.fallback(for: sport)
            XCTAssertEqual(localNames.left, canonical.left)
            XCTAssertEqual(localNames.right, canonical.right)
        }
    }

    func testNineBallDefaultParticipantNamesStayNumbered() {
        XCTAssertEqual(
            WatchDefaultTeamNames.setupParticipantName(for: .nineBall, index: 0),
            String.localizedStringWithFormat(
                NSLocalizedString("watch_setup_player_number", comment: ""),
                1
            )
        )
        XCTAssertEqual(
            WatchDefaultTeamNames.setupParticipantName(for: .nineBall, index: 3),
            String.localizedStringWithFormat(
                NSLocalizedString("watch_setup_player_number", comment: ""),
                4
            )
        )
    }


    // MARK: - Football

    func testFootballIsOfferedOnWatchHomeAndSetup() {
        XCTAssertTrue(WatchHomeItem.allCases.contains(.football))
        XCTAssertTrue(WatchHomeItem.allCases.contains(.football5v5))
        XCTAssertTrue(WatchSetupSport.allCases.contains(.football))
        XCTAssertTrue(WatchSetupSport.allCases.contains(.football5v5))

        for sport in [WatchSetupSport.football, .football5v5] {
            XCTAssertTrue(sport.isFootball)
            XCTAssertEqual(sport.defaultPlayerCount, 2)
            XCTAssertFalse(sport.isDoubles)
        }

        XCTAssertEqual(WatchHomeItem.football.gameType, .football)
        XCTAssertEqual(WatchHomeItem.football5v5.gameType, .football5v5)
        XCTAssertEqual(WatchSetupSport.football5v5.gameType, .football5v5)

        XCTAssertEqual(WatchGameType.football.rawValue, "football")
        XCTAssertEqual(WatchGameType.football5v5.rawValue, "football_5v5")
        XCTAssertEqual(WatchGameType.football.scoreCoreGameType, .football)
        XCTAssertEqual(WatchGameType.football5v5.scoreCoreGameType, .football5v5)
        XCTAssertTrue(WatchGameType.football.usesPointScoreInList)
        XCTAssertTrue(WatchGameType.football5v5.usesPointScoreInList)
    }

    func testFootballSetupDefaultsMatchPhoneHalfLengths() {
        let football = WatchSportsSetupDraft(sport: .football, preferences: preferences)
        XCTAssertEqual(football.footballHalfLengthMinutes, 45)
        XCTAssertEqual(football.maxSets, 0)
        XCTAssertEqual(football.pointsPerSet, 0)

        let futsal = WatchSportsSetupDraft(sport: .football5v5, preferences: preferences)
        XCTAssertEqual(futsal.footballHalfLengthMinutes, 20)

        XCTAssertEqual(WatchSportsSetupDraft.normalizedFootballHalfLengthMinutes(0), 5)
        XCTAssertEqual(WatchSportsSetupDraft.normalizedFootballHalfLengthMinutes(44), 45)
        XCTAssertEqual(WatchSportsSetupDraft.normalizedFootballHalfLengthMinutes(120), 90)

        // The active value must stay visible in the horizontally scrolling chips.
        XCTAssertEqual(WatchSportsSetupDraft.footballHalfLengthOptions(for: .football).first, 45)
        XCTAssertEqual(WatchSportsSetupDraft.footballHalfLengthOptions(for: .football5v5).first, 20)
        XCTAssertEqual(
            Set(WatchSportsSetupDraft.footballHalfLengthOptions(for: .football)),
            Set(WatchSportsSetupDraft.footballHalfLengthMinuteOptions)
        )
    }

    func testFootballHalfLengthPersistsAndFeedsLaunchConfig() {
        var draft = WatchSportsSetupDraft(sport: .football5v5, preferences: preferences)
        draft.footballHalfLengthMinutes = 30
        draft.persistRules(to: preferences)
        XCTAssertEqual(
            preferences.int(forKey: WatchSportsSetupDraft.footballHalfLengthMinutesKey, defaultValue: 0),
            30
        )

        let restored = WatchSportsSetupDraft(sport: .football5v5, preferences: preferences)
        XCTAssertEqual(restored.footballHalfLengthMinutes, 30)
        XCTAssertEqual(WatchScoreboardLaunchConfig(draft: restored).footballHalfLengthSeconds, 1800)
    }

    func testFootballLaunchConfigMapsClockStateAndGameType() throws {
        var draft = WatchSportsSetupDraft(sport: .football, preferences: preferences)
        draft.footballHalfLengthMinutes = 45
        draft.playerNames[0] = "甲队"
        draft.playerNames[1] = "乙队"
        let config = WatchScoreboardLaunchConfig(draft: draft)

        let clock = try XCTUnwrap(WatchSetupPayloadMapper.footballClockState(for: config))
        XCTAssertEqual(clock.halfLengthSeconds, 2700)
        XCTAssertEqual(clock.stage, 1)
        XCTAssertEqual(WatchSetupPayloadMapper.footballGameType(for: config), .football)

        let names = WatchSetupPayloadMapper.twoSideNames(for: config)
        XCTAssertEqual(names.left, "甲队")
        XCTAssertEqual(names.right, "乙队")

        var futsalDraft = WatchSportsSetupDraft(sport: .football5v5, preferences: preferences)
        futsalDraft.footballHalfLengthMinutes = 20
        let futsalConfig = WatchScoreboardLaunchConfig(draft: futsalDraft)
        XCTAssertEqual(WatchSetupPayloadMapper.footballGameType(for: futsalConfig), .football5v5)
        XCTAssertEqual(
            WatchSetupPayloadMapper.footballClockState(for: futsalConfig)?.halfLengthSeconds,
            1200
        )

        let snookerConfig = WatchScoreboardLaunchConfig(
            draft: WatchSportsSetupDraft(sport: .snooker, preferences: preferences)
        )
        XCTAssertNil(WatchSetupPayloadMapper.footballClockState(for: snookerConfig))
        XCTAssertNil(WatchSetupPayloadMapper.footballGameType(for: snookerConfig))
    }

    func testFootballClockFollowsPhonePeriodRules() {
        let football = FootballMatchClockSession(
            state: FootballTimerStateV2(halfLengthSeconds: 45 * 60),
            gameType: .football
        )
        XCTAssertTrue(football.allowsStoppageTime)
        XCTAssertTrue(football.allowsExtraTime)
        XCTAssertFalse(football.allowsManualPause)
        XCTAssertFalse(football.state.isRunning)

        var futsal = FootballMatchClockSession(
            state: FootballTimerStateV2(halfLengthSeconds: 20 * 60),
            gameType: .football5v5
        )
        XCTAssertTrue(futsal.allowsManualPause)
        XCTAssertFalse(futsal.allowsStoppageTime)
        XCTAssertFalse(futsal.allowsExtraTime)
        futsal.start()
        XCTAssertTrue(futsal.state.isRunning)
        futsal.pause()
        XCTAssertFalse(futsal.state.isRunning)
    }

    /// 用一份 Reducer State 构造标准续玩 bundle（含 1 层撤销帧）。
    private func footballResumeBundle(
        _ state: FootballMatchState,
        gameType: ScoreCore.GameType,
        previous: FootballMatchState? = nil
    ) -> WatchFootballResumeBundle {
        let session = ScoreSession<FootballMatchState, FootballMatchEvent>(
            gameType: gameType,
            ruleFamily: .s1,
            reducerType: ScoreboardKernelRegistry.footballReducerType(for: gameType) ?? "football/v1",
            state: state
        )
        let seed = previous.map {
            ScoreSession<FootballMatchState, FootballMatchEvent>(
                gameType: gameType,
                ruleFamily: .s1,
                reducerType: ScoreboardKernelRegistry.footballReducerType(for: gameType) ?? "football/v1",
                state: $0
            )
        } ?? session
        let undoFrames = previous == nil ? [] : [ScoreSessionResumeUndoFrame(session: seed)]
        return ScoreSessionResumeBundle(
            replaySeed: seed,
            currentSession: session,
            undoFrames: undoFrames,
            timeline: []
        )
    }

    func testFootballResumeRouteKeepsHalfLengthAndGameType() {
        let state = FootballMatchState(
            leftName: "甲",
            rightName: "乙",
            leftScore: 2,
            rightScore: 1,
            timer: FootballTimerStateV2(halfLengthSeconds: 20 * 60, elapsedSeconds: 120),
            isFiveAside: true,
            kickedOff: true
        )
        let session = WatchResumeSession(
            startedAt: Date(timeIntervalSince1970: 1_000),
            scoreLine: "2 - 1",
            emoji: "⚽",
            payload: .football(
                isFiveAside: true,
                bundle: footballResumeBundle(state, gameType: .football5v5)
            )
        )
        XCTAssertEqual(session.payload.gameType, .football5v5)
        guard case .football5v5(let halfLengthSeconds)? = WatchScoreboardRoute(resumeSession: session) else {
            return XCTFail("Expected a 5×5 football route")
        }
        XCTAssertEqual(halfLengthSeconds, 1200)
    }

    func testFootballResumeSessionRoundTripsThroughCodable() throws {
        let state = FootballMatchState(
            leftName: "主队",
            rightName: "客队",
            leftScore: 3,
            rightScore: 3,
            timer: FootballTimerStateV2(
                stage: 2,
                halfLengthSeconds: 45 * 60,
                elapsedSeconds: 90,
                isRunning: true,
                savedWallClockMilliseconds: 1_700_000_000_000,
                stoppageSeconds: [0, 180, 0, 0]
            ),
            stoppageHistory: [180],
            kickedOff: true,
            elapsedSubsecondMilliseconds: 420
        )
        var previous = state
        previous.leftScore = 2
        let session = WatchResumeSession(
            startedAt: Date(timeIntervalSince1970: 2_000),
            scoreLine: "3 - 3",
            emoji: "⚽",
            payload: .football(
                isFiveAside: false,
                bundle: footballResumeBundle(state, gameType: .football, previous: previous)
            )
        )
        let decoded = try JSONDecoder().decode(
            WatchResumeSession.self,
            from: try JSONEncoder().encode(session)
        )
        guard case .football(let isFiveAside, let bundle) = decoded.payload else {
            return XCTFail("Expected football payload")
        }
        XCTAssertFalse(isFiveAside)
        let restored = bundle.currentSession.state
        XCTAssertEqual(restored, state)
        // 时钟锚点、分秒余量与补时历史必须随续玩草稿无损往返。
        XCTAssertEqual(restored.timer.savedWallClockMilliseconds, 1_700_000_000_000)
        XCTAssertEqual(restored.elapsedSubsecondMilliseconds, 420)
        XCTAssertEqual(restored.stoppageHistory, [180])
        XCTAssertEqual(bundle.undoFrames.count, 1)
        XCTAssertEqual(WatchScoreboardRoute(resumeSession: decoded)?.id, "football-2700")
    }

    func testFootballHelpersMatchPhonePresentation() {
        XCTAssertEqual(WatchFootballRules.gameType(isFiveAside: false).rawValue, "football")
        XCTAssertEqual(WatchFootballRules.gameType(isFiveAside: true).rawValue, "football_5v5")
        XCTAssertEqual(WatchFootballRules.watchGameType(isFiveAside: true), .football5v5)
        XCTAssertEqual(WatchFootballRules.stageBadge(1), "1H")
        XCTAssertEqual(WatchFootballRules.stageBadge(2), "2H")
        XCTAssertEqual(WatchFootballRules.stageBadge(3), "1T")
        XCTAssertEqual(WatchFootballRules.stageBadge(4), "2T")
        XCTAssertEqual(WatchFootballRules.formattedClock(seconds: 125), "02:05")
        XCTAssertEqual(WatchFootballRules.formattedStoppage(seconds: 65), "+01:05")
    }

    func testFootballDefaultNamesUseHomeAndAwayTeams() {
        XCTAssertEqual(
            WatchDefaultTeamNames.setupParticipantName(for: .football, index: 0),
            NSLocalizedString("team_home", comment: "")
        )
        XCTAssertEqual(
            WatchDefaultTeamNames.setupParticipantName(for: .football5v5, index: 1),
            NSLocalizedString("team_away", comment: "")
        )
        XCTAssertEqual(
            WatchDefaultTeamNames.fallback(for: ScoreCore.GameType.football).left,
            NSLocalizedString("team_home", comment: "")
        )
    }

    func testWatchSportArtworkMatchesPhoneCatalog() {
        XCTAssertEqual(WatchCatalogIconAssets.game(.football), "icon_3d_football")
        XCTAssertEqual(WatchCatalogIconAssets.game(.football5v5), "icon_3d_football")
        XCTAssertEqual(WatchCatalogIconAssets.game(.pingpong), "icon_3d_pingpong")
        XCTAssertEqual(WatchCatalogIconAssets.game(.pickleball), "icon_3d_pickleball")
        XCTAssertEqual(WatchCatalogIconAssets.game(.eightBall), "icon_3d_eight_ball")
        XCTAssertEqual(WatchCatalogIconAssets.game(.nineBall), "icon_3d_nine_ball")
        XCTAssertEqual(WatchCatalogIconAssets.game(.basketballTraining), "icon_3d_basketball")
        XCTAssertEqual(WatchCatalogIconAssets.homeItem(.football5v5), "icon_3d_football")
        XCTAssertEqual(WatchCatalogIconAssets.homeItem(.basketball_training), "icon_3d_basketball")
        XCTAssertEqual(WatchCatalogIconAssets.sport(.football), "icon_3d_football")
        XCTAssertEqual(WatchCatalogIconAssets.tool("flip_coin"), "icon_3d_flip_coin")
    }

    func testEveryWatchEntryArtworkIsBundled() {
        let gameTypes: [WatchGameType] = [
            .badminton, .pingpong, .tennis, .pickleball, .archery,
            .eightBall, .nineBall, .snooker, .football, .football5v5,
            .shuttlecock, .squash, .foosball,
            .basketballTraining
        ]
        for gameType in gameTypes {
            XCTAssertNotNil(
                UIImage(named: WatchCatalogIconAssets.game(gameType)),
                "Missing artwork for \(gameType.rawValue)"
            )
        }
        for toolID in ["flip_coin", "dice", "ten_second", "simple_score"] {
            XCTAssertNotNil(
                UIImage(named: WatchCatalogIconAssets.tool(toolID)),
                "Missing tool artwork \(toolID)"
            )
        }
    }


    func testFootballRecordListUsesGoalTotals() {
        let record = WatchScoreboardRecord(canonical: CanonicalMatchRecord(
            id: "w_football_test",
            kind: .sport(.football),
            source: .watchLocal,
            startEpochMilliseconds: 1_000_000,
            endEpochMilliseconds: 1_600_000,
            durationSeconds: 600,
            team1Name: "主队",
            team2Name: "客队",
            team1FinalScore: 2,
            team2FinalScore: 1,
            team1SetScore: 0,
            team2SetScore: 0,
            winnerIdentity: .team(.team0),
            detailedActions: [],
            totalScoreChanges: 3
        ))!
        let summary = WatchScoreboardRecordSummary(from: record)
        XCTAssertEqual(summary.listDisplayText, "主队 2 - 1 客队")
        XCTAssertTrue(record.usesPointScoreForDisplay)

        let futsal = WatchScoreboardRecord(canonical: CanonicalMatchRecord(
            id: "w_futsal_test",
            kind: .sport(.football5v5),
            source: .watchLocal,
            startEpochMilliseconds: record.canonical.startEpochMilliseconds,
            endEpochMilliseconds: record.canonical.endEpochMilliseconds,
            durationSeconds: 600,
            team1Name: "甲",
            team2Name: "乙",
            team1FinalScore: 0,
            team2FinalScore: 0,
            team1SetScore: 0,
            team2SetScore: 0,
            detailedActions: [],
            totalScoreChanges: 0
        ))!
        XCTAssertEqual(WatchScoreboardRecordSummary(from: futsal).listDisplayText, "甲 0 - 0 乙")
    }


    func testFootballGoalMinuteLabelMatchesHarmonyFormat() {
        XCTAssertEqual(
            WatchFootballRules.goalMinuteLabel(
                isFiveAside: false, halfLengthSeconds: 45 * 60, period: 1, elapsedSeconds: 0
            ),
            "1′"
        )
        XCTAssertEqual(
            WatchFootballRules.goalMinuteLabel(
                isFiveAside: false, halfLengthSeconds: 45 * 60, period: 1, elapsedSeconds: 600
            ),
            "10′"
        )
        XCTAssertEqual(
            WatchFootballRules.goalMinuteLabel(
                isFiveAside: false, halfLengthSeconds: 45 * 60, period: 1, elapsedSeconds: 45 * 60 + 60
            ),
            "45+1′"
        )
        XCTAssertEqual(
            WatchFootballRules.goalMinuteLabel(
                isFiveAside: false, halfLengthSeconds: 45 * 60, period: 2, elapsedSeconds: 600
            ),
            "55′"
        )
        XCTAssertEqual(
            WatchFootballRules.goalMinuteLabel(
                isFiveAside: false, halfLengthSeconds: 45 * 60, period: 3, elapsedSeconds: 60
            ),
            "91′"
        )
        XCTAssertEqual(
            WatchFootballRules.goalMinuteLabel(
                isFiveAside: false, halfLengthSeconds: 45 * 60, period: 4, elapsedSeconds: 600
            ),
            "115′"
        )
        XCTAssertEqual(
            WatchFootballRules.goalMinuteLabel(
                isFiveAside: true, halfLengthSeconds: 20 * 60, period: 1, elapsedSeconds: 300
            ),
            "5′"
        )
        XCTAssertEqual(
            WatchFootballRules.goalMinuteLabel(
                isFiveAside: true, halfLengthSeconds: 20 * 60, period: 2, elapsedSeconds: 60
            ),
            "21′"
        )
        XCTAssertNil(
            WatchFootballRules.goalMinuteLabel(
                isFiveAside: true, halfLengthSeconds: 20 * 60, period: 3, elapsedSeconds: 60
            )
        )
        XCTAssertNil(
            WatchFootballRules.goalMinuteLabel(
                isFiveAside: false, halfLengthSeconds: 45 * 60, period: 5, elapsedSeconds: 60
            )
        )
        XCTAssertNil(
            WatchFootballRules.goalMinuteLabel(
                isFiveAside: false, halfLengthSeconds: 45 * 60, period: 1, elapsedSeconds: nil
            )
        )
    }

    func testFootballGoalActionKeepsMatchClockSnapshot() throws {
        let action = ScoreActionProjector.action(
            .scoreChanged,
            code: "football_goal",
            side: .left,
            scores: (1, 0),
            delta: 1,
            periodNumber: 2,
            footballPeriod: 2,
            footballElapsedSeconds: 600
        )
        XCTAssertEqual(action.footballPeriod, 2)
        XCTAssertEqual(action.footballElapsedSeconds, 600)
        let restored = try JSONDecoder().decode(DetailedScoreAction.self, from: JSONEncoder().encode(action))
        XCTAssertEqual(restored, action)
    }


    func testShuttlecockSquashAndFoosballAreOfferedOnWatch() {
        for item in [WatchHomeItem.shuttlecock, .squash, .foosball] {
            XCTAssertTrue(WatchHomeItem.allCases.contains(item))
        }
        for sport in [WatchSetupSport.shuttlecock, .squash, .foosball] {
            XCTAssertTrue(WatchSetupSport.allCases.contains(sport))
            XCTAssertEqual(sport.defaultPlayerCount, 2)
        }
        XCTAssertEqual(WatchHomeItem.shuttlecock.gameType, .shuttlecock)
        XCTAssertEqual(WatchHomeItem.squash.gameType, .squash)
        XCTAssertEqual(WatchHomeItem.foosball.gameType, .foosball)
        XCTAssertEqual(WatchGameType.shuttlecock.scoreCoreGameType, .shuttlecock)
        XCTAssertEqual(WatchGameType.squash.scoreCoreGameType, .squash)
        XCTAssertEqual(WatchGameType.foosball.scoreCoreGameType, .foosball)
        XCTAssertEqual(WatchCatalogIconAssets.game(.shuttlecock), "icon_3d_shuttlecock")
        XCTAssertEqual(WatchCatalogIconAssets.game(.squash), "icon_3d_squash")
        XCTAssertEqual(WatchCatalogIconAssets.game(.foosball), "icon_3d_foosball")
    }

    func testShuttlecockSquashAndFoosballBuildRallyStates() throws {
        let shuttle = WatchSportsSetupDraft(sport: .shuttlecock, preferences: preferences)
        XCTAssertEqual(shuttle.maxSets, 3)
        XCTAssertEqual(shuttle.pointsPerSet, 21)
        let shuttleState = try XCTUnwrap(
            WatchSetupPayloadMapper.rallyState(for: WatchScoreboardLaunchConfig(draft: shuttle))
        )
        XCTAssertEqual(shuttleState.rules.pointsToWinSet, 21)
        XCTAssertTrue(shuttleState.rules.winByTwo)

        let squash = WatchSportsSetupDraft(sport: .squash, preferences: preferences)
        XCTAssertEqual(squash.maxSets, 5)
        XCTAssertEqual(squash.pointsPerSet, 11)
        let squashState = try XCTUnwrap(
            WatchSetupPayloadMapper.rallyState(for: WatchScoreboardLaunchConfig(draft: squash))
        )
        XCTAssertEqual(squashState.rules.pointsToWinSet, 11)
        // The watch disables automatic side changes on every rally board.
        XCTAssertFalse(squashState.rules.autoChangeSides)

        let foosball = WatchSportsSetupDraft(sport: .foosball, preferences: preferences)
        XCTAssertEqual(foosball.maxSets, 3)
        XCTAssertEqual(foosball.pointsPerSet, 5)
        let foosballState = try XCTUnwrap(
            WatchSetupPayloadMapper.rallyState(for: WatchScoreboardLaunchConfig(draft: foosball))
        )
        XCTAssertEqual(foosballState.rules.pointsToWinSet, 5)
        XCTAssertFalse(foosballState.rules.winByTwo)
    }


    func testWatchLocalizationsStayInSync() throws {
        let locales = ["en", "zh-Hans", "zh-Hant"]
        var strings: [String: [String: String]] = [:]
        for locale in locales {
            let path = try XCTUnwrap(Bundle.main.path(forResource: locale, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            let file = try XCTUnwrap(bundle.path(forResource: "Localizable", ofType: "strings"))
            let dict = try XCTUnwrap(NSDictionary(contentsOfFile: file) as? [String: String])
            strings[locale] = dict
        }
        let base = try XCTUnwrap(strings["en"])
        for locale in locales.dropFirst() {
            let other = try XCTUnwrap(strings[locale])
            XCTAssertEqual(
                Set(base.keys),
                Set(other.keys),
                "\(locale) key set drifted from en"
            )
            for (key, source) in base {
                guard let translated = other[key] else { continue }
                XCTAssertFalse(translated.isEmpty, "\(locale).\(key) is empty")
                XCTAssertEqual(
                    placeholders(in: source),
                    placeholders(in: translated),
                    "\(locale).\(key) placeholder mismatch"
                )
            }
        }
    }

    private func placeholders(in value: String) -> [String] {
        let pattern = "%(\\d+\\$)?[@dfs]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..., in: value)
        return regex.matches(in: value, range: range).map {
            String(value[Range($0.range, in: value)!])
        }
    }

    func testWatchTenSecondChallengePolicy() {
        XCTAssertEqual(WatchTenSecondChallengePolicy.presetSeconds, [1, 3, 5, 10])
        XCTAssertEqual(WatchTenSecondChallengePolicy.defaultTargetSeconds, 10)
        for preset in WatchTenSecondChallengePolicy.presetSeconds {
            XCTAssertEqual(WatchTenSecondChallengePolicy.normalizedTargetSeconds(preset), preset)
        }
        for invalid in [0, 2, 7, -3] {
            XCTAssertEqual(WatchTenSecondChallengePolicy.normalizedTargetSeconds(invalid), 10)
        }

        XCTAssertEqual(WatchTenSecondChallengePolicy.difference(elapsed: 1.00, targetSeconds: 1), 0.0, accuracy: 0.0001)
        XCTAssertEqual(WatchTenSecondChallengePolicy.difference(elapsed: 0.94, targetSeconds: 1), 0.06, accuracy: 0.0001)
        XCTAssertEqual(WatchTenSecondChallengePolicy.difference(elapsed: 3.05, targetSeconds: 3), 0.05, accuracy: 0.0001)
        XCTAssertEqual(WatchTenSecondChallengePolicy.difference(elapsed: 4.88, targetSeconds: 5), 0.12, accuracy: 0.0001)
        XCTAssertEqual(WatchTenSecondChallengePolicy.difference(elapsed: 10.00, targetSeconds: 10), 0.0, accuracy: 0.0001)
        XCTAssertEqual(WatchTenSecondChallengePolicy.difference(elapsed: -0.5, targetSeconds: 5), 5.0, accuracy: 0.0001)

        XCTAssertEqual(WatchTenSecondChallengePolicy.hapticType(for: 0.0), .strong)
        XCTAssertEqual(WatchTenSecondChallengePolicy.hapticType(for: 0.005), .strong)
        XCTAssertEqual(WatchTenSecondChallengePolicy.hapticType(for: 0.05), .medium)
        XCTAssertEqual(WatchTenSecondChallengePolicy.hapticType(for: 0.25), .light)
    }

    private func assertDefaultParticipantPair(
        _ gameType: ScoreCore.GameType,
        _ leftKey: String,
        _ rightKey: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let pair = WatchDefaultTeamNames.fallback(for: gameType)
        if leftKey == "watch_setup_player_number" {
            XCTAssertEqual(
                pair.left,
                String.localizedStringWithFormat(NSLocalizedString(leftKey, comment: ""), 1),
                file: file,
                line: line
            )
            XCTAssertEqual(
                pair.right,
                String.localizedStringWithFormat(NSLocalizedString(rightKey, comment: ""), 2),
                file: file,
                line: line
            )
        } else {
            XCTAssertEqual(pair.left, NSLocalizedString(leftKey, comment: ""), file: file, line: line)
            XCTAssertEqual(pair.right, NSLocalizedString(rightKey, comment: ""), file: file, line: line)
        }
    }
}

func trainingResumeFixture(
    mode: ShotTrainingMode, startedAt: Date, shots: [ShotTrainingShot] = []
) -> WatchResumePayload {
    let descriptor = ScoreboardKernelRegistry.descriptor(for: .basketballTraining)
    let seed = ScoreSession<ShotTrainingState, ShotTrainingEvent>(
        gameType: .basketballTraining, ruleFamily: descriptor.ruleFamily, reducerType: descriptor.reducerType,
        state: ShotTrainingState(mode: mode, startTime: startedAt, shots: shots)
    )
    let machine = ScoreSessionMachine(seedSession: seed, reducer: ShotTrainingReducer())
    return .basketballTraining(bundle: machine.resumeBundle())
}
