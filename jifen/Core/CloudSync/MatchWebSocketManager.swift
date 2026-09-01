import Foundation
import Combine
import UIKit

// MARK: - 消息模型（对齐安卓 WsModels）

enum WsMessageType: String, CaseIterable, Sendable {
    case join = "JOIN"
    case ping = "PING"
    case participantUpdate = "PARTICIPANT_UPDATE"
    case leave = "LEAVE"
    case gameOver = "GAME_OVER"
    case joinSuccess = "JOIN_SUCCESS"
    case participantSync = "PARTICIPANT_SYNC"
    case participantJoined = "PARTICIPANT_JOINED"
    case participantLeft = "PARTICIPANT_LEFT"
    case sessionUpdated = "SESSION_UPDATED"
    case sessionEnded = "SESSION_ENDED"
    case displayBind = "DISPLAY_BIND"
    case displaySubscribed = "DISPLAY_SUBSCRIBED"
    case matchStarted = "MATCH_STARTED"
    case controllerAway = "CONTROLLER_AWAY"
    case controllerResume = "CONTROLLER_RESUME"
    case controllerLeft = "CONTROLLER_LEFT"
    case controllerDisconnected = "CONTROLLER_DISCONNECTED"
    case connectionReplaced = "CONNECTION_REPLACED"
    case forceReconnect = "FORCE_RECONNECT"
    case displayJoined = "DISPLAY_JOINED"
    case displayLeft = "DISPLAY_LEFT"
    case displayDisconnected = "DISPLAY_DISCONNECTED"
    case error = "ERROR"
    case pong = "PONG"
}

enum WsConnectionState: String, Sendable {
    case disconnected, connecting, connected, reconnecting
}

struct WsDisplayPresence: Equatable, Sendable {
    var connectionId: String
    var name: String
    var platform: String?
    var deviceType: String?
    var connectedAt: String
}

struct WsEnvelope: @unchecked Sendable {
    var type: String
    var payload: [String: Any]?
    var timestamp: Int64?

    var errorText: String? {
        guard let payload else { return nil }
        return (payload["error"] as? String)
            ?? (payload["message"] as? String)
            ?? (payload["msg"] as? String)
    }

    var displayPresences: [WsDisplayPresence]? {
        guard let payload, payload.keys.contains("displays") else { return nil }
        guard let raw = payload["displays"] as? [[String: Any]] else { return [] }
        return raw.compactMap { item in
            guard let connectionId = item["connectionId"] as? String, !connectionId.isEmpty,
                  let name = item["name"] as? String, !name.isEmpty,
                  let connectedAt = item["connectedAt"] as? String, !connectedAt.isEmpty else {
                return nil
            }
            return WsDisplayPresence(
                connectionId: connectionId,
                name: name,
                platform: item["platform"] as? String,
                deviceType: item["deviceType"] as? String,
                connectedAt: connectedAt
            )
        }
    }

    /// 从参与者 metadata 中提取 displayState（新协议：所有参与者携带同一份）。
    var displayStateMap: [String: Any]? {
        guard let participants = payload?["participants"] as? [[String: Any]] else { return nil }
        for participant in participants {
            if let metadata = participant["metadata"] as? [String: Any],
               let displayState = metadata["displayState"] as? [String: Any] {
                return displayState
            }
        }
        return nil
    }

    var sessionPhase: String? { payload?["sessionPhase"] as? String }
    var replaceParticipants: Bool {
        switch payload?["replace"] {
        case let flag as Bool: return flag
        case let value as String: return value.lowercased() == "true"
        default: return false
        }
    }
}

// MARK: - WebSocket 管理器（对齐安卓 MatchWebSocketManager）

@MainActor
final class MatchWebSocketManager: NSObject, ObservableObject {
    static let shared = MatchWebSocketManager()

    @Published private(set) var connectionState: WsConnectionState = .disconnected

    private var webSocket: URLSessionWebSocketTask?
    private var matchId: String?
    private var token: String?
    private var wsUrl: String?
    private var isDisplayMode = false

    private var handlers: [WsMessageType: [(UUID, (WsEnvelope) -> Void)]] = [:]
    private var pendingQueue: [WsEnvelope] = []
    private var sentUpdateFingerprints: [String] = []
    private var heartbeatTimer: Timer?
    private var receiveLoopTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private var autoReconnectDisabled = false

    private let maxReconnectAttempts = 5
    private let maxSentMessagesCache = 100
    private lazy var session: URLSession = URLSession(configuration: .default)

    override private init() {
        super.init()
    }

    // MARK: 连接管理

    var isConnected: Bool { connectionState == .connected }
    var currentMatchId: String? { matchId }

