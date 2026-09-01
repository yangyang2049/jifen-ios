import SwiftUI

// MARK: - 跨设备同步入口面板（对齐安卓 RemoteSyncEntryPanel）

/// 「跨设备同步」Tab 内容：说明卡 + 分享端 / 显示端手风琴卡片。
struct CloudSyncEntryPanel: View {
    @ObservedObject private var session = CloudSyncSession.shared
    @State private var expandedRole: Role = .viewer
    @State private var codeInput = ""
    @State private var joinError: String?
    @State private var joining = false
    @State private var creatingRoom = false
    @State private var showLoginSheet = false
    @State private var pendingAction: PendingAction?
    @State private var joinedSession: RemoteDisplaySession?
    @State private var toastMessage: String?
    @State private var showEndConfirm = false

    enum Role {
        case scorer, viewer
    }

    enum PendingAction {
        case createRoom
        case joinDisplay(String)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                CloudSyncIntroCard()

                scorerCard

                if session.isActive {
                    Text(NSLocalizedString(
                        "sync_display_unavailable_hint",
                        value: "当前正在分享比分，结束分享后才能加入其他比赛。",
                        comment: ""
                    ))
                    .font(.system(size: 12))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.homeNeutralCardTextTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                } else {
                    viewerCard
                }
            }
            .padding(.horizontal, Theme.pageHorizontalInset)
            .padding(.top, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: Theme.secondaryPageContentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            if session.isActive { expandedRole = .scorer }
        }
        .sheet(isPresented: $showLoginSheet, onDismiss: consumePendingAction) {
            AccountLoginSheet()
        }
        .navigationDestination(isPresented: Binding(
            get: { joinedSession != nil },
            set: { if !$0 { joinedSession = nil } }
        )) {
            if let joinedSession {
                RemoteDisplayView(session: joinedSession)
            }
        }
        .overlay {
            if showEndConfirm {
                CloudSyncEndConfirmDialog(
                    onCancel: { showEndConfirm = false },
                    onConfirm: {
                        showEndConfirm = false
                        CloudSyncSession.shared.end()
                        showToast(NSLocalizedString("scoreboard_sharing_ended", value: "已结束同步", comment: ""))
                    }
                )
            }
        }
        .overlay {
            if let toastMessage {
                ToastView(message: toastMessage)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showEndConfirm)
    }

    private var isSharingActive: Bool { session.isActive && session.controller?.state.isSharing == true }

    // MARK: 分享端卡片

    private var scorerCard: some View {
        CloudSyncRoleCard(
            icon: "square.and.arrow.up",
            title: NSLocalizedString("sync_role_scorer_title", value: "开始同步比分", comment: ""),
            subtitle: isSharingActive
                ? NSLocalizedString("sync_status_active", value: "同步比分中", comment: "")
                : NSLocalizedString("sync_role_scorer_desc", value: "在本机记分，生成 6 位短码", comment: ""),
            expanded: expandedRole == .scorer || isSharingActive,
            collapsible: !isSharingActive,
            onToggle: {
                guard !isSharingActive else { return }
                expandedRole = expandedRole == .scorer ? .viewer : .scorer
            }
        ) {
            if isSharingActive {
                sharingActiveContent
            } else {
                createRoomButton
            }
        }
    }

    @ViewBuilder
    private var sharingActiveContent: some View {
        let sharingState = session.controller?.state ?? RemoteSyncController.SharingState()

        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(connectionColor(sharingState.connectionState))
                    .frame(width: 10, height: 10)
                Text(connectionText(sharingState.connectionState))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity)

            if !sharingState.shortCode.isEmpty {
                Text(sharingState.shortCode.map(String.init).joined(separator: "  "))
                    .font(.system(size: 36, weight: .bold))
                    .kerning(4)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
            } else if sharingState.shortCodeError {
                Text(NSLocalizedString(
                    "sync_shortcode_create_failed",
                    value: "短码生成失败，请点击下方按钮重试",
                    comment: ""
                ))
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(Color(hex: "FF3B30"))
            }

            if !sharingState.connectedDisplays.isEmpty {
                VStack(spacing: 8) {
                    ForEach(sharingState.connectedDisplays, id: \.connectionId) { display in
                        ConnectedDisplayCard(display: display)
                    }
                }
            }

