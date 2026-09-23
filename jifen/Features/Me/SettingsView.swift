import StoreKit
import SwiftUI
import UIKit

private enum AppSupportURLs {
    static let website = URL(string: "https://jifenqi.com?utm_source=ios_app&utm_medium=me_tab&utm_campaign=official_website&utm_content=website_entry")!
    static let download = URL(string: "https://jifenqi.com/download?utm_source=ios_app&utm_medium=share&utm_campaign=share_app")!
    static let support = URL(string: "https://jifenqi.com/contact")!
    static let wechatGroup = URL(string: "https://jifenqi.com/contact?utm_source=jifenqi_app&utm_medium=app_link&utm_campaign=official_wechat_group&utm_content=about_page")!
    static let qqGroupNumber = "825096333"
}

private enum SettingsSheetDestination: String, Identifiable {
    case scoreboardSettings
    case faq
    case about
    case feedback

    var id: String { rawValue }

    var entryAccessibilityIdentifier: String {
        switch self {
        case .scoreboardSettings: "settings_scoreboard_entry"
        case .faq: "settings_faq_entry"
        case .about: "settings_about_entry"
        case .feedback: "settings_feedback_entry"
        }
    }

    var sheetAccessibilityIdentifier: String {
        switch self {
        case .scoreboardSettings: "settings_scoreboard_sheet"
        case .faq: "settings_faq_sheet"
        case .about: "settings_about_sheet"
        case .feedback: "settings_feedback_sheet"
        }
    }

