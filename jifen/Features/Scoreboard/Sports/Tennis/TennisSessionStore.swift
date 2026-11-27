import Foundation
import Observation
import OSLog
import PersistenceCore
import RecordCore
import ScoreCore
import SessionCore

@MainActor
@Observable
final class TennisSessionStore {
    private typealias ResumeBundle = ScoreSessionResumeBundle<TennisMatchState, TennisMatchEvent, TennisMatchIntent>

    @ObservationIgnored private var machine: ScoreSessionMachine<TennisMatchReducer>
    private let resumeRepository: ResumeSessionRepository
    private var detailedActions: [DetailedScoreAction]
    private(set) var completedSetScores: [VoiceSetScore] = []
    private var recordUndoCheckpoints: [ScoreSessionRecordCheckpoint]
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?
    @ObservationIgnored private var persistenceGeneration: UInt64 = 0
    private var scoreInputFrozen: Bool
    private var lastPersistenceErrorPresentationAt: Date?
    private var hasPersistedFinishedRecord = false
    private var reopenedResumeID: UUID?
    @ObservationIgnored var isManagedByLink = false {
        didSet {
            if isManagedByLink && !oldValue {
                persistenceGeneration &+= 1
            }
        }
    }
    private(set) var linkedMatchGeneration: UInt64?
    private var linkedRevision: UInt64?
    private let logger = Logger(subsystem: "com.douhua.jifen.ios", category: "TennisPersistence")

    private(set) var state: TennisMatchState
    private(set) var persistenceFailureSignal = 0
    var actionTimeline: [DetailedScoreAction] { detailedActions }

    var teamScreenLayout: TeamScreenLayout {
        TeamScreenLayout(sidesSwapped: state.sidesSwapped)
    }

    func teamID(onScreen side: MatchSide) -> TeamID {
        teamScreenLayout.teamID(on: side)
    }

    func geometricSide(for team: TeamID) -> MatchSide {
        TeamScreenLayout.identityEngineSide(for: team)
    }
    let gameType: ScoreCore.GameType
    let sessionId: UUID
    let startedAt: Date
    var voiceAnnouncementEnabled: Bool = false

    convenience init(
        leftName: String,
        rightName: String,
        gameType: ScoreCore.GameType = .tennis,
        rules: TennisRuleSet = .init(),
        openingServer: MatchSide = .left,
        voiceAnnouncementEnabled: Bool = false,
        resumeRepository: ResumeSessionRepository? = nil
    ) {
        let state = TennisMatchState(
            leftName: leftName,
            rightName: rightName,
            rules: rules,
            openingServer: openingServer
        )
        self.init(
            gameType: gameType,
            state: state,
            voiceAnnouncementEnabled: voiceAnnouncementEnabled,
            resumeRepository: resumeRepository
        )
    }

    convenience init(
        gameType: ScoreCore.GameType,
        state: TennisMatchState,
        voiceAnnouncementEnabled: Bool = false,
        resumeRepository: ResumeSessionRepository? = nil
    ) {
        let session = ScoreSession<TennisMatchState, TennisMatchEvent>(
            gameType: gameType,
            ruleFamily: .s1,
            reducerType: ScoreboardKernelRegistry.descriptor(for: gameType).reducerType,
            state: state,
            participants: Self.participants(for: state),
            metadata: .init(extras: [
                "startedAtEpochMilliseconds": String(Int64(Date().timeIntervalSince1970 * 1_000)),
                "voiceAnnouncementEnabled": String(voiceAnnouncementEnabled)
            ])
        )
        self.init(
            session: session,
            voiceAnnouncementEnabled: voiceAnnouncementEnabled,
            resumeRepository: resumeRepository
        )
    }

