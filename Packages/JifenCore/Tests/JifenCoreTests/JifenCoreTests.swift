import Foundation
import Testing
import ScoreCore
import SessionCore
import TimerCore
import PersistenceCore
import LinkCore
import RecordCore

private struct CounterReducer: DomainReducer {
    struct State: Codable, Equatable, Sendable { var value: Int }
    enum Intent: Codable, Sendable { case add(Int) }
    enum Event: Codable, Equatable, Sendable { case changed(Int) }

    func reduce(state: State, intent: Intent, at epochMilliseconds: Int64) -> ReduceResult<State, Event> {
        switch intent {
        case .add(let amount):
            let next = State(value: state.value + amount)
            return .init(state: next, events: [.changed(next.value)])
        }
    }
}

@Test func linkEnvelopeRoundTripsTheSessionProtocol() throws {
    let sessionId = UUID()
    let envelope = LinkEnvelope(
        sessionId: sessionId,
        kind: .stateSnapshot,
        sender: .phone,
        senderSequence: 4,
        sessionRevision: 7,
        sentAtEpochMilliseconds: 123,
        payload: Data([0x01, 0x02])
    )

    let decoded = try JSONDecoder().decode(LinkEnvelope<Data>.self, from: JSONEncoder().encode(envelope))
    #expect(decoded.sessionId == sessionId)
    #expect(decoded.kind == .stateSnapshot)
    #expect(decoded.sender == .phone)
    #expect(decoded.payload == Data([0x01, 0x02]))
}

@Test func linkedScoreboardSetupPreservesTheInitialState() throws {
    var state = BasketballMatchEngine.initial(leftName: "Home", rightName: "Away", gameMode: .threeXThree)
    state.leftScore = 14
    state.rightScore = 12
    state.gameTimeSeconds = 86
    state.shotTimeSeconds = 7

    let setup = LinkedScoreboardSetup(
        gameType: .threeBasketball,
        basketballThreeXThree: true,
        initialSnapshot: .basketball(state)
    )
    let decoded = try JSONDecoder().decode(LinkedScoreboardSetup.self, from: JSONEncoder().encode(setup))

    #expect(decoded == setup)
    guard case .basketball(let restored)? = decoded.initialSnapshot else {
        #expect(Bool(false))
        return
    }
    #expect(restored.leftName == "Home")
    #expect(restored.leftScore == 14)
    #expect(restored.gameTimeSeconds == 86)
}

@Test func linkedRallySetupPreservesSetsAndServer() throws {
    var state = RallyMatchEngine.initial(leftName: "Red", rightName: "Blue", rules: .pingPong(maxSets: 7))
    state.leftPoints = 10
    state.rightPoints = 9
    state.leftSets = 2
    state.rightSets = 1
    state.servingSide = .right

    let setup = LinkedScoreboardSetup(
        gameType: .pingpongDoubles,
        maxSets: 7,
        initialSnapshot: .rally(state)
    )
    let decoded = try JSONDecoder().decode(LinkedScoreboardSetup.self, from: JSONEncoder().encode(setup))

    guard case .rally(let restored)? = decoded.initialSnapshot else {
        #expect(Bool(false))
        return
    }
    #expect(restored == state)
    #expect(restored.rules.maxSets == 7)
    #expect(restored.servingSide == .right)
}

@Test func stateSnapshotEnvelopePreservesSessionAndRevision() throws {
    let sessionId = UUID()
    var state = RallyMatchEngine.initial(leftName: "Red", rightName: "Blue", rules: .badminton())
    state.leftPoints = 18
    state.rightPoints = 16

    let envelope = LinkEnvelope(
        sessionId: sessionId,
        kind: .stateSnapshot,
        sender: .phone,
        senderSequence: 9,
        sessionRevision: 4,
        sentAtEpochMilliseconds: 456,
        payload: LinkedScoreboardSetup(
            gameType: .badminton,
            maxSets: state.rules.maxSets,
            initialSnapshot: .rally(state)
        )
    )
    let decoded = try JSONDecoder().decode(
        LinkEnvelope<LinkedScoreboardSetup>.self,
        from: JSONEncoder().encode(envelope)
    )

    #expect(decoded.sessionId == sessionId)
    #expect(decoded.sessionRevision == 4)
    #expect(decoded.payload.initialSnapshot?.rallyState == state)
}

