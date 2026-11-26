import Foundation
import LinkCore
import Observation
import RecordCore
import ScoreCore
import SessionCore

/// 每块手表计分板提供给通用宿主的“口径”闭包：动作投影、撤销摘要、比分文案、
/// 续玩载荷与联动快照。除这些展示/接线口径外，分数、撤销栈与时间线全部由
/// `ScoreSessionResumeBundle` 统一承载。
struct WatchReducerBinding<R: DomainReducer>: Sendable {
    /// 续玩草稿 emoji（续赛浮条展示）。
    let emoji: String
    /// 该项运动产出联动/本地快照的唯一口径（直接携带 Reducer State）。
    let snapshot: @Sendable (R.State) -> LinkedScoreboardSnapshot
    /// 已接受动作投影为共享 `DetailedScoreAction`。
    let project: @Sendable (R.Intent, [R.Event], R.State, Date) -> [DetailedScoreAction]
    /// 撤销时用于写撤销动作的比分口径。
    let undoSummary: @Sendable (R.State) -> WatchReducerUndoSummary
    /// 续赛浮条比分文案。
    let scoreLine: @Sendable (R.State) -> String
    /// 该 Intent 是否重置动作日志（新开一局/清零计分）。
    let resetsActionLog: @Sendable (R.Intent) -> Bool
    /// 续玩载荷（各运动只有一处构造）。
    let payload: @Sendable (ScoreSessionResumeBundle<R.State, R.Event, R.Intent>) -> WatchResumePayload

    init(
        emoji: String,
        snapshot: @escaping @Sendable (R.State) -> LinkedScoreboardSnapshot,
        project: @escaping @Sendable (R.Intent, [R.Event], R.State, Date) -> [DetailedScoreAction],
        undoSummary: @escaping @Sendable (R.State) -> WatchReducerUndoSummary,
        scoreLine: @escaping @Sendable (R.State) -> String,
        resetsActionLog: @escaping @Sendable (R.Intent) -> Bool = { _ in false },
        payload: @escaping @Sendable (ScoreSessionResumeBundle<R.State, R.Event, R.Intent>) -> WatchResumePayload
    ) {
        self.emoji = emoji
        self.snapshot = snapshot
        self.project = project
        self.undoSummary = undoSummary
        self.scoreLine = scoreLine
        self.resetsActionLog = resetsActionLog
        self.payload = payload
    }
}

/// 撤销动作写库所需的比分快照。
struct WatchReducerUndoSummary {
    let team1Score: Int
    let team2Score: Int
    let team1SetScore: Int?
    let team2SetScore: Int?

    init(team1Score: Int, team2Score: Int, team1SetScore: Int? = nil, team2SetScore: Int? = nil) {
        self.team1Score = team1Score
        self.team2Score = team2Score
        self.team1SetScore = team1SetScore
        self.team2SetScore = team2SetScore
    }
}

/// 8 块手表计分板共用的同步状态宿主。
///
/// 与旧的 `WatchRallySessionStore` / `WatchTennisSessionStore` /
/// `WatchArcherySessionStore` 相比：
/// - 用值类型 `ScoreSessionMachine` 同步推进，点击不再每次开 `Task {}`；
/// - 续玩统一持久化标准 `ScoreSessionResumeBundle`，不再各存散装 undoStates；
/// - 完赛写库用单一 `savedRecordID` 门闩，写失败取消后可继续计分或重试。
@MainActor
@Observable
final class WatchReducerSessionStore<R: DomainReducer> where R.State: Equatable {
    typealias ResumeBundle = ScoreSessionResumeBundle<R.State, R.Event, R.Intent>

    private(set) var machine: ScoreSessionMachine<R>
    /// 动作日志仍允许计分板做联动合并/清零（`merge`、`reset`、`omitSecondaryScores`），
    /// 但计分追加与撤销记录只走 `dispatch`/`undo`。
    var actionLog: WatchScoreActionLog
    /// 已成功落库的完赛记录 ID。非 nil 后禁止继续改动本场。
    private(set) var savedRecordID: String?
    /// 已接受的可撤销动作数（撤销按钮可用性）。
    private(set) var undoDepth = 0

    let binding: WatchReducerBinding<R>
    var startedAt: Date
    private let now: () -> Date
    private var lastAppliedRemoteGeneration: UInt64?
    private var lastAppliedRemoteRevision: UInt64?
    /// 状态变化回调（联动发布、界面提示等由 View 决定）。
    var onStateChanged: ((R.State, [R.Event]) -> Void)?

    var state: R.State { machine.currentSession.state }
    var status: SessionStatus { machine.currentSession.status }
    var isFinished: Bool { machine.currentSession.status == .finished }
    var canUndo: Bool { undoDepth > 0 }

