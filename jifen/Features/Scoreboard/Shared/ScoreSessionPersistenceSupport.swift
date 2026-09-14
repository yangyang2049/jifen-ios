import Foundation
import PersistenceCore
import RecordCore
import ScoreCore
import SessionCore

@MainActor
enum ScoreSessionPersistenceSupport {
    static func loadLiveResumeBundle<
        State: Codable & Sendable,
        Event: Codable & Sendable,
        Intent: Codable & Sendable
    >(
        sessionId: UUID,
        as type: ScoreSessionResumeBundle<State, Event, Intent>.Type
    ) -> ScoreSessionResumeBundle<State, Event, Intent>? {
        guard let data = try? ResumeSessionRepository.loadPayload(
            sessionId: sessionId,
            expectedKind: .scoreSessionBundle
        ),
        let bundle = try? JSONDecoder().decode(type, from: data),
        bundle.currentSession.status == .live else {
            return nil
        }
        return bundle
    }

    /// Persists a live resume bundle or commits a finished record before
    /// removing its resume snapshot. Returns `true` after a finished session
    /// reaches the durable commit/cleanup phase.
    static func persist<
        State: Codable & Sendable,
        Event: Codable & Sendable,
        Intent: Codable & Sendable
    >(
        _ bundle: ScoreSessionResumeBundle<State, Event, Intent>,
        repository: ResumeSessionRepository,
        alreadyPersistedFinishedRecord: Bool,
        makeFinishedRecord: (ScoreSession<State, Event>) throws -> ScoreboardRecord?,
        onCleanupFailure: (Error) -> Void
    ) async throws -> Bool {
        let session = bundle.currentSession
        if session.status == .live {
            try await repository.saveResumeBundle(bundle)
            return false
        }

        guard let record = try makeFinishedRecord(session) else { return false }
        let coordinator = FinishedSessionCommitCoordinator(
            resumeRemover: { [repository] sessionId in
                try await repository.remove(sessionId: sessionId)
            }
        )
        let result: FinishedSessionCommitResult
        if alreadyPersistedFinishedRecord {
            result = await coordinator.cleanupResume(
                after: FinishedSessionRecordCommit(
                    sessionId: session.sessionId,
                    recordWritten: false
                )
            )
        } else {
            result = try await coordinator.commit(record, sessionId: session.sessionId)
        }

        if result.recordWritten {
            ScoreboardRecordsViewModel.shared.refreshRecords()
        }
        if let cleanupError = result.cleanupError {
            onCleanupFailure(cleanupError)
        }
        return true
    }
}
