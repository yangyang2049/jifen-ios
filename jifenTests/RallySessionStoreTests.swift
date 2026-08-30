import XCTest
import PersistenceCore
import ScoreCore
import SessionCore
@testable import jifen

@MainActor
final class RallySessionStoreTests: XCTestCase {
    private let participants: [SessionParticipant] = [
        .init(id: "left-top", name: "Red A", role: "player"),
        .init(id: "left-bottom", name: "Red B", role: "player"),
        .init(id: "right-top", name: "Blue A", role: "player"),
        .init(id: "right-bottom", name: "Blue B", role: "player")
    ]

    func testPingPongDoublesUsesCrossPlatformSlotOrder() {
        let store = RallySessionStore(
            leftName: "Red",
            rightName: "Blue",
            gameType: .pingpongDoubles,
            rules: .pingPong(),
            participants: participants
        )

        XCTAssertEqual(store.state.doubles?.playerNames, ["Red A", "Blue A", "Red B", "Blue B"])
        XCTAssertEqual(store.state.doubles?.serverSlotIndex, 0)
        XCTAssertEqual(store.state.doubles?.receiverSlotIndex, 1)
        XCTAssertEqual(store.state.doubles?.serverName, "Red A")
        XCTAssertEqual(store.state.doubles?.receiverName, "Blue A")
        guard case .pingPong(let rotation) = store.state.doubles?.rotation else {
            return XCTFail("Expected ping-pong doubles rotation")
        }
        XCTAssertNil(rotation.pendingGameOpening)
    }

    func testBadmintonDoublesUsesCrossPlatformSlotOrder() {
        let store = RallySessionStore(
            leftName: "Red",
            rightName: "Blue",
            gameType: .badmintonDoubles,
            rules: .badminton(),
            participants: participants
        )

        XCTAssertEqual(store.state.doubles?.playerNames, ["Red A", "Blue A", "Red B", "Blue B"])
        XCTAssertEqual(store.state.doubles?.serverSlotIndex, 2)
        XCTAssertEqual(store.state.doubles?.receiverSlotIndex, 1)
    }

    func testSinglesDoesNotCreateDoublesState() {
        let store = RallySessionStore(
            leftName: "Red",
            rightName: "Blue",
            gameType: .pingpong,
            rules: .pingPong()
        )

        XCTAssertNil(store.state.doubles)
    }

    func testPingPongTerminalPointEventKeepsElevenWhileReducerAdvancesNextSet() {
        var state = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: .pingPong(maxSets: 3))
        state.leftPoints = 10
        state.rightPoints = 4

        let result = RallyMatchReducer().reduce(state: state, intent: .pointWon(.left), at: 1)

