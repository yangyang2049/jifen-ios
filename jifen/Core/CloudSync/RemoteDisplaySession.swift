import Foundation
import Combine

/// 显示端（观看端）会话：短码加入 → WS 接收快照 → 渲染状态。
/// 对齐安卓 RemoteSyncDisplaySource + DisplayPresentationReducer 的核心语义。
@MainActor
final class RemoteDisplaySession: ObservableObject {
    enum Mode: String {
        case connecting
        case waiting
        case live
        case finished
        case error
    }

    enum ControllerStatus: String {
        case none
        case away
        case disconnected
        case left
        case sessionEnded
    }

    @Published private(set) var mode: Mode = .connecting
    @Published private(set) var displayState: ScoreboardDisplayState?
    @Published private(set) var controllerStatus: ControllerStatus = .none
    @Published private(set) var errorMessage: String?
    @Published private(set) var connectionState: WsConnectionState = .disconnected

    private(set) var matchId: String?
    private(set) var matchName: String?
    private(set) var joinedCode: String

    private var wsHandlerIDs: [(WsMessageType, UUID)] = []
    private var connectionStateCancellable: AnyCancellable?
    private var isConnectedOnce = false

    init(code: String) {
        joinedCode = code
    }

    // MARK: 加入

    /// join-by-code → 连接 WS；失败抛出错误由 UI 映射文案。
    func connect() async throws {
        mode = .connecting
        let response = try await MatchSyncAPI.shared.joinByCode(joinedCode)
        matchId = response.matchId
        matchName = response.match?.name
        MatchWebSocketManager.shared.enableAutoReconnect()
        MatchWebSocketManager.shared.connect(
            matchId: response.matchId,
            token: response.wsToken,
            wsUrl: response.wsUrl,
            displayMode: true
        )
        registerWsHandlers()
        connectionStateCancellable = MatchWebSocketManager.shared.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.connectionState = state
                if state == .disconnected, self.isConnectedOnce, self.mode != .error {
                    self.controllerStatus = .disconnected
                }
            }
        // 若短时间内没收到快照，进入等待态。
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, self.mode == .connecting else { return }
            self.mode = .waiting
        }
    }

    func stop() {
        MatchWebSocketManager.shared.disableAutoReconnect()
        MatchWebSocketManager.shared.disconnect(sendLeave: true, leaveReason: "display_exit")
        wsHandlerIDs.forEach { id, uuid in MatchWebSocketManager.shared.off(id, id: uuid) }
        wsHandlerIDs.removeAll()
        connectionStateCancellable?.cancel()
        connectionStateCancellable = nil
    }

    // MARK: WS 事件

    private func registerWsHandlers() {
        let ws = MatchWebSocketManager.shared
        wsHandlerIDs.append((.joinSuccess, ws.on(.joinSuccess) { [weak self] _ in
            self?.isConnectedOnce = true
        }))
        wsHandlerIDs.append((.participantUpdate, ws.on(.participantUpdate) { [weak self] envelope in
            self?.handleSnapshot(envelope)
        }))
        wsHandlerIDs.append((.participantSync, ws.on(.participantSync) { [weak self] envelope in
            self?.handleSnapshot(envelope)
        }))
        wsHandlerIDs.append((.controllerAway, ws.on(.controllerAway) { [weak self] _ in
            self?.controllerStatus = .away
        }))
        wsHandlerIDs.append((.controllerResume, ws.on(.controllerResume) { [weak self] _ in
            self?.controllerStatus = .none
        }))
        wsHandlerIDs.append((.controllerDisconnected, ws.on(.controllerDisconnected) { [weak self] _ in
            self?.controllerStatus = .disconnected
        }))
        wsHandlerIDs.append((.controllerLeft, ws.on(.controllerLeft) { [weak self] _ in
            self?.controllerStatus = .left
            guard let self else { return }
            self.mode = .error
            self.errorMessage = NSLocalizedString(
                "sync_controller_disconnected",
                value: "控制端已断开连接",
                comment: ""
            )
        }))
        wsHandlerIDs.append((.sessionEnded, ws.on(.sessionEnded) { [weak self] _ in
            guard let self else { return }
            self.stop()
            self.controllerStatus = .sessionEnded
            self.mode = .error
            self.errorMessage = NSLocalizedString("sync_session_ended", value: "会话已结束", comment: "")
        }))
        wsHandlerIDs.append((.error, ws.on(.error) { [weak self] envelope in
            guard let self else { return }
            self.errorMessage = envelope.errorText
        }))
    }

    private func handleSnapshot(_ envelope: WsEnvelope) {
        isConnectedOnce = true
        controllerStatus = controllerStatus == .away ? .away : .none

        let sessionPhase = envelope.sessionPhase
        let isIdleFrame = sessionPhase == "idle" && envelope.replaceParticipants

        guard let stateMap = envelope.displayStateMap,
              let state = DisplayStateWireCodec.decode(stateMap) else {
            if isIdleFrame {
                mode = .waiting
                displayState = nil
            }
            return
        }
        displayState = state
        mode = state.result?.ended == true ? .finished : .live
    }
}