    func enableAutoReconnect() {
        autoReconnectDisabled = false
        reconnectAttempts = 0
    }

    func disableAutoReconnect() {
        autoReconnectDisabled = true
    }

    func connect(matchId: String, token: String, wsUrl: String, displayMode: Bool = false) {
        disconnectInternal(sendLeave: false)
        enableAutoReconnect()
        self.matchId = matchId
        self.token = token
        self.wsUrl = wsUrl
        self.isDisplayMode = displayMode
        openSocket()
    }

    func disconnect(sendLeave: Bool = false, preserveSession: Bool = false, leaveReason: String = "user_exit") {
        disconnectInternal(sendLeave: sendLeave, leaveReason: leaveReason)
        if !preserveSession {
            matchId = nil
            token = nil
            wsUrl = nil
            isDisplayMode = false
            pendingQueue.removeAll()
            autoReconnectDisabled = false
        }
    }

    private func disconnectInternal(sendLeave: Bool, leaveReason: String = "user_exit") {
        if sendLeave {
            self.sendLeave(reason: leaveReason)
        }
        stopHeartbeat()
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempts = maxReconnectAttempts
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        webSocket?.cancel(with: .normalClosure, reason: "client disconnect".data(using: .utf8))
        webSocket = nil
        connectionState = .disconnected
    }

    private func openSocket() {
        guard let wsUrl, let token else { return }
        connectionState = .connecting
        var components = URLComponents(string: wsUrl)
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components?.url else {
            connectionState = .disconnected
            return
        }
        let task = session.webSocketTask(with: url)
        webSocket = task
        task.resume()
        startReceiveLoop()
        connectionState = .connected
        reconnectAttempts = 0
        sendJoin()
        startHeartbeat()
        flushQueue()
    }

