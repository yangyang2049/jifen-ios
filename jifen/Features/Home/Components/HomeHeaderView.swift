import SwiftUI

struct HomeHeaderView: View {
    let headerDate: String
    /// 首页水平边距（由 HomeTab 按窗口尺寸传入；iPad 平板档为 64，对齐安卓 responsiveHorizontalPadding）。
    var horizontalInset: CGFloat = Theme.pageHorizontalInset
    var onCastTapped: () -> Void = {}
    @ObservedObject private var externalDisplay = ExternalDisplayCoordinator.shared
    @ObservedObject private var cloudSyncSession = CloudSyncSession.shared

    var body: some View {
        if let sharingState = activeSharingState {
            // 对齐安卓 HomeHeader：发起方同步中时，顶栏整体替换为绿色同步条。
            HomeSharingActiveHeaderView(
                sharingState: sharingState,
                horizontalInset: horizontalInset,
                onRetryShortCode: {
                    Task { await cloudSyncSession.controller?.retryShortCode() }
                },
                onNavigateToSync: onCastTapped
            )
        } else {
            normalHeader
        }
    }

    /// 当前为跨设备同步发起方且正在分享（对齐安卓 currentSession != null && sharingState.isSharing）。
    private var activeSharingState: RemoteSyncController.SharingState? {
        guard let state = cloudSyncSession.state, state.controller.state.isSharing else { return nil }
        return state.controller.state
    }

    private var normalHeader: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(NSLocalizedString("app_name", comment: "App Name"))
                    .font(.system(size: Theme.fontH4, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                    .padding(.bottom, 2)
                    .lineLimit(1)

                Text(headerDate)
                    .font(.system(size: Theme.fontCaption, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer()

            Button(action: onCastTapped) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 13, weight: .semibold))
                    Text(externalDisplay.status == .dedicated
                         ? NSLocalizedString("cast_active", value: "投屏中", comment: "")
                         : NSLocalizedString("home_sync_entry", value: "投屏与同步", comment: ""))
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(externalDisplay.status == .dedicated ? Color.white : Theme.primary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    externalDisplay.status == .dedicated
                        ? Theme.primary
                        : Theme.primary.opacity(0.12),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home_cast_button")
            .accessibilityLabel(NSLocalizedString("home_sync_entry", value: "投屏与同步", comment: ""))
        }
        // 水平内边距移入正常顶栏内部：同步态绿色条需要全宽贴边（对齐安卓 activeModifier）。
        .padding(.horizontal, horizontalInset)
        .padding(.top, Theme.md)
        .padding(.bottom, Theme.sm)
        .frame(maxWidth: .infinity)
        .background(Theme.backgroundColor)
    }
}

// MARK: - 同步中绿色顶栏（对齐安卓 HomeSharingActiveHeader）

struct HomeSharingActiveHeaderView: View {
    let sharingState: RemoteSyncController.SharingState
    var horizontalInset: CGFloat = Theme.pageHorizontalInset
    var onRetryShortCode: () -> Void
    var onNavigateToSync: () -> Void

    @State private var toastMessage: String?
    @State private var toastDismissTask: Task<Void, Never>?

    private var spacedCode: String {
        sharingState.shortCode.filter { $0.isNumber }.map(String.init).joined(separator: " ")
    }

    var body: some View {
        HStack(spacing: 12) {
            // 对齐安卓 Column(Modifier.weight(1f))：左列占满剩余宽度保持左对齐，
            // 右侧箭头按钮被推到最右（避免整体内容被居中）。
            leadingColumn
                .frame(maxWidth: .infinity, alignment: .leading)
            manageButton
        }
        // 对齐安卓：背景先于 contentPadding，绿条全宽贴边，内容由水平内边距承担。
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, 2)
        .frame(height: 84)
        .frame(maxWidth: .infinity)
        .background(Theme.primary)
        .overlay(alignment: .bottom) {
            if let toastMessage {
                ToastView(message: toastMessage)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toastMessage)
    }

    // MARK: 左侧信息列（状态行 + 短码/错误态）

    private var leadingColumn: some View {
        Button(action: onNavigateToSync) {
            VStack(alignment: .leading, spacing: 4) {
                statusRow

                if !spacedCode.isEmpty {
                    codeRow
                        .padding(.top, 4)
                } else if sharingState.shortCodeError {
                    errorContent
                        .padding(.top, 4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.white)
                .frame(width: 5, height: 5)

            Text(NSLocalizedString("home_sync_sharing", value: "同步比分中", comment: ""))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(1)

            if !sharingState.connectedDisplays.isEmpty {
                Rectangle()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 1, height: 12)

                Text(connectedDevicesText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.95))
                    .lineLimit(1)
            }
        }
    }

    private var connectedDevicesText: String {
        let displays = sharingState.connectedDisplays
        if displays.count == 1 {
            return String(
                format: NSLocalizedString("home_sync_connected_device", value: "%@ 已连接", comment: ""),
                displays[0].name
            )
        }
        return String(
            format: NSLocalizedString("home_sync_connected_devices", value: "%d 台设备已连接", comment: ""),
            displays.count
        )
    }

    // MARK: 短码行（大号间隔数字 + 复制按钮）

    private var codeRow: some View {
        HStack(spacing: 8) {
            Text(spacedCode)
                .font(.system(size: 24, weight: .bold))
                .tracking(2)
                .foregroundColor(.white)
                .lineLimit(1)

            Button {
                UIPasteboard.general.string = sharingState.shortCode
                showToast(NSLocalizedString("sync_code_copied", value: "已复制短码", comment: ""))
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("home_sync_copy", value: "复制", comment: ""))
        }
    }

    // MARK: 短码生成失败态

    private var errorContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(NSLocalizedString("sync_shortcode_create_failed", value: "短码生成失败，请点击下方按钮重试", comment: ""))
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.95))
                .lineLimit(1)

            Button(action: onRetryShortCode) {
                Text(NSLocalizedString("sync_retry_shortcode", value: "重新生成短码", comment: ""))
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 右侧管理入口

    private var manageButton: some View {
        Button(action: onNavigateToSync) {
            Image(systemName: "chevron.forward")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.95))
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.16), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString("sync_manage", value: "管理", comment: ""))
    }

    /// 连续触发时取消上一个清除定时器，避免旧定时器提前清掉新 toast。
    private func showToast(_ message: String) {
        toastMessage = message
        toastDismissTask?.cancel()
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            toastMessage = nil
        }
    }
}