    init(
        seedSession: ScoreSession<R.State, R.Event>,
        reducer: R,
        binding: WatchReducerBinding<R>,
        actionLog: WatchScoreActionLog,
        startedAt: Date = Date(),
        canDispatch: @escaping @Sendable (String, R.Intent) -> Bool = { _, _ in true },
        shouldFinish: (@Sendable (R.Intent, R.State) -> Bool)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        machine = ScoreSessionMachine(
            seedSession: seedSession,
            reducer: reducer,
            canDispatch: canDispatch,
            shouldFinish: shouldFinish ?? { _, state in
                binding.snapshot(state).isFinished
            }
        )
        self.binding = binding
        self.actionLog = actionLog
        self.startedAt = startedAt
        self.now = now
    }

    init(
        resumeBundle: ResumeBundle,
        reducer: R,
        binding: WatchReducerBinding<R>,
        actionLog: WatchScoreActionLog,
        startedAt: Date = Date(),
        canDispatch: @escaping @Sendable (String, R.Intent) -> Bool = { _, _ in true },
        shouldFinish: (@Sendable (R.Intent, R.State) -> Bool)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        machine = ScoreSessionMachine(
            resumeBundle: resumeBundle,
            reducer: reducer,
            canDispatch: canDispatch,
            shouldFinish: shouldFinish ?? { _, state in
                binding.snapshot(state).isFinished
            }
        )
        self.binding = binding
        self.actionLog = actionLog
        self.startedAt = startedAt
        self.now = now
        undoDepth = max(0, resumeBundle.undoFrames.count)
    }

    // MARK: - 计分

    @discardableResult
    func dispatch(
        _ intent: R.Intent,
        at timestamp: Date = Date(),
        actorId: String = "watch",
        recordsUndo: Bool = true,
        recordsNonUndoableActions: Bool = false
    ) -> DispatchResult<R.State, R.Event> {
        let nowMs = Self.epochMilliseconds(timestamp)
        if recordsUndo {
            actionLog.beginUndoableMutation()
        }
        let result = recordsUndo
            ? machine.dispatch(actorId: actorId, intent: intent, at: nowMs)
            : machine.dispatchNonUndoable(
                actorId: actorId, intent: intent, at: nowMs, recordsInTimeline: recordsNonUndoableActions
            )

        switch result {
        case .rejected:
            if recordsUndo { actionLog.rejectUndoableMutation() }
            return result
        case .accepted(let session, let events):
            if recordsUndo {
                if binding.resetsActionLog(intent) {
                    actionLog.reset(at: timestamp)
                    machine.rebase(to: session.state, status: session.status)
                    undoDepth = 0
                } else {
                    undoDepth += 1
                    actionLog.append(contentsOf: binding.project(intent, events, session.state, timestamp))
                }
            } else if recordsNonUndoableActions {
                actionLog.append(contentsOf: binding.project(intent, events, session.state, timestamp))
            }
            let committed = machine.currentSession
            onStateChanged?(committed.state, events)
            return .accepted(session: committed, events: events)
        }
    }

    /// 与旧 `Watch*SessionStore.apply` 同形的入口，便于计分板最小改动接入。
    @discardableResult
    func apply(
        _ intent: R.Intent,
        recordHistory: Bool = true,
        at timestamp: Date = Date(),
        recordsNonUndoableActions: Bool = false
    ) -> DispatchResult<R.State, R.Event> {
        dispatch(intent, at: timestamp, recordsUndo: recordHistory, recordsNonUndoableActions: recordsNonUndoableActions)
    }

    /// Dispatch without a new undo frame. Display-only changes leave the action log unchanged.
    @discardableResult
    func dispatchNonUndoable(
        _ intent: R.Intent,
        at timestamp: Date = Date(),
        actorId: String = "watch",
        recordsNonUndoableActions: Bool = false
    ) -> DispatchResult<R.State, R.Event> {
        dispatch(
            intent, at: timestamp, actorId: actorId,
            recordsUndo: false, recordsNonUndoableActions: recordsNonUndoableActions
        )
    }

    @discardableResult
    func undo(at timestamp: Date = Date()) -> Bool {
        guard savedRecordID == nil, canUndo else { return false }
        guard machine.undo(actorId: "watch") else { return false }
        undoDepth = max(0, undoDepth - 1)
        let summary = binding.undoSummary(state)
        actionLog.undo(
            at: timestamp,
            team1Score: summary.team1Score,
            team2Score: summary.team2Score,
            team1SetScore: summary.team1SetScore,
            team2SetScore: summary.team2SetScore
        )
        onStateChanged?(state, [])
        return true
    }

    // MARK: - 联动

