import Foundation
import LinkCore
import Observation
import PersistenceCore
import RecordCore
import ScoreCore
import SessionCore

/// Watch archery session host — sync apply (same reducer as phone), local undo + archive.
@MainActor
@Observable
final class WatchArcherySessionStore {
    private let reducer = ArcheryMatchReducer()
    private let archiveRepository = SessionArchiveRepository()
    private var undoStack: [ArcheryMatchState] = []
    private let ruleFamily: RuleFamily
    private let reducerType: String
    private var participants: [SessionParticipant]

    private(set) var state: ArcheryMatchState
    private(set) var actionLog: WatchScoreActionLog
    let sessionId: UUID
    let startedAt: Date

    var teamScreenLayout: TeamScreenLayout {
        TeamScreenLayout(sidesSwapped: state.sidesSwapped)
    }

    init(
        initialState: LinkedArcheryState? = nil,
        resumedState: ArcheryMatchState? = nil,
        resumedUndoStates: [ArcheryMatchState] = [],
        resumedStartTime: Date? = nil,
        resumedActionLog: WatchScoreActionLog? = nil
    ) {
        let descriptor = ScoreboardKernelRegistry.descriptor(for: .archeryDual)
        let defaults = WatchDefaultTeamNames.resolve()
        let seed: ArcheryMatchState
        if let resumedState {
            seed = resumedState
        } else if let initialState {
            var match = ArcheryMatchState(
                leftName: initialState.leftName,
                rightName: initialState.rightName,
                leftArrowSum: initialState.leftArrowSum,
                rightArrowSum: initialState.rightArrowSum,
                leftSetPoints: initialState.leftSetPoints,
                rightSetPoints: initialState.rightSetPoints,
                currentSet: max(1, initialState.setNumber),
                currentShooterIsLeft: initialState.currentShooterIsLeft,
                openingShooterIsLeft: initialState.currentShooterIsLeft,
                finished: initialState.finished,
                sidesSwapped: initialState.sidesSwapped
            )
            initialState.applying(to: &match)
            seed = match
        } else {
            seed = ArcheryMatchState(
                leftName: defaults.left,
                rightName: defaults.right
            )
        }
        sessionId = UUID()
        state = seed
        undoStack = resumedUndoStates
        ruleFamily = descriptor.ruleFamily
        reducerType = descriptor.reducerType
        participants = [
            .init(id: TeamID.team0.rawValue, name: seed.leftName, role: "team"),
            .init(id: TeamID.team1.rawValue, name: seed.rightName, role: "team")
        ]
        startedAt = resumedStartTime ?? Date()
        actionLog = resumedActionLog ?? WatchScoreActionLog(startedAt: startedAt)
    }

    @discardableResult
    func apply(_ intent: ArcheryMatchIntent, recordHistory: Bool = true) -> ReduceResult<ArcheryMatchState, ArcheryMatchEvent> {
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        if recordHistory {
            undoStack.append(state)
            if undoStack.count > 50 { undoStack.removeFirst() }
            actionLog.beginUndoableMutation()
        }
        let result = reducer.reduce(state: state, intent: intent, at: now)
        guard result.accepted else {
            if recordHistory {
                _ = undoStack.popLast()
                actionLog.rejectUndoableMutation()
            }
            return result
        }
        state = result.state
        let timestamp = Date(timeIntervalSince1970: TimeInterval(now) / 1_000)
        if case .reset = intent {
            actionLog.reset(at: timestamp)
        } else {
            actionLog.append(contentsOf: WatchScoreActionProjector.archery(
                events: result.events,
                state: state,
                timestamp: timestamp
            ))
        }
        persistSnapshot()
        return result
    }

    @discardableResult
    func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        state = previous
        actionLog.undo(
            at: Date(),
            team1Score: state.leftArrowSum,
            team2Score: state.rightArrowSum,
            team1SetScore: state.leftSetPoints,
            team2SetScore: state.rightSetPoints
        )
        persistSnapshot()
        return true
    }

    func replaceDisplayedState(_ state: ArcheryMatchState) {
        self.state = state
    }

    /// Applies a remote authority snapshot and prevents undo across devices.
    func rebase(to state: ArcheryMatchState) {
        self.state = state
        undoStack.removeAll()
        persistSnapshot()
    }

    func mergeRemoteActions(_ actions: [DetailedScoreAction]) {
        actionLog.merge(detailedActions: actions)
    }

    func clearHistory() {
        undoStack.removeAll()
    }

    func resumeUndoStates() -> [ArcheryMatchState] {
        undoStack
    }

    func persistSnapshot() {
        let session = ScoreSession<ArcheryMatchState, ArcheryMatchEvent>(
            sessionId: sessionId,
            gameType: .archeryDual,
            ruleFamily: ruleFamily,
            reducerType: reducerType,
            state: state,
            status: state.finished ? .finished : .live,
            participants: participants,
            metadata: .init(extras: [
                "startedAtEpochMilliseconds": String(Int64(startedAt.timeIntervalSince1970 * 1_000))
            ])
        )
        Task { [archiveRepository] in
            try? await archiveRepository.save(session, source: .watchLocal)
        }
    }
}
