import Foundation
import LinkCore
import Observation
import RecordCore
import ScoreCore

struct LinkedSetupRequest: Equatable {
    let handle: LinkedMatchHandle
    let messageId: UUID
    let authorityEpoch: UInt64
    let setup: LinkedScoreboardSetup
    var peerSupportsCompressedFinish = false
    /// Capability intersection negotiated from the request envelope.
    var peerCapabilities: Set<LinkCapability> = []
    var peerSupportsSharedEditing = false

    var sessionId: UUID { handle.sessionId }
}
struct LinkedSnapshotUpdate: Equatable {
    let sessionId: UUID
    let revision: UInt64
    var matchGeneration: UInt64 = 1
    let snapshot: LinkedScoreboardSnapshot
    var detailedActions: [DetailedScoreAction]
    var removedActionIDs: Set<UUID> = []

    func beginsMatch(after previous: Self?) -> Bool {
        guard let previous, previous.sessionId == sessionId else { return false }
        return previous.matchGeneration < matchGeneration
    }
}

struct PendingWatchReclaimAcceptance: Equatable {
    let messageId: UUID
    let correlationId: UUID
    let sessionId: UUID
    let revision: UInt64
    let snapshot: LinkedScoreboardSnapshot
    let detailedActions: [DetailedScoreAction]
}

enum WatchPhoneLinkTestState: Equatable {
    case idle
    case testing
    case success
    case failed
}

enum WatchPhoneLinkTestFailure: Equatable {
    case inactive
    case unreachable
    case sendFailed
    case timedOut
}

enum WatchCommonNamesSyncRequestResult: Equatable {
    case requested
    case queuedUntilPhoneAvailable
    case connectionInactive
    case failed
}

struct WatchPhoneLinkProbeTracker: Equatable {
    static let timeoutSeconds: TimeInterval = 8
    private(set) var activeProbeID: UUID?

    mutating func start(_ probeID: UUID) {
        activeProbeID = probeID
    }

    mutating func accept(_ probeID: UUID) -> Bool {
        guard activeProbeID == probeID else { return false }
        activeProbeID = nil
        return true
    }

    mutating func accept(sessionID: UUID, probeID: UUID) -> Bool {
        guard sessionID == probeID else { return false }
        return accept(probeID)
    }

    mutating func timeout(_ probeID: UUID) -> Bool {
        accept(probeID)
    }

    mutating func cancel() {
        activeProbeID = nil
    }

    static func canStart(with status: WatchConnectivityStatus) -> Bool {
        status.isActivated && status.isReachable
    }
}

@MainActor
@Observable
final class WatchLinkService {
    /// Pending setup awaiting user confirm (does not auto-open).
    var pendingConfirmRequest: LinkedSetupRequest?
    /// After accept, active linked setup for scoreboard routing.
    var acceptedSetup: LinkedSetupRequest?
    var latestSnapshot: LinkedSnapshotUpdate?
    var sharedEditTracker = LinkSharedEditTracker()
    var simultaneousEditNotice: UUID?
    var controlRole: LinkControlRole?
    var phoneTookOver: Bool = false
    var pendingReclaimAcceptance: PendingWatchReclaimAcceptance?
    internal(set) var connectivityStatus: WatchConnectivityStatus
    internal(set) var phoneLinkTestState: WatchPhoneLinkTestState = .idle
    internal(set) var phoneLinkTestFailure: WatchPhoneLinkTestFailure?
    internal(set) var lastCommunicationAtEpochMilliseconds: Int64
    internal(set) var commonNamesSyncFailed = false
    internal(set) var lastLinkErrorMessage: String?

