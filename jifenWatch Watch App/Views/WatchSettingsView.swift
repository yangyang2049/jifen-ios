import SwiftUI

struct WatchSettingsView: View {
    @AppStorage("watch_vibration_enabled") private var vibrationEnabled: Bool = true
    @AppStorage("watch_sound_enabled") private var soundEnabled: Bool = true
    @AppStorage("watch_set_break_enabled") private var setBreakEnabled: Bool = true
    @AppStorage(WatchPreferences.scoreboardKeepScreenOnKey) private var scoreboardKeepScreenOn: Bool = true
    @State private var scoreboardLayout: String = "horizontal"
    @State private var showUsageAlert: Bool = false

    private let appVersion = "v2.0.0"

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                navigationRow(
                    title: NSLocalizedString("watch_common_names_title", value: "常用名称", comment: "")
                ) {
                    WatchCommonNamesView()
                }
                navigationRow(
                    title: NSLocalizedString("watch_phone_link_title", value: "手机联动", comment: "")
                ) {
                    WatchPhoneLinkView()
                }
                settingRow(title: NSLocalizedString("vibration", comment: "Vibration"), isOn: $vibrationEnabled)
                settingRow(title: NSLocalizedString("sound", comment: "Sound"), isOn: $soundEnabled)
                settingRow(
                    title: NSLocalizedString(
                        "watch_scoreboard_keep_screen_on",
                        value: "计分时常亮",
                        comment: ""
                    ),
                    isOn: $scoreboardKeepScreenOn
                )
                settingRow(
                    title: NSLocalizedString("watch_rest_between_sets", value: "局间休息", comment: ""),
                    isOn: $setBreakEnabled
                )
                layoutRow()
                usageGuideRow()

                Spacer(minLength: 16)

                VStack(spacing: 6) {
                    Text(appVersion)
                        .font(.system(size: 12))
                        .foregroundColor(WatchTheme.secondaryText)
                    Text(NSLocalizedString("company_name", comment: "Company name"))
                        .font(.system(size: 11))
                        .foregroundColor(WatchTheme.secondaryText.opacity(0.9))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .padding(.horizontal, WatchLayout.pageHorizontalPadding)
            .padding(.bottom, 12)
        }
        .background(WatchTheme.background)
        .navigationTitle(NSLocalizedString("setup", comment: "Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: vibrationEnabled) { _, newValue in
            WatchPreferences.shared.vibrationEnabled = newValue
        }
        .onChange(of: soundEnabled) { _, newValue in
            WatchPreferences.shared.soundEnabled = newValue
        }
        .onChange(of: setBreakEnabled) { _, newValue in
            WatchPreferences.shared.setBreakEnabled = newValue
        }
        .onChange(of: scoreboardKeepScreenOn) { _, newValue in
            WatchPreferences.shared.scoreboardKeepScreenOn = newValue
        }
        .onAppear {
            scoreboardLayout = WatchPreferences.shared.scoreboardLayout
            setBreakEnabled = WatchPreferences.shared.setBreakEnabled
            scoreboardKeepScreenOn = WatchPreferences.shared.scoreboardKeepScreenOn
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            scoreboardLayout = WatchPreferences.shared.scoreboardLayout
        }
        .alert(NSLocalizedString("usage_guide", comment: "Usage Guide"), isPresented: $showUsageAlert) {
            Button(NSLocalizedString("got_it", comment: "Got it"), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("usage_prompt_message", comment: "Usage prompt message"))
        }
    }

    private func navigationRow<Destination: View>(
        title: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(WatchTheme.primaryText)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WatchTheme.secondaryText)
            }
            .padding(.horizontal, WatchLayout.pillRowHorizontalPadding)
            .frame(height: WatchMetrics.pillHeight)
            .background(WatchTheme.listItemBackground)
            .cornerRadius(WatchMetrics.pillRadius)
        }
        .buttonStyle(.plain)
    }

    private func usageGuideRow() -> some View {
        Button {
            showUsageAlert = true
        } label: {
            HStack {
                Text(NSLocalizedString("usage_guide", comment: "Usage Guide"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(WatchTheme.primaryText)
                Spacer()
                Image(systemName: "info.circle")
                    .font(.system(size: 16))
                    .foregroundColor(WatchTheme.secondaryText)
            }
            .padding(.horizontal, WatchLayout.pillRowHorizontalPadding)
            .frame(height: WatchMetrics.pillHeight)
            .background(WatchTheme.listItemBackground)
            .cornerRadius(WatchMetrics.pillRadius)
        }
        .buttonStyle(.plain)
    }

    private func layoutRow() -> some View {
        Button {
            let nextLayout = scoreboardLayout == "horizontal" ? "vertical" : "horizontal"
            WatchPreferences.shared.scoreboardLayout = nextLayout
            scoreboardLayout = WatchPreferences.shared.scoreboardLayout
        } label: {
            HStack {
                Text(NSLocalizedString("watch_settings_layout_title", comment: "Scoreboard layout"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(WatchTheme.primaryText)
                Spacer()
                Text(scoreboardLayout == "horizontal"
                     ? NSLocalizedString("watch_layout_horizontal", comment: "Horizontal")
                     : NSLocalizedString("watch_layout_vertical", comment: "Vertical"))
                    .font(.system(size: 14))
                    .foregroundColor(WatchTheme.secondaryText)
            }
            .padding(.horizontal, WatchLayout.pillRowHorizontalPadding)
            .frame(height: WatchMetrics.pillHeight)
            .background(WatchTheme.listItemBackground)
            .cornerRadius(WatchMetrics.pillRadius)
        }
        .buttonStyle(.plain)
    }

    private func settingRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(WatchTheme.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .layoutPriority(1)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(WatchTheme.accent)
                .fixedSize()
        }
        .padding(.horizontal, WatchLayout.pillRowHorizontalPadding)
        .frame(height: WatchMetrics.pillHeight)
        .background(WatchTheme.listItemBackground)
        .cornerRadius(WatchMetrics.pillRadius)
    }
}
