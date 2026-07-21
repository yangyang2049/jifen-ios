import PersistenceCore
import StoreKit
import SwiftUI

private enum AppSupportURLs {
    static let website = URL(string: "https://jifenqi.com")!
    static let support = URL(string: "https://jifenqi.com/contact")!
    static let terms = URL(string: "https://jifenqi.com/terms")!
    static let privacy = URL(string: "https://jifenqi.com/privacy")!
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(AppAppearanceStore.self) private var appearance
    var isTabRoot: Bool = false
    @State private var showClearConfirm = false
    @State private var showAppearancePicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundColor.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.lg) {
                        SettingsSection(title: NSLocalizedString("settings_features", value: "功能设置", comment: "")) {
                            VStack(spacing: 0) {
                                NavigationLink { ScoreboardSettingsView() } label: {
                                    SettingsNavigationRow(title: NSLocalizedString("scoreboard_settings_title", value: "计分器设置", comment: ""))
                                }
                                Divider().overlay(Theme.divider)
                                Button { showAppearancePicker = true } label: {
                                    SettingsNavigationRow(
                                        title: NSLocalizedString("appearance", comment: ""),
                                        value: appearance.mode.localizedTitle
                                    )
                                }
                                .buttonStyle(.plain)
                                Divider().overlay(Theme.divider)
                                Button { showClearConfirm = true } label: {
                                    SettingsNavigationRow(title: NSLocalizedString("clear_data", comment: ""))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        SettingsSection(title: NSLocalizedString("settings_help_support", value: "帮助与支持", comment: "")) {
                            VStack(spacing: 0) {
                                Button { requestReview() } label: {
                                    SettingsNavigationRow(title: NSLocalizedString("settings_rate_app", value: "给个好评", comment: ""))
                                }
                                .buttonStyle(.plain)
                                Divider().overlay(Theme.divider)
                                ShareLink(item: AppSupportURLs.website) {
                                    SettingsNavigationRow(title: NSLocalizedString("settings_share_app", value: "分享给朋友", comment: ""))
                                }
                                .buttonStyle(.plain)
                                Divider().overlay(Theme.divider)
                                NavigationLink { FAQView() } label: {
                                    SettingsNavigationRow(title: NSLocalizedString("settings_faq", value: "常见问题", comment: ""))
                                }
                                Divider().overlay(Theme.divider)
                                NavigationLink { AboutUsView() } label: {
                                    SettingsNavigationRow(title: NSLocalizedString("about_us_title", value: "关于我们", comment: ""))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.md)
                    .padding(.vertical, Theme.lg)
                }
            }
            .navigationTitle(NSLocalizedString(isTabRoot ? "tab_me" : "settings", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(isTabRoot ? .visible : .hidden, for: .tabBar)
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
                    Button(mode.localizedTitle) { appearance.mode = mode }
                }
            }
            .tint(showAppearancePicker ? Color.primary : Theme.accentColor)
            .alert(NSLocalizedString("clear_data", comment: ""), isPresented: $showClearConfirm) {
                Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) { }
                Button(NSLocalizedString("clear_data", comment: ""), role: .destructive) {
                    ScoreboardRecordManager.shared.clearAllRecords()
                    Task { try? await SessionArchiveRepository().clear() }
                    _ = TimerRecordManager.shared.clearAllRecords()
                    _ = LocalBookingManager.shared.clearAllBookings()
                    CommonNamesManager.shared.clearNames(type: .team)
                    CommonNamesManager.shared.clearNames(type: .player)
                    CommonPlacesManager.shared.clearAll()
                    ScoreboardRecordsViewModel.shared.refreshRecordsImmediately()
                    TimerRecordsViewModel.shared.loadFromStorage()
                }
            } message: {
                Text(NSLocalizedString("clear_all_records_message", comment: ""))
            }
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
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 4)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
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
        .padding(.horizontal, Theme.md)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

private struct ScoreboardSettingsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTheme = ScoreboardTheme(rawValue: PreferencesManager.shared.scoreboardTheme) ?? .defaultTheme
    @State private var selectedFont = ScoreboardFont(rawValue: PreferencesManager.shared.scoreboardFont) ?? .default
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
                        if UIDevice.current.userInterfaceIdiom == .pad {
                            ScoreboardToggleSettingRow(
                                title: NSLocalizedString("scoreboard_force_ipad_landscape", value: "iPad 强制横屏", comment: ""),
                                isOn: $forceIPadLandscape
                            )
                            Divider().overlay(Theme.divider)
                        }
                        ScoreboardToggleSettingRow(
                            title: NSLocalizedString("scoreboard_keep_screen_on", value: "屏幕常亮", comment: ""),
                            isOn: $keepScreenOn
                        )
                        Divider().overlay(Theme.divider)
                        ScoreboardToggleSettingRow(
                            title: NSLocalizedString("sound", value: "声音", comment: ""),
                            isOn: $soundEnabled
                        )
                        Divider().overlay(Theme.divider)
                        ScoreboardToggleSettingRow(
                            title: NSLocalizedString("vibration", value: "振动", comment: ""),
                            isOn: $vibrationEnabled
                        )
                        Divider().overlay(Theme.divider)
                        ScoreboardToggleSettingRow(
                            title: NSLocalizedString("scoreboard_immersive_mode", value: "沉浸模式", comment: ""),
                            isOn: $immersiveMode,
                            helpAction: { helpTopic = .immersive }
                        )
                        Divider().overlay(Theme.divider)
                        ScoreboardToggleSettingRow(
                            title: NSLocalizedString("scoreboard_touch_guard", value: "触摸防误触", comment: ""),
                            isOn: $touchGuard,
                            helpAction: { helpTopic = .touchGuard }
                        )
                        Divider().overlay(Theme.divider)
                        ScoreboardToggleSettingRow(
                            title: NSLocalizedString("scoreboard_double_tap_subtract", value: "双击减分", comment: ""),
                            isOn: $doubleTapSubtract,
                            helpAction: { helpTopic = .doubleTapSubtract }
                        )
                    }
                }
            }
            .frame(maxWidth: horizontalSizeClass == .regular ? 680 : .infinity)
            .padding(.horizontal, Theme.md)
            .padding(.vertical, Theme.lg)
        }
        .background(Theme.backgroundColor)
        .navigationTitle(NSLocalizedString("scoreboard_settings_title", value: "计分器设置", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedTheme) { _, value in PreferencesManager.shared.scoreboardTheme = value.rawValue }
        .onChange(of: selectedFont) { _, value in PreferencesManager.shared.scoreboardFont = value.rawValue }
        .onChange(of: forceIPadLandscape) { _, value in PreferencesManager.shared.forceIPadLandscape = value }
        .onChange(of: keepScreenOn) { _, value in PreferencesManager.shared.keepScoreboardScreenOn = value }
        .onChange(of: soundEnabled) { _, value in PreferencesManager.shared.soundEnabled = value }
        .onChange(of: vibrationEnabled) { _, value in PreferencesManager.shared.vibrationEnabled = value }
        .onChange(of: immersiveMode) { _, value in PreferencesManager.shared.scoreboardImmersiveModeEnabled = value }
        .onChange(of: touchGuard) { _, value in PreferencesManager.shared.scoreboardTouchGuardEnabled = value }
        .onChange(of: doubleTapSubtract) { _, value in PreferencesManager.shared.scoreboardDoubleTapSubtractEnabled = value }
        .alert(item: $helpTopic) { topic in
            Alert(title: Text(topic.title), message: Text(topic.message), dismissButton: .default(Text(NSLocalizedString("got_it", value: "知道了", comment: ""))))
        }
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
            return NSLocalizedString("scoreboard_double_tap_help_message", value: "开启后，快速双击某一方的比分区域会减 1 分。", comment: "")
        }
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
                            HStack(spacing: 0) {
                                theme.palette.left
                                theme.palette.right
                            }
                            .frame(height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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
            Text(NSLocalizedString("scoreboard_font", value: "比分字体", comment: ""))
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
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
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
        (1...8).map { index in
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
                            }
                        }
                        .padding(Theme.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.md)
        }
        .background(Theme.backgroundColor)
        .navigationTitle(NSLocalizedString("settings_faq", value: "常见问题", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AboutUsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.lg) {
                VStack(spacing: Theme.sm) {
                    Image(systemName: "sportscourt")
                        .font(.system(size: 52))
                        .foregroundColor(Theme.primaryDark)
                    Text(NSLocalizedString("app_name", value: "全能计分器", comment: ""))
                        .font(.title2.weight(.semibold))
                        .foregroundColor(Theme.textPrimary)
                    Text(String(format: NSLocalizedString("about_version_format", value: "版本 %@", comment: ""), appVersion))
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                }
                SettingsSection(title: NSLocalizedString("about_legal", value: "相关信息", comment: "")) {
                    VStack(spacing: 0) {
                        Link(destination: AppSupportURLs.terms) { SettingsNavigationRow(title: NSLocalizedString("terms_of_service", value: "用户协议", comment: "")) }
                        Divider().overlay(Theme.divider)
                        Link(destination: AppSupportURLs.privacy) { SettingsNavigationRow(title: NSLocalizedString("privacy_policy", value: "隐私政策", comment: "")) }
                        Divider().overlay(Theme.divider)
                        Link(destination: AppSupportURLs.support) { SettingsNavigationRow(title: NSLocalizedString("support_contact", value: "联系我们", comment: "")) }
                    }
                }
            }
            .padding(Theme.md)
        }
        .background(Theme.backgroundColor)
        .navigationTitle(NSLocalizedString("about_us_title", value: "关于我们", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
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