            if sharingState.shortCodeError {
                Button {
                    Task { await session.controller?.retryShortCode() }
                } label: {
                    Text(NSLocalizedString("sync_retry_shortcode", value: "重新生成短码", comment: ""))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.primary, lineWidth: 1)
                )
            } else {
                Text(NSLocalizedString(
                    "sync_sharing_start_via_home_hint",
                    value: "将此短码发给显示端设备即可开始同步；进入计分项目后比分会自动同步。",
                    comment: ""
                ))
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

                sharingActionButtons
            }
        }
    }

    private var sharingActionButtons: some View {
        HStack(spacing: 8) {
            outlineButton(
                title: NSLocalizedString("sync_copy_code", value: "复制短码", comment: ""),
                color: Color(hex: "22C55E"),
                enabled: !(session.controller?.state.shortCode.isEmpty ?? true)
            ) {
                UIPasteboard.general.string = session.controller?.state.shortCode ?? ""
                showToast(NSLocalizedString("sync_code_copied", value: "已复制短码", comment: ""))
            }

            outlineButton(
                title: NSLocalizedString("sync_end_sharing", value: "结束同步", comment: ""),
                color: Color(hex: "FF3B30")
            ) {
                showEndConfirm = true
            }
        }
    }

    private var createRoomButton: some View {
        Button {
            requireLogin(.createRoom) {
                Task { await createRoom() }
            }
        } label: {
            ZStack {
                if creatingRoom {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(SessionStore.shared.isAuthenticated
                        ? NSLocalizedString("sync_login_create_room", value: "生成同步码", comment: "")
                        : NSLocalizedString("sync_login_and_create_room", value: "登录并生成同步码", comment: ""))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .background(Theme.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .disabled(creatingRoom)
    }

    private func createRoom() async {
        if isSharingActive {
            expandedRole = .scorer
            return
        }
        creatingRoom = true
        defer { creatingRoom = false }
        CloudSyncSession.shared.create()
        guard let controller = CloudSyncSession.shared.controller else { return }
        let success = await controller.startSharing()
        if success {
            expandedRole = .scorer
        } else {
            CloudSyncSession.shared.end()
            showToast(controller.state.errorMessage
                ?? NSLocalizedString("sync_start_failed", value: "开始同步失败", comment: ""))
        }
    }

    // MARK: 显示端卡片

    private var viewerCard: some View {
        CloudSyncRoleCard(
            icon: "display",
            title: NSLocalizedString("sync_role_viewer_title", value: "加入同步比分", comment: ""),
            subtitle: NSLocalizedString("sync_role_viewer_desc", value: "输入分享端提供的 6 位短码", comment: ""),
            expanded: expandedRole == .viewer,
            collapsible: true,
            onToggle: {
                expandedRole = expandedRole == .viewer ? .scorer : .viewer
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString(
                    "sync_viewer_flow_hint",
                    value: "输入分享端提供的 6 位短码，登录后即可全屏显示比分。",
                    comment: ""
                ))
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                codeInputField

                if let joinError {
                    Text(joinError)
                        .font(.system(size: 12))
                        .lineSpacing(3)
                        .foregroundStyle(Color(hex: "FF3B30"))
                        .padding(.top, 2)
                }

                Button {
                    requireLogin(.joinDisplay(codeInput)) {
                        Task { await connectDisplay() }
                    }
                } label: {
                    ZStack {
                        if joining {
                            ProgressView().tint(.white)
                        } else {
                            Text(SessionStore.shared.isAuthenticated
                                ? NSLocalizedString("sync_login_join_display", value: "加入同步", comment: "")
                                : NSLocalizedString("sync_login_and_join_display", value: "登录并加入同步", comment: ""))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                }
                .background(Theme.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(joining || codeInput.count != 6)
                .opacity(codeInput.count == 6 || joining ? 1 : 0.5)
            }
        }
    }

    private var codeInputField: some View {
        TextField(
            "",
            text: Binding(
                get: { codeInput.map(String.init).joined(separator: " ") },
                set: { newValue in
                    joinError = nil
                    codeInput = newValue.filter(\.isNumber).prefix(6).map(String.init).joined()
                }
            ),
            prompt: Text(NSLocalizedString("sync_code_input_placeholder", value: "0 0 0 0 0 0", comment: ""))
                .foregroundStyle(Theme.homeNeutralCardTextTertiary)
        )
        .keyboardType(.numberPad)
        .multilineTextAlignment(.center)
        .font(.system(size: 20, weight: .medium))
        .foregroundStyle(Theme.textPrimary)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .padding(.horizontal, 16)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    joinError != nil ? Color(hex: "FF3B30") : Theme.homeNeutralCardTextTertiary.opacity(0.26),
                    lineWidth: 1
                )
        )
    }

    private func connectDisplay() async {
        guard !joining else { return }
        joining = true
        joinError = nil
        defer { joining = false }
        let displaySession = RemoteDisplaySession(code: codeInput)
        do {
            try await displaySession.connect()
            joinedSession = displaySession
        } catch {
            displaySession.stop()
            joinError = CloudSyncErrorMapper.joinFailureMessage(error)
        }
    }

    // MARK: 登录门槛

    private func requireLogin(_ action: PendingAction, proceed: @escaping () -> Void) {
        if SessionStore.shared.isAuthenticated {
            proceed()
        } else {
            pendingAction = action
            showLoginSheet = true
        }
    }

    private func consumePendingAction() {
        guard let pendingAction, SessionStore.shared.isAuthenticated else {
            pendingAction = nil
            return
        }
        self.pendingAction = nil
        switch pendingAction {
        case .createRoom:
            expandedRole = .scorer
            Task { await createRoom() }
        case .joinDisplay(let code):
            codeInput = code
            Task { await connectDisplay() }
        }
    }

    // MARK: 复用小组件

    private func outlineButton(title: String, color: Color, enabled: Bool = true,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(color, lineWidth: 1)
        )
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private func connectionColor(_ state: WsConnectionState) -> Color {
        switch state {
        case .connected: Color(hex: "22C55E")
        case .connecting, .reconnecting: Color(hex: "F59E0B")
        case .disconnected: Color(hex: "EF4444")
        }
    }

    private func connectionText(_ state: WsConnectionState) -> String {
        switch state {
        case .connected:
            NSLocalizedString("sync_connected_service", value: "已连接到同步服务", comment: "")
        case .connecting:
            NSLocalizedString("sync_connecting", value: "正在连接同步服务…", comment: "")
        case .reconnecting:
            NSLocalizedString("sync_reconnecting", value: "正在重新连接同步服务…", comment: "")
        case .disconnected:
            NSLocalizedString("sync_disconnected", value: "未连接到同步服务", comment: "")
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            toastMessage = nil
        }
    }
}

// MARK: - 已连接显示端卡片

private struct ConnectedDisplayCard: View {
    let display: WsDisplayPresence

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(display.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(NSLocalizedString("sync_connected_display_role", value: "跨设备显示端", comment: ""))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(NSLocalizedString("sync_connected_display_status", value: "已连接", comment: ""))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: "22C55E"))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - 说明卡（对齐安卓 SyncIntroSteps）

struct CloudSyncIntroCard: View {
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            } label: {
                HStack {
                    Text(NSLocalizedString("sync_intro_title", value: "同步比分怎么用", comment: ""))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        Text(NSLocalizedString(
                            expanded ? "sync_intro_collapse" : "sync_intro_expand",
                            value: expanded ? "收起" : "展开说明",
                            comment: ""
                        ))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.homeNeutralCardTextTertiary)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.homeNeutralCardTextTertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(NSLocalizedString(
                "sync_intro_overview",
                value: "两台设备配合使用：分享端负责记分，显示端全屏展示比分。",
                comment: ""
            ))
            .font(.system(size: 13))
            .lineSpacing(5)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    CloudSyncIntroSection(
                        heading: NSLocalizedString("sync_intro_share_heading", value: "分享端", comment: ""),
                        steps: [
                            NSLocalizedString("sync_intro_share_1", value: "登录并开始同步，生成 6 位短码", comment: ""),
                            NSLocalizedString("sync_intro_share_2", value: "把短码发给显示端", comment: ""),
                            NSLocalizedString("sync_intro_share_3", value: "进入计分项目开始记分，比分会自动同步", comment: "")
                        ]
                    )

                    Divider().foregroundStyle(Theme.divider)

                    CloudSyncIntroSection(
                        heading: NSLocalizedString("sync_intro_display_heading", value: "显示端", comment: ""),
                        steps: [
                            NSLocalizedString("sync_intro_display_1", value: "登录并输入分享端提供的 6 位短码", comment: ""),
                            NSLocalizedString("sync_intro_display_2", value: "进入全屏展示页面，实时查看比分", comment: ""),
                            NSLocalizedString("sync_intro_display_3", value: "分享端继续记分或更换项目，显示端都会同步更新", comment: "")
                        ]
                    )

                    Text(NSLocalizedString(
                        "sync_intro_note",
                        value: "例如：手机记分，平板或另一台手机展示；也可以打开官方网站（https://jifenqi.com），使用本机扫码登录后，将比分跨设备同步到网页端展示。",
                        comment: ""
                    ))
                    .font(.system(size: 12))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.homeNeutralCardTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(16)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CloudSyncIntroSection: View {
    let heading: String
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.primary)
                    .frame(width: 3, height: 14)
                Text(heading)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            ForEach(steps, id: \.self) { step in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.primary)
                    Text(step)
                        .font(.system(size: 13))
                        .lineSpacing(5)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - 角色手风琴卡片（对齐安卓 SyncRoleAccordionCard）

struct CloudSyncRoleCard<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let expanded: Bool
    var collapsible = true
    let onToggle: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Theme.primary.opacity(0.8))
                            .frame(width: 40, height: 40)
                        Image(systemName: icon)
                            .font(.system(size: 17))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(subtitle)
                            .font(.system(size: 13))
                            .lineSpacing(3)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    if collapsible {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.homeNeutralCardTextTertiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!collapsible)

            if expanded {
                VStack(alignment: .leading, spacing: 12) {
                    content()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: expanded)
    }
}

// MARK: - 结束同步确认对话框（项目自定义对话框规范）

struct CloudSyncEndConfirmDialog: View {
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .transition(.opacity)
                .onTapGesture { onCancel() }

            VStack(spacing: 16) {
                Text(NSLocalizedString("sync_end_confirm_title", value: "结束同步？", comment: ""))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString(
                    "sync_end_confirm_message",
                    value: "结束同步后将断开与当前显示端的连接。",
                    comment: ""
                ))
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button(action: onCancel) {
                        Text(NSLocalizedString("cancel", value: "取消", comment: ""))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .background(Theme.homeNeutralCardTextTertiary.opacity(0.14),
                                in: Capsule())

                    Button(action: onConfirm) {
                        Text(NSLocalizedString("sync_end_sharing", value: "结束同步", comment: ""))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .background(Color(hex: "FF3B30"), in: Capsule())
                }
            }
            .padding(20)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .frame(width: 280)
            .transition(.opacity.combined(with: .scale(0.96)))
        }
    }
}

