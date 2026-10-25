import CryptoKit
import Foundation
import Observation
import ScoreCore
import Network

nonisolated struct PersonalIdentitySnapshot: Codable, Sendable {
    struct Person: Codable, Sendable { var id: String; var kind: ParticipantPersonRef.Kind; var accountId: String?; var revision: Int }
    struct Capabilities: Codable, Sendable { var maxActiveAliases: Int; var privateRecordsV1: Bool; var privateRecordAudioV1: Bool }
    var schemaVersion: Int
    var person: Person
    var aliases: [ParticipantAlias]
    var capabilities: Capabilities
    var personRef: ParticipantPersonRef { .init(id: person.id, kind: person.kind) }
}

nonisolated struct PersonalIdentityMutation: Codable, Sendable {
    var mutationId: String = UUID().uuidString
    var expectedRevision: Int
    var operation: String
    var aliasId: String?
    var name: String?
    var nameType: String?
    var visibleInPicker: Bool?
    var claimId: String?
    var claims: [PersonalHistoricalClaimInput]?
}

/// The server's strict write schema deliberately excludes sidecar state and
/// server-owned revision/provenance fields returned by the claims read API.
nonisolated struct PersonalHistoricalClaimInput: Codable, Sendable {
    var id: String; var libraryId: String; var recordKey: String; var seatKey: String
    var nameSnapshot: String; var participantKind = "PERSON"
    init(_ claim: ParticipantHistoricalClaim) {
        id = claim.id; libraryId = claim.libraryId; recordKey = claim.recordKey
        seatKey = claim.seatKey; nameSnapshot = claim.nameSnapshot
    }
}

nonisolated private struct PersonalRecordMutation: Codable, Sendable {
    var mutationId = UUID().uuidString
    var operation: String
    var libraryId: String
    var recordKey: String
    var expectedRevision: Int
    var envelope: PersonalRecordEnvelope?
}

nonisolated struct PersonalRecordConflict: Codable, Identifiable, Sendable {
    var id: String
    var local: PersonalRecordEnvelope?
    var remote: PersonalRecordEnvelope?
    var operation: String
}

/// All writes (including synchronous UI mutations) share one FIFO queue so an
/// older background snapshot cannot overwrite a newer logout/reset snapshot.
nonisolated private final class PersonalRecordDiskIO: @unchecked Sendable {
    private let queue = DispatchQueue(label: "private-record-state", qos: .utility)
    private static func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
    func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        try queue.sync { try Self.write(value, to: url) }
    }
    func enqueueWrite<Value: Encodable & Sendable>(_ value: Value, to url: URL,
                                                  completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        queue.async {
            do { try Self.write(value, to: url); completion(.success(())) }
            catch { completion(.failure(error)) }
        }
    }
}

@MainActor @Observable
final class PersonalRecordsCloudSync {
    static let shared: PersonalRecordsCloudSync = {
        if AppTestRuntime.isolatesDefaultPrivateSync {
            // Hosted tests and UI fixtures may exercise real view lifecycles,
            // but only explicitly injected services may authenticate or sync.
            return PersonalRecordsCloudSync(fileURL: AppTestRuntime.storageRootURL?.appendingPathComponent("cloud.json"),
                observeConnectivity: false, currentAccountID: { nil })
        }
        return PersonalRecordsCloudSync(observeConnectivity: true)
    }()
    private(set) var phase = "local"
    private(set) var lastError: String?
    private(set) var remoteRecords: [PersonalRecordEnvelope] = []
    private var userId: String?
    private var authRevision: UInt64 = 0
    private var generation: UInt64 = 0
    private var task: Task<Void, Never>?
    private var pausedContext: WechatBindingSessionContext?
    private let client: APIClient
    private let fileURL: URL
    let audioCacheURL: URL
    private let diskIO = PersonalRecordDiskIO()
    private let identity: ParticipantIdentityStore
    private let currentAccountID: @MainActor () -> String?
    private let scoreRecords: @MainActor () -> [ScoreboardRecord]
    private let timerRecords: @MainActor () -> [GameRecordSummary]
    private let asyncScoreRecords: @MainActor () async -> [ScoreboardRecord]
    private let asyncTimerRecords: @MainActor () async -> [GameRecordSummary]
    private var persisted: Persisted
    private struct OutboxIndex {
        var accountId: String
        var pending: Set<String>
        var deleted: Set<String>
    }
    @ObservationIgnored private var cachedOutboxIndex: OutboxIndex?
    private let connectivity = NWPathMonitor()

    nonisolated private struct AccountState: Codable, Sendable {
        var cursor: String?
        var records: [String: PersonalRecordEnvelope] = [:]
        var outbox: [PersonalRecordMutation] = []
        var identityOutbox: [PersonalIdentityMutation] = []
        var digests: [String: String] = [:]
        var localRevisions: [String: Int] = [:]
        var queuedDigests: [String: String] = [:]
        var adoptionRequests: [String: String] = [:]
        var adoptionCommits: [String: String] = [:]
        var adoptionSeeds: [String: PrepareRequest]?
        var commitSeeds: [String: CommitRequest]?
        var uploadedClaims: Set<String> = []
        var assetIds: [String: String] = [:]
        var readyAssets: Set<String> = []
        var conflicts: [String: PersonalRecordConflict]?
        // Permanent local/server rejections stay durable but never block other records.
        var blockedMutations: [String: String]?
        var cloudChoices: [String: String]?
        var retryNotBefore: Date?
        var pushBatchLimit: Int?
        var pendingIdentityMutations: [PersonalIdentityMutation]?
        var blockedAdoptions: [String: String]?
        var blockedAssets: [String: String]?
        var archived = false
    }
    nonisolated private struct Persisted: Codable, Sendable {
        var accounts: [String: AccountState] = [:]
        var guestIntentOwners: [String: String] = [:]
        var pendingLink: PendingLink?
    }
    nonisolated private struct PendingLink: Codable, Sendable { var masterId: String; var sourceId: String; var mode: String }
    nonisolated private struct PushRequest: Encodable, Sendable { var mutations: [PersonalRecordMutation] }
    nonisolated private struct PushResponse: Decodable, Sendable {
        struct Result: Decodable, Sendable {
            var mutationId: String; var status: String; var record: PersonalRecordEnvelope?
            var error: String?; var currentRevision: Int?; var retryable: Bool?
            var splitBatch: Bool?; var retryAfterSeconds: Double?; var outcome: PrivateSyncMutationOutcome?
        }
        var results: [Result]; var syncEpoch: Int
    }
    nonisolated private struct PullResponse: Decodable, Sendable { var records: [PersonalRecordEnvelope]; var nextCursor: String; var hasMore: Bool; var syncEpoch: Int }
    nonisolated private struct QueryResponse: Decodable, Sendable { var records: [PersonalRecordEnvelope]; var nextCursor: String?; var total: Int }
    nonisolated private struct ClaimsResponse: Decodable, Sendable { var claims: [ParticipantHistoricalClaim]; var nextCursor: String? }
    nonisolated private struct AdoptionAlias: Codable, Sendable { var id: String; var name: String; var nameType = "PLAYER"; var visibleInPicker: Bool }
    nonisolated private struct PrepareRequest: Codable, Sendable { var mutationId: String; var guestPersonId: String; var guestLibraryId: String; var aliases: [AdoptionAlias] }
    nonisolated private struct CommitRequest: Codable, Sendable { var mutationId: String; var adoptionId: String }
    nonisolated private struct Adoption: Decodable, Sendable {
        var adoptionId: String; var guestPersonRef: ParticipantPersonRef; var accountPersonRef: ParticipantPersonRef
        var libraryId: String; var aliases: [ParticipantAlias]; var needsAliasReview: Bool
        var identity: PersonalIdentitySnapshot?
    }
    private struct AssetRequest: Encodable, Sendable {
        var mutationId: String; var assetId: String; var libraryId: String; var recordKey: String
        var sha256: String; var sizeBytes: Int; var contentType: String; var durationMs: Int
    }
    nonisolated private struct AssetResponse: Decodable, Sendable {
        var assetId: String; var status: String; var uploadUrl: String?; var downloadUrl: String?
        var libraryId: String?; var recordKey: String?; var sha256: String?; var sizeBytes: Int?
        var contentType: String?; var durationMs: Int?
    }
    private struct AssetComplete: Encodable, Sendable { var mutationId: String }

