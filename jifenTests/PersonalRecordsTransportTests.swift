import Foundation
import XCTest
import ScoreCore
@testable import jifen

private nonisolated final class IdentityTransportProtocol: URLProtocol, @unchecked Sendable {
    private nonisolated final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var handlers: [String: @Sendable (IdentityTransportProtocol) -> Void] = [:]
        func set(_ token: String, handler: (@Sendable (IdentityTransportProtocol) -> Void)?) { lock.lock(); defer { lock.unlock() }; handlers["Bearer " + token] = handler }
        func get(_ token: String) -> (@Sendable (IdentityTransportProtocol) -> Void)? { lock.lock(); defer { lock.unlock() }; return handlers[token] }
    }
    private static let registry = Registry()
    static func register(_ token: String, handler: (@Sendable (IdentityTransportProtocol) -> Void)?) { registry.set(token, handler: handler) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.registry.get(request.value(forHTTPHeaderField: "Authorization") ?? "") else { fail(); return }
        handler(self)
    }
    override func stopLoading() {}
    var bodyData: Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }; data.append(buffer, count: count)
        }
        return data
    }
    func fail() { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)) }
    func replyBytes(_ data: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "audio/mp4"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    func reply(_ object: [String: Any], status: Int = 200) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: object))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private nonisolated final class IdentityTransportServer: @unchecked Sendable {
    let lock = NSRecursiveLock()
    var aliases: [[String: Any]] = []
    var mutationBodies: [Data] = []
    var pushedKeys: [String] = []
    var loseFirstMutationReply = false
    var deletedConflict = false
    var revision = 0
    var claimInputs: [[String: Any]] = []
    var preparedBodies: [[String: Any]] = []
    var expireFirstAdoption = false
    var pushedEnvelopes: [[String: Any]] = []
    var firstPushAssetId: String?
    var snapshotReads = 0
    var pullRecords: [[String: Any]] = []
    var rejectedKeys: Set<String> = []
    var pushAttempts: [[[String: Any]]] = []
    var splitMultiple = false
    var throttleFirst = false
    var expiredReceipt = false
    var mismatchedProof = false
    var permanentOversizedKeys: Set<String> = []
    var httpOversizedKeys: Set<String> = []
    var expiredIdentity = false
    var mismatchedIdentityProof = false
    var compactedAdoption = false
    var mismatchedAdoptionProof = false
    var commitBodies: [[String: Any]] = []
    var audioEnabled = false
    var expiredAssetManifest = false
    var expiredAssetComplete = false
    var mismatchedAssetProof = false
    var assetBodies: [[String: Any]] = []
    var assetPuts = 0
    var assetCompletes = 0
    var downloadableAssetID: String?
    let audioBytes = Data("0000ftypisom-audio-fixture".utf8)
    func snapshot() -> [String: Any] {
        ["schemaVersion": 1, "person": ["id": "person-account", "kind": "account", "accountId": "account", "revision": revision],
         "aliases": aliases, "capabilities": ["maxActiveAliases": 3, "privateRecordsV1": true, "privateRecordAudioV1": audioEnabled]]
    }
    func respond(_ proto: IdentityTransportProtocol) {
        lock.lock(); defer { lock.unlock() }
        let path = proto.request.url!.path
        switch path {
        case "/api/self-identity": snapshotReads += 1; proto.reply(snapshot())
        case "/api/self-identity/adoptions/prepare":
            let body = (try? JSONSerialization.jsonObject(with: proto.bodyData)) as? [String: Any] ?? [:]
            preparedBodies.append(body)
            proto.reply(["adoptionId": "adoption-\(preparedBodies.count)", "guestPersonRef": ["id": body["guestPersonId"]!, "kind": "guest"], "accountPersonRef": ["id": "person-account", "kind": "account"], "libraryId": body["guestLibraryId"]!, "aliases": [], "needsAliasReview": false])
        case "/api/self-identity/adoptions/commit":
            let commit = (try? JSONSerialization.jsonObject(with: proto.bodyData)) as? [String: Any] ?? [:]
            commitBodies.append(commit)
            if compactedAdoption {
                let source = preparedBodies.last!
                proto.reply(["error": "MUTATION_RECEIPT_EXPIRED", "details": ["outcome": ["status": "applied", "operation": "adoption", "adoptionId": commit["adoptionId"]!, "userId": mismatchedAdoptionProof ? "other-account" : "account", "guestPersonId": source["guestPersonId"]!, "libraryId": source["guestLibraryId"]!]]], status: 410); return
            }
            if expireFirstAdoption && preparedBodies.count == 1 { proto.reply(["error": "ADOPTION_EXPIRED"], status: 410) }
            else {
                let body = preparedBodies.last!
                proto.reply(["adoptionId": "adoption-\(preparedBodies.count)", "guestPersonRef": ["id": body["guestPersonId"]!, "kind": "guest"], "accountPersonRef": ["id": "person-account", "kind": "account"], "libraryId": body["guestLibraryId"]!, "aliases": [], "needsAliasReview": false, "identity": snapshot()])
            }
        case "/api/self-identity/claims": proto.reply(["claims": [], "nextCursor": NSNull()])
        case "/api/self-identity/mutations":
            let body = proto.bodyData
            mutationBodies.append(body)
            let operation = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
            if let claims = operation["claims"] as? [[String: Any]] {
                claimInputs += claims
                let allowed: Set<String> = ["id", "libraryId", "recordKey", "seatKey", "nameSnapshot", "participantKind"]
                if claims.contains(where: { Set($0.keys) != allowed }) { proto.reply(["error": "INVALID_REQUEST"], status: 400); return }
            }
            if aliases.isEmpty {
                revision += 1
                aliases = [["id": operation["aliasId"] ?? "alias", "name": operation["name"] ?? "YY", "normalizedName": "yy", "state": "active", "visibleInPicker": true, "revision": 1, "createdAt": 1, "updatedAt": 1]]
            }
            if expiredIdentity {
                proto.reply(["error": "MUTATION_RECEIPT_EXPIRED", "details": ["outcome": ["status": "applied", "mutationId": operation["mutationId"]!, "operation": mismatchedIdentityProof ? "unproven" : operation["operation"]!]]], status: 410)
            } else if loseFirstMutationReply && mutationBodies.count == 1 { proto.fail() } else { proto.reply(snapshot()) }
        case "/api/private-records/sync/pull": proto.reply(["records": pullRecords, "nextCursor": "opaque-cursor", "hasMore": false, "syncEpoch": 1])
        case "/api/private-records/sync/push":
            let body = (try? JSONSerialization.jsonObject(with: proto.bodyData)) as? [String: Any] ?? [:]
            let mutations = body["mutations"] as? [[String: Any]] ?? []
            pushAttempts.append(mutations)
            if mutations.contains(where: { httpOversizedKeys.contains($0["recordKey"] as? String ?? "") }) {
                proto.reply(["error": "RESOURCE_RECORD_TOO_LARGE", "details": ["retryable": false, "splitBatch": true, "retryAfterSeconds": 1]], status: 413); return
            }
            if throttleFirst && pushAttempts.count == 1 {
                proto.reply(["error": "RESOURCE_RATE_LIMITED", "details": ["retryable": true, "retryAfterSeconds": 1]], status: 429); return
            }
            if splitMultiple && mutations.count > 1 {
                proto.reply(["results": mutations.map { ["mutationId": $0["mutationId"]!, "status": "rejected", "error": "RESOURCE_RESPONSE_BUDGET_EXCEEDED", "retryable": true, "splitBatch": true, "retryAfterSeconds": 1] }, "syncEpoch": 1]); return
            }
            let results: [[String: Any]] = mutations.map { mutation in
                let key = mutation["recordKey"] as! String; pushedKeys.append(key)
                if permanentOversizedKeys.contains(key) {
                    return ["mutationId": mutation["mutationId"]!, "status": "rejected", "error": "RESOURCE_RECORD_TOO_LARGE", "retryable": false, "splitBatch": true]
                }
                if rejectedKeys.contains(key) {
                    return ["mutationId": mutation["mutationId"]!, "status": "rejected", "error": "INVALID_REQUEST"]
                }
                var record = mutation["envelope"] as? [String: Any] ?? [:]
                pushedEnvelopes.append(record)
                if expiredReceipt {
                    var newest = record
                    newest["revision"] = 9; newest["deleted"] = false; newest["updatedAt"] = 2
                    newest["summary"] = ["leftScore": 99]
                    pullRecords = [newest]
                    return ["mutationId": mutation["mutationId"]!, "status": "rejected", "error": "MUTATION_RECEIPT_EXPIRED",
                            "outcome": ["mutationId": mutation["mutationId"]!, "status": "applied", "operation": mismatchedProof ? "delete" : mutation["operation"]!, "libraryId": mutation["libraryId"]!, "recordKey": key, "appliedRevision": 2]]
                }
                if pushedEnvelopes.count == 1, let firstPushAssetId { record["assetIds"] = [firstPushAssetId] }
                record["id"] = "cloud-" + key; record["revision"] = 2; record["updatedAt"] = 1; record["deleted"] = deletedConflict
                return ["mutationId": mutation["mutationId"]!, "status": deletedConflict ? "conflict" : "applied", "record": record, "currentRevision": 2, "error": deletedConflict ? "RECORD_DELETED" : NSNull()]
            }
            proto.reply(["results": results, "syncEpoch": 1])
        case "/api/private-record-assets":
            let manifest = (try? JSONSerialization.jsonObject(with: proto.bodyData)) as? [String: Any] ?? [:]
            assetBodies.append(manifest)
            if expiredAssetManifest {
                var outcome: [String: Any] = ["status": "applied", "operation": "createAsset", "mutationId": manifest["mutationId"]!, "assetId": manifest["assetId"]!, "libraryId": manifest["libraryId"]!, "recordKey": manifest["recordKey"]!]
                if mismatchedAssetProof { outcome["assetId"] = "different-asset" }
                proto.reply(["error": "MUTATION_RECEIPT_EXPIRED", "details": ["outcome": outcome]], status: 410)
            } else { var response = manifest; response["status"] = "pending"; proto.reply(response) }
        default:
            if let manifest = assetBodies.last, let assetId = manifest["assetId"] as? String, path == "/api/private-record-assets/\(assetId)" {
                var response = manifest; response["status"] = expiredAssetManifest || expiredAssetComplete ? "ready" : "pending"; proto.reply(response)
            } else if let manifest = assetBodies.last, let assetId = manifest["assetId"] as? String, path == "/api/private-record-assets/\(assetId)/content" {
                assetPuts += 1; proto.reply(["status": "uploaded"])
            } else if let manifest = assetBodies.last, let assetId = manifest["assetId"] as? String, path == "/api/private-record-assets/\(assetId)/complete" {
                assetCompletes += 1
                let complete = (try? JSONSerialization.jsonObject(with: proto.bodyData)) as? [String: Any] ?? [:]
                if expiredAssetComplete {
                    proto.reply(["error": "MUTATION_RECEIPT_EXPIRED", "details": ["outcome": ["status": "applied", "operation": "completeAsset", "mutationId": complete["mutationId"]!, "assetId": assetId, "libraryId": manifest["libraryId"]!, "recordKey": manifest["recordKey"]!]]], status: 410)
                } else { var response = manifest; response["status"] = "ready"; proto.reply(response) }
            } else if let id = downloadableAssetID, path == "/api/private-record-assets/\(id)" {
                proto.reply(["assetId": id, "status": "ready", "downloadUrl": "https://api.jifenqi.com/api/private-record-assets/\(id)/content"])
            } else if let id = downloadableAssetID, path == "/api/private-record-assets/\(id)/content" {
                proto.replyBytes(audioBytes)
            } else { proto.fail() }
        }
    }
}

