import CryptoKit
import Foundation
import LinkCore
import RecordCore
import ScoreCore
import SessionCore

/// Native reducer state. The wire snapshot must preserve every field that can
/// change the outcome of a future operation.
public enum LinkedReducerSnapshot: Codable, Equatable, Sendable {
    case rally(RallyMatchState)
    case tennis(TennisMatchState)
    case archery(ArcheryMatchState)
    case eightBall(EightBallState)
    case nineBall(NineBallChaseState)
    case snooker(SnookerState)
    case football(FootballMatchState)
    case shotTraining(ShotTrainingState)

    fileprivate var family: WatchSetupFamily {
        switch self {
        case .rally: .rally
        case .tennis: .tennis
        case .archery: .archery
        case .eightBall: .eightBall
        case .nineBall: .nineBall
        case .snooker: .snooker
        case .football: .football
        case .shotTraining: .basketballTraining
        }
    }

    public var isFinished: Bool {
        switch self {
        case .rally(let state): state.finished
        case .tennis(let state): state.finished
        case .archery(let state): state.finished
        case .eightBall(let state): state.finished
        case .nineBall(let state): state.finished
        case .snooker(let state): state.finished
        case .football(let state): state.finished
        case .shotTraining(let state): state.finished
        }
    }

    fileprivate var finishIntent: LinkedScoreboardIntent {
        switch self {
        case .rally: .rally(.finish)
        case .tennis: .tennis(.finish)
        case .archery: .archery(.finish)
        case .eightBall: .eightBall(.finishMatch)
        case .nineBall: .nineBall(.finishMatch)
        case .snooker: .snooker(.finishMatch)
        case .football: .football(.finish)
        case .shotTraining: .shotTraining(.finish)
        }
    }

    fileprivate var scoreSummary: (scores: [Int], sets: [Int]) {
        switch self {
        case .rally(let state): ([state.leftPoints, state.rightPoints], [state.leftSets, state.rightSets])
        case .tennis(let state):
            ([state.leftPoints, state.rightPoints],
             state.rules.setScoringMode == .tiebreakOnly ? [] : [state.leftSets, state.rightSets])
        case .archery(let state): ([state.leftArrowSum, state.rightArrowSum], [state.leftSetPoints, state.rightSetPoints])
        case .eightBall(let state): ([state.leftPoints, state.rightPoints], [])
        case .nineBall(let state): (Array(state.playerPoints.prefix(state.playerCount)), [])
        case .snooker(let state): ([state.leftScore, state.rightScore], [state.leftFrames, state.rightFrames])
        case .football(let state): ([state.leftScore, state.rightScore], [])
        case .shotTraining(let state): ([state.counts.missed, state.counts.made], [])
        }
    }
}

/// Durable reducer state keeps a short-form replay log rather than a full
/// historical snapshot for each operation. Phone recovery preserves that log.
/// A Watch can install a later wire checkpoint as a fresh local replay seed.
public struct LinkedReducerState: Codable, Equatable, Sendable {
    fileprivate struct ReplayStep: Codable, Equatable, Sendable {
        let operation: LinkOperation
        let time: Int64
    }

    public let gameType: GameType
    public fileprivate(set) var current: LinkedReducerSnapshot
    fileprivate let seed: LinkedReducerSnapshot
    fileprivate var steps: [ReplayStep] = []

    public init?(gameType: GameType, state: LinkedReducerSnapshot) {
        guard WatchSportRegistry.descriptor(for: gameType)?.setupFamily == state.family else { return nil }
        if case .football(let football) = state, football.isFiveAside != (gameType == .football5v5) { return nil }
        self.gameType = gameType
        current = state
        seed = state
    }

    public var latestUndoableOperationId: UUID? {
        steps.last { !$0.operation.intent.isOfficialBreakChange }?.operation.opId
    }

    /// Score undo skips intervening football clock changes. Those changes
    /// remain in the replay log and must still succeed when the goal is removed.
    public var latestFootballScoreUndoTargetId: UUID? {
        guard case .football = current, !current.isFinished else { return nil }
        for step in steps.reversed() {
            let intent = step.operation.intent
            if intent.isFootballScoreEdit { return step.operation.opId }
            guard intent.isFootballClockEdit else { return nil }
        }
        return nil
    }

