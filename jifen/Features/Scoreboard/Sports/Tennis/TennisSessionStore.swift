import Foundation
import Observation
import PersistenceCore
import RecordCore
import ScoreCore
import SessionCore

@MainActor
@Observable
final class TennisSessionStore {
    private let core: ScoreSessionCore<TennisMatchReducer>
    private let archiveRepository: SessionArchiveRepository
    private var detailedActions: [DetailedScoreAction]
    private var completedSetScores: [VoiceSetScore] = []

    private(set) var state: TennisMatchState

    var teamScreenLayout: TeamScreenLayout {
        TeamScreenLayout(sidesSwapped: state.sidesSwapped)
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
        voiceAnnouncementEnabled: Bool = false
    ) {
        let state = TennisMatchState(
            leftName: leftName,
            rightName: rightName,
            rules: rules,
            openingServer: openingServer
        )
        self.init(gameType: gameType, state: state, voiceAnnouncementEnabled: voiceAnnouncementEnabled)
    }

    convenience init(
        gameType: ScoreCore.GameType,
        state: TennisMatchState,
        voiceAnnouncementEnabled: Bool = false
    ) {
        let session = ScoreSession<TennisMatchState, TennisMatchEvent>(
            gameType: gameType,
            ruleFamily: .s1,
            reducerType: ScoreboardKernelRegistry.descriptor(for: gameType).reducerType,
            state: state,
            participants: [
                .init(id: "left", name: state.leftName, role: "team"),
                .init(id: "right", name: state.rightName, role: "team")
            ],
            metadata: .init(extras: ["startedAtEpochMilliseconds": String(Int64(Date().timeIntervalSince1970 * 1_000))])
        )
        self.init(session: session, voiceAnnouncementEnabled: voiceAnnouncementEnabled)
    }

    private init(session: ScoreSession<TennisMatchState, TennisMatchEvent>, voiceAnnouncementEnabled: Bool) {
        gameType = session.gameType
        sessionId = session.sessionId
        let startedMilliseconds = session.metadata.extras["startedAtEpochMilliseconds"].flatMap(Int64.init)
        startedAt = startedMilliseconds.map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) } ?? Date()
        core = ScoreSessionCore(
            seedSession: session,
            reducer: TennisMatchReducer(),
            shouldFinish: { _, state in state.finished }
        )
        archiveRepository = SessionArchiveRepository()
        state = session.state
        detailedActions = ScoreboardRecordManager.shared.getRecordById(session.sessionId.uuidString)?.detailedActions ?? []
        self.voiceAnnouncementEnabled = voiceAnnouncementEnabled
    }

    convenience init?(restoring sessionId: UUID) {
        let url = SessionArchiveRepository.snapshotURL(sessionId: sessionId)
        guard let data = try? Data(contentsOf: url),
              let session = try? JSONDecoder().decode(ScoreSession<TennisMatchState, TennisMatchEvent>.self, from: data),
              session.status == .live else {
            return nil
        }
        self.init(session: session, voiceAnnouncementEnabled: false)
    }

    func send(_ intent: TennisMatchIntent, onEvents: (([TennisMatchEvent]) -> Void)? = nil) {
        Task { [weak self, core] in
            guard let self else { return }
            let before = self.state
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            guard case .accepted(let session, let events) = await core.dispatch(actorId: "phone", intent: intent, at: now) else { return }
            self.state = session.state
            onEvents?(events)
            try? await self.archiveRepository.save(session)
            self.append(events: events, at: now, state: session.state)
            self.persistRecord(session)
            self.speak(intent: intent, before: before, after: session.state, events: events)
        }
    }

    func undo(completion: ((Bool) -> Void)? = nil) {
        Task { [weak self, core] in
            guard await core.undo(actorId: "phone"), let self else {
                completion?(false)
                return
            }
            let session = await core.snapshot()
            self.state = session.state
            completion?(true)
            try? await self.archiveRepository.save(session)
            self.detailedActions.append(.init(
                type: .undo,
                epochMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000),
                scores: [session.state.leftPoints, session.state.rightPoints],
                setScores: [session.state.leftSets, session.state.rightSets],
                operationCode: "undo"
            ))
            self.persistRecord(session)
        }
    }

    func replaceDisplayedState(_ state: TennisMatchState) {
        self.state = state
    }

    func persistSnapshot(completion: ((Bool) -> Void)? = nil) {
        Task { [core, archiveRepository] in
            let session = await core.snapshot()
            do {
                try await archiveRepository.save(session)
                self.persistRecord(session)
                completion?(true)
            } catch {
                completion?(false)
            }
        }
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

    private func persistRecord(_ session: ScoreSession<TennisMatchState, TennisMatchEvent>) {
        guard let appGameType = GameType(scoreCoreGameType: gameType) else { return }
        let snapshot = try? JSONEncoder().encode(session)
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
            projectConfiguration: [
                "maxSets": AnyCodable(state.rules.maxSets),
                "tieBreakPoints": AnyCodable(state.rules.tieBreakPoints),
                "gamesPerSet": AnyCodable(state.rules.gamesPerSet),
                "setScoringMode": AnyCodable(state.rules.setScoringMode.rawValue),
                "voiceAnnouncement": AnyCodable(voiceAnnouncementEnabled)
            ],
            stateSnapshot: snapshot,
            status: state.finished ? .finished : .draft
        )
        try? ScoreboardRecordManager.shared.saveScoreboardRecord(record)
        ScoreboardRecordsViewModel.shared.refreshRecords()
    }
}
