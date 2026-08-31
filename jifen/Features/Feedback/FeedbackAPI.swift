import Foundation

actor FeedbackAPI {
    static let shared = FeedbackAPI()
    private static let appClientHeaders = ["X-App-Client": "ios"]
    private let client: APIClient
    private let tokenStore: AuthTokenStore

    init(client: APIClient = .shared, tokenStore: AuthTokenStore = .shared) {
        self.client = client
        self.tokenStore = tokenStore
    }

    func list(page: Int = 1, type: FeedbackType? = nil) async throws -> FeedbackPage {
        var query = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "pageSize", value: "20")]
        if let type { query.append(URLQueryItem(name: "type", value: type.rawValue)) }
        return try await publicRequest("/api/feedback", query: query)
    }

    func detail(id: String) async throws -> FeedbackItem {
        try await publicRequest("/api/feedback/\(id)")
    }

    func comments(feedbackId: String) async throws -> [FeedbackComment] {
        try await publicRequest("/api/feedback/\(feedbackId)/comments")
    }

    func create(type: FeedbackType, title: String, content: String, imageURLs: [String]) async throws -> FeedbackItem {
        struct Body: Encodable, Sendable {
            var type: FeedbackType
            var title: String
            var content: String
            var imageUrls: [String]
            let clientPlatform = "ios"
        }
        return try await client.request(
            "/api/feedback",
            method: .post,
            body: Body(type: type, title: title, content: content, imageUrls: imageURLs),
            requiresAuth: true,
            headers: Self.appClientHeaders
        )
    }

    func uploadJPEG(_ data: Data) async throws -> String {
        let boundary = "jifen-feedback-\(UUID().uuidString)"
        var body = Data()
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"image\"; filename=\"feedback.jpg\"\r\n")
        body.appendUTF8("Content-Type: image/jpeg\r\n\r\n")
        body.append(data)
        body.appendUTF8("\r\n--\(boundary)--\r\n")
        let response: FeedbackImageUpload = try await client.upload(
            "/api/feedback/upload-image",
            multipartBody: body,
            boundary: boundary,
            headers: Self.appClientHeaders
        )
        return response.url
    }

    func setLiked(_ liked: Bool, feedbackId: String) async throws -> FeedbackItem {
        struct Body: Encodable, Sendable { var feedbackId: String; var action: String }
        return try await client.request(
            "/api/feedback/action",
            method: .post,
            body: Body(feedbackId: feedbackId, action: liked ? "like" : "unlike"),
            requiresAuth: true,
            headers: Self.appClientHeaders
        )
    }

    func comment(_ content: String, feedbackId: String) async throws -> FeedbackComment {
        struct Body: Encodable, Sendable { var feedbackId: String; var content: String }
        return try await client.request(
            "/api/feedback/comment",
            method: .post,
            body: Body(feedbackId: feedbackId, content: content),
            requiresAuth: true,
            headers: Self.appClientHeaders
        )
    }

    func report(feedbackId: String, reason: String, detail: String?) async throws {
        struct Body: Encodable, Sendable { var feedbackId: String; var reason: String; var detail: String? }
        let _: SuccessResponse = try await client.request(
            "/api/feedback/report",
            method: .post,
            body: Body(feedbackId: feedbackId, reason: reason, detail: detail),
            requiresAuth: true,
            headers: Self.appClientHeaders
        )
    }

    func delete(feedbackId: String) async throws {
        let _: EmptyResponse = try await client.request(
            "/api/feedback/\(feedbackId)",
            method: .delete,
            requiresAuth: true,
            headers: Self.appClientHeaders
        )
    }

    /// Public feedback endpoints accept optional auth for per-user like/report
    /// state. If that optional credential has expired, retry anonymously so the
    /// public community remains readable while SessionStore signs the user out.
    private func publicRequest<Response: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem] = []
    ) async throws -> Response {
        if await tokenStore.authToken() != nil {
            do {
                return try await client.request(path, query: query, requiresAuth: true)
            } catch APIClientError.sessionExpired {
                // The authenticated attempt already cleared the invalid token.
            }
        }
        return try await client.request(path, query: query)
    }

    nonisolated func absoluteImageURL(_ path: String) -> URL? {
        if let url = URL(string: path), url.scheme != nil { return url }
        return URL(string: path, relativeTo: APIEnvironment.current.restBaseURL)?.absoluteURL
    }
}

nonisolated private extension Data {
    mutating func appendUTF8(_ value: String) {
        if let data = value.data(using: .utf8) { append(data) }
    }
}