private nonisolated final class GroupResponseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: IdentityTransportProtocol?
    func hold(_ proto: IdentityTransportProtocol) {
        lock.lock(); defer { lock.unlock() }
        pending = proto
    }
    func release() {
        lock.lock(); let proto = pending; pending = nil; lock.unlock()
        proto?.reply(["items": [], "nextCursor": NSNull()])
    }
}

@MainActor private final class IdentityRecordLoaderGate {
    private var started = false
    private var loader: CheckedContinuation<[ScoreboardRecord], Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    func load() async -> [ScoreboardRecord] {
        await withCheckedContinuation { continuation in
            loader = continuation; started = true
            let waiting = observers; observers = []
            for observer in waiting { observer.resume() }
        }
    }
    func waitForStart() async {
        if started { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func release() { loader?.resume(returning: []); loader = nil }
}

@MainActor final class PersonalRecordsTransportTests: XCTestCase {
    private struct Fixture {
        var root: URL; var identity: ParticipantIdentityStore; var tokens: AuthTokenStore; var client: APIClient; var session: URLSession; var token: String
    }
    private func fixture() async throws -> Fixture {
        let id = UUID().uuidString
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("identity-transport-" + id)
        let identity = ParticipantIdentityStore(fileURL: root.appendingPathComponent("identity.json"))
        try identity.adopt(libraryId: identity.ledger.libraryId, accountId: "account", person: .init(id: "person-account", kind: .account))
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [IdentityTransportProtocol.self]
        let session = URLSession(configuration: config), tokens = AuthTokenStore(service: "identity-transport-" + id)
        try await tokens.setAuth(token: id, expiresAt: Date().addingTimeInterval(3600))
        return Fixture(root: root, identity: identity, tokens: tokens, client: APIClient(session: session, tokenStore: tokens), session: session, token: id)
    }
    private func cleanup(_ f: Fixture) async {
        IdentityTransportProtocol.register(f.token, handler: nil); f.session.invalidateAndCancel()
        await f.tokens.clearAuth(); try? FileManager.default.removeItem(at: f.root)
    }
    private func sync(_ f: Fixture, records: [ScoreboardRecord] = []) -> PersonalRecordsCloudSync {
        .init(client: f.client, fileURL: f.root.appendingPathComponent("cloud.json"), identity: f.identity,
              currentAccountID: { "account" }, scoreRecords: { records }, timerRecords: { [] })
    }
    private func accountJournal(_ f: Fixture) throws -> [String: Any] {
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: f.root.appendingPathComponent("cloud.json"))) as! [String: Any]
        return (root["accounts"] as! [String: Any])["account"] as! [String: Any]
    }

