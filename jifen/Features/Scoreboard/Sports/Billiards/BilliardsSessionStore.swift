import Foundation
import Observation
import OSLog
import PersistenceCore
import RecordCore
import ScoreCore
import SessionCore

/// Main-actor projection of `ScoreSessionCore` for the three
/// billiards scoreboards. The actor owns the authoritative state, undo frames,
/// and typed intent timeline; SwiftUI only observes this read-only projection.
@MainActor
@Observable
final class BilliardsSessionStore<Reducer: DomainReducer> where Reducer.State: Equatable {
    typealias State = Reducer.State
    typealias Intent = Reducer.Intent
    typealias Event = Reducer.Event
    typealias ResumeBundle = ScoreSessionResumeBundle<State, Event, Intent>

    private let core: ScoreSessionCore<Reducer>
    private let reducer: Reducer
    private let resumeRepository: ResumeSessionRepository
    private var cachedBundle: ResumeBundle
    private(set) var recordContext: ScoreSessionRecordContext
    /// Synchronous projection of the serialized reducer queue. Every accepted
    /// preview uses the same reducer input, intent, and timestamp as the later
    /// actor dispatch, so Undo can reserve a real future frame without treating
    /// a nil/rejected derived intent as optimistic capacity.
    private var reservationState: State
    private var reservationUndoStates: [State]
    private var operationTask: Task<Void, Never>?
    private var isProjectingAcceptedTransition = false
    private var lastPersistenceErrorPresentationAt: Date?
    private let logger = Logger(subsystem: "com.douhua.jifen.ios", category: "BilliardsPersistence")

    private(set) var state: State
    private(set) var persistenceFailureSignal = 0
    private(set) var hasCommittedFinishedRecord = false
    private(set) var shouldReplaceCommittedFinishedRecord = false
    let sessionId: UUID

    var finishedCommitCoordinator: FinishedSessionCommitCoordinator {
        let cleanupToken = try? ResumeSessionRepository.cleanupToken(
            sessionId: sessionId,
            rootURL: resumeRepository.rootURL
        )
        return FinishedSessionCommitCoordinator(
            resumeRemover: { [resumeRepository] sessionId in
                guard let cleanupToken else { return }
                _ = try await resumeRepository.remove(
                    sessionId: sessionId,
                    ifUnchanged: cleanupToken
                )
            }
        )
    }

    var undoStates: [State] {
        cachedBundle.undoFrames.map(\.session.state)
    }

    var encodedResumeBundle: Data? {
        try? JSONEncoder().encode(cachedBundle)
    }

    init(
        gameType: ScoreCore.GameType,
        state: State,
        reducer: Reducer,
        participants: [SessionParticipant],
        startedAt: Date,
        recordID: String,
        metadataTitle: String? = nil,
        restoredUndoStates: [State] = [],
        resumeRepository: ResumeSessionRepository? = nil
    ) {
        let descriptor = ScoreboardKernelRegistry.descriptor(for: gameType)
        let session = ScoreSession<State, Event>(
            sessionId: UUID(uuidString: recordID) ?? UUID(),
            gameType: gameType,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            state: state,
            status: Self.status(of: state),
            participants: participants,
            metadata: .init(title: metadataTitle, extras: [
                "startedAtEpochMilliseconds": String(Int64(startedAt.timeIntervalSince1970 * 1_000)),
                "recordID": recordID
            ])
        )
        let undoFrames = restoredUndoStates.map {
            ScoreSessionResumeUndoFrame<State, Event>(
                session: ScoreSession(
                    sessionId: session.sessionId,
                    gameType: session.gameType,
                    ruleFamily: session.ruleFamily,
                    reducerType: session.reducerType,
                    state: $0,
                    participants: session.participants,
                    metadata: session.metadata
                )
            )
        }
        let bundle = ResumeBundle(
            replaySeed: undoFrames.first?.session ?? session,
            currentSession: session,
            undoFrames: undoFrames,
            timeline: []
        )
        self.sessionId = session.sessionId
        self.state = state
        self.cachedBundle = bundle
        self.recordContext = .init()
        self.reducer = reducer
        self.reservationState = state
        self.reservationUndoStates = restoredUndoStates
        self.resumeRepository = resumeRepository ?? ResumeSessionRepository()
        self.core = ScoreSessionCore(
            resumeBundle: bundle,
            reducer: reducer,
            shouldFinish: { _, state in Self.status(of: state) == .finished }
        )
    }

