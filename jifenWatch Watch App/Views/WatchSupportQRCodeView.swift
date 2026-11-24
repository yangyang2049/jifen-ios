import SwiftUI

enum WatchSupportLink {
    static let wechatGroup = "https://c.weixin.com/g/n1ltxDV-Ogi46YYG"

    /// 简体中文使用国内站点 jifenqi.com；其他语言（含繁体中文与外语）使用 iscoreboard.live。
    static func isSimplifiedChinese(locale: Locale = .current) -> Bool {
        let languageCode = locale.language.languageCode?.identifier.lowercased()
        guard languageCode == "zh" else { return false }
        if let script = locale.language.script?.identifier.lowercased() {
            return script == "hans"
        }
        let normalized = locale.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        if normalized.contains("hant")
            || normalized.hasSuffix("-tw")
            || normalized.hasSuffix("-hk")
            || normalized.hasSuffix("-mo") {
            return false
        }
        return true
    }

    /// 用户微信群仅在中文环境（简/繁中文）展示。
    static func showsWeChatGroup(locale: Locale = .current) -> Bool {
        locale.language.languageCode?.identifier.lowercased() == "zh"
    }

    static func feedback(for locale: Locale = .current) -> String {
        isSimplifiedChinese(locale: locale)
            ? "https://jifenqi.com/feedback"
            : "https://iscoreboard.live/feedback"
    }

    static func contact(for locale: Locale = .current) -> String {
        isSimplifiedChinese(locale: locale)
            ? "https://jifenqi.com/contact"
            : "https://iscoreboard.live/contact"
    }

    static func feedbackQRImageName(for locale: Locale = .current) -> String {
        isSimplifiedChinese(locale: locale) ? "watch_feedback_qr" : "watch_feedback_qr_intl"
    }

    static func contactQRImageName(for locale: Locale = .current) -> String {
        isSimplifiedChinese(locale: locale) ? "watch_contact_qr" : "watch_contact_qr_intl"
    }
}

struct WatchFeedbackView: View {
    @Environment(\.locale) private var locale

    var body: some View {
        WatchSupportQRCodeView(
            title: NSLocalizedString("watch_feedback", value: "意见反馈", comment: ""),
            link: WatchSupportLink.feedback(for: locale),
            imageName: WatchSupportLink.feedbackQRImageName(for: locale)
        )
    }
}

struct WatchContactView: View {
    @Environment(\.locale) private var locale

    var body: some View {
        WatchSupportQRCodeView(
            title: NSLocalizedString("watch_contact_us", value: "联系我们", comment: ""),
            link: WatchSupportLink.contact(for: locale),
            imageName: WatchSupportLink.contactQRImageName(for: locale)
        )
    }
}

struct WatchWechatGroupView: View {
    var body: some View {
        WatchSupportQRCodeView(
            title: NSLocalizedString("watch_wechat_group_title", value: "用户微信群", comment: ""),
            link: WatchSupportLink.wechatGroup,
            imageName: "watch_wechat_group_qr",
            hint: NSLocalizedString(
                "watch_wechat_group_scan_hint",
                value: "使用微信扫码加入用户群",
                comment: ""
            ),
            usesPixelInterpolation: false
        )
    }
}

struct WatchSupportQRCodeView: View {
    let title: String
    let link: String
    let imageName: String
    var hint: String = NSLocalizedString("scan_to_view_details", comment: "Scan to view details")
    var usesPixelInterpolation: Bool = true

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                qrImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: 130, height: 130)
                    .padding(usesPixelInterpolation ? 10 : 6)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(title)
                    .accessibilityValue(link)

                Text(hint)
                    .font(.system(size: 12))
                    .foregroundStyle(WatchTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .background(WatchTheme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var qrImage: Image {
        usesPixelInterpolation
            ? Image(imageName).interpolation(.none)
            : Image(imageName).interpolation(.high)
    }
}