    func testPermanentSizeRejectionsPreserveLocalRecordAndContinueLaterRecords() async throws {
        for http in [false, true] {
            let f = try await fixture(), server = IdentityTransportServer()
            if http { server.httpOversizedKeys = ["oversized"] } else { server.permanentOversizedKeys = ["oversized"] }
            IdentityTransportProtocol.register(f.token) { server.respond($0) }
            let bad = ScoreboardRecord(id: "oversized", gameType: .pingpong, startTime: Date(), team1Name: "YY", team2Name: "Bob", team1FinalScore: 11, team2FinalScore: 9, totalScoreChanges: 1)
            let good = ScoreboardRecord(id: "after-large", gameType: .pingpong, startTime: Date(), team1Name: "YY", team2Name: "Bob", team1FinalScore: 12, team2FinalScore: 9, totalScoreChanges: 1)
            try f.identity.registerRecord(bad.id); try f.identity.registerRecord(good.id)
            var records = http ? [bad] : [bad, good]
            let service = PersonalRecordsCloudSync(client: f.client, fileURL: f.root.appendingPathComponent("cloud.json"), identity: f.identity,
                currentAccountID: { "account" }, scoreRecords: { records }, timerRecords: { [] })
            await service.sessionDidAuthenticate(userId: "account"); await service.synchronizeNow()
            if http { records.append(good); await service.synchronizeNow() }
            await service.synchronizeNow()
            XCTAssertEqual(service.blockedRecordCount, 1); XCTAssertEqual(service.pendingCount, 1)
            XCTAssertTrue(server.pushedKeys.contains(good.id)); XCTAssertEqual(bad.team1FinalScore, 11)
            XCTAssertNotNil((try accountJournal(f))["outbox"])
            service.signedOut(explicit: false); await cleanup(f)
        }
    }

    func testCompactedIdentityReceiptUsesProofOrRetainsOriginalIntentWithoutBlockingRecords() async throws {
        for proven in [true, false] {
            let f = try await fixture(), server = IdentityTransportServer(); server.expiredIdentity = true; server.mismatchedIdentityProof = !proven
            IdentityTransportProtocol.register(f.token) { server.respond($0) }
            let record = ScoreboardRecord(id: "identity-unblocked", gameType: .pingpong, startTime: Date(), team1Name: "YY", team2Name: "Bob", team1FinalScore: 11, team2FinalScore: 9, totalScoreChanges: 1)
            try f.identity.registerRecord(record.id)
            let service = sync(f, records: [record]); await service.sessionDidAuthenticate(userId: "account")
            let alias = try f.identity.link(name: "YY"); service.enqueueIdentity(accountId: "account", operation: "linkAlias", alias: alias)
            await service.synchronizeNow(); await service.synchronizeNow()
            XCTAssertEqual(server.mutationBodies.count, 1); XCTAssertTrue(server.pushedKeys.contains(record.id))
            XCTAssertEqual(((try accountJournal(f))["pendingIdentityMutations"] as? [Any])?.count ?? 0, proven ? 0 : 1)
            XCTAssertEqual(((try accountJournal(f))["identityOutbox"] as? [Any])?.count, 0)
            service.signedOut(explicit: false); await cleanup(f)
        }
    }

