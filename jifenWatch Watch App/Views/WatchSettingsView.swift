import SwiftUI

struct WatchSettingsView: View {
    @AppStorage("watch_vibration_enabled") private var vibrationEnabled: Bool = true
    @AppStorage("watch_sound_enabled") private var soundEnabled: Bool = true
    @State private var scoreboardLayout: String = "vertical"
    @State private var showUsageAlert: Bool = false

    private let appVersion = "v1.0.0"

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                settingRow(title: NSLocalizedString("vibration", comment: "Vibration"), isOn: $vibrationEnabled)
                settingRow(title: NSLocalizedString("sound", comment: "Sound"), isOn: $soundEnabled)
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
            .padding(.horizontal, 12)
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
        .onAppear {
            scoreboardLayout = WatchPreferences.shared.scoreboardLayout
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
            .padding(.horizontal, 16)
            .frame(height: WatchMetrics.pillHeight)
            .background(WatchTheme.listItemBackground)
            .cornerRadius(WatchMetrics.pillRadius)
        }
        .buttonStyle(.plain)
    }

    private func layoutRow() -> some View {
        NavigationLink {
            layoutPickerDestination
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
            .padding(.horizontal, 16)
            .frame(height: WatchMetrics.pillHeight)
            .background(WatchTheme.listItemBackground)
            .cornerRadius(WatchMetrics.pillRadius)
        }
        .buttonStyle(.plain)
    }

    private var layoutPickerDestination: some View {
        List {
            Button {
                WatchPreferences.shared.scoreboardLayout = "vertical"
                scoreboardLayout = WatchPreferences.shared.scoreboardLayout
            } label: {
                HStack {
                    Text(NSLocalizedString("watch_layout_vertical", comment: "Vertical"))
                        .foregroundColor(WatchTheme.primaryText)
                    Spacer()
                    if scoreboardLayout == "vertical" {
                        Image(systemName: "checkmark")
                            .foregroundColor(WatchTheme.accent)
                    }
                }
            }
            .buttonStyle(.plain)
            Button {
                WatchPreferences.shared.scoreboardLayout = "horizontal"
                scoreboardLayout = WatchPreferences.shared.scoreboardLayout
            } label: {
                HStack {
                    Text(NSLocalizedString("watch_layout_horizontal", comment: "Horizontal"))
                        .foregroundColor(WatchTheme.primaryText)
                    Spacer()
                    if scoreboardLayout == "horizontal" {
                        Image(systemName: "checkmark")
                            .foregroundColor(WatchTheme.accent)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle(NSLocalizedString("watch_settings_layout_title", comment: "Scoreboard layout"))
        .navigationBarTitleDisplayMode(.inline)
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
        .padding(.horizontal, 16)
        .frame(height: WatchMetrics.pillHeight)
        .background(WatchTheme.listItemBackground)
        .cornerRadius(WatchMetrics.pillRadius)
    }
}