@Test func sessionUndoAndReplayUseOneTimeline() async throws {
    let seed = ScoreSession<CounterReducer.State, CounterReducer.Event>(
        gameType: .badminton,
        ruleFamily: .s1,
        reducerType: "test/counter",
        state: CounterReducer.State(value: 0)
    )
    let session = ScoreSessionCore(seedSession: seed, reducer: CounterReducer())

    _ = await session.dispatch(actorId: "phone", intent: CounterReducer.Intent.add(2), at: 1)
    _ = await session.dispatch(actorId: "watch", intent: CounterReducer.Intent.add(3), at: 2)
    #expect(await session.snapshot().state.value == 5)

    #expect(await session.undo(actorId: "watch"))
    #expect(await session.snapshot().state.value == 2)
    #expect(try await session.replay().state.value == 2)
}

@Test func standardBasketballClockOnlyAcceptsFourteenOrTwentyFour() {
    let reducer = BasketballClockReducer()
    let state = BasketballClockState(profile: .standard, gameClockSeconds: 600)

    let fourteen = reducer.reduce(state: state, intent: .resetShotClock(seconds: 14), at: 0)
    #expect(fourteen.accepted)
    #expect(fourteen.state.shotClockSeconds == 14)

    let twelve = reducer.reduce(state: state, intent: .resetShotClock(seconds: 12), at: 0)
    #expect(!twelve.accepted)
}

@Test func threeByThreeBasketballClockUsesTwelveSeconds() {
    let reducer = BasketballClockReducer()
    let state = BasketballClockState(profile: .threeXThree, gameClockSeconds: 600)

    #expect(state.shotClockSeconds == 12)
    #expect(reducer.reduce(state: state, intent: .resetShotClock(seconds: 12), at: 0).accepted)
}

@Test func basketballThreeByThreeEndsAtTwentyOneAndUsesTwelveSecondShotClock() {
    let reducer = BasketballMatchReducer()
    var state = BasketballMatchEngine.initial(leftName: "Home", rightName: "Away", gameMode: .threeXThree)

    #expect(state.shotTimeSeconds == 12)
    #expect(BasketballMatchEngine.scoringButtons(state) == [1, 2])

    for _ in 0..<10 {
        state = reducer.reduce(
            state: state,
            intent: .addPoints(side: .left, points: 2),
            at: 0
        ).state
    }
    state = reducer.reduce(state: state, intent: .addPoints(side: .left, points: 1), at: 0).state

    #expect(state.leftScore == 21)
    #expect(state.finished)
    #expect(!state.gameRunning)
}

@Test func basketballFiveByFiveTieAtFinalBuzzerStartsOvertime() {
    var state = BasketballMatchEngine.initial(leftName: "Home", rightName: "Away", gameMode: .fiveVFive)
    state.leftScore = 88
    state.rightScore = 88
    state.currentPeriod = 4
    state.gameTimeSeconds = 1
    state.shotTimeSeconds = 8
    state.gameRunning = true
    state.shotRunning = true

    let next = BasketballMatchEngine.tickClock(state)
    #expect(!next.finished)
    #expect(next.isOvertime)
    #expect(next.gameTimeSeconds == BasketballMatchEngine.overtimeSeconds())
    #expect(next.overtimeStartScore == 88)
}

@Test func basketballScoreResetsShotClockWithoutStoppingGameClock() {
    let reducer = BasketballMatchReducer()
    var state = BasketballMatchEngine.initial(leftName: "Home", rightName: "Away", gameMode: .fiveVFive)
    state.shotTimeSeconds = 8
    state.gameRunning = true
    state.shotRunning = true

    let next = reducer.reduce(state: state, intent: .addPoints(side: .left, points: 2), at: 0).state
    #expect(next.leftScore == 2)
    #expect(next.shotTimeSeconds == 24)
    #expect(next.gameRunning)
}

