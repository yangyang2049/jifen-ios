import Foundation
import UIKit
import WechatOpenSDK

nonisolated enum WechatLoginPolicy {
    // 同一微信开放平台移动应用的 iOS / 鸿蒙配置。
    static let appID = "wx945ba56799035847"
    static let universalLink = "https://jifenqi.com/app/"

    static func supports(language: String) -> Bool {
        language.replacingOccurrences(of: "_", with: "-")
            .lowercased().split(separator: "-").first == "zh"
    }
}

enum WechatAuthError: LocalizedError {
    case notInstalled, requestFailed, cancelled, denied, invalidResponse, timeout

    var errorDescription: String? {
        let key: String
        switch self {
        case .notInstalled: key = "login_wechat_not_installed"
        case .requestFailed: key = "login_wechat_request_failed"
        case .cancelled: key = "login_wechat_cancelled"
        case .denied: key = "login_wechat_denied"
        case .invalidResponse: key = "login_wechat_invalid_response"
        case .timeout: key = "login_wechat_timeout"
        }
        return NSLocalizedString(key, comment: "")
    }
}

@MainActor
final class ProductionWechatAuthProvider: NSObject, AccountIdentityProviding, @preconcurrency WXApiDelegate {
    static let shared = ProductionWechatAuthProvider()
    let providerID: AccountIdentityProviderID = .wechat
    private var registered = false
    private var expectedState: String?
    private var continuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?

    static var isInstalled: Bool { WXApi.isWXAppInstalled() }

    // 仅在用户勾选协议并主动登录，或处理微信回调时注册 SDK。
    private func register() -> Bool {
        if !registered {
            registered = WXApi.registerApp(WechatLoginPolicy.appID, universalLink: WechatLoginPolicy.universalLink)
        }
        return registered
    }

    func signIn() async throws -> AuthResponse {
        guard Self.isInstalled else { throw WechatAuthError.notInstalled }
        guard continuation == nil, register() else { throw WechatAuthError.requestFailed }
        let code: String = try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let state = UUID().uuidString
            expectedState = state
            let request = SendAuthReq()
            request.scope = "snsapi_userinfo"
            request.state = state
            timeoutTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                self?.finish(.failure(WechatAuthError.timeout))
            }
            WXApi.send(request) { [self] success in
                Task { @MainActor [self] in
                    guard self.expectedState == state, !success else { return }
                    self.finish(.failure(WechatAuthError.requestFailed))
                }
            }
        }
        struct Body: Encodable, Sendable {
            let code: String
            let app_id: String
        }
        return try await APIClient.shared.request(
            "/api/auth/login/wechat", method: .post,
            body: Body(code: code, app_id: WechatLoginPolicy.appID)
        )
    }

    func handle(url: URL) -> Bool {
        guard url.scheme == WechatLoginPolicy.appID, register() else { return false }
        return WXApi.handleOpen(url, delegate: self)
    }

    func handle(activity: NSUserActivity) -> Bool {
        guard let url = activity.webpageURL,
              url.scheme == "https", url.host == "jifenqi.com",
              url.path.hasPrefix("/app/"), register() else { return false }
        return WXApi.handleOpenUniversalLink(activity, delegate: self)
    }

    func onResp(_ resp: BaseResp) {
        guard let response = resp as? SendAuthResp, let state = expectedState else { return }
        // 不允许过期或其他授权请求的回调完成当前登录。
        guard response.state == state else { return }
        switch response.errCode {
        case 0:
            guard let code = response.code, !code.isEmpty else {
                finish(.failure(WechatAuthError.invalidResponse)); return
            }
            finish(.success(code))
        case -2: finish(.failure(WechatAuthError.cancelled))
        case -4: finish(.failure(WechatAuthError.denied))
        default: finish(.failure(WechatAuthError.requestFailed))
        }
    }

    private func finish(_ result: Result<String, Error>) {
        let pending = continuation
        continuation = nil
        expectedState = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        pending?.resume(with: result)
    }
}
