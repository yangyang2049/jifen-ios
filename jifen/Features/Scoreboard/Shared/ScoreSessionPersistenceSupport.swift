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

    static func reopenedResumeID(in payload: Data) -> UUID? {
        struct BundleHeader: Decodable {
            let auxiliaryPayload: Data?
        }
        guard let header = try? JSONDecoder().decode(BundleHeader.self, from: payload) else { return nil }
        return ScoreSessionRecordContext.decode(header.auxiliaryPayload)?.reopenedResumeID
    }

    static func finishedResumeRemover<State, Event>(
        for session: ScoreSession<State, Event>,
        repository: ResumeSessionRepository
    ) -> FinishedSessionCommitCoordinator.ResumeRemover? {
        guard session.status == .finished else { return nil }
        // The cleanup retry may run after an undo has written a new draft.
        let token = Result {
            try ResumeSessionRepository.cleanupToken(sessionId: session.sessionId, rootURL: repository.rootURL)
        }
        return { sessionId in
            guard let token = try token.get() else { return }
            _ = try await repository.remove(sessionId: sessionId, ifUnchanged: token)
        }
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
        reopenedResumeID: UUID? = nil,
        makeFinishedRecord: (ScoreSession<State, Event>) throws -> ScoreboardRecord?,
        onCleanupFailure: (Error) -> Void,
        removeResume: FinishedSessionCommitCoordinator.ResumeRemover? = nil
    ) async throws -> Bool {
        let session = bundle.currentSession
        if session.status == .live {
            try await repository.saveResumeBundle(bundle)
            return false
        }

        guard let record = try makeFinishedRecord(session) else { return false }
        let coordinator = FinishedSessionCommitCoordinator(
            resumeRemover: removeResume ?? { [repository] sessionId in
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
            let commit = try coordinator.commitRecord(
                record, sessionId: session.sessionId,
                replaceExisting: reopenedResumeID != nil, reopenedResumeID: reopenedResumeID
            )
            result = await coordinator.cleanupResume(after: commit)
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