    let transport: any WatchLinkTransport
    let contextStore: any LinkDataStore
    let outboxStore: any LinkDataStore
    let clock: any LinkClock
    let recordSink: any WatchLinkRecordSink
    var revisionGate = LinkRevisionGate()
    var sequence: UInt64 = 0
    /// Authoritative linked-match and control lifecycle. The scalar fields
    /// below are projections used by existing Watch views and persistence.
    var sessionMachine: LinkSessionStateMachine?
    var pendingAck = LinkControlRetryQueue()
    var terminalOutbox = LinkDurableOutbox()
    var peerSupportsCompressedFinish = false
    /// Capability intersection agreed during the setup handshake; gates the
    /// new channels (file transfer, delta actions) until both sides declared.
    var negotiatedPeerCapabilities: Set<LinkCapability> = []
    var deltaActionTracker = LinkDeltaActionTracker()
    /// 对端帧送达的动作来源账本：本地权威替换时保留这些并发有效动作。
    var actionHistory = LinkSnapshotHistory()
    @ObservationIgnored var retiredRecordSessions: LinkRetiredRecordSessions

    var peerSupportsFileTransfer: Bool {
        negotiatedPeerCapabilities.contains(.fileTransfer)
    }

    var peerSupportsDeltaActions: Bool {
        negotiatedPeerCapabilities.contains(.deltaActions)
    }

    var activeRecordSession: LinkRecordSession? {
        guard let handle = activeHandle, let gameType = activeGameType,
              sessionMachine?.lifecycle != .starting else { return nil }
        return LinkRecordSession(
            handle: handle, gameType: gameType,
            authorityEpoch: authorityEpoch, completedMatchIds: publishedFinishedMatchIds,
            allowsPeerNextMatch: controlRole == .watchFollower || controlRole == .shared
        )
    }
    var publishedFinishedMatchIds: Set<UUID> = []
    var pendingReclaimRequestMessageId: UUID?
    var reclaimRequestTimeoutTask: Task<Void, Never>?
    var activeSessionId: UUID?
    var activeHandle: LinkedMatchHandle?
    var activeRevision: UInt64 = 0
    var authorityEpoch: UInt64 = 0
    var activeGameType: GameType?
    var activeSetup: LinkedScoreboardSetup?
    var mergedDetailedActions: [DetailedScoreAction] = []
    var ackRetryTask: Task<Void, Never>?
    let pendingWatchRecordsKey = "watch_pending_record_transfers_v1"
    var pendingWatchRecords: [WatchRecordTransferPayload] = []
    var lastQueuedCommonNameMutationIDs: [UUID] = []
    var probeTracker = WatchPhoneLinkProbeTracker()
    var probeTimeoutTask: Task<Void, Never>?
    let lastCommunicationAtKey = "watch_phone_link_last_communication_at_v1"
    let contextKey = "watch_link_context"
    let terminalOutboxKey = "watch_link_terminal_outbox"
    let pendingSessionEndsKey = "watch_link_pending_session_ends"
    var pendingSessionEnds: [LinkPendingSessionEnd] = []
    var pendingSessionEndInFlight: Set<UUID> = []

