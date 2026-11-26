import Foundation
import LinkCore
import LinkSync
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
    private var link: (sessionId: UUID, service: PhoneWatchLinkService)?
    private var installedLinkedUpdate: PhoneWatchLinkService.LinkedSnapshotUpdate?

    var isLinked: Bool { link != nil }
    var linkedActions: [DetailedScoreAction] { installedLinkedUpdate?.detailedActions ?? [] }
    private(set) var linkedActionNotice: String?

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

    func attachLink(sessionId: UUID, service: PhoneWatchLinkService) {
        if link?.sessionId != sessionId { installedLinkedUpdate = nil }
        link = (sessionId, service)
        undoStack.removeAll()
    }

    func detachLink() {
        link = nil
        installedLinkedUpdate = nil
        linkedActionNotice = nil
    }

    @discardableResult
    func installLinkedUpdate(_ update: PhoneWatchLinkService.LinkedSnapshotUpdate) -> Bool {
        guard update.sessionId == link?.sessionId, case .archery(let confirmed) = update.snapshot else { return false }
        if let previous = installedLinkedUpdate {
            guard update.matchGeneration > previous.matchGeneration
                    || (update.matchGeneration == previous.matchGeneration && update.revision > previous.revision) else {
                return false
            }
        }
        rebase(to: confirmed)
        installedLinkedUpdate = update
        return true
    }

    func clearLinkedActionNotice() { linkedActionNotice = nil }

    @discardableResult
    func apply(_ intent: ArcheryMatchIntent, recordHistory: Bool = true) -> ReduceResult<ArcheryMatchState, ArcheryMatchEvent> {
        if let link {
            if let update = link.service.latestRemoteSnapshot { installLinkedUpdate(update) }
            let previous = state
            if intent == .reset {
                linkedActionNotice = NSLocalizedString(
                    "linked_score_reset_unavailable",
                    value: "联动计分期间请先结束本场，再开始新一局。",
                    comment: ""
                )
                return .rejected(state: state, reason: "Linked reset requires a finished match")
            }
            guard let effectiveTime = submitLinked(intent == .finish ? .finish : .archery(intent)) else {
                return .rejected(state: state, reason: "Linked archery operation was not accepted")
            }
            // Read reducer events for local presentation. The phone projection
            // installed by submitLinked owns the state and action history.
            let preview = reducer.reduce(state: previous, intent: intent, at: effectiveTime)
            return .init(state: state, events: preview.accepted && preview.state == state ? preview.events : [])
        }
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
        if isLinked { return submitLinked(.undo(targetOpId: nil)) != nil }
        guard let previous = undoStack.popLast() else { return false }
        state = previous
        return true
    }

    private func submitLinked(_ intent: LinkedScoreboardIntent) -> Int64? {
        guard let link else { return nil }
        do {
            let result = try link.service.submitLocalIntent(intent, sessionId: link.sessionId)
            guard let update = link.service.latestRemoteSnapshot, update.sessionId == link.sessionId,
                  update.matchGeneration == result.op.handle.matchGeneration, update.revision == result.committedRevision,
                  case .archery = update.snapshot else {
                linkedActionNotice = NSLocalizedString(
                    "linked_score_sync_timeout",
                    value: "比分同步超时，将在重新连接后继续同步。",
                    comment: ""
                )
                return nil
            }
            installLinkedUpdate(update)
            return result.outcome == .accepted ? result.effectiveEpochMilliseconds : nil
        } catch {
            linkedActionNotice = error.localizedDescription
            return nil
        }
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
