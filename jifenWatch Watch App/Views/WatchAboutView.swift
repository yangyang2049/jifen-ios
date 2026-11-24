import SwiftUI

/// 手表端「关于」页：图标 + 应用名 + 版本 + 公司。
/// 对齐鸿蒙 `WatchAboutPage.ets`；版本号与设置页同源读 Info.plist。
struct WatchAboutView: View {
    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard !short.isEmpty else { return "" }
        return short.hasPrefix("v") ? short : "v" + short
    }

    private var appName: String {
        NSLocalizedString("watch_about_app_name", value: "全能计分器", comment: "")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image("AppIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text(appName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(WatchTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if !appVersion.isEmpty {
                    Text(String(
                        format: NSLocalizedString("watch_about_version", value: "版本 %@", comment: ""),
                        appVersion
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(WatchTheme.secondaryText)
                    .lineLimit(1)
                }

                Text(NSLocalizedString("company_name", comment: "Company name"))
                    .font(.system(size: 11))
                    .foregroundStyle(WatchTheme.secondaryText.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .background(WatchTheme.background)
        .navigationTitle(NSLocalizedString("watch_about_us", value: "关于我们", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
}
