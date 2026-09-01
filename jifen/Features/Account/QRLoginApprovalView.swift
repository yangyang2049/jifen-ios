import SwiftUI
import Vision
import VisionKit

nonisolated struct QRLoginPayload: Decodable, Equatable, Sendable {
    var type: String
    var version: Int
    var sessionId: String
    var scanToken: String
    var apiBaseUrl: String?
    var targetPlatform: String?
    var expiresAt: Int64?

    static func parse(_ raw: String) throws -> QRLoginPayload {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let payload = try? JSONDecoder().decode(Self.self, from: data) {
            try payload.validate()
            return payload
        }
        guard let components = URLComponents(string: trimmed),
              components.scheme == "https",
              components.host == "jifenqi.com" || components.host == "www.jifenqi.com",
              components.path == "/auth/qr",
              let fragment = components.fragment,
              let values = URLComponents(string: "?\(fragment)")?.queryItems,
              let sessionId = values.first(where: { $0.name == "sid" })?.value,
              let scanToken = values.first(where: { $0.name == "st" })?.value
        else { throw QRLoginError.invalidPayload }
        let payload = Self(
            type: "AUTH_QR_LOGIN",
            version: 1,
            sessionId: sessionId,
            scanToken: scanToken,
            apiBaseUrl: nil,
            targetPlatform: nil,
            expiresAt: nil
        )
        try payload.validate()
        return payload
    }

    private func validate() throws {
        let sessionPattern = /^[A-Za-z0-9_-]{10,128}$/
        let tokenPattern = /^qrl_scan_[A-Za-z0-9_-]{43}$/
        guard type == "AUTH_QR_LOGIN", version == 1,
              sessionId.wholeMatch(of: sessionPattern) != nil,
              scanToken.wholeMatch(of: tokenPattern) != nil
        else { throw QRLoginError.invalidPayload }
        if let apiBaseUrl {
            let allowed = APIEnvironment.current.restBaseURL.appending(path: "/api").absoluteString
            guard apiBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ==
                    allowed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            else { throw QRLoginError.untrustedServer }
        }
        if let expiresAt, expiresAt <= Int64(Date().timeIntervalSince1970 * 1000) {
            throw QRLoginError.expired
        }
    }
}

nonisolated enum QRLoginError: LocalizedError {
    case invalidPayload
    case untrustedServer
    case expired

    var errorDescription: String? {
        switch self {
        case .invalidPayload: NSLocalizedString("qr_login_invalid", value: "不是有效的计分器登录二维码", comment: "")
        case .untrustedServer: NSLocalizedString("qr_login_untrusted", value: "二维码来自未受信任的服务器", comment: "")
        case .expired: NSLocalizedString("qr_login_expired", value: "二维码已过期", comment: "")
        }
    }
}

nonisolated private struct QRScanResponse: Decodable, Sendable {
    var status: String
    var sessionId: String?
    var targetPlatform: String?
    var targetDeviceName: String?
    var expiresAt: String?
}

nonisolated private struct QRConfirmResponse: Decodable, Sendable {
    var status: String
    var message: String?
}