    /// Returns the newest retained shot matching every supplied filter.
    public func latestShotTrainingUndoTargetId(made: Bool? = nil, points: Int? = nil) -> UUID? {
        guard case .shotTraining = current, !current.isFinished else { return nil }
        for step in steps.suffix(ShotTrainingState.maxDetailedShots).reversed() {
            guard case .shotTraining(.recordShot(let shotPoints, let shotMade)) = step.operation.intent else {
                return nil
            }
            if (made == nil || made == shotMade) && (points == nil || points == shotPoints) {
                return step.operation.opId
            }
        }
        return nil
    }

    fileprivate func indexOfUndoTarget(_ target: UUID?) -> Int? {
        guard let target = target ?? latestUndoableOperationId else { return nil }
        guard let index = steps.lastIndex(where: { $0.operation.opId == target }) else { return nil }
        let intent = steps[index].operation.intent
        guard !intent.isOfficialBreakChange else { return nil }
        if index == steps.count - 1 { return index }

        let laterSteps = steps.suffix(from: index + 1)
        if laterSteps.allSatisfy({ $0.operation.intent.isOfficialBreakChange }) { return index }
        if intent.isFootballScoreEdit, laterSteps.allSatisfy({ $0.operation.intent.isFootballClockEdit }) {
            return index
        }
        if case .shotTraining(.recordShot) = intent,
           laterSteps.count < ShotTrainingState.maxDetailedShots,
           laterSteps.allSatisfy({ step in
               if case .shotTraining(.recordShot) = step.operation.intent { return true }
               return false
           }) {
            return index
        }
        return nil
    }
}

private extension LinkedScoreboardIntent {
    var isOfficialBreakChange: Bool {
        switch self {
        case .rally(.setOfficialBreakState), .tennis(.setOfficialBreakState): true
        default: false
        }
    }

    var isFootballScoreEdit: Bool {
        switch self {
        case .football(.goal), .football(.subtractGoal): true
        default: false
        }
    }

    var isFootballClockEdit: Bool {
        switch self {
        case .football(.kickOff), .football(.toggleClock), .football(.startClock), .football(.pauseClock),
             .football(.addStoppage), .football(.undoLastStoppage), .football(.advanceStage):
            true
        default:
            false
        }
    }
}

public struct LinkedReducerAdapter {
    public init() {}

    public func snapshot(_ state: LinkedReducerState) -> LinkedScoreboardSnapshot {
        switch state.current {
        case .rally(let value): .rally(value)
        case .tennis(let value): .tennis(value)
        case .archery(let value): .archery(value)
        case .eightBall(let value): .eightBall(value)
        case .nineBall(let value): .nineBall(value)
        case .snooker(let value): .snooker(value)
        case .football(let value): .football(value)
        case .shotTraining(let value): .basketballTraining(value)
        }
    }

    public func isFinished(_ state: LinkedReducerState) -> Bool { state.current.isFinished }

    public func state(gameType: GameType, from snapshot: LinkedScoreboardSnapshot) -> LinkedReducerState? {
        let native: LinkedReducerSnapshot
        switch snapshot {
        case .rally(let value): native = .rally(value)
        case .tennis(let value): native = .tennis(value)
        case .archery(let value): native = .archery(value)
        case .eightBall(let value): native = .eightBall(value)
        case .nineBall(let value): native = .nineBall(value)
        case .snooker(let value): native = .snooker(value)
        case .football(let value): native = .football(value)
        case .basketballTraining(let value): native = .shotTraining(value)
        }
        return LinkedReducerState(gameType: gameType, state: native)
    }

    public func installSnapshot(
        _ current: LinkedReducerState, _ snapshot: LinkedScoreboardSnapshot
    ) -> LinkedReducerState? {
        if self.snapshot(current) == snapshot { return current }
        return state(gameType: current.gameType, from: snapshot)
    }