    var closeAccessibilityIdentifier: String {
        "\(sheetAccessibilityIdentifier)_close"
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openInAppWebLink) private var openInAppWebLink
    @Environment(AppAppearanceStore.self) private var appearance
    @Environment(SessionStore.self) private var session
    var isTabRoot: Bool = false
    @State private var showClearConfirm = false
    @State private var showAppShareSheet = false
    @State private var showAccountLoginSheet = false
    @State private var showQRLogin = false
    @State private var activeSheet: SettingsSheetDestination?
    @State private var clearDataErrorMessage: String?
    @State private var isClearingData = false
    @State private var toastMessage: String?
    @State private var soundEffectsEnabled = PreferencesManager.shared.soundEnabled

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.sectionSpacing) {
                        accountCard
                        websiteCard
                        if AppFeatureFlags.feedbackEntryEnabled {
                            feedbackCard
                        }
                        preferencesCard
                        supportCard
                    }
                    .frame(maxWidth: Theme.meTabContentMaxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Theme.pageHorizontalInset)
                    .padding(.vertical, Theme.tabContentBottomPadding)
                }
            }
            .navigationTitle(NSLocalizedString(isTabRoot ? "tab_me" : "settings", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showQRLogin) {
                QRLoginApprovalView()
            }
            // Use `.automatic` on the Me tab root so pushed pages can hide the tab bar.
            .toolbar(isTabRoot ? .automatic : .hidden, for: .tabBar)
            .toolbar {
                if !isTabRoot {
                    ToolbarItem(placement: .topBarTrailing) {
                        ModalCloseButton { dismiss() }
                    }
                }
            }
            .sheet(item: $activeSheet) { destination in
                SettingsFormSheet(destination: destination)
                    .presentationSizing(.form)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showAppShareSheet) {
                AnalyticsActivityView(
                    activityItems: [
                        NSLocalizedString("settings_share_app_message", value: "打球、训练或朋友聚会，用全能计分器轻松记分。支持乒乓球、羽毛球、网球、篮球和多种游戏，比分清楚，还能回看记录。", comment: ""),
                        AppSupportURLs.download
                    ],
                    contentType: "app_link"
                )
            }
            .sheet(isPresented: $showAccountLoginSheet) {
                AccountLoginSheet()
            }
            .alert(
                NSLocalizedString("clear_data_confirm_title", value: "清除全部数据？", comment: ""),
                isPresented: $showClearConfirm
            ) {
                Button(NSLocalizedString("clear_data_confirm_action", value: "清除", comment: ""), role: .destructive) {
                    clearAllData()
                }
                Button(NSLocalizedString("cancel", comment: ""), role: .cancel) { }
            } message: {
                Text(NSLocalizedString(
                    "clear_data_confirm_message",
                    value: "将删除所有本地记录、预约、提醒、常用名称和常用地点，且无法恢复。",
                    comment: ""
                ))
            }
            .overlay {
                if let toastMessage {
                    ToastView(message: toastMessage)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: toastMessage)
            .alert(
                NSLocalizedString("clear_data_failed_title", value: "清除失败", comment: ""),
                isPresented: clearDataErrorPresented
            ) {
                Button(NSLocalizedString("confirm", value: "OK", comment: "")) {
                    clearDataErrorMessage = nil
                }
            } message: {
                Text(clearDataErrorMessage ?? "")
            }
            .onChange(of: soundEffectsEnabled) { _, value in
                PreferencesManager.shared.soundEnabled = value
                AppAnalytics.track(.toggleSetting, parameters: [
                    .sourcePage: .string(AnalyticsScreen.meTab.rawValue),
                    .settingName: .string("sound"),
                    .settingValue: .string(value ? "on" : "off")
                ])
            }
            .task {
                await session.reloadProfileIfNeeded()
            }
            .navigationDestination(for: SettingsSheetDestination.self) {
                settingsDestinationView($0)
            }
            .inAppWebLinkDestination()
        }
    }

    // MARK: - Cards (aligned 1:1 with Android MeTabScreen)

    private var accountCard: some View {
        SettingsSection {
            VStack(spacing: 0) {
                accountEntry
                settingsRowDivider
                NavigationLink { MembershipView() } label: {
                    SettingsNavigationRow(
                        title: session.isVIP
                            ? NSLocalizedString("membership_entry_title_active", value: "VIP 会员", comment: "")
                            : NSLocalizedString("membership_title", value: "会员", comment: ""),
                        subtitle: session.isVIP
                            ? NSLocalizedString("membership_entry_summary_active", value: "您已是 VIP 会员，感谢您的支持", comment: "")
                            : NSLocalizedString("membership_entry_summary", value: "月卡、年卡或终身 VIP", comment: "")
                    )
                }
                .accessibilityIdentifier("settings_membership_entry")
            }
        }
    }

    @ViewBuilder
    private var accountEntry: some View {
        if session.isAuthenticated {
            NavigationLink { AccountCenterView() } label: {
                accountEntryLabel
            }
            .accessibilityIdentifier("settings_account_entry")
        } else {
            Button {
                showAccountLoginSheet = true
            } label: {
                accountEntryLabel
            }
            .buttonStyle(.plain)
            .disabled(session.state == .restoring)
            .accessibilityIdentifier("settings_account_entry")
        }
    }

    private var accountEntryLabel: some View {
        MeAccountEntryRow(
            loggedIn: session.isAuthenticated,
            displayName: session.user?.displayName ?? "",
            avatarURL: avatarURL,
            subtitle: accountSubtitle,
            onScanLogin: session.isAuthenticated ? { showQRLogin = true } : nil
        )
    }

    private var websiteCard: some View {
        SettingsSection {
            Button {
                AppAnalytics.openPage(from: .meTab, to: .legalWebPage, entryPoint: .meTab)
                openInAppWebLink(InAppWebLink(
                    url: AppSupportURLs.website,
                    title: NSLocalizedString("me_official_website", value: "官方网站", comment: "")
                ))
            } label: {
                SettingsNavigationRow(
                    title: NSLocalizedString("me_official_website", value: "官方网站", comment: ""),
                    subtitle: NSLocalizedString("me_official_website_subtitle", value: "支持网页端实时投屏比分", comment: "")
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings_website_entry")
        }
    }

    private var feedbackCard: some View {
        SettingsSection {
            // 对齐安卓平板端：iPad 上反馈社区以对话框（form sheet）呈现。
            if Theme.usesPadLayout {
                Button {
                    activeSheet = .feedback
                } label: {
                    SettingsNavigationRow(
                        title: NSLocalizedString("me_feedback_entry", value: "反馈社区", comment: ""),
                        subtitle: NSLocalizedString("feedback_entry_subtitle", value: "功能建议与问题反馈", comment: "")
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings_feedback_entry")
            } else {
                // 反馈页内含外链（会再 item-push 网页），同样走值驱动，理由同 settingsDestinationRow。
                NavigationLink(value: SettingsSheetDestination.feedback) {
                    SettingsNavigationRow(
                        title: NSLocalizedString("me_feedback_entry", value: "反馈社区", comment: ""),
                        subtitle: NSLocalizedString("feedback_entry_subtitle", value: "功能建议与问题反馈", comment: "")
                    )
                }
                .accessibilityIdentifier("settings_feedback_entry")
            }
        }
    }

    private var preferencesCard: some View {
        SettingsSection {
            VStack(spacing: 0) {
                settingsDestinationRow(
                    .scoreboardSettings,
                    title: NSLocalizedString("scoreboard_settings_title", value: "计分设置", comment: "")
                )
                settingsRowDivider
                MeSoundToggleRow(
                    title: NSLocalizedString("sound_effects", value: "音效", comment: ""),
                    isOn: $soundEffectsEnabled,
                    toggleAccessibilityIdentifier: "me_sound_effects_toggle",
                    helpTitle: NSLocalizedString("sound_effects_help_title", value: "音效", comment: ""),
                    helpMessage: NSLocalizedString(
                        "sound_effects_help_message",
                        value: "控制掷骰子、抛硬币、倒计时结束等工具音效，关闭后这些音效将静音。",
                        comment: ""
                    )
                )
                settingsRowDivider
                Menu {
                    ForEach(AppAppearanceMode.allCases, id: \.self) { mode in
                        Button {
                            appearance.mode = mode
                            AppAnalytics.track(.toggleSetting, parameters: [
                                .settingName: .string("app_appearance"),
                                .settingValue: .string(mode.rawValue)
                            ])
                        } label: {
                            if appearance.mode == mode {
                                Label(mode.localizedTitle, systemImage: "checkmark")
                            } else {
                                Text(mode.localizedTitle)
                            }
                        }
                    }
                } label: {
                    SettingsNavigationRow(
                        title: NSLocalizedString("appearance_mode_title", value: "外观模式", comment: ""),
                        value: appearance.mode.localizedTitle
                    )
                }
                settingsRowDivider
                Button {
                    AppAnalytics.openDialog("clear_data_confirm", source: .meTab)
                    showClearConfirm = true
                } label: {
                    SettingsNavigationRow(title: NSLocalizedString("clear_data", comment: ""))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var supportCard: some View {
        SettingsSection {
            VStack(spacing: 0) {
                Button {
                    requestReview()
                    AppAnalytics.track(.rateApp, parameters: [
                        .entryPoint: .string(AnalyticsEntryPoint.meTab.rawValue),
                        .result: .string(AnalyticsResult.requested.rawValue)
                    ])
                } label: {
                    SettingsNavigationRow(title: NSLocalizedString("settings_rate_app", value: "给个好评", comment: ""))
                }
                .buttonStyle(.plain)
                settingsRowDivider
                Button {
                    AppAnalytics.track(.shareApp, parameters: [
                        .entryPoint: .string(AnalyticsEntryPoint.meTab.rawValue),
                        .contentType: .string("app_link")
                    ])
                    AppAnalytics.track(.shareStart, parameters: [
                        .contentType: .string("app_link"),
                        .sourcePage: .string(AnalyticsScreen.meTab.rawValue)
                    ])
                    showAppShareSheet = true
                } label: {
                    SettingsNavigationRow(title: NSLocalizedString("settings_share_app", value: "分享给朋友", comment: ""))
                }
                .buttonStyle(.plain)
                settingsRowDivider
                settingsDestinationRow(
                    .faq,
                    title: NSLocalizedString("settings_faq", value: "常见问题", comment: "")
                )
                settingsRowDivider
                settingsDestinationRow(
                    .about,
                    title: NSLocalizedString("about_us_title", value: "关于我们", comment: "")
                )
            }
        }
    }

    private var accountSubtitle: String {
        if session.isAuthenticated, let user = session.user {
            if session.isVIP {
                // Prefer richer server membership metadata only when that
                // membership is active; local Apple entitlement uses the
                // generic VIP label so every entry point stays consistent.
                guard user.isVIP else {
                    return NSLocalizedString("me_profile_vip_badge", value: "VIP", comment: "")
                }
                let summary = user.membership?.identitySummary.trimmingCharacters(in: .whitespacesAndNewlines)
                if let summary, !summary.isEmpty { return summary }
                return NSLocalizedString("me_profile_vip_badge", value: "VIP", comment: "")
            }
            return NSLocalizedString("membership_basic_member_title", value: "普通用户", comment: "")
        }
        return NSLocalizedString("me_account_logged_out_summary", value: "登录后体验更多功能", comment: "")
    }

    private var avatarURL: URL? {
        APIAssetURLResolver.resolve(session.user?.avatarUrl ?? session.user?.avatar)
    }

    private var clearDataErrorPresented: Binding<Bool> {
        Binding(
            get: { clearDataErrorMessage != nil },
            set: { if !$0 { clearDataErrorMessage = nil } }
        )
    }

    private func clearAllData() {
        guard !isClearingData else { return }
        isClearingData = true
        Task {
            let result = await LocalDataResetCoordinator.live(
                appearance: appearance
            ).clearAll()
            ScoreboardRecordsViewModel.shared.refreshRecordsImmediately()
            TimerRecordsViewModel.shared.loadFromStorage()
            isClearingData = false
            if result.succeeded {
                showToast(NSLocalizedString("clear_data_success", value: "已清除全部数据", comment: ""))
                trackClearDataResult(.success)
            } else {
                clearDataErrorMessage = String(
                    format: NSLocalizedString(
                        "clear_data_failed_format",
                        value: "部分数据未能清除，可安全重试：\n%@",
                        comment: "Clear data failure grouped by category"
                    ),
                    result.localizedFailureSummary
                )
                trackClearDataResult(.failed)
            }
        }
    }

    private func trackClearDataResult(_ result: AnalyticsResult) {
        AppAnalytics.track(.clearData, parameters: [
            .actionName: .string("clear_all"),
            .result: .string(result.rawValue)
        ])
    }

    private func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    @ViewBuilder
    private func settingsDestinationRow(
        _ destination: SettingsSheetDestination,
        title: String
    ) -> some View {
        if Theme.usesPadLayout {
            Button {
                AppAnalytics.openPage(from: .meTab, to: destination.analyticsScreen, entryPoint: .meTab)
                activeSheet = destination
            } label: {
                SettingsNavigationRow(title: title)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(destination.entryAccessibilityIdentifier)
        } else {
            // iPhone 必须走值驱动 NavigationLink：闭包式 `NavigationLink { 页面 }` 与
            // inAppWebLinkDestination 的 item push 混在一条栈上时，网页返回会把闭包
            // push 的页面一并退掉（实测关于页 → 协议网页 → 返回直接退到「我的」根）。
            NavigationLink(value: destination) {
                SettingsNavigationRow(title: title)
            }
            .simultaneousGesture(TapGesture().onEnded {
                AppAnalytics.openPage(from: .meTab, to: destination.analyticsScreen, entryPoint: .meTab)
            })
            .accessibilityIdentifier(destination.entryAccessibilityIdentifier)
        }
    }

    @ViewBuilder
    private func settingsDestinationView(_ destination: SettingsSheetDestination) -> some View {
        switch destination {
        case .scoreboardSettings: ScoreboardSettingsView()
        case .faq: FAQView()
        case .about: AboutUsView()
        case .feedback: FeedbackListView()
        }
    }

    private var settingsRowDivider: some View {
        SettingsRowDivider()
    }
}

private struct SettingsFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    let destination: SettingsSheetDestination

    var body: some View {
        NavigationStack {
            destinationContent
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ModalCloseButton { dismiss() }
                        .accessibilityIdentifier(destination.closeAccessibilityIdentifier)
                    }
                }
                .inAppWebLinkDestination()
        }
        // 弹窗自己是独立的一条栈，网页要内嵌 push 在弹窗里，所以这里配一套自己的宿主；
        // 不能让 AboutUsView 等页面自己身上挂（自己 inject 的 environment 对自己无效）。
        .inAppWebLinks()
        .background(Theme.backgroundColor.ignoresSafeArea())
        .accessibilityIdentifier(destination.sheetAccessibilityIdentifier)
    }

    @ViewBuilder
    private var destinationContent: some View {
        switch destination {
        case .scoreboardSettings:
            ScoreboardSettingsView()
        case .faq:
            FAQView()
        case .about:
            AboutUsView()
        case .feedback:
            FeedbackListView()
        }
    }
}

private extension SettingsSheetDestination {
    var analyticsScreen: AnalyticsScreen {
        switch self {
        case .scoreboardSettings: return .scoreboardSettingsPage
        case .faq: return .faqPage
        case .about: return .aboutUsPage
        case .feedback: return .feedbackPage
        }
    }
}

struct MeTab: View {
    var body: some View {
        SettingsView(isTabRoot: true)
            // 宿主必须挂在读 openInAppWebLink 的那个视图之上：挂在 SettingsView 自己
            // body 的输出上等于自我注入，它本身读到的仍是默认空 action（点了没反应）。
            .inAppWebLinks()
    }
}

// MARK: - Supporting Views

/// 我的 Tab 列表页统一的条目分割线：Theme.divider 45% 透明度。
private struct SettingsRowDivider: View {
    var body: some View {
        Divider()
            .overlay(Theme.divider)
            .opacity(0.45)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionContentSpacing) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(size: Theme.fontBody2, weight: .regular))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 4)
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.appCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Theme.divider.opacity(0.7), lineWidth: 0.5)
                }
        }
    }
}

