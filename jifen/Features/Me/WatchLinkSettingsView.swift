import LinkCore
import SwiftUI

struct WatchLinkSettingsView: View {
    @Environment(PhoneWatchLinkService.self) private var watchLinkService
    @State private var isRefreshing = false
    @State private var showOpenWatchHelp = false
    @State private var selectedUsageTab: WatchLinkUsageTab = .liveScoring

    private enum WatchLinkUsageTab: String, CaseIterable, Identifiable {
        case liveScoring
        case commonNames
        case watchRecords

        var id: String { rawValue }

        var title: String {
            switch self {
            case .liveScoring:
                return NSLocalizedString("watch_sync_usage_tab_live_scoring", value: "双端计分", comment: "")
            case .commonNames:
                return NSLocalizedString("watch_sync_usage_tab_common_names", value: "常用名称", comment: "")
            case .watchRecords:
                return NSLocalizedString("watch_sync_usage_tab_watch_records", value: "手表记录", comment: "")
            }
        }

        var steps: [String] {
            switch self {
            case .liveScoring:
                return [
                    NSLocalizedString("watch_sync_usage_step_1", value: "在手机选择支持的计分项目。", comment: ""),
                    NSLocalizedString("watch_sync_usage_step_2", value: "点击发送到手表，手表确认后主控计分。", comment: ""),
                    NSLocalizedString("watch_sync_usage_step_3", value: "手机实时同步比分，完赛后记录回传保存。", comment: "")
                ]
            case .commonNames:
                return [
                    NSLocalizedString("watch_sync_common_names_step_1", value: "在手机维护常用名称。", comment: ""),
                    NSLocalizedString("watch_sync_common_names_step_2", value: "手机自动同步到手表，无需手动操作。", comment: ""),
                    NSLocalizedString("watch_sync_common_names_step_3", value: "手表开局时可直接选用已同步名称。", comment: "")
                ]
            case .watchRecords:
                return [
                    NSLocalizedString("watch_sync_watch_records_step_1", value: "手表完赛后自动回传记录到手机。", comment: ""),
                    NSLocalizedString("watch_sync_watch_records_step_2", value: "手机记录页可查看，并标示来自手表。", comment: ""),
                    NSLocalizedString("watch_sync_watch_records_step_3", value: "手机与手表保持配对即可，无需手动同步。", comment: "")
                ]
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroCard
                connectionStatusCard
                usageCard
            }
            .padding(.horizontal, Theme.md)
            .padding(.vertical, Theme.lg)
        }
        .background(Theme.backgroundColor)
        .navigationTitle(NSLocalizedString("watch_link_title", value: "手表联动", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .alert(
            NSLocalizedString("watch_sync_open_watch_help_title", value: "打开手表应用", comment: ""),
            isPresented: $showOpenWatchHelp
        ) {
            Button(NSLocalizedString("watch_sync_comm_failure_help_confirm", value: "知道了", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString(
                "watch_sync_open_watch_help_message",
                value: "请在 Apple Watch 上打开「全能计分器」。保持手表解锁且应用在前台，手机端「可达」为是后即可联动开局。",
                comment: ""
            ))
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.primary)
                    .frame(width: 116, height: 116)
                Image(systemName: "applewatch")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(height: 132)

            Text(NSLocalizedString("watch_sync_hero_title", value: "手机手表联动", comment: ""))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Text(NSLocalizedString(
                "watch_sync_hero_description",
                value: "双端同步计分；常用名称自动同步到手表；手表完赛记录自动回传到手机。",
                comment: ""
            ))
            .font(.system(size: 13))
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            Divider().overlay(Theme.divider)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(NSLocalizedString("watch_sync_device_apple_watch", value: "Apple Watch", comment: ""))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(installStatusText)
                        .font(.system(size: 13))
                        .foregroundStyle(installStatusColor)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(connectionStatusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(connectionStatusColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.controlBackground)
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                Button {
                    refreshConnection()
                } label: {
                    HStack(spacing: 8) {
                        if isRefreshing {
                            ProgressView()
                        }
                        Text(NSLocalizedString("watch_sync_action_refresh", value: "刷新连接", comment: ""))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Theme.controlBackground)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)

                Button {
                    showOpenWatchHelp = true
                } label: {
                    Text(NSLocalizedString("watch_sync_action_test", value: "打开手表应用", comment: ""))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(canPromptOpenWatch ? Theme.textOnPrimary : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(canPromptOpenWatch ? Theme.primary : Theme.controlBackground)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.md)
        .frame(maxWidth: .infinity)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Connection status

    private var connectionStatusCard: some View {
        SettingsSection(title: NSLocalizedString("watch_link_status", value: "连接状态", comment: "")) {
            VStack(spacing: 0) {
                statusRow(
                    NSLocalizedString("watch_link_entry_enabled", value: "联动入口", comment: ""),
                    AppFeatureFlags.watchLinkEntryEnabled
                        ? NSLocalizedString("yes", value: "是", comment: "")
                        : NSLocalizedString("no", value: "否", comment: "")
                )
                Divider().overlay(Theme.divider)
                statusRow(
                    NSLocalizedString("watch_link_paired", value: "已配对", comment: ""),
                    boolLabel(watchLinkService.connectivityStatus.isPaired)
                )
                Divider().overlay(Theme.divider)
                statusRow(
                    NSLocalizedString("watch_link_installed", value: "手表 App 已安装", comment: ""),
                    boolLabel(watchLinkService.connectivityStatus.isWatchAppInstalled)
                )
                Divider().overlay(Theme.divider)
                statusRow(
                    NSLocalizedString("watch_link_reachable", value: "可达", comment: ""),
                    boolLabel(watchLinkService.connectivityStatus.isReachable)
                )
                Divider().overlay(Theme.divider)
                statusRow(
                    NSLocalizedString("watch_link_role", value: "当前角色", comment: ""),
                    roleLabel
                )
            }
        }
    }

    // MARK: - Usage

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(NSLocalizedString("watch_sync_usage_title", value: "使用说明", comment: ""))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.textPrimary)

            Text(NSLocalizedString(
                "watch_sync_usage_prerequisite",
                value: "使用前请确认手机和手表均已安装全能计分器，并保持配对连接。",
                comment: ""
            ))
            .font(.system(size: 13))
            .foregroundStyle(Theme.textSecondary)

            usageTabs

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(selectedUsageTab.steps.enumerated()), id: \.offset) { index, step in
                    usageStepRow(index: index + 1, text: step)
                }
            }
        }
        .padding(Theme.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var usageTabs: some View {
        HStack(spacing: 4) {
            ForEach(WatchLinkUsageTab.allCases) { tab in
                Button {
                    selectedUsageTab = tab
                } label: {
                    Text(tab.title)
                        .font(.system(size: 13, weight: selectedUsageTab == tab ? .medium : .regular))
                        .foregroundStyle(selectedUsageTab == tab ? Theme.textOnPrimary : Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(selectedUsageTab == tab ? Theme.primary : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.controlBackground)
        .clipShape(Capsule())
    }

    private func usageStepRow(index: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.primary)
                .frame(width: 22, height: 22)
                .background(Theme.controlBackground)
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Helpers

    private var roleLabel: String {
        switch watchLinkService.controlRole {
        case .phoneController:
            return NSLocalizedString("watch_link_role_phone_controller", value: "手机主控", comment: "")
        case .phoneFollower:
            return NSLocalizedString("watch_link_role_phone_follower", value: "手机跟随", comment: "")
        case .none:
            return NSLocalizedString("watch_link_role_idle", value: "空闲", comment: "")
        default:
            return "—"
        }
    }

    private var canPromptOpenWatch: Bool {
        watchLinkService.connectivityStatus.isPaired
            && watchLinkService.connectivityStatus.isWatchAppInstalled
    }

    private var installStatusText: String {
        let status = watchLinkService.connectivityStatus
        if !status.isPaired {
            return NSLocalizedString("watch_sync_install_not_paired", value: "尚未配对 Apple Watch", comment: "")
        }
        if !status.isWatchAppInstalled {
            return NSLocalizedString("watch_sync_install_missing", value: "手表未安装全能计分器", comment: "")
        }
        if status.isReachable {
            return NSLocalizedString("watch_sync_install_ready", value: "手表应用已安装且可达", comment: "")
        }
        return NSLocalizedString("watch_sync_install_not_reachable", value: "手表应用已安装，当前不可达", comment: "")
    }

    private var installStatusColor: Color {
        let status = watchLinkService.connectivityStatus
        if status.isPaired && status.isWatchAppInstalled && status.isReachable {
            return Theme.primary
        }
        if status.isPaired && status.isWatchAppInstalled {
            return Theme.warningText
        }
        return Theme.textSecondary
    }

    private var connectionStatusText: String {
        let status = watchLinkService.connectivityStatus
        if status.canStartInteractiveSession {
            return NSLocalizedString("watch_sync_status_ready", value: "可同步", comment: "")
        }
        if status.isPaired && status.isWatchAppInstalled {
            return NSLocalizedString("watch_sync_status_wait_reply", value: "等待手表在线", comment: "")
        }
        if !status.isPaired {
            return NSLocalizedString("watch_sync_status_no_connection", value: "未连接", comment: "")
        }
        return NSLocalizedString("watch_sync_status_app_not_installed", value: "未安装应用", comment: "")
    }

    private var connectionStatusColor: Color {
        let status = watchLinkService.connectivityStatus
        if status.canStartInteractiveSession {
            return Theme.primary
        }
        if status.isPaired && status.isWatchAppInstalled {
            return Theme.warningText
        }
        return Theme.textSecondary
    }

    private func boolLabel(_ value: Bool) -> String {
        value
            ? NSLocalizedString("yes", value: "是", comment: "")
            : NSLocalizedString("no", value: "否", comment: "")
    }

    private func statusRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, Theme.md)
        .frame(minHeight: 52)
    }

    private func refreshConnection() {
        isRefreshing = true
        watchLinkService.refreshConnectivity()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            isRefreshing = false
        }
    }
}
