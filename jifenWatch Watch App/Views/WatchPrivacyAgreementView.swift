import SwiftUI
#if canImport(CoreImage)
import CoreImage
import CoreImage.CIFilterBuiltins
#endif

struct WatchPrivacyAgreementView: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var qrImage: Image? = nil
    @State private var isGenerating: Bool = false

    private let agreementURL = "https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=1813773073430649408"

    var body: some View {
        VStack(spacing: 12) {
            Text(NSLocalizedString("privacy_policy", comment: "Privacy Policy"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(WatchTheme.primaryText)
                .padding(.top, 8)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white)

                if let qrImage = qrImage {
                    qrImage
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding(8)
                } else {
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(WatchTheme.primaryText)
                        Text(isGenerating ? NSLocalizedString("generating_qr_code", comment: "Generating QR code") : NSLocalizedString("loading_failed", comment: "Loading failed"))
                            .font(.system(size: 10))
                            .foregroundColor(WatchTheme.secondaryText)
                    }
                }
            }
            .frame(width: 120, height: 120)

            Text(NSLocalizedString("scan_to_view_details", comment: "Scan to view details"))
                .font(.system(size: 10))
                .foregroundColor(WatchTheme.secondaryText)

            Button(action: onConfirm) {
                Text(NSLocalizedString("confirm", comment: "Confirm"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 120, height: 28)
                    .background(WatchTheme.accent)
                    .cornerRadius(8)
            }

            Button(action: onCancel) {
                Text(NSLocalizedString("cancel", comment: "Cancel"))
                    .font(.system(size: 12))
                    .foregroundColor(WatchTheme.secondaryText)
                    .frame(width: 120, height: 28)
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WatchTheme.background)
        .onAppear {
            generateQRCode()
        }
    }

    private func generateQRCode() {
        guard qrImage == nil else { return }
        isGenerating = true
        #if canImport(CoreImage)
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(agreementURL.utf8), forKey: "inputMessage")
        filter.correctionLevel = "M"
        if let output = filter.outputImage,
           let cgImage = context.createCGImage(output.transformed(by: CGAffineTransform(scaleX: 10, y: 10)), from: output.extent) {
            qrImage = Image(decorative: cgImage, scale: 1)
        }
        #endif
        isGenerating = false
    }
}
