import SwiftUI

// MARK: - 显示端全屏页（对齐安卓 RemoteDisplayScreen）

/// 显示端（加入观看）全屏渲染页：连接中 / 等待 / 直播 / 结束 / 错误 五态。
/// 行为对齐安卓：屏幕常亮、点屏唤出返回按钮（3 秒自动隐藏）、
/// 返回按钮 3 秒内双击退出（长按直接退出）。
struct RemoteDisplayView: View {
    @ObservedObject var session: RemoteDisplaySession

    @State private var backVisible = false
    @State private var backRevealRevision = 0
    @State private var lastExitTapAt: Date?
    @State private var toastMessage: String?
    @Environment(\.dismiss) private var dismiss

    /// 与安卓 REMOTE_DISPLAY_EXIT_DOUBLE_TAP_MS 一致。
    private static let exitDoubleTapWindowMs: Int64 = 3000
    private static let backButtonAutoHideMs: UInt64 = 3000

    var body: some View {
        ZStack {
            Color(hex: "071017").ignoresSafeArea()

            content

            if session.controllerStatus == .away, session.displayState != nil {
                controllerAwayOverlay
            }

            if session.controllerStatus == .disconnected {
                controllerDisconnectedOverlay
            }

            floatingBackButton
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        // 对齐安卓 RemoteDisplayHost：整页锁定方向（等待/连接/直播/结束均如此），
        // 手机默认横屏（OrientationPolicy.resolveScoreboardOrientation），
        // iPad 无强制横屏偏好时跟随设备；推分状态携带 orientation 时按其锁定。
        .lockOrientation(displayOrientationMask)
        .onChange(of: session.displayState?.orientation) { _, _ in
            applyDisplayOrientationPolicy()
        }
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .persistentSystemOverlays(.hidden)
        .contentShape(Rectangle())
        .onTapGesture { revealBackButton() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            // 兜底：非按钮退出路径（如父级 pop）也要断开连接并注销监听。
            session.stop()
        }
        .overlay {
            if let toastMessage {
                ToastView(message: toastMessage)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: 方向

    private var displayOrientationMask: UIInterfaceOrientationMask {
        if let orientation = session.displayState?.orientation {
            return orientationMask(for: orientation)
        }
        // 无推分状态时：手机默认横屏；iPad 由 lockOrientation 按偏好决定是否跟随设备。
        return .landscape
    }

    private func orientationMask(for orientation: ScoreboardDisplayOrientation) -> UIInterfaceOrientationMask {
        switch orientation {
        case .landscape: return .landscape
        case .portrait: return .portrait
        }
    }

    private func applyDisplayOrientationPolicy() {
        if Theme.usesPadLayout,
           !PreferencesManager.shared.forceIPadLandscape {
            OrientationLock.shared.unlock()
        } else {
            OrientationLock.shared.lock(displayOrientationMask)
        }
    }

    // MARK: 内容态

    @ViewBuilder
    private var content: some View {
        switch session.mode {
        case .live, .finished:
            if let state = session.displayState {
                ScoreboardExternalLiveView(state: state, projection: .synchronizedDisplay, onExit: exitImmediately)
                    .id("\(state.gameType)-\(state.layoutKind.rawValue)")
                    .transition(.opacity)
            } else {
                waitingPanel
            }
        case .connecting:
            ProgressView()
                .tint(.white)
                .scaleEffect(1.4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error:
            errorPanel
        case .waiting:
            waitingPanel
        }
    }

    /// 等待/无内容态：App 图标 + 横排翻页时钟 + 等待文案（对齐安卓 DisplayIdleWaitingPanel）。
    private var waitingPanel: some View {
        let isLargeDisplay = Theme.usesPadLayout
        return GeometryReader { proxy in
            let baseCardWidth: CGFloat = isLargeDisplay ? 140 : 72
            let digitPairGap: CGFloat = isLargeDisplay ? 6 : 4
            let groupGap: CGFloat = isLargeDisplay ? 28 : 16
            let horizontalPadding: CGFloat = isLargeDisplay ? 64 : 32
            let minCardWidth: CGFloat = isLargeDisplay ? 96 : 44
            let availableWidth = max(proxy.size.width - horizontalPadding, 1)
            let fixedGapWidth = digitPairGap * 3 + groupGap * 2
            let fittedCardWidth = max((availableWidth - fixedGapWidth) / 6, minCardWidth)
            let cardWidth = min(baseCardWidth, fittedCardWidth)
            let cardHeight = cardWidth * 1.5

            VStack(spacing: isLargeDisplay ? 32 : 24) {
                Image("AppLogo")
                    .resizable()
                    .frame(width: isLargeDisplay ? 72 : 48, height: isLargeDisplay ? 72 : 48)
                    .clipShape(RoundedRectangle(
                        cornerRadius: isLargeDisplay ? 17 : 12,
                        style: .continuous
                    ))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    FlipClockFace(
                        date: context.date,
                        cardWidth: cardWidth,
                        cardHeight: cardHeight,
                        digitGap: digitPairGap,
                        groupGap: groupGap,
                        showShadow: false,
                        hideCenterSeam: true
                    )
                }
                if session.controllerStatus != .disconnected {
                    Text(NSLocalizedString("sync_display_waiting_title", value: "等待分享端推分", comment: ""))
                        .font(.system(size: isLargeDisplay ? 20 : 18, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 32)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var errorPanel: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white.opacity(0.72))
            Text(session.errorMessage ?? NSLocalizedString(
                "sync_display_error_generic",
                value: "连接已断开",
                comment: ""
            ))
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)

            Button {
                exitImmediately()
            } label: {
                Text(NSLocalizedString("sync_display_exit", value: "退出显示端", comment: ""))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 160, height: 48)
            }
            .background(.white.opacity(0.14), in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 遮罩

    // 对齐安卓 RemoteDisplayAwayPill：右上角小胶囊（黑 46% + 琥珀圆点），避免遮挡比赛信息。
    private var controllerAwayOverlay: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 7) {
                    Circle()
                        .fill(Color(hex: "FFC44D").opacity(0.68))
                        .frame(width: 6, height: 6)
                    Text(NSLocalizedString("cast_controller_away", value: "控制端暂离", comment: ""))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 16)
                .padding(.trailing, 16)
            }
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var controllerDisconnectedOverlay: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.white.opacity(0.8))
                Text(NSLocalizedString(
                    "sync_display_disconnected_title",
                    value: "与分享端的连接已断开",
                    comment: ""
                ))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                Text(NSLocalizedString(
                    "sync_display_disconnected_message",
                    value: "正在尝试自动重连，你也可以退出显示端",
                    comment: ""
                ))
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.68))

                Button {
                    exitImmediately()
                } label: {
                    Text(NSLocalizedString("sync_display_exit", value: "退出显示端", comment: ""))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 160, height: 48)
                }
                .background(.white.opacity(0.14), in: Capsule())
            }
            .padding(24)
        }
    }

    // MARK: 悬浮返回按钮

    /// 对齐安卓 shouldShowRemoteDisplayBackButton：结束态 / 断开遮罩已有退出入口时隐藏。
    private var shouldShowBackButton: Bool {
        session.mode != .finished &&
            session.controllerStatus != .disconnected &&
            session.mode != .error &&
            backVisible
    }

    private var floatingBackButton: some View {
        VStack {
            Spacer()
            HStack {
                if shouldShowBackButton {
                    Button(action: handleExitTap) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                    .simultaneousGesture(LongPressGesture().onEnded { _ in
                        exitImmediately()
                    })
                    .transition(.opacity)
                }
                Spacer()
            }
            .padding(.leading, 20)
            .padding(.bottom, 20)
        }
        .animation(.easeInOut(duration: 0.2), value: shouldShowBackButton)
    }

    private func revealBackButton() {
        guard session.mode != .finished,
              session.controllerStatus != .disconnected,
              session.mode != .error else { return }
        backVisible = true
        backRevealRevision += 1
        scheduleBackHide()
    }

    private func scheduleBackHide() {
        let revision = backRevealRevision
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.backButtonAutoHideMs * 1_000_000)
            guard revision == backRevealRevision else { return }
            backVisible = false
        }
    }

    // MARK: 退出

    private func handleExitTap() {
        let now = Date()
        if let lastExitTapAt,
           now.timeIntervalSince(lastExitTapAt) <= Double(Self.exitDoubleTapWindowMs) / 1000 {
            exitImmediately()
        } else {
            lastExitTapAt = now
            showToast(NSLocalizedString("scoreboard_tap_exit_again", value: "再点一次退出", comment: ""))
        }
    }

    private func exitImmediately() {
        session.stop()
        dismiss()
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            toastMessage = nil
        }
    }
}