// MARK: - 记分板页同步入口（对齐安卓 RemoteSyncScoreboardSharingEntry）

/// 分享中在记分板页展示的绿色入口按钮，点击弹出管理对话框。
struct CloudSyncScoreboardSharingEntry: View {
    @ObservedObject private var session = CloudSyncSession.shared
    @State private var showSharingDialog = false
    @State private var showEndConfirm = false
    @State private var toastMessage: String?

    private var isSharingVisible: Bool {
        session.isActive && session.controller?.state.isSharing == true
    }

    var body: some View {
        ZStack {
            if isSharingVisible {
                Button {
                    showSharingDialog = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Color(hex: "22C55E"), in: Circle())
                }
                .accessibilityLabel(NSLocalizedString("sync_status_active", value: "同步比分中", comment: ""))
                .transition(.opacity.combined(with: .scale))
            }

            if let toastMessage {
                ToastView(message: toastMessage)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSharingVisible)
        .overlay {
            if showSharingDialog && session.isActive {
                RemoteSyncSharingDialog(
                    sharingState: session.controller?.state ?? RemoteSyncController.SharingState(),
                    onDismiss: { showSharingDialog = false },
                    onCopyCode: {
                        UIPasteboard.general.string = session.controller?.state.shortCode ?? ""
                        showToast(NSLocalizedString("sync_code_copied", value: "已复制短码", comment: ""))
                    },
                    onRetryShortCode: {
                        Task { await session.controller?.retryShortCode() }
                    },
                    onForceSync: {
                        Task {
                            let connected = await session.controller?.ensureConnected() ?? false
                            LocalScoreboardSyncCoordinator.shared.publishSnapshot()
                            showToast(NSLocalizedString(
                                connected ? "sync_force_sync_done" : "sync_start_failed",
                                value: connected ? "已强制同步大屏" : "开始同步失败",
                                comment: ""
                            ))
                        }
                    },
                    onEndSharing: {
                        showSharingDialog = false
                        showEndConfirm = true
                    }
                )
                .transition(.opacity)
            }
        }
        .overlay {
            if showEndConfirm {
                CloudSyncEndConfirmDialog(
                    onCancel: { showEndConfirm = false },
                    onConfirm: {
                        showEndConfirm = false
                        CloudSyncSession.shared.end()
                        showToast(NSLocalizedString("scoreboard_sharing_ended", value: "已结束同步", comment: ""))
                    }
                )
            }
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            toastMessage = nil
        }
    }
}

