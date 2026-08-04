import Foundation
import LinkCore
import Observation
import RecordCore
import ScoreCore
import UIKit

@MainActor
@Observable
final class PhoneWatchLinkService {
    struct ReclaimConfirmationRequest: Equatable {
        let messageId: UUID
        let sessionId: UUID
        let revision: UInt64
    }

    struct PendingPhoneTakeoverApplication: Equatable {
        let messageId: UUID
        let sessionId: UUID
        let revision: UInt64
        let snapshot: LinkedScoreboardSnapshot
        let detailedActions: [DetailedScoreAction]
    }

    struct LinkedResumeDescriptor: Equatable {
        let handle: LinkedMatchHandle
        let gameType: ScoreCore.GameType
        let setup: LinkedScoreboardSetup
        let role: LinkControlRole
        let authorityEpoch: UInt64
        let revision: UInt64
        let snapshot: LinkedScoreboardSnapshot
        let detailedActions: [DetailedScoreAction]
        let isReachable: Bool
        let watchBackgrounded: Bool
    }

    struct ActiveSession {
        var handle: LinkedMatchHandle
        let gameType: ScoreCore.GameType
        var revision: UInt64
        var role: LinkControlRole
        var authorityEpoch: UInt64
        var setup: LinkedScoreboardSetup
        var completedMatchIds: Set<UUID>

        var sessionId: UUID { handle.sessionId }
    }

    let transport: any WatchLinkTransport
    let contextStore: any LinkDataStore
    let outboxStore: any LinkDataStore
    let recordSink: any PhoneLinkRecordSink
    let clock: any LinkClock
    var sequence: UInt64 = 0
    var activeSession: ActiveSession?
    /// Authoritative match/control lifecycle. `ActiveSession` keeps only the
    /// setup projection needed by existing scoreboards and is synchronized
    /// from this machine after every transition.
    var sessionMachine: LinkSessionStateMachine?
    var pendingAck = LinkControlRetryQueue()
    var terminalOutbox = LinkDurableOutbox()
    var setupContinuation: CheckedContinuation<UUID, Error>?
    var pendingSetupMessageId: UUID?
    var setupTimeoutTask: Task<Void, Never>?
    var setupAnalyticsGameType: String?
    var didTrackSetupAnalyticsResult = false
    var ackRetryTask: Task<Void, Never>?
    var revisionGate = LinkRevisionGate()
    var pendingTakeoverMessageId: UUID?
    var pendingStatusCorrelationId: UUID?
    var statusContinuations: [CheckedContinuation<LinkStatusPayload, Error>] = []
    var statusTimeoutTask: Task<Void, Never>?
    var pendingReclaimGrantMessageId: UUID?
    var reclaimTimeoutTask: Task<Void, Never>?
    var mergedDetailedActions: [DetailedScoreAction] = []
    var publishedFinishedMatchIds: Set<UUID> = []
    let contextKey = "phone_link_context"
    let terminalOutboxKey = "phone_link_terminal_outbox"
    let pendingSessionEndsKey = "phone_link_pending_session_ends"
    let legacyCleanupMarkerKey = "phone_link_legacy_cleanup_v1"
    var pendingSessionEnds: [LinkPendingSessionEnd] = []
    var pendingSessionEndInFlight: Set<UUID> = []

    internal(set) var connectivityStatus: WatchConnectivityStatus
    internal(set) var controlRole: LinkControlRole?
    internal(set) var latestRemoteSnapshot: LinkedSnapshotUpdate?
    internal(set) var finishedRecordId: String?
    internal(set) var watchBackgrounded: Bool = false
    internal(set) var lastErrorMessage: String?
    /// Last watch record id auto-synced into phone records (for toast / UI).
    internal(set) var lastSyncedWatchRecordId: String?
    /// Guards against firing the catch-up pull repeatedly while one is in flight.
    var watchRecordCatchUpInFlight = false
    internal(set) var pendingReclaimRequest: ReclaimConfirmationRequest?
    internal(set) var pendingTakeoverApplication: PendingPhoneTakeoverApplication?
    internal(set) var forceTakeoverConfirmationSessionId: UUID?

