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
    case basketball(
        gameMode: BasketballGameMode,
        bundle: ScoreSessionResumeBundle<BasketballMatchState, BasketballMatchEvent, BasketballMatchIntent>
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

struct WatchResumeLinkContext: Codable, Sendable {
    let sessionId: UUID
    let revision: UInt64
    let controlRole: LinkControlRole
    let setup: LinkedScoreboardSetup
}

struct WatchResumeSession: Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var savedAt: Date
    let startedAt: Date
    let scoreLine: String
    let emoji: String
    let payload: WatchResumePayload
    let link: WatchResumeLinkContext?

    init(
        savedAt: Date = Date(),
        startedAt: Date,
        scoreLine: String,
        emoji: String,
        payload: WatchResumePayload,
        link: WatchResumeLinkContext? = nil
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.savedAt = savedAt
        self.startedAt = startedAt
        self.scoreLine = scoreLine
        self.emoji = emoji
        self.payload = payload
        self.link = link
    }
}

@MainActor
@Observable
final class WatchResumeSessionStore {
    static let shared = WatchResumeSessionStore()
    static let ttl: TimeInterval = 10 * 60

    private let defaults: UserDefaults
    private let now: () -> Date
    private let storageKey = "watch_resume_session_v1"

    private(set) var session: WatchResumeSession?
    private(set) var expiredLinkContext: WatchResumeLinkContext?

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        session = nil
        expiredLinkContext = nil
        reload()
    }

    func reload() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(WatchResumeSession.self, from: data),
              decoded.schemaVersion == WatchResumeSession.currentSchemaVersion else {
            defaults.removeObject(forKey: storageKey)
            session = nil
            expiredLinkContext = nil
            return
        }
        guard now().timeIntervalSince(decoded.savedAt) <= Self.ttl else {
            expiredLinkContext = decoded.link
            defaults.removeObject(forKey: storageKey)
            session = nil
            return
        }
        session = decoded
        expiredLinkContext = nil
    }

    func save(_ value: WatchResumeSession) {
        var refreshed = value
        refreshed.savedAt = now()
        guard let data = try? JSONEncoder().encode(refreshed) else { return }
        defaults.set(data, forKey: storageKey)
        session = refreshed
        expiredLinkContext = nil
    }

    func refreshLinkContext(_ context: WatchResumeLinkContext) {
        guard let value = session, value.link?.sessionId == context.sessionId else { return }
        save(WatchResumeSession(
            startedAt: value.startedAt,
            scoreLine: value.scoreLine,
            emoji: value.emoji,
            payload: value.payload,
            link: context
        ))
    }

    /// Apply phone-controller updates while the scoreboard is suspended on the
    /// watch home screen. Remote changes become a new replay seed, so future
    /// watch undo never crosses the phone takeover boundary.
    func applyLinkedSnapshot(
        _ snapshot: LinkedScoreboardSnapshot,
        context: WatchResumeLinkContext
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
        case (.basketball(let gameMode, let bundle), .basketball(let state)):
            updated = (
                .basketball(
                    gameMode: gameMode,
                    bundle: replacingCurrentState(in: bundle, with: state)
                ),
                "\(state.leftScore) : \(state.rightScore)"
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
        save(WatchResumeSession(
            startedAt: value.startedAt,
            scoreLine: updated.scoreLine,
            emoji: value.emoji,
            payload: updated.payload,
            link: context
        ))
    }

    @discardableResult
    func consume() -> WatchResumeSession? {
        let value = session
        clear()
        return value
    }

    func consumeExpiredLinkContext() -> WatchResumeLinkContext? {
        defer { expiredLinkContext = nil }
        return expiredLinkContext
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
        session = nil
        expiredLinkContext = nil
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
