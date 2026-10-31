import Combine
import Foundation
import SwiftUI
import UIKit

enum ScoreboardDisplayPublishPriority {
    case normal
    case urgent
}

enum ScoreboardDisplayPresentationMode: Equatable {
    case waiting
    case live
    case finished
}

@MainActor
final class ScoreboardDisplayOutputs: ObservableObject {
    static let shared = ScoreboardDisplayOutputs()

    @Published private(set) var displayState: ScoreboardDisplayState?
    @Published private(set) var presentationMode: ScoreboardDisplayPresentationMode = .waiting
    @Published private(set) var controllerAway = false
    /// 本地投屏当前屏的锚点玩家（完整名单里的全局下标）。
    ///
    /// 对齐安卓 `DisplaySurfaceBuildOptions.localMultiScoreAnchorPlayer`：它只在本进程内
    /// 从手机端分页控件流向独立大屏视图，不进入 `ScoreboardDisplayState`、wire 协议、
    /// 偏好或战绩；大屏仍按完整名单里同一个玩家 ID 取名字、分数与配色。
    @Published private(set) var localMultiScoreAnchorPlayer = 0

    private var ownerID: String?
    private var leaseID: UInt64 = 0
    private var nextLeaseID: UInt64 = 1
    private var pendingState: ScoreboardDisplayState?
    private var publishScheduled = false

    private init() {}

    @discardableResult
    func bind(ownerID: String, initial state: ScoreboardDisplayState) -> UInt64 {
        let lease = nextLeaseID
        nextLeaseID &+= 1
        self.ownerID = ownerID
        leaseID = lease
        pendingState = nil
        publishScheduled = false
        apply(state)
        return lease
    }

    func publish(
        ownerID: String,
        leaseID: UInt64,
        state: ScoreboardDisplayState,
        priority: ScoreboardDisplayPublishPriority = .normal
    ) {
        guard self.ownerID == ownerID, self.leaseID == leaseID else { return }
        if priority == .urgent {
            pendingState = nil
            apply(state)
            return
        }
        pendingState = state
        guard !publishScheduled else { return }
        publishScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.publishScheduled = false
            guard self.ownerID == ownerID,
                  self.leaseID == leaseID,
                  let pendingState = self.pendingState else { return }
            self.pendingState = nil
            self.apply(pendingState)
        }
    }

    func finish(ownerID: String, leaseID: UInt64, state: ScoreboardDisplayState) {
        publish(ownerID: ownerID, leaseID: leaseID, state: state, priority: .urgent)
    }

    func release(ownerID: String, leaseID: UInt64) {
        guard self.ownerID == ownerID, self.leaseID == leaseID else { return }
        self.ownerID = nil
        displayState = nil
        pendingState = nil
        presentationMode = .waiting
    }

    func setControllerAway(_ away: Bool) {
        controllerAway = away
    }

    /// 手机端分页控件切换大屏当前屏。这里保留原始锚点，越界由分页模型按名单长度夹取，
    /// 因此重连、旋转、窗口重建都不会丢失或裁剪当前屏。
    func setLocalMultiScoreAnchorPlayer(_ anchorPlayer: Int) {
        let clamped = max(0, anchorPlayer)
        guard clamped != localMultiScoreAnchorPlayer else { return }
        localMultiScoreAnchorPlayer = clamped
    }

    private func apply(_ state: ScoreboardDisplayState) {
        displayState = state
        presentationMode = state.result?.ended == true ? .finished : .live
    }
}

enum ExternalDisplayStatus: String, Equatable {
    case disconnected
    case mirroring
    case dedicated
}

@MainActor
final class ExternalDisplayCoordinator: ObservableObject {
    static let shared = ExternalDisplayCoordinator()

    @Published private(set) var status: ExternalDisplayStatus = .disconnected
    private var dedicatedSceneCount = 0
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIScreen.didConnectNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in self?.refreshStatus() }
        })
        observers.append(center.addObserver(
            forName: UIScreen.didDisconnectNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in self?.refreshStatus() }
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func externalSceneConnected() {
        dedicatedSceneCount += 1
        updateStatus(.dedicated)
    }

    func externalSceneDisconnected() {
        dedicatedSceneCount = max(0, dedicatedSceneCount - 1)
        DispatchQueue.main.async { [weak self] in self?.refreshStatus() }
    }

    func refreshStatus() {
        if dedicatedSceneCount > 0 {
            updateStatus(.dedicated)
            return
        }
        let isMirroring = UIScreen.screens.dropFirst().contains { $0.mirrored != nil }
        updateStatus(isMirroring ? .mirroring : .disconnected)
    }

    private func updateStatus(_ next: ExternalDisplayStatus) {
        guard status != next else { return }
        let previous = status
        status = next
        let action = next == .disconnected
            ? "stop"
            : (previous == .disconnected ? "connect" : "mode_change")
        AppAnalytics.trackCastAction(action, result: .success, outcome: next.rawValue)
    }
}

private struct ScoreboardExternalDisplayModifier: ViewModifier {
    let ownerID: String
    let state: ScoreboardDisplayState
    @State private var leaseID: UInt64?

    func body(content: Content) -> some View {
        content
            .onAppear {
                leaseID = ScoreboardDisplayOutputs.shared.bind(ownerID: ownerID, initial: state)
            }
            .onChange(of: state) { _, next in
                guard let leaseID else { return }
                ScoreboardDisplayOutputs.shared.publish(
                    ownerID: ownerID,
                    leaseID: leaseID,
                    state: next,
                    priority: next.result?.ended == true ? .urgent : .normal
                )
            }
            .onDisappear {
                guard let leaseID else { return }
                ScoreboardDisplayOutputs.shared.release(ownerID: ownerID, leaseID: leaseID)
                self.leaseID = nil
            }
    }
}

extension View {
    func scoreboardExternalDisplay(ownerID: String, state: ScoreboardDisplayState) -> some View {
        modifier(ScoreboardExternalDisplayModifier(ownerID: ownerID, state: state))
    }
}
