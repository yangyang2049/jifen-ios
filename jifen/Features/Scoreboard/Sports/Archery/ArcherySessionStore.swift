import Foundation
import Observation
import PersistenceCore
import ScoreCore
import SessionCore

/// Primary archery session host — sync apply for scoreboard UI, archives via SessionCore snapshot shape.
@MainActor
@Observable
final class ArcherySessionStore {
    private let reducer = ArcheryMatchReducer()
    private let archiveRepository = SessionArchiveRepository()
    private var undoStack: [ArcheryMatchState] = []
    private let ruleFamily: RuleFamily
    private let reducerType: String
    private var participants: [SessionParticipant]

    private(set) var state: ArcheryMatchState
    let sessionId: UUID
    let startedAt: Date

    /// HOS-aligned screen placement derived from engine `sidesSwapped`.
    var teamScreenLayout: TeamScreenLayout {
        TeamScreenLayout(sidesSwapped: state.sidesSwapped)
    }

    convenience init(leftName: String, rightName: String, openingShooterIsLeft: Bool = true) {
        let descriptor = ScoreboardKernelRegistry.descriptor(for: .archeryDual)
        let initial = ArcheryMatchState(
            leftName: leftName,
            rightName: rightName,
            currentShooterIsLeft: openingShooterIsLeft,
            openingShooterIsLeft: openingShooterIsLeft
        )
        self.init(
            sessionId: UUID(),
            state: initial,
            ruleFamily: descriptor.ruleFamily,
            reducerType: descriptor.reducerType,
            participants: [
                .init(id: TeamID.team0.rawValue, name: initial.leftName, role: "team"),
                .init(id: TeamID.team1.rawValue, name: initial.rightName, role: "team")
            ]
        )
    }

    private init(
        sessionId: UUID,
        state: ArcheryMatchState,
        ruleFamily: RuleFamily,
        reducerType: String,
        participants: [SessionParticipant]
    ) {
        self.sessionId = sessionId
        self.state = state
        self.ruleFamily = ruleFamily
        self.reducerType = reducerType
        self.participants = participants
        startedAt = Date()
    }

    @discardableResult
    func apply(_ intent: ArcheryMatchIntent, recordHistory: Bool = true) -> ReduceResult<ArcheryMatchState, ArcheryMatchEvent> {
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        if recordHistory {
            undoStack.append(state)
            if undoStack.count > 100 { undoStack.removeFirst() }
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

    func configureOpening(leftName: String, rightName: String, openingIsLeft: Bool) {
        state = ArcheryMatchState(
            leftName: leftName,
            rightName: rightName,
            currentShooterIsLeft: openingIsLeft,
            openingShooterIsLeft: openingIsLeft
        )
        participants = [
            .init(id: TeamID.team0.rawValue, name: leftName, role: "team"),
            .init(id: TeamID.team1.rawValue, name: rightName, role: "team")
        ]
        undoStack.removeAll()
        persistSnapshot()
    }

    func replaceDisplayedState(_ state: ArcheryMatchState) {
        self.state = state
    }

    /// Applies a remote authority snapshot and establishes a new local undo boundary.
    func rebase(to state: ArcheryMatchState) {
        self.state = state
        undoStack.removeAll()
        persistSnapshot()
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
            try? await archiveRepository.save(session)
        }
    }
}
