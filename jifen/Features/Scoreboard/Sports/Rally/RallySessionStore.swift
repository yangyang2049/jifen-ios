import Foundation
import Observation
import OSLog
import PersistenceCore
import RecordCore
import ScoreCore
import SessionCore

@MainActor
@Observable
final class RallySessionStore {
    private typealias ResumeBundle = ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>

    @ObservationIgnored private var machine: ScoreSessionMachine<RallyMatchReducer>
    private let resumeRepository: ResumeSessionRepository
    private var detailedActions: [DetailedScoreAction]
    private(set) var completedSetScores: [VoiceSetScore]
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
    private let logger = Logger(subsystem: "com.douhua.jifen.ios", category: "RallyPersistence")

    private(set) var state: RallyMatchState
    private(set) var persistenceFailureSignal = 0
    var actionTimeline: [DetailedScoreAction] { detailedActions }
    let gameType: ScoreCore.GameType
    let sessionId: UUID
    let startedAt: Date
    var voiceAnnouncementEnabled: Bool
    private(set) var showMatchTimeEnabled: Bool

    /// HOS-aligned screen placement derived from engine `sidesSwapped`.
    var teamScreenLayout: TeamScreenLayout {
        TeamScreenLayout(sidesSwapped: state.sidesSwapped)
    }

    /// Engine MatchSide for a team identity (left=team0, right=team1).
    func geometricSide(for team: TeamID) -> MatchSide {
        TeamScreenLayout.identityEngineSide(for: team)
    }

    func teamID(onScreen side: MatchSide) -> TeamID {
        teamScreenLayout.teamID(on: side)
    }

    convenience init(
        leftName: String,
        rightName: String,
        gameType: ScoreCore.GameType,
        rules: RallyRuleSet,
        participants: [SessionParticipant]? = nil,
        competitionFormat: CompetitionFormat? = nil,
        competitionPlayerNames: [String]? = nil,
        openingServer: MatchSide = .left,
        voiceAnnouncementEnabled: Bool = false,
        showMatchTimeEnabled: Bool = false,
        resumeRepository: ResumeSessionRepository? = nil
    ) {
        let providedParticipants = participants?.filter { !$0.name.isEmpty }
        var initial = RallyMatchEngine.initial(
            leftName: leftName,
            rightName: rightName,
            rules: rules,
            openingServer: openingServer,
            doubles: Self.doublesState(
                for: gameType,
                participants: providedParticipants,
                openingServer: openingServer
            ),
            competitionFormat: competitionFormat,
            competitionPlayerNames: competitionPlayerNames
        )
        #if DEBUG
        if MarketingScreenshotFixture.isRequested("rally") {
            initial.leftPoints = 23
            initial.rightPoints = 23
        }
        #endif
        self.init(
            gameType: gameType,
            state: initial,
            participants: providedParticipants,
            voiceAnnouncementEnabled: voiceAnnouncementEnabled,
            showMatchTimeEnabled: showMatchTimeEnabled,
            resumeRepository: resumeRepository
        )
    }

    convenience init(
        gameType: ScoreCore.GameType,
        state: RallyMatchState,
        participants: [SessionParticipant]? = nil,
        voiceAnnouncementEnabled: Bool = false,
        showMatchTimeEnabled: Bool = false,
        resumeRepository: ResumeSessionRepository? = nil
    ) {
        let sessionParticipants = participants ?? [
            .init(id: TeamID.team0.rawValue, name: state.leftName, role: "team"),
            .init(id: TeamID.team1.rawValue, name: state.rightName, role: "team")
        ]
        let session = ScoreSession<RallyMatchState, RallyMatchEvent>(
            gameType: gameType,
            ruleFamily: .s1,
            reducerType: ScoreboardKernelRegistry.descriptor(for: gameType).reducerType,
            state: state,
            participants: sessionParticipants,
            metadata: .init(extras: [
                "startedAtEpochMilliseconds": String(Int64(Date().timeIntervalSince1970 * 1_000)),
                "voiceAnnouncementEnabled": String(voiceAnnouncementEnabled),
                "showMatchTime": String(showMatchTimeEnabled)
            ])
        )
        self.init(
            session: session,
            voiceAnnouncementEnabled: voiceAnnouncementEnabled,
            showMatchTimeEnabled: showMatchTimeEnabled,
            resumeRepository: resumeRepository
        )
    }

