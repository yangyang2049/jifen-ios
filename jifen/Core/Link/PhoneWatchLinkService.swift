import Foundation
import LinkCore
import LinkSync
import Observation
import RecordCore
import ScoreCore
import UIKit

@MainActor
@Observable
final class PhoneWatchLinkService {
    struct LinkedResumeDescriptor: Equatable {
        let handle: LinkedMatchHandle
        let gameType: ScoreCore.GameType
        let setup: LinkedScoreboardSetup
        let revision: UInt64
        let snapshot: LinkedScoreboardSnapshot
        let detailedActions: [DetailedScoreAction]
        let isReachable: Bool
    }

    struct ActiveSession {
        var handle: LinkedMatchHandle
        let gameType: ScoreCore.GameType
        var revision: UInt64
        var setup: LinkedScoreboardSetup
        var completedMatchIds: Set<UUID>

        var sessionId: UUID { handle.sessionId }
    }

    let transport: any WatchLinkTransport
    let contextStore: any LinkDataStore
    let outboxStore: any LinkDataStore
    let recordSink: any PhoneLinkRecordSink
    let clock: any LinkClock
    let intentProjectionStore: FileLinkDataStore
    private let intentDirectoryURL: URL
    @ObservationIgnored lazy var intentCoordinator = makeIntentCoordinator(directoryURL: intentDirectoryURL)
    @ObservationIgnored lazy var intentSessionEngine = LinkSessionEngine(
        localPeer: .phone, transport: transport, clock: clock,
        fileTransfer: { [transport] data, kind in
            try transport.transferFileData(data, metadata: [
                WatchConnectivityTransport.transferFileKindKey: kind.rawValue,
            ])
        }
    )
    var sequence: UInt64 = 0
    var activeSession: ActiveSession?
    /// Authoritative match/control lifecycle. `ActiveSession` keeps only the
    /// setup projection needed by existing scoreboards and is synchronized
    /// from this machine after every transition.
    var sessionMachine: LinkSessionStateMachine?
    var peerSupportsCompressedFinish = false
    /// Capabilities agreed during the setup handshake.
    var negotiatedPeerCapabilities: Set<LinkCapability> = []
    /// Reason reported by the watch when it refused the latest setup request.
    internal(set) var lastSetupRejectionReason: LinkSetupRejectionReason?
    var setupContinuation: CheckedContinuation<UUID, Error>?
    var pendingSetupMessageId: UUID?
    var setupTimeoutTask: Task<Void, Never>?
    var setupAnalyticsGameType: String?
    var didTrackSetupAnalyticsResult = false
    var ackRetryTask: Task<Void, Never>?
    var pendingStatusCorrelationId: UUID?
    var statusContinuations: [CheckedContinuation<LinkStatusPayload, Error>] = []
    var statusTimeoutTask: Task<Void, Never>?
    var mergedDetailedActions: [DetailedScoreAction] = []
    let contextKey = "phone_link_context"
    let pendingSessionEndsKey = "phone_link_pending_session_ends"
    var pendingSessionEnds: [LinkPendingSessionEnd] = []
    var pendingSessionEndInFlight: Set<UUID> = []

    internal(set) var connectivityStatus: WatchConnectivityStatus
    internal(set) var latestRemoteSnapshot: LinkedSnapshotUpdate?
    internal(set) var finishedRecordId: String?
    internal(set) var lastErrorMessage: String?
    /// Last watch record id auto-synced into phone records (for toast / UI).
    internal(set) var lastSyncedWatchRecordId: String?
    /// Guards against firing the catch-up pull repeatedly while one is in flight.
    var watchRecordCatchUpInFlight = false

    #if DEBUG
    var hasScheduledRetryForTesting: Bool { ackRetryTask != nil }
    #endif

    static let setupTimeoutSeconds: TimeInterval = 20
    /// 状态查询（STATUS_QUERY）超时。对齐手表端的确认/开局超时窗口
    ///（`WatchRootView.confirmTimeoutSeconds = 20`），避免手机侧在手表
    /// 尚在确认时过早以 3 秒判定超时。
    static let statusQueryTimeoutSeconds: TimeInterval = 20

    enum InteractiveStartError: LocalizedError {
        case watchUnavailable
        case watchAppNotForeground
        case setupRejected
        case setupTimedOut
        case statusQueryTimedOut

