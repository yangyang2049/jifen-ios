import XCTest
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

    func testPickleballUsesTableTennisIcon() {
        XCTAssertEqual(WatchGameType.pickleball.icon, WatchGameType.pingpong.icon)
    }

    func testRegulationBasketballIsHistoricalOnlyAndHasRecordMappings() {
        XCTAssertFalse(WatchHomeItem.allCases.map(\.rawValue).contains("basketball"))
        XCTAssertFalse(WatchHomeItem.allCases.map(\.rawValue).contains("three_basketball"))
        XCTAssertFalse(WatchSetupSport.allCases.map(\.rawValue).contains("basketball"))
        XCTAssertFalse(WatchSetupSport.allCases.map(\.rawValue).contains("three_basketball"))
        XCTAssertEqual(WatchGameType.basketball.scoreCoreGameType, .basketball)
        XCTAssertEqual(WatchGameType.threeBasketball.scoreCoreGameType, .threeBasketball)
        XCTAssertTrue(WatchGameType.basketball.usesPointScoreInList)
        XCTAssertTrue(WatchGameType.threeBasketball.usesPointScoreInList)
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
        let reducer = NineBallChaseReducer()
        let two = reducer.reduce(
            state: .initial(config: .init(foul: 2), playerCount: 2),
            intent: .chaseEvent(player: 0, kind: .foul),
            at: 1
        ).state
        XCTAssertEqual(two.playerPoints[0], 0)
        XCTAssertEqual(two.playerPoints[1], 2)

        let four = reducer.reduce(
            state: .initial(config: .init(foul: 2), playerCount: 4),
            intent: .chaseEvent(player: 2, kind: .foul),
            at: 1
        ).state
        XCTAssertEqual(four.playerPoints[2], -2)
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

        let actions = WatchScoreActionProjector.snooker(
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
        let store = WatchResumeSessionStore(defaults: defaults, now: { currentDate })
        let sessionID = UUID()
        let link = WatchLinkResumeContext(
            sessionId: sessionID,
            revision: 3,
            controlRole: .watchController,
            setup: LinkedScoreboardSetup(gameType: .basketball)
        )
        let shot = WatchBasketballTrainingShot(points: 2, made: true)
        store.save(WatchResumeSession(
            startedAt: currentDate.addingTimeInterval(-30),
            scoreLine: "2 / 1",
            emoji: "🏀",
            payload: .basketballTraining(mode: .free, history: [shot]),
            link: link
        ))

        // Within TTL: session persists
        let restored = WatchResumeSessionStore(defaults: defaults, now: { currentDate })
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
        XCTAssertNil(defaults.data(forKey: "watch_resume_session"))
    }

    @MainActor
    func testResumeSessionMigratesLegacyArcheryPhysicalSideSwap() throws {
        let now = Date(timeIntervalSince1970: 15_000)
        let legacyState = ArcheryMatchState(
            leftName: "蓝射手",
            rightName: "红射手",
            leftArrowSum: 18,
            rightArrowSum: 19,
            leftSetPoints: 0,
            rightSetPoints: 2,
            currentShooterIsLeft: false,
            openingShooterIsLeft: false,
            sidesSwapped: true
        )
        let legacyUndoState = ArcheryMatchState(
            leftName: "蓝射手",
            rightName: "红射手",
            leftArrowSum: 8,
            rightArrowSum: 9,
            currentShooterIsLeft: false,
            openingShooterIsLeft: false,
            sidesSwapped: true
        )
        let session = WatchResumeSession(
            savedAt: now,
            startedAt: now.addingTimeInterval(-30),
            scoreLine: "0 : 2",
            emoji: "🏹",
            payload: .archery(
                state: legacyState,
                undoStates: [legacyUndoState],
                restState: nil
            )
        )
        let encoded = try JSONEncoder().encode(session)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json["schemaVersion"] = 2
        defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: "watch_resume_session")

        let restoredStore = WatchResumeSessionStore(defaults: defaults, now: { now })
        let restoredSession = try XCTUnwrap(restoredStore.session)
        XCTAssertEqual(restoredSession.schemaVersion, WatchResumeSession.currentSchemaVersion)
        guard case .archery(let state, let undoStates, _) = restoredSession.payload else {
            return XCTFail("Expected migrated archery payload")
        }
        XCTAssertEqual(state.leftName, "红射手")
        XCTAssertEqual(state.rightName, "蓝射手")
        XCTAssertEqual(state.leftArrowSum, 19)
        XCTAssertEqual(state.rightArrowSum, 18)
        XCTAssertEqual(state.leftSetPoints, 2)
        XCTAssertEqual(state.rightSetPoints, 0)
        XCTAssertTrue(state.currentShooterIsLeft)
        XCTAssertTrue(state.openingShooterIsLeft)
        XCTAssertTrue(state.sidesSwapped)
        XCTAssertEqual(undoStates.first?.leftName, "红射手")
        XCTAssertEqual(undoStates.first?.leftArrowSum, 9)
        XCTAssertEqual(undoStates.first?.rightArrowSum, 8)

        let persistedData = try XCTUnwrap(defaults.data(forKey: "watch_resume_session"))
        let persisted = try JSONDecoder().decode(WatchResumeSession.self, from: persistedData)
        XCTAssertEqual(persisted.schemaVersion, WatchResumeSession.currentSchemaVersion)
    }

    @MainActor
    func testResumeSessionRefreshUsesLatestLinkedActionTimeline() throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let sessionID = UUID()
        let store = WatchResumeSessionStore(defaults: defaults, now: { now })
        store.save(WatchResumeSession(
            startedAt: now,
            scoreLine: "1 : 0",
            emoji: "🏸",
            payload: .basketballTraining(mode: .free, history: []),
            actionLog: WatchScoreActionLog(startedAt: now),
            link: WatchLinkResumeContext(
                sessionId: sessionID,
                revision: 1,
                controlRole: .watchFollower,
                setup: LinkedScoreboardSetup(gameType: .badminton)
            )
        ))

        let remoteAction = DetailedScoreAction(
            type: .scoreChanged,
            epochMilliseconds: 20_500,
            team: .team1,
            scores: [1, 0],
            scoreChange: 1,
            operationCode: "point"
        )
        store.refreshLinkContext(WatchLinkResumeContext(
            sessionId: sessionID,
            revision: 2,
            controlRole: .watchFollower,
            setup: LinkedScoreboardSetup(
                gameType: .badminton,
                detailedActions: [remoteAction]
            )
        ))

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

    func testLegacyWatchRecordDecodesWithoutNewOptionalFields() throws {
        let json = """
        [{
          "id": "legacy",
          "gameType": "basketballTraining",
          "startTime": "2026-07-23T00:00:00Z",
          "endTime": "2026-07-23T00:01:00Z",
          "duration": 60,
          "team1Name": "出手",
          "team2Name": "命中",
          "team1FinalScore": 10,
          "team2FinalScore": 6,
          "team1SetScore": 0,
          "team2SetScore": 0,
          "actions": [],
          "totalScoreChanges": 16
        }]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = try decoder.decode(
            [WatchScoreboardRecord].self,
            from: Data(json.utf8)
        )
        XCTAssertNil(records[0].participants)
        XCTAssertNil(records[0].projectConfiguration)
        XCTAssertNil(records[0].basketballTrainingDetails)
        XCTAssertEqual(records[0].team1FinalScore, 10)
    }

    func testDoublesRecordListGroupsPartnersByTeam() {
        let record = WatchScoreboardRecord(
            id: "doubles-record",
            gameType: .badminton,
            startTime: Date(timeIntervalSince1970: 1_000),
            endTime: Date(timeIntervalSince1970: 1_060),
            duration: 60,
            team1Name: "红方",
            team2Name: "蓝方",
            team1FinalScore: 21,
            team2FinalScore: 18,
            team1SetScore: 2,
            team2SetScore: 1,
            actions: [],
            totalScoreChanges: 39,
            participants: [
                WatchRecordParticipant(name: "红A", score: 0),
                WatchRecordParticipant(name: "蓝A", score: 0),
                WatchRecordParticipant(name: "红B", score: 0),
                WatchRecordParticipant(name: "蓝B", score: 0)
            ]
        )

        let summary = WatchScoreboardRecordSummary(from: record)

        XCTAssertEqual(summary.doublesTeamNames?.left, "红A/红B")
        XCTAssertEqual(summary.doublesTeamNames?.right, "蓝A/蓝B")
        XCTAssertEqual(summary.listDisplayText, "红A/红B 2 - 蓝A/蓝B 1")
    }

    func testTennisTiebreakOnlyRecordListUsesPointsInsteadOfGames() {
        let record = WatchScoreboardRecord(
            id: "tennis-tiebreak-record",
            gameType: .tennis,
            startTime: Date(timeIntervalSince1970: 1_000),
            endTime: Date(timeIntervalSince1970: 1_060),
            duration: 60,
            team1Name: "甲",
            team2Name: "乙",
            team1FinalScore: 10,
            team2FinalScore: 8,
            team1SetScore: 0,
            team2SetScore: 0,
            actions: [],
            totalScoreChanges: 18,
            projectConfiguration: [
                "setScoringMode": "tiebreak_only",
                "tieBreakPoints": "10"
            ]
        )

        let summary = WatchScoreboardRecordSummary(from: record)

        XCTAssertTrue(record.usesPointScoreForDisplay)
        XCTAssertEqual(summary.listDisplayText, "甲 10 - 8 乙")
    }

    func testMultiplayerRecordListKeepsIndividualScores() {
        let record = WatchScoreboardRecord(
            id: "multi-record",
            gameType: .nineBall,
            startTime: Date(timeIntervalSince1970: 1_000),
            endTime: Date(timeIntervalSince1970: 1_060),
            duration: 60,
            team1Name: "选手1",
            team2Name: "选手2",
            team1FinalScore: 8,
            team2FinalScore: 5,
            team1SetScore: 0,
            team2SetScore: 0,
            actions: [],
            totalScoreChanges: 13,
            participants: [
                WatchRecordParticipant(name: "甲", score: 8),
                WatchRecordParticipant(name: "乙", score: 5),
                WatchRecordParticipant(name: "丙", score: 3),
                WatchRecordParticipant(name: "丁", score: 1)
            ]
        )

        let summary = WatchScoreboardRecordSummary(from: record)

        XCTAssertNil(summary.doublesTeamNames)
        XCTAssertEqual(summary.listDisplayText, "甲 8 · 乙 5 · 丙 3 · 丁 1")
    }

    func testBasketballTrainingDetailsKeepSixAndroidStatsAndDecodeFirstVersion() throws {
        let shots = [
            WatchBasketballTrainingShot(points: 1, made: true),
            WatchBasketballTrainingShot(points: 1, made: false),
            WatchBasketballTrainingShot(points: 2, made: true),
            WatchBasketballTrainingShot(points: 3, made: false)
        ]
        let details = WatchBasketballTrainingDetails(mode: .free, shots: shots)
        XCTAssertEqual(details.count(points: 1, made: true), 1)
        XCTAssertEqual(details.count(points: 1, made: false), 1)
        XCTAssertEqual(details.count(points: 2, made: true), 1)
        XCTAssertEqual(details.count(points: 2, made: false), 0)
        XCTAssertEqual(details.count(points: 3, made: true), 0)
        XCTAssertEqual(details.count(points: 3, made: false), 1)

        let encoded = try JSONEncoder().encode(details)
        let roundTrip = try JSONDecoder().decode(
            WatchBasketballTrainingDetails.self,
            from: encoded
        )
        XCTAssertEqual(roundTrip.onePointMade, 1)
        XCTAssertEqual(roundTrip.threePointMiss, 1)

        let firstVersionJSON = """
        {
          "mode": "free",
          "shots": [
            {
              "id": "legacy-shot",
              "points": 2,
              "made": true,
              "timestamp": 0
            }
          ]
        }
        """
        let legacy = try JSONDecoder().decode(
            WatchBasketballTrainingDetails.self,
            from: Data(firstVersionJSON.utf8)
        )
        XCTAssertNil(legacy.twoPointMade)
        XCTAssertEqual(legacy.count(points: 2, made: true), 1)
    }

    func testActionLogUndoRemovesEveryActionCreatedByOneMutation() {
        let start = Date(timeIntervalSince1970: 1_000)
        var log = WatchScoreActionLog(startedAt: start)
        log.beginUndoableMutation()
        log.append(contentsOf: [
            WatchScoreAction(actionType: .scoreAdd, description: "point", team1Score: 1, team2Score: 0),
            WatchScoreAction(actionType: .setEnd, description: "set_completed", team1Score: 1, team2Score: 0),
            WatchScoreAction(actionType: .gameEnd, description: "game_end", team1Score: 1, team2Score: 0)
        ])

        XCTAssertTrue(log.undo(at: start.addingTimeInterval(2), team1Score: 0, team2Score: 0))
        XCTAssertEqual(log.actions.map(\.actionType), [.gameStart, .undo])
        XCTAssertEqual(log.scoreChangeCount, 0)
    }

    func testRemoteActionTimelineReplacesActionsRemovedByUndoOrReset() {
        let start = Date(timeIntervalSince1970: 1_000)
        var log = WatchScoreActionLog(startedAt: start)
        log.beginUndoableMutation()
        log.append(contentsOf: [
            WatchScoreAction(
                actionType: .scoreAdd,
                description: "point",
                team1Score: 1,
                team2Score: 0,
                scoreChange: 1,
                operationCode: "point"
            )
        ])

        let replacement = DetailedScoreAction(
            type: .matchStarted,
            epochMilliseconds: 2_000,
            scores: [0, 0],
            operationCode: "game_start"
        )
        log.merge(detailedActions: [replacement])

        XCTAssertEqual(log.detailedActions.map(\.id), [replacement.id])
        XCTAssertEqual(log.detailedActions.map(\.type), [.matchStarted])
        XCTAssertEqual(log.detailedActions.map(\.scores), [[0, 0]])
        XCTAssertEqual(log.detailedActions.map(\.operationCode), ["game_start"])
        XCTAssertEqual(log.scoreChangeCount, 0)
        XCTAssertFalse(log.undo(team1Score: 0, team2Score: 0))
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
        let actions = WatchScoreActionProjector.tennis(
            intent: .pointWon(.left),
            events: [
                .pointScored(side: .left, left: 10, right: 8),
                .matchFinished(winner: .left)
            ],
            state: state,
            timestamp: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(actions.map(\.team1Score), [10, 10])
        XCTAssertTrue(actions.allSatisfy { $0.team1SetScore == nil && $0.team2SetScore == nil })
        XCTAssertTrue(actions.allSatisfy { $0.gameNumber == nil })

        var legacyLog = WatchScoreActionLog(startedAt: Date(timeIntervalSince1970: 900))
        legacyLog.append(contentsOf: [
            WatchScoreAction(
                actionType: .gameEnd,
                description: "game_end",
                team1Score: 10,
                team2Score: 8,
                team1SetScore: 0,
                team2SetScore: 0,
                gameNumber: 1
            )
        ])
        legacyLog.omitSecondaryScores()
        XCTAssertTrue(legacyLog.actions.allSatisfy {
            $0.team1SetScore == nil && $0.team2SetScore == nil && $0.gameNumber == nil
        })
    }

    func testRallyProjectionKeepsScoreSetAndFinishOrder() {
        var state = RallyMatchEngine.initial(
            leftName: "红A/红B",
            rightName: "蓝A/蓝B",
            rules: .badminton(maxSets: 1)
        )
        state.leftSets = 1
        state.finished = true
        let actions = WatchScoreActionProjector.rally(
            intent: .pointWon(.left),
            events: [
                .pointScored(side: .left, leftPoints: 21, rightPoints: 19),
                .setCompleted(winner: .left, setNumber: 1, leftPoints: 21, rightPoints: 19, leftSets: 1, rightSets: 0),
                .matchFinished(winner: .left)
            ],
            state: state,
            timestamp: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(actions.map(\.actionType), [.scoreAdd, .setEnd, .gameEnd])
        XCTAssertEqual(actions.first?.team, .team1)
        XCTAssertEqual(actions[1].setNumber, 1)
    }

    func testSpecializedProjectorsKeepMissFoulAndParticipantIdentity() {
        let archery = WatchScoreActionProjector.archery(
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
            intent: .chaseEvent(player: 2, kind: .foul),
            at: 1
        )
        let nineBall = WatchScoreActionProjector.nineBall(
            events: result.events,
            state: result.state,
            timestamp: Date()
        )
        XCTAssertEqual(nineBall.first?.actionType, .foul)
        XCTAssertEqual(nineBall.first?.roundNumber, 3)
        XCTAssertEqual(nineBall.first?.participants?[2].name, "丙")
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
