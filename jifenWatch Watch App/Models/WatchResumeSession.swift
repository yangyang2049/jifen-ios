import Foundation
import LinkCore
import Observation
import OSLog
import RecordCore
import ScoreCore
import SessionCore

typealias WatchRallyResumeBundle = ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>
typealias WatchTennisResumeBundle = ScoreSessionResumeBundle<TennisMatchState, TennisMatchEvent, TennisMatchIntent>
typealias WatchArcheryResumeBundle = ScoreSessionResumeBundle<ArcheryMatchState, ArcheryMatchEvent, ArcheryMatchIntent>
typealias WatchEightBallResumeBundle = ScoreSessionResumeBundle<EightBallState, EightBallEvent, EightBallIntent>
typealias WatchNineBallResumeBundle = ScoreSessionResumeBundle<NineBallChaseState, NineBallChaseEvent, NineBallChaseIntent>
typealias WatchSnookerResumeBundle = ScoreSessionResumeBundle<SnookerState, SnookerEvent, SnookerIntent>
typealias WatchFootballResumeBundle = ScoreSessionResumeBundle<FootballMatchState, FootballMatchEvent, FootballMatchIntent>
typealias WatchShotTrainingResumeBundle = ScoreSessionResumeBundle<ShotTrainingState, ShotTrainingEvent, ShotTrainingIntent>

/// 续玩统一为标准 `ScoreSessionResumeBundle`：比分、撤销帧与时间线全部由
/// 引擎值类型承载，不再各运动散装保存 `undoStates` 数组。
enum WatchResumePayload: Codable, Sendable {
    case rally(
        gameType: GameType,
        bundle: WatchRallyResumeBundle,
        restState: WatchRestState?
    )
    case tennis(
        isDoubles: Bool,
        bundle: WatchTennisResumeBundle,
        restState: WatchRestState?
    )
    case archery(
        bundle: WatchArcheryResumeBundle,
        restState: WatchRestState?
    )
    case eightBall(
        bundle: WatchEightBallResumeBundle,
        leftName: String,
        rightName: String
    )
    case nineBall(
        bundle: WatchNineBallResumeBundle
    )
    case snooker(
        bundle: WatchSnookerResumeBundle,
        leftName: String,
        rightName: String
    )
    case football(
        isFiveAside: Bool,
        bundle: WatchFootballResumeBundle
    )
    case basketballTraining(
        bundle: WatchShotTrainingResumeBundle
    )

    /// Artwork lookup for the resume bar; nil when no sport artwork applies.
    var gameType: WatchGameType? {
        switch self {
        case .rally(let gameType, _, _):
            switch gameType {
            case .pingpong, .pingpongDoubles: return .pingpong
            case .badminton, .badmintonDoubles: return .badminton
            case .pickleball, .pickleballDoubles: return .pickleball
            case .shuttlecock: return .shuttlecock
            case .squash: return .squash
            case .foosball, .foosballDoubles: return .foosball
            default: return nil
            }
        case .tennis:
            return .tennis
        case .archery:
            return .archery
        case .eightBall:
            return .eightBall
        case .nineBall:
            return .nineBall
        case .snooker:
            return .snooker
        case .football(let isFiveAside, _):
            return WatchFootballRules.watchGameType(isFiveAside: isFiveAside)
        case .basketballTraining:
            return .basketballTraining
        }
    }
}

extension WatchLinkResumeContext {
    var sessionId: UUID { handle.sessionId }
}

struct WatchResumeSession: Codable, Sendable {
    /// 首发格式直接起算：restore 只接受当前 schema 版本，旧版本会话一律视为
    /// 无会话丢弃，不做任何迁移。v4 起联动草稿只保存完整 handle 引用，
    /// 会话身份、revision 与权威快照全部来自 link/ 联动上下文。v5 统一保存 Reducer bundle。
    static let currentSchemaVersion = 5

    let schemaVersion: Int
    var savedAt: Date
    let startedAt: Date
    let scoreLine: String
    let emoji: String
    let payload: WatchResumePayload
    let actionLog: WatchScoreActionLog
    /// 仅用于匹配同一场次的完整 handle 引用；nil 表示本地独立比赛。
    let linkHandle: LinkedMatchHandle?

