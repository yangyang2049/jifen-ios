import Foundation
import OSLog
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

nonisolated enum WechatCallbackRoute: String, Sendable {
    case scheme, universalLink
}

nonisolated enum WechatCallbackRouter {
    static func route(for url: URL) -> WechatCallbackRoute? {
        if url.scheme == WechatLoginPolicy.appID { return .scheme }
        guard url.scheme == "https", url.host == "jifenqi.com",
              url.port == nil || url.port == 443,
              url.user == nil, url.password == nil,
              url.path.hasPrefix("/app/") else { return nil }
        return .universalLink
    }

    @MainActor
    static func handle(
        url: URL,
        openScheme: (URL) -> Bool,
        openUniversalLink: (NSUserActivity) -> Bool
    ) -> Bool {
        switch route(for: url) {
        case .scheme:
            return openScheme(url)
        case .universalLink:
            // SwiftUI delivers Universal Links to onOpenURL as URLs, while
            // WeChat's Universal Link entry point requires an NSUserActivity.
            let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
            activity.webpageURL = url
            return openUniversalLink(activity)
        case nil:
            return false
        }
    }
}

// MARK: - 真机诊断（仅 WECHAT_DIAG 编译条件生效；正常构建全部为空操作，不写任何数据）

nonisolated enum WechatDiag {
    #if WECHAT_DIAG
    private static let queue = DispatchQueue(label: "com.douhua.jifen.wechat-diag")

    /// 输出到 App 沙盒 Documents/wechat-diag.log，供 devicectl 拉取后排查。
    static func log(_ message: String) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let url = docs?.appendingPathComponent("wechat-diag.log") else { return }
        let stamp = Int(Date.now.timeIntervalSince1970 * 1000)
        let line = "\(stamp) \(message)\n"
        queue.async {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
            }
        }
    }

    /// 只记录路径、参数名和 state 值；不记录 code 等一次性凭据。
    static func describe(url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "unparsable"
        }
        let items = components.queryItems ?? []
        let names = items.map(\.name).joined(separator: ",")
        let state = items.first(where: { $0.name == "state" })?.value ?? "-"
        return "path=\(components.path) queryKeys=\(names) state=\(state)"
    }

    static func startSDKLogging() {
        WXApi.startLog(by: .detail) { message in
            log("SDK \(String(describing: message))")
        }
    }

    /// SDK 官方 Universal Link 自检：逐项检查参数、系统、微信版本，并真实拉起微信再返回。
    static func runUniversalLinkCheck() {
        log("UL check start")
        WXApi.checkUniversalLinkReady { step, result in
            log("UL check step=\(step.rawValue) success=\(result.success) error=\(String(describing: result.errorInfo)) suggestion=\(String(describing: result.suggestion))")
        }
    }
    #else
    @inline(__always)
    static func log(_ message: String) {}
    @inline(__always)
    static func describe(url: URL) -> String { "" }
    @inline(__always)
    static func startSDKLogging() {}
    @inline(__always)
    static func runUniversalLinkCheck() {}
    #endif
}