private struct SettingsNavigationRow: View {
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    /// 行最小高度覆盖；不传则沿用默认（无副标题 56 / 有副标题 80）。
    var minHeight: CGFloat? = nil
    /// 标题与副标题之间的纵向间距覆盖；不传则沿用默认（无副标题 2 / 有副标题 6）。
    var contentSpacing: CGFloat? = nil

    var body: some View {
        HStack(spacing: Theme.sm) {
            VStack(alignment: .leading, spacing: contentSpacing ?? (subtitle == nil ? 2 : 6)) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let value {
                Text(value)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.horizontal, Theme.cardPadding)
        .frame(minHeight: minHeight ?? (subtitle == nil ? 56 : 80), alignment: .center)
        .contentShape(Rectangle())
    }
}

/// Account header row aligned 1:1 with Android `AccountEntryRow`.
private struct MeAccountEntryRow: View {
    let loggedIn: Bool
    let displayName: String
    let avatarURL: URL?
    let subtitle: String
    var onScanLogin: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 16) {
            avatar
            VStack(alignment: .leading, spacing: 4) {
                Text(loggedIn && !displayName.isEmpty
                    ? displayName
                    : NSLocalizedString("me_account_logged_out", value: "未登录", comment: ""))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if let onScanLogin {
                scanLoginButton(action: onScanLogin)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.horizontal, Theme.cardPadding)
        .padding(.vertical, 16)
        .frame(minHeight: 92)
        .contentShape(Rectangle())
    }

    // 扫码登录：嵌在名称条右侧、右箭头左侧的图标按钮（对齐安卓扫一扫图标入口）。
    private func scanLoginButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(Theme.textPrimary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(NSLocalizedString("qr_login_title", value: "扫码登录", comment: ""))
        .accessibilityIdentifier("settings_qr_login_entry")
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(Theme.controlBackground)
            if loggedIn, let avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                } placeholder: {
                    avatarFallback
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: 60, height: 60)
    }

