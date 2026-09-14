import XCTest
import SwiftUI
import ScoreCore
@testable import jifen

@MainActor
final class ScoreboardDisplayTests: XCTestCase {
    func testMatchClockRebindPreservesElapsedOriginAndOnlyPublishesUserChanges() {
        let originalStart = Date(timeIntervalSince1970: 1_000)
        let resumedStart = Date(timeIntervalSince1970: 900)
        let clock = ScoreboardMatchClockSession(isVisible: false, startedAt: originalStart)
        var visibilityChanges: [Bool] = []

        clock.bind(startedAt: resumedStart, isVisible: true) { visibilityChanges.append($0) }

        XCTAssertEqual(clock.startedAt, resumedStart)
        XCTAssertTrue(clock.isVisible)
        XCTAssertEqual(clock.elapsed(at: Date(timeIntervalSince1970: 960)), 60)
        XCTAssertTrue(visibilityChanges.isEmpty, "Binding restored state is not a user toggle")

        clock.isVisible = false
        XCTAssertEqual(visibilityChanges, [false])
        clock.reset(startedAt: originalStart)
        XCTAssertEqual(clock.elapsed(at: Date(timeIntervalSince1970: 1_015)), 15)
    }

    func testCompactSnapshotBuildsVersionedTwoSideDisplay() throws {
        let compact = LocalScoreboardDisplayState(
            gameID: "badminton",
            title: "Badminton",
            leftName: "A",
            rightName: "B",
            leftScore: "20",
            rightScore: "18",
            leftDetail: "1 set",
            rightDetail: "0 sets",
            themeID: "default",
            fontID: "sports",
            finished: false,
            revision: 9
        )

        let state = ScoreboardDisplayState(compactState: compact)
        XCTAssertEqual(state.schemaVersion, 1)
        XCTAssertEqual(state.layoutKind, .twoSide)
        XCTAssertEqual(state.teams.map(\.score), [20, 18])
        XCTAssertEqual(state.displayScore(forVisualIndex: 0), "20")
        XCTAssertEqual(state.detail(forVisualIndex: 0), "1 set")

        let decoded = try JSONDecoder().decode(
            ScoreboardDisplayState.self,
            from: JSONEncoder().encode(state)
        )
        XCTAssertEqual(decoded, state)
    }

    func testLayoutResolverCoversAllExternalTemplates() {
        XCTAssertEqual(ScoreboardDisplayLayoutKind.resolve(gameID: "football"), .twoSide)
        XCTAssertEqual(ScoreboardDisplayLayoutKind.resolve(gameID: "tennis_doubles"), .doublesCourt)
        XCTAssertEqual(ScoreboardDisplayLayoutKind.resolve(gameID: "uno"), .multiGrid)
        XCTAssertEqual(ScoreboardDisplayLayoutKind.resolve(gameID: "doudizhu"), .boardCard)
        XCTAssertEqual(ScoreboardDisplayLayoutKind.resolve(gameID: "xiangqi"), .boardCard)
        XCTAssertEqual(ScoreboardDisplayLayoutKind.resolve(gameID: "counter"), .trainingCounter)
        XCTAssertEqual(ScoreboardDisplayLayoutKind.resolve(gameID: "nine_ball", playerCount: 4), .multiGrid)
    }

    func testAllThirtyThreeExactScoreboardTypesBuildRoundTripAndPublish() throws {
        let exactTypes = ScoreCore.GameType.allCases
        XCTAssertEqual(exactTypes.count, 33)
        XCTAssertEqual(Set(exactTypes.map(\.rawValue)), expectedExactGameIDs)

        let outputs = ScoreboardDisplayOutputs.shared
        for (index, gameType) in exactTypes.enumerated() {
            let initial = fixture(gameID: gameType.rawValue, score: index)
            XCTAssertEqual(initial.gameType, gameType.rawValue)
            XCTAssertEqual(initial.layoutKind, expectedLayout(for: gameType))

            let decoded = try JSONDecoder().decode(
                ScoreboardDisplayState.self,
                from: JSONEncoder().encode(initial)
            )
            XCTAssertEqual(decoded, initial, "Display snapshot did not round-trip for \(gameType.rawValue)")

            let ownerID = "coverage-\(gameType.rawValue)"
            let leaseID = outputs.bind(ownerID: ownerID, initial: initial)
            var updated = initial
            updated.teams[0].score += 1
            updated.updatedAt += 1
            outputs.publish(ownerID: ownerID, leaseID: leaseID, state: updated, priority: .urgent)

            XCTAssertEqual(outputs.displayState, updated, "Display output did not publish \(gameType.rawValue)")
            XCTAssertEqual(outputs.presentationMode, .live)
            outputs.release(ownerID: ownerID, leaseID: leaseID)
        }
        XCTAssertNil(outputs.displayState)
        XCTAssertEqual(outputs.presentationMode, .waiting)
    }

    func testRendererDispatchesAllSevenTemplates() {
        XCTAssertEqual(ScoreboardExternalTemplate.resolve(state: fixture(gameID: "football", score: 1)), .twoSide)

        var doubles = fixture(gameID: "tennis_doubles", score: 1)
        doubles.layoutKind = .doublesCourt
        XCTAssertEqual(ScoreboardExternalTemplate.resolve(state: doubles), .doublesCourt)

        var grid = fixture(gameID: "uno", score: 1)
        grid.layoutKind = .multiGrid
        XCTAssertEqual(ScoreboardExternalTemplate.resolve(state: grid), .multiGrid)

        var twoTeamCard = fixture(gameID: "guandan", score: 1)
        twoTeamCard.layoutKind = .boardCard
        XCTAssertEqual(ScoreboardExternalTemplate.resolve(state: twoTeamCard), .cardTwoTeam)

        var threePlayerCard = fixture(gameID: "doudizhu", score: 1)
        threePlayerCard.layoutKind = .boardCard
        XCTAssertEqual(ScoreboardExternalTemplate.resolve(state: threePlayerCard), .cardThreePlayer)

        var twoSeatClock = fixture(gameID: "chess", score: 1)
        twoSeatClock.layoutKind = .boardCard
        XCTAssertEqual(ScoreboardExternalTemplate.resolve(state: twoSeatClock), .cardTwoSeat)

        var training = fixture(gameID: "counter", score: 1)
        training.layoutKind = .trainingCounter
        XCTAssertEqual(ScoreboardExternalTemplate.resolve(state: training), .trainingCounter)
    }

    func testClockAndOfficialBreakProjectLocally() {
        let countingUp = ScoreboardDisplayClock(
            elapsedMilliseconds: 15_000,
            isRunning: true,
            anchorWallClockMilliseconds: 100_000
        )
        XCTAssertEqual(countingUp.projectedMilliseconds(atWallClockMilliseconds: 104_500), 19_500)

        let countingDown = ScoreboardDisplayClock(
            elapsedMilliseconds: 8_000,
            isRunning: true,
            countsDown: true,
            anchorWallClockMilliseconds: 100_000
        )
        XCTAssertEqual(countingDown.projectedMilliseconds(atWallClockMilliseconds: 103_000), 5_000)
        XCTAssertEqual(countingDown.projectedMilliseconds(atWallClockMilliseconds: 120_000), 0)

        let rest = ScoreboardDisplayRest(
            kind: "technical",
            phase: "active",
            remainingSeconds: 60,
            isRunning: true,
            updatedWallClockMilliseconds: 100_000
        )
        XCTAssertEqual(rest.projectedRemainingSeconds(atWallClockMilliseconds: 112_900), 48)
        XCTAssertEqual(rest.projectedRemainingSeconds(atWallClockMilliseconds: 170_000), 0)
    }

