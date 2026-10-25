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
    func testTestRuntimeSeparatesHostedAndUIFixturesFromNormalAuthentication() {
        XCTAssertEqual(AppTestRuntime.detect(arguments: [], environment: [:], xctestLoaded: false, debugBuild: true), .application)
        XCTAssertEqual(AppTestRuntime.detect(arguments: [], environment: ["XCTestConfigurationFilePath": "/fixture.xctestconfiguration"], xctestLoaded: false, debugBuild: true), .hostedUnitTests)
        XCTAssertEqual(AppTestRuntime.detect(arguments: [], environment: [:], xctestLoaded: true, debugBuild: true), .hostedUnitTests)
        XCTAssertEqual(AppTestRuntime.detect(arguments: ["-UITestRecordFixtures"], environment: [:], xctestLoaded: false, debugBuild: true), .uiTests)
        XCTAssertEqual(AppTestRuntime.detect(arguments: ["-UITestFakeSession"], environment: ["XCTestSessionIdentifier": "fixture"], xctestLoaded: true, debugBuild: false), .application)
        let first = AppTestRuntime.authService(for: .hostedUnitTests, processNamespace: "first-process")
        let second = AppTestRuntime.authService(for: .hostedUnitTests, processNamespace: "second-process")
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first, AppTestRuntime.normalAuthService)
        XCTAssertEqual(AppTestRuntime.authService(for: .application, processNamespace: "fixture"), AppTestRuntime.normalAuthService)
        XCTAssertEqual(AppTestRuntime.authService(for: .uiTests, processNamespace: "first-process"),
                       AppTestRuntime.authService(for: .uiTests, processNamespace: "second-process"))
        XCTAssertNotEqual(AppTestRuntime.authService(for: .uiTests, processNamespace: "fixture"), AppTestRuntime.normalAuthService)
    }

    func testHostedDefaultsUseAnIsolatedNamespaceAndCannotActivatePrivateSync() async throws {
        XCTAssertEqual(AppTestRuntime.mode, .hostedUnitTests)
        XCTAssertTrue(AppTestRuntime.isolatesDefaultPrivateSync)
        // Inspect only metadata. Never probe the normal Keychain service.
        XCTAssertEqual(AuthTokenStore.shared.serviceIdentifier, AppTestRuntime.authService)
        XCTAssertTrue(AuthTokenStore.shared.serviceIdentifier.hasPrefix(AppTestRuntime.normalAuthService + ".tests.unit."))
        XCTAssertNotEqual(AuthTokenStore.shared.serviceIdentifier, AppTestRuntime.normalAuthService)
        XCTAssertNotNil(AppTestRuntime.storageRootURL)
        XCTAssertTrue(AppTestRuntime.storageRootURL?.lastPathComponent.hasPrefix("jifen-hosted-tests-") == true)
        XCTAssertTrue(AppTestRuntime.defaultsSuiteName?.hasPrefix("com.douhua.jifen.tests.unit.") == true)
        let root = try XCTUnwrap(AppTestRuntime.storageRootURL)
        let recordID = "test-namespace-" + UUID().uuidString
        let score = ScoreboardRecord(id: recordID, gameType: .pingpong, startTime: Date(),
            team1Name: "A", team2Name: "B", team1FinalScore: 1, team2FinalScore: 0, totalScoreChanges: 1)
        try ScoreboardRecordManager.shared.saveScoreboardRecord(score, cleanupResumeAfterWrite: false)
        let scoreFiles = ScoreboardRecordFileStore(rootURL: root.appendingPathComponent("ScoreboardRecords-v4"))
        XCTAssertEqual(scoreFiles.loadRecord(id: recordID)?.id, recordID)
        XCTAssertTrue(ScoreboardRecordManager.voiceNotesDirectoryURL.path.hasPrefix(root.path + "/"))
        XCTAssertTrue(ParticipantIdentityStore().storageFileURL.path.hasPrefix(root.path + "/"))
        XCTAssertTrue(PersonalRecordsCloudSync().storageFileURL.path.hasPrefix(root.path + "/"))
        XCTAssertTrue(PersonalGroupRecords.shared.cacheDirectoryURL.path.hasPrefix(root.path + "/"))
        XCTAssertTrue(PersonalRecordsCloudSync.shared.audioCacheURL.path.hasPrefix(root.path + "/"))
        let timer = GameRecordSummary(id: recordID, gameType: .chess, timestamp: 1)
        TimerRecordManager.shared.addRecord(timer)
        let timerFiles = TimerRecordManager(defaults: AppTestRuntime.persistenceDefaults,
            rootURL: root.appendingPathComponent("TimerRecords-v2"))
        XCTAssertTrue(timerFiles.getRecords().contains { $0.id == recordID })
        _ = ScoreboardRecordManager.shared.deleteRecord(recordID)
        _ = TimerRecordManager.shared.deleteRecord(recordID)
        let service = PersonalRecordsCloudSync.shared
        await service.sessionDidAuthenticate(userId: "hosted-fixture-must-not-sync")
        await service.synchronizeNow()
        XCTAssertEqual(service.phase, "local")
        XCTAssertTrue(service.remoteRecords.isEmpty)
    }

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
    func testNativeRequestsAndRefreshIgnoreRevokedLoginCookies() async throws {
        let id = UUID().uuidString
        let store = AuthTokenStore(service: "com.douhua.jifen.cookie-tests." + id)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DelayedAuthURLProtocol.self]
        let cookies = try XCTUnwrap(config.httpCookieStorage)
        let staleCookie = try XCTUnwrap(HTTPCookie(properties: [
            .name: "jwt_token", .value: "revoked-cookie-" + id,
            .domain: "api.jifenqi.com", .path: "/", .secure: "TRUE"
        ]))
        cookies.setCookie(staleCookie)
        let transport = URLSession(configuration: config)
        let client = APIClient(session: transport, tokenStore: store)
        let original = "native-original-" + id, refreshed = "native-refreshed-" + id
        defer {
            transport.invalidateAndCancel()
            DelayedAuthURLProtocol.unregister(tokens: [original, refreshed, ""])
        }
        let expiry = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
        let body = "{\"token\":\"\(refreshed)\",\"expiresAt\":\"\(expiry)\"}"
        let log = AuthRequestLog()
        DelayedAuthURLProtocol.register(tokens: [original, refreshed, ""]) { proto in
            log.append(proto.request.url!.path)
            XCTAssertFalse(proto.request.httpShouldHandleCookies)
            XCTAssertNil(proto.request.value(forHTTPHeaderField: "Cookie"), "web cookies must never override the native bearer")
            proto.reply(status: 200, body: proto.request.url?.path == "/api/auth/refresh" ? body : "{}")
        }
        try await store.setAuth(token: original, expiresAt: Date().addingTimeInterval(-1))
        let _: EmptyResponse = try await client.request("/native-protected", requiresAuth: true)
        let _: EmptyResponse = try await client.request("/native-login", headers: ["Cookie": "jwt_token=revoked"])
        let _: EmptyResponse = try await client.request("/native-receipt", headers: ["Authorization": "Bearer " + original])
        XCTAssertEqual(log.count("/api/auth/refresh"), 1)
        XCTAssertEqual(log.count("/native-protected"), 1)
        XCTAssertEqual(log.count("/native-login"), 1)
        XCTAssertEqual(log.count("/native-receipt"), 1)
        XCTAssertEqual(cookies.cookies?.first?.value, staleCookie.value, "the client does not mutate unrelated web cookie storage")
        await store.clearAuth()
    }
    func testDelayedRefresh401CannotClearNewAccount() async throws { try await delayedRefresh(status: 401) }
    func testLinkedCredentialInstallAtomicallyAcceptsSourceExpiryButRejectsLaterLogin() async throws {
        let (store, _, transport, tokens) = fixture()
        defer { transport.invalidateAndCancel() }
        let expiry = Date().addingTimeInterval(3600)
        try await store.setAuth(token: tokens[0], expiresAt: expiry)
        let source = await store.authSnapshot()
        _ = await store.clearAuth(ifMatching: source)
        let applied = try await store.setLinkedAuth(token: tokens[1], expiresAt: expiry,
                                                   replacingSourceRevision: source.revision)
        XCTAssertTrue(applied, "a source 401 between snapshot and installation must not discard successful confirmation")
        let staleApplied = try await store.setLinkedAuth(token: tokens[2], expiresAt: expiry,
                                                        replacingSourceRevision: source.revision)
        XCTAssertFalse(staleApplied, "a replacement login cannot be overwritten by a late confirmation")
        let current = await store.authToken()
        XCTAssertEqual(current, tokens[1])
        await store.clearAuth()
    }
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

    private func logoutDuringBindingStatus(restoring: Bool) async throws {
        let (store, client, transport, tokens) = fixture()
        let suiteName = "com.douhua.jifen.status-warmup-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let gate = AuthReplyGate()
        defer {
            gate.release()
            transport.invalidateAndCancel()
            DelayedAuthURLProtocol.unregister(tokens: tokens + [""])
            defaults.removePersistentDomain(forName: suiteName)
        }
        if restoring {
            try await store.setAuth(token: tokens[0], expiresAt: Date().addingTimeInterval(3600))
        }
        let statusStarted = expectation(description: "binding status is in flight after authentication")
        let profile = #"{"id":"original-account","role":"FREE","plan":"FREE","createdAt":1}"#
        let expiry = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
        let login = "{\"user\":\(profile),\"token\":\"\(tokens[0])\",\"expiresAt\":\"\(expiry)\"}"
        let bindings = #"{"sessionProvider":"apple","providers":["apple"],"capabilities":{"wechatBinding":true,"accountMerge":true},"wechat":{"bound":false,"canBind":true}}"#
        DelayedAuthURLProtocol.register(tokens: tokens + [""]) { proto in
            switch proto.request.url?.path {
            case WechatBindingEndpoint.status:
                statusStarted.fulfill()
                gate.hold { proto.reply(status: 200, body: bindings) }
            case PasswordLoginEndpoint.path: proto.reply(status: 200, body: login)
            case "/api/auth/me": proto.reply(status: 200, body: profile)
            default: proto.reply(status: 200, body: #"{"success":true}"#)
            }
        }
        var warmedUsers: [String?] = []
        let account = SessionStore(client: client, tokenStore: store,
            postAuthenticationWarmup: { warmedUsers.append($0) }, defaults: defaults)
        let authentication = Task {
            if restoring { await account.restore() }
            else { await account.signInWithEmail(account: "test@example.invalid", password: "test") }
        }
        await fulfillment(of: [statusStarted], timeout: 3)
        await account.logout()
        gate.release()
        await authentication.value
        XCTAssertTrue(warmedUsers.isEmpty, "a late binding status response must not reactivate stores after logout")
        XCTAssertFalse(account.isAuthenticated)
        XCTAssertNil(account.user)
        let finalToken = await store.authToken()
        XCTAssertNil(finalToken)
        await store.clearAuth()
    }

    func testLogoutDuringLoginBindingStatusDoesNotRestartWarmup() async throws {
        try await logoutDuringBindingStatus(restoring: false)
    }

    func testLogoutDuringRestoreBindingStatusDoesNotRestartWarmup() async throws {
        try await logoutDuringBindingStatus(restoring: true)
    }

}