    @ViewBuilder
    private var avatarFallback: some View {
        let initial = displayName.trimmingCharacters(in: .whitespacesAndNewlines).first
        if loggedIn, let initial {
            Text(String(initial))
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
        } else {
            Image(systemName: "person.fill")
                .font(.system(size: 26))
                .foregroundColor(Theme.textSecondary)
        }
    }
}

private struct ScoreboardSettingsView: View {
    @State private var forceIPadLandscape = PreferencesManager.shared.forceIPadLandscape
    @State private var keepScreenOn = PreferencesManager.shared.keepScoreboardScreenOn
    @State private var officialBreaksEnabled = PreferencesManager.shared.officialBreaksEnabled
    @State private var vibrationEnabled = PreferencesManager.shared.vibrationEnabled
    @State private var touchGuard = PreferencesManager.shared.scoreboardTouchGuardEnabled
    @State private var doubleTapSubtract = PreferencesManager.shared.scoreboardDoubleTapSubtractEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.lg) {
                SettingsSection {
                    VStack(spacing: 0) {
                        if Theme.usesPadLayout {
                            ScoreboardToggleSettingRow(
                                title: NSLocalizedString("scoreboard_force_ipad_landscape", value: "计分板强制横屏", comment: ""),
                                isOn: $forceIPadLandscape,
                                toggleAccessibilityIdentifier: "scoreboard_force_ipad_landscape_toggle"
                            )
                            Divider().overlay(Theme.divider)
                        }
                        ScoreboardToggleSettingRow(
                            title: NSLocalizedString("scoreboard_keep_screen_on", value: "屏幕常亮", comment: ""),
                            isOn: $keepScreenOn,
                            toggleAccessibilityIdentifier: "scoreboard_keep_screen_on_toggle"
                        )
                        Divider().overlay(Theme.divider)
                        ScoreboardToggleSettingRow(
                            title: NSLocalizedString("vibration", value: "振动", comment: ""),
                            isOn: $vibrationEnabled,
                            toggleAccessibilityIdentifier: "scoreboard_vibration_toggle"
                        )
                        Divider().overlay(Theme.divider)
                        ScoreboardToggleSettingRow(
                            title: NSLocalizedString("scoreboard_touch_guard", value: "触摸防误触", comment: ""),
                            isOn: $touchGuard,
                            toggleAccessibilityIdentifier: "scoreboard_touch_guard_toggle",
                            help: .touchGuard
                        )
                        Divider().overlay(Theme.divider)
                        ScoreboardToggleSettingRow(
                            title: NSLocalizedString("scoreboard_double_tap_subtract", value: "双击减分", comment: ""),
                            isOn: $doubleTapSubtract,
                            toggleAccessibilityIdentifier: "scoreboard_double_tap_subtract_toggle",
                            help: .doubleTapSubtract
                        )
                    }
                }

                SettingsSection {
                    ScoreboardToggleSettingRow(
                        title: NSLocalizedString("official_break_game", value: "局中/局间官方休息", comment: ""),
                        isOn: $officialBreaksEnabled,
                        toggleAccessibilityIdentifier: "official_breaks_toggle",
                        help: .officialBreak
                    )
                }
            }
            .frame(maxWidth: Theme.meTabContentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.pageHorizontalInset)
            .padding(.top, Theme.lg)
            .padding(.bottom, Theme.lg + 72)
        }
        .background(Theme.backgroundColor)
        .navigationTitle(NSLocalizedString("scoreboard_settings_title", value: "计分设置", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .analyticsScreen(.scoreboardSettingsPage, source: .meTab)
        .onChange(of: forceIPadLandscape) { _, value in
            PreferencesManager.shared.forceIPadLandscape = value
            trackSetting("tablet_scoreboard_force_landscape", value)
        }
        .onChange(of: keepScreenOn) { _, value in
            PreferencesManager.shared.keepScoreboardScreenOn = value
            trackSetting("scoreboard_keep_screen_on", value)
        }
        .onChange(of: officialBreaksEnabled) { _, value in
            PreferencesManager.shared.officialBreaksEnabled = value
            trackSetting("scoreboard_official_break", value)
        }
        .onChange(of: vibrationEnabled) { _, value in
            PreferencesManager.shared.vibrationEnabled = value
            trackSetting("vibration", value)
        }
        .onChange(of: touchGuard) { _, value in
            PreferencesManager.shared.scoreboardTouchGuardEnabled = value
            trackSetting("scoreboard_touch_guard", value)
        }
        .onChange(of: doubleTapSubtract) { _, value in
            PreferencesManager.shared.scoreboardDoubleTapSubtractEnabled = value
            trackSetting("scoreboard_double_tap_subtract", value)
        }
    }

    private func trackSetting(_ name: String, _ value: Bool) {
        trackSetting(name, value ? "on" : "off")
    }

    private func trackSetting(_ name: String, _ value: String) {
        // 对齐安卓：toggle_setting 事件带 source_page=scoreboard_settings_page。
        AppAnalytics.track(.toggleSetting, parameters: [
            .sourcePage: .string(AnalyticsScreen.scoreboardSettingsPage.rawValue),
            .settingName: .string(name),
            .settingValue: .string(value)
        ])
    }
}