    init(
        resumeBundle: ResumeBundle,
        reducer: Reducer,
        resumeRepository: ResumeSessionRepository? = nil
    ) {
        sessionId = resumeBundle.currentSession.sessionId
        state = resumeBundle.currentSession.state
        cachedBundle = resumeBundle
        recordContext = ScoreSessionRecordContext.decode(resumeBundle.auxiliaryPayload) ?? .init()
        self.reducer = reducer
        reservationState = resumeBundle.currentSession.state
        reservationUndoStates = resumeBundle.undoFrames.map(\.session.state)
        self.resumeRepository = resumeRepository ?? ResumeSessionRepository()
        core = ScoreSessionCore(
            resumeBundle: resumeBundle,
            reducer: reducer,
            shouldFinish: { _, state in Self.status(of: state) == .finished }
        )
    }

    // Work around a Swift 6.3.3 Release optimizer crash in synthesized
    // deinitializers for generic classes that retain Task handles.
    @inline(never)
    deinit {}

    func send(
        _ intent: Intent,
        completion: ((State, State, [Event]) -> Void)? = nil,
        afterFinalized: ((State, State, [Event]) -> Void)? = nil
    ) {
        enqueueDerivedIntent(
            { _ in intent },
            completion: { _, before, after, events in
                completion?(before, after, events)
            },
            afterFinalized: { _, before, after, events in
                afterFinalized?(before, after, events)
            }
        )
    }

    /// Derives an intent from a synchronous projection of the serialized queue.
    /// Use this for absolute correction intents whose values depend on the
    /// previous score; the projection includes every earlier accepted preview,
    /// so rapid taps neither collapse nor create false Undo capacity.
    func sendDerived(
        _ deriveIntent: @escaping (State) -> Intent?,
        completion: ((Intent, State, State, [Event]) -> Void)? = nil,
        afterFinalized: ((Intent, State, State, [Event]) -> Void)? = nil
    ) {
        enqueueDerivedIntent(
            deriveIntent,
            completion: completion,
            afterFinalized: afterFinalized
        )
    }

    private func enqueueDerivedIntent(
        _ deriveIntent: @escaping (State) -> Intent?,
        completion: ((Intent, State, State, [Event]) -> Void)?,
        afterFinalized: ((Intent, State, State, [Event]) -> Void)?
    ) {
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        let reservedBefore = reservationState
        guard let intent = deriveIntent(reservedBefore) else { return }
        let preview = reducer.reduce(state: reservedBefore, intent: intent, at: now)
        guard preview.accepted else { return }
        reservationUndoStates.append(reservedBefore)
        reservationState = preview.state
        let previousTask = operationTask
        operationTask = Task { [weak self, core] in
            _ = await previousTask?.value
            guard let self else { return }
            let before = self.state
            guard case .accepted(let session, let events) = await core.dispatch(
                actorId: "phone",
                intent: intent,
                at: now
            ) else {
                assertionFailure("Billiards reducer dispatch diverged from its synchronous reservation preview")
                return
            }
            self.recordContext.pushUndoCheckpoint()
            self.state = session.state
            // Let the scoreboard project the accepted reducer events into the
            // record context before this authoritative state is persisted.
            // `updateRecordContext` replaces `recordContext` synchronously, so
            // the resume saved below contains state + action timeline together.
            self.isProjectingAcceptedTransition = true
            completion?(intent, before, session.state, events)
            self.isProjectingAcceptedTransition = false
            await core.setResumeAuxiliaryPayload(self.recordContext.encoded)
            self.cachedBundle = await core.resumeBundle()
            // Formal records must read `encodedResumeBundle` only after both
            // the accepted state and its projected record context are present.
            afterFinalized?(intent, before, session.state, events)
            do {
                try await self.saveLiveResumeIfNeeded()
            } catch {
                self.reportPersistenceFailure(error)
            }
        }
    }