extension APIClientSessionIsolationTests {
    private struct CommonDataLinkFixture {
        let store: AuthTokenStore
        let transport: URLSession
        let tokens: [String]
        let defaults: UserDefaults
        let suiteName: String
        let manager: CommonDataCloudSyncManager
        let localData: [(String, Any?)]

        func context() async -> WechatBindingSessionContext {
            .init(accountID: "same-account", authRevision: await store.authSessionRevision(), generation: 1)
        }

        func cleanup() async {
            await manager.sessionDidChange(userId: nil)
            transport.invalidateAndCancel()
            DelayedAuthURLProtocol.unregister(tokens: tokens)
            defaults.removePersistentDomain(forName: suiteName)
            for (key, value) in localData { UserDefaults.standard.set(value, forKey: key) }
            await store.clearAuth()
        }
    }

    private func commonDataLinkFixture() async throws -> CommonDataLinkFixture {
        let (store, client, transport, tokens) = fixture()
        let suiteName = "com.douhua.jifen.common-data-link-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let localData = ["commonTeamNames", "commonPlayerNames", "jifen-v2.commonPlaces"]
            .map { ($0, UserDefaults.standard.object(forKey: $0)) }
        try await store.setAuth(token: tokens[0], expiresAt: Date().addingTimeInterval(3600))
        let manager = CommonDataCloudSyncManager(client: client, defaults: defaults)
        return .init(store: store, transport: transport, tokens: tokens, defaults: defaults,
                     suiteName: suiteName, manager: manager, localData: localData)
    }

