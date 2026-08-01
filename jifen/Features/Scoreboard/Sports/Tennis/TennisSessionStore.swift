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

    private let core: ScoreSessionCore<TennisMatchReducer>
    private let resumeRepository: ResumeSessionRepository
    private var detailedActions: [DetailedScoreAction]
    private var completedSetScores: [VoiceSetScore] = []
    private var lastAppliedRemoteRevision: UInt64?
    private var operationTask: Task<Void, Never>?
    private var lastPersistenceErrorPresentationAt: Date?
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
            metadata: .init(extras: ["startedAtEpochMilliseconds": String(Int64(Date().timeIntervalSince1970 * 1_000))])
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
        core = ScoreSessionCore(
            seedSession: session,
            reducer: TennisMatchReducer(),
            shouldFinish: { _, state in state.finished }
        )
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
            reducer: TennisMatchReducer(),
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

    func makeFreshMatchStore() -> TennisSessionStore {
        let resetState = TennisMatchReducer().reduce(
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

    func send(_ intent: TennisMatchIntent, onEvents: (([TennisMatchEvent]) -> Void)? = nil) {
        let previousTask = operationTask
        operationTask = Task { [weak self, core] in
            _ = await previousTask?.value
            guard let self else { return }
            let before = self.state
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            guard case .accepted(let session, let events) = await core.dispatch(actorId: "phone", intent: intent, at: now) else { return }
            self.state = session.state
            onEvents?(events)
            await self.synchronizeParticipants(for: session.state)
            let bundle = await core.resumeBundle()
            self.append(events: events, at: now, state: session.state)
            do {
                try await self.resumeRepository.saveResumeBundle(bundle)
                try self.persistRecord(bundle.currentSession)
            } catch {
                self.reportPersistenceFailure(error)
            }
            self.speak(intent: intent, before: before, after: session.state, events: events)
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
            await self.synchronizeParticipants(for: session.state)
            completion?(true)
            let bundle = await core.resumeBundle()
            self.detailedActions.append(.init(
                type: .undo,
                epochMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000),
                scores: [session.state.leftPoints, session.state.rightPoints],
                setScores: [session.state.leftSets, session.state.rightSets],
                operationCode: "undo"
            ))
            do {
                try await self.resumeRepository.saveResumeBundle(bundle)
                try self.persistRecord(session)
            } catch {
                self.reportPersistenceFailure(error)
            }
        }
    }

    @discardableResult
    func applyAuthoritativeState(
        _ state: TennisMatchState,
        detailedActions incoming: [DetailedScoreAction],
        revision: UInt64,
        persistFormalRecord: Bool = true
    ) async -> Bool {
        if let lastAppliedRemoteRevision, revision <= lastAppliedRemoteRevision {
            return false
        }
        lastAppliedRemoteRevision = revision
        _ = await operationTask?.value
        let session = await core.rebase(
            to: state,
            status: state.finished ? .finished : .live
        )
        guard lastAppliedRemoteRevision == revision else { return false }
        self.state = session.state
        mergeRemoteActions(incoming)
        await synchronizeParticipants(for: session.state)
        let bundle = await core.resumeBundle()
        do {
            try await resumeRepository.saveResumeBundle(bundle)
            if persistFormalRecord {
                try persistRecord(bundle.currentSession)
            }
        } catch {
            reportPersistenceFailure(error)
        }
        return true
    }

    func mergeRemoteActions(_ incoming: [DetailedScoreAction]) {
        guard !incoming.isEmpty else { return }
        detailedActions = incoming.sorted {
            ($0.epochMilliseconds ?? 0, $0.id.uuidString) < ($1.epochMilliseconds ?? 0, $1.id.uuidString)
        }
    }

    func persistSnapshot(completion: ((Bool) -> Void)? = nil) {
        let previousTask = operationTask
        operationTask = Task { [core, resumeRepository] in
            _ = await previousTask?.value
            let bundle = await core.resumeBundle()
            do {
                try await resumeRepository.saveResumeBundle(bundle)
                try self.persistRecord(bundle.currentSession)
                completion?(true)
            } catch {
                self.reportPersistenceFailure(error, forcePresentation: true)
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

    private func synchronizeParticipants(for state: TennisMatchState) async {
        let participants = Self.participants(for: state)
        guard await core.snapshot().participants != participants else { return }
        _ = await core.updateParticipants(participants)
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

    private func speak(
        intent: TennisMatchIntent,
        before: TennisMatchState,
        after: TennisMatchState,
        events: [TennisMatchEvent]
    ) {
        guard voiceAnnouncementEnabled else { return }

        // Append completed set first (Android / Harmony order), then flip history on exchange.
        for event in events {
            if case let .setCompleted(_, _, leftGames, rightGames, _, _) = event {
                completedSetScores.append(VoiceSetScore(leftGames: leftGames, rightGames: rightGames))
            }
        }
        let sideChanged = events.contains {
            if case .sidesExchanged = $0 { return true }
            return false
        }
        if sideChanged {
            completedSetScores = completedSetScores.map { $0.swapped() }
        }
        if events.contains(where: { if case .matchReset = $0 { return true }; return false }) {
            completedSetScores = []
        }

        let payloads = TennisVoiceAnnouncementMapper.payloads(
            gameType: gameType,
            before: before,
            after: after,
            intent: intent,
            events: events,
            completedSetScores: completedSetScores
        )
        for payload in payloads {
            ScoreVoiceAnnouncer.shared.speak(payload)
        }
    }

    private func append(events: [TennisMatchEvent], at milliseconds: Int64, state: TennisMatchState) {
        for event in events {
            switch event {
            case .pointScored(let side, let left, let right):
                detailedActions.append(.init(
                    type: .scoreChanged,
                    epochMilliseconds: milliseconds,
                    team: side == .left ? .team1 : .team2,
                    scores: [left, right],
                    setScores: [state.leftSets, state.rightSets],
                    scoreChange: 1,
                    operationCode: "point"
                ))
            case .gameCompleted(let winner, let leftGames, let rightGames, _):
                detailedActions.append(.init(
                    type: .stateChanged,
                    epochMilliseconds: milliseconds,
                    team: winner == .left ? .team1 : .team2,
                    scores: [leftGames, rightGames],
                    setScores: [state.leftSets, state.rightSets],
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
                    setScores: [state.leftSets, state.rightSets],
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
                    setScores: [state.leftSets, state.rightSets],
                    winner: winner.map { $0 == .left ? .team1 : .team2 },
                    operationCode: "finish"
                ))
            case .matchReset:
                detailedActions.append(.init(
                    type: .reset,
                    epochMilliseconds: milliseconds,
                    scores: [0, 0],
                    setScores: [0, 0],
                    operationCode: "reset"
                ))
            default:
                break
            }
        }
    }

    private func persistRecord(_ session: ScoreSession<TennisMatchState, TennisMatchEvent>) throws {
        guard session.status == .finished, state.finished else { return }
        guard let appGameType = GameType(scoreCoreGameType: gameType) else { return }
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
            team1SetScore: state.leftSets,
            team2SetScore: state.rightSets,
            winner: winner,
            detailedActions: detailedActions,
            setResults: ScoreboardRecordActionAdapter.setResults(from: detailedActions),
            totalScoreChanges: detailedActions.count,
            projectConfiguration: ScoreboardRecordConfiguration.tennis(
                gameType: gameType,
                state: state,
                voiceAnnouncement: voiceAnnouncementEnabled
            ),
            stateSnapshot: snapshot,
            status: .finished
        )
        try ScoreboardRecordManager.shared.saveScoreboardRecord(record)
        ScoreboardRecordsViewModel.shared.refreshRecords()
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
