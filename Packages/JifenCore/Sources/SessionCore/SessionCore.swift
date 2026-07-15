import Foundation
import ScoreCore

public struct ScoreSession<State: Codable & Sendable, Event: Codable & Sendable>: Codable, Sendable {
    public let sessionId: UUID
    public let gameType: GameType
    public let ruleFamily: RuleFamily
    public let reducerType: String
    public let version: UInt64
    public let state: State
    public let events: [Event]
    public let status: SessionStatus
    public let participants: [SessionParticipant]
    public let metadata: SessionMetadata

    public init(
        sessionId: UUID = UUID(),
        gameType: GameType,
        ruleFamily: RuleFamily,
        reducerType: String,
        version: UInt64 = 0,
        state: State,
        events: [Event] = [],
        status: SessionStatus = .live,
        participants: [SessionParticipant] = [],
        metadata: SessionMetadata = .init()
    ) {
        self.sessionId = sessionId
        self.gameType = gameType
        self.ruleFamily = ruleFamily
        self.reducerType = reducerType
        self.version = version
        self.state = state
        self.events = events
        self.status = status
        self.participants = participants
        self.metadata = metadata
    }
}

public struct SessionIntentRecord<Intent: Codable & Sendable>: Codable, Sendable {
    public let actorId: String
    public let intent: Intent
    public let epochMilliseconds: Int64

    public init(actorId: String, intent: Intent, epochMilliseconds: Int64) {
        self.actorId = actorId
        self.intent = intent
        self.epochMilliseconds = epochMilliseconds
    }
}

public enum DispatchResult<State: Codable & Sendable, Event: Codable & Sendable>: Sendable {
    case accepted(session: ScoreSession<State, Event>, events: [Event])
    case rejected(session: ScoreSession<State, Event>, reason: String)
}

public actor ScoreSessionCore<Reducer: DomainReducer> {
    public typealias State = Reducer.State
    public typealias Intent = Reducer.Intent
    public typealias Event = Reducer.Event

    private struct UndoFrame: Sendable {
        let session: ScoreSession<State, Event>
        let intentCount: Int
    }

    private let seedSession: ScoreSession<State, Event>
    private let reducer: Reducer
    private let canDispatch: @Sendable (String, Intent) -> Bool
    private let canUndo: @Sendable (String) -> Bool
    private let shouldFinish: @Sendable (Intent, State) -> Bool
    private var currentSession: ScoreSession<State, Event>
    private var undoStack: [UndoFrame] = []
    private var timeline: [SessionIntentRecord<Intent>] = []

    public init(
        seedSession: ScoreSession<State, Event>,
        reducer: Reducer,
        canDispatch: @escaping @Sendable (String, Intent) -> Bool = { _, _ in true },
        canUndo: @escaping @Sendable (String) -> Bool = { _ in true },
        shouldFinish: @escaping @Sendable (Intent, State) -> Bool = { _, _ in false }
    ) {
        self.seedSession = seedSession
        self.reducer = reducer
        self.canDispatch = canDispatch
        self.canUndo = canUndo
        self.shouldFinish = shouldFinish
        self.currentSession = seedSession
    }

    public func snapshot() -> ScoreSession<State, Event> {
        currentSession
    }

    public func intentTimeline() -> [SessionIntentRecord<Intent>] {
        timeline
    }

    public func dispatch(
        actorId: String,
        intent: Intent,
        at epochMilliseconds: Int64
    ) -> DispatchResult<State, Event> {
        dispatch(actorId: actorId, intent: intent, at: epochMilliseconds, recordsUndo: true)
    }

    public func dispatchNonUndoable(
        actorId: String,
        intent: Intent,
        at epochMilliseconds: Int64
    ) -> DispatchResult<State, Event> {
        dispatch(actorId: actorId, intent: intent, at: epochMilliseconds, recordsUndo: false)
    }

    private func dispatch(
        actorId: String,
        intent: Intent,
        at epochMilliseconds: Int64,
        recordsUndo: Bool
    ) -> DispatchResult<State, Event> {
        guard canDispatch(actorId, intent) else {
            return .rejected(session: currentSession, reason: "Permission denied")
        }

        let result = reducer.reduce(state: currentSession.state, intent: intent, at: epochMilliseconds)
        guard result.accepted else {
            return .rejected(session: currentSession, reason: result.reason ?? "Rule rejected")
        }

        if recordsUndo {
            undoStack.append(UndoFrame(session: currentSession, intentCount: 1))
        }
        let status: SessionStatus = shouldFinish(intent, result.state) ? .finished : currentSession.status
        currentSession = ScoreSession(
            sessionId: currentSession.sessionId,
            gameType: currentSession.gameType,
            ruleFamily: currentSession.ruleFamily,
            reducerType: currentSession.reducerType,
            version: currentSession.version + 1,
            state: result.state,
            events: currentSession.events + result.events,
            status: status,
            participants: currentSession.participants,
            metadata: currentSession.metadata
        )
        timeline.append(.init(actorId: actorId, intent: intent, epochMilliseconds: epochMilliseconds))
        return .accepted(session: currentSession, events: result.events)
    }

    public func undo(actorId: String) -> Bool {
        guard canUndo(actorId), let frame = undoStack.popLast() else {
            return false
        }
        currentSession = frame.session
        if frame.intentCount > 0 {
            timeline.removeLast(min(frame.intentCount, timeline.count))
        }
        return true
    }

    public func replay() throws -> ScoreSession<State, Event> {
        var session = seedSession
        for record in timeline {
            let result = reducer.reduce(
                state: session.state,
                intent: record.intent,
                at: record.epochMilliseconds
            )
            guard result.accepted else {
                throw ReplayError.rejectedIntent(reason: result.reason ?? "Rule rejected")
            }
            session = ScoreSession(
                sessionId: session.sessionId,
                gameType: session.gameType,
                ruleFamily: session.ruleFamily,
                reducerType: session.reducerType,
                version: session.version + 1,
                state: result.state,
                events: session.events + result.events,
                status: shouldFinish(record.intent, result.state) ? .finished : session.status,
                participants: session.participants,
                metadata: session.metadata
            )
        }
        return session
    }
}

public enum ReplayError: Error, Equatable, Sendable {
    case rejectedIntent(reason: String)
}