    /// 安装对端权威状态。revision/generation 校验保留在宿主内，避免各板重复。
    @discardableResult
    func applyAuthoritativeState(
        _ state: R.State,
        revision: UInt64,
        matchGeneration: UInt64? = nil,
        status: SessionStatus? = nil
    ) -> Bool {
        let newStatus = status ?? (binding.snapshot(state).isFinished ? .finished : .live)
        let startsNewMatch: Bool
        if let matchGeneration, lastAppliedRemoteGeneration != matchGeneration {
            if let lastAppliedRemoteGeneration, matchGeneration < lastAppliedRemoteGeneration { return false }
            startsNewMatch = lastAppliedRemoteGeneration != nil
            lastAppliedRemoteGeneration = matchGeneration
            lastAppliedRemoteRevision = nil
        } else {
            startsNewMatch = false
        }
        if let lastAppliedRemoteRevision {
            let finishesCurrentRevision = revision == lastAppliedRemoteRevision
                && self.status == .live && newStatus == .finished
            guard revision > lastAppliedRemoteRevision || finishesCurrentRevision else { return false }
        }
        lastAppliedRemoteRevision = revision
        if startsNewMatch { savedRecordID = nil }
        rebase(to: state, status: newStatus, preserveUndoWhenUnchanged: !startsNewMatch)
        return true
    }

    func beginRemoteMatch(at timestamp: Date) {
        startedAt = timestamp
        actionLog.reset(at: timestamp)
        if canUndo || !machine.intentTimeline().isEmpty { machine.rebase(to: state, status: status) }
        undoDepth = 0
        savedRecordID = nil
    }

    @discardableResult
    func mergeRemoteActions(_ actions: [DetailedScoreAction], removing removedIDs: Set<UUID> = []) -> Bool {
        actionLog.merge(detailedActions: actions, removing: removedIDs)
    }

    /// A changed authoritative state becomes the new undo boundary.
    func rebase(to state: R.State, status: SessionStatus? = nil, preserveUndoWhenUnchanged: Bool = true) {
        let newStatus = status ?? (binding.snapshot(state).isFinished ? .finished : .live)
        if preserveUndoWhenUnchanged, self.state == state, self.status == newStatus { return }
        machine.rebase(to: state, status: newStatus)
        undoDepth = 0
        actionLog.clearUndoHistory()
    }

    /// 展示态补丁（不改变撤销栈与时间线），例如射箭待定局分提示。
    func replaceDisplayedState(_ state: R.State) {
        machine.overrideCurrentState(state)
    }

    // MARK: - 续玩与完赛

    func resumeBundle() -> ResumeBundle {
        machine.resumeBundle()
    }

    var snapshot: LinkedScoreboardSnapshot { binding.snapshot(state) }

    var scoreLine: String { binding.scoreLine(state) }

    /// 标准续玩草稿：所有运动只有这一处写 `WatchResumePayload`。
    /// `payload` 仅用于带额外展示字段（八球/斯诺克队名、射箭/网球休息态）的运动；
    /// 其余运动一律由 binding 从标准 bundle 生成。
    @discardableResult
    func persistResumeSession(
        into store: WatchResumeSessionStore,
        link: WatchLinkResumeContext? = nil,
        startedAt: Date? = nil,
        payload: WatchResumePayload? = nil
    ) -> Bool {
        guard savedRecordID == nil else { return false }
        store.save(WatchResumeSession(
            startedAt: startedAt ?? self.startedAt,
            scoreLine: binding.scoreLine(state),
            emoji: binding.emoji,
            payload: payload ?? binding.payload(resumeBundle()),
            actionLog: actionLog,
            linkHandle: link?.handle
        ))
        return true
    }

    /// 完赛落库：成功才置 `savedRecordID`。失败时保持 nil，调用方可重试，
    /// 取消后棋盘仍可继续计分（投篮训练 P2）。
    @discardableResult
    func saveFinishedRecord(
        into resumeStore: WatchResumeSessionStore,
        gameType: ScoreCore.GameType,
        recordID: String,
        endTime: Date,
        winnerSide: MatchSide? = nil,
        participantNames: [String] = [],
        totalScoreChanges: Int? = nil,
        additionalConfiguration: [String: String] = [:],
        isFinished: Bool = true
    ) -> Bool {
        guard savedRecordID == nil else { return true }
        var log = actionLog
        log.appendGameEndIfNeeded(
            at: endTime,
            team1Score: binding.undoSummary(state).team1Score,
            team2Score: binding.undoSummary(state).team2Score
        )
        let resolvedTotalChanges = totalScoreChanges ?? log.scoreChangeCount
        guard let record = WatchScoreboardRecord(
            localSnapshot: binding.snapshot(state),
            gameType: gameType,
            id: recordID,
            startTime: startedAt,
            endTime: endTime,
            participantNames: participantNames,
            winnerSide: winnerSide,
            detailedActions: log.detailedActions,
            totalScoreChanges: resolvedTotalChanges,
            additionalConfiguration: additionalConfiguration
        ) else { return false }
        guard resumeStore.saveFinishedRecord(record) else { return false }
        markRecordSaved(recordID)
        return true
    }

    func markRecordSaved(_ recordID: String) {
        savedRecordID = recordID
    }

    func clearSavedRecord() {
        savedRecordID = nil
    }

    static func epochMilliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }
}
