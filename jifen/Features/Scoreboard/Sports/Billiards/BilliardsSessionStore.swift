import Foundation
import LinkCore
import LinkSync
import Observation
import OSLog
import PersistenceCore
import RecordCore
import ScoreCore
import SessionCore

@MainActor
struct BilliardsWatchLink {
    let sessionId: UUID
    let service: PhoneWatchLinkService

    static var resetUnavailableMessage: String {
        NSLocalizedString("linked_score_reset_unavailable", value: "联动计分期间请先结束本场，再开始新一局。", comment: "")
    }

    static var renameUnavailableMessage: String {
        NSLocalizedString("linked_score_rename_unavailable", value: "请在结束联动后修改选手名称。", comment: "")
    }

    var latestUpdate: PhoneWatchLinkService.LinkedSnapshotUpdate? {
        guard let update = service.latestRemoteSnapshot, update.sessionId == sessionId else { return nil }
        return update
    }
}

/// Main-actor projection of `ScoreSessionMachine` for the three
/// billiards scoreboards. The actor owns the authoritative state, undo frames,
/// and typed intent timeline; SwiftUI only observes this read-only projection.
@MainActor
@Observable
final class BilliardsSessionStore<Reducer: DomainReducer> where Reducer.State: Equatable {
    typealias State = Reducer.State
    typealias Intent = Reducer.Intent
    typealias Event = Reducer.Event
    typealias ResumeBundle = ScoreSessionResumeBundle<State, Event, Intent>

    @ObservationIgnored private var machine: ScoreSessionMachine<Reducer>
    private let reducer: Reducer
    private let resumeRepository: ResumeSessionRepository
    private var cachedBundle: ResumeBundle
    private(set) var recordContext: ScoreSessionRecordContext
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?
    @ObservationIgnored private var liveSaveGeneration: UInt64 = 0
    private var installedLinkedUpdate: PhoneWatchLinkService.LinkedSnapshotUpdate?
    private var isProjectingAcceptedTransition = false
    private var lastPersistenceErrorPresentationAt: Date?
    private let logger = Logger(subsystem: "com.douhua.jifen.ios", category: "BilliardsPersistence")

    private(set) var state: State
    private(set) var persistenceFailureSignal = 0
    private(set) var hasCommittedFinishedRecord = false
    var shouldReplaceCommittedFinishedRecord: Bool { recordContext.reopenedResumeID != nil }
    let sessionId: UUID

    var finishedCommitCoordinator: FinishedSessionCommitCoordinator {
        let pending = persistenceTask
        let generation = liveSaveGeneration
        var cleanupToken: ResumeSessionCleanupToken?
        return FinishedSessionCommitCoordinator(
            resumeRemover: { [weak self, resumeRepository] sessionId in
                // A final record can commit before the previous scoring tap's
                // draft write finishes. Wait for it before capturing cleanup.
                _ = await pending?.value
                guard (self?.liveSaveGeneration ?? generation) == generation else { return }
                if cleanupToken == nil {
                    cleanupToken = try ResumeSessionRepository.cleanupToken(
                        sessionId: sessionId, rootURL: resumeRepository.rootURL
                    )
                }
                guard let cleanupToken else { return }
                _ = try await resumeRepository.remove(sessionId: sessionId, ifUnchanged: cleanupToken)
            }
        )
    }

    var undoStates: [State] {
        cachedBundle.undoFrames.map(\.session.state)
    }

    var encodedResumeBundle: Data? {
        try? JSONEncoder().encode(cachedBundle)
    }

