import Foundation
import Observation
import OSLog
import PersistenceCore
import ScoreCore
import SessionCore

/// Main-actor projection of `ScoreSessionCore` for the three specialized
/// billiards scoreboards. The actor owns the authoritative state, undo frames,
/// and typed intent timeline; SwiftUI only observes this read-only projection.
@MainActor
@Observable
final class SpecializedBilliardsSessionStore<Reducer: DomainReducer> where Reducer.State: Equatable {
    typealias State = Reducer.State
    typealias Intent = Reducer.Intent
    typealias Event = Reducer.Event
    typealias ResumeBundle = ScoreSessionResumeBundle<State, Event, Intent>

    private let core: ScoreSessionCore<Reducer>
    private let archiveRepository = SessionArchiveRepository()
    private var cachedBundle: ResumeBundle
    private var pendingUndoReservations = 0
    private var operationTask: Task<Void, Never>?
    private var lastPersistenceErrorPresentationAt: Date?
    private let logger = Logger(subsystem: "com.douhua.jifen.ios", category: "BilliardsPersistence")

    private(set) var state: State
    private(set) var persistenceFailureSignal = 0
    let sessionId: UUID

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
        legacyUndoStates: [State] = []
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
            metadata: .init(extras: [
                "startedAtEpochMilliseconds": String(Int64(startedAt.timeIntervalSince1970 * 1_000)),
                "recordID": recordID
            ])
        )
        let undoFrames = legacyUndoStates.map {
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
        self.core = ScoreSessionCore(
            resumeBundle: bundle,
            reducer: reducer,
            shouldFinish: { _, state in Self.status(of: state) == .finished }
        )
    }

    init(resumeBundle: ResumeBundle, reducer: Reducer) {
        sessionId = resumeBundle.currentSession.sessionId
        state = resumeBundle.currentSession.state
        cachedBundle = resumeBundle
        core = ScoreSessionCore(
            resumeBundle: resumeBundle,
            reducer: reducer,
            shouldFinish: { _, state in Self.status(of: state) == .finished }
        )
    }

    func send(
        _ intent: Intent,
        completion: ((State, State, [Event]) -> Void)? = nil
    ) {
        let previousTask = operationTask
        operationTask = Task { [weak self, core, archiveRepository] in
            _ = await previousTask?.value
            guard let self else { return }
            let before = self.state
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            guard case .accepted(let session, let events) = await core.dispatch(
                actorId: "phone",
                intent: intent,
                at: now
            ) else { return }
            self.state = session.state
            self.cachedBundle = await core.resumeBundle()
            do {
                try await archiveRepository.saveResumeBundle(self.cachedBundle)
            } catch {
                self.reportPersistenceFailure(error)
            }
            completion?(before, session.state, events)
        }
    }

    /// Reserves an existing undo frame synchronously so current UI callbacks can
    /// decide which Toast to show without racing a second rapid tap.
    @discardableResult
    func undo(completion: ((Bool, State) -> Void)? = nil) -> Bool {
        guard cachedBundle.undoFrames.count > pendingUndoReservations else {
            return false
        }
        pendingUndoReservations += 1
        let previousTask = operationTask
        operationTask = Task { [weak self, core, archiveRepository] in
            _ = await previousTask?.value
            let succeeded = await core.undo(actorId: "phone")
            guard let self else { return }
            self.pendingUndoReservations = max(0, self.pendingUndoReservations - 1)
            if succeeded {
                let session = await core.snapshot()
                self.state = session.state
                self.cachedBundle = await core.resumeBundle()
                do {
                    try await archiveRepository.saveResumeBundle(self.cachedBundle)
                } catch {
                    self.reportPersistenceFailure(error)
                }
            }
            completion?(succeeded, self.state)
        }
        return true
    }

    func rebase(to state: State, completion: ((State) -> Void)? = nil) {
        let previousTask = operationTask
        operationTask = Task { [weak self, core, archiveRepository] in
            _ = await previousTask?.value
            let session = await core.rebase(to: state, status: Self.status(of: state))
            guard let self else { return }
            self.state = session.state
            self.cachedBundle = await core.resumeBundle()
            do {
                try await archiveRepository.saveResumeBundle(self.cachedBundle)
            } catch {
                self.reportPersistenceFailure(error)
            }
            completion?(session.state)
        }
    }

    func updateParticipants(_ participants: [SessionParticipant]) {
        let previousTask = operationTask
        operationTask = Task { [weak self, core, archiveRepository] in
            _ = await previousTask?.value
            _ = await core.updateParticipants(participants)
            guard let self else { return }
            self.cachedBundle = await core.resumeBundle()
            do {
                try await archiveRepository.saveResumeBundle(self.cachedBundle)
            } catch {
                self.reportPersistenceFailure(error)
            }
        }
    }

    func persistSnapshot(completion: ((Bool) -> Void)? = nil) {
        let previousTask = operationTask
        operationTask = Task { [weak self, core, archiveRepository] in
            _ = await previousTask?.value
            guard let self else { return }
            self.cachedBundle = await core.resumeBundle()
            do {
                try await archiveRepository.saveResumeBundle(self.cachedBundle)
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
        let url = SessionArchiveRepository.snapshotURL(sessionId: sessionId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ResumeBundle.self, from: data)
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
