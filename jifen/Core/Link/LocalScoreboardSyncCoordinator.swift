import Combine
import Foundation
import ScoreCore

struct LocalScoreboardKeyPoint: Codable, Equatable {
    enum Kind: String, Codable {
        case game
        case set
        case match
        case unknown

        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer().decode(String.self)
            self = Self(rawValue: value) ?? .unknown
        }
    }

    enum Side: String, Codable {
        case left
        case right
        case unknown

        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer().decode(String.self)
            self = Self(rawValue: value) ?? .unknown
        }
    }

    var kind: Kind
    var side: Side

    var isRenderable: Bool { kind != .unknown && side != .unknown }

    init?(status: KeyPointStatus?, sidesSwapped: Bool) {
        guard let status else { return nil }
        switch status.kind {
        case .game: kind = .game
        case .set: kind = .set
        case .match: kind = .match
        }
        let screenSide = TeamScreenLayout(sidesSwapped: sidesSwapped)
            .screenSide(of: TeamScreenLayout.teamID(forEngine: status.side))
        side = screenSide == .left ? .left : .right
    }

    static func syncValue(
        _ keyPoint: LocalScoreboardKeyPoint?,
        finished: Bool,
        isEditing: Bool
    ) -> LocalScoreboardKeyPoint? {
        guard !finished, !isEditing else { return nil }
        return keyPoint
    }
}

struct LocalScoreboardDisplayState: Codable, Equatable {
    var gameID: String
    var title: String
    var leftName: String
    var rightName: String
    var leftScore: String
    var rightScore: String
    var leftDetail: String?
    var rightDetail: String?
    var themeID: String
    var fontID: String
    var scoreMultiplier: Double? = nil
    var nameMultiplier: Double? = nil
    var secondaryMultiplier: Double? = nil
    var finished: Bool
    var keyPoint: LocalScoreboardKeyPoint? = nil
    var revision: UInt64
    /// Optional full-fidelity state for the process-local dedicated display.
    /// The compact fields remain the common in-process scoreboard snapshot.
    var externalState: ScoreboardDisplayState? = nil
}

enum LocalScoreboardIntent: String, Codable, CaseIterable {
    case addLeft = "add_left"
    case addRight = "add_right"
    case subtractLeft = "subtract_left"
    case subtractRight = "subtract_right"
    case undo
    case exchangeSides = "exchange_sides"
    case requestSnapshot = "request_snapshot"
}

enum LocalScoreboardMutationPolicy {
    static func allowsMutation(
        isEditing: Bool,
        finished: Bool,
        scoringLocked: Bool
    ) -> Bool {
        !isEditing && !finished && !scoringLocked
    }
}

/// Publishes the currently visible scoreboard to a system-managed external
/// display. The source-compatible intent callback is intentionally dormant in
/// the offline release; phone-to-phone LAN control is not initialized.
@MainActor
final class LocalScoreboardSyncCoordinator: ObservableObject {
    static let shared = LocalScoreboardSyncCoordinator()

    @Published private(set) var displayState: LocalScoreboardDisplayState?

    private var snapshotProvider: (() -> LocalScoreboardDisplayState)?
    private var revision: UInt64 = 0
    private var externalOwnerID: String?
    private var externalLeaseID: UInt64?
    private var genericMatchClockOwnerID: String?
    private var genericMatchClockProvider: (() -> ScoreboardDisplayClock?)?

    private static let genericMatchClockGameIDs: Set<String> = [
        "pingpong",
        "volleyball",
        "air_volleyball",
        "beach_volleyball",
        "guandan",
        "shengji",
        "simple_score"
    ]

    private init() {}

    func registerHost(
        snapshot: @escaping () -> LocalScoreboardDisplayState,
        handleIntent: @escaping (LocalScoreboardIntent) -> Void
    ) {
        if let externalOwnerID, let externalLeaseID {
            ScoreboardDisplayOutputs.shared.release(ownerID: externalOwnerID, leaseID: externalLeaseID)
        }
        snapshotProvider = snapshot
        // The callback stays in the source-compatible API because every
        // scoreboard already provides one. The offline release has no remote
        // controller transport, so intents are never delivered here.
        _ = handleIntent
        let ownerID = "local-scoreboard-\(UUID().uuidString)"
        var initial = snapshot()
        initial.revision = revision
        let initialExternalState = decoratedExternalState(for: initial)
        initial.externalState = initialExternalState
        externalOwnerID = ownerID
        externalLeaseID = ScoreboardDisplayOutputs.shared.bind(
            ownerID: ownerID,
            initial: initialExternalState
        )
        attachCloudSyncIfSharing(gameType: initialExternalState.gameType)
        publishSnapshot()
    }

    /// 云同步分享中进入记分页：绑定项目并进入 IN_GAME（对齐安卓 ScoreboardDisplayEffects）。
    private func attachCloudSyncIfSharing(gameType: String) {
        guard CloudSyncSession.shared.isSharingActive() else { return }
        guard CloudSyncSession.shared.canAttach(gameType: gameType) else { return }
        Task { await CloudSyncSession.shared.controller?.updateMatchGameType(gameType) }
        CloudSyncSession.shared.markInGame(gameType: gameType)
    }

    /// Adds the launch-scoped, count-up match clock to supported generic
    /// scoreboards. The owner token prevents a departing page from clearing a
    /// newer page's provider during a navigation transition.
    func registerGenericMatchClock(
        ownerID: String,
        provider: @escaping () -> ScoreboardDisplayClock?
    ) {
        genericMatchClockOwnerID = ownerID
        genericMatchClockProvider = provider
        publishSnapshot()
    }

    func unregisterGenericMatchClock(ownerID: String) {
        guard genericMatchClockOwnerID == ownerID else { return }
        genericMatchClockOwnerID = nil
        genericMatchClockProvider = nil
        publishSnapshot()
    }

    func unregisterHost() {
        if CloudSyncSession.shared.state?.phase == .inGame {
            CloudSyncSession.shared.markSharing()
        }
        if let externalOwnerID, let externalLeaseID {
            ScoreboardDisplayOutputs.shared.release(ownerID: externalOwnerID, leaseID: externalLeaseID)
        }
        externalOwnerID = nil
        externalLeaseID = nil
        snapshotProvider = nil
        displayState = nil
    }

    func publishSnapshot() {
        guard var state = snapshotProvider?() else { return }
        revision += 1
        state.revision = revision
        let externalState = decoratedExternalState(for: state)
        state.externalState = externalState
        displayState = state
        if let externalOwnerID, let externalLeaseID {
            ScoreboardDisplayOutputs.shared.publish(
                ownerID: externalOwnerID,
                leaseID: externalLeaseID,
                state: externalState,
                priority: state.finished ? .urgent : .normal
            )
        }
        // 云同步第二路分发（本地投屏与云端共用同一 DisplayState 组装）。
        CloudSyncSession.shared.publish(externalState)
    }

    private func decoratedExternalState(
        for state: LocalScoreboardDisplayState
    ) -> ScoreboardDisplayState {
        var externalState = state.externalState ?? ScoreboardDisplayState(compactState: state)
        if externalState.clock == nil,
           Self.genericMatchClockGameIDs.contains(externalState.gameType),
           let clock = genericMatchClockProvider?() {
            externalState.clock = clock
        }
        return externalState
    }
}