private enum ScoreboardSettingHelp {
    case touchGuard
    case doubleTapSubtract
    case officialBreak

    var title: String {
        switch self {
        case .touchGuard: return NSLocalizedString("scoreboard_touch_guard_help_title", value: "触摸防误触", comment: "")
        case .doubleTapSubtract: return NSLocalizedString("scoreboard_double_tap_help_title", value: "双击减分", comment: "")
        case .officialBreak: return NSLocalizedString("scoreboard_official_break_help_title", value: "局中/局间官方休息", comment: "")
        }
    }

    var message: String {
        switch self {
        case .touchGuard:
            return NSLocalizedString("scoreboard_touch_guard_help_message", value: "仅点击比分数字附近时才会计分，减少握持和擦拭屏幕时的误触。", comment: "")
        case .doubleTapSubtract:
            return NSLocalizedString("scoreboard_double_tap_subtract_help_message", value: "开启后，快速双击某一方的比分区域会减 1 分。仅适用于部分计分板。", comment: "")
        case .officialBreak:
            return NSLocalizedString("scoreboard_official_break_help_message", value: "开启后，支持的项目会在局中或局间按规则自动进入官方休息；休息期间暂停计分，可跳过并可撤销。", comment: "")
        }
    }

    /// 该行位于页面底部，气泡固定向锚点上方展开，避免小屏（如 iPhone SE）下方空间不足被裁切。
    var prefersAboveAnchor: Bool {
        self == .officialBreak
    }
}

