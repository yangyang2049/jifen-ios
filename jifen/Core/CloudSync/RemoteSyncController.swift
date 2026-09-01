import Foundation
import Combine

/// 分享端（记分端）控制器，对齐安卓 RemoteSyncController。
@MainActor
final class RemoteSyncController: ObservableObject {
    struct SharingState: Equatable {
        var isSharing = false
        var matchId = ""
        var shortCode = ""
        var shortCodeExpiry: Int64 = 0
        var shortCodeError = false
        var connectionState: WsConnectionState = .disconnected
        var errorMessage: String? = nil
        var connectedDisplays: [WsDisplayPresence] = []
    }

    /// 快照修复重发延迟（绝对延迟，容忍丢帧），对齐安卓 SNAPSHOT_REPAIR_DELAYS_MS。
    private static let snapshotRepairDelaysMs: [Int64] = [800, 2500]
    private static let forceSyncConnectTimeoutMs: UInt64 = 8_000

    @Published private(set) var state = SharingState()

    private var attached = false
    private var snapshotRequestListener: (() -> Void)?
    private var snapshotRepairTask: Task<Void, Never>?
    private var connectionCancellable: AnyCancellable?
    private var lastPushedMatchEnded = false
    private var activeGameType = CloudSyncGameTypes.placeholder
    private var wsHandlerIDs: [(WsMessageType, UUID)] = []

    func isAttached() -> Bool { attached }

    func setSnapshotRequestListener(_ listener: (() -> Void)?) {
        snapshotRequestListener = listener
    }

    // MARK: 生命周期

