import Foundation
import Observation
import PersistenceCore
import RecordCore
import ScoreCore
import SessionCore

@MainActor
@Observable
final class BasketballSessionStore {
    private let core: ScoreSessionCore<BasketballMatchReducer>
    private let archiveRepository: SessionArchiveRepository
    private var clockTask: Task<Void, Never>?
    private var detailedActions: [DetailedScoreAction]

    private(set) var state: BasketballMatchState
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
        ruleSet: BasketballRuleSet = .fiba
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
        self.init(session: session)
    }

    private init(session: ScoreSession<BasketballMatchState, BasketballMatchEvent>) {
        sessionId = session.sessionId
        let startedMilliseconds = session.metadata.extras["startedAtEpochMilliseconds"].flatMap(Int64.init)
        startedAt = startedMilliseconds.map { Date(timeIntervalSince1970: TimeInterval($0) / 1_000) } ?? Date()
        core = ScoreSessionCore(
            seedSession: session,
            reducer: BasketballMatchReducer(),
            shouldFinish: { _, state in state.finished }
        )
        archiveRepository = SessionArchiveRepository()
        state = session.state
        detailedActions = ScoreboardRecordManager.shared.getRecordById(session.sessionId.uuidString)?.detailedActions ?? []
    }

    convenience init?(restoring sessionId: UUID) {
        let url = SessionArchiveRepository.snapshotURL(sessionId: sessionId)
        guard let data = try? Data(contentsOf: url),
              let session = try? JSONDecoder().decode(ScoreSession<BasketballMatchState, BasketballMatchEvent>.self, from: data),
              session.status == .live else {
            return nil
        }
        self.init(session: session)
    }

    func send(_ intent: BasketballMatchIntent, recordsUndo: Bool = true) {
        Task { [weak self, core] in
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            let result = if recordsUndo {
                await core.dispatch(actorId: "phone", intent: intent, at: now)
            } else {
                await core.dispatchNonUndoable(actorId: "phone", intent: intent, at: now)
            }
            guard case .accepted(let session, _) = result, let self else { return }
            self.state = session.state
            try? await self.archiveRepository.save(session)
            if intent != .tickClock {
                self.append(intent: intent, at: now, state: session.state)
                self.persistRecord(session)
            }
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
            self.detailedActions.append(.init(type: .undo, epochMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000), scores: [session.state.leftScore, session.state.rightScore], periodNumber: session.state.currentPeriod, operationCode: "undo"))
            self.persistRecord(session)
        }
    }

    func startClock() {
        guard clockTask == nil else { return }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.send(.tickClock, recordsUndo: false)
            }
        }
    }

    func stopClock() {
        clockTask?.cancel()
        clockTask = nil
    }

    func persistSnapshot() {
        Task { [core, archiveRepository] in
            let session = await core.snapshot()
            try? await archiveRepository.save(session)
            self.persistRecord(session)
        }
    }

    func replaceDisplayedState(_ state: BasketballMatchState) {
        self.state = state
    }

    private func append(intent: BasketballMatchIntent, at milliseconds: Int64, state: BasketballMatchState) {
        let action: DetailedScoreAction
        switch intent {
        case .addPoints(let side, let points, _):
            action = .init(type: .scoreChanged, epochMilliseconds: milliseconds, team: side == .left ? .team1 : .team2, scores: [state.leftScore, state.rightScore], periodNumber: state.currentPeriod, scoreChange: points, operationCode: "basketball_score_\(points)")
        case .adjustScore(let side, let delta):
            action = .init(type: .scoreChanged, epochMilliseconds: milliseconds, team: side == .left ? .team1 : .team2, scores: [state.leftScore, state.rightScore], periodNumber: state.currentPeriod, scoreChange: delta, operationCode: "score_adjust")
        case .addFoul(let side), .removeFoul(let side):
            action = .init(type: .foul, epochMilliseconds: milliseconds, team: side == .left ? .team1 : .team2, scores: [state.leftScore, state.rightScore], periodNumber: state.currentPeriod, operationCode: String(describing: intent))
        case .useTimeout(let side):
            action = .init(type: .timeout, epochMilliseconds: milliseconds, team: side == .left ? .team1 : .team2, scores: [state.leftScore, state.rightScore], periodNumber: state.currentPeriod, operationCode: "timeout")
        case .advanceToNextPeriod, .enterOvertime:
            action = .init(type: .periodFinished, epochMilliseconds: milliseconds, scores: [state.leftScore, state.rightScore], periodNumber: max(1, state.currentPeriod - (state.isOvertime ? 0 : 1)), operationCode: state.isOvertime ? "overtime" : "period_finished")
        case .exchangeSides:
            action = .init(type: .sideChanged, epochMilliseconds: milliseconds, scores: [state.leftScore, state.rightScore], periodNumber: state.currentPeriod, operationCode: "exchange_sides")
        case .reset:
            action = .init(type: .reset, epochMilliseconds: milliseconds, scores: [state.leftScore, state.rightScore], periodNumber: state.currentPeriod, operationCode: "reset")
        case .finish:
            action = .init(type: .matchFinished, epochMilliseconds: milliseconds, scores: [state.leftScore, state.rightScore], periodNumber: state.currentPeriod, winner: state.leftScore == state.rightScore ? nil : (state.leftScore > state.rightScore ? .team1 : .team2), operationCode: "finish")
        default:
            action = .init(type: .stateChanged, epochMilliseconds: milliseconds, scores: [state.leftScore, state.rightScore], periodNumber: state.currentPeriod, operationCode: String(describing: intent))
        }
        detailedActions.append(action)
    }

    private func persistRecord(_ session: ScoreSession<BasketballMatchState, BasketballMatchEvent>) {
        let appGameType: GameType = state.gameMode == .threeXThree ? .threeBasketball : .basketball
        let snapshot = try? JSONEncoder().encode(session)
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
            detailedActions: detailedActions,
            setResults: ScoreboardRecordActionAdapter.setResults(from: detailedActions),
            totalScoreChanges: detailedActions.count,
            projectConfiguration: [
                "basketballMode": AnyCodable(state.gameMode == .threeXThree ? "three_x_three" : "five_v_five"),
                "basketballRuleSet": AnyCodable(String(describing: state.ruleSet).lowercased())
            ],
            stateSnapshot: snapshot,
            status: state.finished ? .finished : .draft
        )
        try? ScoreboardRecordManager.shared.saveScoreboardRecord(record)
        ScoreboardRecordsViewModel.shared.refreshRecords()
    }
}
