import Foundation

nonisolated enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

nonisolated struct EmptyRequest: Encodable, Sendable {}
nonisolated struct EmptyResponse: Decodable, Sendable {}

nonisolated enum APIDateParser {
    static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

nonisolated struct APIErrorPayload: Decodable, Sendable {
    var error: String?
    var message: String?
    var nextAvailableAt: String? = nil
    var currentResultId: String? = nil
}

/// Carries actionable group conflict details without changing existing server errors.
nonisolated struct APIClientServerContextError: LocalizedError, Sendable {
    var underlying: APIClientError
    var currentResultID: String
    var errorDescription: String? { underlying.errorDescription }
}

nonisolated enum APIClientError: LocalizedError, Equatable {
    case invalidResponse
    case sessionExpired
    /// 带 token 的请求收到 401：先不拆会话，交给刷新后重放，重放仍 401 才升级 sessionExpired（对齐安卓）
    case unauthorized
    case server(status: Int, code: String?, message: String?, nextAvailableAt: String?)
    case decoding

    var errorDescription: String? {
        switch self {
        case .invalidResponse: NSLocalizedString("network_invalid_response", value: "服务器响应无效", comment: "")
        case .sessionExpired, .unauthorized: NSLocalizedString("login_expired", value: "登录已失效，请重新登录", comment: "")
        case .server(let status, let code, let message, _):
            Self.serverMessage(status: status, code: code, message: message)
        case .decoding: NSLocalizedString("network_invalid_response", value: "服务器响应无效", comment: "")
        }
    }

    static func serverMessage(status: Int, code: String?, message: String?, bundle: Bundle = .main) -> String {
        let key: String
        switch code {
        case "NAME_COOLDOWN": key = "me_profile_nickname_cooldown_generic"
        case "NAME_BLOCKED": key = "group_error_content_blocked"
        case "ACCOUNT_DELETION_FAILED": key = "account_deletion_failed"
        case "SESSION_REVOKED", "ACCOUNT_DELETED": key = "login_expired"
        default:
            // Legacy server messages are authored in Simplified Chinese only.
            // Keep their detail for that language; never leak them or raw codes
            // into other app languages. Feature mappers handle business codes.
            if bundle.preferredLocalizations.first == "zh-Hans",
               let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return message
            }
            key = status == 429 ? "group_rate_limited" : "network_request_failed"
        }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}

nonisolated extension Notification.Name {
    static let apiSessionExpired = Notification.Name("jifen.api.sessionExpired")
}

/// 纯策略：哪些响应可以重试、退避多久。收敛在 API 漏斗一处，与安卓 OkHttp 拦截器口径一致。
nonisolated enum APIRetryPolicy {
    static let maxRetries = 2
    static let baseBackoffSeconds = 0.4
    static let maxRetryAfterSeconds = 10.0
    static let retryableStatuses: Set<Int> = [429, 502, 503, 504]
    private static let retryableURLCodes: Set<Int> = [
        URLError.timedOut.rawValue,
        URLError.networkConnectionLost.rawValue,
        URLError.notConnectedToInternet.rawValue,
        URLError.dataNotAllowed.rawValue,
        URLError.secureConnectionFailed.rawValue,
        URLError.cannotFindHost.rawValue,
        URLError.cannotConnectToHost.rawValue,
    ]

    /// 只重试幂等的 GET；POST/PATCH 可能是计分/兑换等非幂等写操作。
    static func maxRetries(method: HTTPMethod) -> Int { method == .get ? maxRetries : 0 }

    static func retryDelay(attempt: Int, retryAfterSeconds: Double?) -> Double {
        if let retryAfterSeconds, retryAfterSeconds.isFinite {
            return min(max(retryAfterSeconds, 0), maxRetryAfterSeconds)
        }
        return min(baseBackoffSeconds * pow(2.0, Double(max(attempt - 1, 0))), maxRetryAfterSeconds)
    }

    static func isRetryableTransport(_ error: URLError) -> Bool {
        retryableURLCodes.contains(error.code.rawValue)
    }

    static func retryAfterSeconds(from headerValue: String?) -> Double? {
        guard let raw = headerValue?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if let seconds = Double(raw) { return seconds.isFinite ? seconds : nil }
        let formatter = HTTPDateFormatter.shared
        guard let date = formatter.date(from: raw) else { return nil }
        return date.timeIntervalSinceNow
    }
}

/// perform 在「尝试已耗尽或不幂等」时抛出的包装：携带原始错误供上层原样重抛，同时告知 execute 还可重试。
nonisolated enum APIRetryTerminalError: Error {
    indirect case retryable(underlying: Error, retryAfterSeconds: Double?)
}

private nonisolated final class HTTPDateFormatter: DateFormatter, @unchecked Sendable {
    static let shared: HTTPDateFormatter = {
        let formatter = HTTPDateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}

actor APIClient {
    static let shared = APIClient()

    let environment: APIEnvironment
    private let session: URLSession
    private let tokenStore: AuthTokenStore
    private nonisolated struct ActiveRefresh: Sendable {
        let id: UUID
        let snapshot: AuthSessionSnapshot
        let task: Task<AuthSessionSnapshot, Error>
    }
    private var refreshTask: ActiveRefresh?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        environment: APIEnvironment = .current,
        session: URLSession? = nil,
        tokenStore: AuthTokenStore = .shared
    ) {
        self.environment = environment
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        configuration.waitsForConnectivity = true
        // Native authentication is owned by AuthTokenStore. A web login cookie
        // can outlive account linking and takes precedence over Bearer server-side.
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        self.session = session ?? URLSession(configuration: configuration)
        self.tokenStore = tokenStore
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func request<Response: Decodable & Sendable>(
        _ path: String,
        method: HTTPMethod = .get,
        query: [URLQueryItem] = [],
        body: (any Encodable & Sendable)? = nil,
        requiresAuth: Bool = false,
        headers: [String: String] = [:],
        timeout: TimeInterval? = nil,
        retries: Int? = nil,
        expectedAuthRevision: UInt64? = nil
    ) async throws -> Response {
        let data = try await execute(
            path,
            method: method,
            query: query,
            bodyData: body.map { try encoder.encode(AnyEncodable($0)) },
            contentType: body == nil ? nil : "application/json",
            requiresAuth: requiresAuth,
            headers: headers,
            timeout: timeout,
            retries: retries,
            expectedAuthRevision: expectedAuthRevision
        )
        if Response.self == EmptyResponse.self, data.isEmpty {
            return try decoder.decode(Response.self, from: Data("{}".utf8))
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            #if DEBUG
            print("[APIClient] decode failed \(path):", error)
            #endif
            throw APIClientError.decoding
        }
    }

    func upload<Response: Decodable & Sendable>(
        _ path: String,
        multipartBody: Data,
        boundary: String,
        requiresAuth: Bool = true,
        headers: [String: String] = [:],
        expectedAuthRevision: UInt64? = nil
    ) async throws -> Response {
        let data = try await execute(
            path,
            method: .post,
            query: [],
            bodyData: multipartBody,
            contentType: "multipart/form-data; boundary=\(boundary)",
            requiresAuth: requiresAuth,
            headers: headers,
            timeout: nil,
            retries: nil,
            expectedAuthRevision: expectedAuthRevision
        )
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIClientError.decoding
        }
    }

    /// The binding flow retains the exact bearer used to verify its ticket.
    /// Refresh before taking this snapshot; recovery must not silently exchange
    /// the revoked source session for unrelated credentials.
    func accountLinkingAuthorization(expectedRevision: UInt64) async throws -> AuthSessionSnapshot {
        try await validAuthSnapshot(expectedRevision: expectedRevision)
    }

    func authSessionRevision() async -> UInt64 {
        await tokenStore.authSessionRevision()
    }

    func clearSession() async {
        refreshTask?.task.cancel()
        refreshTask = nil
        await tokenStore.clearAuth()
    }

    /// A delayed logout may clear only the session that initiated it.
    @discardableResult
    func clearSession(expectedAuthRevision: UInt64) async -> Bool {
        guard await tokenStore.clearAuth(ifRevisionMatches: expectedAuthRevision) != nil else { return false }
        if refreshTask?.snapshot.revision == expectedAuthRevision {
            refreshTask?.task.cancel()
            refreshTask = nil
        }
        return true
    }

    /// Requests and refreshes remain bound to the login session that started them.
    private func ensureCurrent(_ snapshot: AuthSessionSnapshot) async throws {
        guard await tokenStore.authSessionRevision() == snapshot.revision else { throw CancellationError() }
    }

    private func expireSession(_ snapshot: AuthSessionSnapshot) async throws -> Never {
        guard let clearedRevision = await tokenStore.clearAuth(ifMatching: snapshot) else { throw CancellationError() }
        if refreshTask?.snapshot.revision == snapshot.revision {
            refreshTask?.task.cancel()
            refreshTask = nil
        }
        await MainActor.run {
            NotificationCenter.default.post(name: .apiSessionExpired, object: nil,
                userInfo: ["authSessionRevision": clearedRevision])
        }
        throw APIClientError.sessionExpired
    }

    /// GET retry and 401 replay never cross a logout/login boundary.
    private func execute(
        _ path: String,
        method: HTTPMethod,
        query: [URLQueryItem],
        bodyData: Data?,
        contentType: String?,
        requiresAuth: Bool,
        headers: [String: String],
        timeout: TimeInterval?,
        retries: Int?,
        expectedAuthRevision: UInt64?
    ) async throws -> Data {
        #if DEBUG
        if GroupCaptureFixture.enabled { throw GroupCaptureFailure.networkForbidden(path) }
        #endif
        var auth = requiresAuth ? try await validAuthSnapshot(expectedRevision: expectedAuthRevision) : nil
        let retryBudget = retries ?? APIRetryPolicy.maxRetries(method: method)
        var attemptsMade = 0
        var unauthorizedHandled = false
        while true {
            if let auth { try await ensureCurrent(auth) }
            // Explicit credentials used by account-link confirmation still
            // belong to the original session at the actual send boundary.
            // Receipt recovery intentionally omits this precondition.
            if !requiresAuth, let expectedAuthRevision,
               await tokenStore.authSessionRevision() != expectedAuthRevision { throw CancellationError() }
            do {
                let data = try await perform(
                    path, method: method, query: query, bodyData: bodyData, contentType: contentType,
                    token: auth?.token, headers: headers, timeout: timeout
                )
                if let auth { try await ensureCurrent(auth) }
                return data
            } catch APIRetryTerminalError.retryable(let underlying, let retryAfterSeconds) {
                if let auth { try await ensureCurrent(auth) }
                guard attemptsMade < retryBudget else { throw underlying }
                attemptsMade += 1
                let delay = APIRetryPolicy.retryDelay(attempt: attemptsMade, retryAfterSeconds: retryAfterSeconds)
                if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            } catch let error as APIClientError {
                if let auth { try await ensureCurrent(auth) }
                guard case .unauthorized = error else { throw error }
                guard requiresAuth, let snapshot = auth else { throw error }
                guard !unauthorizedHandled else { try await expireSession(snapshot) }
                unauthorizedHandled = true
                auth = try await refresh(existing: snapshot)
            } catch {
                if let auth { try await ensureCurrent(auth) }
                throw error
            }
        }
    }

    private func validAuthSnapshot(expectedRevision: UInt64?) async throws -> AuthSessionSnapshot {
        let snapshot = await tokenStore.authSnapshot()
        if let expectedRevision, expectedRevision != snapshot.revision { throw CancellationError() }
        guard let token = snapshot.token else { throw APIClientError.sessionExpired }
        let expiry = snapshot.expiresAt ?? jwtExpiration(token)
        if let expiry, expiry.timeIntervalSinceNow < 5 * 60 {
            return try await refresh(existing: snapshot)
        }
        return snapshot
    }

    private func refresh(existing snapshot: AuthSessionSnapshot) async throws -> AuthSessionSnapshot {
        let current = await tokenStore.authSnapshot()
        guard current.revision == snapshot.revision, current.token != nil else { throw CancellationError() }
        // Another request may have refreshed this same session while this request was in flight.
        if current.token != snapshot.token { return current }
        if let active = refreshTask, active.snapshot.revision == snapshot.revision, active.snapshot.token == snapshot.token {
            let result = try await active.task.value
            try await ensureCurrent(result)
            return result
        }
        refreshTask?.task.cancel()
        let id = UUID()
        let task = Task<AuthSessionSnapshot, Error> { [session, environment, tokenStore, encoder, decoder] in
            var request = URLRequest(url: environment.restBaseURL.appending(path: "/api/auth/refresh"))
            request.httpMethod = HTTPMethod.post.rawValue
            request.setValue("Bearer \(snapshot.token ?? "")", forHTTPHeaderField: "Authorization")
            APIClient.applyDefaultHeaders(to: &request)
            request.httpBody = try encoder.encode(EmptyRequest())
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                guard await tokenStore.authSessionRevision() == snapshot.revision else { throw CancellationError() }
                throw error
            }
            guard await tokenStore.authSessionRevision() == snapshot.revision else { throw CancellationError() }
            guard let http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                let payload = try? decoder.decode(APIErrorPayload.self, from: data)
                if http.statusCode == 401 {
                    guard let clearedRevision = await tokenStore.clearAuth(ifMatching: snapshot) else { throw CancellationError() }
                    await MainActor.run {
                        NotificationCenter.default.post(name: .apiSessionExpired, object: nil,
                            userInfo: ["authSessionRevision": clearedRevision])
                    }
                    throw APIClientError.sessionExpired
                }
                throw APIClientError.server(status: http.statusCode, code: payload?.error,
                    message: payload?.message, nextAvailableAt: payload?.nextAvailableAt)
            }
            let payload = try decoder.decode(RefreshResponse.self, from: data)
            guard let expiry = APIDateParser.date(from: payload.expiresAt) else { throw APIClientError.decoding }
            guard let refreshed = try await tokenStore.setRefreshedAuth(token: payload.token, expiresAt: expiry, ifMatching: snapshot)
            else { throw CancellationError() }
            return refreshed
        }
        refreshTask = ActiveRefresh(id: id, snapshot: snapshot, task: task)
        defer { if refreshTask?.id == id { refreshTask = nil } }
        let result = try await task.value
        try await ensureCurrent(result)
        return result
    }

    private func perform(
        _ path: String,
        method: HTTPMethod,
        query: [URLQueryItem] = [],
        bodyData: Data?,
        contentType: String?,
        token: String?,
        headers: [String: String],
        timeout: TimeInterval?
    ) async throws -> Data {
        var components = URLComponents(url: environment.restBaseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIClientError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = bodyData
        if let timeout { request.timeoutInterval = timeout }
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        Self.applyDefaultHeaders(to: &request)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // catch 子句里不能 await（默认 MainActor 隔离），先把判定算成普通值再抛。
            let isRetryable = (error as? URLError).map(APIRetryPolicy.isRetryableTransport) ?? false
            guard isRetryable else { throw error }
            throw APIRetryTerminalError.retryable(underlying: error, retryAfterSeconds: nil)
        }
        guard let http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        #if DEBUG
        print("[APIClient] \(method.rawValue) \(path) -> \(http.statusCode), bytes=\(data.count)")
        #endif
        guard (200..<300).contains(http.statusCode) else {
            let payload = try? decoder.decode(APIErrorPayload.self, from: data)
            if http.statusCode == 401, token != nil {
                throw APIClientError.unauthorized
            }
            let error = APIClientError.server(
                status: http.statusCode,
                code: payload?.error,
                message: payload?.message,
                nextAvailableAt: payload?.nextAvailableAt
            )
            if APIRetryPolicy.retryableStatuses.contains(http.statusCode) {
                var retryAfter: Double?
                if let nextAvailableAt = payload?.nextAvailableAt {
                    retryAfter = APIDateParser.date(from: nextAvailableAt).map { max($0.timeIntervalSinceNow, 0) }
                }
                if retryAfter == nil {
                    retryAfter = APIRetryPolicy.retryAfterSeconds(
                        from: http.value(forHTTPHeaderField: "Retry-After")
                    )
                }
                throw APIRetryTerminalError.retryable(underlying: error, retryAfterSeconds: retryAfter)
            }
            if path.hasPrefix("/api/groups/"), let resultID = payload?.currentResultId, !resultID.isEmpty {
                throw APIClientServerContextError(underlying: error, currentResultID: resultID)
            }
            throw error
        }
        return data
    }

    nonisolated private static func applyDefaultHeaders(to request: inout URLRequest) {
        // Also cover injected URLSessions and the pinned receipt-recovery bearer.
        request.httpShouldHandleCookies = false
        request.setValue(nil, forHTTPHeaderField: "Cookie")
        let info = Bundle.main.infoDictionary
        if request.value(forHTTPHeaderField: "X-Request-ID") == nil {
            request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        }
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
        request.setValue(info?["CFBundleShortVersionString"] as? String ?? "0", forHTTPHeaderField: "X-App-Version-Name")
        request.setValue(info?["CFBundleVersion"] as? String ?? "0", forHTTPHeaderField: "X-App-Version-Code")
        request.setValue("1", forHTTPHeaderField: "X-Api-Level")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.acceptLanguageHeader, forHTTPHeaderField: "Accept-Language")
    }

    nonisolated private static var acceptLanguageHeader: String {
        guard Locale.current.language.languageCode?.identifier == "zh" else { return "en" }
        return ChineseScript.isTraditional() ? "zh-Hant-TW" : "zh-Hans-CN"
    }

    private func jwtExpiration(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let data = Data(base64URLEncoded: String(parts[1])),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = payload["exp"] as? TimeInterval
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}

nonisolated private struct RefreshResponse: Decodable, Sendable {
    let token: String
    let expiresAt: String
}

nonisolated private struct AnyEncodable: Encodable {
    private let encodeValue: (Encoder) throws -> Void
    init(_ value: any Encodable) { encodeValue = value.encode }
    func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
}

nonisolated private extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64.append(String(repeating: "=", count: (4 - base64.count % 4) % 4))
        self.init(base64Encoded: base64)
    }
}
