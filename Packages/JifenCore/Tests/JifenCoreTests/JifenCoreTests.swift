import Foundation
import Testing
import ScoreCore
import SessionCore
import TimerCore
import PersistenceCore

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
