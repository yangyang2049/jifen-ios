import Foundation
import LinkCore
import Observation
import OSLog
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
        mode: WatchBasketballTrainingMode,
        history: [WatchBasketballTrainingShot]
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
        setup: LinkedScoreboardSetup
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
            pendingTerminalMessageIds: []
        )
    }

    init(
        sessionId: UUID,
        revision: UInt64,
        authorityEpoch: UInt64 = 0,
        controlRole: LinkControlRole,
        setup: LinkedScoreboardSetup
    ) {
        self.init(
            handle: LinkedMatchHandle(sessionId: sessionId),
            revision: revision,
            authorityEpoch: authorityEpoch,
            controlRole: controlRole,
            setup: setup
        )
    }
}

struct WatchResumeSession: Codable, Sendable {
    /// Schema 3 adopts stable team identity for archery side exchanges.
    /// Schema-2 sessions on the current storage key are migrated on restore.
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

    private let defaults: UserDefaults
    private let now: () -> Date
    private let storageKey = "watch_resume_session"
    private let legacyCleanupMarkerKey = "watch_resume_legacy_cleanup_v1"
    /// 得分高频触发 persistResumeSession；把落盘合并为 750ms 防抖，
    /// 内存中的 session 立即更新（resume/clear 语义不受影响），
    /// 只有 defaults 写入被推迟。切后台时 flushPendingWrite 保证不丢。
    private var pendingWrite: (data: Data, key: String)?
    private var pendingWriteTask: Task<Void, Never>?
    private static let writeDebounceNanoseconds: UInt64 = 750_000_000

    private(set) var session: WatchResumeSession?
    private(set) var lastErrorMessage: String?
    private(set) var restoreAttemptCount = 0

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        if !defaults.bool(forKey: legacyCleanupMarkerKey) {
            defaults.removeObject(forKey: "watch_resume_session_v1")
            if defaults === UserDefaults.standard {
                let applicationSupport = FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                )[0]
                for oldRoot in [
                    applicationSupport.appendingPathComponent("jifen-v2", isDirectory: true),
                    applicationSupport
                        .appendingPathComponent("jifen", isDirectory: true)
                        .appendingPathComponent("resume", isDirectory: true)
                ] {
                    try? FileManager.default.removeItem(at: oldRoot)
                }
            }
            defaults.set(true, forKey: legacyCleanupMarkerKey)
        }
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
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(WatchResumeSession.self, from: data),
              let restored = restoredSession(from: decoded) else {
            defaults.removeObject(forKey: storageKey)
            session = nil
            return
        }
        if now().timeIntervalSince(restored.savedAt) > Self.sessionTTL {
            defaults.removeObject(forKey: storageKey)
            session = nil
            return
        }
        if decoded.schemaVersion != restored.schemaVersion,
           let migratedData = try? JSONEncoder().encode(restored) {
            defaults.set(migratedData, forKey: storageKey)
        }
        session = restored
    }

    private func restoredSession(from decoded: WatchResumeSession) -> WatchResumeSession? {
        if decoded.schemaVersion == WatchResumeSession.currentSchemaVersion {
            return decoded
        }
        guard decoded.schemaVersion == 2 else { return nil }

        let payload: WatchResumePayload
        switch decoded.payload {
        case .archery(let state, let undoStates, let restState):
            payload = .archery(
                state: state.normalizedFromLegacyPhysicalSideSwap(),
                undoStates: undoStates.map { $0.normalizedFromLegacyPhysicalSideSwap() },
                restState: restState
            )
        default:
            payload = decoded.payload
        }

        return WatchResumeSession(
            savedAt: decoded.savedAt,
            startedAt: decoded.startedAt,
            scoreLine: decoded.scoreLine,
            emoji: decoded.emoji,
            payload: payload,
            actionLog: decoded.actionLog,
            link: decoded.link
        )
    }

    func save(_ value: WatchResumeSession) {
        var refreshed = value
        refreshed.savedAt = now()
        do {
            let data = try JSONEncoder().encode(refreshed)
            session = refreshed
            lastErrorMessage = nil
            scheduleWrite(data, forKey: storageKey)
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

    private func scheduleWrite(_ data: Data, forKey key: String) {
        pendingWrite = (data, key)
        pendingWriteTask?.cancel()
        pendingWriteTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.writeDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            self?.flushPendingWrite()
        }
    }

    /// 立即落盘待写数据（切后台/退出计分板前调用）。
    func flushPendingWrite() {
        pendingWriteTask?.cancel()
        pendingWriteTask = nil
        guard let pending = pendingWrite else { return }
        pendingWrite = nil
        defaults.set(pending.data, forKey: pending.key)
    }

    func clearError() {
        lastErrorMessage = nil
    }

    func refreshLinkContext(_ context: WatchLinkResumeContext) {
        guard let value = session, value.link?.sessionId == context.sessionId else { return }
        var actionLog = value.actionLog
        actionLog.merge(detailedActions: context.setup.detailedActions)
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
        guard let value = session, value.link?.sessionId == context.sessionId else { return }

        let updated: (payload: WatchResumePayload, scoreLine: String)?
        switch (value.payload, snapshot) {
        case (.rally(let gameType, let bundle, let restState), .rally(let state)):
            let score = state.leftSets + state.rightSets > 0
                ? "\(state.leftSets) - \(state.rightSets)"
                : "\(state.leftPoints) : \(state.rightPoints)"
            updated = (
                .rally(
                    gameType: gameType,
                    bundle: replacingCurrentState(in: bundle, with: state),
                    restState: restState
                ),
                score
            )
        case (.tennis(let isDoubles, let bundle, let restState), .tennis(let state)):
            let score = state.rules.setScoringMode == .tiebreakOnly
                ? "\(state.leftPoints) : \(state.rightPoints)"
                : "\(state.leftSets) - \(state.rightSets)"
            updated = (
                .tennis(
                    isDoubles: isDoubles,
                    bundle: replacingCurrentState(in: bundle, with: state),
                    restState: restState
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
        var actionLog = value.actionLog
        actionLog.merge(detailedActions: context.setup.detailedActions)
        save(WatchResumeSession(
            startedAt: value.startedAt,
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
        defaults.removeObject(forKey: storageKey)
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
