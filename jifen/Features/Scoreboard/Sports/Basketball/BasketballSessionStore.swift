import Foundation
import Observation
import PersistenceCore
import RecordCore
import ScoreCore
import SessionCore

@MainActor
@Observable
final class BasketballSessionStore {
    private typealias ResumeBundle = ScoreSessionResumeBundle<BasketballMatchState, BasketballMatchEvent, BasketballMatchIntent>
    private static let clockStartedFlag = "basketballClockStarted"

    private let core: ScoreSessionCore<BasketballMatchReducer>
    private let resumeRepository: ResumeSessionRepository
    private var clockTask: Task<Void, Never>?
    private var recordContext: ScoreSessionRecordContext
    private var operationTask: Task<Void, Never>?
    private var hasPersistedFinishedRecord = false
    private var gameClockAnchorNanoseconds: UInt64?
    private var timeoutClockAnchorNanoseconds: UInt64?

    private(set) var state: BasketballMatchState
    private(set) var basketballClockStarted: Bool
    var actionTimeline: [DetailedScoreAction] { recordContext.detailedActions }
    let sessionId: UUID
    let startedAt: Date

    /// HOS-aligned screen placement derived from engine `sidesSwapped`.
    var teamScreenLayout: TeamScreenLayout {
        TeamScreenLayout(sidesSwapped: state.sidesSwapped)
    }

    func teamID(onScreen side: MatchSide) -> TeamID {
        teamScreenLayout.teamID(on: side)
    }

    func geometricSide(for team: TeamID) -> MatchSide {
        TeamScreenLayout.identityEngineSide(for: team)
    }

    convenience init(
        leftName: String,
        rightName: String,
        gameMode: BasketballGameMode = .fiveVFive,
        ruleSet: BasketballRuleSet = .fiba,
        resumeRepository: ResumeSessionRepository? = nil
    ) {
        let initial = BasketballMatchEngine.initial(
            leftName: leftName,
            rightName: rightName,
            gameMode: gameMode,
            ruleSet: ruleSet
        )
        let session = ScoreSession<BasketballMatchState, BasketballMatchEvent>(
            gameType: gameMode == .threeXThree ? .threeBasketball : .basketball,
            ruleFamily: .s2,
            reducerType: ScoreboardKernelRegistry.descriptor(for: gameMode == .threeXThree ? .threeBasketball : .basketball).reducerType,
            state: initial,
            participants: [
                .init(id: TeamID.team0.rawValue, name: initial.leftName, role: "team"),
                .init(id: TeamID.team1.rawValue, name: initial.rightName, role: "team")
            ],
            metadata: .init(extras: ["startedAtEpochMilliseconds": String(Int64(Date().timeIntervalSince1970 * 1_000))])
        )
        self.init(session: session, resumeRepository: resumeRepository)
    }

