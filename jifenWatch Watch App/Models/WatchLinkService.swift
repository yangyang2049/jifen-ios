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

    var sessionId: UUID { handle.sessionId }
}
struct LinkedSnapshotUpdate: Equatable {
    let sessionId: UUID
    let revision: UInt64
    let snapshot: LinkedScoreboardSnapshot
    let detailedActions: [DetailedScoreAction]
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
    var revisionGate = LinkRevisionGate()
    var sequence: UInt64 = 0
    /// Authoritative linked-match and control lifecycle. The scalar fields
    /// below are projections used by existing Watch views and persistence.
    var sessionMachine: LinkSessionStateMachine?
    var pendingAck = LinkControlRetryQueue()
    var terminalOutbox = LinkDurableOutbox()
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
    let pendingCommonNameUsageKey = "watch_pending_common_name_usage_v1"
    var pendingCommonNameUsage: [CommonNameUsagePayload] = []
    var lastQueuedCommonNameMutationIDs: [UUID] = []
    var probeTracker = WatchPhoneLinkProbeTracker()
    var probeTimeoutTask: Task<Void, Never>?
    let lastCommunicationAtKey = "watch_phone_link_last_communication_at_v1"
    let contextKey = "watch_link_context"
    let terminalOutboxKey = "watch_link_terminal_outbox"
    let pendingSessionEndsKey = "watch_link_pending_session_ends"
    let legacyCleanupMarkerKey = "watch_link_legacy_cleanup_v1"
    var pendingSessionEnds: [LinkPendingSessionEnd] = []
    var pendingSessionEndInFlight: Set<UUID> = []

    init(
        transport: any WatchLinkTransport = WatchConnectivityTransport(),
        contextStore: any LinkDataStore = UserDefaultsLinkDataStore.standard,
        outboxStore: any LinkDataStore = UserDefaultsLinkDataStore.standard,
        clock: any LinkClock = SystemLinkClock()
    ) {
        self.transport = transport
        self.contextStore = contextStore
        self.outboxStore = outboxStore
        self.clock = clock
        connectivityStatus = transport.status
        lastCommunicationAtEpochMilliseconds = Int64(
            UserDefaults.standard.integer(forKey: lastCommunicationAtKey)
        )
        if contextStore.data(forKey: legacyCleanupMarkerKey) == nil {
            contextStore.removeObject(forKey: "watch_link_context_v1")
            outboxStore.removeObject(forKey: "watch_link_terminal_outbox_v1")
            outboxStore.removeObject(forKey: "watch_link_pending_ack_v1")
            contextStore.set(Data([1]), forKey: legacyCleanupMarkerKey)
        }
        if let data = outboxStore.data(forKey: terminalOutboxKey),
           let outbox = try? JSONDecoder().decode(LinkDurableOutbox.self, from: data) {
            terminalOutbox = outbox
        }
        if let data = outboxStore.data(forKey: pendingSessionEndsKey),
           let requests = try? JSONDecoder().decode([LinkPendingSessionEnd].self, from: data) {
            pendingSessionEnds = requests
        }
        restoreContext()
        if let data = UserDefaults.standard.data(forKey: pendingWatchRecordsKey),
           let payloads = try? JSONDecoder().decode([WatchRecordTransferPayload].self, from: data) {
            pendingWatchRecords = payloads
        }
        if let data = UserDefaults.standard.data(forKey: pendingCommonNameUsageKey),
           let payloads = try? JSONDecoder().decode([CommonNameUsagePayload].self, from: data) {
            pendingCommonNameUsage = payloads
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
        transport.onStatusChange = { [weak self] status in
            DispatchQueue.main.async {
                self?.connectivityStatus = status
                guard status.isActivated else { return }
                self?.flushPendingWatchRecords()
                self?.flushPendingCommonNameUsage()
                self?.flushPendingCommonNameMutations(force: false)
                if status.isReachable {
                    self?.requestCommonNamesSnapshot()
                }
            }
        }
        transport.activate()
        scheduleRetryIfNeeded()
        handleApplicationContext(transport.receivedApplicationContext)
        flushPendingCommonNameMutations(force: false)
        WatchRecordManager.shared.recordTransferHandler = { [weak self] payload in
            self?.transferFinishedRecord(payload)
        }
    }

    var isController: Bool {
        controlRole == .watchController
    }

    #if DEBUG
    var hasScheduledRetryForTesting: Bool { ackRetryTask != nil }
    #endif

    func clearLinkError() {
        lastLinkErrorMessage = nil
    }

}
