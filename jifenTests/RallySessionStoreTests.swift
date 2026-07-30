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

    func testBasketballAuthoritativeRebaseRejectsStaleRevision() async {
        let store = BasketballSessionStore(leftName: "A", rightName: "B")
        var remote = store.state
        remote.leftScore = 12
        remote.rightScore = 8

        let applied = await store.applyAuthoritativeState(remote, detailedActions: [], revision: 9)
        XCTAssertTrue(applied)
        XCTAssertEqual(store.state.leftScore, 12)

        var stale = remote
        stale.leftScore = 2
        let staleApplied = await store.applyAuthoritativeState(stale, detailedActions: [], revision: 8)
        XCTAssertFalse(staleApplied)
        XCTAssertEqual(store.state.leftScore, 12)
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

    func testTennisDoublesArchiveKeepsAllFourPlayerIdentities() async throws {
        let archiveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("tennis-doubles-archive-\(UUID().uuidString)", isDirectory: true)
        let archiveRepository = SessionArchiveRepository(rootURL: archiveRoot)
        defer { try? FileManager.default.removeItem(at: archiveRoot) }

        let state = TennisMatchState(
            leftName: "红队",
            rightName: "蓝队",
            doublesPlayerNames: ["红A", "蓝A", "红B", "蓝B"]
        )
        let store = TennisSessionStore(
            gameType: .tennisDoubles,
            state: state,
            archiveRepository: archiveRepository
        )
        store.persistSnapshot()
        let flushed = expectation(description: "tennis doubles archive flushed")
        store.flush { flushed.fulfill() }
        await fulfillment(of: [flushed], timeout: 2)

        let bundle = try await archiveRepository.loadResumeBundle(
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
            voiceAnnouncementEnabled: true
        )
        let freshRally = rally.makeFreshMatchStore()
        XCTAssertNotEqual(freshRally.sessionId, rally.sessionId)
        XCTAssertEqual(freshRally.state.rules, rally.state.rules)
        XCTAssertEqual(freshRally.state.doubles?.playerNames, rally.state.doubles?.playerNames)
        XCTAssertEqual(freshRally.state.openingServerSide, .right)
        XCTAssertTrue(freshRally.voiceAnnouncementEnabled)

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
        XCTAssertEqual(
            ScoreboardRecordManager.shared.getRecordById(freshStore.sessionId.uuidString)?.status,
            .draft
        )
        XCTAssertNotNil(RallySessionStore(restoring: freshStore.sessionId))
        XCTAssertTrue(freshStore.actionTimeline.isEmpty)

        _ = ScoreboardRecordManager.shared.deleteRecord(finishedStore.sessionId.uuidString)
        _ = ScoreboardRecordManager.shared.deleteRecord(freshStore.sessionId.uuidString)
        try? await SessionArchiveRepository().remove(sessionId: finishedStore.sessionId)
        try? await SessionArchiveRepository().remove(sessionId: freshStore.sessionId)
    }

    func testUndoAfterRenameKeepsParticipantsAlignedWithRestoredState() async throws {
        let archiveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("rally-participant-undo-\(UUID().uuidString)", isDirectory: true)
        let archiveRepository = SessionArchiveRepository(rootURL: archiveRoot)
        defer { try? FileManager.default.removeItem(at: archiveRoot) }

        let rally = RallySessionStore(
            leftName: "Before Left",
            rightName: "Before Right",
            gameType: .pingpong,
            rules: .pingPong(),
            archiveRepository: archiveRepository
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
        let rallyBundle = try await archiveRepository.loadResumeBundle(
            sessionId: rally.sessionId,
            as: ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>.self
        )
        XCTAssertEqual(rally.state.leftName, "Before Left")
        XCTAssertEqual(rallyBundle?.currentSession.participants.map(\.name), ["Before Left", "Before Right"])

        let tennis = TennisSessionStore(
            leftName: "Before Left",
            rightName: "Before Right",
            archiveRepository: archiveRepository
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
        let tennisBundle = try await archiveRepository.loadResumeBundle(
            sessionId: tennis.sessionId,
            as: ScoreSessionResumeBundle<TennisMatchState, TennisMatchEvent, TennisMatchIntent>.self
        )
        XCTAssertEqual(tennis.state.leftName, "Before Left")
        XCTAssertEqual(tennisBundle?.currentSession.participants.map(\.name), ["Before Left", "Before Right"])

        let basketball = BasketballSessionStore(
            leftName: "Before Left",
            rightName: "Before Right",
            archiveRepository: archiveRepository
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
        let basketballBundle = try await archiveRepository.loadResumeBundle(
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

    func testRallyLegacyDraftDecoderAcceptsRawSessionAndResumeBundle() throws {
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
}