    init(
        savedAt: Date = Date(),
        startedAt: Date,
        scoreLine: String,
        emoji: String,
        payload: WatchResumePayload,
        actionLog: WatchScoreActionLog? = nil,
        linkHandle: LinkedMatchHandle? = nil
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.savedAt = savedAt
        self.startedAt = startedAt
        self.scoreLine = scoreLine
        self.emoji = emoji
        self.payload = payload
        self.actionLog = actionLog ?? WatchScoreActionLog(startedAt: startedAt)
        self.linkHandle = linkHandle
    }

    var isTrainingSession: Bool {
        if case .basketballTraining = payload {
            return true
        }
        return false
    }

    var resumeActionTitle: String {
        if isTrainingSession {
            return NSLocalizedString("watch_continue_scoring", value: "继续计分", comment: "")
        }
        return NSLocalizedString("watch_continue_match", value: "继续比赛", comment: "")
    }

    var discardActionTitle: String {
        if isTrainingSession {
            return NSLocalizedString("watch_resume_discard_training", value: "放弃未完成训练", comment: "")
        }
        return NSLocalizedString("watch_resume_discard", value: "放弃未完成比赛", comment: "")
    }
}

@MainActor
@Observable
final class WatchResumeSessionStore {
    static let shared = WatchResumeSessionStore()

    /// Resume sessions expire after 24 hours. Aligned with HarmonyOS's TTL
    /// approach (which uses 10 minutes); iOS uses a longer window so users
    /// can resume after a mid-session break without losing state. Expired
    /// sessions are silently cleared — no link context is retained.
    private static let sessionTTL: TimeInterval = 24 * 60 * 60
    private static let startupLog = OSLog(
        subsystem: "com.douhua.jifen.watch",
        category: "Startup"
    )

