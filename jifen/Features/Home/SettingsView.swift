import SwiftUI

private enum AppSupportURLs {
    static let support = "https://douhua.fan/jifenqi/contact"
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var vibrationEnabled: Bool = true

    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Theme.backgroundColor : Theme.homeBackgroundLight).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Settings sections
                        VStack(spacing: 24) {
                            // Accessibility Section
                            SettingsSection(title: NSLocalizedString("accessibility", comment: "Accessibility")) {
                                VStack(spacing: 0) {
                                    ToggleRow(
                                        title: NSLocalizedString("vibration", comment: "Vibration"),
                                        isOn: $vibrationEnabled,
                                        icon: "waveform"
                                    )
                                }
                            }

                            // About Section
                            SettingsSection(title: NSLocalizedString("about", comment: "About")) {
                                VStack(spacing: 0) {
                                    if let url = URL(string: AppSupportURLs.support) {
                                        LinkRow(
                                            title: NSLocalizedString("support_contact", comment: "Support & Contact"),
                                            icon: "envelope.fill",
                                            url: url
                                        )
                                    }
                                    InfoRow(
                                        title: NSLocalizedString("version", comment: "Version"),
                                        value: getAppVersion(),
                                        icon: "info.circle.fill"
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 24)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("settings", comment: "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
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
    }

    private func getAppVersion() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return version
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
                .font(.system(size: Theme.fontH5, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 4)

            content
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
