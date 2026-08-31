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
    @State private var manualPayload = ""
    @State private var parsed: QRLoginPayload?
    @State private var scanResponse: QRScanResponse?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var scannerPaused = false

    var body: some View {
        VStack(spacing: 18) {
            if let parsed, let scanResponse {
                Image(systemName: "desktopcomputer.and.arrow.down")
                    .font(.system(size: 52))
                Text(NSLocalizedString("qr_login_confirm_title", value: "确认网页登录", comment: ""))
                    .font(.title2.bold())
                Text(scanResponse.targetDeviceName ?? readablePlatform(scanResponse.targetPlatform ?? parsed.targetPlatform))
                    .foregroundStyle(.secondary)
                HStack {
                    Button(NSLocalizedString("deny", value: "拒绝", comment: ""), role: .destructive) {
                        Task { await confirm(approve: false) }
                    }
                    .buttonStyle(.bordered)
                    Button(NSLocalizedString("approve", value: "确认登录", comment: "")) {
                        Task { await confirm(approve: true) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                QRDataScannerView(paused: scannerPaused) { raw in
                    Task { await receive(raw) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(alignment: .bottom) {
                    Text(NSLocalizedString("qr_login_scan_hint", value: "扫描计分器网页上的登录二维码", comment: ""))
                        .font(.footnote)
                        .padding(10)
                        .background(.regularMaterial, in: Capsule())
                        .padding()
                }
            } else {
                manualEntry
            }
            if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
        }
        .padding()
        .navigationTitle(NSLocalizedString("qr_login_title", value: "扫码登录", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .overlay { if isWorking { ProgressView().controlSize(.large) } }
        .safeAreaInset(edge: .bottom) {
            if parsed == nil && DataScannerViewController.isSupported {
                DisclosureGroup(NSLocalizedString("qr_login_manual", value: "手动粘贴二维码内容", comment: "")) {
                    manualEntry
                }
                .padding()
                .background(.thinMaterial)
            }
        }
    }

    private var manualEntry: some View {
        VStack(spacing: 10) {
            TextField(NSLocalizedString("qr_login_payload_placeholder", value: "粘贴二维码内容或链接", comment: ""), text: $manualPayload, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            Button(NSLocalizedString("continue", value: "继续", comment: "")) {
                Task { await receive(manualPayload) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(manualPayload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
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