    func testProjectionTypographyStaysStableAcrossRacketScoreDigits() {
        let viewport = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(DisplayTypographyResolver.tennisMainScoreWidth(fontSize: 180), 320.4, accuracy: 0.01)
        let sharedSecondaryScale = DisplayTypographyResolver.secondaryScoreScale(for: viewport)
        for gameType in [
            "pingpong", "pingpong_doubles", "badminton", "badminton_doubles",
            "tennis", "tennis_doubles", "pickleball", "pickleball_doubles"
        ] {
            XCTAssertEqual(
                DisplayTypographyResolver.secondaryScoreScale(for: viewport, gameType: gameType),
                sharedSecondaryScale,
                "\(gameType) should share volleyball's projection set-score scale"
            )
        }
        XCTAssertGreaterThan(sharedSecondaryScale, 1)
        XCTAssertEqual(
            DisplayTypographyResolver.secondaryScoreScale(for: viewport, gameType: "volleyball"),
            sharedSecondaryScale
        )
        let singlesNameSize = 40
            * DisplayTypographyResolver.chromeScale(for: viewport)
            * DisplayTypographyResolver.singlesNameScale(for: viewport)
        let doublesTokens = DisplayTypographyResolver.doublesTokens(
            width: viewport.width,
            height: viewport.height,
            tennisDoubles: false
        )
        let doublesNameSize = min(
            80,
            doublesTokens.name * DisplayTypographyResolver.doublesNameScale(for: viewport)
        )
        XCTAssertEqual(singlesNameSize, doublesNameSize, accuracy: 0.5)
    }

    func testTableTennisAdministrativeCardsStayAboveServeAndKeyPointIndicators() {
        let ordinary = ScoreboardServeGeometry.tableTennisCardsCenterY(
            height: 800,
            keyPointVisible: false
        )
        let keyPoint = ScoreboardServeGeometry.tableTennisCardsCenterY(
            height: 800,
            keyPointVisible: true
        )
        XCTAssertLessThan(ordinary, 400)
        XCTAssertLessThan(keyPoint, ordinary)
    }

    func testProjectionServeIndicatorOnlyExpandsOnTelevision() {
        XCTAssertEqual(DisplayServeIndicatorSizing.singles(baseSize: 10, projection: .localProjection), 36)
        XCTAssertEqual(DisplayServeIndicatorSizing.singles(baseSize: 100, projection: .localProjection), 84)
        XCTAssertEqual(DisplayServeIndicatorSizing.singles(baseSize: 10, projection: .synchronizedDisplay), 36)
        XCTAssertEqual(DisplayServeIndicatorSizing.singles(baseSize: 100, projection: .synchronizedDisplay), 64)
        XCTAssertEqual(DisplayServeIndicatorSizing.doubles(
            scoreFontSize: 10,
            tennisDoubles: false,
            projection: .localProjection
        ), 30)
        XCTAssertEqual(DisplayServeIndicatorSizing.doubles(
            scoreFontSize: 300,
            tennisDoubles: false,
            projection: .localProjection
        ), 64)
        XCTAssertEqual(DisplayServeIndicatorSizing.doubles(
            scoreFontSize: 100,
            tennisDoubles: true,
            projection: .synchronizedDisplay
        ), 36)
    }

    func testEveryDisplayProjectionHidesOnlyTransientCompletedGameOrdinal() {
        XCTAssertTrue(ExternalTennisScoreProjection.hidesTransientCompletedGameOrdinal(
            rawScore: 4, isTieBreak: false, isDeuce: false, isLocalProjection: true
        ))
        XCTAssertFalse(ExternalTennisScoreProjection.hidesTransientCompletedGameOrdinal(
            rawScore: 4, isTieBreak: true, isDeuce: false, isLocalProjection: true
        ))
        XCTAssertFalse(ExternalTennisScoreProjection.hidesTransientCompletedGameOrdinal(
            rawScore: 4, isTieBreak: false, isDeuce: true, isLocalProjection: true
        ))
        XCTAssertTrue(ExternalTennisScoreProjection.hidesTransientCompletedGameOrdinal(
            rawScore: 4, isTieBreak: false, isDeuce: false, isLocalProjection: false
        ))
    }

    func testEnrichedStatePreservesExplicitSourceOrientation() {
        let compact = compactFixture(
            gameID: ScoreCore.GameType.uno.rawValue,
            leftName: "A",
            rightName: "B",
            leftScore: "0",
            rightScore: "0",
            revision: 1
        )
        let portrait = ScoreboardDisplayState.enriched(
            compact: compact,
            layoutKind: .multiGrid,
            orientation: .portrait
        )
        XCTAssertEqual(portrait.orientation, .portrait)
    }

    func testBasketballAndFootballClocksKeepTheirDistinctSemantics() {
        let basketball = ScoreboardDisplayClock(
            elapsedMilliseconds: 90_000,
            isRunning: true,
            countsDown: true,
            durationMilliseconds: 10 * 60 * 1_000,
            anchorWallClockMilliseconds: 100_000,
            label: "Q4"
        )
        XCTAssertEqual(basketball.projectedMilliseconds(atWallClockMilliseconds: 112_000), 78_000)
        XCTAssertEqual(basketball.label, "Q4")
        XCTAssertTrue(basketball.visible)
        var basketballState = fixture(gameID: ScoreCore.GameType.basketball.rawValue, score: 88)
        basketballState.clock = basketball
        basketballState.sportState?["shotClock"] = .integer(12)
        XCTAssertTrue(basketballState.clock?.countsDown == true)
        XCTAssertEqual(basketballState.sportInt("shotClock"), 12)

        let football = ScoreboardDisplayClock(
            elapsedMilliseconds: 45 * 60 * 1_000,
            isRunning: true,
            countsDown: false,
            anchorWallClockMilliseconds: 100_000,
            label: "加时赛"
        )
        XCTAssertEqual(
            football.projectedMilliseconds(atWallClockMilliseconds: 112_000),
            45 * 60 * 1_000 + 12_000
        )
        XCTAssertEqual(football.label, "加时赛")
        var footballState = fixture(gameID: ScoreCore.GameType.football.rawValue, score: 1)
        footballState.clock = football
        footballState.sportState?["clockStage"] = .integer(3)
        XCTAssertFalse(footballState.clock?.countsDown ?? true)
        XCTAssertEqual(footballState.sportInt("clockStage"), 3)

        var hiddenMatchTime = football
        hiddenMatchTime.visible = false
        XCTAssertFalse(hiddenMatchTime.visible)
        XCTAssertEqual(hiddenMatchTime.projectedMilliseconds(atWallClockMilliseconds: 112_000), 45 * 60 * 1_000 + 12_000)
    }