private struct ScoreboardToggleSettingRow: View {
    let title: String
    @Binding var isOn: Bool
    let toggleAccessibilityIdentifier: String
    var help: ScoreboardSettingHelp? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(Theme.textPrimary)
            if let help {
                SystemHelpButton(
                    title: help.title,
                    message: help.message,
                    accessibilityIdentifier: "\(toggleAccessibilityIdentifier)_help",
                    preferredArrowEdge: help.prefersAboveAnchor ? .bottom : nil
                )
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .accessibilityIdentifier(toggleAccessibilityIdentifier)
        }
        .padding(.horizontal, Theme.md)
        .frame(minHeight: 56)
        // 对齐安卓 ScoreboardSettingsSwitchRow：整行可点击切换开关。
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}

/// 我的页音效开关行：标题 + “?”帮助 + Toggle，对齐 MeTab 行样式（56pt 行高）。
private struct MeSoundToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let toggleAccessibilityIdentifier: String
    var helpTitle: String? = nil
    var helpMessage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Theme.textPrimary)
            if let helpTitle, let helpMessage {
                SystemHelpButton(
                    title: helpTitle,
                    message: helpMessage,
                    accessibilityIdentifier: "\(toggleAccessibilityIdentifier)_help"
                )
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .accessibilityIdentifier(toggleAccessibilityIdentifier)
        }
        .padding(.horizontal, Theme.cardPadding)
        .frame(minHeight: 56)
        // 对齐安卓 MeTab 开关行：整行可点击切换开关。
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}