@Test func pingPongUsesTwoServeTurnsThenOneServeAtDeuce() {
    let reducer = RallyMatchReducer()
    var state = RallyMatchEngine.initial(
        leftName: "Red",
        rightName: "Blue",
        rules: .pingPong(maxSets: 5),
        openingServer: .left
    )

    state = reducer.reduce(state: state, intent: .pointWon(.left), at: 1).state
    #expect(state.servingSide == .left)
    state = reducer.reduce(state: state, intent: .pointWon(.right), at: 2).state
    #expect(state.servingSide == .right)

    state.leftPoints = 10
    state.rightPoints = 9
    state = reducer.reduce(state: state, intent: .pointWon(.right), at: 3).state
    #expect(state.leftPoints == 10)
    #expect(state.rightPoints == 10)
    #expect(state.servingSide == .left)
    state = reducer.reduce(state: state, intent: .pointWon(.left), at: 4).state
    #expect(state.servingSide == .right)
}

@Test func badmintonCapsAtThirtyAndCompletesTheSet() {
    let reducer = RallyMatchReducer()
    var state = RallyMatchEngine.initial(leftName: "Red", rightName: "Blue", rules: .badminton())
    state.leftPoints = 29
    state.rightPoints = 29

    let result = reducer.reduce(state: state, intent: .pointWon(.left), at: 1)
    #expect(result.state.leftPoints == 0)
    #expect(result.state.rightPoints == 0)
    #expect(result.state.leftSets == 1)
    #expect(result.events.contains(.setCompleted(
        winner: .left,
        setNumber: 1,
        leftPoints: 30,
        rightPoints: 29,
        leftSets: 1,
        rightSets: 0
    )))
}

@Test func pickleballSideOutChangesServerWithoutAddingAPoint() {
    let reducer = RallyMatchReducer()
    var state = RallyMatchEngine.initial(
        leftName: "Red",
        rightName: "Blue",
        rules: .pickleball(),
        openingServer: .left
    )

    state = reducer.reduce(state: state, intent: .pointWon(.right), at: 1).state
    #expect(state.leftPoints == 0)
    #expect(state.rightPoints == 0)
    #expect(state.servingSide == .right)

    state = reducer.reduce(state: state, intent: .pointWon(.right), at: 2).state
    #expect(state.rightPoints == 1)
    #expect(state.servingSide == .right)
}

@Test func pickleballFactoryHasNoDefaultPointCap() {
    #expect(RallyRuleSet.pickleball().pointCap == nil)
    #expect(RallyRuleSet.pickleball().nextSetServerModel == .opening)
}

@Test func pickleballSinglesNextSetUsesOpeningServer() {
    let reducer = RallyMatchReducer()
    var rules = RallyRuleSet.pickleball(maxSets: 3)
    rules.pointsToWinSet = 2
    rules.winByTwo = false
    var state = RallyMatchEngine.initial(
        leftName: "Red",
        rightName: "Blue",
        rules: rules,
        openingServer: .left
    )

    state = reducer.reduce(state: state, intent: .pointWon(.left), at: 1).state
    state = reducer.reduce(state: state, intent: .pointWon(.left), at: 2).state
    #expect(state.leftSets == 1)
    #expect(state.leftPoints == 0)
    #expect(state.servingSide == .left)
    #expect(state.firstServerInSet == .left)
}

