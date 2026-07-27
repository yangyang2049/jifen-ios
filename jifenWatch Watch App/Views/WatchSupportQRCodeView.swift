import SwiftUI

private enum WatchSupportLink {
    static let feedback = "https://jifenqi.com/feedback"
    static let contact = "https://jifenqi.com/contact"
}

struct WatchFeedbackView: View {
    var body: some View {
        WatchSupportQRCodeView(
            title: NSLocalizedString("watch_feedback", value: "意见反馈", comment: ""),
            link: WatchSupportLink.feedback,
            imageName: "watch_feedback_qr"
        )
    }
}

struct WatchContactView: View {
    var body: some View {
        WatchSupportQRCodeView(
            title: NSLocalizedString("watch_contact_us", value: "联系我们", comment: ""),
            link: WatchSupportLink.contact,
            imageName: "watch_contact_qr"
        )
    }
}

private struct WatchSupportQRCodeView: View {
    let title: String
    let link: String
    let imageName: String

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(imageName)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 130, height: 130)
                    .padding(10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(title)
                    .accessibilityValue(link)

                Text(NSLocalizedString("scan_to_view_details", comment: "Scan to view details"))
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
}
