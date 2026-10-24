import Foundation
import XCTest
@testable import jifen

@MainActor
final class WechatCallbackRouterTests: XCTestCase {
    func testSwiftUIUniversalLinkIsForwardedToWechatUniversalLinkEntryPoint() throws {
        let url = try XCTUnwrap(URL(string: "https://jifenqi.com/app/wxcallback?code=test-code&state=test-state"))
        var receivedActivity: NSUserActivity?
        var schemeCalls = 0
        let handled = WechatCallbackRouter.handle(url: url) { _ in
            schemeCalls += 1
            return false
        } openUniversalLink: { activity in
            receivedActivity = activity
            return true
        }
        XCTAssertTrue(handled)
        XCTAssertEqual(schemeCalls, 0)
        XCTAssertEqual(receivedActivity?.activityType, NSUserActivityTypeBrowsingWeb)
        XCTAssertEqual(receivedActivity?.webpageURL, url, "the SDK must receive the original callback parameters")
    }

    func testLegacyWechatSchemeRetainsItsSDKEntryPointAndResult() throws {
        let url = try XCTUnwrap(URL(string: WechatLoginPolicy.appID + "://oauth?code=test-code"))
        var schemeCalls = 0
        var universalCalls = 0
        let handled = WechatCallbackRouter.handle(url: url) { received in
            XCTAssertEqual(received, url)
            schemeCalls += 1
            return false
        } openUniversalLink: { _ in
            universalCalls += 1
            return true
        }
        XCTAssertFalse(handled, "the SDK's handled result must propagate to the caller")
        XCTAssertEqual(schemeCalls, 1)
        XCTAssertEqual(universalCalls, 0)
    }

    func testInvitationAndUntrustedURLsNeverReachWechatSDK() throws {
        let urls = [
            "https://jifenqi.com/groups/join?groupNo=123456",
            "https://jifenqi.com/app", "https://jifenqi.com/application/callback",
            "http://jifenqi.com/app/callback", "https://jifenqi.com.evil.example/app/callback",
            "https://evil.example/app/callback", "https://jifenqi.com@evil.example/app/callback",
            "https://user@jifenqi.com/app/callback", "https://jifenqi.com:8443/app/callback"
        ]
        for value in urls {
            let url = try XCTUnwrap(URL(string: value))
            var sdkCalls = 0
            let handled = WechatCallbackRouter.handle(url: url) { _ in
                sdkCalls += 1
                return true
            } openUniversalLink: { _ in
                sdkCalls += 1
                return true
            }
            XCTAssertFalse(handled, value)
            XCTAssertEqual(sdkCalls, 0, value)
        }
    }

    func testUniversalLinkSDKRejectionIsNotReportedAsHandled() throws {
        let url = try XCTUnwrap(URL(string: "https://jifenqi.com/app/callback"))
        var universalCalls = 0
        let handled = WechatCallbackRouter.handle(url: url) { _ in
            XCTFail("Universal Links must not use the legacy scheme handler")
            return true
        } openUniversalLink: { _ in
            universalCalls += 1
            return false
        }
        XCTAssertFalse(handled)
        XCTAssertEqual(universalCalls, 1)
    }
}

private nonisolated final class BindingReplyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: (() -> Void)?
    private var released = false

    func hold(_ reply: @escaping () -> Void) {
        lock.lock()
        if released { lock.unlock(); reply() }
        else { pending = reply; lock.unlock() }
    }

    func release() {
        lock.lock(); released = true; let reply = pending; pending = nil; lock.unlock()
        reply?()
    }
}

private nonisolated final class BindingRequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URLRequest] = []
    func append(_ value: URLRequest) {
        var captured = value
        if captured.httpBody == nil, let stream = value.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            captured.httpBody = data
        }
        lock.lock(); values.append(captured); lock.unlock()
    }
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return values }
}

@MainActor private struct FlowBindingAuthorizer: WechatBindingAuthorizing {
    var authorize: @MainActor () async throws -> String
    func authorizeForBinding() async throws -> String { try await authorize() }
}

@MainActor private final class FlowBindingContext {
    var value: WechatBindingSessionContext?
}