    func testOldCommonDataPauseCannotFreezeSameAccountAfterRelogin() async throws {
        let f = try await commonDataLinkFixture()
        let gate = AuthReplyGate(), log = AuthRequestLog()
        defer { gate.release() }
        let requested = expectation(description: "source sync is in flight")
        DelayedAuthURLProtocol.register(tokens: f.tokens) { proto in
            let path = proto.request.url!.path
            log.append(path)
            let body = #"{"names":[],"places":[],"serverTime":1}"#
            if log.count(path) == 1 {
                requested.fulfill()
                gate.hold { proto.reply(status: 200, body: body) }
            } else { proto.reply(status: 200, body: body) }
        }
        let context = await f.context()
        let initialSync = Task { await f.manager.sessionDidChange(userId: context.accountID) }
        await fulfillment(of: [requested], timeout: 3)
        let entered = expectation(description: "old binding begins waiting")
        let pause = Task {
            entered.fulfill()
            try await f.manager.pauseForAccountLink(context: context)
        }
        await fulfillment(of: [entered], timeout: 3)
        await f.manager.sessionDidChange(userId: nil)
        try await f.store.setAuth(token: f.tokens[1], expiresAt: Date().addingTimeInterval(3600))
        await f.manager.sessionDidChange(userId: context.accountID)
        gate.release()
        await initialSync.value
        do { try await pause.value; XCTFail("a pause from before relogin must be cancelled") }
        catch { XCTAssertTrue(error is CancellationError) }
        await f.manager.forceSync()
        XCTAssertEqual(f.manager.phase, .synced)
        await f.cleanup()
    }

