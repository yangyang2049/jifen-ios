import Foundation
import Testing
import ScoreCore
import SessionCore
import TimerCore
import PersistenceCore
import LinkCore

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