nonisolated enum WechatAuthError: LocalizedError, Equatable {
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

nonisolated enum WechatAuthorizationResultPolicy {
    /// A failed SDK dispatch does not identify its cause. Only the SDK's
    /// installation check can distinguish a missing app from another failure.
    static func sendFailure(isInstalled: Bool) -> WechatAuthError {
        isInstalled ? .requestFailed : .notInstalled
    }

    static func response(
        expectedState: String?, state: String?, errorCode: Int32,
        code: String?, isInstalled: Bool
    ) -> Result<String, WechatAuthError>? {
        // Ignore stale or unrelated callbacks before interpreting their result.
        guard let expectedState, state == expectedState else { return nil }
        switch errorCode {
        case 0:
            guard let code, !code.isEmpty else { return .failure(.invalidResponse) }
            return .success(code)
        case -2: return .failure(.cancelled)
        case -3: return .failure(sendFailure(isInstalled: isInstalled))
        case -4: return .failure(.denied)
        default: return .failure(.requestFailed)
        }
    }
}

@MainActor
protocol WechatBindingAuthorizing {
    func authorizeForBinding() async throws -> String
}

@MainActor
final class ProductionWechatAuthProvider: NSObject, AccountIdentityProviding, WechatBindingAuthorizing, @preconcurrency WXApiDelegate {
    static let shared = ProductionWechatAuthProvider()
    private static let logger = Logger(subsystem: "com.douhua.jifen.ios", category: "WechatAuth")
    let providerID: AccountIdentityProviderID = .wechat
    private var registered = false
    private var expectedState: String?
    private var continuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?

    static var isInstalled: Bool { WXApi.isWXAppInstalled() }

    // 仅在用户勾选协议并主动登录，或处理微信回调时注册 SDK。
    private func register() -> Bool {
        if !registered {
            WechatDiag.startSDKLogging()
            registered = WXApi.registerApp(WechatLoginPolicy.appID, universalLink: WechatLoginPolicy.universalLink)
            WechatDiag.log("register registered=\(registered)")
        }
        return registered
    }

    func signIn() async throws -> AuthResponse {
        guard Self.isInstalled else { throw WechatAuthError.notInstalled }
        WechatDiag.log("signIn start")
        let code = try await authorize()
        WechatDiag.log("signIn code received, exchanging")
        struct Body: Encodable, Sendable {
            let code: String
            let app_id: String
        }
        do {
            let response: AuthResponse = try await APIClient.shared.request(
                "/api/auth/login/wechat", method: .post,
                body: Body(code: code, app_id: WechatLoginPolicy.appID)
            )
            WechatDiag.log("signIn exchange ok")
            return response
        } catch {
            WechatDiag.log("signIn exchange failed: \(String(describing: error))")
            throw error
        }
    }

    /// Binding requests authorization only. Calling signIn() here would create or
    /// select a WeChat login account before the current user has agreed to bind.
    /// Attempt the SDK request directly; installation status does not gate binding.
    func authorizeForBinding() async throws -> String {
        try await authorize()
    }

    private func authorize() async throws -> String {
        try Task.checkCancellation()
        guard continuation == nil, register() else { throw WechatAuthError.requestFailed }
        let state = UUID().uuidString
        WechatDiag.log("authorize start state=\(state)")
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError()); return
                }
                self.continuation = continuation
                expectedState = state
                let request = SendAuthReq()
                request.scope = "snsapi_userinfo"
                request.state = state
                timeoutTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    guard self?.expectedState == state else { return }
                    Self.logger.error("[WechatAuth] authorization timeout")
                    WechatDiag.log("authorize timeout state=\(state)")
                    self?.finish(.failure(WechatAuthError.timeout))
                }
                WXApi.send(request) { [self] success in
                    Task { @MainActor [self] in
                        WechatDiag.log("WXApi.send success=\(success)")
                        guard self.expectedState == state, !success else { return }
                        self.finish(.failure(WechatAuthorizationResultPolicy.sendFailure(
                            isInstalled: Self.isInstalled
                        )))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.expectedState == state else { return }
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    func handle(url: URL) -> Bool {
        let handled = WechatCallbackRouter.handle(url: url) { [self] url in
            guard register() else { return false }
            return WXApi.handleOpen(url, delegate: self)
        } openUniversalLink: { [self] activity in
            guard register() else { return false }
            return WXApi.handleOpenUniversalLink(activity, delegate: self)
        }
        let kind = WechatCallbackRouter.route(for: url)?.rawValue ?? "ignored"
        Self.logger.notice("[WechatAuth] callback kind=\(kind, privacy: .public) handled=\(handled, privacy: .public)")
        WechatDiag.log("handle url kind=\(kind) handled=\(handled) \(WechatDiag.describe(url: url))")
        if url.query?.contains("ulcheck=zcode") == true {
            WechatDiag.runUniversalLinkCheck()
        }
        return handled
    }

    func handle(activity: NSUserActivity) -> Bool {
        guard let url = activity.webpageURL,
              WechatCallbackRouter.route(for: url) == .universalLink,
              register() else { return false }
        let handled = WXApi.handleOpenUniversalLink(activity, delegate: self)
        Self.logger.notice("[WechatAuth] callback kind=universalLink handled=\(handled, privacy: .public)")
        WechatDiag.log("handle activity handled=\(handled) \(WechatDiag.describe(url: url))")
        return handled
    }

    func onResp(_ resp: BaseResp) {
        guard let response = resp as? SendAuthResp else { return }
        let stateMatches = expectedState.map { response.state == $0 } ?? false
        Self.logger.notice("[WechatAuth] response errCode=\(response.errCode, privacy: .public) stateMatches=\(stateMatches, privacy: .public)")
        WechatDiag.log("onResp errCode=\(response.errCode) state=\(String(describing: response.state)) stateMatches=\(stateMatches) hasCode=\(!(response.code ?? "").isEmpty)")
        guard let result = WechatAuthorizationResultPolicy.response(
            expectedState: expectedState, state: response.state,
            errorCode: response.errCode, code: response.code,
            isInstalled: Self.isInstalled
        ) else { return }
        finish(result.mapError { $0 as Error })
    }

    private func finish(_ result: Result<String, Error>) {
        switch result {
        case .success(let code): WechatDiag.log("finish success codeEmpty=\(code.isEmpty)")
        case .failure(let error): WechatDiag.log("finish failure \(String(describing: error))")
        }
        let pending = continuation
        continuation = nil
        expectedState = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        pending?.resume(with: result)
    }
}