    /// Derives the successor of a finished match. Pass the effective time
    /// from the accepted rollover receipt when opening or recovering its seed.
    public func nextMatchSnapshot(
        from finishedState: LinkedReducerState,
        at epochMilliseconds: Int64
    ) -> LinkedScoreboardSnapshot? {
        guard finishedState.current.isFinished, (0...9_000_000_000_000_000).contains(epochMilliseconds) else {
            return nil
        }

        func reset<Reducer: DomainReducer>(
            _ state: Reducer.State,
            with reducer: Reducer,
            intent: Reducer.Intent,
            wrap: (Reducer.State) -> LinkedReducerSnapshot
        ) -> LinkedReducerSnapshot? {
            let result = reducer.reduce(state: state, intent: intent, at: epochMilliseconds)
            return result.accepted ? wrap(result.state) : nil
        }

        let fresh = switch finishedState.current {
        case .rally(let state):
            reset(state, with: RallyMatchReducer(), intent: .reset, wrap: LinkedReducerSnapshot.rally)
        case .tennis(let state):
            reset(state, with: TennisMatchReducer(), intent: .reset, wrap: LinkedReducerSnapshot.tennis)
        case .archery(let state):
            reset(state, with: ArcheryMatchReducer(), intent: .reset, wrap: LinkedReducerSnapshot.archery)
        case .eightBall(let state):
            reset(state, with: EightBallReducer(), intent: .reset, wrap: LinkedReducerSnapshot.eightBall)
        case .nineBall(let state):
            reset(state, with: NineBallChaseReducer(), intent: .resetScores, wrap: LinkedReducerSnapshot.nineBall)
        case .snooker(let state):
            reset(state, with: SnookerReducer(), intent: .reset, wrap: LinkedReducerSnapshot.snooker)
        case .football(let state):
            reset(state, with: FootballMatchReducer(), intent: .reset(), wrap: LinkedReducerSnapshot.football)
        case .shotTraining(let state):
            reset(state, with: ShotTrainingReducer(), intent: .reset, wrap: LinkedReducerSnapshot.shotTraining)
        }

        guard let fresh, !fresh.isFinished,
              let seed = LinkedReducerState(gameType: finishedState.gameType, state: fresh) else { return nil }
        let wire = snapshot(seed)
        guard state(gameType: seed.gameType, from: wire)?.current == fresh else { return nil }
        return wire
    }

    public func transition(
        _ current: LinkedReducerState, _ op: LinkOperation, _ time: Int64
    ) -> LinkIntentTransition<LinkedReducerState> {
        // Keep millisecond-to-Date projections and their integer round trips
        // within the exact integer range of Double.
        guard (-9_000_000_000_000_000...9_000_000_000_000_000).contains(time) else {
            return .rejected(.reducerRejected)
        }
        guard !current.current.isFinished else { return .rejected(.matchFinished) }
        guard !op.intent.usesSportSpecificSessionControl else { return .rejected(.unsupportedSessionControl) }
        if case .undo(let target) = op.intent { return undo(current, op: op, target: target, at: time) }

        let intent = op.intent == .finish ? current.current.finishIntent : op.intent
        guard matches(intent, state: current.current) else { return .rejected(.intentFamilyMismatch) }
        guard let applied = apply(current.current, gameType: current.gameType, op: op, intent: intent, time: time) else {
            return .rejected(.reducerRejected)
        }

        var next = current
        next.current = applied.state
        if next.current != current.current {
            next.steps.append(.init(operation: op, time: time))
        }
        return .accepted(state: next, deltaActions: stabilized(applied.actions, opId: op.opId))
    }

    private func undo(
        _ current: LinkedReducerState, op: LinkOperation, target: UUID?, at time: Int64
    ) -> LinkIntentTransition<LinkedReducerState> {
        guard let index = current.indexOfUndoTarget(target) else { return .rejected(.undoTargetUnavailable) }
        var next = current
        let removed = next.steps.remove(at: index)
        var restored = next.seed
        for step in next.steps {
            let intent = step.operation.intent == .finish ? restored.finishIntent : step.operation.intent
            guard let replayed = apply(
                restored, gameType: next.gameType, op: step.operation, intent: intent, time: step.time, projectActions: false
            ) else { return .rejected(.undoTargetUnavailable) }
            restored = replayed.state
        }
        next.current = restored
        let score = restored.scoreSummary
        return .accepted(state: next, deltaActions: [
            DetailedScoreAction(
                id: op.opId, type: .undo, epochMilliseconds: time, scores: score.scores,
                setScores: score.sets, operationCode: "undo", operationPayload: removed.operation.opId.uuidString
            ),
        ])
    }

    private func matches(_ intent: LinkedScoreboardIntent, state: LinkedReducerSnapshot) -> Bool {
        switch (state, intent) {
        case (.rally, .rally), (.tennis, .tennis), (.archery, .archery), (.eightBall, .eightBall),
             (.nineBall, .nineBall), (.snooker, .snooker), (.football, .football), (.shotTraining, .shotTraining):
            true
        default:
            false
        }
    }

    private struct Applied {
        let state: LinkedReducerSnapshot
        let actions: [DetailedScoreAction]
    }