    func testCoordinatorPublishesGenericMatchClockAndVisibilityWithoutReplacingSportClock() async {
        let coordinator = LocalScoreboardSyncCoordinator.shared
        let outputs = ScoreboardDisplayOutputs.shared
        let ownerID = "generic-match-clock-test"
        let startedAt = Date(timeIntervalSince1970: 123_456)
        let session = ScoreboardMatchClockSession(isVisible: false, startedAt: startedAt)

        coordinator.registerGenericMatchClock(ownerID: ownerID) {
            session.externalDisplayClock
        }
        coordinator.registerHost(
            snapshot: {
                self.compactFixture(
                    gameID: ScoreCore.GameType.volleyball.rawValue,
                    leftName: "A",
                    rightName: "B",
                    leftScore: "1",
                    rightScore: "0",
                    revision: 0
                )
            },
            handleIntent: { _ in }
        )
        defer {
            coordinator.unregisterHost()
            coordinator.unregisterGenericMatchClock(ownerID: ownerID)
        }

        XCTAssertEqual(outputs.displayState?.clock?.elapsedMilliseconds, 0)
        XCTAssertEqual(outputs.displayState?.clock?.isRunning, true)
        XCTAssertEqual(outputs.displayState?.clock?.countsDown, false)
        XCTAssertEqual(outputs.displayState?.clock?.visible, false)
        XCTAssertEqual(outputs.displayState?.clock?.anchorWallClockMilliseconds, 123_456_000)

        session.isVisible = true
        coordinator.publishSnapshot()
        await Task.yield()
        XCTAssertEqual(outputs.displayState?.clock?.visible, true)

        let sportClock = ScoreboardDisplayClock(
            elapsedMilliseconds: 30_000,
            isRunning: true,
            countsDown: true,
            anchorWallClockMilliseconds: 200_000,
            label: "Q1"
        )
        coordinator.registerHost(
            snapshot: {
                var compact = self.compactFixture(
                    gameID: ScoreCore.GameType.basketball.rawValue,
                    leftName: "A",
                    rightName: "B",
                    leftScore: "8",
                    rightScore: "6",
                    revision: 0
                )
                var external = ScoreboardDisplayState(compactState: compact)
                external.clock = sportClock
                compact.externalState = external
                return compact
            },
            handleIntent: { _ in }
        )
        XCTAssertEqual(outputs.displayState?.clock, sportClock)
    }

    func testSideExchangePublishesStableLogicalTeamsAndVisualOverrides() {
        let outputs = ScoreboardDisplayOutputs.shared
        let initial = fixture(
            gameID: ScoreCore.GameType.badminton.rawValue,
            leftName: "Red",
            rightName: "Blue",
            leftScore: "11",
            rightScore: "8",
            revision: 1
        )
        let leaseID = outputs.bind(ownerID: "side-exchange", initial: initial)

        let swappedCompact = compactFixture(
            gameID: ScoreCore.GameType.badminton.rawValue,
            leftName: "Blue",
            rightName: "Red",
            leftScore: "8",
            rightScore: "11",
            revision: 2
        )
        let swapped = ScoreboardDisplayState.enriched(
            compact: swappedCompact,
            layoutKind: .twoSide,
            sportState: ["team0ScreenSide": .string("right")]
        )
        outputs.publish(
            ownerID: "side-exchange",
            leaseID: leaseID,
            state: swapped,
            priority: .urgent
        )

        XCTAssertEqual(outputs.displayState?.teams.map(\.id), ["team_0", "team_1"])
        XCTAssertEqual(outputs.displayState?.teams.map(\.name), ["Red", "Blue"])
        XCTAssertEqual(outputs.displayState?.teams.map(\.score), [11, 8])
        XCTAssertEqual(outputs.displayState?.displayScore(forVisualIndex: 0), "8")
        XCTAssertEqual(outputs.displayState?.displayScore(forVisualIndex: 1), "11")
        XCTAssertEqual(outputs.displayState?.sportString("team0ScreenSide"), "right")
        outputs.release(ownerID: "side-exchange", leaseID: leaseID)
    }

    func testSwappedEnrichedStateNormalizesPlayersResultAndWireIdentity() throws {
        let compact = LocalScoreboardDisplayState(
            gameID: ScoreCore.GameType.badmintonDoubles.rawValue,
            title: "Badminton Doubles",
            leftName: "Blue",
            rightName: "Red",
            leftScore: "8",
            rightScore: "11",
            leftDetail: nil,
            rightDetail: nil,
            themeID: "default",
            fontID: "default",
            finished: true,
            keyPoint: LocalScoreboardKeyPoint(
                status: KeyPointStatus(kind: .match, side: .left),
                sidesSwapped: false
            ),
            revision: 3,
            leftSets: 0,
            rightSets: 2
        )
        let state = ScoreboardDisplayState.enriched(
            compact: compact,
            layoutKind: .doublesCourt,
            players: [
                .init(id: "left_top", name: "Blue A", teamID: "team_0", slot: "top", order: 0),
                .init(id: "right_top", name: "Red A", teamID: "team_1", slot: "top", order: 1)
            ],
            sportState: ["team0ScreenSide": .string("right")]
        )

        XCTAssertEqual(state.teams.map(\.name), ["Red", "Blue"])
        XCTAssertEqual(state.teams.map(\.sets), [2, 0])
        XCTAssertEqual(state.players?.map(\.teamID), ["team_1", "team_0"])
        XCTAssertEqual(state.result?.winnerID, "team_0")
        XCTAssertEqual(state.result?.finalScores?["team_0"]?.score, 11)
        XCTAssertEqual(state.result?.finalScores?["team_1"]?.score, 8)
        XCTAssertEqual(state.result?.finalScores?["team_0"]?.sets, 2)
        XCTAssertEqual(state.result?.finalScores?["team_1"]?.sets, 0)
        XCTAssertEqual(state.keyPoint?.side, "left", "Key-point side is already a visual side")

        let wire = try XCTUnwrap(DisplayStateWireCodec.encode(state))
        let wireTeams = try XCTUnwrap(wire["teams"] as? [[String: Any]])
        XCTAssertEqual(wireTeams.map { $0["id"] as? String }, ["team_0", "team_1"])
        XCTAssertEqual(wireTeams.map { $0["name"] as? String }, ["Red", "Blue"])
    }

    func testFinishedCompactSnapshotUsesMatchHierarchyForWinnerAndResultCard() throws {
        let compact = LocalScoreboardDisplayState(
            gameID: ScoreCore.GameType.badminton.rawValue,
            title: "",
            leftName: "A",
            rightName: "B",
            leftScore: "0",
            rightScore: "0",
            themeID: "default",
            fontID: "default",
            finished: true,
            revision: 1,
            leftSets: 3,
            rightSets: 1
        )

        let state = ScoreboardDisplayState(compactState: compact)

        XCTAssertEqual(state.result?.winnerID, "team_0")
        XCTAssertEqual(state.result?.finalScores?["team_0"]?.sets, 3)
        XCTAssertEqual(state.result?.finalScores?["team_1"]?.sets, 1)
        XCTAssertEqual(
            ScoreboardExternalResultScorePresentation.score(
                forTeamID: "team_0",
                visualIndex: 0,
                state: state
            ),
            "3"
        )
        XCTAssertEqual(
            ScoreboardExternalResultScorePresentation.score(
                forTeamID: "team_1",
                visualIndex: 1,
                state: state
            ),
            "1"
        )
        let wire = try XCTUnwrap(DisplayStateWireCodec.encode(state))
        let decoded = try XCTUnwrap(DisplayStateWireCodec.decode(wire))
        XCTAssertEqual(decoded.sportString("resultScoreLevel"), "sets")
        XCTAssertEqual(decoded.result?.finalScores?["team_0"]?.sets, 3)
    }