    func testClosingPendingCommonDataPauseCannotFreezeAfterLateFlush() async throws {
        let f = try await commonDataLinkFixture()
        let gate = AuthReplyGate(), log = AuthRequestLog()
        defer { gate.release() }
        let requested = expectation(description: "binding flush is in flight")
        DelayedAuthURLProtocol.register(tokens: f.tokens) { proto in
            let path = proto.request.url!.path
            log.append(path)
            let body = #"{"names":[],"places":[],"serverTime":1}"#
            if log.count(path) == 2 {
                requested.fulfill()
                gate.hold { proto.reply(status: 200, body: body) }
            } else { proto.reply(status: 200, body: body) }
        }
        await f.manager.sessionDidChange(userId: "same-account")
        let context = await f.context()
        let pause = Task { try await f.manager.pauseForAccountLink(context: context) }
        await fulfillment(of: [requested], timeout: 3)
        await f.manager.cancelAccountLink(context: context)
        gate.release()
        do { try await pause.value; XCTFail("closing must invalidate a pending pause before its flush returns") }
        catch { XCTAssertTrue(error is CancellationError) }
        await f.manager.forceSync()
        XCTAssertEqual(f.manager.phase, .synced)
        await f.cleanup()
    }

    func testOldCommonDataCloseAndCompletionCannotConsumeNewPause() async throws {
        let f = try await commonDataLinkFixture()
        let log = AuthRequestLog()
        DelayedAuthURLProtocol.register(tokens: f.tokens) { proto in
            log.append(proto.request.url!.path)
            proto.reply(status: 200, body: #"{"names":[],"places":[],"serverTime":1}"#)
        }
        await f.manager.sessionDidChange(userId: "same-account")
        let old = await f.context()
        try await f.manager.pauseForAccountLink(context: old)
        await f.manager.cancelAccountLink(context: old)
        let current = await f.context()
        XCTAssertNotEqual(old.id, current.id)
        try await f.manager.pauseForAccountLink(context: current)
        let requestCount = log.count("/api/common-data/sync")
        await f.manager.cancelAccountLink(context: old)
        do {
            try await f.manager.completeAccountLink(userID: "unrelated-master", context: old)
            XCTFail("a stale completion must not replace the new flow's cloud baseline")
        } catch { XCTAssertTrue(error is CancellationError) }
        await f.manager.forceSync()
        XCTAssertEqual(log.count("/api/common-data/sync"), requestCount, "the new pause must stay frozen")
        XCTAssertEqual(log.count("/api/common-data"), 0)
        await f.manager.cancelAccountLink(context: current)
        XCTAssertEqual(f.manager.phase, .synced)
        XCTAssertGreaterThan(log.count("/api/common-data/sync"), requestCount)
        await f.cleanup()
    }

    func testOwnedCommonDataCompletionPullsBaselineAfterSourceExpiry() async throws {
        let f = try await commonDataLinkFixture()
        let log = AuthRequestLog()
        DelayedAuthURLProtocol.register(tokens: f.tokens) { proto in
            log.append(proto.request.url!.path)
            proto.reply(status: 200, body: #"{"names":[],"places":[],"serverTime":1}"#)
        }
        await f.manager.sessionDidChange(userId: "same-account")
        let context = await f.context()
        try await f.manager.pauseForAccountLink(context: context)
        await f.store.clearAuth()
        try await f.store.setAuth(token: f.tokens[1], expiresAt: Date().addingTimeInterval(3600))
        try await f.manager.completeAccountLink(userID: "linked-master", context: context)
        XCTAssertEqual(f.manager.phase, .synced)
        XCTAssertEqual(log.count("/api/common-data"), 1)
        let requestCount = log.count("/api/common-data/sync")
        await f.manager.cancelAccountLink(context: context)
        await f.manager.forceSync()
        XCTAssertEqual(f.manager.phase, .synced)
        XCTAssertEqual(log.count("/api/common-data/sync"), requestCount + 1)
        await f.cleanup()
    }
}