private nonisolated final class BindingURLProtocol: URLProtocol, @unchecked Sendable {
    private nonisolated final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var handlers: [String: @Sendable (BindingURLProtocol) -> Void] = [:]
        func set(_ token: String, handler: @escaping @Sendable (BindingURLProtocol) -> Void) {
            lock.lock(); defer { lock.unlock() }; handlers["Bearer " + token] = handler
        }
        func handler(for request: URLRequest) -> (@Sendable (BindingURLProtocol) -> Void)? {
            lock.lock(); defer { lock.unlock() }
            return handlers[request.value(forHTTPHeaderField: "Authorization") ?? ""]
        }
        func remove(_ token: String) {
            lock.lock(); defer { lock.unlock() }; handlers.removeValue(forKey: "Bearer " + token)
        }
    }
    private static let registry = Registry()
    static func register(_ token: String, handler: @escaping @Sendable (BindingURLProtocol) -> Void) {
        registry.set(token, handler: handler)
    }
    static func unregister(_ token: String) { registry.remove(token) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.registry.handler(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled)); return
        }
        handler(self)
    }
    override func stopLoading() {}
    func fail(_ error: URLError) { client?.urlProtocol(self, didFailWithError: error) }
    func reply(status: Int = 200, body: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
final class WechatBindingTests: XCTestCase {
    nonisolated private static let unbound = #"{"sessionProvider":"apple","providers":["apple"],"capabilities":{"wechatBinding":true,"accountMerge":false},"wechat":{"bound":false,"canBind":true}}"#
    nonisolated private static let bound = #"{"sessionProvider":"apple","providers":["apple","wechat"],"capabilities":{"wechatBinding":true,"accountMerge":false},"wechat":{"bound":true,"canBind":false}}"#

    private func status(_ json: String = WechatBindingTests.unbound) throws -> WechatBindingStatus {
        try JSONDecoder().decode(WechatBindingStatus.self, from: Data(json.utf8))
    }

    private func fixture() -> (AuthTokenStore, APIClient, URLSession, String) {
        let id = UUID().uuidString
        let store = AuthTokenStore(service: "com.douhua.jifen.binding-tests." + id)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BindingURLProtocol.self]
        let session = URLSession(configuration: config)
        return (store, APIClient(session: session, tokenStore: store), session, "fake-binding-" + id)
    }

    func testEntryRequiresChineseAppleSessionAndServerCapability() throws {
        let eligible = try status()
        for language in ["zh-Hans", "zh-Hant", "zh_CN", "zh-TW"] {
            XCTAssertTrue(WechatBindingPolicy.showsEntry(isAuthenticated: true, language: language, status: eligible))
            XCTAssertTrue(WechatBindingPolicy.canBind(isAuthenticated: true, language: language, status: eligible))
        }
        XCTAssertFalse(WechatBindingPolicy.showsEntry(isAuthenticated: false, language: "zh-Hans", status: eligible))
        XCTAssertFalse(WechatBindingPolicy.showsEntry(isAuthenticated: true, language: "en", status: eligible))
        XCTAssertFalse(WechatBindingPolicy.showsEntry(isAuthenticated: true, language: "zh-Hans", status: nil))
        var disabled = eligible
        disabled.capabilities.wechatBinding = false
        XCTAssertFalse(WechatBindingPolicy.canBind(isAuthenticated: true, language: "zh-Hans", status: disabled))
        XCTAssertFalse(WechatBindingPolicy.showsEntry(isAuthenticated: true, language: "zh-Hans", status: disabled))
        var legacy = eligible
        legacy.sessionProvider = nil
        XCTAssertFalse(WechatBindingPolicy.showsEntry(isAuthenticated: true, language: "zh-Hans", status: legacy),
                       "An Apple identity linked to a legacy/WeChat session cannot prove Apple login")
        var wechatSession = try status(Self.bound)
        wechatSession.sessionProvider = "wechat"
        XCTAssertFalse(WechatBindingPolicy.showsEntry(isAuthenticated: true, language: "zh-Hans", status: wechatSession))
    }

    func testBoundAppleEntryRemainsVisibleReadOnlyWhenRolloutIsDisabled() throws {
        var bound = try status(Self.bound)
        bound.capabilities.wechatBinding = false
        XCTAssertTrue(WechatBindingPolicy.showsEntry(isAuthenticated: true, language: "zh-Hant", status: bound))
        XCTAssertFalse(WechatBindingPolicy.canBind(isAuthenticated: true, language: "zh-Hant", status: bound))
        XCTAssertFalse(bound.capabilities.accountMerge)
    }

    func testStatusUsesAuthenticatedSessionWithoutReplacingToken() async throws {
        let (store, client, session, token) = fixture()
        defer { session.invalidateAndCancel(); BindingURLProtocol.unregister(token) }
        try await store.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        let revision = await store.authSessionRevision()
        let log = BindingRequestLog(), responseBody = Self.unbound
        BindingURLProtocol.register(token) { proto in
            log.append(proto.request)
            proto.reply(body: responseBody)
        }
        let result = try await WechatBindingService(client: client).status(expectedAuthRevision: revision)
        XCTAssertEqual(result, try status())
        XCTAssertEqual(log.requests.map { $0.url?.path }, [WechatBindingEndpoint.status])
        XCTAssertEqual(log.requests.first?.httpMethod, "GET")
        XCTAssertEqual(log.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer " + token)
        let current = await store.authSnapshot()
        XCTAssertEqual(current.token, token)
        XCTAssertEqual(current.revision, revision)
        await store.clearAuth()
    }

    func testBindingRetriesUseSameAuthorizationReceiptAndNeverCallLogin() async throws {
        let (store, client, session, token) = fixture()
        defer { session.invalidateAndCancel(); BindingURLProtocol.unregister(token) }
        try await store.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        let revision = await store.authSessionRevision()
        let log = BindingRequestLog(), responseBody = "{\"success\":true,\"status\":\"bound\",\"bindings\":\(Self.bound)}"
        BindingURLProtocol.register(token) { proto in
            log.append(proto.request)
            proto.reply(body: responseBody)
        }
        let service = WechatBindingService(client: client)
        let attempt = WechatBindingAttempt(code: "fake-authorization-code", authRevision: revision)
        let first = try await service.bind(attempt)
        let retried = try await service.bind(attempt)
        XCTAssertTrue(first.bindings.wechat.bound)
        XCTAssertTrue(retried.bindings.wechat.bound)
        XCTAssertEqual(log.requests.count, 2)
        for request in log.requests {
            XCTAssertEqual(request.url?.path, WechatBindingEndpoint.bind)
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
            XCTAssertEqual(json["code"], attempt.code)
            XCTAssertEqual(json["requestId"], attempt.requestID)
            XCTAssertEqual(json["app_id"], WechatLoginPolicy.appID)
        }
        let current = await store.authSnapshot()
        XCTAssertEqual(current.token, token)
        XCTAssertEqual(current.revision, revision)
        await store.clearAuth()
    }

    func testOldAuthorizationCannotBeSentUnderAnotherSession() async throws {
        let (store, client, session, token) = fixture()
        defer { session.invalidateAndCancel(); BindingURLProtocol.unregister(token) }
        try await store.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        let attempt = WechatBindingAttempt(code: "old-authorization", authRevision: await store.authSessionRevision())
        try await store.setAuth(token: token + "-new", expiresAt: Date().addingTimeInterval(3600))
        do {
            _ = try await WechatBindingService(client: client).bind(attempt)
            XCTFail("Stale authorization must be rejected before it is sent")
        } catch { XCTAssertTrue(error is CancellationError) }
        let current = await store.authToken()
        XCTAssertEqual(current, token + "-new")
        await store.clearAuth()
    }

    func testDelayedBindingSuccessCannotReplaceNewSession() async throws {
        let (store, client, session, token) = fixture()
        defer { session.invalidateAndCancel(); BindingURLProtocol.unregister(token) }
        try await store.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        let attempt = WechatBindingAttempt(code: "fake-authorization", authRevision: await store.authSessionRevision())
        let gate = BindingReplyGate(), started = expectation(description: "binding request started")
        let responseBody = "{\"success\":true,\"status\":\"bound\",\"bindings\":\(Self.bound)}"
        BindingURLProtocol.register(token) { proto in
            started.fulfill()
            gate.hold { proto.reply(body: responseBody) }
        }
        let task = Task { try await WechatBindingService(client: client).bind(attempt) }
        await fulfillment(of: [started], timeout: 3)
        try await store.setAuth(token: token + "-new", expiresAt: Date().addingTimeInterval(3600))
        gate.release()
        do { _ = try await task.value; XCTFail("Delayed binding cannot publish into another login") }
        catch { XCTAssertTrue(error is CancellationError) }
        let current = await store.authToken()
        XCTAssertEqual(current, token + "-new")
        await store.clearAuth()
    }

    func testExistingWechatAccountConflictPreservesOriginalLogin() async throws {
        let (store, client, session, token) = fixture()
        defer { session.invalidateAndCancel(); BindingURLProtocol.unregister(token) }
        try await store.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        let revision = await store.authSessionRevision()
        BindingURLProtocol.register(token) { proto in
            proto.reply(status: 409, body: #"{"error":"ACCOUNT_MERGE_NOT_AVAILABLE","message":"merge unavailable"}"#)
        }
        do {
            _ = try await WechatBindingService(client: client).bind(
                WechatBindingAttempt(code: "fake-authorization", authRevision: revision)
            )
            XCTFail("An existing account cannot be silently replaced or merged")
        } catch let error as APIClientError {
            guard case .server(let status, let code, _, _) = error else { return XCTFail("Wrong failure: \(error)") }
            XCTAssertEqual(status, 409)
            XCTAssertEqual(code, "ACCOUNT_MERGE_NOT_AVAILABLE")
        }
        let current = await store.authSnapshot()
        XCTAssertEqual(current.token, token)
        XCTAssertEqual(current.revision, revision)
        await store.clearAuth()
    }

    func testMalformedSuccessCannotPublishBoundState() async throws {
        let (store, client, session, token) = fixture()
        defer { session.invalidateAndCancel(); BindingURLProtocol.unregister(token) }
        try await store.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        let revision = await store.authSessionRevision()
        let responseBody = "{\"success\":true,\"status\":\"bound\",\"bindings\":\(Self.unbound)}"
        BindingURLProtocol.register(token) { proto in proto.reply(body: responseBody) }
        do {
            _ = try await WechatBindingService(client: client).bind(
                WechatBindingAttempt(code: "fake-authorization", authRevision: revision)
            )
            XCTFail("The response must actually report a bound WeChat identity")
        } catch { XCTAssertEqual(error as? APIClientError, .invalidResponse) }
        await store.clearAuth()
    }
}

@MainActor
final class WechatBindingUpgradePromptTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "binding-prompt-" + UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)!
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }
    private var status: WechatBindingStatus {
        .init(sessionProvider: "apple", providers: ["apple"], capabilities: .init(wechatBinding: true, accountMerge: true),
              wechat: .init(bound: false, canBind: true))
    }
    func testActualPresentationIsOnceAcrossLaunchesAndLanguageChanges() {
        let prompt = WechatBindingUpgradePrompt(defaults: defaults, language: "zh-Hans")
        XCTAssertTrue(prompt.offer(status: status))
        prompt.markPresented()
        XCTAssertFalse(prompt.offer(status: status))
        let next = WechatBindingUpgradePrompt(defaults: defaults, language: "zh-Hant")
        XCTAssertFalse(next.offer(status: status))
    }
    func testWaitingForPresentationDoesNotConsumeReminder() {
        let prompt = WechatBindingUpgradePrompt(defaults: defaults, language: "zh-Hans")
        XCTAssertTrue(prompt.offer(status: status))
        XCTAssertTrue(prompt.offer(status: status), "A game or another sheet can defer actual presentation.")
        let next = WechatBindingUpgradePrompt(defaults: defaults, language: "zh-Hans")
        XCTAssertTrue(next.offer(status: status))
    }
    func testUnavailableStatusAndDisabledRolloutDoNotConsumeReminder() {
        let prompt = WechatBindingUpgradePrompt(defaults: defaults, language: "zh-Hans")
        XCTAssertFalse(prompt.offer(status: nil))
        var disabled = status
        disabled.capabilities.wechatBinding = false
        XCTAssertFalse(prompt.offer(status: disabled))
        XCTAssertTrue(prompt.offer(status: status))
    }
    func testChineseLanguageIndependentOfRegion() {
        for (language, expected) in [("zh-Hans", true), ("zh-Hant", true), ("zh-Hant-US", true), ("en-CN", false)] {
            let prompt = WechatBindingUpgradePrompt(defaults: defaults, language: language)
            XCTAssertEqual(prompt.offer(status: status), expected, language)
        }
    }
    func testBoundAndOtherProvidersDoNotOfferOrConsumeFutureEligibility() {
        let prompt = WechatBindingUpgradePrompt(defaults: defaults, language: "zh-Hans")
        for provider in ["apple", "wechat", "password"] {
            var ineligible = status
            ineligible.sessionProvider = provider
            ineligible.wechat.bound = provider == "apple"
            XCTAssertFalse(prompt.offer(status: ineligible))
        }
        XCTAssertTrue(prompt.offer(status: status), "A later eligible Apple login may receive the first reminder.")
    }
    func testRecordIsGlobalInsteadOfVersionOrAccountSpecific() {
        let prompt = WechatBindingUpgradePrompt(defaults: defaults, language: "zh-Hans")
        prompt.markPresented()
        XCTAssertTrue(defaults.bool(forKey: "wechat.binding.prompt.presented"))
        let anotherSession = WechatBindingUpgradePrompt(defaults: defaults, language: "zh-Hans")
        XCTAssertFalse(anotherSession.offer(status: status))
    }
}