    /// 存储根目录：默认 WatchStorageContainer.shared 的 resume/ 子目录；
    /// resume/current.json 与 resume/pending-finished.json 均为原子写文件。
    /// 首发格式直接起算，不迁移/清理任何旧版键或旧目录。
    private let resumeDirectory: URL
    private let now: () -> Date
    /// 750ms 防抖写盘：主线程只保存内存 session 引用与待写值类型快照，
    /// 由后台 Task 完成整个 JSONEncoder().encode + 原子写文件，消除每次得分
    /// 在主线程同步编码全量 undoFrames + actionLog。切后台/退出计分板时
    /// flushPendingWrite 同步落盘保证不丢。
    private var pendingWrite: WatchResumeSession?
    private var pendingWriteTask: Task<Void, Never>?
    private static let writeDebounceNanoseconds: UInt64 = 750_000_000
    /// 生成号 + 锁：清空/冲刷后作废在途后台写，确保旧草稿不会复活；
    /// 校验生成号与落盘在同一临界区完成，关闭「校验后、写入前被清空」的窗口。
    /// 计数器自带锁，nonisolated 后台写路径也能安全读写。
    private final class WriteGenerationCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func next() -> Int {
            lock.lock()
            defer { lock.unlock() }
            value += 1
            return value
        }
        var current: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func withCurrent(_ body: (Int) -> Void) {
            lock.lock()
            defer { lock.unlock() }
            body(value)
        }
    }
    private let writeGenerationCounter = WriteGenerationCounter()

    private(set) var session: WatchResumeSession?
    private(set) var lastErrorMessage: String?
    private(set) var restoreAttemptCount = 0

    private var currentFileURL: URL {
        resumeDirectory.appendingPathComponent("current.json", isDirectory: false)
    }
    private var pendingFinishedFileURL: URL {
        resumeDirectory.appendingPathComponent("pending-finished.json", isDirectory: false)
    }

    /// - Parameter directoryURL: 存储目录；nil 使用 WatchStorageContainer.shared
    ///   的 resume/ 子目录（测试传临时目录隔离）。
    init(directoryURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.resumeDirectory = directoryURL ?? WatchStorageContainer.shared.resumeDirectory
        self.now = now
        session = nil
        reload()
    }

    func reload() {
        flushPendingWrite()
        restoreAttemptCount += 1
        os_signpost(.begin, log: Self.startupLog, name: "WatchResumeRestore")
        defer {
            os_signpost(
                .end,
                log: Self.startupLog,
                name: "WatchResumeRestore",
                "restored=%{public}d",
                session == nil ? 0 : 1
            )
        }
        guard let data = try? Data(contentsOf: currentFileURL), !data.isEmpty,
              let decoded = try? JSONDecoder().decode(WatchResumeSession.self, from: data),
              decoded.schemaVersion == WatchResumeSession.currentSchemaVersion else {
            // 缺失、损坏或非当前 schema 版本：视为无会话丢弃（首发格式直接起算）。
            try? FileManager.default.removeItem(at: currentFileURL)
            session = nil
            return
        }
        if now().timeIntervalSince(decoded.savedAt) > Self.sessionTTL {
            try? FileManager.default.removeItem(at: currentFileURL)
            session = nil
            return
        }
        session = decoded
    }

    func save(_ value: WatchResumeSession) {
        var refreshed = value
        refreshed.savedAt = now()
        // 主线程只保存内存引用与待写值类型快照，编码与写盘全部移出主线程。
        session = refreshed
        lastErrorMessage = nil
        pendingWrite = refreshed
        pendingWriteTask?.cancel()
        pendingWriteTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.writeDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.performDebouncedWrite()
        }
    }

    private func performDebouncedWrite() {
        guard let pending = pendingWrite else { return }
        pendingWrite = nil
        pendingWriteTask = nil
        scheduleBackgroundWrite(of: pending)
    }

    /// 生成号作废 + 后台编码写盘。encode 可能失败（极少见）：失败时回主线程
    /// 报错，不吞掉持久化异常。
    private func scheduleBackgroundWrite(of value: WatchResumeSession) {
        let generation = invalidatePendingBackgroundWrites()
        let url = currentFileURL
        Task.detached(priority: .utility) { [weak self] in
            do {
                let data = try JSONEncoder().encode(value)
                self?.writeAtomically(data, to: url, generation: generation)
            } catch {
                await self?.reportEncodeFailure(error)
            }
        }
    }

    /// 立即落盘待写数据（切后台/退出计分板前调用）。同步编码 + 生成号校验写盘。
    func flushPendingWrite() {
        pendingWriteTask?.cancel()
        pendingWriteTask = nil
        guard let pending = pendingWrite else { return }
        pendingWrite = nil
        let generation = invalidatePendingBackgroundWrites()
        do {
            let data = try JSONEncoder().encode(pending)
            writeAtomically(data, to: currentFileURL, generation: generation)
        } catch {
            lastErrorMessage = String(
                format: NSLocalizedString(
                    "resume_persistence_failed",
                    value: "无法保存续玩数据：%@",
                    comment: ""
                ),
                error.localizedDescription
            )
        }
    }

    func clearError() {
        lastErrorMessage = nil
    }

    /// Keep the exact record and ID across a failed write and a watch app restart.
    func saveFinishedRecord(
        _ record: WatchScoreboardRecord,
        using save: @MainActor (WatchScoreboardRecord) -> Bool = { WatchRecordManager.shared.saveRecord($0) }
    ) -> Bool {
        var pending = pendingFinishedRecords
        let candidate: WatchScoreboardRecord
        if let staged = pending.first(where: {
            $0.gameType == record.gameType
                && $0.canonical.startEpochMilliseconds == record.canonical.startEpochMilliseconds
        }) {
            candidate = staged
        } else {
            candidate = record
            pending.append(candidate)
            storePendingFinishedRecords(pending)
        }
        guard save(candidate) else {
            flushPendingWrite()
            return false
        }
        if let session, session.linkHandle == nil, hasRecordStart(session.startedAt, record: candidate) {
            clear()
        }
        removePendingFinishedRecords { $0.id == candidate.id }
        return true
    }

    func cancelPendingTrainingFinish(startedAt: Date) {
        removePendingFinishedRecords { $0.gameType == .basketballTraining && hasRecordStart(startedAt, record: $0) }
    }

    private func hasRecordStart(_ date: Date, record: WatchScoreboardRecord) -> Bool {
        record.canonical.startEpochMilliseconds == Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private func removePendingFinishedRecords(where shouldRemove: (WatchScoreboardRecord) -> Bool) {
        storePendingFinishedRecords(pendingFinishedRecords.filter { !shouldRemove($0) })
    }

    private func storePendingFinishedRecords(_ records: [WatchScoreboardRecord]) {
        if records.isEmpty {
            try? FileManager.default.removeItem(at: pendingFinishedFileURL)
        } else if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: pendingFinishedFileURL, options: .atomic)
        }
    }

    func retryPendingFinishedRecords(
        using save: @MainActor (WatchScoreboardRecord) -> Bool = { WatchRecordManager.shared.saveRecord($0) }
    ) {
        for record in pendingFinishedRecords { _ = saveFinishedRecord(record, using: save) }
    }

    private var pendingFinishedRecords: [WatchScoreboardRecord] {
        guard let data = try? Data(contentsOf: pendingFinishedFileURL), !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([WatchScoreboardRecord].self, from: data)) ?? []
    }

    nonisolated private func invalidatePendingBackgroundWrites() -> Int {
        writeGenerationCounter.next()
    }

    /// 校验生成号与写入在同一临界区：clear() 先递增生成号再删文件，
    /// 在途后台写要么在此之前完成（随后被 clear 删除），要么被作废跳过。
    nonisolated private func writeAtomically(_ data: Data, to url: URL, generation: Int) {
        writeGenerationCounter.withCurrent { current in
            guard generation == current else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    @MainActor
    private func reportEncodeFailure(_ error: Error) {
        lastErrorMessage = String(
            format: NSLocalizedString(
                "resume_persistence_failed",
                value: "无法保存续玩数据：%@",
                comment: ""
            ),
            error.localizedDescription
        )
    }

    /// 草稿只记录 handle 引用；联动上下文永远来自 link/ 权威存储。
    func refreshLinkContext(_ context: WatchLinkResumeContext) {
        guard let value = session, value.linkHandle == context.handle else { return }
        var actionLog = value.actionLog
        actionLog.merge(detailedActions: context.detailedActions, removing: context.actionHistory?.removedActionIDs ?? [])
        save(WatchResumeSession(
            startedAt: value.startedAt,
            scoreLine: value.scoreLine,
            emoji: value.emoji,
            payload: value.payload,
            actionLog: actionLog,
            linkHandle: context.handle
        ))
    }

    /// 计分板挂起在手表桌面时应用对端权威快照。远端变化成为新的重放种子，
    /// 之后的本地撤销不会跨过对端权威边界。
    /// - Returns: 是否真的用权威快照重建并保存了草稿。`false` 表示草稿与上下文
    ///   不匹配或快照无法映射，调用方不得用旧草稿继续展示。
    @discardableResult
    func applyLinkedSnapshot(
        _ snapshot: LinkedScoreboardSnapshot,
        context: WatchLinkResumeContext
    ) -> Bool {
        guard let value = session, let previous = value.linkHandle, previous.sessionId == context.sessionId else {
            return false
        }
        let beganNewMatch = previous.matchGeneration < context.handle.matchGeneration
        guard previous == context.handle || beganNewMatch else { return false }

        let updated: (payload: WatchResumePayload, scoreLine: String)?
        let status: SessionStatus = snapshot.isFinished ? .finished : .live
        let startedAt = snapshot.basketballTrainingState?.startTime ?? (beganNewMatch ? now() : value.startedAt)
        switch (value.payload, snapshot) {
        case (.rally(let gameType, let bundle, _), .rally(let state)):
            let score = state.leftSets + state.rightSets > 0
                ? "\(state.leftSets) - \(state.rightSets)"
                : "\(state.leftPoints) : \(state.rightPoints)"
            updated = (
                .rally(
                    gameType: gameType,
                    bundle: replacingCurrentState(in: bundle, with: state, status: status),
                    restState: WatchRestState.fromOfficialBreak(state.officialBreakState)
                ),
                score
            )
        case (.tennis(let isDoubles, let bundle, _), .tennis(let state)):
            let score = state.rules.setScoringMode == .tiebreakOnly
                ? "\(state.leftPoints) : \(state.rightPoints)"
                : "\(state.leftSets) - \(state.rightSets)"
            updated = (
                .tennis(
                    isDoubles: isDoubles,
                    bundle: replacingCurrentState(in: bundle, with: state, status: status),
                    restState: WatchRestState.fromOfficialBreak(state.officialBreakState)
                ),
                score
            )
        case (.archery(let bundle, let restState), .archery(let state)):
            let score = state.leftSetPoints + state.rightSetPoints > 0
                ? "\(state.leftSetPoints) : \(state.rightSetPoints)"
                : "\(state.leftArrowSum) : \(state.rightArrowSum)"
            updated = (
                .archery(
                    bundle: replacingCurrentState(in: bundle, with: state, status: status),
                    restState: restState
                ),
                score
            )
        case (.eightBall(let bundle, let leftName, let rightName), .eightBall(let state)):
            updated = (
                .eightBall(
                    bundle: replacingCurrentState(in: bundle, with: state, status: status),
                    leftName: leftName,
                    rightName: rightName
                ),
                "\(state.leftPoints) : \(state.rightPoints)"
            )
        case (.nineBall(let bundle), .nineBall(let state)):
            updated = (
                .nineBall(bundle: replacingCurrentState(in: bundle, with: state, status: status)),
                state.playerPoints.prefix(state.playerCount).map(String.init).joined(separator: " · ")
            )
        case (.snooker(let bundle, let leftName, let rightName), .snooker(let state)):
            updated = (
                .snooker(
                    bundle: replacingCurrentState(in: bundle, with: state, status: status),
                    leftName: leftName,
                    rightName: rightName
                ),
                "\(state.leftFrames)-\(state.rightFrames) / \(state.leftScore):\(state.rightScore)"
            )
        case (.basketballTraining(let bundle), .basketballTraining(let state)):
            let counts = state.counts
            updated = (
                .basketballTraining(bundle: replacingCurrentState(in: bundle, with: state, status: status)),
                "\(counts.made)/\(counts.attempts) = \(counts.rate)%"
            )
        case (.football(let isFiveAside, let bundle), .football(let state)):
            // 足球权威快照直接是 Reducer State：时钟锚点、分秒余量与补时/换边
            // 全部随状态落地，不做二次变形。
            updated = (
                .football(
                    isFiveAside: isFiveAside,
                    bundle: replacingCurrentState(in: bundle, with: state, status: status)
                ),
                "\(state.leftScore) - \(state.rightScore)"
            )
        default:
            updated = nil
        }

        guard let updated else { return false }
        // 完全相同 typed state 的恢复：保留草稿自己的 undo 栈，只合并动作与显式删除。
        let sameState = !beganNewMatch && Self.sameLinkedState(updated.payload, value.payload)
        let payload = sameState
            ? Self.carryingUndo(from: value.payload, into: updated.payload)
            : updated.payload
        var actionLog = beganNewMatch ? WatchScoreActionLog(startedAt: startedAt) : value.actionLog
        actionLog.merge(detailedActions: context.detailedActions, removing: context.actionHistory?.removedActionIDs ?? [])
        if !sameState { actionLog.clearUndoHistory() }
        save(WatchResumeSession(
            startedAt: startedAt,
            scoreLine: updated.scoreLine,
            emoji: value.emoji,
            payload: payload,
            actionLog: actionLog,
            linkHandle: context.handle
        ))
        return true
    }

    /// A repeated authoritative state keeps both the reducer and action-log undo history.
    private static func sameLinkedState(_ lhs: WatchResumePayload, _ rhs: WatchResumePayload) -> Bool {
        func same<State: Codable & Sendable & Equatable, Event: Codable & Sendable, Intent: Codable & Sendable>(
            _ left: ScoreSessionResumeBundle<State, Event, Intent>,
            _ right: ScoreSessionResumeBundle<State, Event, Intent>
        ) -> Bool {
            left.currentSession.state == right.currentSession.state
                && left.currentSession.status == right.currentSession.status
        }

        switch (lhs, rhs) {
        case (.rally(let leftType, let left, _), .rally(let rightType, let right, _)):
            return leftType == rightType && same(left, right)
        case (.tennis(let leftDoubles, let left, _), .tennis(let rightDoubles, let right, _)):
            return leftDoubles == rightDoubles && same(left, right)
        case (.archery(let left, _), .archery(let right, _)):
            return same(left, right)
        case (.eightBall(let left, _, _), .eightBall(let right, _, _)):
            return same(left, right)
        case (.nineBall(let left), .nineBall(let right)):
            return same(left, right)
        case (.snooker(let left, _, _), .snooker(let right, _, _)):
            return same(left, right)
        case (.football(let leftFiveAside, let left), .football(let rightFiveAside, let right)):
            return leftFiveAside == rightFiveAside && same(left, right)
        case (.basketballTraining(let left), .basketballTraining(let right)):
            return same(left, right)
        default:
            return false
        }
    }

    /// Keeps the original bundle and applies the refreshed presentation-only rest state.
    private static func carryingUndo(
        from source: WatchResumePayload,
        into target: WatchResumePayload
    ) -> WatchResumePayload {
        switch (source, target) {
        case (.rally(let gameType, let bundle, _), .rally(_, _, let restState)):
            return .rally(gameType: gameType, bundle: bundle, restState: restState)
        case (.tennis(let isDoubles, let bundle, _), .tennis(_, _, let restState)):
            return .tennis(isDoubles: isDoubles, bundle: bundle, restState: restState)
        case (.archery(let bundle, _), .archery(_, let restState)):
            return .archery(bundle: bundle, restState: restState)
        default:
            return source
        }
    }

    /// 恢复前的权威性判定：草稿的完整 handle 必须与 link/ 上下文完全一致，
    /// 项目一致，且上下文本身可判定为同一场有效会话。旧草稿、错场引用与
    /// 损坏引用一律不复活联动，也不会被当成独立比赛。
    func linkContextForResume(
        _ context: WatchLinkResumeContext?
    ) -> WatchLinkResumeContext? {
        guard let session, let linkHandle = session.linkHandle, let context else { return nil }
        guard context.handle == linkHandle else { return nil }
        guard WatchGameType(scoreCoreGameType: context.setup.gameType) == session.payload.gameType else { return nil }
        switch session.payload {
        case .rally(_, let bundle, _):
            guard bundle.currentSession.gameType == context.setup.gameType else { return nil }
        case .tennis(let isDoubles, _, _):
            guard context.setup.gameType == (isDoubles ? .tennisDoubles : .tennis) else { return nil }
        case .football(let isFiveAside, let bundle):
            guard context.setup.gameType == (isFiveAside ? .football5v5 : .football),
                  bundle.currentSession.gameType == context.setup.gameType else { return nil }
        default:
            break
        }
        guard let snapshot = context.latestAuthoritativeSnapshot,
              snapshot.matches(gameType: context.setup.gameType) else { return nil }
        return context
    }

    @discardableResult
    func consume() -> WatchResumeSession? {
        let value = session
        clear()
        return value
    }

    func clear() {
        pendingWriteTask?.cancel()
        pendingWriteTask = nil
        pendingWrite = nil
        // 先作废在途后台写再删文件：清空后旧草稿不会复活。
        invalidatePendingBackgroundWrites()
        try? FileManager.default.removeItem(at: currentFileURL)
        session = nil
    }

    private func replacingCurrentState<
        State: Codable & Sendable,
        Event: Codable & Sendable,
        Intent: Codable & Sendable
    >(
        in bundle: ScoreSessionResumeBundle<State, Event, Intent>,
        with state: State,
        status: SessionStatus
    ) -> ScoreSessionResumeBundle<State, Event, Intent> {
        let current = bundle.currentSession
        let rebased = ScoreSession<State, Event>(
            sessionId: current.sessionId,
            gameType: current.gameType,
            ruleFamily: current.ruleFamily,
            reducerType: current.reducerType,
            version: current.version + 1,
            state: state,
            events: [],
            status: status,
            participants: current.participants,
            metadata: current.metadata
        )
        return ScoreSessionResumeBundle(
            replaySeed: rebased,
            currentSession: rebased,
            undoFrames: [],
            timeline: [],
            auxiliaryPayload: bundle.auxiliaryPayload
        )
    }
}
