import Foundation
import PersistenceCore
import RecordCore
import ScoreCore
import SessionCore

/// Bridges Watch scoreboards that still keep lightweight view-local undo state
/// into the shared v2 session archive. ScoreSessionCore is not required for
/// persistence; the repository accepts an authoritative typed snapshot.
enum WatchSessionArchiveSupport {
    static func makeSession<State: Codable & Sendable, Event: Codable & Sendable>(
        sessionId: UUID,
        gameType: GameType,
        state: State,
        eventType _: Event.Type,
        finished: Bool,
        participants: [SessionParticipant],
        startedAt: Date
    ) -> ScoreSession<State, Event> {
        let descriptor = ScoreboardKernelRegistry.descriptor(for: gameType)
        return ScoreSession(
            sessionId: sessionId,
            gameType: gameType,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            state: state,
            status: finished ? .finished : .live,
            participants: participants,
            metadata: .init(extras: [
                "startedAtEpochMilliseconds": String(Int64(startedAt.timeIntervalSince1970 * 1_000))
            ])
        )
    }

    static func persist<State: Codable & Sendable, Event: Codable & Sendable>(
        repository: SessionArchiveRepository,
        sessionId: UUID,
        gameType: GameType,
        state: State,
        eventType: Event.Type,
        finished: Bool,
        participants: [SessionParticipant],
        startedAt: Date
    ) {
        let session = makeSession(
            sessionId: sessionId,
            gameType: gameType,
            state: state,
            eventType: eventType,
            finished: finished,
            participants: participants,
            startedAt: startedAt
        )
        Task { [repository] in
            try? await repository.save(session, source: .watchLocal)
        }
    }
}