    func testFinishedResultScoreLevelCanKeepOneSetMatchPointScore() throws {
        var compact = LocalScoreboardDisplayState(
            gameID: ScoreCore.GameType.pingpong.rawValue,
            title: "",
            leftName: "A",
            rightName: "B",
            leftScore: "11",
            rightScore: "7",
            themeID: "default",
            fontID: "default",
            finished: true,
            revision: 1,
            leftSets: 1,
            rightSets: 0
        )
        compact.externalState = ScoreboardDisplayState.enriched(
            compact: compact,
            layoutKind: .twoSide,
            sportState: ["resultScoreLevel": .string("score")]
        )
        let state = try XCTUnwrap(compact.externalState)

        XCTAssertEqual(
            ScoreboardExternalResultScorePresentation.score(
                forTeamID: "team_0",
                visualIndex: 0,
                state: state
            ),
            "11"
        )
        XCTAssertEqual(
            ScoreboardExternalResultScorePresentation.score(
                forTeamID: "team_1",
                visualIndex: 1,
                state: state
            ),
            "7"
        )
    }

    func testTableTennisAdministrativeMarkerCountIsBoundedForRemotePayloads() {
        XCTAssertEqual(TableTennisAdministrativeMarkerPolicy.displayedRedCardCount(-1), 0)
        XCTAssertEqual(TableTennisAdministrativeMarkerPolicy.displayedRedCardCount(1), 1)
        XCTAssertEqual(TableTennisAdministrativeMarkerPolicy.displayedRedCardCount(200), 2)
    }

    func testConcurrentPurchaseCallersAwaitOneAuthoritativeTransactionTask() async throws {
        let gate = PurchaseTransactionGate()
        let counter = PurchaseGateInvocationCounter()

        let first = Task { @MainActor in
            try await gate.perform(transactionID: 42) {
                counter.value += 1
                try await Task.sleep(for: .milliseconds(80))
            }
        }
        try await Task.sleep(for: .milliseconds(10))
        let second = Task { @MainActor in
            try await gate.perform(transactionID: 42) {
                counter.value += 1
            }
        }

        try await first.value
        try await second.value
        XCTAssertEqual(counter.value, 1)
    }

    func testFinishedSnapshotPublishesUrgentlyWithFinalScores() {
        let outputs = ScoreboardDisplayOutputs.shared
        let live = fixture(gameID: ScoreCore.GameType.football.rawValue, score: 2)
        let leaseID = outputs.bind(ownerID: "finished", initial: live)
        var finished = live
        finished.result = ScoreboardDisplayResult(
            ended: true,
            manualEnd: false,
            winnerID: "team_0",
            finalScores: [
                "team_0": .init(score: 2),
                "team_1": .init(score: 1)
            ]
        )
        finished.updatedAt += 1

        outputs.finish(ownerID: "finished", leaseID: leaseID, state: finished)

        XCTAssertEqual(outputs.presentationMode, .finished)
        XCTAssertEqual(outputs.displayState?.result?.winnerID, "team_0")
        XCTAssertEqual(outputs.displayState?.result?.finalScores?["team_0"]?.score, 2)
        outputs.release(ownerID: "finished", leaseID: leaseID)
    }

    func testCompleteDisplayStateRoundTripPreservesSpecializedData() throws {
        var state = fixture(gameID: "basketball", score: 88)
        state.matchTitle = "Final"
        state.players = [
            .init(id: "p1", name: "A1", teamID: "team_0", slot: "top", order: 0, isServer: true)
        ]
        state.sportState = [
            "period": .string("Q4"),
            "leftFouls": .integer(4),
            "shotClockRunning": .boolean(true),
            "roundScores": .integers([22, 19, 25, 22])
        ]
        state.keyPoint = .init(kind: "match", side: "left")
        state.clock = .init(
            elapsedMilliseconds: 95_000,
            isRunning: true,
            countsDown: true,
            anchorWallClockMilliseconds: 123_000,
            label: "Q4"
        )
        state.rest = .init(
            kind: "timeout",
            phase: "active",
            remainingSeconds: 30,
            isRunning: true,
            updatedWallClockMilliseconds: 123_000
        )
        state.result = .init(
            ended: true,
            winnerID: "team_0",
            finalScores: ["team_0": .init(score: 88), "team_1": .init(score: 81)]
        )

        let decoded = try JSONDecoder().decode(
            ScoreboardDisplayState.self,
            from: JSONEncoder().encode(state)
        )
        XCTAssertEqual(decoded, state)
    }

    func testOldCompactPayloadDecodesWithoutExternalState() throws {
        let json = #"{"gameID":"football","title":"Football","leftName":"A","rightName":"B","leftScore":"1","rightScore":"0","themeID":"default","fontID":"default","finished":false,"revision":2}"#
        let compact = try JSONDecoder().decode(LocalScoreboardDisplayState.self, from: Data(json.utf8))
        XCTAssertNil(compact.externalState)
    }

    /// 对齐安卓 toProtocolTennisPointScore：网球家族常规局显示串转协议序数，
    /// 抢七整数字符串透传，非网球项目不受影响。
    func testTennisFamilyCompactScoreUsesProtocolOrdinals() {
        func teamScore(_ gameID: String, _ display: String) -> Int {
            ScoreboardDisplayState(compactState: compactFixture(
                gameID: gameID,
                leftName: "A",
                rightName: "B",
                leftScore: display,
                rightScore: "0",
                revision: 1
            )).teams[0].score
        }
        XCTAssertEqual(teamScore("tennis", "0"), 0)
        XCTAssertEqual(teamScore("tennis", "15"), 1)
        XCTAssertEqual(teamScore("tennis", "30"), 2)
        XCTAssertEqual(teamScore("tennis", "40"), 3)
        XCTAssertEqual(teamScore("tennis", "AD"), 4)
        XCTAssertEqual(teamScore("tennis", "7"), 7, "抢七实际分数应原样透传")
        XCTAssertEqual(teamScore("tennis_doubles", "30"), 2)
        XCTAssertEqual(teamScore("soft_tennis", "15"), 1, "软式网球 wire 用原始步进值")
        XCTAssertEqual(teamScore("padel", "AD"), 4)
        XCTAssertEqual(teamScore("football", "15"), 15, "非网球家族不转换")
    }

    /// 未设置比赛抬头时 wire 不携带 matchTitle（对齐安卓），设置了才透传。
    func testWireEncodeOmitsMatchTitleWhenUserTitleUnset() {
        func encodedTitle(_ compact: LocalScoreboardDisplayState) -> String? {
            DisplayStateWireCodec.encode(ScoreboardDisplayState(compactState: compact))?["matchTitle"] as? String
        }
        XCTAssertNil(encodedTitle(compactFixture(
            gameID: "snooker",
            leftName: "A",
            rightName: "B",
            leftScore: "0",
            rightScore: "0",
            revision: 1
        )), "未设置抬头不应传出 matchTitle")
        XCTAssertEqual(encodedTitle(compactFixture(
            gameID: "snooker",
            leftName: "A",
            rightName: "B",
            leftScore: "0",
            rightScore: "0",
            revision: 1,
            title: "决赛"
        )), "决赛")
    }