private struct FAQItem: Identifiable {
    let id: Int
    let question: String
    let answer: String
}

private struct FAQView: View {
    @State private var expandedID: Int?

    private var items: [FAQItem] {
        [1, 2, 3, 5, 6, 7, 8].map { index in
            FAQItem(
                id: index,
                question: NSLocalizedString("faq_question_\(index)", value: "", comment: ""),
                answer: NSLocalizedString("faq_answer_\(index)", value: "", comment: "")
            )
        }
    }

    var body: some View {
        ScrollView {
            // 全部条目收在一张 20pt 圆角大卡内，条目间用分隔线；
            // 20 对齐首页区块卡与设置弹窗容器档（安卓端 FAQ 仍为 12，见圆角审计报告）。
            VStack(spacing: 0) {
                ForEach(items) { item in
                    Button { expandedID = expandedID == item.id ? nil : item.id } label: {
                        VStack(alignment: .leading, spacing: Theme.sm) {
                            HStack {
                                Text(item.question)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(Theme.textPrimary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: expandedID == item.id ? "chevron.up" : "chevron.down")
                                    .foregroundColor(Theme.textSecondary)
                            }
                            if expandedID == item.id {
                                Text(item.answer)
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.textSecondary)
                                    .multilineTextAlignment(.leading)
                                    .accessibilityIdentifier("settings_faq_answer_\(item.id)")
                            }
                        }
                        .padding(Theme.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.appCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings_faq_question_\(item.id)")
                }
            }
            .background(Theme.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .frame(maxWidth: Theme.meTabContentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.pageHorizontalInset)
            .padding(.vertical, Theme.md)
        }
        .background(Theme.backgroundColor)
        .navigationTitle(NSLocalizedString("settings_faq", value: "常见问题", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .analyticsScreen(.faqPage, source: .meTab)
    }
}

private struct AboutUsView: View {
    @State private var toastMessage: String?

    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.lg) {
                    VStack(spacing: Theme.md) {
                        AppLogoImage(size: 72)
                        Text(NSLocalizedString("app_name", value: "全能计分器", comment: ""))
                            .font(.title2.weight(.semibold))
                            .foregroundColor(Theme.textPrimary)
                        Text(String(format: NSLocalizedString("about_version_format", value: "版本 %@", comment: ""), appVersion))
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)
                    }
                    .padding(.top, Theme.sm)

                    VStack(spacing: 0) {
                        webLinkRow(
                            title: NSLocalizedString("terms_of_service", value: "用户协议", comment: ""),
                            url: LegalDocuments.termsURL,
                            accessibilityIdentifier: "settings_about_terms_link",
                            tracksLegalAnalytics: true
                        )
                        SettingsRowDivider()
                        webLinkRow(
                            title: NSLocalizedString("privacy_policy", value: "隐私政策", comment: ""),
                            url: LegalDocuments.privacyURL,
                            accessibilityIdentifier: "settings_about_privacy_link",
                            tracksLegalAnalytics: true
                        )
                        if isChineseLocale {
                            SettingsRowDivider()
                            webLinkRow(
                                title: NSLocalizedString("about_wechat_group", value: "微信群", comment: ""),
                                url: AppSupportURLs.wechatGroup,
                                accessibilityIdentifier: "settings_about_wechat_link",
                                tracksLegalAnalytics: false
                            )
                            SettingsRowDivider()
                            qqGroupRow
                        }
                    }
                    .background(Theme.appCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Theme.divider.opacity(0.7), lineWidth: 0.5)
                    }

                    Text(companyDisplayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 40)
                        .padding(.bottom, Theme.lg)
                }
                .frame(maxWidth: Theme.meTabContentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.pageHorizontalInset)
                .padding(.vertical, Theme.md)
            }