    private func startReceiveLoop() {
        receiveLoopTask?.cancel()
        receiveLoopTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    private func receiveLoop() async {
        while !Task.isCancelled, let task = webSocket {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    await MainActor.run { self.handleText(text) }
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await MainActor.run { self.handleText(text) }
                    }
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run { self.handleClose() }
                }
                return
            }
        }
    }

    private func handleText(_ text: String) {
        guard let data = text.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = raw["type"] as? String else {
            return
        }
        let envelope = WsEnvelope(
            type: type,
            payload: raw["payload"] as? [String: Any],
            timestamp: (raw["timestamp"] as? NSNumber)?.int64Value
        )
        dispatch(envelope)
    }

    private func handleClose() {
        stopHeartbeat()
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        webSocket = nil
        connectionState = .disconnected
        guard !autoReconnectDisabled, reconnectAttempts < maxReconnectAttempts, matchId != nil else { return }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard connectionState != .reconnecting else { return }
        connectionState = .reconnecting
        reconnectAttempts += 1
        let delayMs = Int64(1000 * pow(2, Double(reconnectAttempts - 1)))
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if self.autoReconnectDisabled || self.matchId == nil {
                    self.connectionState = .disconnected
                    return
                }
                self.openSocket()
            }
        }
    }

    private func flushQueue() {
        let queue = pendingQueue
        pendingQueue.removeAll()
        queue.forEach(sendEnvelope)
    }

    // MARK: 事件订阅

    @discardableResult
    func on(_ type: WsMessageType, _ handler: @escaping (WsEnvelope) -> Void) -> UUID {
        let id = UUID()
        handlers[type, default: []].append((id, handler))
        return id
    }

    func off(_ type: WsMessageType, id: UUID) {
        handlers[type]?.removeAll { $0.0 == id }
    }

    private func dispatch(_ envelope: WsEnvelope) {
        guard let type = WsMessageType(rawValue: envelope.type) else { return }
        if type == .participantUpdate && isOwnMessage(envelope) { return }
        if type == .sessionEnded || type == .connectionReplaced {
            autoReconnectDisabled = true
        }
        if type == .forceReconnect {
            forceReconnectFromServer()
            return
        }
        handlers[type]?.forEach { $0.1(envelope) }
    }

    private func forceReconnectFromServer() {
        guard matchId != nil, token != nil, wsUrl != nil else { return }
        stopHeartbeat()
        receiveLoopTask?.cancel()
        // 对齐安卓 close(1012, "server requested reconnect")；系统枚举未提供 1012。
        let serviceRestart = URLSessionWebSocketTask.CloseCode(rawValue: 1012) ?? .goingAway
        webSocket?.cancel(with: serviceRestart, reason: "server requested reconnect".data(using: .utf8))
        webSocket = nil
        connectionState = .reconnecting
        openSocket()
    }

    // MARK: 发送

    func sendJoin() {
        guard let matchId else { return }
        var payload: [String: Any] = ["matchId": matchId]
        if isDisplayMode {
            payload["displayInfo"] = currentDisplayDeviceInfo()
        }
        send(.join, payload)
    }

    func sendParticipantUpdate(participants: [[String: Any]], sessionPhase: String = "active", replace: Bool = false) {
        guard let matchId else { return }
        let envelope = WsEnvelope(
            type: WsMessageType.participantUpdate.rawValue,
            payload: [
                "matchId": matchId,
                "sessionPhase": sessionPhase,
                "replace": replace,
                "participants": participants
            ],
            timestamp: DisplayStateWireCodec.currentWallClockMs()
        )
        recordSentMessage(fingerprint(envelope))
        sendEnvelope(envelope)
    }

    func sendGameOver(winner: String, finalScores: [String: Any], manualEnd: Bool) {
        guard let matchId else { return }
        send(.gameOver, [
            "matchId": matchId,
            "winner": winner,
            "finalScores": finalScores,
            "manualEnd": manualEnd
        ])
    }

    func sendLeave(reason: String = "user_exit") {
        guard let matchId, isConnected else { return }
        send(.leave, ["matchId": matchId, "reason": reason])
    }

    func sendControllerAway(reason: String = "scoreboard_detached") {
        guard let matchId else { return }
        send(.controllerAway, ["matchId": matchId, "reason": reason])
    }

    func sendControllerResume(reason: String = "scoreboard_attached") {
        guard let matchId else { return }
        send(.controllerResume, ["matchId": matchId, "reason": reason])
    }

    func sendMatchStarted(gameType: String) {
        guard let matchId else { return }
        send(.matchStarted, ["matchId": matchId, "gameType": gameType])
    }

    private func send(_ type: WsMessageType, _ payload: [String: Any]) {
        sendEnvelope(WsEnvelope(
            type: type.rawValue,
            payload: payload,
            timestamp: DisplayStateWireCodec.currentWallClockMs()
        ))
    }

    private func sendEnvelope(_ envelope: WsEnvelope) {
        guard isConnected, let webSocket else {
            enqueuePending(envelope)
            return
        }
        var wire: [String: Any] = ["type": envelope.type]
        if let payload = envelope.payload { wire["payload"] = payload }
        if let timestamp = envelope.timestamp { wire["timestamp"] = timestamp }
        guard JSONSerialization.isValidJSONObject(wire),
              let data = try? JSONSerialization.data(withJSONObject: wire),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        webSocket.send(.string(text)) { [weak self] error in
            if error != nil {
                Task { @MainActor [weak self] in self?.enqueuePending(envelope) }
            }
        }
    }

    /// PARTICIPANT_UPDATE 是全量快照，离线队列只保留最新一帧。
    private func enqueuePending(_ envelope: WsEnvelope) {
        guard WsMessageType(rawValue: envelope.type) == .participantUpdate else { return }
        pendingQueue.removeAll { WsMessageType(rawValue: $0.type) == .participantUpdate }
        pendingQueue.append(envelope)
    }

    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isConnected else { return }
                self.send(.ping, [:])
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: 回声过滤

    private func fingerprint(_ envelope: WsEnvelope) -> String {
        let summary = ((envelope.payload?["participants"] as? [[String: Any]]) ?? []).map { participant in
            "\(participant["id"] ?? ""):\(participant["score"] ?? 0):\(participant["sets"] ?? ""):\(participant["games"] ?? "")"
        }.joined(separator: "|")
        return "\(envelope.timestamp ?? 0)_\(summary)"
    }

    private func recordSentMessage(_ fingerprint: String) {
        sentUpdateFingerprints.append(fingerprint)
        if sentUpdateFingerprints.count > maxSentMessagesCache {
            sentUpdateFingerprints.removeFirst(sentUpdateFingerprints.count - maxSentMessagesCache)
        }
    }

    private func isOwnMessage(_ envelope: WsEnvelope) -> Bool {
        let fingerprint = self.fingerprint(envelope)
        if let index = sentUpdateFingerprints.firstIndex(of: fingerprint) {
            sentUpdateFingerprints.remove(at: index)
            return true
        }
        return false
    }
}

/// 显示端设备信息（JOIN 时上报，对齐安卓 DisplayDeviceInfo）。
private func currentDisplayDeviceInfo() -> [String: Any] {
    let device = UIDevice.current
    let isPad = device.userInterfaceIdiom == .pad
    return [
        "name": String(device.name.prefix(32)),
        "platform": "IOS",
        "deviceType": isPad ? "TABLET" : "PHONE"
    ]
}