    func attach() {
        guard !attached else { return }
        attached = true
        registerWsHandlers()
        // 订阅底层连接状态，保证 UI 上的连接指示实时刷新。
        connectionCancellable = MatchWebSocketManager.shared.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] wsState in
                guard let self, self.state.isSharing, self.state.connectionState != wsState else { return }
                self.state.connectionState = wsState
            }
    }

    func detach() {
        guard attached else { return }
        attached = false
        cancelSnapshotRepairs()
        connectionCancellable?.cancel()
        connectionCancellable = nil
        wsHandlerIDs.forEach { id, uuid in MatchWebSocketManager.shared.off(id, id: uuid) }
        wsHandlerIDs.removeAll()
        snapshotRequestListener = nil
    }

    // MARK: 开始 / 结束分享

    @discardableResult
    func startSharing() async -> Bool {
        do {
            let match = try await MatchSyncAPI.shared.createMatch(gameType: activeGameType)
            let token = try await MatchSyncAPI.shared.getRtToken(matchId: match.id)
            MatchWebSocketManager.shared.enableAutoReconnect()
            MatchWebSocketManager.shared.connect(
                matchId: match.id,
                token: token.rtToken,
                wsUrl: token.wsUrl,
                displayMode: false
            )
            attach()
            let shortCode = await createShortCodeWithRetry(matchId: match.id)
            state = SharingState(
                isSharing: true,
                matchId: match.id,
                shortCode: shortCode.code,
                shortCodeExpiry: shortCode.expiry,
                shortCodeError: shortCode.error,
                connectionState: MatchWebSocketManager.shared.connectionState
            )
            return true
        } catch {
            state.errorMessage = CloudSyncErrorMapper.genericFailureMessage(error)
            return false
        }
    }

    private func createShortCodeWithRetry(matchId: String) async -> (code: String, expiry: Int64, error: Bool) {
        for attempt in 0..<3 {
            if let response = try? await MatchSyncAPI.shared.createShortCode(matchId: matchId), !response.code.isEmpty {
                return (response.code, response.expiresAt, false)
            }
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        return ("", 0, true)
    }

    func retryShortCode() async {
        guard !state.matchId.isEmpty else { return }
        state.shortCodeError = false
        let result = await createShortCodeWithRetry(matchId: state.matchId)
        state.shortCode = result.code
        state.shortCodeExpiry = result.expiry
        state.shortCodeError = result.error
    }

    /// 服务端 SESSION_ENDED / 会话替换后的强制清理。
    func forceDisconnect(sendLeave: Bool, reason: String = "user_exit") {
        cancelSnapshotRepairs()
        MatchWebSocketManager.shared.disableAutoReconnect()
        MatchWebSocketManager.shared.disconnect(sendLeave: sendLeave, leaveReason: reason)
        detach()
        state = SharingState()
        lastPushedMatchEnded = false
    }

    /// 非会话持有者（如临时的显示端复用场景）结束连接。
    func endSharing(sendLeave: Bool = true, reason: String = "user_exit") {
        let sessionOwnsConnection = CloudSyncSession.shared.isSharingActive()
            && CloudSyncSession.shared.isSessionController(self)
        if sessionOwnsConnection && !sendLeave {
            detach()
            return
        }
        forceDisconnect(sendLeave: sendLeave, reason: reason)
    }

    // MARK: 强制同步

    func ensureConnected() async -> Bool {
        guard state.isSharing, !state.matchId.isEmpty else { return false }
        let ws = MatchWebSocketManager.shared
        if ws.isConnected && ws.currentMatchId == state.matchId { return true }
        do {
            let token = try await MatchSyncAPI.shared.getRtToken(matchId: state.matchId)
            ws.enableAutoReconnect()
            ws.connect(matchId: state.matchId, token: token.rtToken, wsUrl: token.wsUrl, displayMode: false)
            let deadline = Date().addingTimeInterval(Double(Self.forceSyncConnectTimeoutMs) / 1000)
            while Date() < deadline {
                if ws.isConnected { return true }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            return ws.isConnected
        } catch {
            state.errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: 项目绑定

    func updateMatchGameType(_ gameType: String) async {
        activeGameType = gameType
        let matchId = state.matchId
        guard !matchId.isEmpty else { return }
        _ = try? await MatchSyncAPI.shared.updateMatchGameType(matchId: matchId, gameType: gameType)
        if state.isSharing {
            snapshotRequestListener?()
        }
    }

    // MARK: 推分

    /// 发送已组装好的 DisplayState 快照；结束态切换时补发 GAME_OVER。
    func publishDisplayState(_ displayState: ScoreboardDisplayState, sessionPhase: String = "active") {
        guard state.isSharing else { return }

        let matchEnded = displayState.result?.ended == true
        if lastPushedMatchEnded && !matchEnded {
            MatchWebSocketManager.shared.sendMatchStarted(gameType: activeGameType)
        }

        guard let wire = DisplayStateWireCodec.encode(displayState),
              DisplayStateWireCodec.isValid(wire) else {
            return
        }

        let participants = Self.mapDisplayStateToParticipants(displayState, wire: wire)
        MatchWebSocketManager.shared.sendParticipantUpdate(participants: participants, sessionPhase: sessionPhase)
        scheduleSnapshotRepairs(participants: participants, sessionPhase: sessionPhase, expectedMatchId: state.matchId)

        if matchEnded && !lastPushedMatchEnded, let result = displayState.result, result.ended {
            let finalScores = (result.finalScores ?? [:]).mapValues { score -> [String: Any] in
                ["score": score.score, "sets": score.sets, "games": score.games]
            }
            MatchWebSocketManager.shared.sendGameOver(
                winner: result.winnerID ?? "draw",
                finalScores: finalScores,
                manualEnd: result.manualEnd
            )
        }
        lastPushedMatchEnded = matchEnded
    }

    private func scheduleSnapshotRepairs(participants: [[String: Any]], sessionPhase: String, expectedMatchId: String) {
        cancelSnapshotRepairs()
        guard !expectedMatchId.isEmpty else { return }
        snapshotRepairTask = Task { [weak self] in
            var previousDelay: Int64 = 0
            for targetDelay in Self.snapshotRepairDelaysMs {
                try? await Task.sleep(nanoseconds: UInt64(targetDelay - previousDelay) * 1_000_000)
                previousDelay = targetDelay
                guard let self, self.attached, self.state.isSharing, self.state.matchId == expectedMatchId else { return }
                MatchWebSocketManager.shared.sendParticipantUpdate(participants: participants, sessionPhase: sessionPhase)
            }
        }
    }

    private func cancelSnapshotRepairs() {
        snapshotRepairTask?.cancel()
        snapshotRepairTask = nil
    }

    // MARK: 控制端状态

    func sendControllerAway(reason: String = "scoreboard_detached") {
        guard state.isSharing else { return }
        MatchWebSocketManager.shared.sendControllerAway(reason: reason)
    }

    func sendControllerResume(reason: String = "scoreboard_attached") {
        guard state.isSharing else { return }
        MatchWebSocketManager.shared.sendControllerResume(reason: reason)
    }

    func sendMatchStarted(gameType: String) {
        guard state.isSharing else { return }
        MatchWebSocketManager.shared.sendMatchStarted(gameType: gameType)
    }

    // MARK: 参与者映射（对齐安卓 RemoteParticipantMapper.mapDisplayStateToParticipants）

    private static func mapDisplayStateToParticipants(
        _ displayState: ScoreboardDisplayState,
        wire: [String: Any]
    ) -> [[String: Any]] {
        let metadata: [String: Any] = ["displayState": wire]
        let base: [[String: Any]]
        if let players = displayState.players, !players.isEmpty {
            let type = players.count > 2 ? "player" : "team"
            base = players.map { player in
                var map: [String: Any] = [
                    "id": player.id,
                    "type": type,
                    "name": player.name,
                    "score": player.score ?? 0,
                    "order": player.order
                ]
                if let color = player.color { map["color"] = color }
                map["metadata"] = metadata
                return map
            }
        } else {
            base = displayState.teams.map { team in
                var map: [String: Any] = [
                    "id": team.id,
                    "type": "team",
                    "name": team.name,
                    "score": team.score,
                    "order": team.order
                ]
                if let sets = team.sets { map["sets"] = sets }
                if let games = team.games { map["games"] = games }
                if let color = team.color { map["color"] = color }
                map["metadata"] = metadata
                return map
            }
        }
        return base
    }

    // MARK: WS 事件

    private func registerWsHandlers() {
        let ws = MatchWebSocketManager.shared
        wsHandlerIDs.append((.error, ws.on(.error) { [weak self] envelope in
            self?.state.errorMessage = envelope.errorText
        }))
        wsHandlerIDs.append((.sessionEnded, ws.on(.sessionEnded) { [weak self] _ in
            guard let self, CloudSyncSession.shared.isSessionController(self) else {
                self?.forceDisconnect(sendLeave: false)
                return
            }
            CloudSyncSession.shared.endFromServer()
        }))
        wsHandlerIDs.append((.connectionReplaced, ws.on(.connectionReplaced) { [weak self] _ in
            guard let self, CloudSyncSession.shared.isSessionController(self) else {
                self?.forceDisconnect(sendLeave: false)
                return
            }
            CloudSyncSession.shared.endFromServer()
        }))
        let applyPresence: (WsEnvelope) -> Void = { [weak self] envelope in
            guard let displays = envelope.displayPresences else { return }
            self?.state.connectedDisplays = displays
        }
        wsHandlerIDs.append((.joinSuccess, ws.on(.joinSuccess, applyPresence)))
        wsHandlerIDs.append((.displayJoined, ws.on(.displayJoined) { [weak self] envelope in
            applyPresence(envelope)
            self?.snapshotRequestListener?()
        }))
        wsHandlerIDs.append((.displayLeft, ws.on(.displayLeft, applyPresence)))
        wsHandlerIDs.append((.displayDisconnected, ws.on(.displayDisconnected, applyPresence)))
        wsHandlerIDs.append((.displaySubscribed, ws.on(.displaySubscribed) { [weak self] _ in
            self?.snapshotRequestListener?()
        }))
        wsHandlerIDs.append((.participantJoined, ws.on(.participantJoined) { [weak self] _ in
            self?.snapshotRequestListener?()
        }))
    }
}