@Test func pickleballDoublesStartsAtServerTwoAndRotates() {
    let reducer = RallyMatchReducer()
    var rules = RallyRuleSet.pickleball(maxSets: 3)
    rules.nextSetServerModel = .alternateFromOpening
    let doubles = RallyDoublesState.pickleball(
        playerNames: ["A", "C", "B", "D"],
        servingTeam0: true
    )
    var state = RallyMatchEngine.initial(
        leftName: "Red",
        rightName: "Blue",
        rules: rules,
        openingServer: .left,
        doubles: doubles
    )

    guard case .pickleball(let opening) = state.doubles?.rotation else {
        Issue.record("Expected pickleball doubles rotation")
        return
    }
    #expect(opening.serverNumber == 2)
    #expect(opening.isFirstServeOfGame)
    #expect(opening.team0PartnersSwapped == false)

    // First rally lost while still on opening second server → side-out to other team as server 1.
    state = reducer.reduce(state: state, intent: .pointWon(.right), at: 1).state
    #expect(state.leftPoints == 0)
    #expect(state.rightPoints == 0)
    #expect(state.servingSide == .right)
    guard case .pickleball(let afterFirstSideOut) = state.doubles?.rotation else {
        Issue.record("Expected pickleball doubles rotation")
        return
    }
    #expect(afterFirstSideOut.serverNumber == 1)
    #expect(afterFirstSideOut.isFirstServeOfGame == false)

    // Server 1 loses → server 2, same team.
    state = reducer.reduce(state: state, intent: .pointWon(.left), at: 2).state
    #expect(state.servingSide == .right)
    guard case .pickleball(let serverTwo) = state.doubles?.rotation else {
        Issue.record("Expected pickleball doubles rotation")
        return
    }
    #expect(serverTwo.serverNumber == 2)

    // Server 2 scores → point + partner swap.
    state = reducer.reduce(state: state, intent: .pointWon(.right), at: 3).state
    #expect(state.rightPoints == 1)
    #expect(state.servingSide == .right)
    guard case .pickleball(let afterScore) = state.doubles?.rotation else {
        Issue.record("Expected pickleball doubles rotation")
        return
    }
    #expect(afterScore.team1PartnersSwapped)
    #expect(afterScore.serverNumber == 2)

    // Server 2 loses → side-out back to left as server 1.
    state = reducer.reduce(state: state, intent: .pointWon(.left), at: 4).state
    #expect(state.servingSide == .left)
    guard case .pickleball(let backToLeft) = state.doubles?.rotation else {
        Issue.record("Expected pickleball doubles rotation")
        return
    }
    #expect(backToLeft.serverNumber == 1)
    #expect(backToLeft.team1PartnersSwapped)
}

@Test func pickleballDoublesNextSetAlternatesFromOpening() {
    let reducer = RallyMatchReducer()
    var rules = RallyRuleSet.pickleball(maxSets: 3)
    rules.pointsToWinSet = 2
    rules.winByTwo = false
    rules.nextSetServerModel = .alternateFromOpening
    var state = RallyMatchEngine.initial(
        leftName: "Red",
        rightName: "Blue",
        rules: rules,
        openingServer: .left,
        doubles: .pickleball(playerNames: ["A", "C", "B", "D"], servingTeam0: true)
    )

    state = reducer.reduce(state: state, intent: .pointWon(.left), at: 1).state
    state = reducer.reduce(state: state, intent: .pointWon(.left), at: 2).state
    #expect(state.leftSets == 1)
    #expect(state.servingSide == .right)
    guard case .pickleball(let nextSet) = state.doubles?.rotation else {
        Issue.record("Expected pickleball doubles rotation")
        return
    }
    #expect(nextSet.serverNumber == 2)
    #expect(nextSet.isFirstServeOfGame)
    #expect(nextSet.team0PartnersSwapped == false)
    #expect(nextSet.team1PartnersSwapped == false)
}

@Test func volleyballUsesFifteenPointsInTheDecidingSet() {
    let reducer = RallyMatchReducer()
    var state = RallyMatchEngine.initial(leftName: "Red", rightName: "Blue", rules: .volleyball())
    state.leftSets = 2
    state.rightSets = 2
    state.leftPoints = 14
    state.rightPoints = 13

    let result = reducer.reduce(state: state, intent: .pointWon(.left), at: 1)
    #expect(result.state.leftSets == 3)
    #expect(result.state.finished)
    #expect(result.events.contains(.setCompleted(
        winner: .left,
        setNumber: 5,
        leftPoints: 15,
        rightPoints: 13,
        leftSets: 3,
        rightSets: 2
    )))
}

@Test func volleyballVariantsUseAlternateFromOpeningNextSetServer() {
    #expect(RallyRuleSet.volleyball().nextSetServerModel == .alternateFromOpening)
    #expect(RallyRuleSet.airVolleyball().nextSetServerModel == .alternateFromOpening)
    #expect(RallyRuleSet.beachVolleyball().nextSetServerModel == .alternateFromOpening)
}

