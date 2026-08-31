import AuthenticationServices
import CryptoKit
import Foundation
import SwiftUI
import UIKit

@MainActor
protocol AccountIdentityProviding {
    var providerID: AccountIdentityProviderID { get }
    func signIn() async throws -> AuthResponse
}

enum AccountIdentityProviderID: String, Sendable {
    case apple
    case wechat
}

enum AccountIdentityProviderAvailability {
    /// WeChat deliberately remains a reserved provider until its iOS SDK and
    /// privacy flow are integrated. It is not rendered or initialized today.
    static let enabled: [AccountIdentityProviderID] = [.apple]
    static let reserved: [AccountIdentityProviderID] = [.wechat]
}

enum AppleAuthError: LocalizedError {
    case stagingTokenRequired
    case cancelled
    case invalidCredential
    case nonceGenerationFailed

    var errorDescription: String? {
        switch self {
        case .stagingTokenRequired:
            NSLocalizedString("staging_token_required", value: "请输入临时测试密钥", comment: "")
        case .cancelled:
            NSLocalizedString("login_cancelled", value: "已取消登录", comment: "")
        case .invalidCredential:
            NSLocalizedString("apple_login_invalid", value: "Apple 登录凭据无效", comment: "")
        case .nonceGenerationFailed:
            NSLocalizedString("apple_login_nonce_failed", value: "无法安全生成 Apple 登录请求，请重试", comment: "")
        }
    }
}

@MainActor
final class ProductionAppleAuthProvider: NSObject, AccountIdentityProviding,
    ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    let providerID: AccountIdentityProviderID = .apple
    private let client: APIClient
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private var rawNonce: String?

    init(client: APIClient = .shared) {
        self.client = client
    }

    func signIn() async throws -> AuthResponse {
        let nonce = try Self.randomNonce()
        rawNonce = nonce
        defer { rawNonce = nil }
        let credential = try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.sha256(nonce)
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
        guard let identityData = credential.identityToken,
              let codeData = credential.authorizationCode,
              let identityToken = String(data: identityData, encoding: .utf8),
              let authorizationCode = String(data: codeData, encoding: .utf8),
              let rawNonce
        else { throw AppleAuthError.invalidCredential }

        #if DEBUG
        print("[AppleAuth] authorization completed; submitting credentials to server")
        #endif

        struct Body: Encodable, Sendable {
            var identityToken: String
            var authorizationCode: String
            var rawNonce: String
            var givenName: String?
            var familyName: String?
        }
        let response: AuthResponse = try await client.request(
            "/api/auth/login/apple",
            method: .post,
            body: Body(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                rawNonce: rawNonce,
                givenName: credential.fullName?.givenName,
                familyName: credential.fullName?.familyName
            )
        )
        #if DEBUG
        print("[AppleAuth] server response decoded; completing local session")
        #endif
        return response
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: AppleAuthError.invalidCredential)
            continuation = nil
            return
        }
        continuation?.resume(returning: credential)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if (error as? ASAuthorizationError)?.code == .canceled {
            continuation?.resume(throwing: AppleAuthError.cancelled)
        } else {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func randomNonce(length: Int = 32) throws -> String {
        guard length > 0 else { throw AppleAuthError.nonceGenerationFailed }
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var bytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            guard status == errSecSuccess else { throw AppleAuthError.nonceGenerationFailed }
            for byte in bytes where remaining > 0 && Int(byte) < alphabet.count {
                result.append(alphabet[Int(byte)])
                remaining -= 1
            }
        }
        return result
    }
}

struct AppleIDButton: UIViewRepresentable {
    var action: () -> Void

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .black)
        button.cornerRadius = 10
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        let action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tap() { action() }
    }
}
