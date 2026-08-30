import Foundation
import Observation
import RecordCore
import ScoreCore

struct ArcheryRecordUndoCheckpoint: Codable, Equatable {
    let recordedActionCount: Int?
    let detailedActionCount: Int?

    static let legacy = Self(recordedActionCount: nil, detailedActionCount: nil)
}

struct ArcheryResumeState: Codable, Equatable {
    var schemaVersion = 4
    let state: ArcheryMatchState
    let undoHistory: [ArcheryMatchState]
    let intentTimeline: [String]
    let detailedActions: [DetailedScoreAction]
    let recordUndoCheckpoints: [ArcheryRecordUndoCheckpoint]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, state, undoHistory, intentTimeline, detailedActions, recordUndoCheckpoints
    }

    init(
        schemaVersion: Int = 4,
        state: ArcheryMatchState,
        undoHistory: [ArcheryMatchState],
        intentTimeline: [String],
        detailedActions: [DetailedScoreAction] = [],
        recordUndoCheckpoints: [ArcheryRecordUndoCheckpoint]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.state = state
        self.undoHistory = undoHistory
        self.intentTimeline = intentTimeline
        self.detailedActions = detailedActions
        self.recordUndoCheckpoints = recordUndoCheckpoints
            ?? Array(repeating: .legacy, count: undoHistory.count)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        state = try container.decode(ArcheryMatchState.self, forKey: .state)
        undoHistory = try container.decodeIfPresent([ArcheryMatchState].self, forKey: .undoHistory) ?? []
        intentTimeline = try container.decodeIfPresent([String].self, forKey: .intentTimeline) ?? []
        detailedActions = try container.decodeIfPresent([DetailedScoreAction].self, forKey: .detailedActions) ?? []
        recordUndoCheckpoints = try container.decodeIfPresent(
            [ArcheryRecordUndoCheckpoint].self,
            forKey: .recordUndoCheckpoints
        ) ?? Array(repeating: .legacy, count: undoHistory.count)
    }
}

/// Primary archery session host — sync apply for scoreboard UI, resumes via SessionCore snapshot shape.
@MainActor
@Observable
final class ArcherySessionStore {
    private let reducer = ArcheryMatchReducer()
    private var undoStack: [ArcheryMatchState] = []

    private(set) var state: ArcheryMatchState
    let sessionId: UUID
    let startedAt: Date

    /// HOS-aligned screen placement derived from engine `sidesSwapped`.
    var teamScreenLayout: TeamScreenLayout {
        TeamScreenLayout(sidesSwapped: state.sidesSwapped)
    }

    convenience init(leftName: String, rightName: String, openingShooterIsLeft: Bool = true) {
        let initial = ArcheryMatchState(
            leftName: leftName,
            rightName: rightName,
            currentShooterIsLeft: openingShooterIsLeft,
            openingShooterIsLeft: openingShooterIsLeft
        )
        self.init(
            sessionId: UUID(),
            state: initial
        )
    }

    convenience init(state: ArcheryMatchState) {
        self.init(sessionId: UUID(), state: state)
    }

    private init(
        sessionId: UUID,
        state: ArcheryMatchState
    ) {
        self.sessionId = sessionId
        self.state = state
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
        return result
    }

    @discardableResult
    func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        state = previous
        return true
    }

    func configureOpening(leftName: String, rightName: String, openingIsLeft: Bool) {
        state = ArcheryMatchState(
            leftName: leftName,
            rightName: rightName,
            currentShooterIsLeft: openingIsLeft,
            openingShooterIsLeft: openingIsLeft
        )
        undoStack.removeAll()
    }

    func replaceDisplayedState(_ state: ArcheryMatchState) {
        self.state = state
    }

    /// Applies a remote authority snapshot and establishes a new local undo boundary.
    func rebase(to state: ArcheryMatchState) {
        self.state = state
        undoStack.removeAll()
    }

    func clearHistory() {
        undoStack.removeAll()
    }

    var resumeHistory: [ArcheryMatchState] {
        undoStack
    }

    func restoreRecordState(_ state: ArcheryMatchState, undoHistory: [ArcheryMatchState]) {
        self.state = state
        undoStack = Array(undoHistory.suffix(100))
    }
}