@Test func volleyballNextSetAlternatesFromOpeningServer() {
    let reducer = RallyMatchReducer()
    var rules = RallyRuleSet.volleyball(maxSets: 5)
    rules.pointsToWinSet = 2
    rules.winByTwo = false
    var state = RallyMatchEngine.initial(
        leftName: "Red",
        rightName: "Blue",
        rules: rules,
        openingServer: .left
    )

    state = reducer.reduce(state: state, intent: .pointWon(.left), at: 1).state
    state = reducer.reduce(state: state, intent: .pointWon(.left), at: 2).state
    #expect(state.leftSets == 1)
    #expect(state.servingSide == .right)
    #expect(state.firstServerInSet == .right)
}

@Test func beachVolleyballSwitchesSidesEverySevenTotalPoints() {
    let reducer = RallyMatchReducer()
    var rules = RallyRuleSet.beachVolleyball()
    rules.autoChangeSides = true
    var state = RallyMatchEngine.initial(leftName: "Red", rightName: "Blue", rules: rules)

    // 3-3 → total 6; next point makes total 7 → sides exchanged
    state.leftPoints = 3
    state.rightPoints = 3
    let before = state.sidesSwapped
    let result = reducer.reduce(state: state, intent: .pointWon(.left), at: 1)
    #expect(result.state.leftPoints + result.state.rightPoints == 7)
    #expect(result.state.sidesSwapped != before)
    #expect(result.events.contains(.sidesExchanged))
}

@Test func indoorVolleyballSwitchesSidesAtEightInDecidingSet() {
    let reducer = RallyMatchReducer()
    var rules = RallyRuleSet.volleyball()
    rules.autoChangeSides = true
    var state = RallyMatchEngine.initial(leftName: "Red", rightName: "Blue", rules: rules)
    state.leftSets = 2
    state.rightSets = 2
    state.leftPoints = 7
    state.rightPoints = 5
    let before = state.sidesSwapped

    let result = reducer.reduce(state: state, intent: .pointWon(.left), at: 1)
    #expect(result.state.leftPoints == 8)
    #expect(result.state.sidesSwapped != before)
    #expect(result.events.contains(.sidesExchanged))
}

@Test func rallyMatchUndoRestoresThePreviousPoint() async {
    let seed = ScoreSession<RallyMatchState, RallyMatchEvent>(
        gameType: .pingpong,
        ruleFamily: .s1,
        reducerType: "rally/v1",
        state: RallyMatchEngine.initial(leftName: "Red", rightName: "Blue", rules: .pingPong())
    )
    let session = ScoreSessionCore(seedSession: seed, reducer: RallyMatchReducer())

    _ = await session.dispatch(actorId: "phone", intent: .pointWon(.left), at: 1)
    _ = await session.dispatch(actorId: "phone", intent: .pointWon(.right), at: 2)
    #expect(await session.undo(actorId: "phone"))
    let state = await session.snapshot().state
    #expect(state.leftPoints == 1)
    #expect(state.rightPoints == 0)
}

@Test func automaticBasketballClockTicksDoNotConsumeScoreUndo() async {
    let seed = ScoreSession<BasketballMatchState, BasketballMatchEvent>(
        gameType: .basketball,
        ruleFamily: .s2,
        reducerType: "basketball/v1",
        state: BasketballMatchEngine.initial(leftName: "Home", rightName: "Away", gameMode: .fiveVFive)
    )
    let session = ScoreSessionCore(seedSession: seed, reducer: BasketballMatchReducer())

    _ = await session.dispatch(actorId: "phone", intent: .setClockRunning(true), at: 1)
    _ = await session.dispatch(actorId: "phone", intent: .addPoints(side: .left, points: 2), at: 2)
    _ = await session.dispatchNonUndoable(actorId: "phone", intent: .tickClock, at: 3)

    #expect(await session.undo(actorId: "phone"))
    let state = await session.snapshot().state
    #expect(state.leftScore == 0)
    #expect(state.gameRunning)
    #expect(await session.intentTimeline().count == 1)
    let replayed = try? await session.replay()
    #expect(replayed?.state.leftScore == 0)
    #expect(replayed?.state.gameTimeSeconds == 600)
}