struct QRLoginApprovalView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var parsed: QRLoginPayload?
    @State private var scanResponse: QRScanResponse?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var scannerPaused = false

    var body: some View {
        ZStack {
            Theme.backgroundColor.ignoresSafeArea()
            if let parsed, let scanResponse {
                confirmContent(scanResponse, fallbackPlatform: parsed.targetPlatform)
            } else if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                scannerContent
            } else {
                // 相机不可用（不支持/权限被拒）时的占位提示。
                cameraUnavailablePlaceholder
            }
        }
        .navigationTitle(NSLocalizedString("qr_login_title", value: "扫码登录", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .overlay { if isWorking { ProgressView().controlSize(.large) } }
        .overlay(alignment: .top) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
            }
        }
    }

    // 扫码态：相机全屏 + 通栏底部渐变提示横幅。
    private var scannerContent: some View {
        QRDataScannerView(paused: scannerPaused) { raw in
            Task { await receive(raw) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .bottom) { scanHintBanner }
    }

    private var scanHintBanner: some View {
        Text(NSLocalizedString("qr_login_scan_hint", value: "对准网页上的登录二维码", comment: ""))
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 46)
            .padding(.bottom, 30)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .accessibilityIdentifier("qr_login_scan_hint")
    }

    // 确认态：App 徽标 + 设备信息大卡 + 全宽胶囊按钮（对齐方案 A demo）。
    private func confirmContent(_ scanResponse: QRScanResponse, fallbackPlatform: String?) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 10)
            appLogoBadge
                .padding(.bottom, 22)
            Text(NSLocalizedString("qr_login_confirm_title", value: "确认网页登录", comment: ""))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(NSLocalizedString("qr_login_confirm_subtitle", value: "以下设备请求登录你的计分器账号", comment: ""))
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 8)
            deviceCard(scanResponse, fallbackPlatform: fallbackPlatform)
                .padding(.top, 22)
            Spacer()
            HStack(spacing: 12) {
                Button {
                    Task { await confirm(approve: false) }
                } label: {
                    Text(NSLocalizedString("deny", value: "拒绝", comment: ""))
                        .font(.system(size: 16.5, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Theme.divider.opacity(0.45), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isWorking)

                Button {
                    Task { await confirm(approve: true) }
                } label: {
                    Text(NSLocalizedString("approve", value: "确认登录", comment: ""))
                        .font(.system(size: 16.5, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Theme.accentColor, in: Capsule())
                        .shadow(color: Theme.accentColor.opacity(0.35), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
                .accessibilityIdentifier("qr_login_approve_button")
            }
            Text(NSLocalizedString("qr_login_confirm_fine_print", value: "确认后网页端将立即进入你的账号", comment: ""))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 14)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // App 徽标：复用应用图标（自动适配亮/暗外观）。
    private var appLogoBadge: some View {
        Image("AppLogo")
            .resizable()
            .scaledToFill()
            .frame(width: 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Theme.divider.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
    }

    private func deviceCard(_ scanResponse: QRScanResponse, fallbackPlatform: String?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Theme.accentColor)
                .frame(width: 52, height: 52)
                .background(Theme.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(NSLocalizedString("qr_login_confirm_device_label", value: "登录设备", comment: ""))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                Text(scanResponse.targetDeviceName ?? readablePlatform(scanResponse.targetPlatform ?? fallbackPlatform))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color(hex: "22C55E"))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.controlBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.divider.opacity(0.6), lineWidth: 1)
        )
    }

    // 相机不可用（不支持/权限被拒）时的占位提示。
    private var cameraUnavailablePlaceholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.on.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textSecondary)
            Text(NSLocalizedString("qr_login_camera_unavailable", value: "相机不可用", comment: ""))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(NSLocalizedString("qr_login_camera_unavailable_hint", value: "请在系统设置中允许使用相机后重试", comment: ""))
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func receive(_ raw: String) async {
        guard !isWorking, parsed == nil else { return }
        isWorking = true
        scannerPaused = true
        defer { isWorking = false }
        do {
            let payload = try QRLoginPayload.parse(raw)
            struct Body: Encodable, Sendable { var scanToken: String }
            let response: QRScanResponse = try await APIClient.shared.request(
                "/api/auth/qr/sessions/\(payload.sessionId)/scan",
                method: .post,
                body: Body(scanToken: payload.scanToken),
                requiresAuth: true
            )
            parsed = payload
            scanResponse = response
            errorMessage = nil
        } catch {
            scannerPaused = false
            errorMessage = error.localizedDescription
        }
    }

    private func confirm(approve: Bool) async {
        guard let parsed else { return }
        isWorking = true
        defer { isWorking = false }
        struct Body: Encodable, Sendable { var scanToken: String; var action: String }
        do {
            let _: QRConfirmResponse = try await APIClient.shared.request(
                "/api/auth/qr/sessions/\(parsed.sessionId)/confirm",
                method: .post,
                body: Body(scanToken: parsed.scanToken, action: approve ? "approve" : "deny"),
                requiresAuth: true
            )
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }

    private func readablePlatform(_ value: String?) -> String {
        guard let value else { return NSLocalizedString("qr_login_unknown_device", value: "网页设备", comment: "") }
        return value.replacingOccurrences(of: "_", with: " ")
    }
}

private struct QRDataScannerView: UIViewControllerRepresentable {
    var paused: Bool
    var onValue: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        if paused { controller.stopScanning() } else if !controller.isScanning { try? controller.startScanning() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onValue: onValue) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onValue: (String) -> Void
        init(onValue: @escaping (String) -> Void) { self.onValue = onValue }
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard case .barcode(let barcode) = addedItems.first,
                  let value = barcode.payloadStringValue
            else { return }
            onValue(value)
        }
    }
}

