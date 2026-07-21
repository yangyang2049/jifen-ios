import Combine
import Foundation
import LinkCore
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
        let screenSide = sidesSwapped ? status.side.opposite : status.side
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
    var finished: Bool
    var keyPoint: LocalScoreboardKeyPoint? = nil
    var revision: UInt64
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

/// Bridges the transport-neutral sync protocol to the currently visible scoreboard.
/// The host owns all score mutation; remote controllers only submit intents.
@MainActor
final class LocalScoreboardSyncCoordinator: ObservableObject {
    static let shared = LocalScoreboardSyncCoordinator()

    @Published private(set) var displayState: LocalScoreboardDisplayState?
    @Published private(set) var connectionMessage: String?

    private var snapshotProvider: (() -> LocalScoreboardDisplayState)?
    private var intentHandler: ((LocalScoreboardIntent) -> Void)?
    private var revision: UInt64 = 0
    private let sessionID = UUID()
    private var gate = RealtimeRevisionGate()

    private init() {
        LocalPeerRoomManager.shared.onEnvelope = { [weak self] envelope in
            self?.receive(envelope)
        }
    }

    func registerHost(
        snapshot: @escaping () -> LocalScoreboardDisplayState,
        handleIntent: @escaping (LocalScoreboardIntent) -> Void
    ) {
        snapshotProvider = snapshot
        intentHandler = handleIntent
        publishSnapshot()
    }

    func unregisterHost() {
        snapshotProvider = nil
        intentHandler = nil
    }

    func publishSnapshot() {
        guard LocalPeerRoomManager.shared.localRole == .hostController,
              var state = snapshotProvider?() else { return }
        revision += 1
        state.revision = revision
        displayState = state
        LocalPeerRoomManager.shared.broadcastPayload(
            state,
            kind: .snapshot,
            sessionID: sessionID,
            revision: revision
        )
    }

    func sendIntent(_ intent: LocalScoreboardIntent) {
        guard LocalPeerRoomManager.shared.localRole == .remoteController else { return }
        LocalPeerRoomManager.shared.broadcastPayload(
            intent,
            kind: .intent,
            sessionID: displayState.map { _ in sessionID },
            revision: displayState?.revision ?? 0
        )
    }

    private func receive(_ envelope: RealtimeSyncEnvelope) {
        switch envelope.kind {
        case .intent where LocalPeerRoomManager.shared.localRole == .hostController:
            guard let intent = try? envelope.decodePayload(LocalScoreboardIntent.self) else { return }
            if intent == .requestSnapshot {
                publishSnapshot()
                return
            }
            intentHandler?(intent)
            publishSnapshot()

        case .snapshot where LocalPeerRoomManager.shared.localRole != .hostController:
            guard let state = try? envelope.decodePayload(LocalScoreboardDisplayState.self) else { return }
            if gate.roomID == nil {
                gate.begin(roomID: envelope.roomID, sessionID: envelope.sessionID)
            }
            if gate.requiresResync(for: envelope) {
                connectionMessage = NSLocalizedString("sync_resyncing", value: "正在补齐比分…", comment: "")
                sendIntent(.requestSnapshot)
            }
            guard gate.accept(envelope) else { return }
            displayState = state
            connectionMessage = nil

        case .controllerPaused:
            connectionMessage = NSLocalizedString("sync_host_paused", value: "主控设备暂离", comment: "")
        case .controllerResumed:
            connectionMessage = NSLocalizedString("sync_connected", value: "已连接", comment: "")
            sendIntent(.requestSnapshot)
        case .matchFinished:
            connectionMessage = NSLocalizedString("sync_match_finished", value: "比赛已结束", comment: "")
        default:
            break
        }
    }
}