    func makeLinkedMatchStore(state: State, startedAt: Date, recordID: String) -> BilliardsSessionStore {
        let previous = cachedBundle.currentSession
        return BilliardsSessionStore(
            gameType: previous.gameType,
            state: state,
            reducer: reducer,
            participants: previous.participants,
            startedAt: startedAt,
            recordID: recordID,
            metadataTitle: previous.metadata.title,
            resumeRepository: resumeRepository
        )
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
        self.resumeRepository = resumeRepository ?? ResumeSessionRepository()
        self.machine = ScoreSessionMachine(
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
        self.resumeRepository = resumeRepository ?? ResumeSessionRepository()
        machine = ScoreSessionMachine(
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
        linked: BilliardsWatchLink? = nil,
        completion: ((State, State, [Event]) -> Void)? = nil,
        afterFinalized: ((State, State, [Event]) -> Void)? = nil
    ) {
        enqueueDerivedIntent(
            { _ in intent },
            linked: linked,
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
        linked: BilliardsWatchLink? = nil,
        completion: ((Intent, State, State, [Event]) -> Void)? = nil,
        afterFinalized: ((Intent, State, State, [Event]) -> Void)? = nil
    ) {
        enqueueDerivedIntent(
            deriveIntent,
            linked: linked,
            completion: completion,
            afterFinalized: afterFinalized
        )
    }

    private func enqueueDerivedIntent(
        _ deriveIntent: @escaping (State) -> Intent?,
        linked: BilliardsWatchLink?,
        completion: ((Intent, State, State, [Event]) -> Void)?,
        afterFinalized: ((Intent, State, State, [Event]) -> Void)?
    ) {
        if let linked {
            sendLinked(deriveIntent, through: linked, completion: completion, afterFinalized: afterFinalized)
            return
        }
        let before = state
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        guard let intent = deriveIntent(before),
              case .accepted(let session, let events) = machine.dispatch(
                  actorId: "phone", intent: intent, at: now
              ) else { return }
        recordContext.pushUndoCheckpoint()
        if Self.status(of: before) == .finished, session.status == .live {
            hasCommittedFinishedRecord = false
            recordContext.reopenedResumeID = UUID()
        }
        state = session.state
        // The view projects accepted events into the same snapshot as the score.
        isProjectingAcceptedTransition = true
        completion?(intent, before, session.state, events)
        isProjectingAcceptedTransition = false
        enqueuePersistence()
        afterFinalized?(intent, before, session.state, events)
    }

    @discardableResult
    func undo(linked: BilliardsWatchLink? = nil, completion: ((Bool, State) -> Void)? = nil) -> Bool {
        if let linked {
            let succeeded = submitLinked(.undo(targetOpId: nil), through: linked) != nil
            completion?(succeeded, state)
            return succeeded
        }
        let wasFinished = Self.status(of: state) == .finished
        guard machine.undo(actorId: "phone") else { return false }
        state = machine.currentSession.state
        _ = recordContext.restoreLastUndoCheckpoint()
        if wasFinished, Self.status(of: state) == .live {
            hasCommittedFinishedRecord = false
            recordContext.reopenedResumeID = UUID()
        }
        enqueuePersistence()
        completion?(true, state)
        return true
    }

    /// Apply the phone's synchronous authoritative score and history together.
    /// The local machine is used again only after explicitly ending the link.
    @discardableResult
    func installLinkedUpdate(_ update: PhoneWatchLinkService.LinkedSnapshotUpdate) -> Bool {
        if let previous = installedLinkedUpdate, previous.sessionId == update.sessionId {
            guard update.matchGeneration > previous.matchGeneration
                    || (update.matchGeneration == previous.matchGeneration && update.revision > previous.revision) else {
                return false
            }
        }
        let confirmed: State?
        switch update.snapshot {
        case .eightBall(let value): confirmed = value as? State
        case .nineBall(let value): confirmed = value as? State
        case .snooker(let value): confirmed = value as? State
        default: confirmed = nil
        }
        guard let confirmed else { return false }

        let actionLog = update.detailedActions.map { action in
            let code = ReducerScoreboardRecordPersistence.normalizedOperationCode(action.operationCode ?? action.type.rawValue)
            let scores = action.scores.map(String.init).joined(separator: ",")
            let sets = action.setScores.map(String.init).joined(separator: ",")
            return "\(action.epochMilliseconds ?? 0)|snapshot|\(code)|\(scores)|\(sets)"
        }
        recordContext = .init(
            actionLog: actionLog, detailedActions: update.detailedActions, actionCount: update.detailedActions.count
        )
        state = confirmed
        installedLinkedUpdate = update
        return true
    }

    func leaveLinkedMatch() {
        installedLinkedUpdate = nil
        rebase(to: state)
    }

    private func sendLinked(
        _ deriveIntent: (State) -> Intent?,
        through link: BilliardsWatchLink,
        completion: ((Intent, State, State, [Event]) -> Void)?,
        afterFinalized: ((Intent, State, State, [Event]) -> Void)?
    ) {
        if let update = link.latestUpdate { installLinkedUpdate(update) }
        let before = state
        guard let intent = deriveIntent(before), let submitted = wireIntent(intent),
              let effectiveTime = submitLinked(submitted, through: link) else { return }

        let confirmed = state
        let details = reducer.reduce(state: before, intent: intent, at: effectiveTime)
        let events = details.accepted && details.state == confirmed ? details.events : []
        completion?(intent, before, confirmed, events)
        afterFinalized?(intent, before, confirmed, events)
    }

    private func wireIntent(_ intent: Intent) -> LinkedScoreboardIntent? {
        if let intent = intent as? EightBallIntent {
            return intent == .finishMatch ? .finish : .eightBall(intent)
        }
        if let intent = intent as? NineBallChaseIntent {
            return intent == .finishMatch ? .finish : .nineBall(intent)
        }
        if let intent = intent as? SnookerIntent {
            return intent == .finishMatch ? .finish : .snooker(intent)
        }
        return nil
    }

    private func submitLinked(_ intent: LinkedScoreboardIntent, through link: BilliardsWatchLink) -> Int64? {
        do {
            let result = try link.service.submitLocalIntent(intent, sessionId: link.sessionId)
            guard let update = link.latestUpdate, update.matchGeneration == result.op.handle.matchGeneration,
                  update.revision == result.committedRevision else {
                reportPersistenceFailure(LinkedProjectionFailure.missingConfirmedState)
                return nil
            }
            installLinkedUpdate(update)
            return result.outcome == .accepted ? result.effectiveEpochMilliseconds : nil
        } catch {
            reportPersistenceFailure(error)
            return nil
        }
    }

    private enum LinkedProjectionFailure: Error {
        case missingConfirmedState
    }

    func rebase(to state: State, completion: ((State) -> Void)? = nil) {
        let session = machine.rebase(to: state, status: Self.status(of: state))
        self.state = session.state
        recordContext.undoCheckpoints.removeAll()
        enqueuePersistence { _ in completion?(session.state) }
    }

    /// Starts a fresh local match and clears both undo and record history.
    func resetRuntime(to state: State, completion: ((State) -> Void)? = nil) {
        let session = machine.rebase(to: state, status: Self.status(of: state))
        self.state = session.state
        let reopenedResumeID = hasCommittedFinishedRecord ? UUID() : recordContext.reopenedResumeID
        hasCommittedFinishedRecord = false
        recordContext = .init(reopenedResumeID: reopenedResumeID)
        enqueuePersistence { _ in completion?(session.state) }
    }

    func updateParticipants(_ participants: [SessionParticipant]) {
        machine.updateParticipants(participants)
        guard !isProjectingAcceptedTransition else { return }
        enqueuePersistence()
    }

    func updateMetadataTitle(_ title: String?) {
        machine.updateMetadata(.init(title: title, extras: machine.currentSession.metadata.extras))
        guard !isProjectingAcceptedTransition else { return }
        enqueuePersistence()
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
            undoCheckpoints: recordContext.undoCheckpoints,
            reopenedResumeID: recordContext.reopenedResumeID
        )
        recordContext = context
        guard !isProjectingAcceptedTransition else { return }
        enqueuePersistence()
    }

    func persistSnapshot(completion: ((Bool) -> Void)? = nil) {
        enqueuePersistence(completion: completion)
    }

    func flush(completion: @escaping () -> Void) {
        let pending = persistenceTask
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
        recordContext.reopenedResumeID = nil
    }

    private func enqueuePersistence(completion: ((Bool) -> Void)? = nil) {
        machine.setResumeAuxiliaryPayload(recordContext.encoded)
        let bundle = machine.resumeBundle()
        cachedBundle = bundle
        guard bundle.currentSession.status == .live, installedLinkedUpdate == nil else {
            completion?(true)
            return
        }
        liveSaveGeneration &+= 1
        let pending = persistenceTask
        persistenceTask = Task {
            _ = await pending?.value
            do {
                try await resumeRepository.saveResumeBundle(bundle)
                completion?(true)
            } catch {
                reportPersistenceFailure(error)
                completion?(false)
            }
        }
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