    func testOutputLeaseRejectsStalePageUpdatesAndRelease() {
        let first = fixture(gameID: "football", score: 1)
        let second = fixture(gameID: "basketball", score: 2)
        let stale = fixture(gameID: "football", score: 99)
        let outputs = ScoreboardDisplayOutputs.shared

        let firstLease = outputs.bind(ownerID: "first", initial: first)
        let secondLease = outputs.bind(ownerID: "second", initial: second)
        outputs.publish(ownerID: "first", leaseID: firstLease, state: stale, priority: .urgent)
        outputs.release(ownerID: "first", leaseID: firstLease)

        XCTAssertEqual(outputs.displayState?.gameType, "basketball")
        XCTAssertEqual(outputs.displayState?.teams.first?.score, 2)
        outputs.release(ownerID: "second", leaseID: secondLease)
        XCTAssertNil(outputs.displayState)
        XCTAssertEqual(outputs.presentationMode, .waiting)
    }

    /// Panel layout inspection only: direct UI state bypasses the currently disconnected element taps.
    /// Keep each panel in a separate test process budget so a cold simulator does not have to retain
    /// 112 full-screen screenshot attachments in a single XCTest method.
    func testAuditStyleBackgroundPanelSnapshots() throws {
        try auditStylePanelSnapshots(panelName: "background", panel: .background)
    }

    func testAuditStyleThemePanelSnapshots() throws {
        try auditStylePanelSnapshots(panelName: "theme", panel: .theme)
    }

    func testAuditStyleFontPanelSnapshots() throws {
        try auditStylePanelSnapshots(panelName: "font", panel: .font)
    }

    func testAuditStyleElementPanelSnapshots() throws {
        try auditStylePanelSnapshots(panelName: "element", panel: .element)
    }