    private init(
        session: ScoreSession<TennisMatchState, TennisMatchEvent>,
        voiceAnnouncementEnabled: Bool,
        resumeRepository: ResumeSessionRepository? = nil
    ) {
        gameType = session.gameType
        sessionId = session.sessionId
        let startedMilliseconds = session.metadata.extras["startedAtEpochMilliseconds"].flatMap(Int64.init)
        startedAt = startedMilliseconds.map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) } ?? Date()
        machine = ScoreSessionMachine(
            seedSession: session,
            reducer: TennisMatchReducer(),
            shouldFinish: { _, state in state.finished }
        )
        self.resumeRepository = resumeRepository ?? ResumeSessionRepository()
        state = session.state
        scoreInputFrozen = session.state.officialBreakState?.isRunning == true
        let initialDetailedActions = ScoreboardRecordManager.shared
            .getRecordById(session.sessionId.uuidString)?.detailedActions ?? []
        detailedActions = initialDetailedActions
        completedSetScores = Self.completedSetScores(from: initialDetailedActions)
        recordUndoCheckpoints = []
        self.voiceAnnouncementEnabled = Self.metadataBool(
            session.metadata.extras["voiceAnnouncementEnabled"]
        ) ?? voiceAnnouncementEnabled
    }

    private init(resumeBundle: ResumeBundle) {
        let session = resumeBundle.currentSession
        gameType = session.gameType
        sessionId = session.sessionId
        let startedMilliseconds = session.metadata.extras["startedAtEpochMilliseconds"].flatMap(Int64.init)
        startedAt = startedMilliseconds.map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) } ?? Date()
        machine = ScoreSessionMachine(
            resumeBundle: resumeBundle,
            reducer: TennisMatchReducer(),
            shouldFinish: { _, state in state.finished }
        )
        resumeRepository = ResumeSessionRepository()
        state = session.state
        scoreInputFrozen = session.state.officialBreakState?.isRunning == true
        let recordContext = ScoreSessionRecordContext.decode(resumeBundle.auxiliaryPayload)
        reopenedResumeID = recordContext?.reopenedResumeID
        let restoredDetailedActions = recordContext?.detailedActions
            ?? ScoreboardRecordManager.shared.getRecordById(session.sessionId.uuidString)?.detailedActions
            ?? []
        detailedActions = restoredDetailedActions
        completedSetScores = recordContext?.completedSetScores
            ?? Self.completedSetScores(from: restoredDetailedActions)
        recordUndoCheckpoints = recordContext?.undoCheckpoints ?? []
        self.voiceAnnouncementEnabled = Self.metadataBool(
            session.metadata.extras["voiceAnnouncementEnabled"]
        ) ?? false
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

    func makeFreshMatchStore(initialState: TennisMatchState? = nil) -> TennisSessionStore {
        let resetState = initialState ?? TennisMatchReducer().reduce(
            state: state,
            intent: .reset,
            at: Int64(Date().timeIntervalSince1970 * 1_000)
        ).state
        return TennisSessionStore(
            gameType: gameType,
            state: resetState,
            voiceAnnouncementEnabled: voiceAnnouncementEnabled,
            resumeRepository: resumeRepository
        )
    }

    func setVoiceAnnouncementEnabled(_ enabled: Bool) {
        guard voiceAnnouncementEnabled != enabled else { return }
        voiceAnnouncementEnabled = enabled
        guard !isManagedByLink else { return }
        var metadata = machine.currentSession.metadata
        metadata.extras["voiceAnnouncementEnabled"] = String(enabled)
        machine.updateMetadata(metadata)
        enqueuePersistence()
    }

    private static func metadataBool(_ value: String?) -> Bool? {
        switch value?.lowercased() {
        case "true", "1": true
        case "false", "0": false
        default: nil
        }
    }

    /// Blocks local scoring during the official break presentation.
    func setScoreInputFrozen(_ frozen: Bool) {
        scoreInputFrozen = frozen
    }

    func send(_ intent: TennisMatchIntent, onEvents: (([TennisMatchEvent]) -> Void)? = nil) {
        dispatch(intent) { _, _, events in
            onEvents?(events)
        }
    }

    /// Delivers the accepted before/after transition in the same action.
    func send(
        _ intent: TennisMatchIntent,
        onTransition: @escaping (TennisMatchState, TennisMatchState, [TennisMatchEvent]) -> Void
    ) {
        dispatch(intent, onTransition: onTransition)
    }

    private func dispatch(
        _ intent: TennisMatchIntent,
        onTransition: ((TennisMatchState, TennisMatchState, [TennisMatchEvent]) -> Void)?
    ) {
        guard !isManagedByLink, !scoreInputFrozen || !Self.isScoreChanging(intent) else { return }
        let before = state
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        let result: DispatchResult<TennisMatchState, TennisMatchEvent>
        let recordsUndo: Bool
        if case .setOfficialBreakState = intent {
            recordsUndo = false
            result = machine.dispatchNonUndoable(actorId: "phone", intent: intent, at: now)
        } else {
            recordsUndo = true
            result = machine.dispatch(actorId: "phone", intent: intent, at: now)
        }
        guard case .accepted(let session, let events) = result else { return }
        if recordsUndo {
            recordUndoCheckpoints.append(makeRecordUndoCheckpoint())
        }
        if before.finished, session.status == .live {
            reopenedResumeID = UUID()
        }
        state = session.state
        append(events: events, at: now, state: session.state)
        updateCompletedSetScores(for: events)
        synchronizeParticipants(for: session.state)
        // A UI callback can send another intent, for example when a point
        // starts an official break. Enqueue this snapshot before calling it.
        enqueuePersistence()
        onTransition?(before, session.state, events)
        speak(intent: intent, before: before, after: session.state, events: events)
    }

    private static func isScoreChanging(_ intent: TennisMatchIntent) -> Bool {
        switch intent {
        case .pointWon, .adjustPoints, .adjustGames, .adjustSets:
            true
        default:
            false
        }
    }

    func undo(completion: ((Bool) -> Void)? = nil) {
        let wasFinished = state.finished
        let undoneIntentEpochMilliseconds = machine.intentTimeline().last?.epochMilliseconds
        guard !isManagedByLink, machine.undo(actorId: "phone") else {
            completion?(false)
            return
        }
        state = machine.currentSession.state
        if wasFinished, !state.finished {
            reopenedResumeID = UUID()
        }
        synchronizeParticipants(for: state)
        restoreRecordUndoCheckpoint(fallbackEpochMilliseconds: undoneIntentEpochMilliseconds)
        enqueuePersistence()
        completion?(true)
    }

    func persistSnapshot(completion: ((Bool) -> Void)? = nil) {
        enqueuePersistence(completion: completion, forceFailurePresentation: true)
    }

    func flush(completion: @escaping () -> Void) {
        let pending = persistenceTask
        Task {
            _ = await pending?.value
            completion()
        }
    }

    /// Installs the journaled phone projection without dispatching to the standalone reducer.
    @discardableResult
    func applyLinkedProjection(
        _ state: TennisMatchState,
        detailedActions: [DetailedScoreAction],
        revision: UInt64,
        matchGeneration: UInt64
    ) -> Bool {
        if let linkedMatchGeneration {
            guard matchGeneration >= linkedMatchGeneration else { return false }
            if matchGeneration == linkedMatchGeneration, let linkedRevision, revision <= linkedRevision {
                return false
            }
        }
        isManagedByLink = true
        linkedMatchGeneration = matchGeneration
        linkedRevision = revision
        self.state = state
        self.detailedActions = detailedActions
        completedSetScores = Self.completedSetScores(from: detailedActions)
        trimCompletedSetScores(toMatch: state)
        hasPersistedFinishedRecord = state.finished
        return true
    }

    /// Rebase the standalone machine only when the user ends the link on this page.
    func continueStandaloneFromLink() {
        isManagedByLink = false
        guard linkedMatchGeneration != nil else { return }
        linkedMatchGeneration = nil
        linkedRevision = nil
        recordUndoCheckpoints.removeAll(keepingCapacity: true)
        let session = machine.rebase(to: state, status: state.finished ? .finished : .live)
        var metadata = session.metadata
        metadata.extras["voiceAnnouncementEnabled"] = String(voiceAnnouncementEnabled)
        machine.updateMetadata(metadata)
        synchronizeParticipants(for: state)
        enqueuePersistence()
    }

    private func synchronizeParticipants(for state: TennisMatchState) {
        let participants = Self.participants(for: state)
        guard machine.currentSession.participants != participants else { return }
        machine.updateParticipants(participants)
    }

    private static func participants(for state: TennisMatchState) -> [SessionParticipant] {
        if let names = state.doublesPlayerNames, names.count == 4 {
            let ids = ["left-top", "right-top", "left-bottom", "right-bottom"]
            return names.indices.map {
                .init(id: ids[$0], name: names[$0], role: "player")
            }
        }
        return [
            .init(id: TeamID.team0.rawValue, name: state.leftName, role: "team"),
            .init(id: TeamID.team1.rawValue, name: state.rightName, role: "team")
        ]
    }

    func speak(
        intent: TennisMatchIntent,
        before: TennisMatchState,
        after: TennisMatchState,
        events: [TennisMatchEvent]
    ) {
        guard voiceAnnouncementEnabled else { return }

        let payloads = TennisVoiceAnnouncementMapper.payloads(
            gameType: gameType,
            before: before,
            after: after,
            intent: intent,
            events: events,
            completedSetScores: completedSetScores
        )
        ScoreVoiceAnnouncer.shared.speak(payloads)
    }

    private var recordContext: ScoreSessionRecordContext {
        ScoreSessionRecordContext(
            detailedActions: detailedActions,
            actionCount: detailedActions.count,
            completedSetScores: completedSetScores,
            undoCheckpoints: recordUndoCheckpoints,
            reopenedResumeID: reopenedResumeID
        )
    }

    private func makeRecordUndoCheckpoint() -> ScoreSessionRecordCheckpoint {
        ScoreSessionRecordCheckpoint(
            actionLogCount: 0,
            detailedActionsCount: detailedActions.count,
            actionCount: detailedActions.count,
            completedSetScoresCount: completedSetScores.count
        )
    }

    private func restoreRecordUndoCheckpoint(fallbackEpochMilliseconds: Int64?) {
        if let checkpoint = recordUndoCheckpoints.popLast() {
            detailedActions = Array(detailedActions.prefix(max(0, checkpoint.detailedActionsCount)))
            completedSetScores = Array(completedSetScores.prefix(max(0, checkpoint.completedSetScoresCount)))
            return
        }

        if let fallbackEpochMilliseconds {
            while detailedActions.last?.epochMilliseconds == fallbackEpochMilliseconds {
                detailedActions.removeLast()
            }
        }
        completedSetScores = Self.completedSetScores(from: detailedActions)
    }

    private func updateCompletedSetScores(for events: [TennisMatchEvent]) {
        if events.contains(where: { if case .matchReset = $0 { return true }; return false }) {
            completedSetScores.removeAll()
            return
        }
        for event in events {
            if case let .setCompleted(_, _, leftGames, rightGames, _, _) = event {
                completedSetScores.append(VoiceSetScore(leftGames: leftGames, rightGames: rightGames))
            }
        }
    }

    private func trimCompletedSetScores(toMatch state: TennisMatchState) {
        let completedCount = max(0, state.leftSets + state.rightSets)
        if completedSetScores.count > completedCount {
            completedSetScores.removeLast(completedSetScores.count - completedCount)
        }
    }

    private static func completedSetScores(from actions: [DetailedScoreAction]) -> [VoiceSetScore] {
        actions.compactMap { action in
            guard action.type == .setFinished, action.scores.count >= 2 else { return nil }
            return VoiceSetScore(leftGames: action.scores[0], rightGames: action.scores[1])
        }
    }

    private func append(events: [TennisMatchEvent], at milliseconds: Int64, state: TennisMatchState) {
        let recordedSetScores = state.rules.setScoringMode == .tiebreakOnly
            ? []
            : [state.leftSets, state.rightSets]
        let completedSetNumber = events.compactMap { event -> Int? in
            guard case .setCompleted(_, let number, _, _, _, _) = event else { return nil }
            return number
        }.first
        for event in events {
            switch event {
            case .pointScored(let side, let left, let right):
                detailedActions.append(.init(
                    type: .scoreChanged,
                    epochMilliseconds: milliseconds,
                    team: side == .left ? .team1 : .team2,
                    scores: [left, right],
                    setScores: recordedSetScores,
                    setNumber: completedSetNumber ?? state.currentSet,
                    scoreChange: 1,
                    operationCode: "point"
                ))
            case .gameCompleted(let winner, let leftGames, let rightGames, _):
                detailedActions.append(.init(
                    type: .stateChanged,
                    epochMilliseconds: milliseconds,
                    team: winner == .left ? .team1 : .team2,
                    scores: [leftGames, rightGames],
                    setScores: recordedSetScores,
                    setNumber: completedSetNumber ?? state.currentSet,
                    operationCode: "game_completed"
                ))
            case .setCompleted(let winner, let number, let leftGames, let rightGames, let leftSets, let rightSets):
                detailedActions.append(.init(
                    type: .setFinished,
                    epochMilliseconds: milliseconds,
                    team: winner == .left ? .team1 : .team2,
                    scores: [leftGames, rightGames],
                    setScores: [leftSets, rightSets],
                    setNumber: number,
                    winner: winner == .left ? .team1 : .team2,
                    operationCode: "set_completed"
                ))
            case .sidesExchanged:
                detailedActions.append(.init(
                    type: .sideChanged,
                    epochMilliseconds: milliseconds,
                    scores: [state.leftPoints, state.rightPoints],
                    setScores: recordedSetScores,
                    setNumber: state.currentSet,
                    operationCode: "exchange_sides"
                ))
            case .matchFinished(let winner):
                let usePointScore = state.rules.setScoringMode == .tiebreakOnly
                detailedActions.append(.init(
                    type: .matchFinished,
                    epochMilliseconds: milliseconds,
                    scores: usePointScore
                        ? [state.leftPoints, state.rightPoints]
                        : [state.leftGames, state.rightGames],
                    setScores: recordedSetScores,
                    setNumber: completedSetNumber ?? state.currentSet,
                    winner: winner.map { $0 == .left ? .team1 : .team2 },
                    operationCode: "finish"
                ))
            case .matchReset:
                detailedActions.append(.init(
                    type: .reset,
                    epochMilliseconds: milliseconds,
                    scores: [0, 0],
                    setScores: state.rules.setScoringMode == .tiebreakOnly ? [] : [0, 0],
                    operationCode: "reset"
                ))
            default:
                break
            }
        }
    }

    private func enqueuePersistence(
        completion: ((Bool) -> Void)? = nil,
        forceFailurePresentation: Bool = false
    ) {
        guard !isManagedByLink else {
            completion?(true)
            return
        }
        machine.setResumeAuxiliaryPayload(recordContext.encoded)
        let bundle = machine.resumeBundle()
        let actions = detailedActions
        let voiceEnabled = voiceAnnouncementEnabled
        let generation = persistenceGeneration
        let reopenedResumeID = reopenedResumeID
        let pending = persistenceTask
        persistenceTask = Task {
            _ = await pending?.value
            guard generation == persistenceGeneration else {
                completion?(true)
                return
            }
            if bundle.currentSession.status == .live {
                hasPersistedFinishedRecord = false
            }
            do {
                let reachedFinishedCommit = try await ScoreSessionPersistenceSupport.persist(
                    bundle,
                    repository: resumeRepository,
                    alreadyPersistedFinishedRecord: hasPersistedFinishedRecord,
                    reopenedResumeID: reopenedResumeID,
                    makeFinishedRecord: { session in
                        try self.makeFinishedRecord(session, actions: actions, voiceEnabled: voiceEnabled)
                    },
                    onCleanupFailure: { self.reportPersistenceFailure($0) },
                    removeResume: ScoreSessionPersistenceSupport.finishedResumeRemover(
                        for: bundle.currentSession, repository: resumeRepository
                    )
                )
                if reachedFinishedCommit, generation == persistenceGeneration {
                    hasPersistedFinishedRecord = true
                }
                completion?(true)
            } catch {
                reportPersistenceFailure(error, forcePresentation: forceFailurePresentation)
                completion?(false)
            }
        }
    }

    private func makeFinishedRecord(
        _ session: ScoreSession<TennisMatchState, TennisMatchEvent>,
        actions: [DetailedScoreAction],
        voiceEnabled: Bool
    ) throws -> ScoreboardRecord? {
        let state = session.state
        guard session.status == .finished, state.finished else { return nil }
        guard let appGameType = GameType(scoreCoreGameType: gameType) else { return nil }
        let snapshot = try JSONEncoder().encode(session)
        let usePointScore = state.rules.setScoringMode == .tiebreakOnly
        let leftFinalScore = usePointScore ? state.leftPoints : state.leftGames
        let rightFinalScore = usePointScore ? state.rightPoints : state.rightGames
        let leftWinnerScore = usePointScore ? state.leftPoints : state.leftSets
        let rightWinnerScore = usePointScore ? state.rightPoints : state.rightSets
        let winner: String? = state.finished && leftWinnerScore != rightWinnerScore
            ? (leftWinnerScore > rightWinnerScore ? "left" : "right")
            : nil
        let record = ScoreboardRecord(
            id: sessionId.uuidString,
            gameType: appGameType,
            startTime: startedAt,
            endTime: state.finished ? Date() : nil,
            duration: Date().timeIntervalSince(startedAt),
            team1Name: state.leftName,
            team2Name: state.rightName,
            team1FinalScore: leftFinalScore,
            team2FinalScore: rightFinalScore,
            team1SetScore: usePointScore ? nil : state.leftSets,
            team2SetScore: usePointScore ? nil : state.rightSets,
            winner: winner,
            detailedActions: actions,
            setResults: ScoreboardRecordActionAdapter.setResults(from: actions),
            totalScoreChanges: actions.count,
            projectConfiguration: ScoreboardRecordConfiguration.tennis(
                gameType: gameType,
                state: state,
                voiceAnnouncement: voiceEnabled
            ),
            stateSnapshot: snapshot,
            status: .finished
        )
        return record
    }

    private func reportPersistenceFailure(_ error: Error, forcePresentation: Bool = false) {
        logger.error("Failed to persist tennis session \(self.sessionId.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
        let now = Date()
        if forcePresentation
            || lastPersistenceErrorPresentationAt.map({ now.timeIntervalSince($0) >= 5 }) != false {
            lastPersistenceErrorPresentationAt = now
            persistenceFailureSignal &+= 1
        }
    }
}
