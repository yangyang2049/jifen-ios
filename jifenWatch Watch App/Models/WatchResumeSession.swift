import Foundation
import LinkCore
import Observation
import OSLog
import RecordCore
import ScoreCore
import SessionCore

enum WatchResumePayload: Codable, Sendable {
    case rally(
        gameType: GameType,
        bundle: ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>,
        restState: WatchRestState?
    )
    case tennis(
        isDoubles: Bool,
        bundle: ScoreSessionResumeBundle<TennisMatchState, TennisMatchEvent, TennisMatchIntent>,
        restState: WatchRestState?
    )
    case archery(
        state: ArcheryMatchState,
        undoStates: [ArcheryMatchState],
        restState: WatchRestState?
    )
    case eightBall(
        state: EightBallState,
        undoStates: [EightBallState],
        leftName: String,
        rightName: String
    )
    case nineBall(
        state: NineBallChaseState,
        undoStates: [NineBallChaseState]
    )
    case snooker(
        state: SnookerState,
        undoStates: [SnookerState],
        leftName: String,
        rightName: String
    )
    case football(
        isFiveAside: Bool,
        state: WatchFootballState,
        undoStates: [WatchFootballUndoState],
        leftName: String,
        rightName: String
    )
    case basketballTraining(
        mode: ShotTrainingMode,
        history: [ShotTrainingShot],
        earlierCounts: ShotTrainingCounts? = nil
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
        case .football(let isFiveAside, _, _, _, _):
            return WatchFootballRules.watchGameType(isFiveAside: isFiveAside)
        case .basketballTraining:
            return .basketballTraining
        }
    }
}

extension WatchLinkResumeContext {
    var sessionId: UUID { handle.sessionId }
    var controlRole: LinkControlRole { role }

    init(
        handle: LinkedMatchHandle,
        revision: UInt64,
        authorityEpoch: UInt64,
        controlRole: LinkControlRole,
        setup: LinkedScoreboardSetup,
        actionHistory: LinkSnapshotHistory? = nil
    ) {
        self.init(
            handle: handle,
            setup: setup,
            role: controlRole,
            authorityEpoch: authorityEpoch,
            revision: revision,
            latestAuthoritativeSnapshot: setup.initialSnapshot,
            detailedActions: setup.detailedActions,
            completedMatchIds: [],
            pendingTerminalMessageIds: [],
            actionHistory: actionHistory
        )
    }

    init(
        sessionId: UUID,
        revision: UInt64,
        authorityEpoch: UInt64 = 0,
        controlRole: LinkControlRole,
        setup: LinkedScoreboardSetup,
        actionHistory: LinkSnapshotHistory? = nil
    ) {
        self.init(
            handle: LinkedMatchHandle(sessionId: sessionId),
            revision: revision,
            authorityEpoch: authorityEpoch,
            controlRole: controlRole,
            setup: setup,
            actionHistory: actionHistory
        )
    }
}

struct WatchResumeSession: Codable, Sendable {
    /// 首发格式直接起算：restore 只接受当前 schema 版本，旧版本会话一律视为
    /// 无会话丢弃，不做任何迁移。
    static let currentSchemaVersion = 3

    let schemaVersion: Int
    var savedAt: Date
    let startedAt: Date
    let scoreLine: String
    let emoji: String
    let payload: WatchResumePayload
    let actionLog: WatchScoreActionLog
    let link: WatchLinkResumeContext?