    private init(
        session: ScoreSession<RallyMatchState, RallyMatchEvent>,
        voiceAnnouncementEnabled: Bool,
        showMatchTimeEnabled: Bool,
        resumeRepository: ResumeSessionRepository? = nil
    ) {
        gameType = session.gameType
        sessionId = session.sessionId
        let startedMilliseconds = session.metadata.extras["startedAtEpochMilliseconds"].flatMap(Int64.init)
        startedAt = startedMilliseconds.map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) } ?? Date()
        machine = ScoreSessionMachine(seedSession: session, reducer: RallyMatchReducer(), shouldFinish: { _, state in state.finished })
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
        self.showMatchTimeEnabled = Self.metadataBool(
            session.metadata.extras["showMatchTime"]
        ) ?? showMatchTimeEnabled
    }

    private init(resumeBundle: ResumeBundle) {
        let resumeBundle = Self.migratedResumeBundle(resumeBundle)
        let session = resumeBundle.currentSession
        gameType = session.gameType
        sessionId = session.sessionId
        let startedMilliseconds = session.metadata.extras["startedAtEpochMilliseconds"].flatMap(Int64.init)
        startedAt = startedMilliseconds.map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) } ?? Date()
        machine = ScoreSessionMachine(
            resumeBundle: resumeBundle,
            reducer: RallyMatchReducer(),
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
        self.showMatchTimeEnabled = Self.metadataBool(
            session.metadata.extras["showMatchTime"]
        ) ?? false
    }

    /// The exact game type is the migration authority for local snapshots.
    /// `sportProfile` did not exist in older payloads, and inferring it only
    /// from a serve model is ambiguous now that Android 3.1 pickleball singles
    /// returns every set to the opening server. Normalize the current session,
    /// replay seed, and every undo frame together so undo cannot resurrect the
    /// pre-migration rules or doubles rotation.
    private static func migratedResumeBundle(_ bundle: ResumeBundle) -> ResumeBundle {
        let gameType = bundle.currentSession.gameType
        return ResumeBundle(
            replaySeed: migratedSession(bundle.replaySeed, gameType: gameType),
            currentSession: migratedSession(bundle.currentSession, gameType: gameType),
            undoFrames: bundle.undoFrames.map {
                ScoreSessionResumeUndoFrame(
                    session: migratedSession($0.session, gameType: gameType),
                    intentCount: $0.intentCount
                )
            },
            timeline: bundle.timeline,
            auxiliaryPayload: bundle.auxiliaryPayload
        )
    }

    private static func migratedSession(
        _ session: ScoreSession<RallyMatchState, RallyMatchEvent>,
        gameType: ScoreCore.GameType
    ) -> ScoreSession<RallyMatchState, RallyMatchEvent> {
        ScoreSession(
            sessionId: session.sessionId,
            gameType: session.gameType,
            ruleFamily: session.ruleFamily,
            reducerType: session.reducerType,
            version: session.version,
            state: migratedState(session.state, gameType: gameType),
            events: session.events,
            status: session.status,
            participants: session.participants,
            metadata: session.metadata
        )
    }

    private static func migratedState(
        _ state: RallyMatchState,
        gameType: ScoreCore.GameType
    ) -> RallyMatchState {
        var migrated = state
        switch gameType {
        case .pickleball:
            migrated.rules.sportProfile = .pickleball
            migrated.rules.nextSetServerModel = .opening
        case .pickleballDoubles:
            migrated.rules.sportProfile = .pickleball
            migrated.rules.nextSetServerModel = .alternateFromOpening
        case .badminton, .badmintonDoubles:
            // 旧快照没有 sportProfile 字段；判罚通道挂在 badminton profile 下，按项目归一。
            migrated.rules.sportProfile = .badminton
        default:
            migrated.rules.sportProfile = .generic
        }

        guard gameType == .pingpongDoubles else { return migrated }
        migrated.doubles = migratedPingPongDoubles(migrated.doubles)
        if let replay = migrated.currentSetReplay {
            migrated.currentSetReplay = RallyCurrentSetReplay(
                baselineLeftPoints: replay.baselineLeftPoints,
                baselineRightPoints: replay.baselineRightPoints,
                baselineServingSide: replay.baselineServingSide,
                baselineFirstServerInSet: replay.baselineFirstServerInSet,
                baselineSidesSwapped: replay.baselineSidesSwapped,
                baselineDoubles: migratedPingPongDoubles(replay.baselineDoubles),
                actions: replay.actions
            )
        }
        return migrated
    }

    /// Early iOS table-tennis doubles snapshots used the visually mirrored
    /// receiver pair 0→3 / 1→2 as the game-opening default. Android 3.0/3.1
    /// use the cross-table identity pair 0→1 / 1→0. These slot permutations
    /// preserve the complete in-game service phase (including deciding-game
    /// receiver changes), rather than resetting a resumed game to 0–0.
    private static func migratedPingPongDoubles(
        _ doubles: RallyDoublesState?
    ) -> RallyDoublesState? {
        guard var doubles,
              case .pingPong(let rotation) = doubles.rotation,
              rotation.pendingGameOpening == nil else { return doubles }

        let slotMap: [Int]
        let openingReceiver: Int
        switch (rotation.openingServerSlotIndex, rotation.openingReceiverSlotIndex) {
        case (0, 3):
            slotMap = [0, 3, 2, 1]
            openingReceiver = 1
        case (1, 2):
            slotMap = [2, 1, 0, 3]
            openingReceiver = 0
        default:
            return doubles
        }

        func migratedSlot(_ slot: Int) -> Int {
            slotMap.indices.contains(slot) ? slotMap[slot] : slot
        }
        doubles.rotation = .pingPong(PingPongDoublesRotationState(
            serverSlotIndex: migratedSlot(rotation.serverSlotIndex),
            receiverSlotIndex: migratedSlot(rotation.receiverSlotIndex),
            openingServerSlotIndex: rotation.openingServerSlotIndex,
            openingReceiverSlotIndex: openingReceiver,
            decidingReceiverOrderChanged: rotation.decidingReceiverOrderChanged
        ))
        return doubles
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

    func makeFreshMatchStore(initialState: RallyMatchState? = nil) -> RallySessionStore {
        let resetState = initialState ?? RallyMatchReducer().reduce(
            state: state,
            intent: .reset,
            at: Int64(Date().timeIntervalSince1970 * 1_000)
        ).state
        return RallySessionStore(
            gameType: gameType,
            state: resetState,
            participants: Self.participants(for: resetState),
            voiceAnnouncementEnabled: voiceAnnouncementEnabled,
            showMatchTimeEnabled: showMatchTimeEnabled,
            resumeRepository: resumeRepository
        )
    }

    func setVoiceAnnouncementEnabled(_ enabled: Bool) {
        guard voiceAnnouncementEnabled != enabled else { return }
        voiceAnnouncementEnabled = enabled
        persistPresentationMetadata()
    }

    func setShowMatchTimeEnabled(_ enabled: Bool) {
        guard showMatchTimeEnabled != enabled else { return }
        showMatchTimeEnabled = enabled
        persistPresentationMetadata()
    }

    private func persistPresentationMetadata() {
        guard !isManagedByLink else { return }
        var metadata = machine.currentSession.metadata
        metadata.extras["voiceAnnouncementEnabled"] = String(voiceAnnouncementEnabled)
        metadata.extras["showMatchTime"] = String(showMatchTimeEnabled)
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

    func send(_ intent: RallyMatchIntent, onEvents: (([RallyMatchEvent]) -> Void)? = nil) {
        dispatch(intent) { _, _, events in
            onEvents?(events)
        }
    }

    /// Delivers the accepted before/after transition in the same action.
    func send(
        _ intent: RallyMatchIntent,
        onTransition: @escaping (RallyMatchState, RallyMatchState, [RallyMatchEvent]) -> Void
    ) {
        dispatch(intent, onTransition: onTransition)
    }

    private func dispatch(
        _ intent: RallyMatchIntent,
        onTransition: ((RallyMatchState, RallyMatchState, [RallyMatchEvent]) -> Void)?
    ) {
        guard !isManagedByLink, !scoreInputFrozen || !Self.isScoreChanging(intent) else { return }
        let before = state
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        let result: DispatchResult<RallyMatchState, RallyMatchEvent>
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
    }

    private static func isScoreChanging(_ intent: RallyMatchIntent) -> Bool {
        switch intent {
        case .pointWon, .adjustPoints, .adjustSets:
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
        _ state: RallyMatchState,
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
        metadata.extras["showMatchTime"] = String(showMatchTimeEnabled)
        machine.updateMetadata(metadata)
        synchronizeParticipants(for: state)
        enqueuePersistence()
    }

    private func append(events: [RallyMatchEvent], at milliseconds: Int64, state: RallyMatchState) {
        let completedSetNumber = events.compactMap { event -> Int? in
            guard case .setCompleted(_, let number, _, _, _, _) = event else { return nil }
            return number
        }.first
        for event in events {
            switch event {
            case .pointScored(let side, let left, let right):
                detailedActions.append(.init(type: .scoreChanged, epochMilliseconds: milliseconds, team: side == .left ? .team1 : .team2, scores: [left, right], setScores: [state.leftSets, state.rightSets], setNumber: completedSetNumber ?? state.currentSet, scoreChange: 1, operationCode: "point"))
            case .pointsAdjusted(let side, let delta, let left, let right):
                detailedActions.append(.init(type: .scoreChanged, epochMilliseconds: milliseconds, team: side == .left ? .team1 : .team2, scores: [left, right], setScores: [state.leftSets, state.rightSets], setNumber: completedSetNumber ?? state.currentSet, scoreChange: delta, operationCode: "adjust"))
            case .sideOut(_, let left, let right):
                detailedActions.append(.init(type: .stateChanged, epochMilliseconds: milliseconds, scores: [left, right], setScores: [state.leftSets, state.rightSets], setNumber: state.currentSet, operationCode: "side_out"))
            case .setCompleted(let winner, let number, let left, let right, let leftSets, let rightSets):
                detailedActions.append(.init(type: .setFinished, epochMilliseconds: milliseconds, team: winner == .left ? .team1 : .team2, scores: [left, right], setScores: [leftSets, rightSets], setNumber: number, winner: winner == .left ? .team1 : .team2, operationCode: "set_completed"))
            case .sidesExchanged:
                detailedActions.append(.init(type: .sideChanged, epochMilliseconds: milliseconds, scores: [state.leftPoints, state.rightPoints], setScores: [state.leftSets, state.rightSets], setNumber: state.currentSet, operationCode: "exchange_sides"))
            case .sidesExchangeReminder:
                detailedActions.append(.init(type: .stateChanged, epochMilliseconds: milliseconds, scores: [state.leftPoints, state.rightPoints], setNumber: state.currentSet, operationCode: "side_change_reminder"))
            case .matchReset:
                detailedActions.append(.init(type: .reset, epochMilliseconds: milliseconds, scores: [0, 0], setScores: [0, 0], operationCode: "reset"))
            case .matchFinished(let winner):
                detailedActions.append(.init(type: .matchFinished, epochMilliseconds: milliseconds, scores: [state.leftPoints, state.rightPoints], setScores: [state.leftSets, state.rightSets], winner: winner == .left ? .team1 : (winner == .right ? .team2 : nil), operationCode: "finish"))
            case .pingPongAdministrativeAction(let action):
                let actionType: DetailedScoreActionType = action.type == .timeout || action.type == .medicalTimeout ? .timeout : .foul
                detailedActions.append(.init(
                    type: actionType,
                    epochMilliseconds: action.epochMilliseconds,
                    team: action.side == .left ? .team1 : .team2,
                    scores: [state.leftPoints, state.rightPoints],
                    setScores: [state.leftSets, state.rightSets],
                    operationCode: action.type.rawValue
                ))
            case .badmintonMisconduct(let action):
                // 羽毛球判罚记录：operationCode 逐字对齐安卓 bd_yellow/bd_red/bd_disqualify，
                // 保证跨端记录文案与互通一致（取消资格随后追加 finish 记录）。
                detailedActions.append(.init(
                    type: .foul,
                    epochMilliseconds: action.epochMilliseconds,
                    team: action.side == .left ? .team1 : .team2,
                    scores: [state.leftPoints, state.rightPoints],
                    setScores: [state.leftSets, state.rightSets],
                    operationCode: action.kind.rawValue
                ))
            case .officialBreakChanged:
                break
            }
        }
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

        // Bundles written before record checkpoints were introduced still carry
        // the engine timeline. Every action produced by one accepted intent uses
        // that intent's timestamp, so remove the complete trailing action group.
        if let fallbackEpochMilliseconds {
            while detailedActions.last?.epochMilliseconds == fallbackEpochMilliseconds {
                detailedActions.removeLast()
            }
        }
        completedSetScores = Self.completedSetScores(from: detailedActions)
    }

    private func updateCompletedSetScores(for events: [RallyMatchEvent]) {
        if events.contains(where: { if case .matchReset = $0 { return true }; return false }) {
            completedSetScores.removeAll()
            return
        }
        for event in events {
            if case let .setCompleted(_, _, leftPoints, rightPoints, _, _) = event {
                completedSetScores.append(VoiceSetScore(leftGames: leftPoints, rightGames: rightPoints))
            }
        }
    }

    private func trimCompletedSetScores(toMatch state: RallyMatchState) {
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

    private func synchronizeParticipants(for state: RallyMatchState) {
        let existing = machine.currentSession.participants
        let participants: [SessionParticipant]
        if let doubles = state.doubles {
            let names = doubles.playerNames
            participants = names.indices.map { index in
                let existingParticipant = existing.first { $0.id == Self.doublesParticipantID(for: index) }
                return SessionParticipant(
                    id: Self.doublesParticipantID(for: index),
                    name: names[index],
                    role: existingParticipant?.role ?? "player"
                )
            }
        } else {
            participants = [
                .init(id: TeamID.team0.rawValue, name: state.leftName, role: "team"),
                .init(id: TeamID.team1.rawValue, name: state.rightName, role: "team")
            ]
        }
        guard participants != existing else { return }
        machine.updateParticipants(participants)
    }

    private static func doublesParticipantID(for index: Int) -> String {
        ["left-top", "right-top", "left-bottom", "right-bottom"][min(max(index, 0), 3)]
    }

    private static func participants(for state: RallyMatchState) -> [SessionParticipant] {
        if let doubles = state.doubles {
            return doubles.playerNames.indices.map { index in
                SessionParticipant(
                    id: doublesParticipantID(for: index),
                    name: doubles.playerNames[index],
                    role: "player"
                )
            }
        }
        return [
            .init(id: TeamID.team0.rawValue, name: state.leftName, role: "team"),
            .init(id: TeamID.team1.rawValue, name: state.rightName, role: "team")
        ]
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
        let matchTimeEnabled = showMatchTimeEnabled
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
                        try self.makeFinishedRecord(session, actions: actions, voiceEnabled: voiceEnabled, matchTimeEnabled: matchTimeEnabled)
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
        _ session: ScoreSession<RallyMatchState, RallyMatchEvent>,
        actions: [DetailedScoreAction],
        voiceEnabled: Bool,
        matchTimeEnabled: Bool
    ) throws -> ScoreboardRecord? {
        let state = session.state
        guard session.status == .finished, state.finished else { return nil }
        guard let appGameType = GameType(scoreCoreGameType: gameType) else { return nil }
        let snapshot = try JSONEncoder().encode(session)
        let winner: String? = if let forfeitingSide = state.pingPongForfeitSide {
            forfeitingSide == .left ? "right" : "left"
        } else if state.finished && state.leftSets != state.rightSets {
            state.leftSets > state.rightSets ? "left" : "right"
        } else {
            nil
        }
        let record = ScoreboardRecord(
            id: sessionId.uuidString,
            gameType: appGameType,
            startTime: startedAt,
            endTime: state.finished ? Date() : nil,
            duration: Date().timeIntervalSince(startedAt),
            team1Name: state.leftName,
            team2Name: state.rightName,
            team1FinalScore: state.leftPoints,
            team2FinalScore: state.rightPoints,
            team1SetScore: state.leftSets,
            team2SetScore: state.rightSets,
            winner: winner,
            detailedActions: actions,
            setResults: ScoreboardRecordActionAdapter.setResults(from: actions),
            totalScoreChanges: actions.count,
            projectConfiguration: ScoreboardRecordConfiguration.rally(
                gameType: gameType,
                state: state,
                voiceAnnouncement: voiceEnabled,
                showMatchTime: matchTimeEnabled,
                competitionFormat: gameType == .shuttlecock
                    ? (state.competitionFormat ?? (state.doubles == nil ? .singles : .doubles))
                    : nil,
                competitionPlayerNames: state.competitionPlayerNames
            ),
            stateSnapshot: snapshot,
            status: .finished
        )
        return record
    }

    private func reportPersistenceFailure(_ error: Error, forcePresentation: Bool = false) {
        logger.error("Failed to persist rally session \(self.sessionId.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
        let now = Date()
        if forcePresentation
            || lastPersistenceErrorPresentationAt.map({ now.timeIntervalSince($0) >= 5 }) != false {
            lastPersistenceErrorPresentationAt = now
            persistenceFailureSignal &+= 1
        }
    }

    private static func doublesState(
        for gameType: ScoreCore.GameType,
        participants: [SessionParticipant]?,
        openingServer: MatchSide
    ) -> RallyDoublesState? {
        let namesByID = (participants ?? []).reduce(into: [String: String]()) { names, participant in
            names[participant.id] = participant.name
        }
        let defaults = DefaultParticipantNames.doublesMembers
        let names = [
            namesByID["left-top"] ?? defaults[0],
            namesByID["right-top"] ?? defaults[2],
            namesByID["left-bottom"] ?? defaults[1],
            namesByID["right-bottom"] ?? defaults[3]
        ]
        switch gameType {
        case .pingpongDoubles:
            return .pingPong(
                playerNames: names,
                openingServerSlotIndex: openingServer == .left ? 0 : 1,
                openingReceiverSlotIndex: openingServer == .left ? 1 : 0
            )
        case .badmintonDoubles:
            return .badminton(playerNames: names, servingTeam0: openingServer == .left)
        case .shuttlecock:
            return .badminton(playerNames: names, servingTeam0: openingServer == .left)
        case .squash:
            return nil
        case .pickleballDoubles:
            return .pickleball(playerNames: names, servingTeam0: openingServer == .left)
        case .foosballDoubles:
            return .foosball(playerNames: names)
        default:
            return nil
        }
    }
}