    private func auditStylePanelSnapshots(
        panelName: String,
        panel: ScoreboardStyleEditPanel
    ) throws {
        executionTimeAllowance = 60
        let hintKey = "scoreboard_style_edit_usage_hint_v1_shown"
        let previousHint = UserDefaults.standard.object(forKey: hintKey)
        UserDefaults.standard.set("true", forKey: hintKey)
        defer {
            if let previousHint { UserDefaults.standard.set(previousHint, forKey: hintKey) }
            else { UserDefaults.standard.removeObject(forKey: hintKey) }
        }
        for styleID in ScoreboardStyleV2Registry.enabledStyleIDs.sorted(by: { $0.rawValue < $1.rawValue }) {
            let typography = ScoreboardTypographySession(styleID: styleID)
            let controller = ScoreboardStyleEditorController(styleID: styleID,
                capabilities: ScoreboardStyleV2Registry.capabilities(for: styleID))
            controller.open(typographySession: typography)
            let attachment: XCTAttachment = autoreleasepool {
                let ui = ScoreboardStyleEditorUiState()
                if panel == .element { ui.openElement(.mainScore, slot: .sideLeft) }
                else { ui.openPanel(panel) }
                let size = CGSize(width: 852, height: 393)
                let content = ZStack {
                    Color.gray
                    ScoreboardStyleEditOverlayView(controller: controller, typographySession: typography,
                        uiState: ui, onCancel: {})
                }.frame(width: size.width, height: size.height)
                // ScrollView content needs a hosted UIKit hierarchy; ImageRenderer omits it.
                let window = UIWindow(frame: CGRect(origin: .zero, size: size))
                let hosting = UIHostingController(rootView: content)
                hosting.view.frame = window.bounds
                window.addSubview(hosting.view)
                hosting.view.layoutIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                let image = UIGraphicsImageRenderer(size: size).image { _ in
                    hosting.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                hosting.view.removeFromSuperview()
                return XCTAttachment(
                    data: image.pngData() ?? Data(),
                    uniformTypeIdentifier: "public.png"
                )
            }
            attachment.name = "panel_\(styleID.rawValue)_\(panelName)"
            attachment.lifetime = .keepAlways
            add(attachment)
            controller.cancel()
        }
    }

    /// Records actual wire output for independent Android/HarmonyOS contract validation.
    func testAuditWireProtocolEvidence() throws {
        var state = fixture(gameID: "badminton_doubles", score: 8)
        state.appearance.fontSizeMultipliers = ["mainScore": 1.5, "playerName": 1.5]
        state.appearance.leftScoreHex = "#FF0000"
        state.appearance.rightScoreHex = "#00FF00"
        state.rest = ScoreboardDisplayRest(kind: "game_break", phase: "countdown",
            remainingSeconds: 60, isRunning: true, updatedWallClockMilliseconds: 100_000)
        let wire = try XCTUnwrap(DisplayStateWireCodec.encode(state, atWallClockMilliseconds: 100_000))
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: wire, options: [.prettyPrinted, .sortedKeys]),
            uniformTypeIdentifier: "public.json")
        attachment.name = "audit-ios-outgoing-wire"
        attachment.lifetime = .keepAlways
        add(attachment)
        var incoming = wire
        incoming["appearance"] = ["style": [
            "version": 2, "themeCode": "electronic", "fontCode": "sports",
            "fontSizeMultipliers": ["mainScore": 1.5],
            "panels": [["slotKey": "side_left", "backgroundColor": "#112233"],
                       ["slotKey": "side_right", "backgroundColor": "#223344"]],
            "elements": [["elementKey": "mainScore", "textColors": [
                ["slotKey": "side_left", "color": "#FF0000"],
                ["slotKey": "side_right", "color": "#00FF00"]]]],
            "serverIndicatorColor": "#FF00FF", "styleRevision": 1
        ]]
        let decoded = try XCTUnwrap(DisplayStateWireCodec.decode(incoming))
        let result: [String: Any] = [
            "incoming": incoming,
            "decoded": ["theme": decoded.appearance.theme, "font": decoded.appearance.fontCode,
                        "leftPanel": decoded.appearance.leftPanelHex,
                        "leftMainText": decoded.appearance.leftMainTextHex,
                        "rightMainText": decoded.appearance.rightMainTextHex]
        ]
        let decodeAttachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]),
            uniformTypeIdentifier: "public.json")
        decodeAttachment.name = "audit-ios-incoming-wire"
        decodeAttachment.lifetime = .keepAlways
        add(decodeAttachment)
    }

    func testV2StyleAndOfficialBreakInteroperability() throws {
        var state = fixture(gameID: "badminton_doubles", score: 8)
        state.appearance.style = nil
        state.appearance.fontSizeMultipliers = ["mainScore": 1.5, "playerName": 0.8, "_local": 2]
        state.appearance.leftScoreHex = "#FF0000"
        state.appearance.rightScoreHex = "#00FF00"
        state.appearance.rightSecondaryHex = "#123456"
        state.rest = ScoreboardDisplayRest(kind: "game_break", phase: "countdown", remainingSeconds: 60,
            isRunning: true, updatedWallClockMilliseconds: 100_000, afterAction: "exchange_sides",
            title: "张三 · 暂停")
        let wire = try XCTUnwrap(DisplayStateWireCodec.encode(state, atWallClockMilliseconds: 102_000))
        let appearance = try XCTUnwrap(wire["appearance"] as? [String: Any])
        let style = try XCTUnwrap(appearance["style"] as? [String: Any])
        XCTAssertEqual(style["version"] as? Int, 2)
        XCTAssertNotNil(style["panels"] as? [[String: Any]])
        XCTAssertNotNil(style["elements"] as? [[String: Any]])
        XCTAssertNotNil(style["serverIndicatorColor"] as? String)
        XCTAssertEqual(style["styleRevision"] as? Int, 0)
        XCTAssertNil((style["fontSizeMultipliers"] as? [String: Double])?["_local"])
        let rest = try XCTUnwrap(wire["rest"] as? [String: Any])
        XCTAssertEqual(rest["sport"] as? String, "badminton")
        XCTAssertEqual(rest["remainingMs"] as? Int, 58_000)
        XCTAssertEqual(rest["afterAction"] as? String, "exchange_sides")
        XCTAssertEqual(rest["title"] as? String, "张三 · 暂停")
        let decoded = try XCTUnwrap(DisplayStateWireCodec.decode(wire))
        XCTAssertEqual(decoded.appearance.rightMainTextHex, "#00FF00")
        XCTAssertEqual(decoded.appearance.style?.color("setScore", slot: "side_right"), "#123456")
        XCTAssertEqual(decoded.appearance.fontSizeMultipliers?["mainScore"], 1.5)
        XCTAssertEqual(decoded.rest?.remainingSeconds, 58)
        XCTAssertEqual(decoded.rest?.title, "张三 · 暂停")
        state.rest?.phase = "preparation"
        state.rest?.remainingSeconds = 5
        let prepareWire = try XCTUnwrap(DisplayStateWireCodec.encode(state, atWallClockMilliseconds: 100_000))
        let prepare = try XCTUnwrap(prepareWire["rest"] as? [String: Any])
        XCTAssertEqual(prepare["phase"] as? String, "prepare")
        XCTAssertEqual(prepare["remainingMs"] as? Int, 0)
        XCTAssertEqual(prepare["prepareRemaining"] as? Int, 5)
        XCTAssertEqual(DisplayStateWireCodec.decode(prepareWire)?.rest?.phase, "preparation")
    }

    func testTableTennisAdministrativeFieldsSurviveWhitelistAndSideMapping() throws {
        var state = fixture(gameID: "pingpong", score: 7)
        state.sportState = [
            "team0ScreenSide": .string("right"),
            "servingSide": .string("left"),
            "tableTennisTeam0TimeoutUsed": .boolean(true),
            "tableTennisTeam0Yellow": .boolean(true),
            "tableTennisTeam0RedCount": .integer(2),
            "tableTennisTeam1TimeoutUsed": .boolean(false),
            "tableTennisTeam1Yellow": .boolean(false),
            "tableTennisTeam1RedCount": .integer(0),
            "shouldBeFiltered": .string("no")
        ]
        let wire = try XCTUnwrap(DisplayStateWireCodec.encode(state))
        let sport = try XCTUnwrap(wire["sportState"] as? [String: Any])
        XCTAssertEqual(sport["team0ScreenSide"] as? String, "right")
        XCTAssertEqual(sport["servingSide"] as? String, "left")
        XCTAssertEqual(sport["tableTennisTeam0RedCount"] as? Int, 2)
        XCTAssertNil(sport["shouldBeFiltered"])
        let decoded = try XCTUnwrap(DisplayStateWireCodec.decode(wire))
        XCTAssertEqual(decoded.sportState?["tableTennisTeam0TimeoutUsed"], .boolean(true))
        XCTAssertEqual(decoded.sportInt("tableTennisTeam0RedCount"), 2)
    }

    func testV2ColorsFollowTeamsAfterSideExchange() throws {
        let state = fixture(gameID: "badminton", score: 8)
        let source = try XCTUnwrap(state.appearance.style)
        let projected = source.projected(team0OnRight: true)
        XCTAssertEqual(projected.panelColor(slot: "side_left"), source.panelColor(slot: "side_right"))
        XCTAssertEqual(projected.panelColor(slot: "side_right"), source.panelColor(slot: "side_left"))
        XCTAssertEqual(projected.slot(for: "team_0", fallback: "side_left"), "side_right")
        XCTAssertEqual(projected.renderColor("mainScore", slot: "side_left"), source.renderColor("mainScore", slot: "side_right"))
    }

    func testEightBallHandicapReservesSecondaryRowForBothSides() {
        XCTAssertTrue(ScoreboardExternalSecondaryRowPolicy.shouldShow(
            secondaryText: "+2",
            gameType: "eight_ball",
            eightBallHandicapRacks: 2,
            eightBallHandicapBeneficiary: "team1"
        ))
        XCTAssertTrue(ScoreboardExternalSecondaryRowPolicy.shouldShow(
            secondaryText: "",
            gameType: "eight_ball",
            eightBallHandicapRacks: 2,
            eightBallHandicapBeneficiary: "team1"
        ))
        XCTAssertFalse(ScoreboardExternalSecondaryRowPolicy.shouldShow(
            secondaryText: "",
            gameType: "eight_ball",
            eightBallHandicapRacks: 0,
            eightBallHandicapBeneficiary: "team1"
        ))
        XCTAssertFalse(ScoreboardExternalSecondaryRowPolicy.shouldShow(
            secondaryText: "",
            gameType: "nine_ball",
            eightBallHandicapRacks: 2,
            eightBallHandicapBeneficiary: "team1"
        ))
    }

    func testV2AlphaColorsRetainRGBAOrderAcrossLegacyRendering() throws {
        var state = fixture(gameID: "badminton", score: 8)
        state.appearance.style = nil
        state.appearance.leftScoreHex = "#80112233"
        state.appearance.rightScoreHex = "#CC445566"
        let wire = try XCTUnwrap(DisplayStateWireCodec.encode(state))
        let decoded = try XCTUnwrap(DisplayStateWireCodec.decode(wire))
        XCTAssertEqual(decoded.appearance.style?.color("mainScore", slot: "side_left"), "#11223380")
        XCTAssertEqual(decoded.appearance.leftMainTextHex, "#80112233")
        XCTAssertEqual(decoded.appearance.rightMainTextHex, "#CC445566")
        XCTAssertEqual(ScoreboardDisplayStyle.renderHex("#11223380"), "#80112233")
        XCTAssertEqual(ScoreboardDisplayStyle.wireHex("#80112233"), "#11223380")
    }

    func testFontWireCodesMatchAndroidAndHarmony() throws {
        for (local, wireCode) in [(ScoreboardFont.monospaced, "digital"), (.sports, "teko"), (.sevenSegment, "seven_segment")] {
            var state = fixture(gameID: "tennis", score: 3)
            state.appearance.fontCode = local.rawValue
            let wire = try XCTUnwrap(DisplayStateWireCodec.encode(state))
            let appearance = try XCTUnwrap(wire["appearance"] as? [String: Any])
            let style = try XCTUnwrap(appearance["style"] as? [String: Any])
            XCTAssertEqual(appearance["fontCode"] as? String, wireCode)
            XCTAssertEqual(style["fontCode"] as? String, wireCode)
            XCTAssertEqual(DisplayStateWireCodec.decode(wire)?.appearance.fontCode, local.rawValue)
        }
        XCTAssertEqual(ScoreboardFont(displayCode: "harmony_digit"), .monospaced)
    }

    func testDoublesSecondaryStyleUsesTheSportElementAndMultiplier() throws {
        for game in ["badminton_doubles", "tennis_doubles", "padel"] {
            var state = fixture(gameID: game, score: 3)
            state.teams[0].sets = 2; state.teams[1].sets = 1
            state.teams[0].games = 5; state.teams[1].games = 4
            let key = "setGameScore"
            var style = try XCTUnwrap(state.appearance.style)
            for index in style.elements.indices where style.elements[index].elementKey == key {
                style.elements[index].textColors = [
                    .init(slotKey: "side_left", color: "#FF00FF"),
                    .init(slotKey: "side_right", color: "#FF00FF")
                ]
            }
            state.appearance.style = style
            var counts: [Int] = []
            for multiplier in [0.8, 1.5] {
                // Include every role, as real V2 snapshots do. Unused default roles must
                // not override the active sport's combined or set-score settings.
                state.appearance.fontSizeMultipliers = Dictionary(uniqueKeysWithValues:
                    ScoreboardStyleElementKeyV2.allCases.map { ($0.rawValue, $0.rawValue == key ? multiplier : 1) })
                let wire = try XCTUnwrap(DisplayStateWireCodec.encode(state))
                let decoded = try XCTUnwrap(DisplayStateWireCodec.decode(wire))
                let renderer = ImageRenderer(content: ScoreboardExternalLiveView(state: decoded,
                    projection: .synchronizedDisplay).frame(width: 1194, height: 834))
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.uiImage)
                let cgImage = try XCTUnwrap(image.cgImage)
                var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
                pixels.withUnsafeMutableBytes { buffer in
                    let context = CGContext(data: buffer.baseAddress, width: cgImage.width,
                        height: cgImage.height, bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
                }
                counts.append(stride(from: 0, to: pixels.count, by: 4).filter {
                    pixels[$0] > 200 && pixels[$0 + 1] < 70 && pixels[$0 + 2] > 200
                }.count)
                let attachment = XCTAttachment(image: image)
                attachment.name = "remediation_\(game)_secondary_\(multiplier)x"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            XCTAssertGreaterThan(counts[0], 100, "\(game): selected secondary color was ignored")
            XCTAssertGreaterThan(Double(counts[1]), Double(counts[0]) * 1.2,
                "\(game): selected secondary multiplier was ignored")
        }
    }

    func testTeamCourtPreservesSixPlayersAndLayout() throws {
        var state = fixture(gameID: "shuttlecock", score: 12)
        state.layoutKind = .teamCourt
        let names = ["红 A", "红 B", "红 C", "蓝 A", "蓝 B", "蓝 C"]
        state.sportState = [
            "teamCourtPlayers": .strings(names),
            "team0ScreenSide": .string("right"),
            "servingSide": .string("left")
        ]
        let wire = try XCTUnwrap(DisplayStateWireCodec.encode(state))
        let decoded = try XCTUnwrap(DisplayStateWireCodec.decode(wire))
        XCTAssertEqual(decoded.layoutKind, .teamCourt)
        XCTAssertEqual(ScoreboardExternalTemplate.resolve(state: decoded), .teamCourt)
        XCTAssertEqual(decoded.sportState?["teamCourtPlayers"], .strings(names))
        XCTAssertEqual(decoded.sportString("team0ScreenSide"), "right")
        XCTAssertEqual(decoded.sportString("servingSide"), "left")
        let renderer = ImageRenderer(content: ScoreboardExternalLiveView(state: decoded,
            projection: .synchronizedDisplay).frame(width: 1194, height: 834))
        let attachment = XCTAttachment(image: try XCTUnwrap(renderer.uiImage))
        attachment.name = "remediation_team_court_landscape"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testProjectionRegressionMatrixAt720p1080pAndPhoneLandscape() throws {
        var pingPong = fixture(gameID: "pingpong", score: 10)
        pingPong.keyPoint = .init(kind: "game", side: "left")
        pingPong.sportState = [
            "team0ScreenSide": .string("left"),
            "servingSide": .string("left"),
            "tableTennisTeam0TimeoutUsed": .boolean(true),
            "tableTennisTeam0Yellow": .boolean(true),
            "tableTennisTeam0RedCount": .integer(1),
            "tableTennisTeam1TimeoutUsed": .boolean(false),
            "tableTennisTeam1Yellow": .boolean(true),
            "tableTennisTeam1RedCount": .integer(2)
        ]
        pingPong.rest = .init(
            kind: "timeout",
            phase: "countdown",
            remainingSeconds: 42,
            isRunning: false,
            updatedWallClockMilliseconds: 0,
            sport: "pingpong",
            title: "超长选手姓名甲 · 暂停"
        )

        var doubles = fixture(gameID: "pingpong_doubles", score: 9)
        doubles.layoutKind = .doublesCourt
        doubles.teams[0].name = "红队超长姓名甲 / 红队乙"
        doubles.teams[1].name = "蓝队超长姓名甲 / 蓝队乙"
        doubles.players = [
            .init(id: "r1", name: "红队超长姓名甲", teamID: "team_0", slot: "top", order: 0, isServer: true),
            .init(id: "b1", name: "蓝队超长姓名甲", teamID: "team_1", slot: "top", order: 1),
            .init(id: "r2", name: "红队乙", teamID: "team_0", slot: "bottom", order: 2),
            .init(id: "b2", name: "蓝队乙", teamID: "team_1", slot: "bottom", order: 3)
        ]
        doubles.keyPoint = .init(kind: "match", side: "left")
        doubles.sportState = ["team0ScreenSide": .string("left"), "servingSide": .string("left")]

        var tennis = fixture(gameID: "tennis", score: 0)
        tennis.teams[0].name = "超长网球选手姓名甲"
        tennis.teams[1].name = "超长网球选手姓名乙"
        tennis.teams[0].games = 5
        tennis.teams[1].games = 4
        tennis.teams[0].sets = 1
        tennis.teams[1].sets = 0
        tennis.keyPoint = .init(kind: "set", side: "right")
        tennis.sportState = ["team0ScreenSide": .string("left"), "servingSide": .string("right")]

        var multi = fixture(gameID: "multi_scoreboard", score: 0)
        multi.layoutKind = .multiGrid
        multi.players = [
            .init(id: "p0", name: "第一位长姓名", score: -120, order: 0),
            .init(id: "p1", name: "第二位长姓名", score: 999, order: 1),
            .init(id: "p2", name: "第三位长姓名", score: 100, order: 2),
            .init(id: "p3", name: "第四位长姓名", score: -99, order: 3)
        ]

        let variants = [("pingpong", pingPong), ("pingpong_doubles", doubles), ("tennis", tennis), ("multi", multi)]
        let surfaces: [(String, CGSize, ScoreboardExternalProjection)] = [
            ("720p", CGSize(width: 1280, height: 720), .localProjection),
            ("1080p", CGSize(width: 1920, height: 1080), .localProjection),
            ("phone", CGSize(width: 852, height: 393), .synchronizedDisplay)
        ]
        for (variantName, state) in variants {
            for (surfaceName, size, projection) in surfaces {
                let renderer = ImageRenderer(content: ScoreboardExternalLiveView(
                    state: state,
                    projection: projection
                ).frame(width: size.width, height: size.height))
                let image = try XCTUnwrap(renderer.uiImage, "\(variantName) \(surfaceName) failed to render")
                XCTAssertEqual(image.size.width, size.width, accuracy: 1)
                XCTAssertEqual(image.size.height, size.height, accuracy: 1)
                let attachment = XCTAttachment(image: image)
                attachment.name = "projection_matrix_\(variantName)_\(surfaceName)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    /// Synthetic states rendered through the production display surfaces, without a network room.
    func testAuditDisplaySurfaceSnapshots() throws {
        FontRegistrar.registerFonts()
        let sizes: [(String, CGSize)] = [
            ("phone", CGSize(width: 852, height: 393)),
            ("tablet", CGSize(width: 1194, height: 834))
        ]
        for type in ScoreCore.GameType.allCases {
            for (sizeName, size) in sizes {
                for local in [true, false] {
                    for multiplier in [1.0, 1.5, 2.0] {
                        var state = fixture(gameID: type.rawValue, score: 18)
                        state.teams[0].name = "红方长名称 ABC Team"
                        state.teams[1].name = "蓝方长名称 XYZ Team"
                        state.teams[1].score = 12
                        state.teams[0].sets = 2; state.teams[1].sets = 1
                        state.teams[0].games = 5; state.teams[1].games = 4
                        state.appearance.fontSizeMultipliers = [
                            "mainScore": multiplier, "teamName": multiplier,
                            "playerName": multiplier, "setScore": multiplier,
                            "gameScore": multiplier, "setGameScore": multiplier,
                            "matchTitle": multiplier
                        ]
                        state.sportState?["leftDisplayScore"] = nil
                        state.sportState?["rightDisplayScore"] = nil
                        let playerCount = type.rawValue == "doudizhu" ? 3 : 4
                        state.players = (0..<playerCount).map { i in
                            ScoreboardDisplayPlayer(id: "p\(i)", name: "球员\(i + 1) Long Name",
                                score: i * 11, teamID: state.teams[i / 2].id,
                                slot: i % 2 == 0 ? "top" : "bottom", order: i, isServer: i == 0)
                        }
                        state.sportState = (state.sportState ?? [:]).merging(["servingTeam": .string("team_0"), "archeryCurrentShooter": .string("team_0")]) { _, new in new }
                        if type.rawValue.contains("tennis") || type.rawValue == "padel" {
                            state.teams[0].score = 3; state.teams[1].score = 2
                        }
                        let content = ScoreboardExternalLiveView(state: state,
                            projection: local ? .localProjection : .synchronizedDisplay)
                            .frame(width: size.width, height: size.height)
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                        let renderer = ImageRenderer(content: content)
                        renderer.scale = 1
                        let image = try XCTUnwrap(renderer.uiImage)
                        let attachment = XCTAttachment(image: image)
                        attachment.name = "display_\(type.rawValue)_\(sizeName)_\(local ? "cast" : "sync")_\(String(format: "%g", multiplier))x"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                }
            }
        }
    }

    func testFollowupMultiplayerHorizontalVariants() throws {
        for gameID in ["nine_ball", "multi_scoreboard", "uno"] {
            for count in [3, 4] {
                for local in [true, false] {
                    var state = fixture(gameID: gameID, score: 0)
                    state.layoutKind = .multiGrid
                    state.players = (0..<count).map { index in
                        ScoreboardDisplayPlayer(id: "player_\(index)", name: "Player \(index + 1) Long Name",
                            score: [0, 8, 128, -999][index], order: index)
                    }
                    state.sportState = ["multiGridColumns": .integer(count)]
                    if gameID == "nine_ball" {
                        state.sportState?["chasePlayerCount"] = .integer(count)
                        state.sportState?["chasePlayerCounts"] = .integersArrays(Array(repeating: [1, 2, 3, 4, 5, 6], count: count))
                    }
                    let renderer = ImageRenderer(content: ScoreboardExternalLiveView(state: state,
                        projection: local ? .localProjection : .synchronizedDisplay)
                        .frame(width: 852, height: 393))
                    let image = try XCTUnwrap(renderer.uiImage)
                    if gameID == "nine_ball" {
                        let cg = try XCTUnwrap(image.cgImage)
                        var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
                        pixels.withUnsafeMutableBytes { buffer in
                            let context = CGContext(data: buffer.baseAddress, width: cg.width,
                                height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                        }
                        let blackPixels = stride(from: 0, to: pixels.count, by: 4).filter {
                            pixels[$0] < 15 && pixels[$0 + 1] < 15 && pixels[$0 + 2] < 15
                        }.count
                        XCTAssertEqual(blackPixels, 0, "Default chase scores must remain white on colored panels")
                    }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "remediation_\(gameID)_\(count)_players_\(local ? "cast" : "sync")"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    private func fixture(gameID: String, score: Int) -> ScoreboardDisplayState {
        let compact = compactFixture(
            gameID: gameID,
            leftName: "A",
            rightName: "B",
            leftScore: "\(score)",
            rightScore: "0",
            revision: UInt64(score)
        )
        return ScoreboardDisplayState(compactState: compact)
    }

    private func fixture(
        gameID: String,
        leftName: String,
        rightName: String,
        leftScore: String,
        rightScore: String,
        revision: UInt64
    ) -> ScoreboardDisplayState {
        ScoreboardDisplayState(compactState: compactFixture(
            gameID: gameID,
            leftName: leftName,
            rightName: rightName,
            leftScore: leftScore,
            rightScore: rightScore,
            revision: revision
        ))
    }

    private func compactFixture(
        gameID: String,
        leftName: String,
        rightName: String,
        leftScore: String,
        rightScore: String,
        revision: UInt64,
        title: String = ""
    ) -> LocalScoreboardDisplayState {
        LocalScoreboardDisplayState(
            gameID: gameID,
            title: title,
            leftName: leftName,
            rightName: rightName,
            leftScore: leftScore,
            rightScore: rightScore,
            themeID: "default",
            fontID: "default",
            finished: false,
            revision: revision
        )
    }

    private var expectedExactGameIDs: Set<String> {
        [
            "football", "football_5v5", "basketball", "three_basketball",
            "volleyball", "air_volleyball", "beach_volleyball",
            "pingpong", "pingpong_doubles", "tennis", "tennis_doubles",
            "badminton", "badminton_doubles", "shuttlecock", "squash",
            "soft_tennis", "padel", "pickleball", "pickleball_doubles",
            "archery_dual", "boxing", "billiards", "eight_ball", "nine_ball",
            "snooker", "guandan", "shengji", "uno", "doudizhu", "foosball",
            "foosball_doubles", "simple_score", "multi_scoreboard"
        ]
    }

    private func expectedLayout(for gameType: ScoreCore.GameType) -> ScoreboardDisplayLayoutKind {
        switch gameType {
        case .pingpongDoubles, .tennisDoubles, .badmintonDoubles,
             .pickleballDoubles, .foosballDoubles, .padel:
            .doublesCourt
        case .uno, .multiScoreboard:
            .multiGrid
        case .guandan, .shengji, .doudizhu:
            .boardCard
        default:
            .twoSide
        }
    }
}

@MainActor
private final class PurchaseGateInvocationCounter {
    var value = 0
}
