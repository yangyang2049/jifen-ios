import Foundation

/// Binding never exchanges credentials through the login endpoint and never
/// installs an AuthResponse. APIClient pins every request to its initiating
/// authentication revision, including refresh and delayed network responses.
actor WechatBindingService {
    private let client: APIClient
    private var authorization: AuthSessionSnapshot?
    private var preparationRequestID: String?

    init(client: APIClient = .shared) {
        self.client = client
    }

    func status(expectedAuthRevision: UInt64) async throws -> WechatBindingStatus {
        try Task.checkCancellation()
        return try await client.request(
            WechatBindingEndpoint.status,
            requiresAuth: true,
            expectedAuthRevision: expectedAuthRevision
        )
    }

    func prepare(_ attempt: WechatBindingAttempt) async throws -> AccountLinkResponse {
        if preparationRequestID != attempt.requestID {
            authorization = try await client.accountLinkingAuthorization(expectedRevision: attempt.authRevision)
            preparationRequestID = attempt.requestID
        }
        let result: AccountLinkResponse = try await pinnedRequest(
            "/api/auth/bindings/wechat/prepare",
            method: .post,
            body: WechatBindingEndpoint.Body(code: attempt.code, app_id: WechatLoginPolicy.appID, requestId: attempt.requestID)
        )
        guard result.success == true,
              (result.status == "bound" && result.bindings?.wechat.bound == true)
                || (result.status == "requires_confirmation" && result.ticket?.isEmpty == false && result.accounts != nil)
        else { throw APIClientError.invalidResponse }
        return result
    }

    func preview(ticket: String, mode: AccountLinkMode, masterUserID: String) async throws -> AccountLinkPreview {
        struct Body: Encodable, Sendable { let ticket: String; let mode: AccountLinkMode; let masterUserId: String }
        return try await pinnedRequest("/api/auth/bindings/preview", method: .post,
                                       body: Body(ticket: ticket, mode: mode, masterUserId: masterUserID))
    }

    func confirm(ticket: String, previewToken: String, requestID: String) async throws -> AccountLinkResponse {
        struct Body: Encodable, Sendable { let ticket: String; let previewToken: String; let requestId: String }
        let result: AccountLinkResponse = try await pinnedRequest("/api/auth/bindings/confirm", method: .post,
            body: Body(ticket: ticket, previewToken: previewToken, requestId: requestID), allowRevokedResponse: true)
        guard result.success == true, result.status == "completed", result.authentication != nil, result.bindings != nil
        else { throw APIClientError.invalidResponse }
        return result
    }

    func recover(requestID: String, ticket: String) async throws -> AccountLinkResponse {
        guard UUID(uuidString: requestID) != nil else { throw APIClientError.invalidResponse }
        return try await pinnedRequest("/api/auth/bindings/requests/" + requestID, method: .get,
            query: [.init(name: "ticket", value: ticket)], allowRevokedResponse: true, requiresOriginalSession: false)
    }

    private func pinnedRequest<Response: Decodable & Sendable>(
        _ path: String, method: HTTPMethod, body: (any Encodable & Sendable)? = nil,
        query: [URLQueryItem] = [], allowRevokedResponse: Bool = false, requiresOriginalSession: Bool = true
    ) async throws -> Response {
        try Task.checkCancellation()
        guard let authorization, let token = authorization.token else { throw CancellationError() }
        if requiresOriginalSession, await client.authSessionRevision() != authorization.revision { throw CancellationError() }
        // This narrowly scoped endpoint verifies the exact original bearer and
        // ticket even after commit revokes the ordinary session. Do not invoke
        // APIClient's 401 refresh/expiry machinery for these receipt requests.
        let response: Response = try await client.request(path, method: method, query: query, body: body,
            headers: ["Authorization": "Bearer " + token], retries: 0,
            expectedAuthRevision: requiresOriginalSession ? authorization.revision : nil)
        if !allowRevokedResponse, await client.authSessionRevision() != authorization.revision { throw CancellationError() }
        return response
    }

    func bind(_ attempt: WechatBindingAttempt) async throws -> WechatBindingResponse {
        try Task.checkCancellation()
        guard !attempt.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WechatAuthError.invalidResponse
        }
        let response: WechatBindingResponse = try await client.request(
            WechatBindingEndpoint.bind,
            method: .post,
            body: WechatBindingEndpoint.Body(
                code: attempt.code,
                app_id: WechatLoginPolicy.appID,
                requestId: attempt.requestID
            ),
            requiresAuth: true,
            // POST is not automatically retried. An explicit retry must retain
            // the same attempt so the server can recover the original receipt.
            retries: 0,
            expectedAuthRevision: attempt.authRevision
        )
        guard response.success, response.status == "bound", response.bindings.wechat.bound else {
            throw APIClientError.invalidResponse
        }
        return response
    }
}