        var errorDescription: String? {
            switch self {
            case .watchUnavailable:
                return NSLocalizedString(
                    "linked_score_watch_unavailable",
                    value: "Apple Watch 未连接，请打开手表端全能计分器后重试。",
                    comment: ""
                )
            case .watchAppNotForeground:
                return NSLocalizedString(
                    "linked_score_watch_not_foreground_message",
                    value: "请先在 Apple Watch 上打开「全能计分器」，保持应用在前台，然后再试一次。",
                    comment: ""
                )
            case .setupRejected:
                return NSLocalizedString(
                    "linked_score_watch_rejected",
                    value: "手表拒绝了联动开局。",
                    comment: ""
                )
            case .setupTimedOut:
                return NSLocalizedString(
                    "linked_score_watch_timeout",
                    value: "等待手表确认超时，请重试。",
                    comment: ""
                )
            case .statusQueryTimedOut:
                return NSLocalizedString(
                    "linked_score_status_timeout",
                    value: "等待手表状态响应超时。",
                    comment: ""
                )
            }
        }
    }

    struct LinkedSnapshotUpdate: Equatable {
        let sessionId: UUID
        let revision: UInt64
        /// Match generation within the link session. Increments when the watch
        /// starts a new match (再来一场); the `sessionId` stays constant, so
        /// this is what distinguishes a fresh match from a stale snapshot.
        let matchGeneration: UInt64
        let snapshot: LinkedScoreboardSnapshot
        var detailedActions: [DetailedScoreAction]

        func beginsMatch(after previous: Self?) -> Bool {
            guard let previous, previous.sessionId == sessionId else { return false }
            return previous.matchGeneration < matchGeneration
        }
    }

