import Foundation
import Combine
import UIKit

/// 全局云端同步会话：创建房间后常驻，记分页 attach 推分，退出记分页回到 SHARING。
/// 对齐安卓 CloudSyncSession（SHARING / IN_GAME 两相 + 空闲自动结束）。
@MainActor
final class CloudSyncSession: ObservableObject {
    enum Phase: String {
        case sharing
        case inGame
    }

    struct State {
        var phase: Phase
        var gameType: String
        var controller: RemoteSyncController
    }

    static let shared = CloudSyncSession()

    private static let sharingIdleTimeoutMs: Int64 = 5 * 60 * 1000
    private static let detachedIdleTimeoutMs: Int64 = 10 * 60 * 1000
    private static let idleTimeoutReason = "scoreboard_idle_timeout"

    @Published private(set) var state: State?

    private var idleTask: Task<Void, Never>?
    private var controllerCancellable: AnyCancellable?
    private var ending = false

    private init() {}

    var isActive: Bool { state != nil }

    /// 当前会话的分享端控制器（未开房时为 nil）。
    var controller: RemoteSyncController? { state?.controller }

    func isSharingActive() -> Bool {
        state?.controller.state.isSharing == true
    }

    func isSessionController(_ controller: RemoteSyncController) -> Bool {
        state?.controller === controller
    }

    func canAttach(gameType: String) -> Bool {
        guard isSharingActive() else { return false }
        return CloudSyncGameTypes.isSupported(gameType)
    }

    // MARK: 会话生命周期

    /// 创建新会话；若已有旧会话则先强制结束（对齐安卓 CloudSyncSession.create）。
    func create(gameType: String = CloudSyncGameTypes.placeholder) {
        if let oldSession = state {
            oldSession.controller.forceDisconnect(
                sendLeave: true,
                reason: "replaced_by_new_cloud_sync_session"
            )
        }
        clearIdleTimer()
        ending = false
        let controller = RemoteSyncController()
        state = State(phase: .sharing, gameType: gameType, controller: controller)
        // 转发 controller 的状态变更，保证观察 session 的视图实时刷新。
        controllerCancellable = controller.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        controller.setSnapshotRequestListener { [weak self] in
            self?.requestFreshSnapshot()
        }
        scheduleIdleEnd(Self.sharingIdleTimeoutMs)
    }

    func bindGameType(_ gameType: String) {
        guard var session = state else { return }
        session.gameType = gameType
        state = session
        if session.phase == .inGame {
            session.controller.sendMatchStarted(gameType: gameType)
        }
    }

    /// 记分页进入前台推分（对齐安卓 markInGame）。
    func markInGame(gameType: String) {
        guard var session = state, session.controller.state.isSharing else { return }
        let wasInGame = session.phase == .inGame
        clearIdleTimer()
        let shouldBind = session.gameType != gameType
        session.phase = .inGame
        if shouldBind {
            session.gameType = gameType
        }
        state = session
        if wasInGame {
            if shouldBind {
                session.controller.sendMatchStarted(gameType: gameType)
            }
        } else {
            session.controller.sendControllerResume()
            if gameType != CloudSyncGameTypes.placeholder {
                session.controller.sendMatchStarted(gameType: gameType)
            }
        }
        requestFreshSnapshot()
    }

    /// 记分页退出，回到 SHARING（对齐安卓 markSharing）。
    func markSharing() {
        guard var session = state else { return }
        let wasInGame = session.phase == .inGame
        if wasInGame {
            session.controller.sendControllerAway()
        }
        session.phase = .sharing
        session.gameType = CloudSyncGameTypes.placeholder
        state = session
        scheduleIdleEnd(wasInGame ? Self.detachedIdleTimeoutMs : Self.sharingIdleTimeoutMs)
    }

    /// 记分板推分入口（由 LocalScoreboardSyncCoordinator 调用）。
    func publish(_ displayState: ScoreboardDisplayState?) {
        guard let session = state,
              session.phase == .inGame,
              session.controller.state.isSharing,
              CloudSyncGameTypes.isSupported(displayState?.gameType ?? ""),
              let displayState else {
            return
        }
        session.controller.publishDisplayState(displayState)
    }

    func end(reason: String = "user_exit") {
        guard let session = state, !ending else { return }
        ending = true
        clearIdleTimer()
        session.controller.forceDisconnect(sendLeave: true, reason: reason)
        state = nil
        ending = false
    }

    /// 服务端 SESSION_ENDED：不再发送 LEAVE，仅清理本地会话。
    func endFromServer() {
        guard let session = state else { return }
        clearIdleTimer()
        session.controller.forceDisconnect(sendLeave: false)
        state = nil
    }

    // MARK: 空闲计时

    private func scheduleIdleEnd(_ timeoutMs: Int64) {
        clearIdleTimer()
        guard state != nil, timeoutMs > 0 else { return }
        // App 退后台后 Task 自动挂起，计时自然暂停，回到前台继续。
        idleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.idleTask = nil
            self.end(reason: Self.idleTimeoutReason)
        }
    }

    private func clearIdleTimer(keepRemaining: Bool = false) {
        idleTask?.cancel()
        idleTask = nil
    }

    /// 请求重新推一帧当前快照（显示端加入 / 强制同步时）。
    private func requestFreshSnapshot() {
        LocalScoreboardSyncCoordinator.shared.publishSnapshot()
    }
}
