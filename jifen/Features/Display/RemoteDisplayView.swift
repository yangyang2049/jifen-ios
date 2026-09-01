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

    // MARK: 内容态

    @ViewBuilder
    private var content: some View {
        switch session.mode {
        case .live, .finished:
            if let state = session.displayState {
                ScoreboardExternalLiveView(state: state)
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

    private var waitingPanel: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            GeometryReader { proxy in
                let scale = max(0.85, min(1.8, proxy.size.width / 1280))
                VStack(spacing: 18 * scale) {
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: 74 * scale, weight: .light))
                        .foregroundStyle(Color(hex: "30D158"))
                    Text(NSLocalizedString("sync_display_waiting_title", value: "等待分享端推分", comment: ""))
                        .font(.system(size: 42 * scale, weight: .bold))
                    Text(NSLocalizedString(
                        "sync_display_waiting_message",
                        value: "请在另一台设备打开计分板并开始记分",
                        comment: ""
                    ))
                    .font(.system(size: 24 * scale, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                    VStack(spacing: 2) {
                        Text(context.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 58 * scale, weight: .medium, design: .monospaced))
                        Text(context.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 20 * scale, weight: .medium))
                            .foregroundStyle(.white.opacity(0.54))
                    }
                    .padding(.top, 18 * scale)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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

    private var controllerAwayOverlay: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "iphone.slash")
                Text(NSLocalizedString("cast_controller_away", value: "控制端暂离", comment: ""))
                    .fontWeight(.semibold)
            }
            .font(.system(size: 24))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(.black.opacity(0.72), in: Capsule())
            .padding(.top, 24)
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