    func testCompactedAdoptionProofRecoversAndUnprovenMappingRemainsLocal() async throws {
        for proven in [true, false] {
            let f = try await fixture(), server = IdentityTransportServer(); server.compactedAdoption = true; server.mismatchedAdoptionProof = !proven
            IdentityTransportProtocol.register(f.token) { server.respond($0) }
            try f.identity.beginNewGuest(); let library = f.identity.ledger.libraryId
            let service = sync(f); await service.sessionDidAuthenticate(userId: "account"); await service.synchronizeNow(); await service.synchronizeNow()
            XCTAssertEqual(server.preparedBodies.count, 1); XCTAssertEqual(server.commitBodies.count, 1)
            XCTAssertEqual(f.identity.state.ledgers[library]?.ownerAccountId, proven ? "account" : nil)
            XCTAssertEqual(((try accountJournal(f))["blockedAdoptions"] as? [String: String])?.count ?? 0, proven ? 0 : 1)
            service.signedOut(explicit: false); await cleanup(f)
        }
    }

    func testCompactedAssetReceiptsUseOriginalManifestAndKeepUnprovenBinary() async throws {
        for mode in ["manifest", "complete", "unproven"] {
            let f = try await fixture(), server = IdentityTransportServer(); server.audioEnabled = true
            server.expiredAssetManifest = mode != "complete"; server.expiredAssetComplete = mode == "complete"; server.mismatchedAssetProof = mode == "unproven"
            IdentityTransportProtocol.register(f.token) { server.respond($0) }
            let relative = try ScoreboardRecordManager.createVoiceNoteTempFile(recordId: "asset-proof")
            let localFile = ScoreboardRecordManager.voiceNoteFileURL(relative); try server.audioBytes.write(to: localFile)
            var record = ScoreboardRecord(id: "asset-proof", gameType: .pingpong, startTime: Date(), team1Name: "YY", team2Name: "Bob", team1FinalScore: 11, team2FinalScore: 9, totalScoreChanges: 1)
            record.voiceNote = .init(relativePath: relative, durationMs: 3000); try f.identity.registerRecord(record.id)
            let service = sync(f, records: [record]); await service.sessionDidAuthenticate(userId: "account"); await service.synchronizeNow(); await service.synchronizeNow()
            XCTAssertEqual(server.assetBodies.count, 1); XCTAssertEqual(server.assetPuts, mode == "complete" ? 1 : 0)
            XCTAssertTrue(FileManager.default.fileExists(atPath: localFile.path))
            let journal = try accountJournal(f)
            XCTAssertEqual((journal["blockedAssets"] as? [String: String])?.count ?? 0, mode == "unproven" ? 1 : 0)
            XCTAssertEqual((journal["readyAssets"] as? [String])?.count ?? 0, mode == "unproven" ? 0 : 1)
            service.signedOut(explicit: false); try? FileManager.default.removeItem(at: localFile); await cleanup(f)
        }
    }

    func testResponseBudgetSplitRetainsMutationIDsAndMakesProgress() async throws {
        let f = try await fixture(), server = IdentityTransportServer(); server.splitMultiple = true
        IdentityTransportProtocol.register(f.token) { server.respond($0) }
        let records = (0..<3).map { ScoreboardRecord(id: "split-\($0)", gameType: .pingpong, startTime: Date(), team1Name: "YY", team2Name: "Bob", team1FinalScore: 11, team2FinalScore: 9, totalScoreChanges: 1) }
        for record in records { try f.identity.registerRecord(record.id) }
        let service = sync(f, records: records); await service.sessionDidAuthenticate(userId: "account"); await service.synchronizeNow()
        XCTAssertEqual(service.pendingCount, 3); XCTAssertEqual(service.blockedRecordCount, 0)
        await service.synchronizeNow(); XCTAssertEqual(server.pushAttempts.count, 1)
        try await Task.sleep(for: .milliseconds(1200)); await service.synchronizeNow()
        XCTAssertEqual(service.pendingCount, 0)
        let original = Dictionary(uniqueKeysWithValues: server.pushAttempts[0].map { ($0["recordKey"] as! String, $0["mutationId"] as! String) })
        for attempt in server.pushAttempts.dropFirst() { for item in attempt { XCTAssertEqual(original[item["recordKey"] as! String], item["mutationId"] as? String) } }
        service.signedOut(explicit: false); await cleanup(f)
    }

    func testRateLimitBackoffSurvivesRestartWithoutBlockingRecord() async throws {
        let f = try await fixture(), server = IdentityTransportServer(); server.throttleFirst = true
        IdentityTransportProtocol.register(f.token) { server.respond($0) }
        let record = ScoreboardRecord(id: "rate-limit", gameType: .pingpong, startTime: Date(), team1Name: "YY", team2Name: "Bob", team1FinalScore: 11, team2FinalScore: 9, totalScoreChanges: 1)
        try f.identity.registerRecord(record.id)
        let first = sync(f, records: [record]); await first.sessionDidAuthenticate(userId: "account"); await first.synchronizeNow(); first.signedOut(explicit: false)
        let restarted = sync(f, records: [record]); await restarted.sessionDidAuthenticate(userId: "account"); await restarted.synchronizeNow()
        XCTAssertEqual(server.pushAttempts.count, 1); XCTAssertEqual(restarted.pendingCount, 1); XCTAssertEqual(restarted.blockedRecordCount, 0)
        try await Task.sleep(for: .milliseconds(1200)); await restarted.synchronizeNow()
        XCTAssertEqual(restarted.pendingCount, 0)
        XCTAssertEqual(server.pushAttempts[0][0]["mutationId"] as? String, server.pushAttempts.last?[0]["mutationId"] as? String)
        restarted.signedOut(explicit: false); await cleanup(f)
    }

    func testExpiredAppliedReceiptAcknowledgesOriginalWithoutOverwritingNewerCloud() async throws {
        let f = try await fixture(), server = IdentityTransportServer(); server.expiredReceipt = true
        IdentityTransportProtocol.register(f.token) { server.respond($0) }
        let record = ScoreboardRecord(id: "expired", gameType: .pingpong, startTime: Date(), team1Name: "YY", team2Name: "Bob", team1FinalScore: 11, team2FinalScore: 9, totalScoreChanges: 1)
        try f.identity.registerRecord(record.id)
        let service = sync(f, records: [record]); await service.sessionDidAuthenticate(userId: "account"); await service.synchronizeNow(); await service.synchronizeNow()
        XCTAssertEqual(service.pendingCount, 0); XCTAssertEqual(server.pushAttempts.count, 1)
        XCTAssertEqual(service.remoteRecords.first?.revision, 9); XCTAssertEqual(service.remoteRecords.first?.summary["leftScore"]?.integer, 99)
        service.signedOut(explicit: false); await cleanup(f)
    }