@MainActor
final class AccountLinkContractTests: XCTestCase {
    nonisolated private static let bindings = #"{"sessionProvider":"apple","providers":["apple","wechat"],"capabilities":{"wechatBinding":true,"accountMerge":true},"wechat":{"bound":true,"canBind":false}}"#
    nonisolated private static let accounts = #"{"current":{"id":"a","uid":"10482","name":"A","avatarUrl":null,"providers":["apple"]},"wechat":{"id":"b","uid":"20836","name":"B","avatarUrl":null,"providers":["wechat"]}}"#
    private func fixture() -> (AuthTokenStore, APIClient, URLSession, String) {
        let key = UUID().uuidString
        let store = AuthTokenStore(service: "com.douhua.jifen.link-tests." + key)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BindingURLProtocol.self]
        let session = URLSession(configuration: config)
        return (store, APIClient(session: session, tokenStore: store), session, "fake-link-" + key)
    }
    func testPreparationPinsAuthorizationAndDoesNotInstallNewLogin() async throws {
        let (store, client, urlSession, token) = fixture()
        defer { urlSession.invalidateAndCancel(); BindingURLProtocol.unregister(token) }
        try await store.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        let revision = await store.authSessionRevision()
        let log = BindingRequestLog()
        let response = "{\"success\":true,\"status\":\"requires_confirmation\",\"ticket\":\"verified-ticket\",\"expiresAt\":\"2026-10-24T01:00:00Z\",\"accounts\":\(Self.accounts)}"
        BindingURLProtocol.register(token) { proto in log.append(proto.request); proto.reply(body: response) }
        let service = WechatBindingService(client: client)
        let attempt = WechatBindingAttempt(code: "fake-code", authRevision: revision)
        let prepared = try await service.prepare(attempt)
        _ = try await service.prepare(attempt)
        XCTAssertEqual(prepared.status, "requires_confirmation")
        XCTAssertEqual(log.requests.count, 2)
        XCTAssertTrue(log.requests.allSatisfy { $0.url?.path == "/api/auth/bindings/wechat/prepare" })
        let first = try XCTUnwrap(log.requests.first?.httpBody)
        let last = try XCTUnwrap(log.requests.last?.httpBody)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: first) as? [String:String],
                       try JSONSerialization.jsonObject(with: last) as? [String:String])
        let snapshot = await store.authSnapshot()
        XCTAssertEqual(snapshot.token, token)
        XCTAssertEqual(snapshot.revision, revision)
        await store.clearAuth()
    }
    func testRecoveryUsesExactVerifiedBearerAfterSourceSessionIsRevoked() async throws {
        let (store, client, urlSession, token) = fixture()
        defer { urlSession.invalidateAndCancel(); BindingURLProtocol.unregister(token) }
        try await store.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        let attempt = WechatBindingAttempt(code: "fake-code", authRevision: await store.authSessionRevision())
        let log = BindingRequestLog()
        let prepared = "{\"success\":true,\"status\":\"requires_confirmation\",\"ticket\":\"verified-ticket\",\"accounts\":\(Self.accounts)}"
        let completed = "{\"success\":true,\"status\":\"completed\",\"token\":\"new-master-token\",\"expiresAt\":\"2027-01-01T00:00:00Z\",\"user\":{\"id\":\"b\",\"role\":\"VIP\",\"plan\":\"VIP\",\"createdAt\":1},\"bindings\":\(Self.bindings)}"
        BindingURLProtocol.register(token) { proto in
            log.append(proto.request)
            proto.reply(body: proto.request.url?.path.hasSuffix("/prepare") == true ? prepared : completed)
        }
        let service = WechatBindingService(client: client)
        _ = try await service.prepare(attempt)
        await store.clearAuth()
        let operation = UUID().uuidString
        let receipt = try await service.recover(requestID: operation, ticket: "verified-ticket")
        XCTAssertEqual(receipt.authentication?.user.id, "b")
        XCTAssertEqual(log.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer " + token)
        XCTAssertEqual(log.requests.last?.url?.path, "/api/auth/bindings/requests/" + operation)
        XCTAssertFalse(log.requests.contains { $0.url?.path == "/api/auth/refresh" })
        let snapshot = await store.authSnapshot()
        XCTAssertNil(snapshot.token, "Receipt decoding alone must never install a login")
    }
    func testBlockedOrUnknownScopePreviewCannotSubmit() throws {
        let json = "{\"ticket\":\"t\",\"expiresAt\":\"2026-10-24T01:00:00Z\",\"mode\":\"merge\",\"masterUserId\":\"a\",\"previewToken\":\"snapshot-v1\",\"accounts\":\(Self.accounts),\"summary\":{\"groups\":{\"groupCount\":4,\"recordCount\":21,\"selfMatchCount\":1},\"assets\":{\"commonNameCount\":27,\"commonPlaceCount\":2}},\"blockers\":[{\"code\":\"ACTIVE_MATCH\",\"message\":\"active\"}],\"warnings\":[],\"canConfirm\":true,\"dataScope\":\"cloud\"}"
        var preview = try JSONDecoder().decode(AccountLinkPreview.self, from: Data(json.utf8))
        XCTAssertFalse(preview.canSubmit)
        preview.blockers = []
        XCTAssertTrue(preview.canSubmit)
        preview.dataScope = "unknown"
        XCTAssertFalse(preview.canSubmit)
        XCTAssertEqual(preview.summary.groups.selfMatchCount, 1)
        XCTAssertEqual(preview.masterAccount.id, "a")
        XCTAssertNil(preview.summary.assets.automaticRenewalCount)
        XCTAssertNil(preview.summary.assets.warnings)
        XCTAssertFalse(preview.summary.assets.showsAutomaticRenewalWarning)
    }
    func testPreviewShowsMultipleRenewalWarningWithoutBlockingEitherLinkMode() throws {
        let warning = "双方订阅将保留各自续费状态。账号合并不会替你取消任何自动续费。"
        for mode in ["merge", "keep"] {
            for count in [0, 1, 2, 3] {
                let assetWarnings = count > 1 ? [warning] : []
                let assets: [String: Any] = ["automaticRenewalCount": count, "warnings": assetWarnings]
                let data = try JSONSerialization.data(withJSONObject: assets)
                let assetsJSON = try XCTUnwrap(String(data: data, encoding: .utf8))
                let json = "{\"ticket\":\"t\",\"expiresAt\":\"2026-10-24T01:00:00Z\",\"mode\":\"\(mode)\",\"masterUserId\":\"a\",\"previewToken\":\"snapshot-v1\",\"accounts\":\(Self.accounts),\"summary\":{\"groups\":{},\"assets\":\(assetsJSON)},\"blockers\":[],\"warnings\":[],\"canConfirm\":true,\"dataScope\":\"cloud\"}"
                let preview = try JSONDecoder().decode(AccountLinkPreview.self, from: Data(json.utf8))
                XCTAssertEqual(preview.summary.assets.automaticRenewalCount, count)
                XCTAssertEqual(preview.summary.assets.warnings, assetWarnings)
                XCTAssertEqual(preview.summary.assets.showsAutomaticRenewalWarning, count > 1)
                XCTAssertTrue(preview.canSubmit, "a renewal warning must not prevent confirming \(mode)")
                XCTAssertTrue(preview.warnings.isEmpty, "asset warnings are nested separately from general warnings")
            }
        }
    }
    func testRenewalWarningUsesCountAndRecognizesWarningOnlyResponses() throws {
        let assets = try JSONDecoder().decode(AccountLinkPreview.Assets.self,
            from: Data(#"{"automaticRenewalCount":2}"#.utf8))
        XCTAssertTrue(assets.showsAutomaticRenewalWarning, "the count remains sufficient if warning wording changes")
        let warningOnly = try JSONDecoder().decode(AccountLinkPreview.Assets.self,
            from: Data(#"{"warnings":["双方订阅将保留各自续费状态。账号合并不会替你取消任何自动续费。"]}"#.utf8))
        XCTAssertTrue(warningOnly.showsAutomaticRenewalWarning)
        let unrelatedWarning = try JSONDecoder().decode(AccountLinkPreview.Assets.self,
            from: Data(#"{"warnings":["A future asset warning"]}"#.utf8))
        XCTAssertFalse(unrelatedWarning.showsAutomaticRenewalWarning, "unrelated asset warnings must not be relabeled as subscriptions")
    }
    func testLoginMethodsUseSlashAndDeduplicateHuaweiFamily() {
        XCTAssertEqual(AccountLoginMethodText.joined(["apple", "wechat", "apple"]).components(separatedBy: " / ").count, 2)
        XCTAssertEqual(AccountLoginMethodText.joined(["huawei", "huawei_android"]).components(separatedBy: " / ").count, 1)
    }
    func testWechatLoginMethodUsesProviderNameAcrossLanguages() throws {
        for (locale, name) in [("en", "WeChat"), ("zh-Hans", "微信"), ("zh-Hant", "微信")] {
            let path = LocalizationTestSupport.repositoryRoot
                .appendingPathComponent("jifen/Resources/\(locale).lproj").path
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertEqual(AccountLoginMethodText.joined(["wechat"], bundle: bundle), name, locale)
            XCTAssertEqual(AccountLoginMethodText.joined(["apple", "wechat", "wechat"], bundle: bundle),
                           "Apple / \(name)", locale)
        }
    }
}

@MainActor final class AccountLinkGroupIdentityTests: XCTestCase {
    private var group: ScoreGroup {
        .init(id: "g", groupNo: "12345678", name: "Group", description: "", sport: .badminton,
              status: "active", joinPolicy: "open", ownerMemberId: "owner", memberLimit: 30,
              createdAt: 0, updatedAt: 0, revision: 1)
    }
    private func member(role: String = "member") -> GroupMember {
        var value = GroupMember(id: "canonical", groupId: "g", kind: "account", role: role,
                                status: "active", displayName: "Me", accountId: "account", joinedAt: 0)
        value.legacyMemberIds = ["source-alias"]
        return value
    }
    private func result(submitter: String, canonicalSubmitter: String?) -> GroupResult {
        var value = GroupResult(id: "r", groupId: "g", activityId: "", gameId: "", format: .singles,
            sport: .badminton, setScore: .init(a: 1, b: 0),
            participants: [.init(memberId: "source-alias", side: "A", seat: 0, canonicalMemberId: "canonical", countsForPersonalStats: false),
                           .init(memberId: "other", side: "B", seat: 0)], playedAt: 0,
            submitterMemberId: submitter, confirmedByMemberId: "", status: "pending_confirmation", source: "manual",
            reason: "", createdAt: 0, revision: 1)
        value.submitterCanonicalMemberId = canonicalSubmitter
        return value
    }
    func testAliasParticipantRetainsRawSeatAndBelongsToCurrentMember() throws {
        let seat = result(submitter: "other", canonicalSubmitter: "other").participants[0]
        XCTAssertEqual(seat.memberId, "source-alias")
        XCTAssertTrue(seat.belongs(to: member()))
        XCTAssertEqual(seat.countsForPersonalStats, false)
        let decoded = try JSONDecoder().decode(GroupSeat.self, from: JSONEncoder().encode(seat))
        XCTAssertEqual(decoded.memberId, "source-alias")
        XCTAssertEqual(decoded.canonicalMemberId, "canonical")
    }
    func testMergedAliasCannotConfirmOwnHistoricalSubmissionEvenAsAdmin() {
        let value = result(submitter: "source-alias", canonicalSubmitter: "canonical")
        XCTAssertFalse(GroupPermissions.confirmation(value, group: group, me: member(role: "admin")).allowed)
    }
    func testHistoricalAliasCanConfirmIndependentOpponentSubmission() {
        let value = result(submitter: "other", canonicalSubmitter: "other")
        XCTAssertTrue(GroupPermissions.confirmation(value, group: group, me: member()).allowed)
    }
}

extension AccountLinkContractTests {
    private struct LiveLinkFixture {
        let store: AuthTokenStore
        let client: APIClient
        let transport: URLSession
        let token: String
        let session: SessionStore
        let defaults: UserDefaults

        func cleanup() async {
            transport.invalidateAndCancel()
            BindingURLProtocol.unregister(token)
            defaults.removePersistentDomain(forName: token)
            await store.clearAuth()
        }
    }

    private func restoredLinkFixture() async throws -> LiveLinkFixture {
        let (store, client, transport, token) = fixture()
        try await store.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        BindingURLProtocol.register(token) { proto in
            proto.reply(body: proto.request.url?.path == "/api/auth/me"
                ? #"{"id":"original-account","role":"FREE","plan":"FREE","createdAt":1}"# : Self.bindings)
        }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: token))
        let session = SessionStore(client: client, tokenStore: store,
            postAuthenticationWarmup: { _ in }, postAccountLinkCleanup: { _ in }, defaults: defaults)
        await session.restore()
        XCTAssertTrue(session.isAuthenticated)
        return LiveLinkFixture(store: store, client: client, transport: transport, token: token,
                               session: session, defaults: defaults)
    }

    private func linkedResponse(token: String) -> AuthResponse {
        AuthResponse(user: AppUser(id: "linked-master", role: "VIP", plan: "VIP", createdAt: 1),
                     token: token, expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600)))
    }

    private func mergeWhileSourceRequestExpires(loseConfirmation: Bool) async throws {
        let f = try await restoredLinkFixture()
        let oldRequestGate = BindingReplyGate(), confirmGate = BindingReplyGate()
        defer { oldRequestGate.release(); confirmGate.release() }
        let context = try await f.session.beginWechatBinding()
        let service = WechatBindingService(client: f.client)
        let linkedToken = "linked-" + UUID().uuidString
        let oldRequestStarted = expectation(description: "source profile request is in flight")
        let confirmStarted = expectation(description: "confirm is in flight while source token is revoked")
        let expiry = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
        let prepared = "{\"success\":true,\"status\":\"requires_confirmation\",\"ticket\":\"verified-ticket\",\"accounts\":\(Self.accounts)}"
        let completed = "{\"success\":true,\"status\":\"completed\",\"token\":\"\(linkedToken)\",\"expiresAt\":\"\(expiry)\",\"user\":{\"id\":\"linked-master\",\"role\":\"VIP\",\"plan\":\"VIP\",\"createdAt\":1},\"bindings\":\(Self.bindings)}"
        let log = BindingRequestLog()
        BindingURLProtocol.register(f.token) { proto in
            log.append(proto.request)
            switch proto.request.url?.path {
            case "/api/auth/me":
                oldRequestStarted.fulfill()
                oldRequestGate.hold { proto.reply(status: 401, body: #"{"error":"SESSION_REVOKED"}"#) }
            case "/api/auth/refresh": proto.reply(status: 401, body: #"{"error":"SESSION_REVOKED"}"#)
            case "/api/auth/bindings/wechat/prepare": proto.reply(body: prepared)
            case "/api/auth/bindings/confirm":
                confirmStarted.fulfill()
                confirmGate.hold {
                    if loseConfirmation { proto.fail(URLError(.networkConnectionLost)) }
                    else { proto.reply(body: completed) }
                }
            default: proto.reply(body: completed)
            }
        }
        _ = try await service.prepare(WechatBindingAttempt(code: "fake-code", authRevision: context.authRevision))
        let oldProfile = Task { await f.session.reloadProfile() }
        await fulfillment(of: [oldRequestStarted], timeout: 3)
        let requestID = UUID().uuidString
        let confirming = Task { try await service.confirm(ticket: "verified-ticket", previewToken: "preview", requestID: requestID) }
        await fulfillment(of: [confirmStarted], timeout: 3)
        oldRequestGate.release()
        await oldProfile.value
        XCTAssertTrue(f.session.isAuthenticated, "direct profile error handling must also defer source expiry")
        XCTAssertEqual(f.session.user?.id, "original-account")
        XCTAssertNil(f.session.lastError)
        let expiredSource = await f.store.authSnapshot()
        XCTAssertNil(expiredSource.token)
        XCTAssertEqual(expiredSource.revision, context.authRevision + 1)
        confirmGate.release()
        let result: AccountLinkResponse
        if loseConfirmation {
            do { _ = try await confirming.value; XCTFail("the confirmation response was lost") }
            catch { XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost) }
            result = try await service.recover(requestID: requestID, ticket: "verified-ticket")
        } else { result = try await confirming.value }
        try await f.session.applyLinkedAccount(try XCTUnwrap(result.authentication),
            bindings: try XCTUnwrap(result.bindings), context: context)
        await f.session.endWechatBinding(context)
        let current = await f.store.authSnapshot()
        XCTAssertEqual(current.token, linkedToken)
        XCTAssertTrue(f.session.isAuthenticated)
        XCTAssertEqual(f.session.user?.id, "linked-master")
        XCTAssertNil(f.session.lastError)
        XCTAssertFalse(f.session.isWorking)
        XCTAssertFalse(f.session.isWechatBindingSessionActive)
        XCTAssertEqual(log.requests.filter { $0.url?.path == "/api/auth/refresh" }.count, 1)
        await f.cleanup()
    }

    func testRealSource401BeforeConfirmResponseKeepsLinkedAccountSignedIn() async throws {
        try await mergeWhileSourceRequestExpires(loseConfirmation: false)
    }

    func testLostConfirmResponseRecoversAfterRealSource401WithoutSigningOut() async throws {
        try await mergeWhileSourceRequestExpires(loseConfirmation: true)
    }

    func testClosingExpiredBindingSignsOutAndReleasesLoginGuard() async throws {
        let f = try await restoredLinkFixture()
        let context = try await f.session.beginWechatBinding()
        BindingURLProtocol.register(f.token) { $0.reply(status: 401, body: #"{"error":"SESSION_REVOKED"}"#) }
        await f.session.reloadProfile()
        XCTAssertTrue(f.session.isAuthenticated)
        await f.session.endWechatBinding(context)
        XCTAssertFalse(f.session.isAuthenticated)
        XCTAssertFalse(f.session.isWorking)
        XCTAssertFalse(f.session.isWechatBindingSessionActive)
        XCTAssertNotNil(f.session.lastError)
        await f.cleanup()
    }

    func testNewLinkedSessionExpiryIsNotSuppressedBeforeSheetCloses() async throws {
        let f = try await restoredLinkFixture()
        let context = try await f.session.beginWechatBinding()
        let linkedToken = "linked-" + UUID().uuidString
        defer { BindingURLProtocol.unregister(linkedToken) }
        try await f.session.applyLinkedAccount(linkedResponse(token: linkedToken),
            bindings: JSONDecoder().decode(WechatBindingStatus.self, from: Data(Self.bindings.utf8)), context: context)
        BindingURLProtocol.register(linkedToken) { $0.reply(status: 401, body: #"{"error":"SESSION_REVOKED"}"#) }
        await f.session.reloadProfile()
        XCTAssertFalse(f.session.isAuthenticated, "the success sheet must not swallow genuine replacement-session expiry")
        await f.session.endWechatBinding(context)
        await f.cleanup()
    }

    func testOld401AfterLinkedSwapCannotKickOrRefreshReplacement() async throws {
        let f = try await restoredLinkFixture()
        let context = try await f.session.beginWechatBinding()
        let gate = BindingReplyGate(), started = expectation(description: "old profile request in flight")
        defer { gate.release() }
        let log = BindingRequestLog()
        BindingURLProtocol.register(f.token) { proto in
            log.append(proto.request)
            started.fulfill()
            gate.hold { proto.reply(status: 401, body: #"{"error":"SESSION_REVOKED"}"#) }
        }
        let oldProfile = Task { await f.session.reloadProfile() }
        await fulfillment(of: [started], timeout: 3)
        let linkedToken = "linked-" + UUID().uuidString
        try await f.session.applyLinkedAccount(linkedResponse(token: linkedToken),
            bindings: JSONDecoder().decode(WechatBindingStatus.self, from: Data(Self.bindings.utf8)), context: context)
        gate.release()
        await oldProfile.value
        XCTAssertEqual(log.requests.count, 1, "a stale 401 must not refresh against the replacement session")
        let current = await f.store.authToken()
        XCTAssertEqual(current, linkedToken)
        XCTAssertEqual(f.session.user?.id, "linked-master")
        XCTAssertTrue(f.session.isAuthenticated)
        XCTAssertNil(f.session.lastError)
        await f.session.endWechatBinding(context)
        await f.cleanup()
    }

    func testLogoutDuringBindingReleasesGuardAndRejectsLateConfirmation() async throws {
        let f = try await restoredLinkFixture()
        let context = try await f.session.beginWechatBinding()
        BindingURLProtocol.register(f.token) { $0.reply(body: #"{"success":true}"#) }
        await f.session.logout()
        XCTAssertFalse(f.session.isWorking)
        XCTAssertFalse(f.session.isWechatBindingSessionActive)
        do {
            try await f.session.applyLinkedAccount(linkedResponse(token: "must-not-install"),
                bindings: JSONDecoder().decode(WechatBindingStatus.self, from: Data(Self.bindings.utf8)), context: context)
            XCTFail("a late confirmation cannot undo an explicit logout")
        } catch { XCTAssertTrue(error is CancellationError) }
        await f.session.endWechatBinding(context)
        XCTAssertEqual(f.session.state, .signedOut)
        let token = await f.store.authToken()
        XCTAssertNil(token)
        await f.cleanup()
    }

    func testOldBindingCloseAndValidationCannotChangeNewBinding() async throws {
        let f = try await restoredLinkFixture()
        let oldContext = try await f.session.beginWechatBinding()
        await f.session.endWechatBinding(oldContext)
        let newContext = try await f.session.beginWechatBinding()
        XCTAssertNotEqual(oldContext, newContext)
        do { try await f.session.validateWechatBinding(oldContext); XCTFail("a closed flow must stay closed") }
        catch { XCTAssertTrue(error is CancellationError) }
        await f.session.endWechatBinding(oldContext)
        XCTAssertTrue(f.session.isWechatBindingSessionActive)
        XCTAssertTrue(f.session.isWorking)
        try await f.session.validateWechatBinding(newContext)
        await f.session.endWechatBinding(newContext)
        await f.cleanup()
    }

    func testLogoutDuringLinkedAccountCleanupCannotRestartOldWarmupOrRestoreSession() async throws {
        let (store, client, urlSession, token) = fixture()
        let linkedToken = "fake-linked-" + UUID().uuidString
        let suiteName = "com.douhua.jifen.link-cleanup-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let gate = BindingReplyGate()
        defer {
            gate.release()
            urlSession.invalidateAndCancel()
            BindingURLProtocol.unregister(token)
            BindingURLProtocol.unregister(linkedToken)
            defaults.removePersistentDomain(forName: suiteName)
        }
        try await store.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        let originalProfile = #"{"id":"original-account","role":"FREE","plan":"FREE","createdAt":1}"#
        let unbound = #"{"sessionProvider":"apple","providers":["apple"],"capabilities":{"wechatBinding":true,"accountMerge":true},"wechat":{"bound":false,"canBind":true}}"#
        BindingURLProtocol.register(token) { proto in
            proto.reply(body: proto.request.url?.path == "/api/auth/me" ? originalProfile : unbound)
        }
        BindingURLProtocol.register(linkedToken) { proto in
            XCTAssertEqual(proto.request.url?.path, "/api/auth/logout")
            proto.reply(body: #"{"success":true}"#)
        }
        let cleanupStarted = expectation(description: "linked account cleanup is suspended")
        var warmedUsers: [String?] = []
        let session = SessionStore(client: client, tokenStore: store,
            postAuthenticationWarmup: { userID in warmedUsers.append(userID) },
            postAccountLinkCleanup: { userID in
                XCTAssertEqual(userID, "linked-master")
                cleanupStarted.fulfill()
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    gate.hold { continuation.resume() }
                }
            }, defaults: defaults)
        await session.restore()
        XCTAssertEqual(session.user?.id, "original-account")
        warmedUsers.removeAll()
        let context = try await session.beginWechatBinding()
        let linkedUser = AppUser(id: "linked-master", role: "VIP", plan: "VIP", createdAt: 1)
        let response = AuthResponse(user: linkedUser, token: linkedToken,
            expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600)))
        let status = try JSONDecoder().decode(WechatBindingStatus.self, from: Data(Self.bindings.utf8))
        let applying = Task { try await session.applyLinkedAccount(response, bindings: status, context: context) }
        await fulfillment(of: [cleanupStarted], timeout: 3)
        XCTAssertTrue(session.isWorking, "new logins stay serialized until the merged cloud baseline finishes")
        XCTAssertEqual(session.user?.id, "linked-master")
        await session.logout()
        XCTAssertFalse(session.isAuthenticated)
        gate.release()
        do {
            try await applying.value
            XCTFail("logout must cancel the remaining account-link warmup")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(warmedUsers.isEmpty, "the interrupted merge must not reactivate its old user in shared stores")
        XCTAssertFalse(session.isWorking, "interrupted cleanup must release the sign-in guard")
        XCTAssertEqual(session.state, .signedOut)
        XCTAssertNil(session.user)
        let finalToken = await store.authToken()
        XCTAssertNil(finalToken, "late cleanup completion must not resurrect credentials")
        await store.clearAuth()
    }

    func testAtomicExpiryDuringActiveBindingDoesNotKickAndApplyStillSwaps() async throws {
        let (store, client, urlSession, token) = fixture()
        let linkedToken = "fake-linked-" + UUID().uuidString
        let suiteName = "com.douhua.jifen.binding-expiry-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            urlSession.invalidateAndCancel()
            BindingURLProtocol.unregister(token)
            BindingURLProtocol.unregister(linkedToken)
            defaults.removePersistentDomain(forName: suiteName)
        }
        try await store.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        let originalProfile = #"{"id":"original-account","role":"FREE","plan":"FREE","createdAt":1}"#
        BindingURLProtocol.register(token) { proto in
            proto.reply(body: proto.request.url?.path == "/api/auth/me" ? originalProfile : Self.bindings)
        }
        let session = SessionStore(client: client, tokenStore: store, postAccountLinkCleanup: { _ in }, defaults: defaults)
        await session.restore()
        XCTAssertEqual(session.user?.id, "original-account")
        let context = try await session.beginWechatBinding()
        try await session.validateWechatBinding(context)
        XCTAssertTrue(session.isWechatBindingSessionActive)

        // 旧令牌 401 的原子过期：令牌清空、代际 +1，但踢出被抑制，user 仍显示原账号。
        await store.clearAuth()

        let linkedUser = AppUser(id: "linked-master", role: "VIP", plan: "VIP", createdAt: 1)
        let response = AuthResponse(user: linkedUser, token: linkedToken,
            expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600)))
        let status = try JSONDecoder().decode(WechatBindingStatus.self, from: Data(Self.bindings.utf8))
        try await session.applyLinkedAccount(response, bindings: status, context: context)
        XCTAssertEqual(session.user?.id, "linked-master")
        XCTAssertTrue(session.isAuthenticated)

        await session.endWechatBinding(context)
        XCTAssertFalse(session.isWechatBindingSessionActive)
        await store.clearAuth()
    }

    func testConfirmCannotBeSentAfterAnotherLoginStarts() async throws {
        let (store, client, urlSession, token) = fixture()
        defer { urlSession.invalidateAndCancel(); BindingURLProtocol.unregister(token) }
        try await store.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        let attempt = WechatBindingAttempt(code: "fake-code", authRevision: await store.authSessionRevision())
        let log = BindingRequestLog()
        let body = "{\"success\":true,\"status\":\"requires_confirmation\",\"ticket\":\"verified-ticket\",\"accounts\":\(Self.accounts)}"
        BindingURLProtocol.register(token) { proto in log.append(proto.request); proto.reply(body: body) }
        let service = WechatBindingService(client: client)
        _ = try await service.prepare(attempt)
        try await store.setAuth(token: "different-login", expiresAt: Date().addingTimeInterval(3600))
        do {
            _ = try await service.confirm(ticket: "verified-ticket", previewToken: "preview", requestID: UUID().uuidString)
            XCTFail("A stale flow must not start a server-side merge")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(log.requests.count, 1)
        XCTAssertFalse(log.requests.contains { $0.url?.path.hasSuffix("/confirm") == true })
        await store.clearAuth()
    }
    func testPendingAndExpiredReceiptsDecodeWithoutInventingSuccess() throws {
        for state in ["not_found", "expired"] {
            let value = try JSONDecoder().decode(AccountLinkResponse.self, from: Data("{\"status\":\"\(state)\"}".utf8))
            XCTAssertEqual(value.status, state)
            XCTAssertNil(value.success)
            XCTAssertNil(value.authentication)
        }
    }
}

extension AccountLinkContractTests {
    func testClosingBindingBeforeContextReturnsReleasesLateContext() async throws {
        let fixture = try await restoredLinkFixture()
        let gate = BindingReplyGate()
        defer { gate.release() }
        let began = expectation(description: "binding context created before the model receives it")
        let model = WechatBindingFlowModel(beginBinding: { session in
            let context = try await session.beginWechatBinding()
            began.fulfill()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                gate.hold { continuation.resume() }
            }
            return context
        })
        let starting = Task { await model.start(session: fixture.session) }
        await fulfillment(of: [began], timeout: 3)
        XCTAssertTrue(model.busy, "the initial session setup must block sheet controls")
        XCTAssertTrue(fixture.session.isWechatBindingSessionActive)

        await model.close(session: fixture.session)
        gate.release()
        await starting.value

        XCTAssertFalse(model.busy)
        XCTAssertFalse(fixture.session.isWorking)
        XCTAssertFalse(fixture.session.isWechatBindingSessionActive, "a closed sheet must release a late context")
        XCTAssertTrue(fixture.session.isAuthenticated)
        await fixture.cleanup()
    }

    func testCancellingBindingBeforeContextReturnsReleasesLateContext() async throws {
        let fixture = try await restoredLinkFixture()
        let gate = BindingReplyGate()
        defer { gate.release() }
        let began = expectation(description: "binding context created before cancellation")
        let model = WechatBindingFlowModel(beginBinding: { session in
            let context = try await session.beginWechatBinding()
            began.fulfill()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                gate.hold { continuation.resume() }
            }
            return context
        })
        let starting = Task { await model.start(session: fixture.session) }
        await fulfillment(of: [began], timeout: 3)
        starting.cancel()
        gate.release()
        await starting.value

        XCTAssertFalse(model.busy)
        XCTAssertFalse(fixture.session.isWorking)
        XCTAssertFalse(fixture.session.isWechatBindingSessionActive)
        XCTAssertTrue(fixture.session.isAuthenticated)
        await fixture.cleanup()
    }
}

extension AccountLinkContractTests {
    private struct FlowLinkFixture {
        let store: AuthTokenStore
        let transport: URLSession
        let token: String
        let linkedToken: String
        let session: SessionStore
        let commonData: CommonDataCloudSyncManager
        let model: WechatBindingFlowModel
        let log: BindingRequestLog
        let defaults: UserDefaults
        let localData: [(String, Any?)]

        func cleanup() async {
            await model.close(session: session)
            await commonData.sessionDidChange(userId: nil)
            transport.invalidateAndCancel()
            BindingURLProtocol.unregister(token)
            BindingURLProtocol.unregister(linkedToken)
            defaults.removePersistentDomain(forName: token)
            for (key, value) in localData { UserDefaults.standard.set(value, forKey: key) }
            await store.clearAuth()
        }
    }

    private func flowLinkFixture(
        authorizer: any WechatBindingAuthorizing,
        confirm: @escaping @Sendable (BindingURLProtocol, String) -> Void
    ) async throws -> FlowLinkFixture {
        let (store, client, transport, token) = fixture()
        let linkedToken = "linked-flow-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: token))
        let localData = ["commonTeamNames", "commonPlayerNames", "jifen-v2.commonPlaces"]
            .map { ($0, UserDefaults.standard.object(forKey: $0)) }
        let commonData = CommonDataCloudSyncManager(client: client, defaults: defaults)
        let context = FlowBindingContext(), log = BindingRequestLog()
        let accounts = #"{"current":{"id":"original-account","uid":"10482","providers":["apple"]},"wechat":{"id":"linked-master","uid":"20836","providers":["wechat"]}}"#
        let prepared = "{\"success\":true,\"status\":\"requires_confirmation\",\"ticket\":\"flow-ticket\",\"accounts\":\(accounts)}"
        let preview = "{\"ticket\":\"flow-ticket\",\"expiresAt\":\"2027-01-01T00:00:00Z\",\"mode\":\"merge\",\"masterUserId\":\"linked-master\",\"previewToken\":\"flow-preview\",\"accounts\":\(accounts),\"summary\":{\"groups\":{},\"assets\":{}},\"blockers\":[],\"warnings\":[],\"canConfirm\":true,\"dataScope\":\"cloud\"}"
        let expiry = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
        let completed = "{\"success\":true,\"status\":\"completed\",\"token\":\"\(linkedToken)\",\"expiresAt\":\"\(expiry)\",\"user\":{\"id\":\"linked-master\",\"role\":\"VIP\",\"plan\":\"VIP\",\"createdAt\":1},\"bindings\":\(Self.bindings)}"
        let linkedBaseline = #"{"names":[{"type":"TEAM","name":"Linked baseline","useCount":0,"lastUsed":0,"createTime":1,"updatedAt":1}],"places":[],"serverTime":1}"#
        BindingURLProtocol.register(token) { proto in
            log.append(proto.request)
            switch proto.request.url?.path {
            case "/api/auth/me": proto.reply(body: #"{"id":"original-account","role":"FREE","plan":"FREE","createdAt":1}"#)
            case "/api/auth/bindings": proto.reply(body: Self.bindings)
            case "/api/common-data/sync": proto.reply(body: #"{"names":[],"places":[],"serverTime":1}"#)
            case "/api/auth/bindings/wechat/prepare": proto.reply(body: prepared)
            case "/api/auth/bindings/preview": proto.reply(body: preview)
            case "/api/auth/bindings/confirm": confirm(proto, completed)
            default: XCTFail("unexpected source request: \(proto.request.url?.path ?? "")"); proto.fail(URLError(.unsupportedURL))
            }
        }
        BindingURLProtocol.register(linkedToken) { proto in
            log.append(proto.request)
            switch proto.request.url?.path {
            case "/api/common-data", "/api/common-data/sync": proto.reply(body: linkedBaseline)
            default: XCTFail("unexpected linked request: \(proto.request.url?.path ?? "")"); proto.fail(URLError(.unsupportedURL))
            }
        }
        try await store.setAuth(token: token, expiresAt: Date().addingTimeInterval(3600))
        let session = SessionStore(client: client, tokenStore: store,
            postAuthenticationWarmup: { userID in await commonData.sessionDidChange(userId: userID) },
            postAccountLinkCleanup: { userID in
                guard let context = context.value else { XCTFail("binding context was not captured"); return }
                do { try await commonData.completeAccountLink(userID: userID, context: context) }
                catch { XCTFail("committed baseline installation failed: \(error)") }
            }, defaults: defaults)
        await session.restore()
        XCTAssertTrue(session.isAuthenticated)
        let model = WechatBindingFlowModel(service: WechatBindingService(client: client),
            authorizer: authorizer, commonData: commonData, beginBinding: { session in
                let value = try await session.beginWechatBinding()
                context.value = value
                return value
            })
        return .init(store: store, transport: transport, token: token, linkedToken: linkedToken,
                     session: session, commonData: commonData, model: model, log: log,
                     defaults: defaults, localData: localData)
    }

    func testFlowClosingPendingConfirmationStillInstallsLinkedCredentialsAndBaseline() async throws {
        let gate = BindingReplyGate()
        defer { gate.release() }
        let requested = expectation(description: "confirmation is in flight")
        let f = try await flowLinkFixture(authorizer: FlowBindingAuthorizer { "fake-code" }) { proto, completed in
            requested.fulfill()
            gate.hold { proto.reply(body: completed) }
        }
        await f.model.start(session: f.session)
        f.model.showOptions()
        f.model.masterUserID = "linked-master"
        await f.model.loadPreview(session: f.session)
        XCTAssertEqual(f.model.stage, .preview)
        let confirming = Task { await f.model.confirm(session: f.session) }
        await fulfillment(of: [requested], timeout: 3)
        await f.model.close(session: f.session)
        XCTAssertTrue(f.session.isWorking, "closing must preserve a committed confirmation's session lease")
        XCTAssertTrue(f.session.isWechatBindingSessionActive)
        let syncCount = f.log.requests.filter { $0.url?.path == "/api/common-data/sync" }.count
        await f.commonData.forceSync()
        XCTAssertEqual(f.log.requests.filter { $0.url?.path == "/api/common-data/sync" }.count, syncCount)
        gate.release()
        await confirming.value
        XCTAssertEqual(f.model.stage, .success)
        XCTAssertFalse(f.model.busy)
        XCTAssertFalse(f.session.isWorking)
        XCTAssertFalse(f.session.isWechatBindingSessionActive)
        XCTAssertEqual(f.session.user?.id, "linked-master")
        let snapshot = await f.store.authSnapshot()
        XCTAssertEqual(snapshot.token, f.linkedToken)
        XCTAssertEqual(f.commonData.phase, .synced)
        XCTAssertEqual(CommonNamesManager.shared.getNames(type: .team), ["Linked baseline"])
        let linkedRequests = f.log.requests.filter { $0.value(forHTTPHeaderField: "Authorization") == "Bearer " + f.linkedToken }
        XCTAssertEqual(linkedRequests.first?.url?.path, "/api/common-data", "pull the committed baseline before any replacement-session upload")
        XCTAssertTrue(linkedRequests.contains { $0.url?.path == "/api/common-data/sync" })
        await f.cleanup()
    }

    func testFlowClosingReauthorizationAfterExpiredConfirmReleasesPauseAndRejectsLateCode() async throws {
        let gate = BindingReplyGate()
        defer { gate.release() }
        let reauthorizing = expectation(description: "replacement authorization is waiting")
        var authorizationCount = 0
        let authorizer = FlowBindingAuthorizer {
            authorizationCount += 1
            if authorizationCount == 1 { return "first-code" }
            reauthorizing.fulfill()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                gate.hold { continuation.resume() }
            }
            return "late-code"
        }
        let f = try await flowLinkFixture(authorizer: authorizer) { proto, _ in
            proto.reply(status: 410, body: #"{"error":"LINK_EXPIRED"}"#)
        }
        await f.model.start(session: f.session)
        f.model.showOptions()
        f.model.masterUserID = "linked-master"
        await f.model.loadPreview(session: f.session)
        await f.model.confirm(session: f.session)
        XCTAssertEqual(f.model.errorMessage, bindingText("authorization_expired"))
        let retrying = Task { await f.model.retry(session: f.session) }
        await fulfillment(of: [reauthorizing], timeout: 3)
        let syncCount = f.log.requests.filter { $0.url?.path == "/api/common-data/sync" }.count
        await f.model.close(session: f.session)
        XCTAssertFalse(f.session.isWorking, "reauthorizing is not an in-flight confirmation")
        XCTAssertFalse(f.session.isWechatBindingSessionActive)
        XCTAssertGreaterThan(f.log.requests.filter { $0.url?.path == "/api/common-data/sync" }.count, syncCount)
        XCTAssertEqual(f.commonData.phase, .synced)
        gate.release()
        await retrying.value
        XCTAssertTrue(f.model.cancelled)
        XCTAssertFalse(f.model.busy)
        XCTAssertEqual(f.log.requests.filter { $0.url?.path == "/api/auth/bindings/wechat/prepare" }.count, 1,
                       "a late authorization must not prepare another link after closing")
        XCTAssertEqual(f.session.user?.id, "original-account")
        let snapshot = await f.store.authSnapshot()
        XCTAssertEqual(snapshot.token, f.token)
        await f.commonData.forceSync()
        XCTAssertEqual(f.commonData.phase, .synced)
        await f.cleanup()
    }

    func testFlowPresentsWechatAuthorizationErrorsAndTreatsCancellationSeparately() async throws {
        for error in [WechatAuthError.notInstalled, .requestFailed, .denied, .timeout, .cancelled] {
            let f = try await flowLinkFixture(authorizer: FlowBindingAuthorizer { throw error }) { proto, _ in
                XCTFail("authorization failure must never submit a confirmation")
                proto.fail(URLError(.unsupportedURL))
            }
            await f.model.start(session: f.session)
            XCTAssertFalse(f.model.busy)
            XCTAssertEqual(f.model.cancelled, error == .cancelled)
            if error == .cancelled { XCTAssertNil(f.model.errorMessage) }
            else { XCTAssertEqual(f.model.errorMessage, error.localizedDescription) }
            XCTAssertFalse(f.log.requests.contains { $0.url?.path == "/api/auth/bindings/wechat/prepare" })
            await f.model.close(session: f.session)
            XCTAssertFalse(f.session.isWorking)
            XCTAssertFalse(f.session.isWechatBindingSessionActive)
            await f.cleanup()
        }
    }
}
