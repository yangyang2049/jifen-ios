import XCTest
import Foundation
import UIKit
@testable import jifen

private nonisolated final class FeedbackTestRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URLRequest] = []
    func append(_ request: URLRequest) { lock.lock(); defer { lock.unlock() }; values.append(request) }
    func snapshot() -> [URLRequest] { lock.lock(); defer { lock.unlock() }; return values }
    func reset() { lock.lock(); defer { lock.unlock() }; values = [] }
}
private nonisolated final class FeedbackLanguageURLProtocol: URLProtocol, @unchecked Sendable {
    static let requests = FeedbackTestRequests()
    static let legacyItem = #"{"id":"feedback-test-001","type":"FEEDBACK","title":"Welcome","content":"Feedback body","images":[],"authorName":"Team","authorIsVip":false,"status":"PENDING","likeCount":0,"reportCount":0,"commentCount":0,"createdAt":"2026-10-03T00:00:00Z","updatedAt":"2026-10-03T00:00:00Z","isLiked":false,"isReported":false}"#
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        let body = request.httpMethod == "POST" ? Self.legacyItem : #"{"items":[],"total":0,"page":1,"pageSize":20,"hasMore":false}"#
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor final class FeedbackLanguageTests: XCTestCase {
    func testSmallFeedbackImageCanBePrepared() throws {
        for size in [CGSize(width: 32, height: 32), CGSize(width: 320, height: 200)] {
            let image = UIGraphicsImageRenderer(size: size).image { context in
                UIColor.systemBlue.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            let jpeg = try XCTUnwrap(FeedbackImageCompressor.prepareJPEG(image))
            XCTAssertLessThanOrEqual(jpeg.count, FeedbackImageCompressor.maximumBytes)
            XCTAssertNotNil(UIImage(data: jpeg))
        }
    }
    func testLocalizationMappings() {
        for (raw, expected) in ["ja-JP": "ja", "fr-CA": "fr-CA", "es-MX": "es-MX", "zh_CN": "zh-Hans", "zh-TW": "zh-Hant", "pt_BR": "pt-BR", "pt-PT": "pt-PT", "en-GB": "en", "unsupported": "en"] {
            XCTAssertEqual(FeedbackLanguage.normalize(raw), expected)
        }
    }
    func testOldResponsesRemainDecodable() throws {
        let item = try JSONDecoder().decode(FeedbackItem.self, from: Data(FeedbackLanguageURLProtocol.legacyItem.utf8))
        XCTAssertNil(item.language)
        XCTAssertNil(item.isOfficial)
        XCTAssertNil(item.isPinned)
    }
    func testFullLanguageIsSentForListAndCreate() async throws {
        FeedbackLanguageURLProtocol.requests.reset()
        let store = AuthTokenStore(service: "feedback-language-tests." + UUID().uuidString)
        try await store.setAuth(token: "local-feedback-test-token", expiresAt: Date().addingTimeInterval(86400))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedbackLanguageURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = APIClient(session: session, tokenStore: store)
        let api = FeedbackAPI(client: client, tokenStore: store, languageProvider: { "ja" })
        defer { session.invalidateAndCancel() }
        _ = try await api.list()
        _ = try await api.list(page: 2, language: "fr-CA")
        _ = try await api.create(type: .feedback, title: "App feedback", content: "Please improve the app", imageURLs: [])
        let requests = FeedbackLanguageURLProtocol.requests.snapshot()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "language" })?.value, "ja")
        XCTAssertEqual(URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "language" })?.value, "fr-CA")
        let bodyData: Data
        if let data = requests[2].httpBody { bodyData = data }
        else {
            let stream = try XCTUnwrap(requests[2].httpBodyStream)
            stream.open(); defer { stream.close() }
            var data = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count))
            }
            bodyData = data
        }
        let body = try JSONSerialization.jsonObject(with: bodyData) as! [String: Any]
        XCTAssertEqual(body["language"] as? String, "ja")
        await store.clearAuth()
    }

    func testFeedbackSubmissionStopsBeforeWritingUnderAnotherAccount() async throws {
        FeedbackLanguageURLProtocol.requests.reset()
        let store = AuthTokenStore(service: "feedback-session-tests." + UUID().uuidString)
        try await store.setAuth(token: "first-local-test-token", expiresAt: Date().addingTimeInterval(86400))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedbackLanguageURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = APIClient(session: session, tokenStore: store)
        let api = FeedbackAPI(client: client, tokenStore: store)
        let revision = await api.authSessionRevision()
        try await store.setAuth(token: "second-local-test-token", expiresAt: Date().addingTimeInterval(86400))
        do {
            _ = try await api.create(type: .feedback, title: "Feedback", content: "Old account draft", imageURLs: [], expectedAuthRevision: revision)
            XCTFail("old account submission must not be sent")
        } catch { XCTAssertTrue(error is CancellationError) }
        do {
            _ = try await api.uploadJPEG(Data([1, 2, 3]), expectedAuthRevision: revision)
            XCTFail("old account image must not be uploaded")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(FeedbackLanguageURLProtocol.requests.snapshot().isEmpty)
        let token = await store.authToken()
        XCTAssertEqual(token, "second-local-test-token")
        await store.clearAuth()
    }
}
