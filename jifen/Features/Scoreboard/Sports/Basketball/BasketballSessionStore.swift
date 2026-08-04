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

    private let core: ScoreSessionCore<BasketballMatchReducer>
    private let resumeRepository: ResumeSessionRepository
    private var clockTask: Task<Void, Never>?
    private var detailedActions: [DetailedScoreAction]
    private var operationTask: Task<Void, Never>?
    private var hasPersistedFinishedRecord = false

    private(set) var state: BasketballMatchState
    var actionTimeline: [DetailedScoreAction] { detailedActions }
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
        detailedActions = ScoreboardRecordManager.shared.getRecordById(session.sessionId.uuidString)?.detailedActions ?? []
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
        detailedActions = ScoreboardRecordManager.shared.getRecordById(session.sessionId.uuidString)?.detailedActions ?? []
    }

    convenience init?(restoring sessionId: UUID) {
        guard let data = try? ResumeSessionRepository.loadPayload(
            sessionId: sessionId,
            expectedKind: .scoreSessionBundle
        ) else {
            return nil
        }
        if let bundle = try? JSONDecoder().decode(ResumeBundle.self, from: data),
           bundle.currentSession.status == .live {
            self.init(resumeBundle: bundle)
        } else {
            return nil
        }
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
            if session.status == .live {
                self.hasPersistedFinishedRecord = false
            }
            await self.synchronizeParticipants(for: session.state)
            let bundle = await core.resumeBundle()
            if intent != .tickClock {
                // The final action is part of the formal record and must be in
                // memory before the record-first commit starts.
                self.append(intent: intent, at: now, state: session.state)
            }
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
            self.detailedActions.append(.init(type: .undo, epochMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000), scores: [session.state.leftScore, session.state.rightScore], periodNumber: session.state.currentPeriod, operationCode: "undo"))
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

    func persistSnapshot(completion: ((Bool) -> Void)? = nil) {
        let previousTask = operationTask
        operationTask = Task { [core] in
            _ = await previousTask?.value
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
        let pending = operationTask
        Task {
            _ = await pending?.value
            completion()
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

    private func persist(_ bundle: ResumeBundle) async throws {
        let session = bundle.currentSession
        if session.status == .live {
            try await resumeRepository.saveResumeBundle(bundle)
            return
        }
        guard let record = try makeFinishedRecord(session) else { return }
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
            ScoreboardPersistenceFailureReporter.report(
                cleanupError,
                context: "Failed to clean finished basketball resume \(sessionId.uuidString)"
            )
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
            detailedActions: detailedActions,
            setResults: ScoreboardRecordActionAdapter.setResults(from: detailedActions),
            totalScoreChanges: detailedActions.count,
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