            if let toastMessage {
                ToastView(message: toastMessage)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .navigationTitle(NSLocalizedString("about_us_title", value: "关于我们", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .analyticsScreen(.aboutUsPage, source: .meTab)
    }

    /// 关于页外链行：应用内网页打开（不再跳系统浏览器），标识符与原 Link 保持一致。
    private func webLinkRow(
        title: String,
        url: URL,
        accessibilityIdentifier: String,
        tracksLegalAnalytics: Bool
    ) -> some View {
        NavigationLink(value: InAppWebLink(url: url, title: title)) {
            SettingsNavigationRow(title: title)
        }
        .simultaneousGesture(TapGesture().onEnded {
            if tracksLegalAnalytics {
                AppAnalytics.openPage(from: .aboutUsPage, to: .legalWebPage)
            }
        })
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var qqGroupRow: some View {
        HStack(spacing: Theme.sm) {
            Text(NSLocalizedString("about_qq_group_label", value: "QQ 群", comment: ""))
                .font(.system(size: 16))
                .foregroundColor(Theme.textPrimary)
            Spacer()
            Text(AppSupportURLs.qqGroupNumber)
                .font(.system(size: 15))
                .foregroundColor(Theme.textSecondary)
            Button {
                UIPasteboard.general.string = AppSupportURLs.qqGroupNumber
                showToast(NSLocalizedString("about_copy_qq_toast", value: "已复制 QQ 群号", comment: ""))
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("about_qq_group_label", value: "QQ 群", comment: ""))
        }
        .padding(.horizontal, Theme.md)
        .frame(minHeight: 56)
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"
        return short.hasPrefix("v") ? short : "v\(short)"
    }

    private var isChineseLocale: Bool {
        Locale.current.language.languageCode?.identifier.hasPrefix("zh") == true
    }

    private var companyDisplayName: String {
        // Registered company name is a legal entity string; zh-Hant deliberately
        // reuses the simplified registration. Do not "fix" this as a localization miss.
        isChineseLocale
            ? NSLocalizedString("about_company_zh", value: "重庆豆花科技有限公司", comment: "")
            : NSLocalizedString("about_company_en", value: "Chongqing Douhua Technology Co., Ltd.", comment: "")
    }

    private func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }
}

struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(Theme.accentColor)
                .frame(width: 24, height: 24)

            Text(title)
                .foregroundColor(Theme.textPrimary)

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(Theme.accentColor)
                .frame(width: 24, height: 24)

            Text(title)
                .foregroundColor(Theme.textPrimary)

            Spacer()

            Text(value)
                .foregroundColor(Theme.textSecondary)
                .font(.system(size: Theme.fontBody2))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    SettingsView()
}