@Test func sessionReplayNormalizesRestoredSeedVersionAndEvents() async throws {
    let seed = ScoreSession<CounterReducer.State, CounterReducer.Event>(
        gameType: .badminton,
        ruleFamily: .s1,
        reducerType: "test/counter",
        version: 12,
        state: CounterReducer.State(value: 40),
        events: [.changed(40)],
        status: .finished
    )
    let session = ScoreSessionCore(seedSession: seed, reducer: CounterReducer())

    _ = await session.dispatch(actorId: "phone", intent: .add(2), at: 1)
    let replayed = try await session.replay()

    #expect(replayed.version == 1)
    #expect(replayed.state.value == 42)
    #expect(replayed.events == [.changed(42)])
    #expect(replayed.status == .live)
}

@Test func atomicStoreCreatesAndReplacesItsFirstRecord() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let url = directory.appendingPathComponent("session.json")
    let store = AtomicJSONFileStore<Int>(fileURL: url)

    try await store.save(1)
    #expect(try await store.load() == 1)

    try await store.save(2)
    #expect(try await store.load() == 2)
}

@Test func sessionArchiveIndexUpsertsAndOrdersEntries() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let index = SessionArchiveIndex(fileURL: directory.appendingPathComponent("index.json"))
    let firstID = UUID()
    let secondID = UUID()

    try await index.upsert(.init(
        sessionId: firstID,
        gameType: .pingpong,
        source: .phoneLocal,
        snapshotPath: "sessions/one.json",
        participants: [],
        status: .live,
        updatedAtEpochMilliseconds: 10
    ))
    try await index.upsert(.init(
        sessionId: secondID,
        gameType: .basketball,
        source: .watchLocal,
        snapshotPath: "watch-sessions/two.json",
        participants: [],
        status: .finished,
        updatedAtEpochMilliseconds: 20
    ))

    let entries = try await index.entries()
    #expect(entries.map(\.sessionId) == [secondID, firstID])
}

@Test func canonicalGameTypeDecoderMigratesLegacyIdentifiers() throws {
    let decoder = JSONDecoder()
    #expect(try decoder.decode(GameType.self, from: Data("\"archery\"".utf8)) == .archeryDual)
    #expect(try decoder.decode(GameType.self, from: Data("\"simpleScore\"".utf8)) == .simpleScore)
    #expect(try decoder.decode(GameType.self, from: Data("\"multiScoreboard\"".utf8)) == .multiScoreboard)
    #expect(String(data: try JSONEncoder().encode(GameType.archeryDual), encoding: .utf8) == "\"archery_dual\"")
}

@Test func versionedRecordPreservesSnapshotAndTombstoneMetadata() throws {
    let sessionID = UUID()
    let actorID = UUID()
    let record = ScoreRecordV2(
        sessionId: sessionID,
        gameType: .simpleScore,
        source: .phoneLocal,
        startedAtEpochMilliseconds: 100,
        payload: .twoSide(.init(leftName: "A", rightName: "B", leftScore: -2, rightScore: 4)),
        actions: [.init(kind: .scoreChanged, epochMilliseconds: 120, summary: "A -1")],
        configuration: Data("{\"allowNegative\":true}".utf8),
        stateSnapshot: Data("{\"leftScore\":-2}".utf8),
        syncMetadata: .init(actorID: actorID, revision: 3, updatedAtEpochMilliseconds: 130),
        deletedAtEpochMilliseconds: 150
    )
    let decoded = try JSONDecoder().decode(ScoreRecordV2.self, from: JSONEncoder().encode(record))
    #expect(decoded.schemaVersion == 3)
    #expect(decoded.sessionId == sessionID)
    #expect(decoded.stateSnapshot == record.stateSnapshot)
    #expect(decoded.syncMetadata?.actorID == actorID)
    #expect(decoded.deletedAtEpochMilliseconds == 150)
}