    /// Reserves an existing undo frame synchronously so current UI callbacks can
    /// decide which Toast to show without racing a second rapid tap.
    @discardableResult
    func undo(completion: ((Bool, State) -> Void)? = nil) -> Bool {
        guard let projectedRestore = reservationUndoStates.popLast() else { return false }
        reservationState = projectedRestore
        let previousTask = operationTask
        operationTask = Task { [weak self, core] in
            _ = await previousTask?.value
            guard let self else { return }
            let wasFinished = Self.status(of: self.state) == .finished
            let succeeded = await core.undo(actorId: "phone")
            if succeeded {
                let session = await core.snapshot()
                self.state = session.state
                _ = self.recordContext.restoreLastUndoCheckpoint()
                await core.setResumeAuxiliaryPayload(self.recordContext.encoded)
                self.cachedBundle = await core.resumeBundle()
                if wasFinished,
                   Self.status(of: session.state) == .live,
                   self.hasCommittedFinishedRecord {
                    self.hasCommittedFinishedRecord = false
                    self.shouldReplaceCommittedFinishedRecord = true
                }
                do {
                    try await self.saveLiveResumeIfNeeded()
                } catch {
                    self.reportPersistenceFailure(error)
                }
            }
            completion?(succeeded, self.state)
        }
        return true
    }

    func rebase(to state: State, completion: ((State) -> Void)? = nil) {
        reservationState = state
        reservationUndoStates.removeAll(keepingCapacity: true)
        let previousTask = operationTask
        operationTask = Task { [weak self, core] in
            _ = await previousTask?.value
            let session = await core.rebase(to: state, status: Self.status(of: state))
            guard let self else { return }
            self.state = session.state
            self.recordContext.undoCheckpoints.removeAll()
            await core.setResumeAuxiliaryPayload(self.recordContext.encoded)
            self.cachedBundle = await core.resumeBundle()
            do {
                try await self.saveLiveResumeIfNeeded()
            } catch {
                self.reportPersistenceFailure(error)
            }
            completion?(session.state)
        }
    }

    /// Starts a fresh local match in the same session slot. Unlike a scoring
    /// reset intent this is an undo boundary: Android's Snooker reset rebuilds
    /// the runtime and clears both reducer history and record projection.
    func resetRuntime(to state: State, completion: ((State) -> Void)? = nil) {
        reservationState = state
        reservationUndoStates.removeAll(keepingCapacity: true)
        let previousTask = operationTask
        operationTask = Task { [weak self, core] in
            _ = await previousTask?.value
            let session = await core.rebase(to: state, status: Self.status(of: state))
            guard let self else { return }
            self.state = session.state
            self.recordContext = .init()
            await core.setResumeAuxiliaryPayload(self.recordContext.encoded)
            self.cachedBundle = await core.resumeBundle()
            do {
                try await self.saveLiveResumeIfNeeded()
            } catch {
                self.reportPersistenceFailure(error)
            }
            completion?(session.state)
        }
    }

    func updateParticipants(_ participants: [SessionParticipant]) {
        let previousTask = operationTask
        operationTask = Task { [weak self, core] in
            _ = await previousTask?.value
            _ = await core.updateParticipants(participants)
            guard let self else { return }
            self.cachedBundle = await core.resumeBundle()
            do {
                try await self.saveLiveResumeIfNeeded()
            } catch {
                self.reportPersistenceFailure(error)
            }
        }
    }