    private func apply(
        _ state: LinkedReducerSnapshot,
        gameType: GameType,
        op: LinkOperation,
        intent: LinkedScoreboardIntent,
        time: Int64,
        projectActions: Bool = true
    ) -> Applied? {
        func reduce<Reducer: DomainReducer>(
            _ state: Reducer.State,
            _ intent: Reducer.Intent,
            reducer: Reducer,
            wrap: (Reducer.State) -> LinkedReducerSnapshot,
            project: (Reducer.Intent, [Reducer.Event], Reducer.State, Date) -> [DetailedScoreAction]
        ) -> Applied? {
            let descriptor = ScoreboardKernelRegistry.descriptor(for: gameType)
            let session = ScoreSession<Reducer.State, Reducer.Event>(
                sessionId: op.handle.matchId, gameType: gameType, ruleFamily: descriptor.ruleFamily,
                reducerType: ScoreboardKernelRegistry.footballReducerType(for: gameType) ?? descriptor.reducerType,
                state: state
            )
            var machine = ScoreSessionMachine(seedSession: session, reducer: reducer)
            guard case .accepted(let next, let events) = machine.dispatchNonUndoable(
                actorId: op.origin.rawValue, intent: intent, at: time
            ) else { return nil }
            let date = Date(timeIntervalSince1970: Double(time) / 1_000)
            return Applied(state: wrap(next.state), actions: projectActions ? project(intent, events, next.state, date) : [])
        }

        return switch (state, intent) {
        case (.rally(let value), .rally(let action)):
            reduce(value, action, reducer: RallyMatchReducer(), wrap: LinkedReducerSnapshot.rally, project: ScoreActionProjector.rally)
        case (.tennis(let value), .tennis(let action)):
            reduce(value, action, reducer: TennisMatchReducer(), wrap: LinkedReducerSnapshot.tennis, project: ScoreActionProjector.tennis)
        case (.archery(let value), .archery(let action)):
            reduce(value, action, reducer: ArcheryMatchReducer(), wrap: LinkedReducerSnapshot.archery) { _, events, state, date in
                ScoreActionProjector.archery(events: events, state: state, timestamp: date)
            }
        case (.eightBall(let value), .eightBall(let action)):
            reduce(value, action, reducer: EightBallReducer(), wrap: LinkedReducerSnapshot.eightBall) { _, events, state, date in
                ScoreActionProjector.eightBall(events: events, state: state, timestamp: date)
            }
        case (.nineBall(let value), .nineBall(let action)):
            reduce(value, action, reducer: NineBallChaseReducer(), wrap: LinkedReducerSnapshot.nineBall) { _, events, state, date in
                ScoreActionProjector.nineBall(events: events, state: state, timestamp: date)
            }
        case (.snooker(let value), .snooker(let action)):
            reduce(value, action, reducer: SnookerReducer(), wrap: LinkedReducerSnapshot.snooker, project: ScoreActionProjector.snooker)
        case (.football(let value), .football(let action)):
            reduce(value, action, reducer: FootballMatchReducer(), wrap: LinkedReducerSnapshot.football, project: ScoreActionProjector.football)
        case (.shotTraining(let value), .shotTraining(let action)):
            reduce(value, action, reducer: ShotTrainingReducer(), wrap: LinkedReducerSnapshot.shotTraining, project: ScoreActionProjector.shotTraining)
        default:
            nil
        }
    }
}

private extension LinkedReducerAdapter {
    func stabilized(_ actions: [DetailedScoreAction], opId: UUID) -> [DetailedScoreAction] {
        actions.enumerated().map { index, action in
            DetailedScoreAction(
                id: Self.actionId(opId: opId, index: index), type: action.type, epochMilliseconds: action.epochMilliseconds,
                team: action.team, scores: action.scores, setScores: action.setScores, setNumber: action.setNumber,
                gameNumber: action.gameNumber, roundNumber: action.roundNumber, periodNumber: action.periodNumber,
                gameTimeSeconds: action.gameTimeSeconds, scoreChange: action.scoreChange, winner: action.winner,
                loser: action.loser, landlord: action.landlord, winners: action.winners, losers: action.losers,
                farmers: action.farmers, participants: action.participants, operationCode: action.operationCode,
                operationPayload: action.operationPayload, summary: action.summary, footballPeriod: action.footballPeriod,
                footballElapsedSeconds: action.footballElapsedSeconds
            )
        }
    }

    static func actionId(opId: UUID, index: Int) -> UUID {
        let opBytes = withUnsafeBytes(of: opId.uuid) { Data($0) }
        let ordinal = withUnsafeBytes(of: UInt64(index).bigEndian) { Data($0) }
        let digest = Array(SHA256.hash(data: opBytes + ordinal).prefix(16))
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], (digest[6] & 0x0f) | 0x80, digest[7],
            (digest[8] & 0x3f) | 0x80, digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]
        ))
    }
}