@Test func localRecordSyncStorePersistsQueueAndCursor() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let url = directory.appendingPathComponent("record-sync.json")
    let store = LocalRecordSyncStore(fileURL: url)
    let mutation = RecordSyncMutation(
        recordID: UUID(),
        actorID: UUID(),
        revision: 1,
        updatedAtEpochMilliseconds: 200,
        kind: .delete,
        payload: nil
    )
    try await store.enqueue(mutation)
    #expect(try await store.pendingMutations(limit: 10) == [mutation])
    try await store.acknowledge(ids: Set([mutation.id]), cursor: "cursor-1")
    #expect(try await store.pendingMutations(limit: 10).isEmpty)
    #expect(try await store.syncCursor() == "cursor-1")
}

@Test func foosballUsesFivePointSetsByDefault() {
    let rules = RallyRuleSet.foosball()
    #expect(rules.pointsToWinSet == 5)
    #expect(rules.maxSets == 3)
    #expect(!rules.winByTwo)
}

@Test func foosballDecidingSetWinByTwoAndCapOnlyApplyToFinalSet() {
    var rules = RallyRuleSet.foosball(maxSets: 3)
    rules.finalSetWinByTwo = true
    rules.finalSetPointCap = 8
    let reducer = RallyMatchReducer()

    var openingSet = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: rules)
    openingSet.leftPoints = 4
    openingSet.rightPoints = 4
    openingSet = reducer.reduce(state: openingSet, intent: .pointWon(.left), at: 1).state
    #expect(openingSet.leftSets == 1)

    var decidingSet = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: rules)
    decidingSet.leftSets = 1
    decidingSet.rightSets = 1
    decidingSet.leftPoints = 4
    decidingSet.rightPoints = 4
    decidingSet = reducer.reduce(state: decidingSet, intent: .pointWon(.left), at: 2).state
    #expect(decidingSet.leftSets == 1)
    #expect(decidingSet.leftPoints == 5)
    decidingSet = reducer.reduce(state: decidingSet, intent: .pointWon(.left), at: 3).state
    #expect(decidingSet.finished)

    var cappedSet = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: rules)
    cappedSet.leftSets = 1
    cappedSet.rightSets = 1
    cappedSet.leftPoints = 7
    cappedSet.rightPoints = 7
    cappedSet = reducer.reduce(state: cappedSet, intent: .pointWon(.right), at: 4).state
    #expect(cappedSet.finished)
    #expect(cappedSet.rightSets == 2)
}

@Test func foosballDoublesKeepsFourFixedCornerNames() {
    let names = ["红A", "蓝A", "红B", "蓝B"]
    let doubles = RallyDoublesState.foosball(playerNames: names)
    var state = RallyMatchEngine.initial(
        leftName: "红队",
        rightName: "蓝队",
        rules: .foosball(),
        doubles: doubles
    )
    let reducer = RallyMatchReducer()
    state = reducer.reduce(state: state, intent: .pointWon(.left), at: 1).state
    #expect(state.doubles?.playerNames == names)
    let retainsFoosballIdentity: Bool
    if case .some(.foosball) = state.doubles?.rotation { retainsFoosballIdentity = true }
    else { retainsFoosballIdentity = false }
    #expect(retainsFoosballIdentity)
    state = reducer.reduce(state: state, intent: .reset, at: 2).state
    #expect(state.doubles?.playerNames == names)
}

@Test func sessionArchiveRepositoryOwnsSnapshotIndexAndDeletion() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let repository = SessionArchiveRepository(rootURL: root)
    let state = LineScoreState(leftName: "A", rightName: "B", rules: .freeCounter, leftScore: -2, rightScore: 4)
    let session = ScoreSession<LineScoreState, LineScoreEvent>(
        gameType: .simpleScore,
        ruleFamily: .s1,
        reducerType: "line/v1",
        state: state
    )

    try await repository.save(session, updatedAtEpochMilliseconds: 100)
    #expect(try await repository.entries().map(\.sessionId) == [session.sessionId])
    let restored: ScoreSession<LineScoreState, LineScoreEvent>? = try await repository.load(sessionId: session.sessionId)
    #expect(restored?.state == state)

    try await repository.remove(sessionId: session.sessionId)
    #expect(try await repository.entries().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: SessionArchiveRepository.snapshotURL(sessionId: session.sessionId, rootURL: root).path))
}