    init(client: APIClient = .shared, fileURL: URL? = nil, identity: ParticipantIdentityStore? = nil, observeConnectivity: Bool = false,
         audioCacheURL: URL? = nil,
         currentAccountID: @escaping @MainActor () -> String? = { SessionStore.shared.user?.id },
         scoreRecords: (@MainActor () -> [ScoreboardRecord])? = nil,
         timerRecords: (@MainActor () -> [GameRecordSummary])? = nil,
         scoreRecordsInBackground: (@MainActor () async -> [ScoreboardRecord])? = nil,
         timerRecordsInBackground: (@MainActor () async -> [GameRecordSummary])? = nil) {
        self.client = client
        self.identity = identity ?? .shared
        self.currentAccountID = currentAccountID
        self.scoreRecords = scoreRecords ?? { ScoreboardRecordManager.shared.loadAllRecords() }
        self.timerRecords = timerRecords ?? { TimerRecordManager.shared.getRecords() }
        if let scoreRecordsInBackground { self.asyncScoreRecords = scoreRecordsInBackground }
        else if let scoreRecords { self.asyncScoreRecords = { scoreRecords() } }
        else { self.asyncScoreRecords = { await ScoreboardRecordManager.shared.loadAllRecordsInBackground() } }
        if let timerRecordsInBackground { self.asyncTimerRecords = timerRecordsInBackground }
        else if let timerRecords { self.asyncTimerRecords = { timerRecords() } }
        else { self.asyncTimerRecords = { await TimerRecordManager.shared.getRecordsInBackground() } }
        self.fileURL = fileURL ?? AppTestRuntime.storageRootURL?.appendingPathComponent("cloud.json")
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("jifen-v3/participant-identity/cloud.json")
        self.audioCacheURL = audioCacheURL ?? fileURL?.deletingLastPathComponent().appendingPathComponent("PrivateRecordAudio", isDirectory: true)
            ?? AppTestRuntime.storageRootURL?.appendingPathComponent("PrivateRecordAudio", isDirectory: true)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("PrivateRecordAudio", isDirectory: true)
        persisted = (try? Data(contentsOf: self.fileURL)).flatMap { try? JSONDecoder().decode(Persisted.self, from: $0) } ?? Persisted()
        if observeConnectivity {
            connectivity.pathUpdateHandler = { [weak self] path in
                if path.status == .satisfied { Task { @MainActor [weak self] in self?.schedule() } }
            }
            connectivity.start(queue: DispatchQueue(label: "private-record-connectivity"))
        }
    }

