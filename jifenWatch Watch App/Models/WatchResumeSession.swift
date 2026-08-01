import Foundation
import LinkCore
import Observation
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
    case basketballTraining(
        mode: WatchBasketballTrainingMode,
        history: [WatchBasketballTrainingShot]
    )
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
    /// Bumped to 2: `actionLog` changed from Optional to non-Optional.
    /// The storage key also changed from `watch_resume_session_v1` to
    /// `watch_resume_session`, so old data is never read. This bump keeps
    /// the version in sync with the format for future migrations.
    static let currentSchemaVersion = 2

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

    private let defaults: UserDefaults
    private let now: () -> Date
    private let storageKey = "watch_resume_session"

    private(set) var session: WatchResumeSession?
    private(set) var lastErrorMessage: String?

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
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
        session = nil
        reload()
    }

    func reload() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(WatchResumeSession.self, from: data),
              decoded.schemaVersion == WatchResumeSession.currentSchemaVersion else {
            defaults.removeObject(forKey: storageKey)
            session = nil
            return
        }
        if now().timeIntervalSince(decoded.savedAt) > Self.sessionTTL {
            defaults.removeObject(forKey: storageKey)
            session = nil
            return
        }
        session = decoded
    }

    func save(_ value: WatchResumeSession) {
        var refreshed = value
        refreshed.savedAt = now()
        do {
            let data = try JSONEncoder().encode(refreshed)
            defaults.set(data, forKey: storageKey)
            session = refreshed
            lastErrorMessage = nil
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
                state.playerPoints.map(String.init).joined(separator: " : ")
            )
        case (.snooker(_, _, let leftName, let rightName), .snooker(let state)):
            updated = (
                .snooker(state: state, undoStates: [], leftName: leftName, rightName: rightName),
                "\(state.leftFrames)-\(state.rightFrames) / \(state.leftScore):\(state.rightScore)"
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
