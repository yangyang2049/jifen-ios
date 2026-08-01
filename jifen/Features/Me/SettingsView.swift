import PersistenceCore
import StoreKit
import SwiftUI
import UIKit

private enum AppSupportURLs {
    static let website = URL(string: "https://jifenqi.com")!
    static let support = URL(string: "https://jifenqi.com/contact")!
    static let feedback = URL(string: "https://jifenqi.com/feedback")!
    static let terms = URL(string: "https://jifenqi.com/terms")!
    static let privacy = URL(string: "https://jifenqi.com/privacy")!
    static let wechatGroup = URL(string: "https://jifenqi.com/contact?utm_source=jifenqi_app&utm_medium=app_link&utm_campaign=official_wechat_group&utm_content=about_page")!
    static let qqGroupNumber = "825096333"
}

private enum SettingsSheetDestination: String, Identifiable {
    case scoreboardSettings
    case faq
    case about

    var id: String { rawValue }

    var entryAccessibilityIdentifier: String {
        switch self {
        case .scoreboardSettings: "settings_scoreboard_entry"
        case .faq: "settings_faq_entry"
        case .about: "settings_about_entry"
        }
    }

    var sheetAccessibilityIdentifier: String {
        switch self {
        case .scoreboardSettings: "settings_scoreboard_sheet"
        case .faq: "settings_faq_sheet"
        case .about: "settings_about_sheet"
        }
    }