    var isAuthorityTransferPending: Bool {
        pendingTakeoverMessageId != nil
            || pendingReclaimGrantMessageId != nil
            || pendingTakeoverApplication != nil
    }

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
        case notController
        case notFollower
        case statusQueryTimedOut
        case noConfirmedSnapshot
        case authorityTransferTimedOut

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
            case .notController:
                return NSLocalizedString(
                    "linked_score_not_controller",
                    value: "当前不是主控端，无法执行该操作。",
                    comment: ""
                )
            case .notFollower:
                return NSLocalizedString(
                    "linked_score_not_follower",
                    value: "当前手机不是跟随端，无需接管。",
                    comment: ""
                )
            case .statusQueryTimedOut:
                return NSLocalizedString(
                    "linked_score_status_timeout",
                    value: "等待手表状态响应超时。",
                    comment: ""
                )
            case .noConfirmedSnapshot:
                return NSLocalizedString(
                    "linked_score_no_confirmed_snapshot",
                    value: "没有已确认的比赛快照，无法安全强制接管。",
                    comment: ""
                )
            case .authorityTransferTimedOut:
                return NSLocalizedString(
                    "linked_score_control_timeout",
                    value: "控制权切换超时，请重试。",
                    comment: ""
                )
            }
        }
    }

    struct LinkedSnapshotUpdate: Equatable {
        let sessionId: UUID
        let revision: UInt64
        let snapshot: LinkedScoreboardSnapshot
        let detailedActions: [DetailedScoreAction]
    }

    init(
        transport: any WatchLinkTransport = WatchConnectivityTransport(),
        contextStore: any LinkDataStore = UserDefaultsLinkDataStore.standard,
        outboxStore: any LinkDataStore = UserDefaultsLinkDataStore.standard,
        recordSink: (any PhoneLinkRecordSink)? = nil,
        clock: any LinkClock = SystemLinkClock()
    ) {
        self.transport = transport
        self.contextStore = contextStore
        self.outboxStore = outboxStore
        self.recordSink = recordSink ?? DefaultPhoneLinkRecordSink()
        self.clock = clock
        connectivityStatus = transport.status
        if contextStore.data(forKey: legacyCleanupMarkerKey) == nil {
            contextStore.removeObject(forKey: "phone_link_context_v1")
            outboxStore.removeObject(forKey: "phone_link_terminal_outbox_v1")
            outboxStore.removeObject(forKey: "phone_link_pending_ack_v1")
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
        transport.onCommonNameUsageData = { [weak self] data in
            DispatchQueue.main.async {
                self?.handleCommonNameUsage(data)
            }
        }
        transport.onCommonNameMutationsData = { [weak self] data in
            DispatchQueue.main.async {
                self?.handleCommonNameMutations(data)
            }
        }
        transport.activate()
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

    var isFollower: Bool {
        controlRole == .phoneFollower
    }

    var isController: Bool {
        controlRole == .phoneController
    }

    var activeSessionId: UUID? {
        activeSession?.sessionId
    }

    var linkedResumeDescriptor: LinkedResumeDescriptor? {
        guard let session = activeSession,
              let snapshot = latestRemoteSnapshot?.sessionId == session.sessionId
                ? latestRemoteSnapshot?.snapshot
                : session.setup.initialSnapshot else {
            return nil
        }
        return LinkedResumeDescriptor(
            handle: session.handle,
            gameType: session.gameType,
            setup: session.setup,
            role: session.role,
            authorityEpoch: session.authorityEpoch,
            revision: session.revision,
            snapshot: snapshot,
            detailedActions: mergedDetailedActions,
            isReachable: connectivityStatus.isReachable,
            watchBackgrounded: watchBackgrounded
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
            String(session.authorityEpoch),
            String(session.revision),
            session.role.rawValue,
            connectivityStatus.isReachable.description,
            watchBackgrounded.description
        ].joined(separator: ":")
    }

    func clearLastError() {
        lastErrorMessage = nil
    }

    func requestForceTakeoverConfirmation(_ sessionId: UUID) {
        guard activeSession?.sessionId == sessionId,
              activeSession?.role == .phoneFollower else {
            lastErrorMessage = InteractiveStartError.notFollower.localizedDescription
            return
        }
        forceTakeoverConfirmationSessionId = sessionId
    }

    func cancelForceTakeoverConfirmation() {
        forceTakeoverConfirmationSessionId = nil
    }

    func confirmForceTakeover() {
        guard let sessionId = forceTakeoverConfirmationSessionId else { return }
        forceTakeoverConfirmationSessionId = nil
        Task {
            do {
                try await forceTakeover(sessionId: sessionId)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

}
