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
    let sessionId: UUID
    let startedAt: Date

    var teamScreenLayout: TeamScreenLayout {
        TeamScreenLayout(sidesSwapped: state.sidesSwapped)
    }

    init(initialState: LinkedArcheryState? = nil) {
        let descriptor = ScoreboardKernelRegistry.descriptor(for: .archeryDual)
        let defaults = WatchDefaultTeamNames.resolve()
        let seed: ArcheryMatchState
        if let initialState {
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
        ruleFamily = descriptor.ruleFamily
        reducerType = descriptor.reducerType
        participants = [
            .init(id: TeamID.team0.rawValue, name: seed.leftName, role: "team"),
            .init(id: TeamID.team1.rawValue, name: seed.rightName, role: "team")
        ]
        startedAt = Date()
    }

    @discardableResult
    func apply(_ intent: ArcheryMatchIntent, recordHistory: Bool = true) -> ReduceResult<ArcheryMatchState, ArcheryMatchEvent> {
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        if recordHistory {
            undoStack.append(state)
            if undoStack.count > 50 { undoStack.removeFirst() }
        }
        let result = reducer.reduce(state: state, intent: intent, at: now)
        guard result.accepted else {
            if recordHistory { _ = undoStack.popLast() }
            return result
        }
        state = result.state
        persistSnapshot()
        return result
    }

    @discardableResult
    func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        state = previous
        persistSnapshot()
        return true
    }

    func replaceDisplayedState(_ state: ArcheryMatchState) {
        self.state = state
    }

    func clearHistory() {
        undoStack.removeAll()
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
