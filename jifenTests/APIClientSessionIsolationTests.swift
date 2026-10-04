import XCTest
import Foundation
@testable import jifen

private nonisolated final class AuthReplyGate: @unchecked Sendable {
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

private nonisolated final class AuthRequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []
    func append(_ path: String) { lock.lock(); paths.append(path); lock.unlock() }
    func count(_ path: String) -> Int { lock.lock(); defer { lock.unlock() }; return paths.filter { $0 == path }.count }
}

private nonisolated final class DelayedAuthURLProtocol: URLProtocol, @unchecked Sendable {
    private nonisolated final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var handlers: [String: @Sendable (DelayedAuthURLProtocol) -> Void] = [:]
        func set(_ handler: @escaping @Sendable (DelayedAuthURLProtocol) -> Void, tokens: [String]) {
            lock.lock(); defer { lock.unlock() }
            for token in tokens { handlers[token.isEmpty ? "" : "Bearer " + token] = handler }
        }
        func handler(_ auth: String) -> (@Sendable (DelayedAuthURLProtocol) -> Void)? {
            lock.lock(); defer { lock.unlock() }; return handlers[auth]
        }
        func remove(tokens: [String]) { lock.lock(); defer { lock.unlock() }; for token in tokens { handlers.removeValue(forKey: token.isEmpty ? "" : "Bearer " + token) } }
    }
    private static let registry = Registry()
    static func register(tokens: [String], handler: @escaping @Sendable (DelayedAuthURLProtocol) -> Void) { registry.set(handler, tokens: tokens) }
    static func unregister(tokens: [String]) { registry.remove(tokens: tokens) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.registry.handler(request.value(forHTTPHeaderField: "Authorization") ?? "") else {
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled)); return
        }
        handler(self)
    }
    override func stopLoading() {}
    func fail(_ error: URLError) { client?.urlProtocol(self, didFailWithError: error) }
    func reply(status: Int, body: String = "{}") {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor private final class CancelledAppleIdentityProvider: AccountIdentityProviding {
    let providerID: AccountIdentityProviderID = .apple
    func signIn() async throws -> AuthResponse { throw AppleAuthError.cancelled }
}

@MainActor final class APIClientSessionIsolationTests: XCTestCase {
    private func fixture() -> (AuthTokenStore, APIClient, URLSession, [String]) {
        let id = UUID().uuidString
        let store = AuthTokenStore(service: "com.douhua.jifen.codex-auth-tests." + id)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DelayedAuthURLProtocol.self]
        let session = URLSession(configuration: config)
        return (store, APIClient(session: session, tokenStore: store), session, ["fake-a-" + id, "fake-b-" + id, "fake-refreshed-" + id])
    }
    private func refreshBody(_ token: String) -> String {
        let expiry = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
        return "{\"token\":\"\(token)\",\"expiresAt\":\"\(expiry)\"}"
    }
    private func assertCancelled(_ task: Task<EmptyResponse, Error>) async {
        do { _ = try await task.value; XCTFail("stale account request must be cancelled") }
        catch { XCTAssertTrue(error is CancellationError, "unexpected stale request error: \(error)") }
    }
    private func delayedRefresh(status: Int, sameTokenLogin: Bool = false) async throws {
        let (store, client, session, tokens) = fixture()
        defer { session.invalidateAndCancel(); DelayedAuthURLProtocol.unregister(tokens: tokens) }
        try await store.setAuth(token: tokens[0], expiresAt: Date().addingTimeInterval(-1))
        let gate = AuthReplyGate(), requested = expectation(description: "A refresh is in flight")
        let body = status == 200 ? refreshBody(tokens[2]) : "{\"error\":\"TOKEN_EXPIRED\"}"
        DelayedAuthURLProtocol.register(tokens: tokens) { proto in
            if proto.request.url!.path == "/api/auth/refresh" { requested.fulfill(); gate.hold { proto.reply(status: status, body: body) } }
            else { proto.reply(status: 200) }
        }
        let pending = Task<EmptyResponse, Error> { try await client.request("/isolated", requiresAuth: true) }
        await fulfillment(of: [requested], timeout: 3)
        if sameTokenLogin { await store.clearAuth() }
        let nextToken = sameTokenLogin ? tokens[0] : tokens[1]
        try await store.setAuth(token: nextToken, expiresAt: Date().addingTimeInterval(3600))
        gate.release()
        await assertCancelled(pending)
        let current = await store.authToken()
        XCTAssertEqual(current, nextToken)
        await store.clearAuth()
    }
    func testDelayedRefreshSuccessCannotOverwriteNewAccount() async throws { try await delayedRefresh(status: 200) }
    func testDelayedRefresh401CannotClearNewAccount() async throws { try await delayedRefresh(status: 401) }
    func testDelayedRefreshCannotResurrectLogoutThenLoginWithSameToken() async throws { try await delayedRefresh(status: 200, sameTokenLogin: true) }
    func testDelayedProtected401DoesNotRefreshUnderTheNextAccount() async throws {
        let (store, client, session, tokens) = fixture()
        defer { session.invalidateAndCancel(); DelayedAuthURLProtocol.unregister(tokens: tokens) }
        try await store.setAuth(token: tokens[0], expiresAt: Date().addingTimeInterval(3600))
        let gate = AuthReplyGate(), requested = expectation(description: "A protected request is in flight"), log = AuthRequestLog()
        DelayedAuthURLProtocol.register(tokens: tokens) { proto in
            let path = proto.request.url!.path; log.append(path)
            if path == "/isolated" { requested.fulfill(); gate.hold { proto.reply(status: 401) } }
            else { proto.reply(status: 200) }
        }
        let pending = Task<EmptyResponse, Error> { try await client.request("/isolated", requiresAuth: true) }
        await fulfillment(of: [requested], timeout: 3)
        try await store.setAuth(token: tokens[1], expiresAt: Date().addingTimeInterval(3600))
        gate.release(); await assertCancelled(pending)
        XCTAssertEqual(log.count("/api/auth/refresh"), 0)
        let token = await store.authToken(); XCTAssertEqual(token, tokens[1])
        await store.clearAuth()
    }
    func testRefresh403PreservesTheCurrentSession() async throws {
        let (store, client, session, tokens) = fixture()
        defer { session.invalidateAndCancel(); DelayedAuthURLProtocol.unregister(tokens: tokens) }
        try await store.setAuth(token: tokens[0], expiresAt: Date().addingTimeInterval(-1))
        DelayedAuthURLProtocol.register(tokens: tokens) { $0.reply(status: 403, body: "{\"error\":\"ROLE_FORBIDDEN\"}") }
        do { let _: EmptyResponse = try await client.request("/isolated", requiresAuth: true); XCTFail("403 must remain a business error") }
        catch APIClientError.server(let status, let code, _, _) { XCTAssertEqual(status, 403); XCTAssertEqual(code, "ROLE_FORBIDDEN") }
        catch { XCTFail("unexpected 403 error: \(error)") }
        let token = await store.authToken(); XCTAssertEqual(token, tokens[0])
        await store.clearAuth()
    }
    func testExpectedSessionRevisionStopsStaleQueuedRequestBeforeSending() async throws {
        let (store, client, session, tokens) = fixture()
        defer { session.invalidateAndCancel(); DelayedAuthURLProtocol.unregister(tokens: tokens) }
        try await store.setAuth(token: tokens[0], expiresAt: Date().addingTimeInterval(3600))
        let revision = await client.authSessionRevision(), log = AuthRequestLog()
        try await store.setAuth(token: tokens[1], expiresAt: Date().addingTimeInterval(3600))
        DelayedAuthURLProtocol.register(tokens: tokens) { log.append($0.request.url!.path); $0.reply(status: 200) }
        let pending = Task<EmptyResponse, Error> { try await client.request("/isolated", requiresAuth: true, expectedAuthRevision: revision) }
        await assertCancelled(pending)
        XCTAssertEqual(log.count("/isolated"), 0)
        await store.clearAuth()
    }
    func testSameSessionConcurrentRequestsShareOneRefresh() async throws {
        let (store, client, session, tokens) = fixture()
        defer { session.invalidateAndCancel(); DelayedAuthURLProtocol.unregister(tokens: tokens) }
        try await store.setAuth(token: tokens[0], expiresAt: Date().addingTimeInterval(-1))
        let revision = await client.authSessionRevision(), gate = AuthReplyGate(), log = AuthRequestLog()
        let requested = expectation(description: "single shared refresh"), body = refreshBody(tokens[2])
        DelayedAuthURLProtocol.register(tokens: tokens) { proto in
            let path = proto.request.url!.path; log.append(path)
            if path == "/api/auth/refresh" { requested.fulfill(); gate.hold { proto.reply(status: 200, body: body) } }
            else { proto.reply(status: 200) }
        }
        let first = Task<EmptyResponse, Error> { try await client.request("/first", requiresAuth: true) }
        let second = Task<EmptyResponse, Error> { try await client.request("/second", requiresAuth: true) }
        await fulfillment(of: [requested], timeout: 3)
        gate.release(); _ = try await first.value; _ = try await second.value
        XCTAssertEqual(log.count("/api/auth/refresh"), 1)
        let after = await client.authSessionRevision(); XCTAssertEqual(after, revision)
        let token = await store.authToken(); XCTAssertEqual(token, tokens[2])
        await store.clearAuth()
    }

    func testDelayedNonRetryableTransportFailureIsCancelledAfterAccountChange() async throws {
        let (store, client, session, tokens) = fixture()
        defer { session.invalidateAndCancel(); DelayedAuthURLProtocol.unregister(tokens: tokens) }
        try await store.setAuth(token: tokens[0], expiresAt: Date().addingTimeInterval(3600))
        let gate = AuthReplyGate(), requested = expectation(description: "old protected request")
        DelayedAuthURLProtocol.register(tokens: tokens) { proto in
            requested.fulfill(); gate.hold { proto.fail(URLError(.badServerResponse)) }
        }
        let pending = Task<EmptyResponse, Error> { try await client.request("/isolated", requiresAuth: true) }
        await fulfillment(of: [requested], timeout: 3)
        try await store.setAuth(token: tokens[1], expiresAt: Date().addingTimeInterval(3600))
        gate.release()
        await assertCancelled(pending)
        await store.clearAuth()
    }

    func testDelayedRefreshTransportFailureIsCancelledAfterAccountChange() async throws {
        let (store, client, session, tokens) = fixture()
        defer { session.invalidateAndCancel(); DelayedAuthURLProtocol.unregister(tokens: tokens) }
        try await store.setAuth(token: tokens[0], expiresAt: Date().addingTimeInterval(-1))
        let gate = AuthReplyGate(), requested = expectation(description: "old refresh request")
        DelayedAuthURLProtocol.register(tokens: tokens) { proto in
            requested.fulfill(); gate.hold { proto.fail(URLError(.badServerResponse)) }
        }
        let pending = Task<EmptyResponse, Error> { try await client.request("/isolated", requiresAuth: true) }
        await fulfillment(of: [requested], timeout: 3)
        try await store.setAuth(token: tokens[1], expiresAt: Date().addingTimeInterval(3600))
        gate.release()
        await assertCancelled(pending)
        await store.clearAuth()
    }

    func testConditionalLogoutCannotClearNewSessionButAllowsSameSessionRefresh() async throws {
        let (store, client, session, tokens) = fixture()
        defer { session.invalidateAndCancel() }
        try await store.setAuth(token: tokens[0], expiresAt: Date().addingTimeInterval(3600))
        let first = await store.authSnapshot()
        try await store.setAuth(token: tokens[1], expiresAt: Date().addingTimeInterval(3600))
        let staleCleared = await client.clearSession(expectedAuthRevision: first.revision)
        XCTAssertFalse(staleCleared)
        let current = await store.authSnapshot()
        _ = try await store.setRefreshedAuth(token: tokens[2], expiresAt: Date().addingTimeInterval(3600), ifMatching: current)
        let cleared = await client.clearSession(expectedAuthRevision: current.revision)
        XCTAssertTrue(cleared)
        let token = await store.authToken()
        XCTAssertNil(token)
    }

    func testDelayedPasswordLoginCannotResurrectSessionAfterLogout() async throws {
        let (store, client, session, tokens) = fixture()
        defer { session.invalidateAndCancel(); DelayedAuthURLProtocol.unregister(tokens: tokens + [""]) }
        let account = SessionStore(client: client, tokenStore: store)
        let gate = AuthReplyGate(), requested = expectation(description: "password login in flight")
        let expiry = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
        let body = "{\"user\":{\"id\":\"old-user\",\"role\":\"FREE\",\"plan\":\"FREE\",\"createdAt\":1},\"token\":\"\(tokens[0])\",\"expiresAt\":\"\(expiry)\"}"
        DelayedAuthURLProtocol.register(tokens: [""]) { proto in
            if proto.request.url?.path == PasswordLoginEndpoint.path {
                requested.fulfill(); gate.hold { proto.reply(status: 200, body: body) }
            } else { proto.reply(status: 200, body: "{\"success\":true}") }
        }
        let pending = Task { await account.signInWithEmail(account: "test@example.invalid", password: "test") }
        await fulfillment(of: [requested], timeout: 3)
        await account.logout()
        gate.release()
        await pending.value
        let token = await store.authToken()
        XCTAssertNil(token)
        XCTAssertFalse(account.isAuthenticated)
        XCTAssertNil(account.lastError)
        await store.clearAuth()
    }

    private func recoverInterruptedRestore(
        appleCancellation: Bool = false,
        retryFails: Bool = false,
        logoutDuringRetry: Bool = false
    ) async throws {
        let (store, client, session, tokens) = fixture()
        defer { session.invalidateAndCancel(); DelayedAuthURLProtocol.unregister(tokens: tokens + [""]) }
        try await store.setAuth(token: tokens[0], expiresAt: Date().addingTimeInterval(3600))
        let revision = await store.authSessionRevision()
        let provider: (any AccountIdentityProviding)? = appleCancellation ? CancelledAppleIdentityProvider() : nil
        let account = SessionStore(client: client, tokenStore: store, appleProvider: provider,
                                   postAuthenticationWarmup: { _ in })
        let firstGate = AuthReplyGate(), retryGate = AuthReplyGate(), log = AuthRequestLog()
        let firstRequested = expectation(description: "launch restore in flight")
        let retryRequested = expectation(description: "failed sign-in retries the preserved session")
        let oldProfile = #"{"id":"stale-restore","role":"FREE","plan":"FREE","createdAt":1}"#
        let retainedProfile = #"{"id":"retained-session","role":"FREE","plan":"FREE","createdAt":1}"#
        DelayedAuthURLProtocol.register(tokens: tokens + [""]) { proto in
            let path = proto.request.url!.path
            log.append(path)
            if path == "/api/auth/me" {
                switch log.count(path) {
                case 1:
                    firstRequested.fulfill()
                    firstGate.hold { proto.reply(status: 200, body: oldProfile) }
                case 2:
                    retryRequested.fulfill()
                    if retryFails { proto.fail(URLError(.notConnectedToInternet)) }
                    else { retryGate.hold { proto.reply(status: 200, body: retainedProfile) } }
                default:
                    proto.reply(status: 200, body: retainedProfile)
                }
            } else if path == PasswordLoginEndpoint.path {
                proto.reply(status: 401, body: #"{"error":"INVALID_CREDENTIALS"}"#)
            } else {
                proto.reply(status: 200, body: #"{"success":true}"#)
            }
        }
        let originalRestore = Task { await account.restore() }
        await fulfillment(of: [firstRequested], timeout: 3)
        XCTAssertEqual(account.state, .restoring)
        XCTAssertFalse(account.isWorking)
        let failedSignIn = Task {
            if appleCancellation { await account.signInWithApple() }
            else { await account.signInWithEmail(account: "bad@example.invalid", password: "invalid") }
        }
        await fulfillment(of: [retryRequested], timeout: 3)
        if retryFails {
            await failedSignIn.value
            XCTAssertEqual(account.state, .signedOut)
            XCTAssertFalse(account.isWorking)
            XCTAssertNotNil(account.lastError)
        }
        firstGate.release()
        await originalRestore.value
        XCTAssertEqual(account.state, .signedOut, "the superseded restore must not publish its profile")
        XCTAssertNil(account.user)
        if retryFails {
            await account.restore()
        } else {
            if logoutDuringRetry { await account.logout() }
            retryGate.release()
            await failedSignIn.value
        }
        if logoutDuringRetry {
            XCTAssertEqual(account.state, .signedOut)
            XCTAssertNil(account.user)
            let token = await store.authToken()
            XCTAssertNil(token)
        } else {
            XCTAssertEqual(account.state, .authenticated)
            XCTAssertEqual(account.user?.id, "retained-session")
            XCTAssertNil(account.lastError)
            let snapshot = await store.authSnapshot()
            XCTAssertEqual(snapshot.token, tokens[0])
            XCTAssertEqual(snapshot.revision, revision, "failed login must preserve the existing session")
        }
        XCTAssertFalse(account.isWorking)
        let expectedRequests = retryFails ? 3 : 2
        XCTAssertEqual(log.count("/api/auth/me"), expectedRequests)
        await account.restore()
        XCTAssertEqual(log.count("/api/auth/me"), expectedRequests)
        await store.clearAuth()
    }

    func testFailedPasswordLoginRetriesInterruptedRestore() async throws {
        try await recoverInterruptedRestore()
    }

    func testCancelledAppleLoginRetriesInterruptedRestore() async throws {
        try await recoverInterruptedRestore(appleCancellation: true)
    }

    func testInterruptedRestoreRetryFailureRemainsSignedOutAndCanRetry() async throws {
        try await recoverInterruptedRestore(retryFails: true)
    }

    func testLogoutDuringInterruptedRestoreRetryCannotRestoreSession() async throws {
        try await recoverInterruptedRestore(logoutDuringRetry: true)
    }
}