    init(
        transport: any WatchLinkTransport = WatchConnectivityTransport(),
        contextStore: any LinkDataStore = FileLinkDataStore.phoneWatchLinkDefault(),
        outboxStore: any LinkDataStore = FileLinkDataStore.phoneWatchLinkDefault(),
        recordSink: (any PhoneLinkRecordSink)? = nil,
        clock: any LinkClock = SystemLinkClock(),
        intentDirectoryURL: URL? = nil
    ) {
        self.transport = transport
        self.contextStore = contextStore
        self.outboxStore = outboxStore
        self.recordSink = recordSink ?? DefaultPhoneLinkRecordSink()
        self.clock = clock
        let intentDirectory = intentDirectoryURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchLink/intent-v1", isDirectory: true)
        self.intentDirectoryURL = intentDirectory
        intentProjectionStore = FileLinkDataStore(directoryURL: intentDirectory.appendingPathComponent("projection", isDirectory: true))
        connectivityStatus = transport.status
        if let data = outboxStore.data(forKey: pendingSessionEndsKey),
           let requests = try? JSONDecoder().decode([LinkPendingSessionEnd].self, from: data) {
            pendingSessionEnds = requests
        }
        restoreContext()
        if let handle = activeSession?.handle {
            do {
                _ = try intentCoordinator.recoverActiveMatch(handle: handle)
                try restoreIntentProjection(handle: handle)
                try finishIntentRollover()
            } catch {
                clearSession()
                lastErrorMessage = error.localizedDescription
            }
        }
        transport.onStatusChange = { [weak self] status in
            DispatchQueue.main.async {
                self?.handleConnectivityStatusChange(status)
            }
        }
        transport.onReceive = { [weak self] data in
            DispatchQueue.main.async {
                self?.handleIncoming(data)
            }
        }
        transport.onSendError = { [weak self] error in
            DispatchQueue.main.async {
                self?.lastErrorMessage = error.localizedDescription
            }
        }
        transport.onWatchRecordData = { [weak self] data in
            DispatchQueue.main.async {
                self?.handleWatchRecordTransfer(data)
            }
        }
        transport.onPendingRecords = { [weak self] datas in
            DispatchQueue.main.async {
                self?.receivePendingWatchRecords(datas)
            }
        }
        transport.onReceivedFile = { [weak self] data, metadata in
            DispatchQueue.main.async {
                self?.handleReceivedFile(data, metadata: metadata)
            }
        }
        transport.onCommonNameMutationsData = { [weak self] data in
            DispatchQueue.main.async {
                self?.handleCommonNameMutations(data)
            }
        }
        transport.activate()
        connectivityStatus = transport.status
        #if DEBUG
        print("[PhoneLink] PhoneWatchLinkService init: activate() called, onWatchRecordData wired")
        #endif
        scheduleRetryIfNeeded()
        NotificationCenter.default.addObserver(
            forName: .commonNamesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let service = self else { return }
            Task { @MainActor in
                service.pushCommonNamesToWatch()
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let service = self else { return }
            Task { @MainActor in
                service.transport.refreshStatus()
            }
        }
        pushCommonNamesToWatch()
    }

    var canStartInteractiveSession: Bool {
        connectivityStatus.canStartInteractiveSession
    }


    /// Cancel an in-flight setup handshake (user left Setup while waiting).
    func cancelPendingSetupHandshake() {
        setupTimeoutTask?.cancel()
        setupTimeoutTask = nil
        let continuation = setupContinuation
        setupContinuation = nil
        if let sessionId = activeSession?.sessionId {
            leaveSession(sessionId)
        } else {
            clearSession()
        }
        trackSetupAnalyticsResult(.rejected)
        continuation?.resume(throwing: InteractiveStartError.setupRejected)
    }

    /// 共享会话下两端都可计分；只有会话未建立时才只读。
    var canEditLinkedMatch: Bool {
        guard let machine = sessionMachine else { return false }
        return machine.lifecycle == .active || machine.lifecycle == .matchFinished
    }

    /// Phone-confirmed state for either origin's operation.
    var incomingSnapshot: LinkedSnapshotUpdate? {
        canEditLinkedMatch ? latestRemoteSnapshot : nil
    }

    var peerFinishedSharedMatch: Bool {
        incomingSnapshot?.snapshot.isFinished == true
    }

    var activeSessionId: UUID? {
        activeSession?.sessionId
    }

    var linkedResumeDescriptor: LinkedResumeDescriptor? {
        // A session only exists once the watch accepts the setup handshake.
        // While lifecycle is `.starting` (setup request sent, accept/reject
        // still pending) no resume descriptor is surfaced, so no Resume
        // GameBar appears before the link is actually established.
        guard let session = activeSession,
              sessionMachine?.lifecycle != .starting,
              !pendingSessionEnds.contains(where: { $0.handle.sessionId == session.sessionId }),
              let snapshot = latestRemoteSnapshot?.sessionId == session.sessionId
                ? latestRemoteSnapshot?.snapshot
                : session.setup.initialSnapshot else {
            return nil
        }
        return LinkedResumeDescriptor(
            handle: session.handle,
            gameType: session.gameType,
            setup: session.setup,
            revision: session.revision,
            snapshot: snapshot,
            detailedActions: mergedDetailedActions,
            isReachable: connectivityStatus.isReachable
        )
    }

    var resumeStateToken: String {
        guard let session = activeSession else {
            return "none-\(connectivityStatus.isReachable)"
        }
        return [
            session.handle.sessionId.uuidString,
            session.handle.matchId.uuidString,
            String(session.handle.matchGeneration),
            String(session.revision),
            pendingSessionEnds.contains { $0.handle.sessionId == session.sessionId }.description,
            connectivityStatus.isReachable.description
        ].joined(separator: ":")
    }

    func clearLastError() {
        lastErrorMessage = nil
    }

    /// Removes only phone-side transient linkage state. It deliberately sends
    /// no leave/delete message to the paired watch, so clearing this device
    /// never erases independent Watch data.
    func clearLocalTransientStateForDataReset() {
        setupTimeoutTask?.cancel()
        setupTimeoutTask = nil
        setupContinuation?.resume(throwing: CancellationError())
        setupContinuation = nil
        pendingSetupMessageId = nil
        ackRetryTask?.cancel()
        ackRetryTask = nil
        clearSession()

        pendingSessionEnds.removeAll()
        pendingSessionEndInFlight.removeAll()
        ackRetryTask?.cancel()
        ackRetryTask = nil
        mergedDetailedActions.removeAll()
        finishedRecordId = nil
        lastSyncedWatchRecordId = nil
        lastErrorMessage = nil

        contextStore.removeObject(forKey: contextKey)
        outboxStore.removeObject(forKey: pendingSessionEndsKey)
        do {
            if FileManager.default.fileExists(atPath: intentDirectoryURL.path) {
                try FileManager.default.removeItem(at: intentDirectoryURL)
            }
            try FileManager.default.createDirectory(
                at: intentDirectoryURL.appendingPathComponent("projection", isDirectory: true),
                withIntermediateDirectories: true
            )
            intentCoordinator = makeIntentCoordinator(directoryURL: intentDirectoryURL)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

}
