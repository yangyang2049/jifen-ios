import Foundation
import LinkCore
import LinkSync
import Observation
import RecordCore
import ScoreCore

struct LinkedSetupRequest: Equatable {
    let handle: LinkedMatchHandle
    let messageId: UUID
    let setup: LinkedScoreboardSetup
    var senderEpochMilliseconds: Int64 = 0
    /// Capability intersection negotiated from the request envelope.
    var peerCapabilities: Set<LinkCapability> = []

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
    /// 联动会话恒为 `.shared`：两端都能计分，不再有主控/跟随角色。
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
    let intentStore: FileLinkDataStore
    @ObservationIgnored lazy var intentSessionEngine: LinkSessionEngine = {
        let transport = self.transport
        return LinkSessionEngine(localPeer: .watch, transport: transport, clock: clock) { data, kind in
            try transport.transferFileData(data, metadata: [
                WatchConnectivityTransport.transferFileKindKey: kind.rawValue
            ])
        }
    }()
    @ObservationIgnored lazy var intentSync: WatchLinkIntentSync = {
        let sync = WatchLinkIntentSync(service: self, store: intentStore)
        sync.onMatchStarted = { [weak self] handle, setup in
            guard let self else { throw CancellationError() }
            try installAuthoritativeIntentStart(handle: handle, setup: setup)
        }
        return sync
    }()

    var sequence: UInt64 = 0
    var sessionMachine: LinkSessionStateMachine?
    var negotiatedPeerCapabilities: Set<LinkCapability> = []
    var peerSupportsFileTransfer: Bool { negotiatedPeerCapabilities.contains(.fileTransfer) }

    var publishedFinishedMatchIds: Set<UUID> = []
    var activeSessionId: UUID?
    var activeHandle: LinkedMatchHandle?
    var activeRevision: UInt64 = 0
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
    let contextKey = "watch_intent_active_context"
    let pendingSessionEndsKey = "watch_link_pending_session_ends"
    var pendingSessionEnds: [LinkPendingSessionEnd] = []
    var pendingSessionEndInFlight: Set<UUID> = []

    init(
        transport: any WatchLinkTransport = WatchConnectivityTransport(),
        contextStore: any LinkDataStore = WatchStorageContainer.shared.linkDataStore,
        outboxStore: any LinkDataStore = WatchStorageContainer.shared.linkDataStore,
        clock: any LinkClock = SystemLinkClock(),
        recordSink: (any WatchLinkRecordSink)? = nil,
        intentStore: FileLinkDataStore? = nil
    ) {
        self.transport = transport
        self.contextStore = contextStore
        self.outboxStore = outboxStore
        self.intentStore = intentStore ?? (contextStore as? FileLinkDataStore) ?? WatchStorageContainer.shared.linkDataStore
        self.clock = clock
        self.recordSink = recordSink ?? DefaultWatchLinkRecordSink()
        connectivityStatus = transport.status
        lastCommunicationAtEpochMilliseconds = WatchPreferences.shared.int64(
            forKey: lastCommunicationAtKey
        )
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
                let becameActivated = !self.connectivityStatus.isActivated && status.isActivated
                self.connectivityStatus = status
                guard status.isActivated else { return }
                self.flushPendingWatchRecords()
                self.flushPendingCommonNameMutations(force: false)
                if becameReachable || becameActivated {
                    self.intentSync.retryPendingAfterReconnect()
                    self.flushPendingSessionEnds()
                }
                self.rescheduleRetryIfNeeded()
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
            intentSync.retryPendingAfterReconnect()
            flushPendingSessionEnds()
            rescheduleRetryIfNeeded()
        }
        #if DEBUG
        print("[WatchLink] recordTransferHandler registered at WatchLinkService init")
        #endif
    }

    /// 共享会话下两端都可计分；只有会话未建立时才只读。
    var canEditLinkedMatch: Bool {
        guard let handle = activeHandle, intentSync.update?.handle == handle,
              !pendingSessionEnds.contains(where: { $0.handle == handle }),
              let machine = sessionMachine else { return false }
        return machine.lifecycle == .active || machine.lifecycle == .matchFinished
    }

    /// Read-only projection for callers moving to intentSync.update.

    var hasPendingIntentFinish: Bool {
        guard let update = intentSync.update, update.handle == activeHandle else { return false }
        return update.isPendingFinish || (update.displayedSnapshot.isFinished && !update.confirmedSnapshot.isFinished)
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
        guard WatchRecordManager.shared.saveRecord(record, source: .linked, transferToPhone: false) else {
            return nil
        }
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