    init(
        savedAt: Date = Date(),
        startedAt: Date,
        scoreLine: String,
        emoji: String,
        payload: WatchResumePayload,
        actionLog: WatchScoreActionLog? = nil,
        link: WatchLinkResumeContext? = nil
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.savedAt = savedAt
        self.startedAt = startedAt
        self.scoreLine = scoreLine
        self.emoji = emoji
        self.payload = payload
        self.actionLog = actionLog ?? WatchScoreActionLog(startedAt: startedAt)
        self.link = link
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
        if let session, session.link == nil, hasRecordStart(session.startedAt, record: candidate) {
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

    func refreshLinkContext(_ context: WatchLinkResumeContext) {
        guard let value = session, value.link?.handle == context.handle else { return }
        var actionLog = value.actionLog
        actionLog.merge(detailedActions: context.detailedActions, removing: context.actionHistory?.removedActionIDs ?? [])
        save(WatchResumeSession(
            startedAt: value.startedAt,
            scoreLine: value.scoreLine,
            emoji: value.emoji,
            payload: value.payload,
            actionLog: actionLog,
            link: context
        ))
    }

    /// Apply phone-controller updates while the scoreboard is suspended on the
    /// watch home screen. Remote changes become a new replay seed, so future
    /// watch undo never crosses the phone takeover boundary.
    func applyLinkedSnapshot(
        _ snapshot: LinkedScoreboardSnapshot,
        context: WatchLinkResumeContext
    ) {
        guard let value = session, let previous = value.link, previous.sessionId == context.sessionId else { return }
        let beganNewMatch = previous.handle.matchGeneration < context.handle.matchGeneration
        guard previous.handle == context.handle || beganNewMatch else { return }

        let updated: (payload: WatchResumePayload, scoreLine: String)?
        let startedAt = snapshot.basketballTrainingState?.startTime ?? (beganNewMatch ? now() : value.startedAt)
        switch (value.payload, snapshot) {
        case (.rally(let gameType, let bundle, _), .rally(let state)):
            let score = state.leftSets + state.rightSets > 0
                ? "\(state.leftSets) - \(state.rightSets)"
                : "\(state.leftPoints) : \(state.rightPoints)"
            updated = (
                .rally(
                    gameType: gameType,
                    bundle: replacingCurrentState(in: bundle, with: state),
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
                    bundle: replacingCurrentState(in: bundle, with: state),
                    restState: WatchRestState.fromOfficialBreak(state.officialBreakState)
                ),
                score
            )
        case (.archery(var state, _, let restState), .archery(let linkedState)):
            linkedState.applying(to: &state)
            let score = state.leftSetPoints + state.rightSetPoints > 0
                ? "\(state.leftSetPoints) : \(state.rightSetPoints)"
                : "\(state.leftArrowSum) : \(state.rightArrowSum)"
            updated = (.archery(state: state, undoStates: [], restState: restState), score)
        case (.eightBall(_, _, let leftName, let rightName), .eightBall(let state)):
            updated = (
                .eightBall(state: state, undoStates: [], leftName: leftName, rightName: rightName),
                "\(state.leftPoints) : \(state.rightPoints)"
            )
        case (.nineBall, .nineBall(let state)):
            updated = (
                .nineBall(state: state, undoStates: []),
                state.playerPoints.prefix(state.playerCount).map(String.init).joined(separator: " · ")
            )
        case (.snooker(_, _, let leftName, let rightName), .snooker(let state)):
            updated = (
                .snooker(state: state, undoStates: [], leftName: leftName, rightName: rightName),
                "\(state.leftFrames)-\(state.rightFrames) / \(state.leftScore):\(state.rightScore)"
            )
        case (.basketballTraining, .basketballTraining(let state)):
            let counts = state.counts
            updated = (
                .basketballTraining(
                    mode: state.mode,
                    history: state.shots,
                    earlierCounts: state.earlierCounts
                ),
                "\(counts.made)/\(counts.attempts) = \(counts.rate)%"
            )
        case (.football(let isFiveAside, _, _, let leftName, let rightName), .football(let state)):
            let footballState = WatchFootballState(
                leftScore: state.leftScore,
                rightScore: state.rightScore,
                clock: state.timer,
                kickedOff: state.kickedOff
            )
            updated = (
                .football(
                    isFiveAside: isFiveAside,
                    state: footballState,
                    undoStates: [],
                    leftName: state.leftName.isEmpty ? leftName : state.leftName,
                    rightName: state.rightName.isEmpty ? rightName : state.rightName
                ),
                "\(state.leftScore) - \(state.rightScore)"
            )
        default:
            updated = nil
        }

        guard let updated else { return }
        var actionLog = beganNewMatch ? WatchScoreActionLog(startedAt: startedAt) : value.actionLog
        actionLog.merge(detailedActions: context.detailedActions, removing: context.actionHistory?.removedActionIDs ?? [])
        actionLog.clearUndoHistory()
        save(WatchResumeSession(
            startedAt: startedAt,
            scoreLine: updated.scoreLine,
            emoji: value.emoji,
            payload: updated.payload,
            actionLog: actionLog,
            link: context
        ))
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
        with state: State
    ) -> ScoreSessionResumeBundle<State, Event, Intent> {
        let current = bundle.currentSession
        let rebased = ScoreSession<State, Event>(
            sessionId: current.sessionId,
            gameType: current.gameType,
            ruleFamily: current.ruleFamily,
            reducerType: current.reducerType,
            version: current.version,
            state: state,
            events: current.events,
            status: current.status,
            participants: current.participants,
            metadata: current.metadata
        )
        return ScoreSessionResumeBundle(
            replaySeed: rebased,
            currentSession: rebased,
            undoFrames: [],
            timeline: []
        )
    }
}
