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
}

nonisolated enum APIClientError: LocalizedError, Equatable {
    case invalidResponse
    case sessionExpired
    case server(status: Int, code: String?, message: String?)
    case decoding

    var errorDescription: String? {
        switch self {
        case .invalidResponse: NSLocalizedString("network_invalid_response", value: "服务器响应无效", comment: "")
        case .sessionExpired: NSLocalizedString("login_expired", value: "登录已失效，请重新登录", comment: "")
        case .server(_, let code, let message): message ?? code ?? NSLocalizedString("network_request_failed", value: "请求失败，请稍后重试", comment: "")
        case .decoding: NSLocalizedString("network_invalid_response", value: "服务器响应无效", comment: "")
        }
    }
}

nonisolated extension Notification.Name {
    static let apiSessionExpired = Notification.Name("jifen.api.sessionExpired")
}

actor APIClient {
    static let shared = APIClient()

    let environment: APIEnvironment
    private let session: URLSession
    private let tokenStore: AuthTokenStore
    private var refreshTask: Task<String, Error>?
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
        headers: [String: String] = [:]
    ) async throws -> Response {
        var token: String?
        if requiresAuth {
            token = try await validToken()
        }
        let data = try await perform(
            path,
            method: method,
            query: query,
            bodyData: body.map { try encoder.encode(AnyEncodable($0)) },
            contentType: body == nil ? nil : "application/json",
            token: token,
            headers: headers
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
        headers: [String: String] = [:]
    ) async throws -> Response {
        let token = requiresAuth ? try await validToken() : nil
        let data = try await perform(
            path,
            method: .post,
            bodyData: multipartBody,
            contentType: "multipart/form-data; boundary=\(boundary)",
            token: token,
            headers: headers
        )
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIClientError.decoding
        }
    }

    func clearSession() async {
        refreshTask?.cancel()
        refreshTask = nil
        await tokenStore.clearAuth()
    }

    private func validToken() async throws -> String {
        guard let token = await tokenStore.authToken() else { throw APIClientError.sessionExpired }
        let expiry = await tokenStore.authExpiry() ?? jwtExpiration(token)
        if let expiry, expiry.timeIntervalSinceNow < 5 * 60 {
            return try await refresh(existingToken: token)
        }
        return token
    }

    private func refresh(existingToken: String) async throws -> String {
        if let refreshTask { return try await refreshTask.value }
        let task = Task<String, Error> { [session, environment, tokenStore, encoder, decoder] in
            var request = URLRequest(url: environment.restBaseURL.appending(path: "/api/auth/refresh"))
            request.httpMethod = HTTPMethod.post.rawValue
            request.setValue("Bearer \(existingToken)", forHTTPHeaderField: "Authorization")
            APIClient.applyDefaultHeaders(to: &request)
            request.httpBody = try encoder.encode(EmptyRequest())
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIClientError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                let payload = try? decoder.decode(APIErrorPayload.self, from: data)
                if http.statusCode == 401 || http.statusCode == 403 {
                    await tokenStore.clearAuth()
                    await MainActor.run {
                        NotificationCenter.default.post(name: .apiSessionExpired, object: nil)
                    }
                    throw APIClientError.sessionExpired
                }
                throw APIClientError.server(
                    status: http.statusCode,
                    code: payload?.error,
                    message: payload?.message
                )
            }
            let payload = try decoder.decode(RefreshResponse.self, from: data)
            guard let expiry = APIDateParser.date(from: payload.expiresAt) else {
                #if DEBUG
                print("[APIClient] refresh rejected: invalid expiresAt=\(payload.expiresAt)")
                #endif
                throw APIClientError.decoding
            }
            try await tokenStore.setAuth(token: payload.token, expiresAt: expiry)
            return payload.token
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func perform(
        _ path: String,
        method: HTTPMethod,
        query: [URLQueryItem] = [],
        bodyData: Data?,
        contentType: String?,
        token: String?,
        headers: [String: String]
    ) async throws -> Data {
        var components = URLComponents(url: environment.restBaseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIClientError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = bodyData
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        Self.applyDefaultHeaders(to: &request)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
        #if DEBUG
        print("[APIClient] \(method.rawValue) \(path) -> \(http.statusCode), bytes=\(data.count)")
        #endif
        guard (200..<300).contains(http.statusCode) else {
            let payload = try? decoder.decode(APIErrorPayload.self, from: data)
            if http.statusCode == 401 && token != nil {
                await tokenStore.clearAuth()
                await MainActor.run {
                    NotificationCenter.default.post(name: .apiSessionExpired, object: nil)
                }
                throw APIClientError.sessionExpired
            }
            throw APIClientError.server(
                status: http.statusCode,
                code: payload?.error,
                message: payload?.message
            )
        }
        return data
    }

    nonisolated private static func applyDefaultHeaders(to request: inout URLRequest) {
        let info = Bundle.main.infoDictionary
        if request.value(forHTTPHeaderField: "X-Request-ID") == nil {
            request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        }
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
        request.setValue(info?["CFBundleShortVersionString"] as? String ?? "0", forHTTPHeaderField: "X-App-Version-Name")
        request.setValue(info?["CFBundleVersion"] as? String ?? "0", forHTTPHeaderField: "X-App-Version-Code")
        request.setValue("1", forHTTPHeaderField: "X-Api-Level")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
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