    func testExpiredReceiptWithMismatchedProofRetainsLocalRecord() async throws {
        let f = try await fixture(), server = IdentityTransportServer(); server.expiredReceipt = true; server.mismatchedProof = true
        IdentityTransportProtocol.register(f.token) { server.respond($0) }
        let record = ScoreboardRecord(id: "unproven", gameType: .pingpong, startTime: Date(), team1Name: "YY", team2Name: "Bob", team1FinalScore: 11, team2FinalScore: 9, totalScoreChanges: 1)
        try f.identity.registerRecord(record.id)
        let service = sync(f, records: [record]); await service.sessionDidAuthenticate(userId: "account"); await service.synchronizeNow(); await service.synchronizeNow()
        XCTAssertEqual(service.pendingCount, 1); XCTAssertEqual(service.blockedRecordCount, 1); XCTAssertEqual(server.pushAttempts.count, 1)
        service.signedOut(explicit: false); await cleanup(f)
    }

    func testLostAliasReplyReplaysIdenticalPersistedRequestAfterRestart() async throws {
        let f = try await fixture(), server = IdentityTransportServer(); server.loseFirstMutationReply = true
        IdentityTransportProtocol.register(f.token) { server.respond($0) }
        let first = sync(f); await first.sessionDidAuthenticate(userId: "account")
        let alias = try f.identity.link(name: "YY")
        first.enqueueIdentity(accountId: "account", operation: "linkAlias", alias: alias)
        await first.synchronizeNow(); first.signedOut(explicit: false)
        let restarted = sync(f); await restarted.sessionDidAuthenticate(userId: "account"); await restarted.synchronizeNow()
        XCTAssertEqual(server.mutationBodies.count, 2)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: server.mutationBodies[0]) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: server.mutationBodies[1]) as? NSDictionary)
        XCTAssertEqual(restarted.phase, "synced")
        restarted.signedOut(explicit: false); await cleanup(f)
    }
    func testDeletedCloudRecordCanOnlyBeRetainedWithANewRecordKey() async throws {
        let f = try await fixture(), server = IdentityTransportServer(); server.deletedConflict = true
        IdentityTransportProtocol.register(f.token) { server.respond($0) }
        let record = ScoreboardRecord(id: "original", gameType: .pingpong, startTime: Date(), team1Name: "YY", team2Name: "Bob", team1FinalScore: 11, team2FinalScore: 9, totalScoreChanges: 1)
        try f.identity.registerRecord(record.id)
        let sync = sync(f, records: [record]); await sync.sessionDidAuthenticate(userId: "account"); await sync.synchronizeNow()
        let conflict = try XCTUnwrap(sync.conflicts.first)
        try sync.resolveConflict(conflict, keepLocal: true)
        server.deletedConflict = false; await sync.synchronizeNow()
        XCTAssertEqual(server.pushedKeys.count, 2)
        XCTAssertEqual(server.pushedKeys.first, "original")
        XCTAssertNotEqual(server.pushedKeys.last, "original")
        XCTAssertTrue(sync.usesCloudVersion(recordKey: "original"))
        XCTAssertTrue(sync.conflicts.isEmpty)
        sync.signedOut(explicit: false); await cleanup(f)
    }

    func testRetainedConflictDoesNotAutomaticallyRescheduleForever() async throws {
        let f = try await fixture(), server = IdentityTransportServer(); server.deletedConflict = true
        IdentityTransportProtocol.register(f.token) { server.respond($0) }
        let record = ScoreboardRecord(id: "needs-choice", gameType: .pingpong, startTime: Date(), team1Name: "YY", team2Name: "Bob", team1FinalScore: 11, team2FinalScore: 9, totalScoreChanges: 1)
        try f.identity.registerRecord(record.id)
        let service = sync(f, records: [record]); await service.sessionDidAuthenticate(userId: "account")
        await service.synchronizeNow(); await service.synchronizeNow()
        let reads = server.snapshotReads
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(server.snapshotReads, reads)
        XCTAssertEqual(service.conflicts.count, 1)
        service.signedOut(explicit: false); await cleanup(f)
    }

    func testNewerCloudRevisionReplacesNativeDisplayWithoutOverwritingBackup() async throws {
        let f = try await fixture(), server = IdentityTransportServer()
        IdentityTransportProtocol.register(f.token) { server.respond($0) }
        let record = ScoreboardRecord(id: "edited-elsewhere", gameType: .pingpong, startTime: Date(), team1Name: "YY", team2Name: "Bob", team1FinalScore: 11, team2FinalScore: 9, totalScoreChanges: 1)
        try f.identity.registerRecord(record.id)
        let service = sync(f, records: [record]); await service.sessionDidAuthenticate(userId: "account"); await service.synchronizeNow()
        var remote = try XCTUnwrap(server.pushedEnvelopes.first)
        remote["revision"] = 3; remote["updatedAt"] = 2; remote["deleted"] = false
        var summary = remote["summary"] as! [String: Any]; summary["leftScore"] = 21; remote["summary"] = summary
        server.pullRecords = [remote]
        await service.synchronizeNow()
        XCTAssertTrue(service.usesCloudVersion(recordKey: record.id))
        XCTAssertFalse(PersonalRecordAccessPolicy.allowsNativeRecord(record.id, identity: f.identity, cloud: service))
        XCTAssertEqual(service.remoteRecords.first?.summary["leftScore"]?.integer, 21)
        XCTAssertEqual(record.team1FinalScore, 11)
        XCTAssertEqual(server.pushedEnvelopes.count, 1)
        service.signedOut(explicit: false); await cleanup(f)
    }

    func testCommittedKeepReceiptRecoversAfterRestartWithoutReadoptingSourceLibrary() async throws {
        let f = try await fixture(), sourceLibrary = f.identity.ledger.libraryId
        try f.identity.registerRecord("source-private")
        let first = sync(f); await first.sessionDidAuthenticate(userId: "account")
        let context = WechatBindingSessionContext(accountID: "account", authRevision: await f.client.authSessionRevision(), generation: 0)
        try first.pauseForAccountLink(context: context)
        first.stageAccountLinkResult(.init(mode: .keep, masterUserId: "master", sourceUserId: "account"))
        first.signedOut(explicit: false)
        let restored = PersonalRecordsCloudSync(client: f.client, fileURL: f.root.appendingPathComponent("cloud.json"), identity: f.identity,
            currentAccountID: { "master" }, scoreRecords: { [] }, timerRecords: { [] })
        await restored.sessionDidAuthenticate(userId: "master")
        XCTAssertFalse(f.identity.canRead(recordKey: "source-private"))
        XCTAssertTrue(f.identity.state.archivedLibraries.contains(sourceLibrary))
        XCTAssertFalse(f.identity.unownedLedgers.contains { $0.libraryId == sourceLibrary })
        XCTAssertEqual(restored.pendingCount, 0)
        restored.signedOut(explicit: false); await cleanup(f)
    }

    func testHistoricalClaimUploadsOnlyStrictInputFields() async throws {
        let f = try await fixture(), server = IdentityTransportServer()
        let alias = try f.identity.link(name: "YY")
        server.aliases = [try JSONSerialization.jsonObject(with: JSONEncoder().encode(alias)) as! [String: Any]]
        IdentityTransportProtocol.register(f.token) { server.respond($0) }
        let record = ScoreboardRecord(id: "claimed", gameType: .pingpong, startTime: Date(), team1Name: "YY", team2Name: "Bob", team1FinalScore: 11, team2FinalScore: 9, totalScoreChanges: 1)
        try f.identity.registerRecord(record.id)
        try f.identity.installClaims([.init(libraryId: f.identity.ledger.libraryId, recordKey: record.id, seatKey: "side:0", aliasId: alias.id, nameSnapshot: "YY")])
        let service = sync(f, records: [record]); await service.sessionDidAuthenticate(userId: "account"); await service.synchronizeNow()
        XCTAssertEqual(service.phase, "synced")
        XCTAssertEqual(server.claimInputs.count, 1)
        XCTAssertEqual(Set(server.claimInputs[0].keys), ["id", "libraryId", "recordKey", "seatKey", "nameSnapshot", "participantKind"])
        service.signedOut(explicit: false); await cleanup(f)
    }

    func testLostHistoricalClaimReplyReplaysThePersistedBody() async throws {
        let f = try await fixture(), server = IdentityTransportServer()
        let alias = try f.identity.link(name: "YY"); server.loseFirstMutationReply = true
        server.aliases = [try JSONSerialization.jsonObject(with: JSONEncoder().encode(alias)) as! [String: Any]]
        IdentityTransportProtocol.register(f.token) { server.respond($0) }
        let record = ScoreboardRecord(id: "claim-retry", gameType: .pingpong, startTime: Date(), team1Name: "YY", team2Name: "Bob", team1FinalScore: 11, team2FinalScore: 9, totalScoreChanges: 1)
        try f.identity.registerRecord(record.id)
        try f.identity.installClaims([.init(libraryId: f.identity.ledger.libraryId, recordKey: record.id, seatKey: "side:0", aliasId: alias.id, nameSnapshot: "YY")])
        let first = sync(f, records: [record]); await first.sessionDidAuthenticate(userId: "account"); await first.synchronizeNow(); first.signedOut(explicit: false)
        let restored = sync(f, records: [record]); await restored.sessionDidAuthenticate(userId: "account"); await restored.synchronizeNow()
        XCTAssertEqual(server.mutationBodies.count, 2)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: server.mutationBodies[0]) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: server.mutationBodies[1]) as? NSDictionary)
        XCTAssertEqual(restored.phase, "synced")
        restored.signedOut(explicit: false); await cleanup(f)
    }

    func testStaleLoginWarmupCannotReactivateSignedOutLibrary() async throws {
        let f = try await fixture()
        var currentAccount: String? = "account"
        let service = PersonalRecordsCloudSync(client: f.client, fileURL: f.root.appendingPathComponent("cloud.json"), identity: f.identity,
            currentAccountID: { currentAccount }, scoreRecords: { [] }, timerRecords: { [] })
        await service.sessionDidAuthenticate(userId: "account")
        currentAccount = nil; service.signedOut(explicit: true)
        let guestLibrary = f.identity.ledger.libraryId
        await service.sessionDidAuthenticate(userId: "account")
        XCTAssertTrue(f.identity.isGuest)
        XCTAssertEqual(f.identity.ledger.libraryId, guestLibrary)
        await cleanup(f)
    }

    func testExpiredAdoptionStartsAFreshPreparedRequest() async throws {
        let f = try await fixture(), server = IdentityTransportServer(); server.expireFirstAdoption = true
        IdentityTransportProtocol.register(f.token) { server.respond($0) }
        try f.identity.beginNewGuest()
        let guestLibrary = f.identity.ledger.libraryId
        let service = sync(f); await service.sessionDidAuthenticate(userId: "account"); await service.synchronizeNow()
        XCTAssertEqual(server.preparedBodies.count, 2)
        XCTAssertNotEqual(server.preparedBodies[0]["mutationId"] as? String, server.preparedBodies[1]["mutationId"] as? String)
        XCTAssertEqual(f.identity.state.ledgers[guestLibrary]?.ownerAccountId, "account")
        XCTAssertEqual(service.phase, "synced")
        service.signedOut(explicit: false); await cleanup(f)
    }

    func testMissingAnnotationsEncodeExplicitNullAndNoAudioReferences() async throws {
        let f = try await fixture(), server = IdentityTransportServer()
        server.firstPushAssetId = "previous-audio"
        IdentityTransportProtocol.register(f.token) { server.respond($0) }
        var record = ScoreboardRecord(id: "cleared", gameType: .pingpong, startTime: Date(), team1Name: "YY", team2Name: "Bob", team1FinalScore: 11, team2FinalScore: 9, totalScoreChanges: 1)
        record.note = "old annotation"; record.voiceNote = .init(relativePath: "old.m4a", durationMs: 3000)
        try f.identity.registerRecord(record.id)
        let service = PersonalRecordsCloudSync(client: f.client, fileURL: f.root.appendingPathComponent("cloud.json"), identity: f.identity,
            currentAccountID: { "account" }, scoreRecords: { [record] }, timerRecords: { [] })
        await service.sessionDidAuthenticate(userId: "account"); await service.synchronizeNow()
        record.note = nil; record.voiceNote = nil
        await service.synchronizeNow()
        XCTAssertEqual(server.pushedEnvelopes.count, 2)
        let wire = try XCTUnwrap(server.pushedEnvelopes.last), payload = try XCTUnwrap(wire["nativePayload"] as? [String: Any])
        XCTAssertTrue(wire["note"] is NSNull)
        XCTAssertTrue(payload["note"] is NSNull)
        XCTAssertTrue(payload["voiceNote"] is NSNull)
        XCTAssertEqual((wire["assetIds"] as? [String])?.count, 0)
        service.signedOut(explicit: false); await cleanup(f)
    }

    func testOversizedRecordIsIsolatedAcrossRestartAndChangedContentRetries() async throws {
        let f = try await fixture(), server = IdentityTransportServer()
        IdentityTransportProtocol.register(f.token) { server.respond($0) }
        var oversized = ScoreboardRecord(id: "oversized", gameType: .pingpong, startTime: Date(), team1Name: "YY", team2Name: "Bob", team1FinalScore: 11, team2FinalScore: 9, totalScoreChanges: 1)
        oversized.extraData = ["futurePayload": AnyCodable(String(repeating: "a", count: 9 * 1024 * 1024))]
        let healthy = ScoreboardRecord(id: "healthy", gameType: .pingpong, startTime: Date(), team1Name: "YY", team2Name: "Bob", team1FinalScore: 11, team2FinalScore: 9, totalScoreChanges: 1)
        try f.identity.registerRecord(oversized.id); try f.identity.registerRecord(healthy.id)
        var records = [oversized, healthy]
        func service() -> PersonalRecordsCloudSync {
            .init(client: f.client, fileURL: f.root.appendingPathComponent("cloud.json"), identity: f.identity,
                  currentAccountID: { "account" }, scoreRecords: { records }, timerRecords: { [] })
        }
        let first = service(); await first.sessionDidAuthenticate(userId: "account"); await first.synchronizeNow()
        XCTAssertEqual(server.pushedKeys, ["healthy"])
        XCTAssertEqual(first.pendingCount, 1); XCTAssertEqual(first.blockedRecordCount, 1)
        XCTAssertEqual(first.phase, "partial")
        first.signedOut(explicit: false)
        let restored = service(); await restored.sessionDidAuthenticate(userId: "account"); await restored.synchronizeNow()
        XCTAssertEqual(server.pushedKeys, ["healthy"])
        XCTAssertEqual(restored.blockedRecordCount, 1)
        records[0].extraData = ["futurePayload": AnyCodable("smaller edited payload")]
        await restored.synchronizeNow()
        XCTAssertEqual(server.pushedKeys, ["healthy", "oversized"])
        XCTAssertEqual(restored.pendingCount, 0); XCTAssertEqual(restored.blockedRecordCount, 0)
        XCTAssertEqual(restored.phase, "synced")
        restored.signedOut(explicit: false); await cleanup(f)
    }

    func testRejectedRecordDoesNotBlockLaterBatchesAndCanBeRetried() async throws {
        let f = try await fixture(), server = IdentityTransportServer(); server.rejectedKeys = ["record-0"]
        IdentityTransportProtocol.register(f.token) { server.respond($0) }
        let records = (0..<52).map { index in
            ScoreboardRecord(id: "record-\(index)", gameType: .pingpong, startTime: Date(), team1Name: "YY", team2Name: "Bob", team1FinalScore: 11, team2FinalScore: 9, totalScoreChanges: 1)
        }
        for record in records { try f.identity.registerRecord(record.id) }
        let service = sync(f, records: records); await service.sessionDidAuthenticate(userId: "account"); await service.synchronizeNow()
        XCTAssertEqual(server.pushedKeys.count, 52)
        XCTAssertTrue(server.pushedKeys.contains("record-51"))
        XCTAssertEqual(service.pendingCount, 1); XCTAssertEqual(service.blockedRecordCount, 1)
        await service.synchronizeNow()
        XCTAssertEqual(server.pushedKeys.count, 52)
        server.rejectedKeys = []
        await service.retryBlockedRecords(); await service.synchronizeNow()
        XCTAssertEqual(server.pushedKeys.count, 53)
        XCTAssertEqual(service.pendingCount, 0); XCTAssertEqual(service.phase, "synced")
        service.signedOut(explicit: false); await cleanup(f)
    }

    func testAudioDownloadUsesManifestAbsoluteEndpoint() async throws {
        let f = try await fixture(), server = IdentityTransportServer(); server.downloadableAssetID = UUID().uuidString
        IdentityTransportProtocol.register(f.token) { server.respond($0) }
        let service = sync(f); await service.sessionDidAuthenticate(userId: "account")
        let url = try await service.downloadAudio(assetId: try XCTUnwrap(server.downloadableAssetID))
        XCTAssertEqual(try Data(contentsOf: url), server.audioBytes)
        XCTAssertTrue(url.path.hasPrefix(f.root.path + "/"))
        try service.clearLocalCache()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        service.signedOut(explicit: false); await cleanup(f)
    }

    func testGroupRefreshCannotRestoreCacheAfterLocalReset() async throws {
        let f = try await fixture()
        let started = expectation(description: "group request started")
        let response = GroupResponseGate()
        IdentityTransportProtocol.register(f.token) { proto in
            response.hold(proto)
            started.fulfill()
        }
        let directory = f.root.appendingPathComponent("group-cache", isDirectory: true)
        let groups = PersonalGroupRecords(cacheDirectoryURL: directory, repository: .init(client: f.client),
            currentAccountID: { "account" })
        let refresh = Task { await groups.refresh() }
        await fulfillment(of: [started], timeout: 5)
        try groups.clearLocalCache()
        response.release()
        await refresh.value
        XCTAssertTrue(groups.rows.isEmpty)
        XCTAssertNil(groups.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        await cleanup(f)
    }

    func testAssetEndpointsAcceptOnlyPrivateAudioOnTheSameOrigin() throws {
        let base = try XCTUnwrap(URL(string: "https://api.jifenqi.com")), id = UUID().uuidString
        let path = "/api/private-record-assets/\(id)/content"
        XCTAssertEqual(try PersonalRecordAssetEndpoint.resolve(path, baseURL: base).path, path)
        XCTAssertEqual(try PersonalRecordAssetEndpoint.resolve("https://api.jifenqi.com" + path, baseURL: base).path, path)
        XCTAssertEqual(try PersonalRecordAssetEndpoint.resolve(String(path.dropFirst()) + "?v=1", baseURL: base).query, [URLQueryItem(name: "v", value: "1")])
        for invalid in ["https://unrelated.example" + path, "http://api.jifenqi.com" + path,
                        "//unrelated.example" + path, "https://api.jifenqi.com:444" + path,
                        "https://user@api.jifenqi.com" + path, "/api/self-identity", path + "#fragment"] {
            XCTAssertThrowsError(try PersonalRecordAssetEndpoint.resolve(invalid, baseURL: base))
        }
    }


    func testCancelledAuthenticationWarmupCannotOverwriteResetOrLogoutState() async throws {
        for resetLocalCache in [true, false] {
            let f = try await fixture(), gate = IdentityRecordLoaderGate()
            var currentAccount: String? = "account"
            let service = PersonalRecordsCloudSync(client: f.client, fileURL: f.root.appendingPathComponent("cloud.json"), identity: f.identity,
                currentAccountID: { currentAccount }, scoreRecords: { [] }, timerRecords: { [] },
                scoreRecordsInBackground: { await gate.load() })
            let warmup = Task { await service.sessionDidAuthenticate(userId: "account") }
            await gate.waitForStart()
            if resetLocalCache { try service.clearLocalCache() }
            else { currentAccount = nil; service.signedOut(explicit: true) }
            gate.release(); await warmup.value
            XCTAssertEqual(service.phase, "local")
            XCTAssertNil(service.lastError)
            XCTAssertTrue(service.remoteRecords.isEmpty)
            if resetLocalCache {
                let data = try Data(contentsOf: f.root.appendingPathComponent("cloud.json"))
                let state = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                XCTAssertTrue((state["accounts"] as? [String: Any])?.isEmpty == true)
            } else { XCTAssertTrue(f.identity.isGuest) }
            service.signedOut(explicit: false); await cleanup(f)
        }
    }

    func testBulkDeleteIsIdempotentAndRejectsUnreadableLibraries() async throws {
        let f = try await fixture(), service = sync(f), library = f.identity.ledger.libraryId
        await service.sessionDidAuthenticate(userId: "account")
        service.markDeleted(records: [("same-record", library), ("same-record", library), ("foreign-record", "foreign-library")])
        XCTAssertEqual(service.pendingCount, 1)
        XCTAssertTrue(service.isLocallyDeleted(libraryId: library, recordKey: "same-record"))
        XCTAssertFalse(service.isLocallyDeleted(libraryId: "foreign-library", recordKey: "foreign-record"))
        let url = f.root.appendingPathComponent("cloud.json"), original = try Data(contentsOf: url)
        service.markDeleted(recordKey: "same-record", libraryId: library)
        service.markDeleted(records: [("same-record", library), ("foreign-record", "foreign-library")])
        XCTAssertEqual(service.pendingCount, 1)
        XCTAssertEqual(try Data(contentsOf: url), original)
        service.signedOut(explicit: false)
        let restored = sync(f)
        XCTAssertEqual(restored.pendingCount, 1)
        XCTAssertTrue(restored.isLocallyDeleted(libraryId: library, recordKey: "same-record"))
        await cleanup(f)
    }

    func testManualRetryCapturesAnEditedRejectedRecordBeforeSending() async throws {
        let f = try await fixture(), server = IdentityTransportServer(); server.rejectedKeys = ["edited-rejection"]
        IdentityTransportProtocol.register(f.token) { server.respond($0) }
        var record = ScoreboardRecord(id: "edited-rejection", gameType: .pingpong, startTime: Date(), team1Name: "YY", team2Name: "Bob", team1FinalScore: 11, team2FinalScore: 9, totalScoreChanges: 1)
        record.note = "old note"
        try f.identity.registerRecord(record.id)
        let service = PersonalRecordsCloudSync(client: f.client, fileURL: f.root.appendingPathComponent("cloud.json"), identity: f.identity,
            currentAccountID: { "account" }, scoreRecords: { [record] }, timerRecords: { [] })
        await service.sessionDidAuthenticate(userId: "account"); await service.synchronizeNow()
        XCTAssertEqual(service.blockedRecordCount, 1)
        record.note = "edited note"
        server.rejectedKeys = []
        await service.retryBlockedRecords(); await service.synchronizeNow()
        XCTAssertEqual(server.pushedKeys, ["edited-rejection", "edited-rejection"])
        XCTAssertEqual(server.pushedEnvelopes.last?["note"] as? String, "edited note")
        XCTAssertEqual(service.phase, "synced")
        service.signedOut(explicit: false); await cleanup(f)
    }

}