    func updateMetadataTitle(_ title: String?) {
        let previousTask = operationTask
        operationTask = Task { [weak self, core] in
            _ = await previousTask?.value
            guard let self else { return }
            let current = await core.snapshot()
            _ = await core.updateMetadata(.init(title: title, extras: current.metadata.extras))
            self.cachedBundle = await core.resumeBundle()
            do {
                try await self.saveLiveResumeIfNeeded()
            } catch {
                self.reportPersistenceFailure(error)
            }
        }
    }

    /// Persists the record-facing timeline beside the typed reducer bundle.
    /// The reducer state and undo frames remain authoritative for scoring.
    func updateRecordContext(
        actionLog: [String],
        detailedActions: [DetailedScoreAction],
        actionCount: Int
    ) {
        let context = ScoreSessionRecordContext(
            actionLog: actionLog,
            detailedActions: detailedActions,
            actionCount: actionCount,
            completedSetScores: recordContext.completedSetScores,
            undoCheckpoints: recordContext.undoCheckpoints
        )
        recordContext = context
        // Accepted-transition completions run inside the serialized operation.
        // The caller above will persist this synchronously replaced context
        // together with the accepted state, so enqueuing a second save here
        // would reorder later taps/undo and could replay stale record data.
        guard !isProjectingAcceptedTransition else { return }
        let previousTask = operationTask
        operationTask = Task { [weak self, core] in
            _ = await previousTask?.value
            guard let self else { return }
            await core.setResumeAuxiliaryPayload(self.recordContext.encoded)
            self.cachedBundle = await core.resumeBundle()
            do {
                try await self.saveLiveResumeIfNeeded()
            } catch {
                self.reportPersistenceFailure(error)
            }
        }
    }

    func persistSnapshot(completion: ((Bool) -> Void)? = nil) {
        let previousTask = operationTask
        operationTask = Task { [weak self, core] in
            _ = await previousTask?.value
            guard let self else { return }
            await core.setResumeAuxiliaryPayload(self.recordContext.encoded)
            self.cachedBundle = await core.resumeBundle()
            do {
                try await self.saveLiveResumeIfNeeded()
                completion?(true)
            } catch {
                self.reportPersistenceFailure(error)
                completion?(false)
            }
        }
    }

    func flush(completion: @escaping () -> Void) {
        let pending = operationTask
        Task {
            _ = await pending?.value
            completion()
        }
    }

    static func decodeResumeBundle(sessionId: UUID) -> ResumeBundle? {
        guard let data = try? ResumeSessionRepository.loadPayload(
            sessionId: sessionId,
            expectedKind: .scoreSessionBundle
        ) else { return nil }
        return try? JSONDecoder().decode(ResumeBundle.self, from: data)
    }

    func markFinishedRecordCommitted() {
        hasCommittedFinishedRecord = true
        shouldReplaceCommittedFinishedRecord = false
    }

    private func saveLiveResumeIfNeeded() async throws {
        guard cachedBundle.currentSession.status == .live else {
            // Never invoke PersistenceCore's finished-save removal before the
            // app-layer formal record has committed. Keeping the last live
            // snapshot makes a failed finish recoverable.
            return
        }
        try await resumeRepository.saveResumeBundle(cachedBundle)
    }

    private func reportPersistenceFailure(_ error: Error) {
        logger.error("Failed to persist billiards session \(self.sessionId.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
        let now = Date()
        guard lastPersistenceErrorPresentationAt.map({ now.timeIntervalSince($0) >= 5 }) != false else { return }
        lastPersistenceErrorPresentationAt = now
        persistenceFailureSignal &+= 1
    }

    private nonisolated static func status(of state: State) -> SessionStatus {
        if let value = state as? EightBallState {
            return value.finished ? .finished : .live
        }
        if let value = state as? NineBallChaseState {
            return value.finished ? .finished : .live
        }
        if let value = state as? SnookerState {
            return value.finished ? .finished : .live
        }
        return .live
    }
}