    init(
        transport: any WatchLinkTransport = WatchConnectivityTransport(),
        contextStore: any LinkDataStore = WatchStorageContainer.shared.linkDataStore,
        outboxStore: any LinkDataStore = WatchStorageContainer.shared.linkDataStore,
        clock: any LinkClock = SystemLinkClock(),
        recordSink: (any WatchLinkRecordSink)? = nil
    ) {
        self.transport = transport
        self.contextStore = contextStore
        retiredRecordSessions = LinkRetiredRecordSessions(store: contextStore)
        self.outboxStore = outboxStore
        self.clock = clock
        self.recordSink = recordSink ?? DefaultWatchLinkRecordSink()
        connectivityStatus = transport.status
        lastCommunicationAtEpochMilliseconds = Int64(
            WatchPreferences.shared.int(forKey: lastCommunicationAtKey)
        )
        if let data = outboxStore.data(forKey: terminalOutboxKey),
           let outbox = try? JSONDecoder().decode(LinkDurableOutbox.self, from: data) {
            terminalOutbox = outbox
        }
        if let data = outboxStore.data(forKey: pendingSessionEndsKey),
           let requests = try? JSONDecoder().decode([LinkPendingSessionEnd].self, from: data) {
            pendingSessionEnds = requests
        }
        restoreContext()
        if let data = outboxStore.data(forKey: pendingWatchRecordsKey),
           let payloads = try? JSONDecoder().decode([WatchRecordTransferPayload].self, from: data) {
            pendingWatchRecords = payloads
        }

        transport.onReceive = { [weak self] data in
            DispatchQueue.main.async {
                self?.receive(data)
            }
        }
        transport.onSendError = { [weak self] error in
            DispatchQueue.main.async {
                self?.lastLinkErrorMessage = error.localizedDescription
            }
        }
        transport.onApplicationContext = { [weak self] context in
            DispatchQueue.main.async {
                self?.handleApplicationContext(context)
            }
        }
        transport.onCommonNameMutationAckData = { [weak self] data in
            DispatchQueue.main.async {
                self?.handleCommonNameMutationAcknowledgement(data)
            }
        }
        transport.onReceivedFile = { [weak self] data, metadata in
            DispatchQueue.main.async {
                self?.handleReceivedFile(data, metadata: metadata)
            }
        }
        transport.onStatusChange = { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                let becameReachable = !self.connectivityStatus.isReachable && status.isReachable
                self.connectivityStatus = status
                guard status.isActivated else { return }
                self.flushPendingWatchRecords()
                self.flushPendingCommonNameMutations(force: false)
                if becameReachable { self.retryLiveSnapshotOnReconnect() }
                if status.isReachable {
                    self.requestCommonNamesSnapshot()
                }
            }
        }
        WatchRecordManager.shared.recordTransferHandler = { [weak self] payload in
            #if DEBUG
            print("[WatchLink] recordTransferHandler fired for \(payload.id)")
            #endif
            self?.transferFinishedRecord(payload)
        }
        transport.onCatchUpRequest = { [weak self] in
            DispatchQueue.main.async {
                self?.respondToCatchUpRequest()
            }
        }
        transport.onClearPendingRequest = { [weak self] ids in
            DispatchQueue.main.async {
                self?.clearPendingWatchRecords(ids: ids)
            }
        }
        transport.activate()
        connectivityStatus = transport.status
        scheduleRetryIfNeeded()
        if connectivityStatus.isActivated {
            handleApplicationContext(transport.receivedApplicationContext)
            flushPendingCommonNameMutations(force: false)
        }
        #if DEBUG
        print("[WatchLink] recordTransferHandler registered at WatchLinkService init")
        #endif
    }

    var isController: Bool {
        controlRole == .watchController
    }

    var canEditLinkedMatch: Bool {
        isController || controlRole == .shared
    }

    var incomingSnapshot: LinkedSnapshotUpdate? {
        guard let update = latestSnapshot,
              isFollower || (controlRole == .shared && LinkSharedRevision.writer(of: update.revision) == .phone)
        else { return nil }
        return update
    }

    var peerFinishedSharedMatch: Bool {
        controlRole == .shared && incomingSnapshot?.snapshot.isFinished == true
    }

    #if DEBUG
    var hasScheduledRetryForTesting: Bool { ackRetryTask != nil }
    #endif

    func clearLinkError() {
        lastLinkErrorMessage = nil
    }

    /// Watch side of the catch-up handshake: phone pulls queued records.
    /// Same pipeline as regular saves: full encode → channel by byte budget →
    /// ACK dequeue. Oversize frames route through the reliable file channel
    /// (no trimming); the ≤60KB fast-path batches are only an accelerant.
    func respondToCatchUpRequest() {
        for payload in pendingWatchRecords {
            deliverStandaloneRecord(payload)
        }
        let datas = pendingWatchRecords
            .compactMap { try? JSONEncoder().encode($0) }
            .filter { !$0.isEmpty && $0.count <= LinkFinishedRouting.realtimeBudgetBytes }
        #if DEBUG
        print("[WatchLink] respondToCatchUpRequest pending=\(pendingWatchRecords.count) fastPath=\(datas.count)")
        #endif
        guard !datas.isEmpty else { return }
        transport.sendPendingWatchRecords(datas)
    }

    /// Phone confirmed it ingested these ids; drop them from the local queue.
    func clearPendingWatchRecords(ids: [String]) {
        WatchRecordManager.shared.markSynced(ids: ids)
        #if DEBUG
        print("[WatchLink] clearPendingWatchRecords ids=\(ids)")
        #endif
        let set = Set(ids)
        let before = pendingWatchRecords.count
        pendingWatchRecords.removeAll { set.contains($0.id) }
        guard pendingWatchRecords.count != before else { return }
        persistPendingWatchRecords()
    }

}

