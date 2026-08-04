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

    private let core: ScoreSessionCore<RallyMatchReducer>
    private let resumeRepository: ResumeSessionRepository
    private var detailedActions: [DetailedScoreAction]
    private var lastAppliedRemoteRevision: UInt64?
    private var operationTask: Task<Void, Never>?
    private var lastPersistenceErrorPresentationAt: Date?
    private var hasPersistedFinishedRecord = false
    private let logger = Logger(subsystem: "com.douhua.jifen.ios", category: "RallyPersistence")

    private(set) var state: RallyMatchState
    private(set) var persistenceFailureSignal = 0
    var actionTimeline: [DetailedScoreAction] { detailedActions }
    let gameType: ScoreCore.GameType
    let sessionId: UUID
    let startedAt: Date
    var voiceAnnouncementEnabled: Bool

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
        openingServer: MatchSide = .left,
        voiceAnnouncementEnabled: Bool = false,
        resumeRepository: ResumeSessionRepository? = nil
    ) {
        let providedParticipants = participants?.filter { !$0.name.isEmpty }
        let initial = RallyMatchEngine.initial(
            leftName: leftName,
            rightName: rightName,
            rules: rules,
            openingServer: openingServer,
            doubles: Self.doublesState(
                for: gameType,
                participants: providedParticipants,
                openingServer: openingServer
            )
        )
        self.init(
            gameType: gameType,
            state: initial,
            participants: providedParticipants,
            voiceAnnouncementEnabled: voiceAnnouncementEnabled,
            resumeRepository: resumeRepository
        )
    }

    convenience init(
        gameType: ScoreCore.GameType,
        state: RallyMatchState,
        participants: [SessionParticipant]? = nil,
        voiceAnnouncementEnabled: Bool = false,
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
            metadata: .init(extras: ["startedAtEpochMilliseconds": String(Int64(Date().timeIntervalSince1970 * 1_000))])
        )
        self.init(
            session: session,
            voiceAnnouncementEnabled: voiceAnnouncementEnabled,
            resumeRepository: resumeRepository
        )
    }

    private init(
        session: ScoreSession<RallyMatchState, RallyMatchEvent>,
        voiceAnnouncementEnabled: Bool,
        resumeRepository: ResumeSessionRepository? = nil
    ) {
        gameType = session.gameType
        sessionId = session.sessionId
        let startedMilliseconds = session.metadata.extras["startedAtEpochMilliseconds"].flatMap(Int64.init)
        startedAt = startedMilliseconds.map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) } ?? Date()
        core = ScoreSessionCore(seedSession: session, reducer: RallyMatchReducer(), shouldFinish: { _, state in state.finished })
        self.resumeRepository = resumeRepository ?? ResumeSessionRepository()
        state = session.state
        detailedActions = ScoreboardRecordManager.shared.getRecordById(session.sessionId.uuidString)?.detailedActions ?? []
        self.voiceAnnouncementEnabled = voiceAnnouncementEnabled
    }

    private init(resumeBundle: ResumeBundle, voiceAnnouncementEnabled: Bool) {
        let session = resumeBundle.currentSession
        gameType = session.gameType
        sessionId = session.sessionId
        let startedMilliseconds = session.metadata.extras["startedAtEpochMilliseconds"].flatMap(Int64.init)
        startedAt = startedMilliseconds.map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) } ?? Date()
        core = ScoreSessionCore(
            resumeBundle: resumeBundle,
            reducer: RallyMatchReducer(),
            shouldFinish: { _, state in state.finished }
        )
        resumeRepository = ResumeSessionRepository()
        state = session.state
        detailedActions = ScoreboardRecordManager.shared.getRecordById(session.sessionId.uuidString)?.detailedActions ?? []
        self.voiceAnnouncementEnabled = voiceAnnouncementEnabled
    }

    convenience init?(restoring sessionId: UUID) {
        guard let data = try? ResumeSessionRepository.loadPayload(
            sessionId: sessionId,
            expectedKind: .scoreSessionBundle
        ) else {
            return nil
        }
        let voiceAnnouncementEnabled = false
        if let bundle = try? JSONDecoder().decode(ResumeBundle.self, from: data),
           bundle.currentSession.status == .live {
            self.init(resumeBundle: bundle, voiceAnnouncementEnabled: voiceAnnouncementEnabled)
        } else {
            return nil
        }
    }

    func makeFreshMatchStore() -> RallySessionStore {
        let resetState = RallyMatchReducer().reduce(
            state: state,
            intent: .reset,
            at: Int64(Date().timeIntervalSince1970 * 1_000)
        ).state
        return RallySessionStore(
            gameType: gameType,
            state: resetState,
            participants: Self.participants(for: resetState),
            voiceAnnouncementEnabled: voiceAnnouncementEnabled,
            resumeRepository: resumeRepository
        )
    }

    func send(_ intent: RallyMatchIntent, onEvents: (([RallyMatchEvent]) -> Void)? = nil) {
        let previousTask = operationTask
        operationTask = Task { [weak self, core] in
            _ = await previousTask?.value
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            guard case .accepted(let session, let events) = await core.dispatch(actorId: "phone", intent: intent, at: now),
                  let self else { return }
            self.state = session.state
            if session.status == .live {
                self.hasPersistedFinishedRecord = false
            }
            onEvents?(events)
            await self.synchronizeParticipants(for: session.state)
            let bundle = await core.resumeBundle()
            self.append(events: events, at: now, state: session.state)
            do {
                try await self.persist(bundle)
            } catch {
                self.reportPersistenceFailure(error)
            }
        }
    }

    func undo(completion: ((Bool) -> Void)? = nil) {
        let previousTask = operationTask
        operationTask = Task { [weak self, core] in
            _ = await previousTask?.value
            guard await core.undo(actorId: "phone"), let self else {
                completion?(false)
                return
            }
            let session = await core.snapshot()
            self.state = session.state
            if session.status == .live {
                self.hasPersistedFinishedRecord = false
            }
            await self.synchronizeParticipants(for: session.state)
            completion?(true)
            let bundle = await core.resumeBundle()
            self.detailedActions.append(.init(type: .undo, epochMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000), scores: [session.state.leftPoints, session.state.rightPoints], setScores: [session.state.leftSets, session.state.rightSets], setNumber: session.state.currentSet, operationCode: "undo"))
            do {
                try await self.persist(bundle)
            } catch {
                self.reportPersistenceFailure(error)
            }
        }
    }

    func persistSnapshot(completion: ((Bool) -> Void)? = nil) {
        let previousTask = operationTask
        operationTask = Task { [core] in
            _ = await previousTask?.value
            let bundle = await core.resumeBundle()
            do {
                try await self.persist(bundle)
                completion?(true)
            } catch {
                self.reportPersistenceFailure(error, forcePresentation: true)
                completion?(false)
            }
        }
    }

    @discardableResult
    func applyAuthoritativeState(
        _ state: RallyMatchState,
        detailedActions incoming: [DetailedScoreAction],
        revision: UInt64,
        persistFormalRecord: Bool = true
    ) async -> Bool {
        if let lastAppliedRemoteRevision, revision <= lastAppliedRemoteRevision {
            return false
        }
        // Reserve the revision before crossing the actor boundary so a newer
        // snapshot cannot be overwritten by an older Task resuming later.
        lastAppliedRemoteRevision = revision
        _ = await operationTask?.value
        let session = await core.rebase(
            to: state,
            status: state.finished ? .finished : .live
        )
        guard lastAppliedRemoteRevision == revision else { return false }
        self.state = session.state
        if session.status == .live || !persistFormalRecord {
            hasPersistedFinishedRecord = false
        }
        mergeRemoteActions(incoming)
        await synchronizeParticipants(for: session.state)
        let bundle = await core.resumeBundle()
        do {
            try await persist(bundle, persistFormalRecord: persistFormalRecord)
        } catch {
            reportPersistenceFailure(error)
        }
        return true
    }

    func flush(completion: @escaping () -> Void) {
        let pending = operationTask
        Task {
            _ = await pending?.value
            completion()
        }
    }

    func mergeRemoteActions(_ incoming: [DetailedScoreAction]) {
        guard !incoming.isEmpty else { return }
        detailedActions = incoming.sorted {
            ($0.epochMilliseconds ?? 0, $0.id.uuidString) < ($1.epochMilliseconds ?? 0, $1.id.uuidString)
        }
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
            }
        }
    }

    private func synchronizeParticipants(for state: RallyMatchState) async {
        let existing = await core.snapshot().participants
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
        _ = await core.updateParticipants(participants)
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

    private func persist(
        _ bundle: ResumeBundle,
        persistFormalRecord: Bool = true
    ) async throws {
        let session = bundle.currentSession
        if session.status == .live {
            try await resumeRepository.saveResumeBundle(bundle)
            return
        }
        // A linked follower does not own the formal record. Keep the last live
        // resume until the authoritative finished record is confirmed instead
        // of deleting the only recoverable copy here.
        guard persistFormalRecord,
              let record = try makeFinishedRecord(session) else { return }
        let coordinator = FinishedSessionCommitCoordinator(
            resumeRemover: { [resumeRepository] sessionId in
                try await resumeRepository.remove(sessionId: sessionId)
            }
        )
        let result: FinishedSessionCommitResult
        if hasPersistedFinishedRecord {
            result = await coordinator.cleanupResume(after: FinishedSessionRecordCommit(
                sessionId: sessionId,
                recordWritten: false
            ))
        } else {
            result = try await coordinator.commit(record, sessionId: sessionId)
        }
        hasPersistedFinishedRecord = true
        if result.recordWritten {
            ScoreboardRecordsViewModel.shared.refreshRecords()
        }
        if let cleanupError = result.cleanupError {
            reportPersistenceFailure(cleanupError)
        }
    }

    private func makeFinishedRecord(
        _ session: ScoreSession<RallyMatchState, RallyMatchEvent>
    ) throws -> ScoreboardRecord? {
        guard session.status == .finished, state.finished else { return nil }
        guard let appGameType = GameType(scoreCoreGameType: gameType) else { return nil }
        let snapshot = try JSONEncoder().encode(session)
        let winner: String? = state.finished && state.leftSets != state.rightSets ? (state.leftSets > state.rightSets ? "left" : "right") : nil
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
            detailedActions: detailedActions,
            setResults: ScoreboardRecordActionAdapter.setResults(from: detailedActions),
            totalScoreChanges: detailedActions.count,
            projectConfiguration: ScoreboardRecordConfiguration.rally(
                gameType: gameType,
                state: state,
                voiceAnnouncement: voiceAnnouncementEnabled
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
                openingReceiverSlotIndex: openingServer == .left ? 3 : 2
            )
        case .badmintonDoubles:
            return .badminton(playerNames: names, servingTeam0: openingServer == .left)
        case .pickleballDoubles:
            return .pickleball(playerNames: names, servingTeam0: openingServer == .left)
        case .foosballDoubles:
            return .foosball(playerNames: names)
        default:
            return nil
        }
    }
}