        XCTAssertTrue(result.events.contains(.setCompleted(
            winner: .left,
            setNumber: 1,
            leftPoints: 11,
            rightPoints: 4,
            leftSets: 1,
            rightSets: 0
        )))
        XCTAssertEqual(result.state.leftPoints, 0)
        XCTAssertEqual(result.state.rightPoints, 0)
        XCTAssertEqual(result.state.leftSets, 1)
    }

    func testPingPongDeuceRequiresTwoPointLeadBeforeTerminalEvent() {
        var state = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: .pingPong(maxSets: 3))
        state.leftPoints = 10
        state.rightPoints = 10

        let advantage = RallyMatchReducer().reduce(state: state, intent: .pointWon(.left), at: 1)
        XCTAssertEqual(advantage.state.leftPoints, 11)
        XCTAssertFalse(advantage.events.contains { if case .setCompleted = $0 { true } else { false } })

        let completed = RallyMatchReducer().reduce(state: advantage.state, intent: .pointWon(.left), at: 2)
        XCTAssertTrue(completed.events.contains { event in
            if case .setCompleted(_, _, 12, 10, _, _) = event { return true }
            return false
        })
    }

    func testPingPongDecidingSetChangesSidesAtConfiguredSwitchPoint() {
        var rules = RallyRuleSet.pingPong(maxSets: 5)
        rules.autoChangeSides = true
        rules.decidingSetSideSwitchPoint = 5
        var state = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: rules)
        state.leftSets = 2
        state.rightSets = 2
        state.leftPoints = 4

        let result = RallyMatchReducer().reduce(state: state, intent: .pointWon(.left), at: 1)

        XCTAssertEqual(result.state.leftPoints, 5)
        XCTAssertTrue(result.events.contains(.sidesExchanged))
        XCTAssertTrue(result.state.sidesSwapped)
    }

    func testPickleballAuthoritativeRebaseContinuesFromWatchScore() async {
        let store = RallySessionStore(
            leftName: "A",
            rightName: "B",
            gameType: .pickleball,
            rules: .pickleball()
        )
        var watchState = store.state
        watchState.leftPoints = 5
        watchState.rightPoints = 2

        let applied = await store.applyAuthoritativeState(
            watchState,
            detailedActions: [],
            revision: 7
        )
        XCTAssertTrue(applied)

        let scored = expectation(description: "score continues from rebased state")
        store.send(.pointWon(.left)) { _ in scored.fulfill() }
        await fulfillment(of: [scored], timeout: 2)
        XCTAssertEqual(store.state.leftPoints, 6)
        XCTAssertEqual(store.state.rightPoints, 2)

        var staleState = watchState
        staleState.leftPoints = 1
        let staleApplied = await store.applyAuthoritativeState(
            staleState,
            detailedActions: [],
            revision: 6
        )
        XCTAssertFalse(staleApplied)
        XCTAssertEqual(store.state.leftPoints, 6)
    }

    func testRallyRapidOperationsPersistUndoBundleAcrossRestore() async throws {
        let store = RallySessionStore(
            leftName: "A",
            rightName: "B",
            gameType: .pingpong,
            rules: .pingPong()
        )
        let scored = expectation(description: "serialized score operations")
        scored.expectedFulfillmentCount = 3
        for _ in 0..<3 {
            store.send(.pointWon(.left)) { _ in scored.fulfill() }
        }
        await fulfillment(of: [scored], timeout: 2)

        let flushed = expectation(description: "resume bundle flushed")
        store.flush { flushed.fulfill() }
        await fulfillment(of: [flushed], timeout: 2)

        let restored = try XCTUnwrap(RallySessionStore(restoring: store.sessionId))
        XCTAssertEqual(restored.state.leftPoints, 3)
        let undone = expectation(description: "restored undo frame")
        restored.undo { success in
            XCTAssertTrue(success)
            undone.fulfill()
        }
        await fulfillment(of: [undone], timeout: 2)
        XCTAssertEqual(restored.state.leftPoints, 2)
    }

    func testTennisAuthoritativeRebaseContinuesFromThirtyFifteen() async {
        let store = TennisSessionStore(
            leftName: "A",
            rightName: "B",
            rules: .init(autoChangeSides: false)
        )
        var watchState = store.state
        watchState.leftPoints = 2
        watchState.rightPoints = 1

        let applied = await store.applyAuthoritativeState(
            watchState,
            detailedActions: [],
            revision: 4
        )
        XCTAssertTrue(applied)

        let scored = expectation(description: "tennis score continues from rebased state")
        store.send(.pointWon(.left)) { _ in scored.fulfill() }
        await fulfillment(of: [scored], timeout: 2)
        XCTAssertEqual(store.state.leftPoints, 3)
        XCTAssertEqual(store.state.rightPoints, 1)
        XCTAssertEqual(store.state.scoreDisplay(for: .left), "40")
        XCTAssertEqual(store.state.scoreDisplay(for: .right), "15")
    }

    func testTennisTerminalGameEventsPreserveFinalPointAndSetScoresForPresentation() {
        var state = TennisMatchState(
            leftName: "A",
            rightName: "B",
            rules: .init(maxSets: 3, gamesPerSet: 6, autoChangeSides: true)
        )
        state.leftPoints = 3
        state.rightPoints = 0
        state.leftGames = 5
        state.rightGames = 4

        let result = TennisMatchReducer().reduce(state: state, intent: .pointWon(.left), at: 1)

        XCTAssertTrue(result.events.contains(.pointScored(side: .left, left: 4, right: 0)))
        XCTAssertTrue(result.events.contains(.gameCompleted(winner: .left, leftGames: 6, rightGames: 4, tieBreak: false)))
        XCTAssertTrue(result.events.contains(.setCompleted(
            winner: .left,
            setNumber: 1,
            leftGames: 6,
            rightGames: 4,
            leftSets: 1,
            rightSets: 0
        )))
        XCTAssertEqual(result.state.leftPoints, 0)
        XCTAssertEqual(result.state.leftGames, 0)
        XCTAssertEqual(result.state.leftSets, 1)
    }

    func testTennisDoublesResumeKeepsAllFourPlayerIdentities() async throws {
        let resumeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("tennis-doubles-resume-\(UUID().uuidString)", isDirectory: true)
        let resumeRepository = ResumeSessionRepository(rootURL: resumeRoot)
        defer { try? FileManager.default.removeItem(at: resumeRoot) }

        let state = TennisMatchState(
            leftName: "红队",
            rightName: "蓝队",
            doublesPlayerNames: ["红A", "蓝A", "红B", "蓝B"]
        )
        let store = TennisSessionStore(
            gameType: .tennisDoubles,
            state: state,
            resumeRepository: resumeRepository
        )
        store.persistSnapshot()
        let flushed = expectation(description: "tennis doubles resume flushed")
        store.flush { flushed.fulfill() }
        await fulfillment(of: [flushed], timeout: 2)

        let bundle = try await resumeRepository.loadResumeBundle(
            sessionId: store.sessionId,
            as: ScoreSessionResumeBundle<TennisMatchState, TennisMatchEvent, TennisMatchIntent>.self
        )
        XCTAssertEqual(bundle?.currentSession.participants.map(\.name), ["红A", "蓝A", "红B", "蓝B"])
    }

    func testFreshMatchStoresUseNewSessionIDsAndPreserveConfiguration() {
        let rally = RallySessionStore(
            leftName: "Red A/Red B",
            rightName: "Blue A/Blue B",
            gameType: .foosballDoubles,
            rules: .foosball(maxSets: 5),
            participants: participants,
            openingServer: .right,
            voiceAnnouncementEnabled: true,
            showMatchTimeEnabled: true
        )
        let freshRally = rally.makeFreshMatchStore()
        XCTAssertNotEqual(freshRally.sessionId, rally.sessionId)
        XCTAssertEqual(freshRally.state.rules, rally.state.rules)
        XCTAssertEqual(freshRally.state.doubles?.playerNames, rally.state.doubles?.playerNames)
        XCTAssertEqual(freshRally.state.openingServerSide, .right)
        XCTAssertTrue(freshRally.voiceAnnouncementEnabled)
        XCTAssertTrue(freshRally.showMatchTimeEnabled)

        let tennisState = TennisMatchState(
            leftName: "Red A/Red B",
            rightName: "Blue A/Blue B",
            rules: .init(maxSets: 5, tieBreakPoints: 10),
            openingServer: .right,
            doublesPlayerNames: ["Red A", "Blue A", "Red B", "Blue B"]
        )
        let tennis = TennisSessionStore(
            gameType: .tennisDoubles,
            state: tennisState,
            voiceAnnouncementEnabled: true
        )
        let freshTennis = tennis.makeFreshMatchStore()
        XCTAssertNotEqual(freshTennis.sessionId, tennis.sessionId)
        XCTAssertEqual(freshTennis.state.rules, tennis.state.rules)
        XCTAssertEqual(freshTennis.state.doublesPlayerNames, tennis.state.doublesPlayerNames)
        XCTAssertEqual(freshTennis.state.openingServerSide, .right)
        XCTAssertTrue(freshTennis.voiceAnnouncementEnabled)

        let basketball = BasketballSessionStore(
            leftName: "Home",
            rightName: "Away",
            gameMode: .threeXThree,
            ruleSet: .nba
        )
        let freshBasketball = basketball.makeFreshMatchStore()
        XCTAssertNotEqual(freshBasketball.sessionId, basketball.sessionId)
        XCTAssertEqual(freshBasketball.state.leftName, "Home")
        XCTAssertEqual(freshBasketball.state.rightName, "Away")
        XCTAssertEqual(freshBasketball.state.gameMode, .threeXThree)
        XCTAssertEqual(freshBasketball.state.ruleSet, .nba)
    }

    func testRallyAndTennisPresentationMetadataSurvivesLiveResume() async throws {
        let rally = RallySessionStore(
            leftName: "A",
            rightName: "B",
            gameType: .pingpong,
            rules: .pingPong(),
            voiceAnnouncementEnabled: true,
            showMatchTimeEnabled: true
        )
        let tennis = TennisSessionStore(
            leftName: "A",
            rightName: "B",
            voiceAnnouncementEnabled: true
        )
        defer {
            Task {
                try? await ResumeSessionRepository().remove(sessionId: rally.sessionId)
                try? await ResumeSessionRepository().remove(sessionId: tennis.sessionId)
            }
        }

        let rallySaved = expectation(description: "rally presentation metadata saved")
        rally.persistSnapshot { success in
            XCTAssertTrue(success)
            rallySaved.fulfill()
        }
        let tennisSaved = expectation(description: "tennis presentation metadata saved")
        tennis.persistSnapshot { success in
            XCTAssertTrue(success)
            tennisSaved.fulfill()
        }
        await fulfillment(of: [rallySaved, tennisSaved], timeout: 2)

        let restoredRally = try XCTUnwrap(RallySessionStore(restoring: rally.sessionId))
        XCTAssertTrue(restoredRally.voiceAnnouncementEnabled)
        XCTAssertTrue(restoredRally.showMatchTimeEnabled)
        let restoredTennis = try XCTUnwrap(TennisSessionStore(restoring: tennis.sessionId))
        XCTAssertTrue(restoredTennis.voiceAnnouncementEnabled)

        restoredRally.setVoiceAnnouncementEnabled(false)
        restoredRally.setShowMatchTimeEnabled(false)
        restoredTennis.setVoiceAnnouncementEnabled(false)
        let rallyFlushed = expectation(description: "rally presentation metadata updated")
        restoredRally.flush { rallyFlushed.fulfill() }
        let tennisFlushed = expectation(description: "tennis presentation metadata updated")
        restoredTennis.flush { tennisFlushed.fulfill() }
        await fulfillment(of: [rallyFlushed, tennisFlushed], timeout: 2)

        XCTAssertFalse(try XCTUnwrap(RallySessionStore(restoring: rally.sessionId)).voiceAnnouncementEnabled)
        XCTAssertFalse(try XCTUnwrap(RallySessionStore(restoring: rally.sessionId)).showMatchTimeEnabled)
        XCTAssertFalse(try XCTUnwrap(TennisSessionStore(restoring: tennis.sessionId)).voiceAnnouncementEnabled)
    }

    func testThreeXThreeRapidScoringStopsAtTargetAndFinalSaveIsReusable() async {
        let resumeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("three-basketball-rapid-score-\(UUID().uuidString)", isDirectory: true)
        let resumeRepository = ResumeSessionRepository(rootURL: resumeRoot)
        let store = BasketballSessionStore(
            leftName: "Home",
            rightName: "Away",
            gameMode: .threeXThree,
            resumeRepository: resumeRepository
        )
        defer {
            _ = ScoreboardRecordManager.shared.deleteRecord(store.sessionId.uuidString)
            try? FileManager.default.removeItem(at: resumeRoot)
        }

        for _ in 0..<30 {
            store.send(.addPoints(side: .left, points: 1))
        }

        let flushed = expectation(description: "rapid 3x3 scores persisted")
        store.flush { flushed.fulfill() }
        await fulfillment(of: [flushed], timeout: 5)

        XCTAssertTrue(store.state.finished)
        XCTAssertEqual(store.state.leftScore, 21)
        XCTAssertEqual(store.state.rightScore, 0)
        XCTAssertEqual(store.actionTimeline.count, 21)
        XCTAssertEqual(
            ScoreboardRecordManager.shared.getRecordById(store.sessionId.uuidString)?.team1FinalScore,
            21
        )

        let firstReuse = expectation(description: "first final snapshot reused")
        let secondReuse = expectation(description: "second final snapshot reused")
        store.persistSnapshot { success in
            XCTAssertTrue(success)
            firstReuse.fulfill()
        }
        store.persistSnapshot { success in
            XCTAssertTrue(success)
            secondReuse.fulfill()
        }
        await fulfillment(of: [firstReuse, secondReuse], timeout: 2)
    }

    func testFiveVFiveRapidScoringAfterFinishDoesNotCreateDuplicateActions() async {
        let resumeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("basketball-rapid-score-\(UUID().uuidString)", isDirectory: true)
        let resumeRepository = ResumeSessionRepository(rootURL: resumeRoot)
        let store = BasketballSessionStore(
            leftName: "Home",
            rightName: "Away",
            gameMode: .fiveVFive,
            resumeRepository: resumeRepository
        )
        defer {
            _ = ScoreboardRecordManager.shared.deleteRecord(store.sessionId.uuidString)
            try? FileManager.default.removeItem(at: resumeRoot)
        }

        store.send(.addPoints(side: .left, points: 3))
        store.send(.finish)
        for _ in 0..<12 {
            store.send(.addPoints(side: .left, points: 3))
        }

        let flushed = expectation(description: "rapid basketball finish persisted")
        store.flush { flushed.fulfill() }
        await fulfillment(of: [flushed], timeout: 5)

        XCTAssertTrue(store.state.finished)
        XCTAssertEqual(store.state.leftScore, 3)
        XCTAssertEqual(store.actionTimeline.count, 2)
        XCTAssertEqual(store.actionTimeline.last?.type, .matchFinished)
        XCTAssertEqual(
            ScoreboardRecordManager.shared.getRecordById(store.sessionId.uuidString)?.team1FinalScore,
            3
        )

        let finalSave = expectation(description: "final basketball snapshot reused")
        store.persistSnapshot { success in
            XCTAssertTrue(success)
            finalSave.fulfill()
        }
        await fulfillment(of: [finalSave], timeout: 2)
    }

    func testBasketballUndoRestoresPersistedRecordCheckpointWithoutGhostPeriod() async throws {
        let repository = ResumeSessionRepository()
        let store = BasketballSessionStore(
            leftName: "Home",
            rightName: "Away",
            gameMode: .fiveVFive
        )
        defer {
            _ = ScoreboardRecordManager.shared.deleteRecord(store.sessionId.uuidString)
            Task { try? await repository.remove(sessionId: store.sessionId) }
        }

        store.send(.addPoints(side: .left, points: 2))
        store.send(.enterOvertime)
        let initiallySaved = expectation(description: "basketball undo checkpoints persisted")
        store.flush { initiallySaved.fulfill() }
        await fulfillment(of: [initiallySaved], timeout: 2)

        XCTAssertEqual(store.actionTimeline.map(\.type), [.scoreChanged, .periodFinished])
        let savedBundle = try await repository.loadResumeBundle(
            sessionId: store.sessionId,
            as: ScoreSessionResumeBundle<
                BasketballMatchState,
                BasketballMatchEvent,
                BasketballMatchIntent
            >.self
        )
        let savedContext = try XCTUnwrap(ScoreSessionRecordContext.decode(savedBundle?.auxiliaryPayload))
        XCTAssertEqual(savedContext.undoCheckpoints.count, 2)

        let restored = try XCTUnwrap(BasketballSessionStore(restoring: store.sessionId))
        XCTAssertTrue(restored.state.isOvertime)
        let undone = expectation(description: "restored basketball period undone")
        restored.undo { success in
            XCTAssertTrue(success)
            undone.fulfill()
        }
        await fulfillment(of: [undone], timeout: 2)

        XCTAssertFalse(restored.state.isOvertime)
        XCTAssertEqual(restored.state.leftScore, 2)
        XCTAssertEqual(restored.actionTimeline.map(\.type), [.scoreChanged])

        restored.send(.finish)
        let finished = expectation(description: "basketball record committed after undo")
        restored.flush { finished.fulfill() }
        await fulfillment(of: [finished], timeout: 2)

        let record = try XCTUnwrap(
            ScoreboardRecordManager.shared.getRecordById(store.sessionId.uuidString)
        )
        let recordedActions = try XCTUnwrap(record.detailedActions)
        XCTAssertEqual(recordedActions.map(\.type), [.scoreChanged, .matchFinished])
        XCTAssertFalse(recordedActions.contains(where: { $0.type == .periodFinished }))
        XCTAssertTrue(
            record.setResults?.isEmpty == true,
            "An undone overtime/period must not survive in set results"
        )
    }

    func testRallyUndoRestoresTerminalPointRecordGroupAtomicallyAcrossResume() async throws {
        let repository = ResumeSessionRepository()
        var state = RallyMatchEngine.initial(
            leftName: "A",
            rightName: "B",
            rules: .pingPong(maxSets: 3)
        )
        state.leftPoints = 10
        state.rightPoints = 4
        let store = RallySessionStore(gameType: .pingpong, state: state)
        defer {
            _ = ScoreboardRecordManager.shared.deleteRecord(store.sessionId.uuidString)
            Task { try? await repository.remove(sessionId: store.sessionId) }
        }

        let scored = expectation(description: "rally terminal point recorded")
        store.send(.pointWon(.left)) { _ in scored.fulfill() }
        await fulfillment(of: [scored], timeout: 2)
        let saved = expectation(description: "rally record checkpoint saved")
        store.flush { saved.fulfill() }
        await fulfillment(of: [saved], timeout: 2)

        XCTAssertEqual(store.state.leftSets, 1)
        XCTAssertTrue(store.actionTimeline.contains { $0.operationCode == "point" })
        XCTAssertTrue(store.actionTimeline.contains { $0.operationCode == "set_completed" })
        XCTAssertEqual(store.completedSetScores, [.init(leftGames: 11, rightGames: 4)])

        let restored = try XCTUnwrap(RallySessionStore(restoring: store.sessionId))
        let undone = expectation(description: "restored rally terminal group undone")
        restored.undo { success in
            XCTAssertTrue(success)
            undone.fulfill()
        }
        await fulfillment(of: [undone], timeout: 2)

        XCTAssertEqual(restored.state.leftPoints, 10)
        XCTAssertEqual(restored.state.rightPoints, 4)
        XCTAssertEqual(restored.state.leftSets, 0)
        XCTAssertTrue(restored.actionTimeline.isEmpty)
        XCTAssertTrue(restored.completedSetScores.isEmpty)
    }

    func testTennisUndoRestoresPointGameAndSetRecordGroupAtomicallyAcrossResume() async throws {
        let repository = ResumeSessionRepository()
        var state = TennisMatchState(
            leftName: "A",
            rightName: "B",
            rules: .init(maxSets: 3, gamesPerSet: 6, autoChangeSides: false)
        )
        state.leftPoints = 3
        state.rightPoints = 0
        state.leftGames = 5
        state.rightGames = 4
        let store = TennisSessionStore(gameType: .tennis, state: state)
        defer {
            _ = ScoreboardRecordManager.shared.deleteRecord(store.sessionId.uuidString)
            Task { try? await repository.remove(sessionId: store.sessionId) }
        }

        let scored = expectation(description: "tennis terminal point recorded")
        store.send(.pointWon(.left)) { _ in scored.fulfill() }
        await fulfillment(of: [scored], timeout: 2)
        let saved = expectation(description: "tennis record checkpoint saved")
        store.flush { saved.fulfill() }
        await fulfillment(of: [saved], timeout: 2)

        XCTAssertEqual(
            store.actionTimeline.map(\.operationCode),
            ["point", "game_completed", "set_completed"]
        )
        XCTAssertEqual(store.completedSetScores, [.init(leftGames: 6, rightGames: 4)])

        let restored = try XCTUnwrap(TennisSessionStore(restoring: store.sessionId))
        let undone = expectation(description: "restored tennis terminal group undone")
        restored.undo { success in
            XCTAssertTrue(success)
            undone.fulfill()
        }
        await fulfillment(of: [undone], timeout: 2)

        XCTAssertEqual(restored.state.leftPoints, 3)
        XCTAssertEqual(restored.state.rightPoints, 0)
        XCTAssertEqual(restored.state.leftGames, 5)
        XCTAssertEqual(restored.state.rightGames, 4)
        XCTAssertEqual(restored.state.leftSets, 0)
        XCTAssertTrue(restored.actionTimeline.isEmpty)
        XCTAssertTrue(restored.completedSetScores.isEmpty)
    }

    func testRallyUndoRemovesOnlyTheLatestTableTennisAdministrativeRecord() async {
        let repository = ResumeSessionRepository()
        let store = RallySessionStore(
            leftName: "A",
            rightName: "B",
            gameType: .pingpong,
            rules: .pingPong()
        )
        defer {
            _ = ScoreboardRecordManager.shared.deleteRecord(store.sessionId.uuidString)
            Task { try? await repository.remove(sessionId: store.sessionId) }
        }

        let point = expectation(description: "point recorded before card")
        store.send(.pointWon(.left)) { _ in point.fulfill() }
        await fulfillment(of: [point], timeout: 2)
        let card = expectation(description: "red card recorded")
        store.send(.pingPongAdministrativeAction(type: .redCard, side: .right)) { _ in card.fulfill() }
        await fulfillment(of: [card], timeout: 2)

        XCTAssertEqual(store.actionTimeline.map(\.operationCode), ["point", "red_card"])
        XCTAssertTrue(store.state.pingPongAdministrativeStatus(for: .right).hasYellowCard)
        let undone = expectation(description: "red card undone")
        store.undo { success in
            XCTAssertTrue(success)
            undone.fulfill()
        }
        await fulfillment(of: [undone], timeout: 2)

        XCTAssertEqual(store.state.leftPoints, 1)
        XCTAssertEqual(store.state.pingPongAdministrativeStatus(for: .right).redCardCount, 0)
        XCTAssertEqual(store.actionTimeline.map(\.operationCode), ["point"])
    }

    func testLegacyPickleballResumeWithoutSportProfileUsesAndroid31SinglesRules() async throws {
        typealias Bundle = ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>
        let repository = ResumeSessionRepository()
        var rules = RallyRuleSet.pickleball(maxSets: 3)
        rules.useRallyScoring = true
        rules.nextSetServerModel = .opening
        let state = RallyMatchEngine.initial(
            leftName: "A",
            rightName: "B",
            rules: rules,
            openingServer: .left
        )
        let session = ScoreSession<RallyMatchState, RallyMatchEvent>(
            gameType: .pickleball,
            ruleFamily: .s1,
            reducerType: "rally/v1",
            state: state
        )
        let bundle = Bundle(
            replaySeed: session,
            currentSession: session,
            undoFrames: [],
            timeline: []
        )
        defer { Task { try? await repository.remove(sessionId: session.sessionId) } }

        func removingSportProfile(from object: Any) -> Any {
            if var dictionary = object as? [String: Any] {
                dictionary.removeValue(forKey: "sportProfile")
                return dictionary.mapValues { removingSportProfile(from: $0) }
            }
            if let array = object as? [Any] {
                return array.map { removingSportProfile(from: $0) }
            }
            return object
        }

        let encoded = try JSONEncoder().encode(bundle)
        let json = try JSONSerialization.jsonObject(with: encoded)
        let legacyData = try JSONSerialization.data(
            withJSONObject: removingSportProfile(from: json)
        )
        let legacyBundle = try JSONDecoder().decode(Bundle.self, from: legacyData)
        XCTAssertEqual(legacyBundle.currentSession.state.rules.sportProfile, .generic)
        try await repository.saveResumeBundle(legacyBundle)

        let restored = try XCTUnwrap(RallySessionStore(restoring: session.sessionId))
        XCTAssertEqual(restored.state.rules.sportProfile, .pickleball)
        XCTAssertEqual(restored.state.rules.nextSetServerModel, .opening)
        let scored = expectation(description: "migrated pickleball alternates prior server")
        restored.send(.pointWon(.left)) { _ in scored.fulfill() }
        await fulfillment(of: [scored], timeout: 2)
        XCTAssertEqual(restored.state.servingSide, .right)
    }

    func testLegacyPingPongDoublesResumeMigratesReceiverSlotsThroughNextSet() async throws {
        typealias Bundle = ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>
        let repository = ResumeSessionRepository()
        var state = RallyMatchEngine.initial(
            leftName: "Red",
            rightName: "Blue",
            rules: .pingPong(maxSets: 3),
            doubles: .pingPong(
                playerNames: ["Red A", "Blue A", "Red B", "Blue B"],
                openingServerSlotIndex: 0,
                openingReceiverSlotIndex: 3
            )
        )
        state = RallyMatchReducer().reduce(state: state, intent: .pointWon(.left), at: 1).state
        state = RallyMatchReducer().reduce(state: state, intent: .pointWon(.left), at: 2).state
        XCTAssertEqual(state.doubles?.serverSlotIndex, 3)
        XCTAssertEqual(state.doubles?.receiverSlotIndex, 2)
        let session = ScoreSession<RallyMatchState, RallyMatchEvent>(
            gameType: .pingpongDoubles,
            ruleFamily: .s1,
            reducerType: "rally/v1",
            state: state,
            participants: participants
        )
        let bundle = Bundle(
            replaySeed: session,
            currentSession: session,
            undoFrames: [],
            timeline: []
        )
        defer { Task { try? await repository.remove(sessionId: session.sessionId) } }
        try await repository.saveResumeBundle(bundle)

        let restored = try XCTUnwrap(RallySessionStore(restoring: session.sessionId))
        XCTAssertEqual(restored.state.doubles?.serverSlotIndex, 1)
        XCTAssertEqual(restored.state.doubles?.receiverSlotIndex, 2)
        XCTAssertEqual(restored.state.currentSetReplay?.baselineDoubles?.receiverSlotIndex, 1)

        for _ in 0..<9 {
            restored.send(.pointWon(.left))
        }
        let completed = expectation(description: "migrated ping-pong next set ready")
        restored.flush { completed.fulfill() }
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(restored.state.leftSets, 1)
        XCTAssertEqual(restored.state.doubles?.serverSlotIndex, 1)
        XCTAssertEqual(restored.state.doubles?.receiverSlotIndex, 0)
    }

    func testRallyRapidQueuedSendsDeliverAtomicBeforeAndAfterTransitions() async {
        let store = RallySessionStore(
            leftName: "A",
            rightName: "B",
            gameType: .pingpong,
            rules: .pingPong()
        )
        var beforeScores: [Int] = []
        var afterScores: [Int] = []
        let transitioned = expectation(description: "two serialized rally transitions")
        transitioned.expectedFulfillmentCount = 2

        for _ in 0..<2 {
            store.send(.pointWon(.left), onTransition: { before, after, events in
                XCTAssertTrue(events.contains { if case .pointScored = $0 { return true }; return false })
                beforeScores.append(before.leftPoints)
                afterScores.append(after.leftPoints)
                transitioned.fulfill()
            })
        }

        await fulfillment(of: [transitioned], timeout: 3)
        XCTAssertEqual(beforeScores, [0, 1])
        XCTAssertEqual(afterScores, [1, 2])
    }

    func testTennisRapidQueuedSendsDeliverAtomicBeforeAndAfterTransitions() async {
        let store = TennisSessionStore(leftName: "A", rightName: "B")
        var beforeScores: [Int] = []
        var afterScores: [Int] = []
        let transitioned = expectation(description: "two serialized tennis transitions")
        transitioned.expectedFulfillmentCount = 2

        for _ in 0..<2 {
            store.send(.pointWon(.left), onTransition: { before, after, events in
                XCTAssertTrue(events.contains { if case .pointScored = $0 { return true }; return false })
                beforeScores.append(before.leftPoints)
                afterScores.append(after.leftPoints)
                transitioned.fulfill()
            })
        }

        await fulfillment(of: [transitioned], timeout: 3)
        XCTAssertEqual(beforeScores, [0, 1])
        XCTAssertEqual(afterScores, [1, 2])
    }

    func testRallyRapidTerminalScoringReusesFinishedPersistence() async {
        let resumeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("rally-rapid-finish-\(UUID().uuidString)", isDirectory: true)
        let resumeRepository = ResumeSessionRepository(rootURL: resumeRoot)
        let store = RallySessionStore(
            leftName: "A",
            rightName: "B",
            gameType: .pingpong,
            rules: .pingPong(maxSets: 1),
            resumeRepository: resumeRepository
        )
        defer {
            _ = ScoreboardRecordManager.shared.deleteRecord(store.sessionId.uuidString)
            try? FileManager.default.removeItem(at: resumeRoot)
        }

        for _ in 0..<18 {
            store.send(.pointWon(.left))
        }
        let flushed = expectation(description: "rapid rally finish persisted")
        store.flush { flushed.fulfill() }
        await fulfillment(of: [flushed], timeout: 5)

        XCTAssertTrue(store.state.finished)
        XCTAssertEqual(store.state.leftPoints, 11)
        XCTAssertEqual(
            ScoreboardRecordManager.shared.getRecordById(store.sessionId.uuidString)?.team1FinalScore,
            11
        )
        XCTAssertEqual(
            store.actionTimeline.last(where: { $0.operationCode == "point" })?.setNumber,
            1,
            "The terminal point belongs to the completed set, not the reducer's next currentSet"
        )

        let firstReuse = expectation(description: "first rally final snapshot reused")
        let secondReuse = expectation(description: "second rally final snapshot reused")
        store.persistSnapshot { success in
            XCTAssertTrue(success)
            firstReuse.fulfill()
        }
        store.persistSnapshot { success in
            XCTAssertTrue(success)
            secondReuse.fulfill()
        }
        await fulfillment(of: [firstReuse, secondReuse], timeout: 2)
    }

    func testTennisRapidTiebreakFinishReusesFinishedPersistence() async {
        let resumeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("tennis-rapid-finish-\(UUID().uuidString)", isDirectory: true)
        let resumeRepository = ResumeSessionRepository(rootURL: resumeRoot)
        let store = TennisSessionStore(
            leftName: "A",
            rightName: "B",
            rules: .init(tieBreakPoints: 7, setScoringMode: .tiebreakOnly),
            resumeRepository: resumeRepository
        )
        defer {
            _ = ScoreboardRecordManager.shared.deleteRecord(store.sessionId.uuidString)
            try? FileManager.default.removeItem(at: resumeRoot)
        }

        for _ in 0..<12 {
            store.send(.pointWon(.left))
        }
        let flushed = expectation(description: "rapid tennis finish persisted")
        store.flush { flushed.fulfill() }
        await fulfillment(of: [flushed], timeout: 5)

        XCTAssertTrue(store.state.finished)
        XCTAssertEqual(store.state.leftPoints, 7)
        XCTAssertEqual(
            ScoreboardRecordManager.shared.getRecordById(store.sessionId.uuidString)?.team1FinalScore,
            7
        )
        XCTAssertTrue(
            store.actionTimeline
                .filter { $0.operationCode == "point" || $0.operationCode == "finish" }
                .allSatisfy { $0.setNumber == 1 }
        )

        let firstReuse = expectation(description: "first tennis final snapshot reused")
        let secondReuse = expectation(description: "second tennis final snapshot reused")
        store.persistSnapshot { success in
            XCTAssertTrue(success)
            firstReuse.fulfill()
        }
        store.persistSnapshot { success in
            XCTAssertTrue(success)
            secondReuse.fulfill()
        }
        await fulfillment(of: [firstReuse, secondReuse], timeout: 2)
    }

    func testFollowerFinishedRallyKeepsLastLiveResumeUntilFormalRecordArrives() async throws {
        let resumeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("follower-finished-rally-\(UUID().uuidString)", isDirectory: true)
        let resumeRepository = ResumeSessionRepository(rootURL: resumeRoot)
        defer { try? FileManager.default.removeItem(at: resumeRoot) }
        let store = RallySessionStore(
            leftName: "A",
            rightName: "B",
            gameType: .pingpong,
            rules: .pingPong(),
            resumeRepository: resumeRepository
        )
        let liveSaved = expectation(description: "live follower resume saved")
        store.persistSnapshot { success in
            XCTAssertTrue(success)
            liveSaved.fulfill()
        }
        await fulfillment(of: [liveSaved], timeout: 2)

        let finishedState = RallyMatchReducer().reduce(
            state: store.state,
            intent: .finish,
            at: 1
        ).state
        let applied = await store.applyAuthoritativeState(
            finishedState,
            detailedActions: [],
            revision: 1,
            persistFormalRecord: false
        )

        XCTAssertTrue(applied)
        let retained = try await resumeRepository.loadResumeBundle(
            sessionId: store.sessionId,
            as: ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>.self
        )
        XCTAssertEqual(retained?.currentSession.status, .live)
        XCTAssertFalse(retained?.currentSession.state.finished ?? true)
    }

    func testFinishedBilliardsStoreDoesNotDeleteResumeBeforeFormalRecordCommit() async throws {
        let resumeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("finished-billiards-resume-\(UUID().uuidString)", isDirectory: true)
        let resumeRepository = ResumeSessionRepository(rootURL: resumeRoot)
        defer { try? FileManager.default.removeItem(at: resumeRoot) }
        let recordID = UUID().uuidString
        let store = BilliardsSessionStore(
            gameType: .eightBall,
            state: EightBallState.initial(targetPoints: 5),
            reducer: EightBallReducer(),
            participants: [
                .init(id: TeamID.team0.rawValue, name: "A", role: "team"),
                .init(id: TeamID.team1.rawValue, name: "B", role: "team")
            ],
            startedAt: Date(),
            recordID: recordID,
            resumeRepository: resumeRepository
        )
        let liveSaved = expectation(description: "live billiards resume saved")
        store.persistSnapshot { success in
            XCTAssertTrue(success)
            liveSaved.fulfill()
        }
        await fulfillment(of: [liveSaved], timeout: 2)

        let finished = expectation(description: "billiards state finished")
        store.send(.finishMatch) { _, next, _ in
            XCTAssertTrue(next.finished)
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
        let flushed = expectation(description: "finished billiards operation flushed")
        store.flush { flushed.fulfill() }
        await fulfillment(of: [flushed], timeout: 2)

        let retained = try await resumeRepository.loadResumeBundle(
            sessionId: store.sessionId,
            as: ScoreSessionResumeBundle<EightBallState, EightBallEvent, EightBallIntent>.self
        )
        XCTAssertTrue(store.state.finished)
        XCTAssertEqual(retained?.currentSession.status, .live)
        XCTAssertFalse(retained?.currentSession.state.finished ?? true)
    }

    func testFreshRallyMatchKeepsFinishedRecordAndPersistsLiveResume() async {
        let finishedStore = RallySessionStore(
            leftName: "Old Left",
            rightName: "Old Right",
            gameType: .pingpong,
            rules: .pingPong()
        )
        let finished = expectation(description: "old match finished")
        finishedStore.send(.finish) { _ in finished.fulfill() }
        await fulfillment(of: [finished], timeout: 2)
        let oldFlushed = expectation(description: "old match persisted")
        finishedStore.flush { oldFlushed.fulfill() }
        await fulfillment(of: [oldFlushed], timeout: 2)

        let freshStore = finishedStore.makeFreshMatchStore()
        let freshSaved = expectation(description: "fresh match persisted")
        freshStore.persistSnapshot { success in
            XCTAssertTrue(success)
            freshSaved.fulfill()
        }
        await fulfillment(of: [freshSaved], timeout: 2)

        XCTAssertNotEqual(freshStore.sessionId, finishedStore.sessionId)
        XCTAssertEqual(
            ScoreboardRecordManager.shared.getRecordById(finishedStore.sessionId.uuidString)?.status,
            .finished
        )
        XCTAssertNil(
            ScoreboardRecordManager.shared.getRecordById(freshStore.sessionId.uuidString),
            "Live matches belong in ResumeSessionRepository, not the finished-record store"
        )
        XCTAssertNotNil(RallySessionStore(restoring: freshStore.sessionId))
        XCTAssertTrue(freshStore.actionTimeline.isEmpty)

        _ = ScoreboardRecordManager.shared.deleteRecord(finishedStore.sessionId.uuidString)
        _ = ScoreboardRecordManager.shared.deleteRecord(freshStore.sessionId.uuidString)
        try? await ResumeSessionRepository().remove(sessionId: finishedStore.sessionId)
        try? await ResumeSessionRepository().remove(sessionId: freshStore.sessionId)
    }

    func testUndoAfterRenameKeepsParticipantsAlignedWithRestoredState() async throws {
        let resumeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("rally-participant-undo-\(UUID().uuidString)", isDirectory: true)
        let resumeRepository = ResumeSessionRepository(rootURL: resumeRoot)
        defer { try? FileManager.default.removeItem(at: resumeRoot) }

        let rally = RallySessionStore(
            leftName: "Before Left",
            rightName: "Before Right",
            gameType: .pingpong,
            rules: .pingPong(),
            resumeRepository: resumeRepository
        )
        defer { _ = ScoreboardRecordManager.shared.deleteRecord(rally.sessionId.uuidString) }
        let renamed = expectation(description: "rally renamed")
        rally.send(.setNames(left: "After Left", right: "After Right")) { _ in renamed.fulfill() }
        await fulfillment(of: [renamed], timeout: 2)
        let rallyUndone = expectation(description: "rally rename undone")
        rally.undo { success in XCTAssertTrue(success); rallyUndone.fulfill() }
        await fulfillment(of: [rallyUndone], timeout: 2)
        let rallyFlushed = expectation(description: "rally undo persisted")
        rally.flush { rallyFlushed.fulfill() }
        await fulfillment(of: [rallyFlushed], timeout: 2)
        let rallyBundle = try await resumeRepository.loadResumeBundle(
            sessionId: rally.sessionId,
            as: ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>.self
        )
        XCTAssertEqual(rally.state.leftName, "Before Left")
        XCTAssertEqual(rallyBundle?.currentSession.participants.map(\.name), ["Before Left", "Before Right"])

        let tennis = TennisSessionStore(
            leftName: "Before Left",
            rightName: "Before Right",
            resumeRepository: resumeRepository
        )
        defer { _ = ScoreboardRecordManager.shared.deleteRecord(tennis.sessionId.uuidString) }
        let tennisRenamed = expectation(description: "tennis renamed")
        tennis.send(.setNames(left: "After Left", right: "After Right")) { _ in tennisRenamed.fulfill() }
        await fulfillment(of: [tennisRenamed], timeout: 2)
        let tennisUndone = expectation(description: "tennis rename undone")
        tennis.undo { success in XCTAssertTrue(success); tennisUndone.fulfill() }
        await fulfillment(of: [tennisUndone], timeout: 2)
        let tennisFlushed = expectation(description: "tennis undo persisted")
        tennis.flush { tennisFlushed.fulfill() }
        await fulfillment(of: [tennisFlushed], timeout: 2)
        let tennisBundle = try await resumeRepository.loadResumeBundle(
            sessionId: tennis.sessionId,
            as: ScoreSessionResumeBundle<TennisMatchState, TennisMatchEvent, TennisMatchIntent>.self
        )
        XCTAssertEqual(tennis.state.leftName, "Before Left")
        XCTAssertEqual(tennisBundle?.currentSession.participants.map(\.name), ["Before Left", "Before Right"])

        let basketball = BasketballSessionStore(
            leftName: "Before Left",
            rightName: "Before Right",
            resumeRepository: resumeRepository
        )
        defer { _ = ScoreboardRecordManager.shared.deleteRecord(basketball.sessionId.uuidString) }
        basketball.send(.rename(side: .left, name: "After Left"))
        let basketballFlushed = expectation(description: "basketball renamed")
        basketball.flush { basketballFlushed.fulfill() }
        await fulfillment(of: [basketballFlushed], timeout: 2)
        let basketballUndone = expectation(description: "basketball rename undone")
        basketball.undo { success in XCTAssertTrue(success); basketballUndone.fulfill() }
        await fulfillment(of: [basketballUndone], timeout: 2)
        let basketballUndoFlushed = expectation(description: "basketball undo persisted")
        basketball.flush { basketballUndoFlushed.fulfill() }
        await fulfillment(of: [basketballUndoFlushed], timeout: 2)
        let basketballBundle = try await resumeRepository.loadResumeBundle(
            sessionId: basketball.sessionId,
            as: ScoreSessionResumeBundle<BasketballMatchState, BasketballMatchEvent, BasketballMatchIntent>.self
        )
        XCTAssertEqual(basketball.state.leftName, "Before Left")
        XCTAssertEqual(basketballBundle?.currentSession.participants.map(\.name), ["Before Left", "Before Right"])
    }

    func testPingPongDecidingSwitchPointIsHalfTarget() {
        var rules = RallyRuleSet.pingPong()
        let target = 11
        rules.pointsToWinSet = target
        rules.decidingSetSideSwitchPoint = RallyRuleSet.decidingSetSideSwitchPoint(for: .pingpong, pointsPerSet: target)
        XCTAssertEqual(rules.decidingSetSideSwitchPoint, 5)
    }

    func testRallyMatchStateRoundTripsThroughJSONSnapshot() throws {
        var rules = RallyRuleSet.pingPong(maxSets: 5)
        rules.autoChangeSides = true
        rules.decidingSetSideSwitchPoint = 5
        var state = RallyMatchEngine.initial(leftName: "红方", rightName: "蓝方", rules: rules)
        state.leftPoints = 7
        state.rightPoints = 5
        state.leftSets = 1
        state.sidesSwapped = true

        let data = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(RallyMatchState.self, from: data)

        XCTAssertEqual(restored.leftPoints, 7)
        XCTAssertEqual(restored.rightPoints, 5)
        XCTAssertEqual(restored.leftSets, 1)
        XCTAssertTrue(restored.sidesSwapped)
        XCTAssertEqual(restored.rules.decidingSetSideSwitchPoint, 5)
    }

    func testRallyCompletedRecordSnapshotDecoderAcceptsHistoricalShapes() throws {
        var state = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: .badminton())
        state.leftPoints = 9
        state.rightPoints = 7
        let session = ScoreSession<RallyMatchState, RallyMatchEvent>(
            gameType: .badminton,
            ruleFamily: .s1,
            reducerType: ScoreboardKernelRegistry.descriptor(for: .badminton).reducerType,
            state: state
        )
        let bundle = ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>(
            replaySeed: session,
            currentSession: session,
            undoFrames: [],
            timeline: []
        )

        XCTAssertEqual(
            decodeRallyStateSnapshot(try JSONEncoder().encode(state))?.leftPoints,
            9
        )
        XCTAssertEqual(
            decodeRallyStateSnapshot(try JSONEncoder().encode(session))?.rightPoints,
            7
        )
        XCTAssertEqual(
            decodeRallyStateSnapshot(try JSONEncoder().encode(bundle))?.leftName,
            "A"
        )
    }

    func testTennisPlayAllAcceptsEvenSetsAndFinishesInDraw() {
        let reducer = TennisMatchReducer()
        var state = TennisMatchState(
            leftName: "A",
            rightName: "B",
            rules: .init(maxSets: 4, matchCompletionMode: .playAll, autoChangeSides: false)
        )

        state = reducer.reduce(state: state, intent: .adjustSets(side: .left, delta: 1), at: 1).state
        state = reducer.reduce(state: state, intent: .adjustSets(side: .left, delta: 1), at: 2).state
        state = reducer.reduce(state: state, intent: .adjustSets(side: .right, delta: 1), at: 3).state
        XCTAssertFalse(state.rules.isMatchFinished(leftSets: state.leftSets, rightSets: state.rightSets))
        state = reducer.reduce(state: state, intent: .adjustSets(side: .right, delta: 1), at: 4).state

        XCTAssertTrue(state.rules.isMatchFinished(leftSets: state.leftSets, rightSets: state.rightSets))
        XCTAssertEqual(state.leftSets, 2)
        XCTAssertEqual(state.rightSets, 2)
    }

    func testTennisClassicStillFinishesEarly() {
        let reducer = TennisMatchReducer()
        var state = TennisMatchState(
            leftName: "A",
            rightName: "B",
            rules: .init(maxSets: 5, matchCompletionMode: .bestOf, autoChangeSides: false)
        )

        state = reducer.reduce(state: state, intent: .adjustSets(side: .left, delta: 1), at: 1).state
        state = reducer.reduce(state: state, intent: .adjustSets(side: .left, delta: 1), at: 2).state
        state = reducer.reduce(state: state, intent: .adjustSets(side: .left, delta: 1), at: 3).state

        XCTAssertTrue(state.rules.isMatchFinished(leftSets: state.leftSets, rightSets: state.rightSets))
        XCTAssertEqual(state.leftSets, 3)
    }

    func testTennisTieBreakServeUsesOneThenTwoPointBlocks() {
        let reducer = TennisMatchReducer()
        var state = TennisMatchState(
            leftName: "A",
            rightName: "B",
            rules: .init(maxSets: 3, autoChangeSides: false),
            openingServer: .left
        )
        state.leftGames = 6
        state.rightGames = 6
        state.isTieBreak = true
        state.firstServerInSet = .left
        state.servingSide = .left
        state.leftPoints = 0
        state.rightPoints = 0

        XCTAssertEqual(state.servingSide, .left)
        state = reducer.reduce(state: state, intent: .pointWon(.left), at: 1).state
        XCTAssertEqual(state.servingSide, .right)
        state = reducer.reduce(state: state, intent: .pointWon(.right), at: 2).state
        XCTAssertEqual(state.servingSide, .right)
        state = reducer.reduce(state: state, intent: .pointWon(.left), at: 3).state
        XCTAssertEqual(state.servingSide, .left)
    }

    func testSportsSetupResultDefaultsMissingCompletionMode() throws {
        let oldJSON = Data(#"{"team1Name":"A","team2Name":"B","maxSets":5}"#.utf8)
        let restored = try JSONDecoder().decode(SportsSetupResult.self, from: oldJSON)

        XCTAssertNil(restored.matchCompletionMode)
        XCTAssertEqual(restored.maxSets, 5)
    }

    func testSnookerFrameSettlementPreservesTerminalScoresInEventBeforeNextFrameReset() {
        let reducer = SnookerReducer()
        let initial = SnookerState.initial(striker: .left, maxFrames: 3)
        let scored = reducer.reduce(
            state: initial,
            intent: .adminCorrect(left: 57, right: 42, striker: .left),
            at: 1
        ).state
        let result = reducer.reduce(
            state: scored,
            intent: .settleFrame(winner: .left),
            at: 2
        )

        XCTAssertEqual(result.events, [.frameSettled(winner: .left, frame: 1)])
        XCTAssertEqual(scored.leftScore, 57)
        XCTAssertEqual(scored.rightScore, 42)
        XCTAssertEqual(result.state.leftScore, 0)
        XCTAssertEqual(result.state.rightScore, 0)
        XCTAssertEqual(result.state.leftFrames, 1)
        XCTAssertEqual(result.state.currentFrame, 2)
    }
}