    var storageFileURL: URL { fileURL }
    private func account(_ id: String) -> AccountState { persisted.accounts[id] ?? AccountState() }
    private func key(_ library: String, _ record: String) -> String { library + ":" + record }
    private func persist() throws {
        cachedOutboxIndex = nil
        try diskIO.write(persisted, to: fileURL)
    }
    private func persistInBackground() async throws {
        cachedOutboxIndex = nil
        let epoch = generation
        // Enqueue synchronously while still on MainActor, before the first
        // suspension, so a newer UI write always enters the FIFO after this one.
        let snapshot = persisted, url = fileURL
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            diskIO.enqueueWrite(snapshot, to: url) { continuation.resume(with: $0) }
        }
        try Task.checkCancellation()
        guard generation == epoch else { throw CancellationError() }
    }
    private func check(_ id: String, _ epoch: UInt64) throws {
        try Task.checkCancellation()
        guard userId == id, generation == epoch, pausedContext == nil,
              currentAccountID() == id else { throw CancellationError() }
    }

    func reportFailure(_ error: Error) { phase = "failed"; lastError = error.localizedDescription }
    var statusText: String {
        switch phase {
        case "syncing": return identityText("syncing", "正在同步")
        case "synced": return identityText("synced", "已同步")
        case "partial": return identityText("partially_synced", "部分内容待同步")
        case "failed": return identityText("sync_failed", "同步未完成")
        default: return identityText("saved_locally", "已保存在本机")
        }
    }
    var pendingCount: Int { (userId ?? identity.state.activeAccountId).map { account($0).outbox.count } ?? 0 }
    var blockedRecordCount: Int { userId.map { account($0).blockedMutations?.count ?? 0 } ?? 0 }
    func retryBlockedRecords() async {
        guard let id = userId, pausedContext == nil else { return }
        generation &+= 1; task?.cancel(); task = nil
        let epoch = generation
        do {
            // Keep rejections marked until capture has replaced any locally
            // edited envelope; otherwise retry would first resend stale content.
            try await captureLocalRecordsInBackground(accountId: id, epoch: epoch)
            try check(id, epoch)
            persisted.accounts[id]?.blockedMutations = nil
            persisted.accounts[id]?.retryNotBefore = nil
            try await persistInBackground(); try check(id, epoch)
            schedule()
        } catch is CancellationError { }
        catch { if generation == epoch, currentAccountID() == id { reportFailure(error) } }
    }
    var conflicts: [PersonalRecordConflict] { userId.map { Array(account($0).conflicts?.values ?? [:].values) } ?? [] }
    private func outboxIndex(for id: String, state: AccountState) -> OutboxIndex {
        if let cachedOutboxIndex, cachedOutboxIndex.accountId == id { return cachedOutboxIndex }
        var pending: Set<String> = [], deleted: Set<String> = []
        for mutation in state.outbox {
            let record = key(mutation.libraryId, mutation.recordKey)
            pending.insert(record)
            if mutation.operation == "delete" { deleted.insert(record) }
        }
        let index = OutboxIndex(accountId: id, pending: pending, deleted: deleted)
        cachedOutboxIndex = index
        return index
    }
    func usesCloudVersion(recordKey: String) -> Bool {
        guard let id = userId ?? identity.state.activeAccountId else { return false }
        let state = account(id), library = identity.libraryId(for: recordKey), cacheKey = key(library, recordKey)
        if state.cloudChoices?[cacheKey] != nil { return true }
        let hasLocalChanges = outboxIndex(for: id, state: state).pending.contains(cacheKey)
        return !hasLocalChanges && (state.records[cacheKey]?.revision ?? 0) > (state.localRevisions[cacheKey] ?? 0)
    }

    func resolveConflict(_ conflict: PersonalRecordConflict, keepLocal: Bool) throws {
        guard let id = userId, pausedContext == nil else { throw CancellationError() }
        var state = account(id)
        guard let index = state.outbox.firstIndex(where: { $0.mutationId == conflict.id }) else { return }
        let old = state.outbox.remove(at: index), recordKey = key(old.libraryId, old.recordKey)
        let hash = state.queuedDigests.removeValue(forKey: old.mutationId)
        if keepLocal, var local = old.envelope {
            let deleted = conflict.remote?.deleted == true
            if deleted {
                // A cloud tombstone is immutable. Keeping this version creates a new record.
                local.recordKey = UUID().uuidString; local.id = nil; local.revision = nil; local.deleted = nil
                try identity.registerRecord(local.recordKey)
            } else if let remote = conflict.remote {
                local.nativePayload = remote.nativePayload.merging(local.nativePayload, uniquingKeysWith: { _, new in new })
                local.summary = remote.summary.merging(local.summary, uniquingKeysWith: { _, new in new })
            }
            let mutation = PersonalRecordMutation(operation: "upsert", libraryId: local.libraryId, recordKey: local.recordKey,
                expectedRevision: deleted ? 0 : (conflict.remote?.revision ?? 0), envelope: local)
            state.outbox.append(mutation)
            if !deleted, let hash { state.queuedDigests[mutation.mutationId] = hash }
            if deleted { state.cloudChoices = (state.cloudChoices ?? [:]).merging([recordKey: hash ?? "accepted"], uniquingKeysWith: { _, new in new }) }
        } else {
            // Keep the native file as an offline backup, but show the chosen cloud version.
            state.cloudChoices = (state.cloudChoices ?? [:]).merging([recordKey: hash ?? "accepted"], uniquingKeysWith: { _, new in new })
            if let remote = conflict.remote { state.records[recordKey] = remote }
            state.digests[recordKey] = hash
            state.localRevisions[recordKey] = conflict.remote?.revision ?? 0
        }
        state.conflicts?.removeValue(forKey: conflict.id)
        persisted.accounts[id] = state; try persist()
        remoteRecords = Array(state.records.values).filter { $0.deleted != true }
        schedule()
    }
    func isLocallyDeleted(libraryId: String, recordKey: String) -> Bool {
        guard let id = userId ?? identity.state.activeAccountId else { return false }
        let state = account(id), record = key(libraryId, recordKey)
        return outboxIndex(for: id, state: state).deleted.contains(record) || state.records[record]?.deleted == true
    }

    func enqueueIdentity(accountId: String?, operation: String, alias: ParticipantAlias, visible: Bool? = nil) {
        guard let id = accountId, identity.state.activeAccountId == id else { return }
        if persisted.accounts[id] == nil { persisted.accounts[id] = AccountState() }
        persisted.accounts[id]?.identityOutbox.append(.init(expectedRevision: -1, operation: operation, aliasId: alias.id, name: alias.name, nameType: "PLAYER", visibleInPicker: visible))
        do { try persist(); schedule() } catch { reportFailure(error) }
    }

    func sessionDidAuthenticate(userId id: String) async {
        guard pausedContext == nil, currentAccountID() == id, !Task.isCancelled else { return }
        generation &+= 1; task?.cancel(); userId = id
        let epoch = generation, revision = await client.authSessionRevision()
        guard generation == epoch, currentAccountID() == id, pausedContext == nil, !Task.isCancelled else { return }
        authRevision = revision
        do {
            if let pending = persisted.pendingLink {
                if pending.masterId == id {
                    try reconcileAccountLink(masterId: id, sourceId: pending.sourceId, mode: pending.mode)
                    persisted.pendingLink = nil; try await persistInBackground()
                } else if pending.sourceId == id {
                    phase = "partial"; lastError = identityText("link_recovery_pending", "账号处理已完成，请重新登录保留的账号以继续同步")
                    return
                }
            }
            let scores = await asyncScoreRecords(), timers = await asyncTimerRecords()
            try check(id, epoch)
            try identity.migrateLegacyIfNeeded(scoreIDs: scores.map(\.id), timerIDs: timers.map(\.id))
            for guest in identity.unownedLedgers where persisted.guestIntentOwners[guest.libraryId] == nil {
                persisted.guestIntentOwners[guest.libraryId] = id
            }
            for (library, owner) in persisted.guestIntentOwners where owner == id {
                try identity.pinPendingGuest(libraryId: library, accountId: id)
            }
            try await persistInBackground(); try identity.beginAccount(id)
            remoteRecords = Array(account(id).records.values).filter { $0.deleted != true }
            schedule()
        } catch is CancellationError { }
        catch { if generation == epoch, currentAccountID() == id { lastError = error.localizedDescription; phase = "failed" } }
    }

    func signedOut(explicit: Bool) {
        generation &+= 1; task?.cancel(); task = nil; userId = nil; pausedContext = nil
        remoteRecords = explicit ? [] : identity.state.activeAccountId.map { Array(account($0).records.values).filter { $0.deleted != true } } ?? []
        phase = "local"
        if explicit { try? identity.beginNewGuest() }
    }

    func clearLocalCache() throws {
        generation &+= 1; task?.cancel(); task = nil; pausedContext = nil
        persisted = Persisted(); remoteRecords = []; phase = "local"; lastError = nil
        try persist()
        if FileManager.default.fileExists(atPath: audioCacheURL.path) { try FileManager.default.removeItem(at: audioCacheURL) }
    }

    func synchronizeNow() async {
        task?.cancel(); task = nil
        await run(epoch: generation)
    }

    func schedule() {
        guard userId != nil, pausedContext == nil else { return }
        task?.cancel()
        let epoch = generation
        let delay = max(0.4, userId.flatMap { account($0).retryNotBefore }?.timeIntervalSinceNow ?? 0)
        task = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(min(delay, 86400))); try Task.checkCancellation() } catch { return }
            await self?.run(epoch: epoch)
        }
    }

    func pauseForAccountLink(context: WechatBindingSessionContext) throws {
        guard userId == nil || userId == context.accountID else { throw CancellationError() }
        pausedContext = context; generation &+= 1; task?.cancel(); task = nil
        for guest in identity.unownedLedgers where persisted.guestIntentOwners[guest.libraryId] == nil {
            persisted.guestIntentOwners[guest.libraryId] = context.accountID
        }
        do { try captureLocalRecords(accountId: context.accountID); try persist() }
        catch { reportFailure(error) }
    }

    func cancelAccountLink(context: WechatBindingSessionContext) async {
        guard pausedContext == context else { return }
        pausedContext = nil
        guard currentAccountID() == context.accountID,
              await client.authSessionRevision() == context.authRevision else { return }
        await sessionDidAuthenticate(userId: context.accountID)
    }

    func completeAccountLink(masterId: String, sourceId: String?, mode: String, context: WechatBindingSessionContext) async throws {
        guard pausedContext == context else { return }
        generation &+= 1; task?.cancel()
        try reconcileAccountLink(masterId: masterId, sourceId: sourceId, mode: mode)
        persisted.pendingLink = nil; try await persistInBackground(); pausedContext = nil; userId = masterId
        // A failed new-domain pull cannot turn an already committed binding into a failure.
        await sessionDidAuthenticate(userId: masterId)
    }

    func stageAccountLinkResult(_ result: AccountLinkResponse.Merge) {
        persisted.pendingLink = .init(masterId: result.masterUserId, sourceId: result.sourceUserId, mode: result.mode.rawValue)
        do { try persist() } catch { reportFailure(error) }
    }

    private func reconcileAccountLink(masterId: String, sourceId: String?, mode: String) throws {
        if let sourceId, sourceId != masterId, var source = persisted.accounts[sourceId] {
            if mode == "merge" {
                var master = account(masterId)
                let recordIds = Set(master.outbox.map(\.mutationId)), identityIds = Set(master.identityOutbox.map(\.mutationId))
                master.outbox += source.outbox.filter { !recordIds.contains($0.mutationId) }
                master.identityOutbox += source.identityOutbox.filter { !identityIds.contains($0.mutationId) }
                for (key, value) in source.records where master.records[key] == nil { master.records[key] = value }
                for (key, value) in source.digests where master.digests[key] == nil { master.digests[key] = value }
                for (key, value) in source.localRevisions where master.localRevisions[key] == nil { master.localRevisions[key] = value }
                for (key, value) in source.queuedDigests where master.queuedDigests[key] == nil { master.queuedDigests[key] = value }
                for (key, value) in source.assetIds where master.assetIds[key] == nil { master.assetIds[key] = value }
                if let failures = source.blockedMutations {
                    master.blockedMutations = (master.blockedMutations ?? [:]).merging(failures, uniquingKeysWith: { old, _ in old })
                }
                master.readyAssets.formUnion(source.readyAssets)
                master.uploadedClaims.formUnion(source.uploadedClaims)
                master.cursor = nil; persisted.accounts[masterId] = master
            }
            source.archived = true; persisted.accounts[sourceId] = source
        }
        if let sourceId, sourceId != masterId {
            let intended = Set(persisted.guestIntentOwners.filter { $0.value == sourceId }.map(\.key))
            if mode == "merge" { for library in intended { persisted.guestIntentOwners[library] = masterId } }
            else { try identity.archive(libraryIds: intended) }
        }
        try identity.completeAccountLink(masterId: masterId, sourceId: sourceId, mode: mode)
        if persisted.accounts[masterId] != nil { persisted.accounts[masterId]?.cursor = nil }
        try persist()
    }

    func markDeleted(recordKey: String, libraryId: String? = nil) {
        markDeleted(records: [(recordKey, libraryId ?? identity.libraryId(for: recordKey))])
    }

    /// One durable write for a multi-selection or clear action. A later native
    /// manager callback for an already queued tombstone is an idempotent no-op.
    func markDeleted(records: [(recordKey: String, libraryId: String)]) {
        guard let id = userId ?? identity.state.activeAccountId else { return }
        var value = account(id)
        let queuedDeletes = Set(value.outbox.filter { $0.operation == "delete" }.map { key($0.libraryId, $0.recordKey) })
        var requests: [String: (recordKey: String, libraryId: String)] = [:]
        let readableLibraries = identity.readableLibraryIds
        for record in records where readableLibraries.contains(record.libraryId) {
            let recordKey = key(record.libraryId, record.recordKey)
            if !queuedDeletes.contains(recordKey) { requests[recordKey] = record }
        }
        guard !requests.isEmpty else { return }
        for mutation in value.outbox where requests[key(mutation.libraryId, mutation.recordKey)] != nil {
            value.queuedDigests.removeValue(forKey: mutation.mutationId)
            value.blockedMutations?.removeValue(forKey: mutation.mutationId)
            value.conflicts?.removeValue(forKey: mutation.mutationId)
        }
        value.outbox.removeAll { requests[key($0.libraryId, $0.recordKey)] != nil }
        for (cacheKey, record) in requests {
            value.outbox.append(.init(operation: "delete", libraryId: record.libraryId, recordKey: record.recordKey,
                                      expectedRevision: value.records[cacheKey]?.revision ?? 0))
            value.records[cacheKey]?.deleted = true
        }
        persisted.accounts[id] = value
        remoteRecords.removeAll { requests[key($0.libraryId, $0.recordKey)] != nil }
        do { try persist(); schedule() } catch { lastError = error.localizedDescription }
    }

    private func captureLocalRecords(accountId: String) throws {
        try identity.migrateLegacyIfNeeded(scoreIDs: scoreRecords().map(\.id),
                                          timerIDs: timerRecords().map(\.id))
        var value = account(accountId)
        let scoreRecords = scoreRecords().filter { identity.canRead(recordKey: $0.id) }
        let timerRecords = timerRecords().filter { identity.canRead(recordKey: $0.id) }
        for record in scoreRecords {
            try capture(PersonalRecordAdapter.envelope(record, identity: identity), in: &value)
        }
        for record in timerRecords {
            try capture(PersonalRecordAdapter.envelope(record, identity: identity), in: &value)
        }
        persisted.accounts[accountId] = value; try persist()
    }

    private func capture(_ original: PersonalRecordEnvelope, in value: inout AccountState, hash: String? = nil) throws {
        var envelope = original
        guard value.blockedAdoptions?[envelope.libraryId] == nil else { return }
        let recordKey = key(envelope.libraryId, envelope.recordKey)
        let localHash = try hash ?? Self.digest(envelope)
        if let pending = value.outbox.first(where: { $0.libraryId == envelope.libraryId && $0.recordKey == envelope.recordKey }) {
            guard value.blockedMutations?[pending.mutationId] != nil,
                  value.queuedDigests[pending.mutationId] != localHash else { return }
            value.outbox.removeAll { $0.mutationId == pending.mutationId }
            value.queuedDigests.removeValue(forKey: pending.mutationId)
            value.blockedMutations?.removeValue(forKey: pending.mutationId)
        }
        if let chosen = value.cloudChoices?[recordKey] {
            if chosen == localHash || chosen == "accepted" { return }
            value.cloudChoices?.removeValue(forKey: recordKey)
        }
        guard value.digests[recordKey] != localHash else { return }
        let hasLocalVoice: Bool
        if case .object = envelope.nativePayload["voiceNote"] { hasLocalVoice = true } else { hasLocalVoice = false }
        if let prior = value.records[recordKey] {
            // Preserve fields unknown to this app version when editing a native record.
            envelope.nativePayload = prior.nativePayload.merging(envelope.nativePayload, uniquingKeysWith: { _, new in new })
            envelope.summary = prior.summary.merging(envelope.summary, uniquingKeysWith: { _, new in new })
            envelope.assetIds = hasLocalVoice ? prior.assetIds : []
        }
        let mutation = PersonalRecordMutation(operation: "upsert", libraryId: envelope.libraryId, recordKey: envelope.recordKey,
            expectedRevision: value.localRevisions[recordKey] ?? 0, envelope: envelope)
        value.outbox.append(mutation); value.queuedDigests[mutation.mutationId] = localHash
    }

    private func captureLocalRecordsInBackground(accountId id: String, epoch: UInt64) async throws {
        let scores = await asyncScoreRecords(), timers = await asyncTimerRecords()
        try check(id, epoch)
        try identity.migrateLegacyIfNeeded(scoreIDs: scores.map(\.id), timerIDs: timers.map(\.id))
        // Encode one record at a time, yielding between records, instead of keeping
        // native snapshots plus two complete arrays of envelopes in memory.
        for record in scores where identity.canRead(recordKey: record.id) {
            try check(id, epoch)
            let envelope = try PersonalRecordAdapter.envelope(record, identity: identity)
            let hash = try await Task.detached(priority: .utility) { try Self.digest(envelope) }.value
            try check(id, epoch)
            var state = account(id); try capture(envelope, in: &state, hash: hash); persisted.accounts[id] = state
            cachedOutboxIndex = nil
        }
        for record in timers where identity.canRead(recordKey: record.id) {
            try check(id, epoch)
            let envelope = try PersonalRecordAdapter.envelope(record, identity: identity)
            let hash = try await Task.detached(priority: .utility) { try Self.digest(envelope) }.value
            try check(id, epoch)
            var state = account(id); try capture(envelope, in: &state, hash: hash); persisted.accounts[id] = state
            cachedOutboxIndex = nil
        }
        try await persistInBackground()
    }

    nonisolated private static func digest(_ value: PersonalRecordEnvelope) throws -> String {
        var value = value; value.id = nil; value.revision = nil; value.updatedAt = nil; value.deleted = nil
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: try encoder.encode(value)).map { String(format: "%02x", $0) }.joined()
    }

    private func adoptGuest(_ guest: ParticipantIdentityLedger, id: String, epoch: UInt64, revision: UInt64) async throws -> Adoption {
        for attempt in 0..<2 {
            do {
                try check(id, epoch)
                if persisted.accounts[id] == nil { persisted.accounts[id] = AccountState() }
                let prepare = account(id).adoptionSeeds?[guest.libraryId] ?? PrepareRequest(
                    mutationId: account(id).adoptionRequests[guest.libraryId] ?? UUID().uuidString,
                    guestPersonId: guest.person.id, guestLibraryId: guest.libraryId,
                    aliases: guest.aliases.filter { $0.state != .removed }.map { .init(id: $0.id, name: $0.name, visibleInPicker: $0.visibleInPicker) })
                if persisted.accounts[id]?.adoptionSeeds == nil { persisted.accounts[id]?.adoptionSeeds = [:] }
                persisted.accounts[id]?.adoptionSeeds?[guest.libraryId] = prepare; try await persistInBackground()
                let prepared: Adoption = try await client.request("/api/self-identity/adoptions/prepare", method: .post,
                    body: prepare, requiresAuth: true, expectedAuthRevision: revision)
                try check(id, epoch)
                let commit = account(id).commitSeeds?[guest.libraryId] ?? CommitRequest(
                    mutationId: account(id).adoptionCommits[guest.libraryId] ?? UUID().uuidString, adoptionId: prepared.adoptionId)
                if persisted.accounts[id]?.commitSeeds == nil { persisted.accounts[id]?.commitSeeds = [:] }
                persisted.accounts[id]?.commitSeeds?[guest.libraryId] = commit; try await persistInBackground()
                let completed: Adoption = try await client.request("/api/self-identity/adoptions/commit", method: .post,
                    body: commit, requiresAuth: true, expectedAuthRevision: revision)
                try check(id, epoch); return completed
            } catch let error as APIClientPrivateSyncError {
                try check(id, epoch)
                if error.code == "ADOPTION_EXPIRED", attempt == 0 {
                    persisted.accounts[id]?.adoptionSeeds?.removeValue(forKey: guest.libraryId)
                    persisted.accounts[id]?.commitSeeds?.removeValue(forKey: guest.libraryId)
                    persisted.accounts[id]?.adoptionRequests.removeValue(forKey: guest.libraryId)
                    persisted.accounts[id]?.adoptionCommits.removeValue(forKey: guest.libraryId)
                    try await persistInBackground(); continue
                }
                if error.status == 410, error.code == "MUTATION_RECEIPT_EXPIRED",
                   let proof = error.details?.outcome, proof.status == "applied", proof.operation == "adoption",
                   proof.userId == id, proof.guestPersonId == guest.person.id, proof.libraryId == guest.libraryId,
                   let adoptionId = proof.adoptionId, !adoptionId.isEmpty,
                   account(id).commitSeeds?[guest.libraryId].map({ $0.adoptionId == adoptionId }) ?? true {
                    let fresh: PersonalIdentitySnapshot = try await client.request("/api/self-identity", requiresAuth: true, expectedAuthRevision: revision)
                    try check(id, epoch)
                    return Adoption(adoptionId: adoptionId, guestPersonRef: .init(id: guest.person.id, kind: .guest),
                        accountPersonRef: fresh.personRef, libraryId: guest.libraryId, aliases: fresh.aliases,
                        needsAliasReview: fresh.aliases.contains { $0.state == .pending }, identity: fresh)
                }
                throw error
            } catch APIClientError.server(_, let code, _, _) where code == "ADOPTION_EXPIRED" && attempt == 0 {
                try check(id, epoch)
                persisted.accounts[id]?.adoptionSeeds?.removeValue(forKey: guest.libraryId)
                persisted.accounts[id]?.commitSeeds?.removeValue(forKey: guest.libraryId)
                persisted.accounts[id]?.adoptionRequests.removeValue(forKey: guest.libraryId)
                persisted.accounts[id]?.adoptionCommits.removeValue(forKey: guest.libraryId)
                try await persistInBackground()
            }
        }
        throw APIClientError.invalidResponse
    }

    private func run(epoch: UInt64) async {
        guard let id = userId else { return }
        do {
            try check(id, epoch)
            if let deadline = account(id).retryNotBefore, deadline > Date() { phase = "partial"; schedule(); return }
            persisted.accounts[id]?.retryNotBefore = nil
            phase = "syncing"; lastError = nil
            let revision = authRevision
            var snapshot: PersonalIdentitySnapshot
            do {
                snapshot = try await client.request("/api/self-identity", requiresAuth: true, expectedAuthRevision: revision)
            } catch APIClientError.server(let status, _, _, _) where status == 404 {
                try check(id, epoch); phase = "local"; return
            }
            try check(id, epoch)
            guard snapshot.capabilities.privateRecordsV1 else { phase = "local"; return }
            for guest in identity.unownedLedgers where persisted.guestIntentOwners[guest.libraryId] == id && account(id).blockedAdoptions?[guest.libraryId] == nil {
                do {
                    let completed = try await adoptGuest(guest, id: id, epoch: epoch, revision: revision)
                    try identity.adopt(libraryId: guest.libraryId, accountId: id, person: completed.accountPersonRef)
                    if let identity = completed.identity { snapshot = identity }
                } catch let error as APIClientPrivateSyncError where error.status == 410 || error.status == 413 {
                    try check(id, epoch)
                    var pending = account(id)
                    pending.blockedAdoptions = (pending.blockedAdoptions ?? [:]).merging([guest.libraryId: error.code ?? "MUTATION_RECEIPT_EXPIRED"], uniquingKeysWith: { _, new in new })
                    persisted.accounts[id] = pending
                    try await persistInBackground()
                    lastError = identityText("sync_conflict", "部分记录需要处理同步冲突")
                }
            }
            var rebases = 0
            while var operation = account(id).identityOutbox.first {
                try check(id, epoch)
                if operation.expectedRevision < 0 {
                    let alias = snapshot.aliases.first { $0.id == operation.aliasId || $0.normalizedName == operation.name.map(ParticipantIdentityRules.normalizedName) }
                    if let alias { operation.aliasId = alias.id }
                    if operation.operation == "activateAlias", alias == nil { operation.operation = "linkAlias" }
                    if (operation.operation == "removeAlias" && (alias == nil || alias?.state == .removed))
                        || (operation.operation == "activateAlias" && alias?.state == .active)
                        || (operation.operation == "linkAlias" && alias?.state == .active)
                        || (operation.operation == "linkClaims" && alias?.state == .removed) {
                        persisted.accounts[id]?.identityOutbox.removeFirst(); try await persistInBackground(); continue
                    }
                    operation.expectedRevision = snapshot.person.revision
                    persisted.accounts[id]?.identityOutbox[0] = operation; try await persistInBackground()
                }
                do {
                    snapshot = try await client.request("/api/self-identity/mutations", method: .post, body: operation,
                        requiresAuth: true, expectedAuthRevision: revision)
                } catch let error as APIClientPrivateSyncError where (error.status == 410 && error.code == "MUTATION_RECEIPT_EXPIRED") || error.status == 413 {
                    try check(id, epoch)
                    let proof = error.details?.outcome
                    if error.code == "MUTATION_RECEIPT_EXPIRED", proof?.status == "applied", proof?.mutationId == operation.mutationId, proof?.operation == operation.operation {
                        if let claims = operation.claims { persisted.accounts[id]?.uploadedClaims.formUnion(claims.map(\.id)) }
                    } else {
                        var pending = account(id)
                        pending.pendingIdentityMutations = (pending.pendingIdentityMutations ?? []) + [operation]
                        persisted.accounts[id] = pending
                        lastError = identityText("sync_conflict", "部分记录需要处理同步冲突")
                    }
                    persisted.accounts[id]?.identityOutbox.removeAll { $0.mutationId == operation.mutationId }
                    try await persistInBackground()
                    snapshot = try await client.request("/api/self-identity", requiresAuth: true, expectedAuthRevision: revision)
                    try check(id, epoch); continue
                } catch APIClientError.server(_, let code, _, _) where code == "REVISION_CONFLICT" && rebases < 3 {
                    // A definite rejection may be rebased. Unknown network outcomes replay
                    // the exact persisted request ID and body on the next run.
                    rebases += 1
                    snapshot = try await client.request("/api/self-identity", requiresAuth: true, expectedAuthRevision: revision)
                    try check(id, epoch)
                    operation.mutationId = UUID().uuidString; operation.expectedRevision = -1
                    persisted.accounts[id]?.identityOutbox[0] = operation; try await persistInBackground(); continue
                } catch APIClientError.server(_, let code, _, _) where code == "ALIAS_LIMIT_REACHED" {
                    try check(id, epoch)
                    try identity.markAliasPending(id: operation.aliasId)
                    persisted.accounts[id]?.identityOutbox.removeAll { $0.mutationId == operation.mutationId }; try await persistInBackground()
                    lastError = identityText("aliases_need_review", "已有 3 个关联名称，新增名称已保留为待整理")
                    continue
                }
                try check(id, epoch)
                persisted.accounts[id]?.identityOutbox.removeAll { $0.mutationId == operation.mutationId }
                if let claims = operation.claims { persisted.accounts[id]?.uploadedClaims.formUnion(claims.map(\.id)) }
                try await persistInBackground()
            }
            // Re-read the queue after every suspension: edits made while a request
            // is in flight must not be replaced by its older snapshot.
            try check(id, epoch)
            if account(id).identityOutbox.isEmpty && account(id).blockedAdoptions?[identity.ledger.libraryId] == nil {
                try identity.install(person: snapshot.personRef, aliases: snapshot.aliases, revision: snapshot.person.revision)
            }
            try check(id, epoch)
            try await captureLocalRecordsInBackground(accountId: id, epoch: epoch)
            try await pull(id: id, epoch: epoch, authRevision: revision)
            while account(id).outbox.contains(where: { account(id).conflicts?[$0.mutationId] == nil && account(id).blockedMutations?[$0.mutationId] == nil }) {
                try check(id, epoch); try Task.checkCancellation()
                let queuedState = account(id)
                let candidates = Array(queuedState.outbox.lazy.filter {
                    queuedState.conflicts?[$0.mutationId] == nil && queuedState.blockedMutations?[$0.mutationId] == nil
                }.prefix(max(1, min(50, queuedState.pushBatchLimit ?? 50))))
                let sizes = try await Task.detached(priority: .utility) {
                    try candidates.map { try JSONEncoder().encode($0).count }
                }.value
                try check(id, epoch)
                var batch: [PersonalRecordMutation] = [], bytes = 16 // {"mutations":[]}
                var anchors: Set<String> = []
                for (mutation, size) in zip(candidates, sizes) {
                    // Local edits/deletes may have replaced a candidate while encoding.
                    guard account(id).outbox.contains(where: { $0.mutationId == mutation.mutationId }) else { continue }
                    if size + 16 > 2560 * 1024 {
                        var updated = account(id)
                        var failures = updated.blockedMutations ?? [:]
                        failures[mutation.mutationId] = "RECORD_TOO_LARGE"
                        updated.blockedMutations = failures
                        persisted.accounts[id] = updated
                        lastError = identityText("sync_record_too_large", "部分记录过大，已保存在本机；其他记录会继续同步。")
                        continue
                    }
                    let anchor = key(mutation.libraryId, mutation.recordKey)
                    if anchors.contains(anchor) { break }
                    if !batch.isEmpty && bytes + size + 1 > 3 * 1024 * 1024 - 4096 { break }
                    anchors.insert(anchor); batch.append(mutation); bytes += size + 1
                }
                try await persistInBackground(); try check(id, epoch)
                if batch.isEmpty { continue }
                let response: PushResponse
                do {
                    response = try await client.request("/api/private-records/sync/push", method: .post,
                        body: PushRequest(mutations: batch), requiresAuth: true, expectedAuthRevision: revision)
                } catch let error as APIClientPrivateSyncError where error.status == 413 && batch.count == 1 {
                    try check(id, epoch)
                    var rejected = account(id)
                    rejected.blockedMutations = (rejected.blockedMutations ?? [:]).merging(
                        [batch[0].mutationId: error.code ?? "RECORD_TOO_LARGE"], uniquingKeysWith: { _, new in new })
                    persisted.accounts[id] = rejected
                    try await persistInBackground(); lastError = identityText("sync_record_too_large", "部分记录过大，已保存在本机；其他记录会继续同步。")
                    continue
                }
                try check(id, epoch)
                guard Set(response.results.map(\.mutationId)) == Set(batch.map(\.mutationId)) else { throw APIClientError.invalidResponse }
                var state = account(id)
                var retryDelay: Double?
                for result in response.results {
                    guard let mutation = batch.first(where: { $0.mutationId == result.mutationId }) else { continue }
                    let proof = result.outcome
                    let acknowledged = result.error == "MUTATION_RECEIPT_EXPIRED"
                        && proof?.status == "applied" && proof?.mutationId == mutation.mutationId
                        && proof?.operation == mutation.operation && proof?.libraryId == mutation.libraryId
                        && proof?.recordKey == mutation.recordKey && (proof?.appliedRevision ?? 0) > mutation.expectedRevision
                    if result.status == "applied" || acknowledged {
                        state.outbox.removeAll { $0.mutationId == result.mutationId }
                        state.blockedMutations?.removeValue(forKey: result.mutationId)
                        if let record = result.record {
                            let cacheKey = key(record.libraryId, record.recordKey)
                            if (state.records[cacheKey]?.revision ?? 0) <= (record.revision ?? 0) { state.records[cacheKey] = record }
                        }
                        let localKey = key(mutation.libraryId, mutation.recordKey)
                        if let hash = state.queuedDigests.removeValue(forKey: mutation.mutationId) {
                            state.digests[localKey] = hash
                            state.localRevisions[localKey] = result.record?.revision ?? proof?.appliedRevision ?? mutation.expectedRevision + 1
                        } else if state.localRevisions[localKey] == mutation.expectedRevision {
                            state.localRevisions[localKey] = result.record?.revision ?? proof?.appliedRevision ?? mutation.expectedRevision + 1
                        }
                    } else if result.retryable == true || (result.retryable != false && result.splitBatch == true && batch.count > 1) {
                        retryDelay = max(retryDelay ?? 1, min(max(result.retryAfterSeconds ?? 60, 1), 86400))
                        if result.splitBatch == true { state.pushBatchLimit = max(1, batch.count / 2) }
                    } else {
                        lastError = identityText("sync_conflict", "部分记录需要处理同步冲突")
                        if result.status == "conflict" || result.error == "RECORD_DELETED" {
                            if state.conflicts == nil { state.conflicts = [:] }
                            state.conflicts?[mutation.mutationId] = .init(id: mutation.mutationId, local: mutation.envelope, remote: result.record, operation: mutation.operation)
                        } else {
                            state.blockedMutations = (state.blockedMutations ?? [:]).merging(
                                [mutation.mutationId: result.error ?? "RECORD_REJECTED"], uniquingKeysWith: { _, new in new })
                            lastError = identityText("sync_record_rejected", "部分记录暂时无法上传，已保存在本机。可修改后重试同步。")
                        }
                    }
                }
                if let retryDelay { state.retryNotBefore = Date().addingTimeInterval(retryDelay) }
                persisted.accounts[id] = state; try await persistInBackground()
                if retryDelay != nil {
                    try await pull(id: id, epoch: epoch, authRevision: revision)
                    phase = "partial"; schedule(); return
                }
                // Conflicts/rejections are isolated; later records still make progress.
                try check(id, epoch)
            }
            try await syncClaims(snapshot: snapshot, id: id, epoch: epoch, authRevision: revision)
            if snapshot.capabilities.privateRecordAudioV1 { try await syncAudio(id: id, epoch: epoch, authRevision: revision) }
            try await pull(id: id, epoch: epoch, authRevision: revision)
            if lastError == nil, let failures = account(id).blockedMutations, !failures.isEmpty {
                lastError = failures.values.contains("RECORD_TOO_LARGE")
                    ? identityText("sync_record_too_large", "部分记录过大，已保存在本机；其他记录会继续同步。")
                    : identityText("sync_record_rejected", "部分记录暂时无法上传，已保存在本机。可修改后重试同步。")
            }
            if !(account(id).pendingIdentityMutations ?? []).isEmpty || !(account(id).blockedAdoptions ?? [:]).isEmpty || !(account(id).blockedAssets ?? [:]).isEmpty {
                lastError = identityText("sync_conflict", "部分记录需要处理同步冲突")
            }
            phase = account(id).outbox.isEmpty && lastError == nil ? "synced" : "partial"
            if account(id).outbox.contains(where: { account(id).conflicts?[$0.mutationId] == nil && account(id).blockedMutations?[$0.mutationId] == nil }) && lastError == nil { schedule() }
        } catch is CancellationError { }
        catch let error as APIClientPrivateSyncError {
            guard generation == epoch, currentAccountID() == id else { return }
            let splits = error.path == "/api/private-records/sync/push" && (error.details?.splitBatch == true || error.status == 413)
            let retryable = error.status == 429 || error.status == 503 || (splits && (account(id).pushBatchLimit ?? 50) > 1)
            if retryable {
                var waiting = account(id)
                if splits { waiting.pushBatchLimit = max(1, (waiting.pushBatchLimit ?? 50) / 2) }
                waiting.retryNotBefore = Date().addingTimeInterval(min(max(error.details?.retryAfterSeconds ?? 60, 1), 86400))
                persisted.accounts[id] = waiting
                do { try await persistInBackground(); try check(id, epoch); phase = "partial"; schedule() }
                catch { if generation == epoch { reportFailure(error) } }
            } else { phase = "partial"; lastError = error.localizedDescription }
        }
        catch { if generation == epoch { phase = "failed"; lastError = error.localizedDescription } }
    }

    private func syncClaims(snapshot: PersonalIdentitySnapshot, id: String, epoch: UInt64, authRevision: UInt64) async throws {
        var snapshot = snapshot
        let pendingClaims = Set((account(id).pendingIdentityMutations ?? []).flatMap { ($0.claims ?? []).map(\.id) })
        for ledger in identity.state.ledgers.values where ledger.ownerAccountId == id && account(id).blockedAdoptions?[ledger.libraryId] == nil {
            for alias in ledger.aliases where alias.state != .removed {
                guard let serverAlias = snapshot.aliases.first(where: { $0.normalizedName == alias.normalizedName && $0.state != .removed }) else { continue }
                let claims = ledger.claims.filter { $0.aliasId == alias.id && !$0.revoked && !account(id).uploadedClaims.contains($0.id) && !pendingClaims.contains($0.id)
                    && account(id).records[key($0.libraryId, $0.recordKey)]?.deleted == false }
                guard !claims.isEmpty else { continue }
                try check(id, epoch)
                for offset in stride(from: 0, to: claims.count, by: 2000) {
                    let batch = Array(claims[offset..<min(offset + 2000, claims.count)])
                    let operation = PersonalIdentityMutation(expectedRevision: snapshot.person.revision, operation: "linkClaims", aliasId: serverAlias.id, claims: batch.map(PersonalHistoricalClaimInput.init))
                    persisted.accounts[id]?.identityOutbox.append(operation); try await persistInBackground()
                    snapshot = try await client.request("/api/self-identity/mutations", method: .post,
                        body: operation,
                        requiresAuth: true, expectedAuthRevision: authRevision)
                    try check(id, epoch)
                    persisted.accounts[id]?.identityOutbox.removeAll { $0.mutationId == operation.mutationId }
                    persisted.accounts[id]?.uploadedClaims.formUnion(batch.map(\.id)); try await persistInBackground()
                }
            }
        }
        var cursor: String?
        repeat {
            let response: ClaimsResponse = try await client.request("/api/self-identity/claims", query: cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [],
                requiresAuth: true, expectedAuthRevision: authRevision)
            try check(id, epoch); try identity.installClaims(response.claims); cursor = response.nextCursor
        } while cursor != nil
    }

    private func pull(id: String, epoch: UInt64, authRevision: UInt64) async throws {
        var hasMore = true
        while hasMore {
            try check(id, epoch)
            let response: PullResponse
            do {
                response = try await client.request("/api/private-records/sync/pull",
                    query: account(id).cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [],
                    requiresAuth: true, expectedAuthRevision: authRevision)
            } catch APIClientError.server(_, let code, _, _) where code == "SYNC_RESET_REQUIRED" {
                persisted.accounts[id]?.cursor = nil; try await persistInBackground(); continue
            }
            try check(id, epoch)
            if persisted.accounts[id] == nil { persisted.accounts[id] = AccountState() }
            for record in response.records {
                let cacheKey = key(record.libraryId, record.recordKey), previous = account(id).records[cacheKey]
                if previous?.deleted != true && (previous?.revision ?? 0) <= (record.revision ?? 0) {
                    persisted.accounts[id]?.records[cacheKey] = record
                }
                try identity.recordReceived(key: record.recordKey, libraryId: record.libraryId)
            }
            persisted.accounts[id]?.cursor = response.nextCursor; try await persistInBackground(); hasMore = response.hasMore
        }
        remoteRecords = Array(account(id).records.values).filter { $0.deleted != true }
    }

    func query(scope: String, kind: String?, project: String?, projects: [String]? = nil, from: Int64?, to: Int64?, search: String) async throws -> [PersonalRecordEnvelope] {
        guard let id = userId, pausedContext == nil else { throw APIClientError.unauthorized }
        let epoch = generation
        var cursor: String?; var records: [PersonalRecordEnvelope] = []
        repeat {
            var query = [URLQueryItem(name: "scope", value: scope), URLQueryItem(name: "limit", value: "100")]
            if let projects, !projects.isEmpty { query.append(.init(name: "projects", value: projects.joined(separator: ","))) }
            for (name, value) in [("kind", kind), ("project", project), ("from", from.map(String.init)), ("to", to.map(String.init)), ("q", search.isEmpty ? nil : search), ("cursor", cursor)] {
                if let value { query.append(.init(name: name, value: value)) }
            }
            let response: QueryResponse = try await client.request("/api/private-records", query: query, requiresAuth: true, expectedAuthRevision: authRevision)
            try check(id, epoch)
            if persisted.accounts[id] == nil { persisted.accounts[id] = AccountState() }
            var page: [PersonalRecordEnvelope] = []
            for record in response.records {
                let cacheKey = key(record.libraryId, record.recordKey)
                let previous = account(id).records[cacheKey]
                if previous?.deleted != true && (previous?.revision ?? 0) <= (record.revision ?? 0) {
                    persisted.accounts[id]?.records[cacheKey] = record
                }
                try identity.recordReceived(key: record.recordKey, libraryId: record.libraryId)
                page.append(account(id).records[cacheKey] ?? record)
            }
            try await persistInBackground()
            remoteRecords = Array(account(id).records.values).filter { $0.deleted != true }
            records += page; cursor = response.nextCursor
        } while cursor != nil
        return records
    }

    private func syncAudio(id: String, epoch: UInt64, authRevision: UInt64) async throws {
        let scores = await asyncScoreRecords()
        try check(id, epoch)
        for record in scores where identity.canRead(recordKey: record.id) {
            guard let voice = record.voiceNote else { continue }
            let library = identity.libraryId(for: record.id), recordKey = key(library, record.id)
            guard let remote = account(id).records[recordKey], remote.deleted != true else { continue }
            let path = ScoreboardRecordManager.voiceNoteFileURL(voice.relativePath)
            guard let audio = try? await Task.detached(priority: .utility, operation: {
                let bytes = try Data(contentsOf: path)
                return (bytes, SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
            }).value else { lastError = identityText("audio_missing", "部分语音文件缺失"); continue }
            try check(id, epoch)
            let (bytes, hash) = audio
            let assetKey = recordKey + ":" + hash
            let assetId = account(id).assetIds[assetKey] ?? UUID().uuidString
            if account(id).readyAssets.contains(assetId) || account(id).blockedAssets?[assetId] != nil { continue }
            persisted.accounts[id]?.assetIds[assetKey] = assetId; try await persistInBackground(); try check(id, epoch)
            let manifest = AssetRequest(mutationId: "manifest-" + assetId, assetId: assetId, libraryId: library, recordKey: record.id,
                sha256: hash, sizeBytes: bytes.count, contentType: "audio/mp4", durationMs: voice.durationMs)
            do {
                let response: AssetResponse
                do {
                    response = try await client.request("/api/private-record-assets", method: .post,
                        body: manifest, requiresAuth: true, expectedAuthRevision: authRevision)
                } catch let error as APIClientPrivateSyncError where error.status == 410 {
                    guard let recovered = try await recoverAssetReceipt(error, manifest: manifest, operation: "createAsset", id: id, epoch: epoch, authRevision: authRevision) else {
                        try await retainBlockedAsset(assetId, id: id, epoch: epoch, code: error.code); continue
                    }
                    response = recovered
                }
                try check(id, epoch)
                if response.status != "ready" {
                    _ = try await client.privateRecordAssetBytes(response.uploadUrl ?? "/api/private-record-assets/\(assetId)/content",
                        method: .put, data: bytes, contentType: "audio/mp4", expectedAuthRevision: authRevision)
                    try check(id, epoch)
                    do {
                        let _: AssetResponse = try await client.request("/api/private-record-assets/\(assetId)/complete", method: .post,
                            body: AssetComplete(mutationId: "complete-" + assetId), requiresAuth: true, expectedAuthRevision: authRevision)
                    } catch let error as APIClientPrivateSyncError where error.status == 410 {
                        guard try await recoverAssetReceipt(error, manifest: manifest, operation: "completeAsset", id: id, epoch: epoch, authRevision: authRevision) != nil else {
                            try await retainBlockedAsset(assetId, id: id, epoch: epoch, code: error.code); continue
                        }
                    }
                }
            } catch let error as APIClientPrivateSyncError where error.status == 413 {
                try await retainBlockedAsset(assetId, id: id, epoch: epoch, code: error.code); continue
            }
            try check(id, epoch)
            var envelope = remote; envelope.assetIds = [assetId]
            persisted.accounts[id]?.outbox.append(.init(operation: "upsert", libraryId: library, recordKey: record.id,
                expectedRevision: remote.revision ?? 0, envelope: envelope))
            persisted.accounts[id]?.readyAssets.insert(assetId); try await persistInBackground()
        }
    }

    private func retainBlockedAsset(_ assetId: String, id: String, epoch: UInt64, code: String?) async throws {
        try check(id, epoch)
        var pending = account(id)
        pending.blockedAssets = (pending.blockedAssets ?? [:]).merging(
            [assetId: code ?? "MUTATION_RECEIPT_EXPIRED"], uniquingKeysWith: { _, new in new })
        persisted.accounts[id] = pending
        try await persistInBackground()
        lastError = identityText("sync_conflict", "部分记录需要处理同步冲突")
    }

    private func recoverAssetReceipt(_ error: APIClientPrivateSyncError, manifest: AssetRequest, operation: String,
                                     id: String, epoch: UInt64, authRevision: UInt64) async throws -> AssetResponse? {
        let expectedMutation = operation == "createAsset" ? manifest.mutationId : "complete-" + manifest.assetId
        guard error.code == "MUTATION_RECEIPT_EXPIRED", let proof = error.details?.outcome,
              proof.status == "applied", proof.operation == operation, proof.mutationId == expectedMutation,
              proof.assetId == manifest.assetId, proof.libraryId == manifest.libraryId, proof.recordKey == manifest.recordKey else { return nil }
        let recovered: AssetResponse
        do {
            recovered = try await client.request("/api/private-record-assets/\(manifest.assetId)", requiresAuth: true, expectedAuthRevision: authRevision)
        } catch APIClientError.server(let status, _, _, _) where status == 404 { return nil }
        try check(id, epoch)
        guard recovered.assetId == manifest.assetId, recovered.libraryId == manifest.libraryId, recovered.recordKey == manifest.recordKey,
              recovered.sha256 == manifest.sha256, recovered.sizeBytes == manifest.sizeBytes,
              recovered.contentType == manifest.contentType, recovered.durationMs == manifest.durationMs,
              operation != "completeAsset" || recovered.status == "ready" else { return nil }
        return recovered
    }

    func downloadAudio(assetId: String) async throws -> URL {
        guard let id = userId else { throw CancellationError() }
        let epoch = generation
        let manifest: AssetResponse = try await client.request("/api/private-record-assets/\(assetId)",
            requiresAuth: true, expectedAuthRevision: authRevision)
        try check(id, epoch)
        guard manifest.status == "ready", let endpoint = manifest.downloadUrl else { throw APIClientError.invalidResponse }
        let data = try await client.privateRecordAssetBytes(endpoint, expectedAuthRevision: authRevision)
        try check(id, epoch)
        let root = audioCacheURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(SHA256.hash(data: Data(assetId.utf8)).map { String(format: "%02x", $0) }.joined() + ".m4a")
        try data.write(to: url, options: .atomic); return url
    }
}