    var closeAccessibilityIdentifier: String {
        "\(sheetAccessibilityIdentifier)_close"
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(AppAppearanceStore.self) private var appearance
    var isTabRoot: Bool = false
    @State private var showClearConfirm = false
    @State private var showAppearancePicker = false
    @State private var showAppShareSheet = false
    @State private var activeSheet: SettingsSheetDestination?
    @State private var clearDataErrorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.sectionSpacing) {
                        SettingsSection(title: NSLocalizedString("settings_features", value: "功能设置", comment: "")) {
                            VStack(spacing: 0) {
                                settingsDestinationRow(
                                    .scoreboardSettings,
                                    title: NSLocalizedString("scoreboard_settings_title", value: "计分设置", comment: "")
                                ) {
                                    ScoreboardSettingsView()
                                }
                                if AppFeatureFlags.watchLinkEntryEnabled
                                    && AppFeatureFlags.isWatchLinkSupportedOnCurrentDevice {
                                    settingsRowDivider
                                    NavigationLink { WatchLinkSettingsView() } label: {
                                        SettingsNavigationRow(title: NSLocalizedString("watch_link_title", value: "手表联动", comment: ""))
                                    }
                                    .simultaneousGesture(TapGesture().onEnded {
                                        AppAnalytics.openPage(from: .meTab, to: .watchLinkPage, entryPoint: .meTab)
                                    })
                                }
                                settingsRowDivider
                                Button {
                                    AppAnalytics.openDialog("appearance_picker", source: .meTab)
                                    showAppearancePicker = true
                                } label: {
                                    SettingsNavigationRow(
                                        title: NSLocalizedString("appearance", comment: ""),
                                        value: appearance.mode.localizedTitle
                                    )
                                }
                                .buttonStyle(.plain)
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

                        SettingsSection(title: NSLocalizedString("settings_help_support", value: "帮助与支持", comment: "")) {
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
                                ) {
                                    FAQView()
                                }
                                settingsRowDivider
                                settingsDestinationRow(
                                    .about,
                                    title: NSLocalizedString("about_us_title", value: "关于我们", comment: "")
                                ) {
                                    AboutUsView()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: Theme.meTabContentMaxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Theme.pageHorizontalInset)
                    .padding(.vertical, Theme.tabContentBottomPadding)
                }
            }
            .navigationTitle(NSLocalizedString(isTabRoot ? "tab_me" : "settings", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            // Use `.automatic` on the Me tab root so pushed pages can hide the tab bar.
            .toolbar(isTabRoot ? .automatic : .hidden, for: .tabBar)
            .toolbar {
                if !isTabRoot {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .foregroundColor(Theme.textPrimary)
                        }
                    }
                }
            }
            .confirmationDialog(NSLocalizedString("appearance", comment: ""), isPresented: $showAppearancePicker) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Button(mode.localizedTitle) {
                        appearance.mode = mode
                        AppAnalytics.track(.toggleSetting, parameters: [
                            .settingName: .string("app_appearance"),
                            .settingValue: .string(mode.rawValue)
                        ])
                    }
                }
            }
            .tint(showAppearancePicker ? Color.primary : Theme.accentColor)
            .alert(NSLocalizedString("clear_data", comment: ""), isPresented: $showClearConfirm) {
                Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) { }
                Button(NSLocalizedString("clear_data", comment: ""), role: .destructive) {
                    clearAllData()
                }
            } message: {
                Text(NSLocalizedString("clear_all_records_message", comment: ""))
            }
            .alert(
                NSLocalizedString("clear_data_failed_title", value: "Clear Failed", comment: ""),
                isPresented: clearDataErrorPresented
            ) {
                Button(NSLocalizedString("confirm", value: "OK", comment: "")) {
                    clearDataErrorMessage = nil
                }
            } message: {
                Text(clearDataErrorMessage ?? "")
            }
        }
        .sheet(item: $activeSheet) { destination in
            SettingsFormSheet(destination: destination)
                .presentationSizing(.form)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAppShareSheet) {
            AnalyticsActivityView(activityItems: [AppSupportURLs.website], contentType: "app_link")
        }
    }

    private var clearDataErrorPresented: Binding<Bool> {
        Binding(
            get: { clearDataErrorMessage != nil },
            set: { if !$0 { clearDataErrorMessage = nil } }
        )
    }

    private func clearAllData() {
        ScoreboardRecordManager.shared.clearAllRecords()
        _ = TimerRecordManager.shared.clearAllRecords()
        _ = LocalBookingManager.shared.clearAllBookings()
        CommonNamesManager.shared.clearNames(type: .team)
        CommonNamesManager.shared.clearNames(type: .player)
        CommonPlacesManager.shared.clearAll()
        ScoreboardRecordsViewModel.shared.refreshRecordsImmediately()
        TimerRecordsViewModel.shared.loadFromStorage()
        Task {
            do {
                try await ResumeSessionRepository().clear()
                trackClearDataResult(.success)
            } catch {
                clearDataErrorMessage = String(
                    format: NSLocalizedString(
                        "clear_data_failed_format",
                        value: "Some resume data could not be cleared: %@",
                        comment: "Clear data failure with the underlying error"
                    ),
                    error.localizedDescription
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

    @ViewBuilder
    private func settingsDestinationRow<Destination: View>(
        _ destination: SettingsSheetDestination,
        title: String,
        @ViewBuilder content: () -> Destination
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
            NavigationLink {
                content()
            } label: {
                SettingsNavigationRow(title: title)
            }
            .simultaneousGesture(TapGesture().onEnded {
                AppAnalytics.openPage(from: .meTab, to: destination.analyticsScreen, entryPoint: .meTab)
            })
            .accessibilityIdentifier(destination.entryAccessibilityIdentifier)
        }
    }

    private var settingsRowDivider: some View {
        Divider()
            .overlay(Theme.divider)
            .opacity(0.45)
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
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(NSLocalizedString("close", value: "关闭", comment: "Close form sheet"))
                        .accessibilityIdentifier(destination.closeAccessibilityIdentifier)
                    }
                }
        }
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
        }
    }
}

private extension SettingsSheetDestination {
    var analyticsScreen: AnalyticsScreen {
        switch self {
        case .scoreboardSettings: return .scoreboardSettingsPage
        case .faq: return .faqPage
        case .about: return .aboutUsPage
        }
    }
}

struct MeTab: View {
    var body: some View {
        SettingsView(isTabRoot: true)
    }
}