@MainActor
protocol WatchLinkRecordSink {
    @discardableResult
    func ingest(
        payload: LinkMatchFinishedPayload,
        gameType: ScoreCore.GameType,
        matchId: UUID,
        syncState: WatchRecordSyncState
    ) -> String?

    func markSynced(recordId: String)
}

struct DefaultWatchLinkRecordSink: WatchLinkRecordSink {
    nonisolated init() {}

    @discardableResult
    func ingest(
        payload: LinkMatchFinishedPayload,
        gameType: ScoreCore.GameType,
        matchId: UUID,
        syncState: WatchRecordSyncState
    ) -> String? {
        WatchLinkedRecordIngestor.ingest(
            payload: payload,
            gameType: gameType,
            matchId: matchId,
            syncState: syncState
        )
    }

    func markSynced(recordId: String) {
        guard !recordId.isEmpty else { return }
        WatchRecordManager.shared.markSynced(ids: [recordId])
    }
}

/// Persists finished Watch↔Phone linked matches into the Watch local history store
/// without re-triggering standalone `transferToPhone` delivery.
enum WatchLinkedRecordIngestor {
    @MainActor
    @discardableResult
    static func ingest(
        payload: LinkMatchFinishedPayload,
        gameType: ScoreCore.GameType,
        matchId: UUID,
        syncState: WatchRecordSyncState
    ) -> String? {
        guard let record = makeRecord(
            payload: payload, gameType: gameType, matchId: matchId,
            source: syncState == .pending ? .linkedWatch : .linkedPhone
        ) else {
            return nil
        }
        guard WatchRecordManager.shared.saveRecord(record, transferToPhone: false) else { return nil }
        switch syncState {
        case .sent:
            WatchRecordManager.shared.markSynced(ids: [record.id])
        case .pending:
            WatchRecordManager.shared.setSyncState(.pending, for: record.id)
        }
        return record.id
    }

    @MainActor
    static func makeRecord(
        payload: LinkMatchFinishedPayload,
        gameType: ScoreCore.GameType,
        matchId: UUID,
        source: RecordSource = .linkedWatch
    ) -> WatchScoreboardRecord? {
        let recordId = payload.recordId.isEmpty ? "w_\(matchId.uuidString)" : payload.recordId
        let snapshot = payload.snapshot
        let training = snapshot.basketballTrainingState
        let canonical = MatchRecordProjector.canonicalRecord(
            id: recordId,
            kind: .sport(gameType),
            source: source,
            snapshot: snapshot,
            gameType: gameType,
            winnerSide: payload.winnerSide,
            startEpochMilliseconds: payload.startTimeEpochMilliseconds,
            endEpochMilliseconds: payload.endTimeEpochMilliseconds,
            durationSeconds: max(0, payload.durationSeconds),
            participantNames: participantNames(for: snapshot, announcedNames: payload.participantNames),
            detailedActions: training == nil ? payload.detailedActions : [],
            totalScoreChanges: training?.counts.attempts ?? max(0, payload.totalScoreChanges)
        )
        return WatchScoreboardRecord(canonical: canonical)
    }

    private static func participantNames(for snapshot: LinkedScoreboardSnapshot, announcedNames: [String]) -> [String] {
        let defaults: WatchParticipantNamePair
        switch snapshot {
        case .nineBall(let state):
            let format = NSLocalizedString("multi_score_player_default_format", value: "选手 %d", comment: "")
            return (0..<state.playerCount).map { index in
                state.resolvedName(at: index, fallback: String(format: format, index + 1))
            }
        case .eightBall:
            defaults = WatchDefaultTeamNames.resolve(for: .eightBall)
        case .snooker:
            defaults = WatchDefaultTeamNames.resolve(for: .snooker)
        default:
            return announcedNames
        }
        return [defaults.left, defaults.right].enumerated().map { index, fallback in
            guard announcedNames.indices.contains(index) else { return fallback }
            let name = announcedNames[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? fallback : name
        }
    }
}