    private init(
        session: ScoreSession<BasketballMatchState, BasketballMatchEvent>,
        resumeRepository: ResumeSessionRepository? = nil
    ) {
        sessionId = session.sessionId
        let startedMilliseconds = session.metadata.extras["startedAtEpochMilliseconds"].flatMap(Int64.init)
        startedAt = startedMilliseconds.map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) } ?? Date()
        core = ScoreSessionCore(
            seedSession: session,
            reducer: BasketballMatchReducer(),
            shouldFinish: { _, state in state.finished }
        )
        self.resumeRepository = resumeRepository ?? ResumeSessionRepository()
        state = session.state
        let restoredActions = ScoreboardRecordManager.shared
            .getRecordById(session.sessionId.uuidString)?.detailedActions ?? []
        var initialContext = ScoreSessionRecordContext(
            detailedActions: restoredActions,
            actionCount: restoredActions.count
        )
        initialContext.presentationFlags[Self.clockStartedFlag] = false
        recordContext = initialContext
        basketballClockStarted = false
    }

    private init(resumeBundle: ResumeBundle) {
        let session = resumeBundle.currentSession
        sessionId = session.sessionId
        let startedMilliseconds = session.metadata.extras["startedAtEpochMilliseconds"].flatMap(Int64.init)
        startedAt = startedMilliseconds.map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) } ?? Date()
        core = ScoreSessionCore(
            resumeBundle: resumeBundle,
            reducer: BasketballMatchReducer(),
            shouldFinish: { _, state in state.finished }
        )
        resumeRepository = ResumeSessionRepository()
        state = session.state
        var restoredContext: ScoreSessionRecordContext
        if let decoded = ScoreSessionRecordContext.decode(resumeBundle.auxiliaryPayload) {
            restoredContext = decoded
        } else {
            let restoredActions = ScoreboardRecordManager.shared
                .getRecordById(session.sessionId.uuidString)?.detailedActions ?? []
            restoredContext = ScoreSessionRecordContext(
                detailedActions: restoredActions,
                actionCount: restoredActions.count
            )
        }
        let restoredClockStarted = restoredContext.presentationFlags[Self.clockStartedFlag]
            ?? Self.inferLegacyClockStarted(from: session.state)
        restoredContext.presentationFlags[Self.clockStartedFlag] = restoredClockStarted
        recordContext = restoredContext
        basketballClockStarted = restoredClockStarted
    }

    convenience init?(restoring sessionId: UUID) {
        guard let bundle = ScoreSessionPersistenceSupport.loadLiveResumeBundle(
            sessionId: sessionId,
            as: ResumeBundle.self
        ) else {
            return nil
        }
        self.init(resumeBundle: bundle)
    }

    func makeFreshMatchStore() -> BasketballSessionStore {
        BasketballSessionStore(
            leftName: state.leftName,
            rightName: state.rightName,
            gameMode: state.gameMode,
            ruleSet: state.ruleSet,
            resumeRepository: resumeRepository
        )
    }

    func send(_ intent: BasketballMatchIntent, recordsUndo: Bool = true) {
        if intent != .tickClock, intent != .tickTimeout {
            refreshClockFromAnchor()
        }
        let previousTask = operationTask
        operationTask = Task { [weak self, core] in
            _ = await previousTask?.value
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            let result = if recordsUndo {
                await core.dispatch(actorId: "phone", intent: intent, at: now)
            } else {
                await core.dispatchNonUndoable(actorId: "phone", intent: intent, at: now)
            }
            guard case .accepted(let session, _) = result, let self else { return }
            self.state = session.state
            self.synchronizeClockAnchors()
            if session.status == .live {
                self.hasPersistedFinishedRecord = false
            }
            if recordsUndo {
                // The actor has just created the matching undo frame. Capture
                // the record-facing state before projecting this accepted
                // intent so both layers can roll back as one operation.
                self.recordContext.pushUndoCheckpoint()
            }
            self.updateClockStarted(after: intent, acceptedState: session.state)
            if intent != .tickClock, intent != .tickTimeout {
                // The final action is part of the formal record and must be in
                // memory before the record-first commit starts.
                self.append(intent: intent, at: now, state: session.state)
            }
            await core.setResumeAuxiliaryPayload(self.recordContext.encoded)
            await self.synchronizeParticipants(for: session.state)
            let bundle = await core.resumeBundle()
            do {
                // Live clock ticks only update the resume snapshot. The tick
                // that actually ends a timed match must still write the final
                // record now that the view no longer queues a duplicate save.
                try await self.persist(bundle)
            } catch {
                ScoreboardPersistenceFailureReporter.report(
                    error,
                    context: "Failed to persist basketball session \(self.sessionId.uuidString)"
                )
            }
        }
    }

    func undo(completion: ((Bool) -> Void)? = nil) {
        refreshClockFromAnchor()
        let previousTask = operationTask
        operationTask = Task { [weak self, core] in
            _ = await previousTask?.value
            guard await core.undo(actorId: "phone"), let self else {
                completion?(false)
                return
            }
            let session = await core.snapshot()
            self.state = session.state
            self.synchronizeClockAnchors()
            if session.status == .live {
                self.hasPersistedFinishedRecord = false
            }
            await self.synchronizeParticipants(for: session.state)
            if !self.recordContext.restoreLastUndoCheckpoint() {
                // Bundles written before record checkpoints existed still have
                // the reducer event stream. Re-project it instead of retaining
                // a stale score/period action after a legacy resume undo.
                self.rebuildRecordContext(from: session.events)
            }
            self.basketballClockStarted = self.recordContext.presentationFlags[Self.clockStartedFlag]
                ?? Self.inferLegacyClockStarted(from: session.state)
            self.recordContext.presentationFlags[Self.clockStartedFlag] = self.basketballClockStarted
            await core.setResumeAuxiliaryPayload(self.recordContext.encoded)
            completion?(true)
            let bundle = await core.resumeBundle()
            do {
                try await self.persist(bundle)
            } catch {
                ScoreboardPersistenceFailureReporter.report(
                    error,
                    context: "Failed to persist basketball undo \(self.sessionId.uuidString)"
                )
            }
        }
    }

    func startClock() {
        guard clockTask == nil else { return }
        synchronizeClockAnchors()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.refreshClockFromAnchor()
            }
        }
    }

    func stopClock() {
        refreshClockFromAnchor()
        clockTask?.cancel()
        clockTask = nil
    }

    /// A normal foul creates a dead ball in Android 3.1: both clocks stop,
    /// while the current shot-clock value is preserved. Edit corrections use
    /// the raw intent and therefore do not disturb the live clocks.
    func addFoul(_ side: MatchSide, stopClocks: Bool = true) {
        let shouldStop = stopClocks && (state.gameRunning || state.shotRunning)
        send(.addFoul(side: side))
        if shouldStop {
            send(.setClockRunning(false), recordsUndo: false)
        }
    }

    func persistSnapshot(completion: ((Bool) -> Void)? = nil) {
        refreshClockFromAnchor()
        let previousTask = operationTask
        operationTask = Task { [core] in
            _ = await previousTask?.value
            await core.setResumeAuxiliaryPayload(self.recordContext.encoded)
            let bundle = await core.resumeBundle()
            do {
                try await self.persist(bundle)
                completion?(true)
            } catch {
                ScoreboardPersistenceFailureReporter.report(
                    error,
                    context: "Failed to persist final basketball snapshot \(self.sessionId.uuidString)",
                    forcePresentation: true
                )
                completion?(false)
            }
        }
    }

    func flush(completion: @escaping () -> Void) {
        refreshClockFromAnchor()
        let pending = operationTask
        Task {
            _ = await pending?.value
            completion()
        }
    }

    private func refreshClockFromAnchor() {
        let now = DispatchTime.now().uptimeNanoseconds
        let maximumCatchUpSeconds = 90 * 60
        if state.timeoutActiveSide != nil, state.timeoutRemainingSeconds > 0 {
            gameClockAnchorNanoseconds = nil
            guard let anchor = timeoutClockAnchorNanoseconds else {
                timeoutClockAnchorNanoseconds = now
                return
            }
            let elapsed = min(maximumCatchUpSeconds, Int((now - anchor) / 1_000_000_000))
            guard elapsed > 0 else { return }
            timeoutClockAnchorNanoseconds = anchor + UInt64(elapsed) * 1_000_000_000
            for _ in 0..<elapsed {
                send(.tickTimeout, recordsUndo: false)
            }
            return
        }

        timeoutClockAnchorNanoseconds = nil
        guard state.gameRunning else {
            gameClockAnchorNanoseconds = nil
            return
        }
        guard let anchor = gameClockAnchorNanoseconds else {
            gameClockAnchorNanoseconds = now
            return
        }
        let elapsed = min(maximumCatchUpSeconds, Int((now - anchor) / 1_000_000_000))
        guard elapsed > 0 else { return }
        gameClockAnchorNanoseconds = anchor + UInt64(elapsed) * 1_000_000_000
        for _ in 0..<elapsed {
            send(.tickClock, recordsUndo: false)
        }
    }

    private func synchronizeClockAnchors() {
        let now = DispatchTime.now().uptimeNanoseconds
        if state.timeoutActiveSide != nil, state.timeoutRemainingSeconds > 0 {
            timeoutClockAnchorNanoseconds = timeoutClockAnchorNanoseconds ?? now
            gameClockAnchorNanoseconds = nil
        } else {
            timeoutClockAnchorNanoseconds = nil
            gameClockAnchorNanoseconds = state.gameRunning
                ? (gameClockAnchorNanoseconds ?? now)
                : nil
        }
    }

    private func synchronizeParticipants(for state: BasketballMatchState) async {
        let participants: [SessionParticipant] = [
            .init(id: TeamID.team0.rawValue, name: state.leftName, role: "team"),
            .init(id: TeamID.team1.rawValue, name: state.rightName, role: "team")
        ]
        guard await core.snapshot().participants != participants else { return }
        _ = await core.updateParticipants(participants)
    }

    private func append(intent: BasketballMatchIntent, at milliseconds: Int64, state: BasketballMatchState) {
        guard let action = Self.detailedAction(intent: intent, at: milliseconds, state: state) else {
            return
        }
        recordContext.detailedActions.append(action)
        recordContext.actionCount = recordContext.detailedActions.count
    }

    private static func detailedAction(
        intent: BasketballMatchIntent,
        at milliseconds: Int64,
        state: BasketballMatchState
    ) -> DetailedScoreAction? {
        let action: DetailedScoreAction
        let gameTimeSeconds = state.gameTimeSeconds
        switch intent {
        case .addPoints(let side, let points, _):
            action = .init(type: .scoreChanged, epochMilliseconds: milliseconds, team: side == .left ? .team1 : .team2, scores: [state.leftScore, state.rightScore], periodNumber: state.currentPeriod, gameTimeSeconds: gameTimeSeconds, scoreChange: points, operationCode: "basketball_score_\(points)")
        case .adjustScore(let side, let delta):
            action = .init(type: .scoreChanged, epochMilliseconds: milliseconds, team: side == .left ? .team1 : .team2, scores: [state.leftScore, state.rightScore], periodNumber: state.currentPeriod, gameTimeSeconds: gameTimeSeconds, scoreChange: delta, operationCode: "score_adjust")
        case .addFoul(let side), .removeFoul(let side):
            action = .init(type: .foul, epochMilliseconds: milliseconds, team: side == .left ? .team1 : .team2, scores: [state.leftScore, state.rightScore], periodNumber: state.currentPeriod, gameTimeSeconds: gameTimeSeconds, operationCode: String(describing: intent))
        case .useTimeout(let side):
            action = .init(type: .timeout, epochMilliseconds: milliseconds, team: side == .left ? .team1 : .team2, scores: [state.leftScore, state.rightScore], periodNumber: state.currentPeriod, gameTimeSeconds: gameTimeSeconds, operationCode: "timeout")
        case .endTimeout:
            action = .init(type: .timeout, epochMilliseconds: milliseconds, scores: [state.leftScore, state.rightScore], periodNumber: state.currentPeriod, gameTimeSeconds: gameTimeSeconds, operationCode: "timeout_end")
        case .advanceToNextPeriod, .enterOvertime:
            action = .init(type: .periodFinished, epochMilliseconds: milliseconds, scores: [state.leftScore, state.rightScore], periodNumber: max(1, state.currentPeriod - (state.isOvertime ? 0 : 1)), gameTimeSeconds: gameTimeSeconds, operationCode: state.isOvertime ? "overtime" : "period_finished")
        case .exchangeSides:
            action = .init(type: .sideChanged, epochMilliseconds: milliseconds, scores: [state.leftScore, state.rightScore], periodNumber: state.currentPeriod, gameTimeSeconds: gameTimeSeconds, operationCode: "exchange_sides")
        case .reset:
            action = .init(type: .reset, epochMilliseconds: milliseconds, scores: [state.leftScore, state.rightScore], periodNumber: state.currentPeriod, gameTimeSeconds: gameTimeSeconds, operationCode: "reset")
        case .finish:
            action = .init(type: .matchFinished, epochMilliseconds: milliseconds, scores: [state.leftScore, state.rightScore], periodNumber: state.currentPeriod, gameTimeSeconds: gameTimeSeconds, winner: state.leftScore == state.rightScore ? nil : (state.leftScore > state.rightScore ? .team1 : .team2), operationCode: "finish")
        case .tickClock, .tickTimeout:
            return nil
        default:
            action = .init(type: .stateChanged, epochMilliseconds: milliseconds, scores: [state.leftScore, state.rightScore], periodNumber: state.currentPeriod, gameTimeSeconds: gameTimeSeconds, operationCode: String(describing: intent))
        }
        return action
    }

    private func rebuildRecordContext(from events: [BasketballMatchEvent]) {
        let presentationFlags = recordContext.presentationFlags
        let actions = events.compactMap { event -> DetailedScoreAction? in
            guard case .stateChanged(let at, let intent, _, let after) = event else {
                return nil
            }
            return Self.detailedAction(intent: intent, at: at, state: after)
        }
        recordContext = ScoreSessionRecordContext(
            detailedActions: actions,
            actionCount: actions.count,
            presentationFlags: presentationFlags
        )
    }

    private func updateClockStarted(
        after intent: BasketballMatchIntent,
        acceptedState: BasketballMatchState
    ) {
        switch intent {
        case .setClockRunning(true):
            if acceptedState.gameRunning || acceptedState.shotRunning {
                basketballClockStarted = true
            }
        case .endTimeout:
            if acceptedState.gameRunning || acceptedState.shotRunning {
                basketballClockStarted = true
            }
        case .reset:
            basketballClockStarted = false
        default:
            break
        }
        recordContext.presentationFlags[Self.clockStartedFlag] = basketballClockStarted
    }

    /// Drafts written before `basketballClockStarted` existed need a conservative
    /// one-time inference. Live updates never use this heuristic, so scoring before
    /// the first tip-off does not incorrectly mark the clock as started.
    private static func inferLegacyClockStarted(from state: BasketballMatchState) -> Bool {
        let initial = BasketballMatchEngine.initial(
            leftName: state.leftName,
            rightName: state.rightName,
            gameMode: state.gameMode,
            ruleSet: state.ruleSet
        )
        return state.gameRunning
            || state.shotRunning
            || state.gameTimeSeconds < initial.gameTimeSeconds
            || state.leftScore > 0
            || state.rightScore > 0
            || state.currentPeriod > 1
            || state.isOvertime
    }

    private func persist(_ bundle: ResumeBundle) async throws {
        let reachedFinishedCommit = try await ScoreSessionPersistenceSupport.persist(
            bundle,
            repository: resumeRepository,
            alreadyPersistedFinishedRecord: hasPersistedFinishedRecord,
            makeFinishedRecord: makeFinishedRecord,
            onCleanupFailure: { [sessionId] error in
                ScoreboardPersistenceFailureReporter.report(
                    error,
                    context: "Failed to clean finished basketball resume \(sessionId.uuidString)"
                )
            }
        )
        if reachedFinishedCommit {
            hasPersistedFinishedRecord = true
        }
    }

    private func makeFinishedRecord(
        _ session: ScoreSession<BasketballMatchState, BasketballMatchEvent>
    ) throws -> ScoreboardRecord? {
        guard session.status == .finished, state.finished else { return nil }
        let appGameType: GameType = state.gameMode == .threeXThree ? .threeBasketball : .basketball
        let snapshot = try JSONEncoder().encode(session)
        let winner = state.finished && state.leftScore != state.rightScore ? (state.leftScore > state.rightScore ? "left" : "right") : nil
        let record = ScoreboardRecord(
            id: sessionId.uuidString,
            gameType: appGameType,
            startTime: startedAt,
            endTime: state.finished ? Date() : nil,
            duration: Date().timeIntervalSince(startedAt),
            team1Name: state.leftName,
            team2Name: state.rightName,
            team1FinalScore: state.leftScore,
            team2FinalScore: state.rightScore,
            winner: winner,
            detailedActions: recordContext.detailedActions,
            setResults: ScoreboardRecordActionAdapter.setResults(from: recordContext.detailedActions),
            totalScoreChanges: recordContext.actionCount,
            projectConfiguration: [
                "basketballMode": AnyCodable(state.gameMode == .threeXThree ? "three_x_three" : "five_v_five"),
                "basketballRuleSet": AnyCodable(String(describing: state.ruleSet).lowercased())
            ],
            stateSnapshot: snapshot,
            status: .finished
        )
        return record
    }
}