// MARK: - Supporting Views

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionContentSpacing) {
            Text(title)
                .font(.system(size: Theme.fontBody2, weight: .regular))
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 4)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.appCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .stroke(Theme.divider.opacity(0.7), lineWidth: 0.5)
                }
        }
    }
}

private struct SettingsNavigationRow: View {
    let title: String
    var value: String? = nil

    var body: some View {
        HStack(spacing: Theme.sm) {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(Theme.textPrimary)
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
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

private struct ScoreboardSettingsView: View {
    @State private var selectedTheme = ScoreboardTheme(rawValue: PreferencesManager.shared.scoreboardTheme) ?? .defaultTheme
    @State private var selectedFont = PreferencesManager.shared.resolvedDefaultScoreboardFont
    @State private var forceIPadLandscape = PreferencesManager.shared.forceIPadLandscape
    @State private var keepScreenOn = PreferencesManager.shared.keepScoreboardScreenOn
    @State private var soundEnabled = PreferencesManager.shared.soundEnabled
    @State private var vibrationEnabled = PreferencesManager.shared.vibrationEnabled
    @State private var immersiveMode = PreferencesManager.shared.scoreboardImmersiveModeEnabled
    @State private var touchGuard = PreferencesManager.shared.scoreboardTouchGuardEnabled
    @State private var doubleTapSubtract = PreferencesManager.shared.scoreboardDoubleTapSubtractEnabled
    @State private var helpTopic: ScoreboardSettingHelp?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.lg) {
                SettingsSection(title: NSLocalizedString("scoreboard_settings_appearance", value: "外观", comment: "")) {
                    VStack(alignment: .leading, spacing: 0) {
                        ScoreboardThemeSelector(selection: $selectedTheme)
                            .padding(Theme.md)
                        Divider().overlay(Theme.divider)
                        ScoreboardFontSelector(selection: $selectedFont)
                            .padding(Theme.md)
                    }
                }

                SettingsSection(title: NSLocalizedString("scoreboard_settings_experience", value: "计分体验", comment: "")) {
                    VStack(spacing: 0) {
                        if Theme.usesPadLayout {
                            ScoreboardToggleSettingRow(
                                title: NSLocalizedString("scoreboard_force_ipad_landscape", value: "iPad 强制横屏", comment: ""),
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
                            title: NSLocalizedString("sound", value: "声音", comment: ""),
                            isOn: $soundEnabled,
                            toggleAccessibilityIdentifier: "scoreboard_sound_toggle"
                        )
                        Divider().overlay(Theme.divider)
                        ScoreboardToggleSettingRow(
                            title: NSLocalizedString("vibration", value: "振动", comment: ""),
                            isOn: $vibrationEnabled,
                            toggleAccessibilityIdentifier: "scoreboard_vibration_toggle"
                        )
                        Divider().overlay(Theme.divider)
                        ScoreboardToggleSettingRow(
                            title: NSLocalizedString("scoreboard_immersive_mode", value: "沉浸模式", comment: ""),
                            isOn: $immersiveMode,
                            toggleAccessibilityIdentifier: "scoreboard_immersive_mode_toggle",
                            helpAction: { helpTopic = .immersive }
                        )
                        Divider().overlay(Theme.divider)
                        ScoreboardToggleSettingRow(
                            title: NSLocalizedString("scoreboard_touch_guard", value: "触摸防误触", comment: ""),
                            isOn: $touchGuard,
                            toggleAccessibilityIdentifier: "scoreboard_touch_guard_toggle",
                            helpAction: { helpTopic = .touchGuard }
                        )
                        Divider().overlay(Theme.divider)
                        ScoreboardToggleSettingRow(
                            title: NSLocalizedString("scoreboard_double_tap_subtract", value: "双击减分", comment: ""),
                            isOn: $doubleTapSubtract,
                            toggleAccessibilityIdentifier: "scoreboard_double_tap_subtract_toggle",
                            helpAction: { helpTopic = .doubleTapSubtract }
                        )
                    }
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
        .onChange(of: selectedTheme) { _, value in
            PreferencesManager.shared.scoreboardTheme = value.rawValue
            trackSetting("scoreboard_theme", value.rawValue)
        }
        .onChange(of: selectedFont) { _, value in
            PreferencesManager.shared.defaultScoreboardFont = value.rawValue
            trackSetting("scoreboard_font", value.rawValue)
        }
        .onChange(of: forceIPadLandscape) { _, value in
            PreferencesManager.shared.forceIPadLandscape = value
            trackSetting("force_ipad_landscape", value)
        }
        .onChange(of: keepScreenOn) { _, value in
            PreferencesManager.shared.keepScoreboardScreenOn = value
            trackSetting("keep_screen_on", value)
        }
        .onChange(of: soundEnabled) { _, value in
            PreferencesManager.shared.soundEnabled = value
            trackSetting("sound_enabled", value)
        }
        .onChange(of: vibrationEnabled) { _, value in
            PreferencesManager.shared.vibrationEnabled = value
            trackSetting("vibration_enabled", value)
        }
        .onChange(of: immersiveMode) { _, value in
            PreferencesManager.shared.scoreboardImmersiveModeEnabled = value
            trackSetting("immersive_mode", value)
        }
        .onChange(of: touchGuard) { _, value in
            PreferencesManager.shared.scoreboardTouchGuardEnabled = value
            trackSetting("touch_guard", value)
        }
        .onChange(of: doubleTapSubtract) { _, value in
            PreferencesManager.shared.scoreboardDoubleTapSubtractEnabled = value
            trackSetting("double_tap_subtract", value)
        }
        .alert(item: $helpTopic) { topic in
            Alert(title: Text(topic.title), message: Text(topic.message), dismissButton: .default(Text(NSLocalizedString("got_it", value: "知道了", comment: ""))))
        }
    }

    private func trackSetting(_ name: String, _ value: Bool) {
        trackSetting(name, value ? "enabled" : "disabled")
    }

    private func trackSetting(_ name: String, _ value: String) {
        AppAnalytics.track(.toggleSetting, parameters: [
            .settingName: .string(name),
            .settingValue: .string(value)
        ])
    }
}

private enum ScoreboardSettingHelp: String, Identifiable {
    case immersive
    case touchGuard
    case doubleTapSubtract

    var id: String { rawValue }

    var title: String {
        switch self {
        case .immersive: return NSLocalizedString("scoreboard_immersive_help_title", value: "沉浸模式", comment: "")
        case .touchGuard: return NSLocalizedString("scoreboard_touch_guard_help_title", value: "触摸防误触", comment: "")
        case .doubleTapSubtract: return NSLocalizedString("scoreboard_double_tap_help_title", value: "双击减分", comment: "")
        }
    }

    var message: String {
        switch self {
        case .immersive:
            return NSLocalizedString("scoreboard_immersive_help_message", value: "进入计分板后，角落操作按钮会自动隐藏。点击角落可再次显示。", comment: "")
        case .touchGuard:
            return NSLocalizedString("scoreboard_touch_guard_help_message", value: "仅点击比分数字附近时才会计分，减少握持和擦拭屏幕时的误触。", comment: "")
        case .doubleTapSubtract:
            return NSLocalizedString("scoreboard_double_tap_help_message", value: "开启后，快速双击某一方的比分区域会减 1 分。仅适用于部分计分板。", comment: "")
        }
    }
}

private struct ScoreboardThemePreviewSwatch: View {
    let theme: ScoreboardTheme

    var body: some View {
        HStack(spacing: 0) {
            themePreviewHalf(color: theme.palette.left, sample: "0")
            themePreviewHalf(color: theme.palette.right, sample: "0")
        }
        .frame(height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    @ViewBuilder
    private func themePreviewHalf(color: Color, sample: String) -> some View {
        ZStack {
            color
            Text(sample)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(theme.palette.foreground)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ScoreboardThemeSelector: View {
    @Binding var selection: ScoreboardTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("scoreboard_theme", value: "计分板主题", comment: ""))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Theme.textPrimary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(ScoreboardTheme.allCases) { theme in
                    Button { selection = theme } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ScoreboardThemePreviewSwatch(theme: theme)
                            HStack {
                                Text(theme.localizedTitle)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Theme.textPrimary)
                                Spacer()
                                if selection == theme {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Theme.accentColor)
                                }
                            }
                        }
                        .padding(9)
                        .background(Theme.controlBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(selection == theme ? Theme.accentColor : Theme.divider.opacity(0.5), lineWidth: selection == theme ? 2 : 0.5)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ScoreboardFontSelector: View {
    @Binding var selection: ScoreboardFont

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("scoreboard_default_font", value: "默认比分字体", comment: ""))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Theme.textPrimary)
            ForEach(ScoreboardFont.allCases) { font in
                Button { selection = font } label: {
                    HStack(spacing: 12) {
                        Text("88:88")
                            .font(font.swiftUIFont(size: 24))
                            .foregroundColor(Theme.textPrimary)
                            .frame(width: 92, alignment: .leading)
                        Text(font.localizedTitle)
                            .font(.system(size: 15))
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Image(systemName: selection == font ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selection == font ? Theme.accentColor : Theme.textSecondary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ScoreboardToggleSettingRow: View {
    let title: String
    @Binding var isOn: Bool
    let toggleAccessibilityIdentifier: String
    var helpAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 16))
                .foregroundColor(Theme.textPrimary)
            if let helpAction {
                Button(action: helpAction) {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(toggleAccessibilityIdentifier)_help")
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .accessibilityIdentifier(toggleAccessibilityIdentifier)
        }
        .padding(.horizontal, Theme.md)
        .frame(minHeight: 56)
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
            VStack(spacing: Theme.sm) {
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
                    VStack(spacing: Theme.sm) {
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
                        Link(destination: AppSupportURLs.terms) {
                            SettingsNavigationRow(title: NSLocalizedString("terms_of_service", value: "用户协议", comment: ""))
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            AppAnalytics.openPage(from: .aboutUsPage, to: .legalWebPage)
                        })
                        .accessibilityIdentifier("settings_about_terms_link")
                        Divider().overlay(Theme.divider)
                        Link(destination: AppSupportURLs.privacy) {
                            SettingsNavigationRow(title: NSLocalizedString("privacy_policy", value: "隐私政策", comment: ""))
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            AppAnalytics.openPage(from: .aboutUsPage, to: .legalWebPage)
                        })
                        .accessibilityIdentifier("settings_about_privacy_link")
                        Divider().overlay(Theme.divider)
                        Link(destination: AppSupportURLs.feedback) {
                            SettingsNavigationRow(title: NSLocalizedString("about_feedback_row", value: "意见反馈", comment: ""))
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            AppAnalytics.openPage(from: .aboutUsPage, to: .feedbackPage)
                        })
                        .accessibilityIdentifier("settings_about_feedback_link")
                        Divider().overlay(Theme.divider)
                        Link(destination: AppSupportURLs.wechatGroup) {
                            SettingsNavigationRow(title: NSLocalizedString("about_wechat_group", value: "微信群", comment: ""))
                        }
                        .accessibilityIdentifier("settings_about_wechat_link")
                        Divider().overlay(Theme.divider)
                        qqGroupRow
                    }
                    .background(Theme.appCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
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

    private var companyDisplayName: String {
        let isChinese = Locale.current.language.languageCode?.identifier.hasPrefix("zh") == true
        return isChinese
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

struct LinkRow: View {
    let title: String
    let icon: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(Theme.accentColor)
                    .frame(width: 24, height: 24)

                Text(title)
                    .foregroundColor(Theme.textPrimary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsView()
}
