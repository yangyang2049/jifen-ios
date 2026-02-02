import SwiftUI

struct WatchSettingsView: View {
    @AppStorage("watch_vibration_enabled") private var vibrationEnabled: Bool = true
    @AppStorage("watch_sound_enabled") private var soundEnabled: Bool = true

    private let appVersion = "v1.0.0"

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                settingRow(title: NSLocalizedString("vibration", comment: "Vibration"), isOn: $vibrationEnabled)
                settingRow(title: NSLocalizedString("sound", comment: "Sound"), isOn: $soundEnabled)

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