/// 同步管理对话框（对齐安卓 RemoteSyncSharingDialog：深色卡 + 短码 + 操作按钮）。
struct RemoteSyncSharingDialog: View {
    let sharingState: RemoteSyncController.SharingState
    let onDismiss: () -> Void
    let onCopyCode: () -> Void
    var onRetryShortCode: (() -> Void)? = nil
    var onForceSync: (() -> Void)? = nil
    var onEndSharing: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 14) {
                HStack {
                    Color.clear.frame(width: 36, height: 36)
                    Spacer(minLength: 0)
                    Text(NSLocalizedString("sync_status_active", value: "同步比分中", comment: ""))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(sharingState.connectionState == .connected ? Color(hex: "22C55E") : Color(hex: "F59E0B"))
                        .frame(width: 10, height: 10)
                    Text(connectionText)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.78))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !sharingState.shortCode.isEmpty {
                    Text(sharingState.shortCode.map(String.init).joined(separator: "  "))
                        .font(.system(size: 36, weight: .bold))
                        .kerning(4)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity)
                } else if sharingState.shortCodeError {
                    Text(NSLocalizedString(
                        "sync_shortcode_create_failed",
                        value: "短码生成失败，请点击下方按钮重试",
                        comment: ""
                    ))
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .foregroundStyle(Color(hex: "FF453A"))
                }

                if sharingState.shortCodeError, onRetryShortCode != nil {
                    dialogButton(
                        NSLocalizedString("sync_retry_shortcode", value: "重新生成短码", comment: ""),
                        filled: true,
                        color: Theme.primary,
                        action: { onRetryShortCode?() }
                    )
                    dialogButton(
                        NSLocalizedString("sync_end_sharing", value: "结束同步", comment: ""),
                        filled: false,
                        color: Color(hex: "FF453A"),
                        action: onEndSharing
                    )
                } else {
                    if onForceSync != nil {
                        dialogButton(
                            NSLocalizedString("sync_force_sync_button", value: "强制同步大屏", comment: ""),
                            filled: true,
                            color: Theme.primary,
                            action: { onForceSync?() }
                        )
                    }
                    HStack(spacing: 8) {
                        dialogOutlineButton(
                            NSLocalizedString("sync_copy_code", value: "复制短码", comment: ""),
                            color: Color(hex: "22C55E"),
                            enabled: !sharingState.shortCode.isEmpty,
                            action: onCopyCode
                        )
                        dialogOutlineButton(
                            NSLocalizedString("sync_end_sharing", value: "结束同步", comment: ""),
                            color: Color(hex: "FF453A"),
                            enabled: true,
                            action: onEndSharing
                        )
                    }
                }
            }
            .padding(20)
            .background(Color(hex: "2C2C2E"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 24)
            .frame(maxWidth: 360)
            .transition(.opacity.combined(with: .scale(0.96)))
        }
    }

    private var connectionText: String {
        switch sharingState.connectionState {
        case .connected:
            NSLocalizedString("sync_connected_service", value: "已连接到同步服务", comment: "")
        case .connecting:
            NSLocalizedString("sync_connecting", value: "正在连接同步服务…", comment: "")
        case .reconnecting:
            NSLocalizedString("sync_reconnecting", value: "正在重新连接同步服务…", comment: "")
        case .disconnected:
            NSLocalizedString("sync_disconnected", value: "未连接到同步服务", comment: "")
        }
    }

    private func dialogButton(_ title: String, filled: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Group {
            if filled {
                Button(action: action) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .background(color, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Button(action: action) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(color)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(color, lineWidth: 1)
                )
            }
        }
    }

    private func dialogOutlineButton(_ title: String, color: Color, enabled: Bool,
                                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(color, lineWidth: 1)
        )
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

// MARK: - 记分板页同步入口挂载（对齐安卓 TopStart 20/20）

extension View {
    /// 记分板页云同步分享绿色入口（对齐安卓 RemoteSyncScoreboardSharingEntry）。
    /// 安卓端为沉浸式全屏（系统栏隐藏），20/20 即为屏内偏移；
    /// iOS 保留状态栏，全屏坐标系的页面需追加安全区偏移避免遮挡。
    func cloudSyncSharingEntryOverlay(respectsSafeArea: Bool = false) -> some View {
        overlay(alignment: .topLeading) {
            let insets = respectsSafeArea
                ? UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first?.keyWindow?.safeAreaInsets ?? .zero
                : .zero
            CloudSyncScoreboardSharingEntry()
                .padding(.leading, 20 + insets.left)
                .padding(.top, 20 + insets.top)
        }
    }
}

