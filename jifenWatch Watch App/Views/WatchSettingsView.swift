import SwiftUI

struct WatchSettingsView: View {
    @AppStorage("watch_vibration_enabled") private var vibrationEnabled: Bool = true
    @AppStorage("watch_sound_enabled") private var soundEnabled: Bool = true
    @AppStorage("watch_set_break_enabled") private var setBreakEnabled: Bool = true
    @State private var scoreboardLayout: String = "horizontal"
    @State private var showUsageAlert: Bool = false
    @State private var showRecordSyncHelp: Bool = false

    private let appVersion = "v2.0.0"

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                settingRow(title: NSLocalizedString("vibration", comment: "Vibration"), isOn: $vibrationEnabled)
                settingRow(title: NSLocalizedString("sound", comment: "Sound"), isOn: $soundEnabled)
                settingRow(
                    title: NSLocalizedString("watch_rest_between_sets", value: "局间休息", comment: ""),
                    isOn: $setBreakEnabled
                )
                layoutRow()
                recordSyncInfoRow()
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
            .padding(.horizontal, WatchLayout.tabHorizontalPadding)
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
        .onAppear {
            scoreboardLayout = WatchPreferences.shared.scoreboardLayout
            setBreakEnabled = WatchPreferences.shared.setBreakEnabled
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchScoreboardLayoutDidChange)) { _ in
            scoreboardLayout = WatchPreferences.shared.scoreboardLayout
        }
        .alert(NSLocalizedString("usage_guide", comment: "Usage Guide"), isPresented: $showUsageAlert) {
            Button(NSLocalizedString("got_it", comment: "Got it"), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("usage_prompt_message", comment: "Usage prompt message"))
        }
        .alert(
            NSLocalizedString("watch_record_auto_sync_title", value: "记录自动回传", comment: ""),
            isPresented: $showRecordSyncHelp
        ) {
            Button(NSLocalizedString("got_it", comment: "Got it"), role: .cancel) { }
        } message: {
            Text(NSLocalizedString(
                "watch_record_auto_sync_help",
                value: "羽/乒/网/匹、射箭、黑八/追分/斯诺克完赛后自动回传到手机；投篮训练仅保存在手表。",
                comment: ""
            ))
        }
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

    private func recordSyncInfoRow() -> some View {
        Button {
            showRecordSyncHelp = true
        } label: {
            HStack {
                Text(NSLocalizedString("watch_record_auto_sync_title", value: "记录自动回传", comment: ""))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(WatchTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Text(NSLocalizedString("watch_record_auto_sync_on", value: "已开启", comment: ""))
                    .font(.system(size: 14))
                    .foregroundColor(WatchTheme.secondaryText)
                Image(systemName: "questionmark.circle")
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
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(WatchTheme.accent)
        }
        .padding(.horizontal, WatchLayout.pillRowHorizontalPadding)
        .frame(height: WatchMetrics.pillHeight)
        .background(WatchTheme.listItemBackground)
        .cornerRadius(WatchMetrics.pillRadius)
    }
}
