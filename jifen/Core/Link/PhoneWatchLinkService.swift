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

    private struct ActiveSession {
        var handle: LinkedMatchHandle
        let gameType: ScoreCore.GameType
        var revision: UInt64
        var role: LinkControlRole
        var authorityEpoch: UInt64
        var setup: LinkedScoreboardSetup
        var completedMatchIds: Set<UUID>

        var sessionId: UUID { handle.sessionId }
    }

    private let transport: any WatchLinkTransport
    private let contextStore: any LinkDataStore
    private let outboxStore: any LinkDataStore
    private let recordSink: any PhoneLinkRecordSink
    private let clock: any LinkClock
    private var sequence: UInt64 = 0
    private var activeSession: ActiveSession?
    /// Authoritative match/control lifecycle. `ActiveSession` keeps only the
    /// setup projection needed by existing scoreboards and is synchronized
    /// from this machine after every transition.
    private var sessionMachine: LinkSessionStateMachine?
    private var pendingAck = LinkControlRetryQueue()
    private var terminalOutbox = LinkDurableOutbox()
    private var setupContinuation: CheckedContinuation<UUID, Error>?
    private var pendingSetupMessageId: UUID?
    private var setupTimeoutTask: Task<Void, Never>?
    private var setupAnalyticsGameType: String?
    private var didTrackSetupAnalyticsResult = false
    private var ackRetryTask: Task<Void, Never>?
    private var revisionGate = LinkRevisionGate()
    private var pendingTakeoverMessageId: UUID?
    private var pendingStatusCorrelationId: UUID?
    private var statusContinuation: CheckedContinuation<LinkStatusPayload, Error>?
    private var statusTimeoutTask: Task<Void, Never>?
    private var pendingReclaimGrantMessageId: UUID?
    private var reclaimTimeoutTask: Task<Void, Never>?
    private var mergedDetailedActions: [DetailedScoreAction] = []
    private var publishedFinishedMatchIds: Set<UUID> = []
    private let contextKey = "phone_link_context"
    private let terminalOutboxKey = "phone_link_terminal_outbox"
    private let pendingSessionEndsKey = "phone_link_pending_session_ends"
    private var pendingSessionEnds: [LinkPendingSessionEnd] = []
    private var pendingSessionEndInFlight: Set<UUID> = []

    private(set) var connectivityStatus: WatchConnectivityStatus
    private(set) var controlRole: LinkControlRole?
    private(set) var latestRemoteSnapshot: LinkedSnapshotUpdate?
    private(set) var finishedRecordId: String?
    private(set) var watchBackgrounded: Bool = false
    private(set) var lastErrorMessage: String?
    /// Last watch record id auto-synced into phone records (for toast / UI).
    private(set) var lastSyncedWatchRecordId: String?
    private(set) var pendingReclaimRequest: ReclaimConfirmationRequest?
    private(set) var pendingTakeoverApplication: PendingPhoneTakeoverApplication?
    private(set) var forceTakeoverConfirmationSessionId: UUID?

    var isAuthorityTransferPending: Bool {
        pendingTakeoverMessageId != nil
            || pendingReclaimGrantMessageId != nil
            || pendingTakeoverApplication != nil
    }

    static let setupTimeoutSeconds: TimeInterval = 20

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
        contextStore.removeObject(forKey: "phone_link_context_v1")
        outboxStore.removeObject(forKey: "phone_link_terminal_outbox_v1")
        outboxStore.removeObject(forKey: "phone_link_pending_ack_v1")
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
        startAckRetryLoop()
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
                service.connectivityStatus = service.transport.status
                if service.connectivityStatus.isReachable {
                    service.requestStatusForActiveSession()
                }
            }
        }
        pushCommonNamesToWatch()
    }

    var canStartInteractiveSession: Bool {
        connectivityStatus.canStartInteractiveSession
    }

    /// Force a connectivity status refresh for the Watch Link settings page.
    func refreshConnectivity() {
        transport.refreshStatus()
        connectivityStatus = transport.status
        pushCommonNamesToWatch()
    }

    /// Interactive setup cannot wake the Watch app. Refresh immediately before
    /// creating a linked session so an unavailable Watch never receives a queued
    /// setup request that appears later without the user's context.
    func validateInteractiveWatchAvailability() throws {
        transport.refreshStatus()
        connectivityStatus = transport.status
        guard connectivityStatus.isSupported,
              connectivityStatus.isActivated,
              connectivityStatus.isPaired,
              connectivityStatus.isWatchAppInstalled else {
            throw InteractiveStartError.watchUnavailable
        }
        guard connectivityStatus.isReachable else {
            throw InteractiveStartError.watchAppNotForeground
        }
    }

    /// Push current phone common names to the watch via application context (always-latest).
    func pushCommonNamesToWatch() {
        guard connectivityStatus.isSupported,
              connectivityStatus.isActivated,
              connectivityStatus.isPaired,
              connectivityStatus.isWatchAppInstalled else { return }
        let snapshot = CommonNamesManager.shared.currentSyncSnapshot()
        let context: [String: Any] = [
            WatchConnectivityTransport.commonNamesContextKey: snapshot.applicationContextValue()
        ]
        do {
            try transport.updateApplicationContext(context)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func handleWatchRecordTransfer(_ data: Data) {
        guard let payload = try? JSONDecoder().decode(WatchRecordTransferPayload.self, from: data) else {
            return
        }
        do {
            lastSyncedWatchRecordId = try WatchStandaloneRecordIngestor.ingest(payload)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func handleCommonNameUsage(_ data: Data) {
        guard let payload = try? JSONDecoder().decode(CommonNameUsagePayload.self, from: data),
              payload.nameType == "player" else { return }
        Task { @MainActor [weak self] in
            for name in payload.names {
                await CommonNamesManager.shared.saveNameIfNeeded(name, .player)
            }
            self?.pushCommonNamesToWatch()
        }
    }

    private func handleCommonNameMutations(_ data: Data) {
        guard let batch = try? JSONDecoder().decode(CommonNameMutationBatch.self, from: data),
              !batch.mutations.isEmpty else { return }
        let acknowledgement = CommonNamesManager.shared.applyWatchMutations(batch.mutations)
        do {
            let acknowledgementData = try JSONEncoder().encode(acknowledgement)
            try transport.transferCommonNameMutationAcknowledgement(acknowledgementData)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        if !acknowledgement.results.contains(where: { $0.status == .applied }) {
            pushCommonNamesToWatch()
        }
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

    /// Ask the authoritative Watch controller to resend its latest full state.
    /// This is user initiated and deliberately does not change control roles.
    @discardableResult
    func requestScoreResync() -> Bool {
        guard let session = activeSession,
              LinkManualResyncPolicy.phoneCanRequest(role: session.role) else {
            return false
        }
        sequence += 1
        let envelope = LinkEnvelope(
            messageId: UUID(),
            correlationId: nil,
            sessionId: session.sessionId,
            matchId: session.handle.matchId,
            matchGeneration: session.handle.matchGeneration,
            authorityEpoch: session.authorityEpoch,
            kind: .resyncRequest,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: session.revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: EmptyLinkPayload()
        )
        Task {
            do {
                try await sendEnvelope(envelope)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
        return true
    }

    func startInteractiveOnWatch(gameType: ScoreCore.GameType, state: RallyMatchState) async throws -> UUID {
        try await startInteractiveSession(
            gameType: gameType,
            maxSets: state.rules.maxSets,
            initialSnapshot: .rally(state)
        )
    }

    func startInteractiveOnWatch(gameType: ScoreCore.GameType, state: TennisMatchState) async throws -> UUID {
        try await startInteractiveSession(
            gameType: gameType,
            maxSets: state.rules.maxSets,
            initialSnapshot: .tennis(state)
        )
    }

    func startInteractiveOnWatch(
        snapshot: LinkedScoreboardSnapshot,
        gameType: ScoreCore.GameType,
        participantNames: [String]? = nil
    ) async throws -> UUID {
        try await startInteractiveSession(
            gameType: gameType,
            maxSets: maxSets(for: snapshot),
            initialSnapshot: snapshot,
            participantNames: participantNames
        )
    }

    func syncWatch(sessionId: UUID, gameType: ScoreCore.GameType, state: RallyMatchState, detailedActions: [DetailedScoreAction]? = nil) {
        sendSnapshotIfController(sessionId: sessionId, gameType: gameType, snapshot: .rally(state), detailedActions: detailedActions)
    }

    func syncWatch(sessionId: UUID, gameType: ScoreCore.GameType, state: TennisMatchState, detailedActions: [DetailedScoreAction]? = nil) {
        sendSnapshotIfController(sessionId: sessionId, gameType: gameType, snapshot: .tennis(state), detailedActions: detailedActions)
    }

    func syncWatch(
        sessionId: UUID,
        gameType: ScoreCore.GameType,
        snapshot: LinkedScoreboardSnapshot,
        detailedActions: [DetailedScoreAction]? = nil,
        participantNames: [String]? = nil
    ) {
        sendSnapshotIfController(
            sessionId: sessionId,
            gameType: gameType,
            snapshot: snapshot,
            detailedActions: detailedActions,
            participantNames: participantNames
        )
    }

    /// Reuses the current phone-controller link for a distinct match while
    /// clearing match-scoped terminal and action state from the previous one.
    func prepareControllerForNewMatch(
        sessionId: UUID,
        gameType: ScoreCore.GameType,
        snapshot: LinkedScoreboardSnapshot,
        participantNames: [String]? = nil
    ) {
        guard let currentSession = activeSession,
              currentSession.sessionId == sessionId,
              currentSession.gameType == gameType,
              currentSession.role == .phoneController,
              var machine = sessionMachine else { return }
        let nextHandle = machine.beginNextMatch()
        sessionMachine = machine
        synchronizeActiveSessionFromStateMachine()
        guard activeSession != nil else { return }
        finishedRecordId = nil
        mergedDetailedActions.removeAll()
        _ = revisionGate.beginMatch(nextHandle, initialRevision: 0)
        persistContext()
        sendSnapshotIfController(
            sessionId: sessionId,
            gameType: gameType,
            snapshot: snapshot,
            detailedActions: [],
            participantNames: participantNames
        )
    }

    func takeover(sessionId: UUID) async throws {
        guard let session = activeSession,
              session.sessionId == sessionId,
              session.role == .phoneFollower,
              connectivityStatus.canStartInteractiveSession else {
            throw InteractiveStartError.watchUnavailable
        }
        sequence += 1
        let messageId = UUID()
        let update = latestRemoteSnapshot
        let envelope = LinkEnvelope(
            messageId: messageId,
            correlationId: messageId,
            sessionId: sessionId,
            matchId: session.handle.matchId,
            matchGeneration: session.handle.matchGeneration,
            authorityEpoch: session.authorityEpoch,
            kind: .takeoverByPhone,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: session.revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkAuthorityTransferPayload(
                snapshot: update?.sessionId == sessionId ? update?.snapshot : nil,
                detailedActions: update?.sessionId == sessionId ? update?.detailedActions ?? [] : [],
                baseRevision: session.revision
            )
        )
        let data = try JSONEncoder().encode(envelope)
        pendingTakeoverMessageId = messageId
        if var machine = sessionMachine {
            guard machine.beginAuthorityTransfer(
                correlationId: messageId,
                targetRole: .phoneController,
                kind: .phoneTakeover
            ) else { throw InteractiveStartError.notFollower }
            machine.registerPendingAcknowledgement(messageId)
            sessionMachine = machine
        }
        pendingAck.enqueue(.init(
            messageId: messageId,
            sessionId: sessionId,
            revision: session.revision,
            data: data,
            lastSentAtEpochMilliseconds: nowMs()
        ))
        do {
            try await transport.sendRealtime(data)
        } catch {
            _ = pendingAck.acknowledge(messageId: messageId)
            pendingTakeoverMessageId = nil
            if var machine = sessionMachine {
                _ = machine.acknowledge(messageId: messageId)
                _ = machine.rejectAuthorityTransfer(correlationId: messageId)
                sessionMachine = machine
            }
            throw error
        }
    }

    /// Emergency authority transfer. A correlated status query gets a full
    /// three-second opportunity to complete first. If the peer cannot answer,
    /// takeover is allowed only from the last snapshot the Watch previously
    /// confirmed or published.
    func forceTakeover(sessionId: UUID) async throws {
        guard activeSession?.sessionId == sessionId,
              activeSession?.role == .phoneFollower else {
            throw InteractiveStartError.notFollower
        }

        _ = try? await queryStatus(timeoutSeconds: 3)

        guard let currentSession = activeSession,
              currentSession.sessionId == sessionId,
              currentSession.role == .phoneFollower,
              var machine = sessionMachine else {
            throw InteractiveStartError.notFollower
        }
        guard let snapshot = latestRemoteSnapshot?.sessionId == sessionId
                ? latestRemoteSnapshot?.snapshot
                : currentSession.setup.initialSnapshot else {
            throw InteractiveStartError.noConfirmedSnapshot
        }

        _ = machine.forceAuthority(to: .phoneController)
        _ = machine.advanceRevision()
        sessionMachine = machine
        synchronizeActiveSessionFromStateMachine()
        guard var session = activeSession else {
            throw InteractiveStartError.notFollower
        }
        session.setup = LinkedScoreboardSetup(
            gameType: session.gameType,
            maxSets: maxSets(for: snapshot),
            initialSnapshot: snapshot,
            detailedActions: mergedDetailedActions,
            participantNames: session.setup.participantNames
        )
        activeSession = session
        controlRole = .phoneController
        watchBackgrounded = false
        latestRemoteSnapshot = .init(
            sessionId: sessionId,
            revision: session.revision,
            snapshot: snapshot,
            detailedActions: mergedDetailedActions
        )
        persistContext()

        sequence += 1
        let messageId = UUID()
        let envelope = LinkEnvelope(
            messageId: messageId,
            sessionId: sessionId,
            matchId: session.handle.matchId,
            matchGeneration: session.handle.matchGeneration,
            authorityEpoch: session.authorityEpoch,
            kind: .stateSnapshot,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: session.revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: session.setup
        )
        let data = try JSONEncoder().encode(envelope)
        sessionMachine?.registerPendingAcknowledgement(messageId)
        pendingAck.enqueue(.init(
            messageId: messageId,
            sessionId: sessionId,
            revision: session.revision,
            data: data,
            lastSentAtEpochMilliseconds: nowMs()
        ))
        try transport.publishLatestSnapshot(data)
        if transport.isReachable {
            try await transport.sendRealtime(data)
        }
    }

    @discardableResult
    private func queryStatus(timeoutSeconds: TimeInterval) async throws -> LinkStatusPayload {
        guard let session = activeSession else {
            throw InteractiveStartError.notFollower
        }
        if let continuation = statusContinuation {
            statusContinuation = nil
            continuation.resume(throwing: CancellationError())
        }
        statusTimeoutTask?.cancel()

        sequence += 1
        let envelope = LinkEnvelope(
            messageId: UUID(),
            sessionId: session.sessionId,
            matchId: session.handle.matchId,
            matchGeneration: session.handle.matchGeneration,
            authorityEpoch: session.authorityEpoch,
            kind: .statusQuery,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: session.revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: EmptyLinkPayload()
        )
        pendingStatusCorrelationId = envelope.messageId

        return try await withCheckedThrowingContinuation { continuation in
            statusContinuation = continuation
            statusTimeoutTask = Task { [weak self] in
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(timeoutSeconds * 1_000_000_000)
                    )
                } catch {
                    return
                }
                await MainActor.run {
                    guard let self,
                          self.pendingStatusCorrelationId == envelope.messageId,
                          let pending = self.statusContinuation else { return }
                    self.pendingStatusCorrelationId = nil
                    self.statusContinuation = nil
                    self.statusTimeoutTask = nil
                    pending.resume(throwing: InteractiveStartError.statusQueryTimedOut)
                }
            }
            Task { [weak self] in
                do {
                    try await self?.sendEnvelope(envelope)
                } catch {
                    // The three-second timeout is intentional even when the
                    // immediate send fails: a delayed reachability change can
                    // still deliver a newer application-context snapshot.
                }
            }
        }
    }

    func resolveReclaimRequest(
        accepted: Bool,
        snapshot: LinkedScoreboardSnapshot?,
        detailedActions: [DetailedScoreAction]
    ) {
        guard let request = pendingReclaimRequest,
              let currentSession = activeSession,
              currentSession.sessionId == request.sessionId,
              currentSession.role == .phoneController else { return }
        reclaimTimeoutTask?.cancel()
        reclaimTimeoutTask = nil
        pendingReclaimRequest = nil
        sequence += 1

        if !accepted || snapshot == nil {
            let envelope = LinkEnvelope(
                correlationId: request.messageId,
                sessionId: request.sessionId,
                matchId: currentSession.handle.matchId,
                matchGeneration: currentSession.handle.matchGeneration,
                authorityEpoch: currentSession.authorityEpoch,
                kind: .reclaimDenied,
                sender: .phone,
                senderSequence: sequence,
                sessionRevision: currentSession.revision,
                sentAtEpochMilliseconds: nowMs(),
                payload: LinkAuthorityTransferPayload(baseRevision: currentSession.revision)
            )
            sendReportingError(envelope)
            return
        }

        let messageId = UUID()
        guard var machine = sessionMachine,
              machine.beginAuthorityTransfer(
                  correlationId: messageId,
                  targetRole: .phoneFollower,
                  kind: .watchReclaim
              ),
              machine.prepareAuthorityTransfer(
                  correlationId: messageId,
                  epoch: machine.authorityEpoch + 1
              ) else { return }
        _ = machine.advanceRevision()
        machine.registerPendingAcknowledgement(messageId)
        sessionMachine = machine
        synchronizeActiveSessionFromStateMachine()
        guard let session = activeSession else { return }
        persistContext()
        let envelope = LinkEnvelope(
            messageId: messageId,
            correlationId: request.messageId,
            sessionId: request.sessionId,
            matchId: session.handle.matchId,
            matchGeneration: session.handle.matchGeneration,
            authorityEpoch: session.authorityEpoch,
            kind: .reclaimAccepted,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: session.revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkAuthorityTransferPayload(
                snapshot: snapshot,
                detailedActions: detailedActions,
                baseRevision: session.revision
            )
        )
        do {
            let data = try JSONEncoder().encode(envelope)
            pendingReclaimGrantMessageId = messageId
            pendingAck.enqueue(.init(
                messageId: messageId,
                sessionId: request.sessionId,
                revision: session.revision,
                data: data,
                lastSentAtEpochMilliseconds: nowMs()
            ))
            Task {
                do {
                    try await transport.sendRealtime(data)
                } catch {
                    lastErrorMessage = error.localizedDescription
                }
            }
        } catch {
            if var machine = sessionMachine {
                _ = machine.acknowledge(messageId: messageId)
                _ = machine.rejectAuthorityTransfer(correlationId: messageId)
                sessionMachine = machine
                synchronizeActiveSessionFromStateMachine()
            }
            pendingReclaimGrantMessageId = nil
            lastErrorMessage = error.localizedDescription
            persistContext()
        }
    }

    func completePhoneTakeover(messageId: UUID) {
        guard let pending = pendingTakeoverApplication,
              pending.messageId == messageId,
              activeSession?.sessionId == pending.sessionId,
              sessionMachine?.role == .phoneController else { return }
        pendingTakeoverApplication = nil
        latestRemoteSnapshot = .init(
            sessionId: pending.sessionId,
            revision: pending.revision,
            snapshot: pending.snapshot,
            detailedActions: pending.detailedActions
        )
        watchBackgrounded = false
        persistContext()
    }

    func leaveSession(_ sessionId: UUID) {
        guard let session = activeSession, session.sessionId == sessionId else { return }
        let request = LinkPendingSessionEnd(
            handle: session.handle,
            authorityEpoch: session.authorityEpoch,
            revision: session.revision
        )
        if let index = pendingSessionEnds.firstIndex(where: {
            $0.handle.sessionId == sessionId
        }) {
            pendingSessionEnds[index] = request
        } else {
            pendingSessionEnds.append(request)
        }
        persistPendingSessionEnds()
        flushPendingSessionEnds()
    }

    @discardableResult
    func attachPage(sessionId: UUID) -> LinkedSnapshotUpdate? {
        guard activeSession?.sessionId == sessionId else { return nil }
        persistContext()
        return latestRemoteSnapshot
    }

    func detachPage(sessionId: UUID) {
        guard activeSession?.sessionId == sessionId else { return }
        persistContext()
    }

    func notifyMatchFinished(
        sessionId: UUID,
        snapshot: LinkedScoreboardSnapshot,
        recordId: String,
        winnerSide: MatchSide?,
        manualEnd: Bool,
        startTime: Date? = nil,
        endTime: Date? = nil,
        totalScoreChanges: Int? = nil,
        participantNames: [String]? = nil
    ) {
        guard let currentSession = activeSession,
              currentSession.sessionId == sessionId,
              !publishedFinishedMatchIds.contains(currentSession.handle.matchId),
              !terminalOutbox.contains(
                  sessionId: sessionId,
                  matchId: currentSession.handle.matchId
              ),
              var machine = sessionMachine else { return }
        publishedFinishedMatchIds.insert(currentSession.handle.matchId)
        _ = machine.markFinished(matchId: currentSession.handle.matchId)
        _ = machine.advanceRevision()
        sessionMachine = machine
        synchronizeActiveSessionFromStateMachine()
        guard let session = activeSession else { return }
        sequence += 1
        let messageId = UUID()
        let end = endTime ?? Date()
        let start = startTime ?? end.addingTimeInterval(-60)
        let duration = max(1, end.timeIntervalSince(start))
        let envelope = LinkEnvelope(
            messageId: messageId,
            sessionId: sessionId,
            matchId: session.handle.matchId,
            matchGeneration: session.handle.matchGeneration,
            authorityEpoch: session.authorityEpoch,
            kind: .matchFinished,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: session.revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkMatchFinishedPayload(
                snapshot: snapshot,
                recordId: recordId,
                winnerSide: winnerSide,
                manualEnd: manualEnd,
                startTimeEpochMilliseconds: Int64(start.timeIntervalSince1970 * 1000),
                endTimeEpochMilliseconds: Int64(end.timeIntervalSince1970 * 1000),
                durationSeconds: duration,
                totalScoreChanges: totalScoreChanges ?? 0,
                detailedActions: mergedDetailedActions,
                participantNames: participantNames ?? []
            )
        )
        sessionMachine?.registerPendingAcknowledgement(messageId)
        Task {
            do {
                let data = try JSONEncoder().encode(envelope)
                terminalOutbox.enqueue(.init(
                    messageId: messageId,
                    handle: session.handle,
                    data: data,
                    lastSentAtEpochMilliseconds: nowMs()
                ))
                persistTerminalOutbox()
                persistContext()
                try transport.enqueueDurable(data)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Private

    private func startInteractiveSession(
        gameType: ScoreCore.GameType,
        maxSets: Int? = nil,
        initialSnapshot: LinkedScoreboardSnapshot,
        participantNames: [String]? = nil
    ) async throws -> UUID {
        if setupContinuation != nil {
            trackSetupAnalyticsResult(.timeout)
        }
        setupAnalyticsGameType = GameType(scoreCoreGameType: gameType)?.analyticsIdentifier
            ?? String(describing: gameType).lowercased()
        didTrackSetupAnalyticsResult = false
        AppAnalytics.track(.watchLinkStart, parameters: [
            .gameType: .string(setupAnalyticsGameType ?? "unknown"),
            .entryPoint: .string(AnalyticsEntryPoint.watchLink.rawValue),
            .sourceSurface: .string(AnalyticsSourceSurface.phone.rawValue)
        ])
        guard Self.phoneInteractiveStartSupported(gameType) else {
            trackSetupAnalyticsResult(.notReachable)
            throw InteractiveStartError.watchUnavailable
        }
        do {
            try validateInteractiveWatchAvailability()
        } catch {
            trackSetupAnalyticsResult(.notReachable)
            throw error
        }
        if setupContinuation != nil {
            let continuation = setupContinuation
            setupContinuation = nil
            if let existing = activeSession?.sessionId {
                leaveSession(existing)
            } else {
                clearSession()
            }
            continuation?.resume(throwing: InteractiveStartError.setupTimedOut)
        }
        setupTimeoutTask?.cancel()

        let sessionId = UUID()
        let setup = LinkedScoreboardSetup(
            gameType: gameType,
            maxSets: maxSets,
            initialSnapshot: initialSnapshot,
            participantNames: participantNames ?? []
        )
        if let existing = activeSession?.sessionId {
            leaveSession(existing)
        }
        activeSession = ActiveSession(
            handle: LinkedMatchHandle(sessionId: sessionId),
            gameType: gameType,
            revision: 0,
            role: .phoneFollower,
            authorityEpoch: 0,
            setup: setup,
            completedMatchIds: []
        )
        if let session = activeSession {
            installStateMachine(from: session, lifecycle: .starting)
        }
        controlRole = .phoneFollower
        latestRemoteSnapshot = nil
        finishedRecordId = nil
        publishedFinishedMatchIds.removeAll()
        lastErrorMessage = nil
        if let handle = activeSession?.handle {
            _ = revisionGate.beginMatch(handle, initialRevision: 0)
        }
        persistContext()
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: sessionId,
            matchId: activeSession?.handle.matchId,
            matchGeneration: activeSession?.handle.matchGeneration ?? 1,
            authorityEpoch: 0,
            kind: .setupRequest,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: 0,
            sentAtEpochMilliseconds: nowMs(),
            payload: setup
        )
        pendingSetupMessageId = envelope.messageId
        _ = sessionMachine?.beginSetup(correlationId: envelope.messageId)
        return try await withCheckedThrowingContinuation { continuation in
            setupContinuation = continuation
            setupTimeoutTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(Self.setupTimeoutSeconds * 1_000_000_000))
                } catch {
                    return
                }
                await MainActor.run {
                    guard let self,
                          self.activeSession?.sessionId == sessionId,
                          let cont = self.setupContinuation else { return }
                    self.setupContinuation = nil
                    self.setupTimeoutTask = nil
                    self.trackSetupAnalyticsResult(.timeout)
                    self.leaveSession(sessionId)
                    cont.resume(throwing: InteractiveStartError.setupTimedOut)
                }
            }
            Task { [weak self] in
                guard let self else { return }
                do {
                    let data = try JSONEncoder().encode(envelope)
                    try self.transport.sendInteractive(data)
                } catch {
                    guard self.activeSession?.sessionId == sessionId,
                          let cont = self.setupContinuation else { return }
                    self.setupContinuation = nil
                    self.setupTimeoutTask?.cancel()
                    self.setupTimeoutTask = nil
                    self.clearSession()
                    if error as? WatchConnectivityTransportError == .peerNotReachable {
                        self.trackSetupAnalyticsResult(.notReachable)
                        cont.resume(throwing: InteractiveStartError.watchAppNotForeground)
                    } else {
                        self.trackSetupAnalyticsResult(.failed)
                        cont.resume(throwing: error)
                    }
                }
            }
        }
    }

    private static func phoneInteractiveStartSupported(_ gameType: ScoreCore.GameType) -> Bool {
        switch gameType {
        case .pingpong, .pingpongDoubles,
             .badminton, .badmintonDoubles,
             .tennis, .tennisDoubles,
             .pickleball, .pickleballDoubles,
             .archeryDual, .eightBall, .nineBall, .snooker:
            return true
        default:
            return false
        }
    }

    private func sendSnapshotIfController(
        sessionId: UUID,
        gameType: ScoreCore.GameType,
        snapshot: LinkedScoreboardSnapshot,
        detailedActions: [DetailedScoreAction]? = nil,
        participantNames: [String]? = nil
    ) {
        guard let currentSession = activeSession,
              currentSession.sessionId == sessionId,
              currentSession.gameType == gameType,
              currentSession.role == .phoneController,
              var machine = sessionMachine else { return }
        _ = machine.advanceRevision()
        sessionMachine = machine
        synchronizeActiveSessionFromStateMachine()
        guard var session = activeSession else { return }
        mergeDetailedActions(detailedActions)
        session.setup = LinkedScoreboardSetup(
            gameType: gameType,
            maxSets: maxSets(for: snapshot),
            initialSnapshot: snapshot,
            detailedActions: mergedDetailedActions,
            participantNames: participantNames ?? session.setup.participantNames
        )
        activeSession = session
        latestRemoteSnapshot = .init(
            sessionId: sessionId,
            revision: session.revision,
            snapshot: snapshot,
            detailedActions: mergedDetailedActions
        )
        persistContext()
        sequence += 1
        let messageId = UUID()
        let envelope = LinkEnvelope(
            messageId: messageId,
            sessionId: sessionId,
            matchId: session.handle.matchId,
            matchGeneration: session.handle.matchGeneration,
            authorityEpoch: session.authorityEpoch,
            kind: .stateSnapshot,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: session.revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkedScoreboardSetup(
                gameType: gameType,
                maxSets: maxSets(for: snapshot),
                initialSnapshot: snapshot,
                detailedActions: mergedDetailedActions,
                participantNames: session.setup.participantNames
            )
        )
        Task {
            do {
                let data = try JSONEncoder().encode(envelope)
                sessionMachine?.registerPendingAcknowledgement(messageId)
                pendingAck.enqueue(.init(
                    messageId: messageId,
                    sessionId: sessionId,
                    revision: session.revision,
                    data: data,
                    lastSentAtEpochMilliseconds: nowMs()
                ))
                try transport.publishLatestSnapshot(data)
                if transport.isReachable {
                    try await transport.sendRealtime(data)
                }
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func handleIncoming(_ data: Data) {
        if handleCommonNamesSyncRequest(data) { return }
        if handleConnectivityProbe(data) { return }
        if handleSetupResponse(data) { return }
        if handleAck(data) { return }
        if handleSnapshotFromWatch(data) { return }
        if handleTakeoverRelated(data) { return }
        if handleMatchFinishedFromWatch(data) { return }
        if handleScoreboardExitedToHome(data) { return }
        if handleWatchBackgrounded(data) { return }
        if handleResumeDiscarded(data) { return }
        if handleSessionLeft(data) { return }
        _ = handleStatus(data)
    }

    private func handleCommonNamesSyncRequest(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(
            LinkEnvelope<CommonNamesSyncRequestPayload>.self,
            from: data
        ), envelope.sender == .watch,
           envelope.kind == .commonNamesSyncRequest,
           envelope.protocolVersion == LinkProtocol.currentVersion else { return false }
        pushCommonNamesToWatch()
        return true
    }

    private func handleConnectivityProbe(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(
            LinkEnvelope<ConnectivityProbePayload>.self,
            from: data
        ), envelope.sender == .watch,
           envelope.kind == .connectivityProbe,
           envelope.protocolVersion == LinkProtocol.currentVersion,
           envelope.sessionId == envelope.payload.probeId else { return false }
        sequence += 1
        let response = LinkEnvelope(
            sessionId: envelope.sessionId,
            kind: .connectivityProbeResponse,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: 0,
            sentAtEpochMilliseconds: nowMs(),
            payload: envelope.payload
        )
        do {
            let responseData = try JSONEncoder().encode(response)
            try transport.sendInteractive(responseData)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        return true
    }

    private func handleSetupResponse(_ data: Data) -> Bool {
        if let accepted = try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: data),
           accepted.kind == .setupAccepted,
           accepted.sender == .watch,
           accepted.handle == activeSession?.handle,
           accepted.correlationId == pendingSetupMessageId,
           accepted.authorityEpoch == activeSession?.authorityEpoch {
            setupTimeoutTask?.cancel()
            setupTimeoutTask = nil
            if let correlationId = accepted.correlationId,
               var machine = sessionMachine,
               machine.resolveSetup(
                   correlationId: correlationId,
                   acceptedRole: .phoneFollower
               ) {
                sessionMachine = machine
                synchronizeActiveSessionFromStateMachine()
            }
            if let session = activeSession,
               let snapshot = session.setup.initialSnapshot {
                latestRemoteSnapshot = .init(
                    sessionId: session.sessionId,
                    revision: session.revision,
                    snapshot: snapshot,
                    detailedActions: session.setup.detailedActions
                )
            }
            pendingSetupMessageId = nil
            persistContext()
            trackSetupAnalyticsResult(.success)
            setupContinuation?.resume(returning: accepted.sessionId)
            setupContinuation = nil
            return true
        }
        if let rejected = try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: data),
           rejected.kind == .setupRejected,
           rejected.sender == .watch,
           rejected.handle == activeSession?.handle,
           rejected.correlationId == pendingSetupMessageId {
            setupTimeoutTask?.cancel()
            setupTimeoutTask = nil
            if let correlationId = rejected.correlationId,
               var machine = sessionMachine {
                _ = machine.resolveSetup(
                    correlationId: correlationId,
                    acceptedRole: nil
                )
                sessionMachine = machine
            }
            clearSession()
            pendingSetupMessageId = nil
            trackSetupAnalyticsResult(.rejected)
            setupContinuation?.resume(throwing: InteractiveStartError.setupRejected)
            setupContinuation = nil
            return true
        }
        return false
    }

    private func handleAck(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkAcknowledgementPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .acknowledgement || envelope.kind == .recordAcknowledgement,
              envelope.correlationId == envelope.payload.acknowledgedMessageId else {
            return false
        }
        let acknowledgedMessageId = envelope.payload.acknowledgedMessageId
        _ = pendingAck.acknowledge(messageId: acknowledgedMessageId)
        if var machine = sessionMachine {
            _ = machine.acknowledge(messageId: acknowledgedMessageId)
            sessionMachine = machine
        }
        let terminalCandidate = terminalOutbox.items.first {
            $0.messageId == acknowledgedMessageId
        }
        let terminalItem: LinkDurableOutbox.Item?
        if let terminalCandidate,
           envelope.kind == .recordAcknowledgement,
           envelope.handle == terminalCandidate.handle {
            terminalItem = terminalOutbox.acknowledge(messageId: acknowledgedMessageId)
        } else {
            terminalItem = nil
        }
        if terminalItem != nil {
            persistTerminalOutbox()
            persistContext()
            flushPendingSessionEnds()
        }
        if acknowledgedMessageId == pendingTakeoverMessageId,
           let session = activeSession,
           session.handle == envelope.handle,
           var machine = sessionMachine,
           machine.prepareAuthorityTransfer(
               correlationId: acknowledgedMessageId,
               epoch: envelope.authorityEpoch
           ) {
            pendingTakeoverMessageId = nil
            _ = machine.accept(
                handle: envelope.handle,
                authorityEpoch: envelope.authorityEpoch,
                revision: envelope.payload.acknowledgedRevision
            )
            if let snapshot = envelope.payload.authoritativeSnapshot,
               snapshot.rallyState != nil || snapshot.tennisState != nil
                    || snapshot.eightBallState != nil || snapshot.nineBallState != nil
                    || snapshot.snookerState != nil || snapshot.archeryState != nil {
                mergeDetailedActions(envelope.payload.detailedActions)
                pendingTakeoverApplication = .init(
                    messageId: acknowledgedMessageId,
                    sessionId: envelope.sessionId,
                    revision: envelope.payload.acknowledgedRevision,
                    snapshot: snapshot,
                    detailedActions: mergedDetailedActions
                )
                latestRemoteSnapshot = .init(
                    sessionId: envelope.sessionId,
                    revision: envelope.payload.acknowledgedRevision,
                    snapshot: snapshot,
                    detailedActions: mergedDetailedActions
                )
                _ = machine.commitAuthorityTransfer(
                    correlationId: acknowledgedMessageId
                )
            } else {
                _ = machine.commitAuthorityTransfer(
                    correlationId: acknowledgedMessageId
                )
            }
            sessionMachine = machine
            synchronizeActiveSessionFromStateMachine()
            persistContext()
        }
        if acknowledgedMessageId == pendingReclaimGrantMessageId,
           activeSession?.handle == envelope.handle,
           var machine = sessionMachine,
           envelope.authorityEpoch == machine.authorityEpoch,
           machine.commitAuthorityTransfer(
               correlationId: acknowledgedMessageId
           ) {
            pendingReclaimGrantMessageId = nil
            sessionMachine = machine
            synchronizeActiveSessionFromStateMachine()
            persistContext()
        }
        return true
    }

    private func handleSnapshotFromWatch(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkedScoreboardSetup>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .stateSnapshot,
              let snapshot = envelope.payload.initialSnapshot,
              let session = activeSession,
              session.sessionId == envelope.sessionId,
              session.gameType == envelope.payload.gameType,
              var machine = sessionMachine else {
            return false
        }

        let previousHandle = machine.handle
        let validation = machine.accept(
            handle: envelope.handle,
            authorityEpoch: envelope.authorityEpoch,
            revision: envelope.sessionRevision
        )
        guard validation == .current || validation == .duplicateOrOlder else {
            return false
        }
        let beganNewMatch = machine.handle != previousHandle
        sessionMachine = machine
        synchronizeActiveSessionFromStateMachine()

        if beganNewMatch {
            if var newSession = activeSession {
                newSession.setup = envelope.payload
                activeSession = newSession
            }
            finishedRecordId = nil
            mergedDetailedActions = []
            latestRemoteSnapshot = nil
            watchBackgrounded = false
            _ = revisionGate.beginMatch(
                envelope.handle,
                initialRevision: envelope.sessionRevision
            )
        } else if validation == .current {
            _ = revisionGate.classify(
                handle: envelope.handle,
                revision: envelope.sessionRevision
            )
        }

        if validation == .current, var session = activeSession {
            session.setup = envelope.payload
            activeSession = session
            mergeDetailedActions(envelope.payload.detailedActions)
            latestRemoteSnapshot = LinkedSnapshotUpdate(
                sessionId: envelope.sessionId,
                revision: envelope.sessionRevision,
                snapshot: snapshot,
                detailedActions: mergedDetailedActions
            )
            // Watch resumed scoring — clear the background-interruption flag.
            watchBackgrounded = false
            persistContext()
        }
        // ACK valid duplicates too: a retry usually means our prior ACK was lost.
        sendAck(
            sessionId: envelope.sessionId,
            messageId: envelope.messageId,
            revision: envelope.sessionRevision,
            handle: envelope.handle,
            authorityEpoch: envelope.authorityEpoch
        )
        return true
    }

    private func handleTakeoverRelated(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkAuthorityTransferPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.handle == activeSession?.handle,
              envelope.authorityEpoch >= activeSession?.authorityEpoch ?? 0 else { return false }
        switch envelope.kind {
        case .reclaimRequest:
            guard activeSession?.role == .phoneController else {
                sequence += 1
                let denied = LinkEnvelope(
                    correlationId: envelope.messageId,
                    sessionId: envelope.sessionId,
                    matchId: envelope.matchId,
                    matchGeneration: envelope.matchGeneration,
                    authorityEpoch: activeSession?.authorityEpoch
                        ?? envelope.authorityEpoch,
                    kind: .reclaimDenied,
                    sender: .phone,
                    senderSequence: sequence,
                    sessionRevision: activeSession?.revision ?? envelope.sessionRevision,
                    sentAtEpochMilliseconds: nowMs(),
                    payload: LinkAuthorityTransferPayload(
                        baseRevision: activeSession?.revision ?? envelope.sessionRevision
                    )
                )
                sendReportingError(denied)
                return true
            }
            pendingReclaimRequest = .init(
                messageId: envelope.messageId,
                sessionId: envelope.sessionId,
                revision: envelope.sessionRevision
            )
            reclaimTimeoutTask?.cancel()
            reclaimTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.resolveReclaimRequest(
                        accepted: false,
                        snapshot: nil,
                        detailedActions: []
                    )
                }
            }
            return true
        case .reclaimAccepted, .reclaimDenied:
            return true
        default:
            return false
        }
    }

    private func handleMatchFinishedFromWatch(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkMatchFinishedPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .matchFinished,
              let session = activeSession,
              envelope.sessionId == session.sessionId,
              envelope.matchGeneration <= session.handle.matchGeneration else {
            return false
        }
        let isCurrentMatch = envelope.handle == session.handle
        guard !isCurrentMatch || envelope.authorityEpoch >= session.authorityEpoch else {
            return false
        }

        if session.completedMatchIds.contains(envelope.matchId) {
            sendAck(
                sessionId: envelope.sessionId,
                messageId: envelope.messageId,
                revision: envelope.sessionRevision,
                handle: envelope.handle,
                authorityEpoch: envelope.authorityEpoch,
                recordAck: true
            )
            return true
        }

        if isCurrentMatch {
            guard var machine = sessionMachine else { return false }
            let validation = machine.accept(
                handle: envelope.handle,
                authorityEpoch: envelope.authorityEpoch,
                revision: envelope.sessionRevision
            )
            guard validation == .current || validation == .duplicateOrOlder else {
                return false
            }
            sessionMachine = machine
            synchronizeActiveSessionFromStateMachine()
            _ = revisionGate.classify(
                handle: envelope.handle,
                revision: envelope.sessionRevision
            )
            mergeDetailedActions(envelope.payload.detailedActions)
            latestRemoteSnapshot = LinkedSnapshotUpdate(
                sessionId: envelope.sessionId,
                revision: envelope.sessionRevision,
                snapshot: envelope.payload.snapshot,
                detailedActions: mergedDetailedActions
            )
        }

        do {
            finishedRecordId = try recordSink.ingest(
                payload: envelope.payload,
                gameType: session.gameType,
                matchId: envelope.matchId
            )
            if var machine = sessionMachine {
                _ = machine.markFinished(matchId: envelope.matchId)
                sessionMachine = machine
                synchronizeActiveSessionFromStateMachine()
            }
            persistContext()
        } catch {
            // Do not ACK a record that was not saved. The watch retains the
            // stable message and retries instead of silently losing the match.
            lastErrorMessage = error.localizedDescription
            return true
        }
        sendAck(
            sessionId: envelope.sessionId,
            messageId: envelope.messageId,
            revision: envelope.sessionRevision,
            handle: envelope.handle,
            authorityEpoch: envelope.authorityEpoch,
            recordAck: true
        )
        return true
    }

    private func handleSessionLeft(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .sessionLeft,
              envelope.sessionId == activeSession?.sessionId else { return false }
        let pendingCount = pendingSessionEnds.count
        pendingSessionEnds.removeAll { $0.handle.sessionId == envelope.sessionId }
        if pendingSessionEnds.count != pendingCount {
            persistPendingSessionEnds()
        }
        clearSession()
        return true
    }

    private func handleScoreboardExitedToHome(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .scoreboardExitedToHome,
              envelope.sessionId == activeSession?.sessionId else { return false }
        // Keep the watch as controller while its resumable game is on the home screen.
        persistContext()
        return true
    }

    private func handleWatchBackgrounded(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .watchBackgrounded,
              envelope.sessionId == activeSession?.sessionId else { return false }
        watchBackgrounded = true
        persistContext()
        return true
    }

    private func handleResumeDiscarded(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkResumeDiscardPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .resumeDiscarded,
              envelope.sessionId == activeSession?.sessionId else { return false }
        if var machine = sessionMachine {
            _ = machine.accept(
                handle: envelope.handle,
                authorityEpoch: envelope.authorityEpoch,
                revision: envelope.sessionRevision
            )
            _ = machine.adoptAuthority(
                role: .phoneController,
                epoch: envelope.authorityEpoch
            )
            sessionMachine = machine
            synchronizeActiveSessionFromStateMachine()
        }
        persistContext()
        return true
    }

    private func handleStatus(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkStatusPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .statusResponse,
              envelope.correlationId == pendingStatusCorrelationId,
              let session = activeSession,
              envelope.sessionId == session.sessionId,
              envelope.handle == session.handle,
              envelope.authorityEpoch == session.authorityEpoch else { return false }
        pendingStatusCorrelationId = nil
        statusTimeoutTask?.cancel()
        statusTimeoutTask = nil
        if var machine = sessionMachine {
            _ = machine.accept(
                handle: envelope.handle,
                authorityEpoch: envelope.authorityEpoch,
                revision: envelope.payload.revision
            )
            let localRole: LinkControlRole
            switch envelope.payload.role {
            case .watchController:
                localRole = .phoneFollower
            case .watchFollower:
                localRole = .phoneController
            case .phoneController, .phoneFollower:
                localRole = machine.role
            }
            _ = machine.adoptAuthority(
                role: localRole,
                epoch: envelope.authorityEpoch
            )
            sessionMachine = machine
            synchronizeActiveSessionFromStateMachine()
            persistContext()
        }
        let continuation = statusContinuation
        statusContinuation = nil
        continuation?.resume(returning: envelope.payload)
        return true
    }

    private func handleConnectivityStatusChange(_ status: WatchConnectivityStatus) {
        connectivityStatus = status
        pushCommonNamesToWatch()
        guard status.isReachable else { return }
        flushPendingSessionEnds()
        requestStatusForActiveSession()
    }

    private func requestStatusForActiveSession() {
        guard activeSession != nil else { return }
        Task {
            do {
                _ = try await queryStatus(timeoutSeconds: 3)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func sendAck(
        sessionId: UUID,
        messageId: UUID,
        revision: UInt64,
        handle: LinkedMatchHandle? = nil,
        authorityEpoch: UInt64? = nil,
        recordAck: Bool = false
    ) {
        let resolvedHandle = handle
            ?? activeSession?.handle
            ?? LinkedMatchHandle(sessionId: sessionId, matchId: sessionId)
        sequence += 1
        let envelope = LinkEnvelope(
            correlationId: messageId,
            sessionId: sessionId,
            matchId: resolvedHandle.matchId,
            matchGeneration: resolvedHandle.matchGeneration,
            authorityEpoch: authorityEpoch
                ?? activeSession?.authorityEpoch
                ?? 0,
            kind: recordAck ? .recordAcknowledgement : .acknowledgement,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkAcknowledgementPayload(
                acknowledgedMessageId: messageId,
                acknowledgedRevision: revision
            )
        )
        sendReportingError(envelope)
    }

    private func sendReportingError<Payload: Codable & Sendable>(
        _ envelope: LinkEnvelope<Payload>
    ) {
        Task {
            do {
                try await sendEnvelope(envelope)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func sendEnvelope<Payload: Codable & Sendable>(_ envelope: LinkEnvelope<Payload>) async throws {
        let data = try JSONEncoder().encode(envelope)
        switch envelope.kind {
        case .stateSnapshot:
            try transport.publishLatestSnapshot(data)
            if transport.isReachable {
                try await transport.sendRealtime(data)
            }
        case .matchFinished:
            try transport.enqueueDurable(data)
        default:
            try await transport.sendRealtime(data)
        }
    }

    private func startAckRetryLoop() {
        ackRetryTask?.cancel()
        ackRetryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    guard let self else { return }
                    let pendingMessageId = self.pendingAck.pending?.messageId
                    let authorityTransferPending = pendingMessageId == self.pendingTakeoverMessageId
                        || pendingMessageId == self.pendingReclaimGrantMessageId
                    if let data = self.pendingAck.retryIfDue(
                        nowEpochMilliseconds: self.nowMs()
                    ) {
                        Task {
                            do {
                                try await self.transport.sendRealtime(data)
                            } catch {
                                self.lastErrorMessage = error.localizedDescription
                            }
                        }
                    } else if let pendingMessageId,
                              self.pendingAck.pending == nil {
                        if var machine = self.sessionMachine {
                            _ = machine.acknowledge(messageId: pendingMessageId)
                            if authorityTransferPending {
                                _ = machine.rejectAuthorityTransfer(
                                    correlationId: pendingMessageId
                                )
                            }
                            self.sessionMachine = machine
                            self.synchronizeActiveSessionFromStateMachine()
                        }
                        if self.pendingTakeoverMessageId == pendingMessageId {
                            self.pendingTakeoverMessageId = nil
                        }
                        if self.pendingReclaimGrantMessageId == pendingMessageId {
                            self.pendingReclaimGrantMessageId = nil
                        }
                        self.lastErrorMessage = authorityTransferPending
                            ? InteractiveStartError.authorityTransferTimedOut.localizedDescription
                            : NSLocalizedString(
                                "linked_score_sync_timeout",
                                value: "比分同步超时，将在重新连接后继续同步。",
                                comment: ""
                            )
                        self.persistContext()
                    }
                    let dueTerminalData = self.terminalOutbox.retryDue(
                        nowEpochMilliseconds: self.nowMs()
                    )
                    if !dueTerminalData.isEmpty {
                        self.persistTerminalOutbox()
                        for data in dueTerminalData {
                            do {
                                try self.transport.enqueueDurable(data)
                            } catch {
                                self.lastErrorMessage = error.localizedDescription
                            }
                        }
                    }
                    self.flushPendingSessionEnds()
                }
            }
        }
    }

    private func clearSession() {
        sessionMachine?.endSession()
        if let id = activeSession?.sessionId {
            revisionGate.endSession(id)
        }
        activeSession = nil
        sessionMachine = nil
        controlRole = nil
        pendingTakeoverMessageId = nil
        pendingReclaimGrantMessageId = nil
        pendingReclaimRequest = nil
        pendingTakeoverApplication = nil
        forceTakeoverConfirmationSessionId = nil
        pendingStatusCorrelationId = nil
        statusTimeoutTask?.cancel()
        statusTimeoutTask = nil
        let statusContinuation = statusContinuation
        self.statusContinuation = nil
        statusContinuation?.resume(throwing: CancellationError())
        reclaimTimeoutTask?.cancel()
        reclaimTimeoutTask = nil
        pendingAck.clear()
        latestRemoteSnapshot = nil
        mergedDetailedActions = []
        publishedFinishedMatchIds.removeAll()
        watchBackgrounded = false
        persistContext()
    }

    private func installStateMachine(
        from session: ActiveSession,
        lifecycle: LinkSessionStateMachine.Lifecycle = .active
    ) {
        sessionMachine = LinkSessionStateMachine(
            handle: session.handle,
            role: session.role,
            authorityEpoch: session.authorityEpoch,
            revision: session.revision,
            completedMatchIds: session.completedMatchIds,
            lifecycle: lifecycle,
            pendingAcknowledgementIds: Set(
                pendingAck.pending.map { [$0.messageId] } ?? []
            )
                .union(terminalOutbox.items.map(\.messageId))
        )
    }

    private func synchronizeActiveSessionFromStateMachine() {
        guard let machine = sessionMachine,
              var session = activeSession,
              session.sessionId == machine.handle.sessionId else { return }
        session.handle = machine.handle
        session.revision = machine.revision
        session.role = machine.role
        session.authorityEpoch = machine.authorityEpoch
        session.completedMatchIds = machine.completedMatchIds
        activeSession = session
        controlRole = machine.role
    }

    private func trackSetupAnalyticsResult(_ result: AnalyticsResult) {
        guard !didTrackSetupAnalyticsResult else { return }
        didTrackSetupAnalyticsResult = true
        AppAnalytics.track(.watchLinkResult, parameters: [
            .gameType: .string(setupAnalyticsGameType ?? "unknown"),
            .entryPoint: .string(AnalyticsEntryPoint.watchLink.rawValue),
            .sourceSurface: .string(AnalyticsSourceSurface.phone.rawValue),
            .result: .string(result.rawValue)
        ])
    }

    private func nowMs() -> Int64 {
        clock.nowEpochMilliseconds()
    }

    private func persistTerminalOutbox() {
        guard !terminalOutbox.isEmpty else {
            outboxStore.removeObject(forKey: terminalOutboxKey)
            return
        }
        do {
            let data = try JSONEncoder().encode(terminalOutbox)
            outboxStore.set(data, forKey: terminalOutboxKey)
        } catch {
            reportPersistenceError(error)
        }
    }

    private func persistPendingSessionEnds() {
        guard !pendingSessionEnds.isEmpty else {
            outboxStore.removeObject(forKey: pendingSessionEndsKey)
            return
        }
        do {
            let data = try JSONEncoder().encode(pendingSessionEnds)
            outboxStore.set(data, forKey: pendingSessionEndsKey)
        } catch {
            reportPersistenceError(error)
        }
    }

    private func flushPendingSessionEnds() {
        for request in pendingSessionEnds {
            let sessionId = request.handle.sessionId
            guard !pendingSessionEndInFlight.contains(sessionId),
                  !terminalOutbox.items.contains(where: {
                      $0.handle.sessionId == sessionId
                  }) else {
                continue
            }
            pendingSessionEndInFlight.insert(sessionId)
            sequence += 1
            let envelope = LinkEnvelope(
                sessionId: sessionId,
                matchId: request.handle.matchId,
                matchGeneration: request.handle.matchGeneration,
                authorityEpoch: request.authorityEpoch,
                kind: .sessionLeft,
                sender: .phone,
                senderSequence: sequence,
                sessionRevision: request.revision,
                sentAtEpochMilliseconds: nowMs(),
                payload: EmptyLinkPayload()
            )
            Task {
                defer { pendingSessionEndInFlight.remove(sessionId) }
                do {
                    try await sendEnvelope(envelope)
                    pendingSessionEnds.removeAll {
                        $0.handle.sessionId == sessionId
                    }
                    persistPendingSessionEnds()
                    if activeSession?.sessionId == sessionId {
                        clearSession()
                    }
                } catch {
                    lastErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func mergeDetailedActions(_ incoming: [DetailedScoreAction]?) {
        guard let incoming, !incoming.isEmpty else { return }
        mergedDetailedActions = incoming.sorted {
            ($0.epochMilliseconds ?? 0, $0.id.uuidString) < ($1.epochMilliseconds ?? 0, $1.id.uuidString)
        }
    }

    private func maxSets(for snapshot: LinkedScoreboardSnapshot) -> Int? {
        switch snapshot {
        case .rally(let state): return state.rules.maxSets
        case .tennis(let state): return state.rules.maxSets
        default: return nil
        }
    }

    private func persistContext() {
        guard let session = activeSession else {
            contextStore.removeObject(forKey: contextKey)
            return
        }
        let context = PhoneLinkResumeContext(
            handle: session.handle,
            setup: session.setup,
            role: session.role,
            authorityEpoch: session.authorityEpoch,
            revision: session.revision,
            latestAuthoritativeSnapshot: latestRemoteSnapshot?.snapshot
                ?? session.setup.initialSnapshot,
            detailedActions: mergedDetailedActions,
            completedMatchIds: session.completedMatchIds,
            pendingTerminalMessageIds: Set(terminalOutbox.items.map(\.messageId))
        )
        do {
            let data = try JSONEncoder().encode(context)
            contextStore.set(data, forKey: contextKey)
        } catch {
            reportPersistenceError(error)
        }
    }

    private func reportPersistenceError(_ error: Error) {
        lastErrorMessage = String(
            format: NSLocalizedString(
                "linked_score_persistence_failed",
                value: "无法保存联动恢复数据：%@",
                comment: ""
            ),
            error.localizedDescription
        )
    }

    private func restoreContext() {
        guard let data = contextStore.data(forKey: contextKey),
              let context = try? JSONDecoder().decode(
                PhoneLinkResumeContext.self,
                from: data
              ) else {
            contextStore.removeObject(forKey: contextKey)
            return
        }
        activeSession = ActiveSession(
            handle: context.handle,
            gameType: context.setup.gameType,
            revision: context.revision,
            role: context.role,
            authorityEpoch: context.authorityEpoch,
            setup: context.setup,
            completedMatchIds: context.completedMatchIds
        )
        if let session = activeSession {
            installStateMachine(from: session)
            synchronizeActiveSessionFromStateMachine()
        }
        mergedDetailedActions = context.detailedActions
        publishedFinishedMatchIds = context.completedMatchIds
        if let snapshot = context.latestAuthoritativeSnapshot {
            latestRemoteSnapshot = LinkedSnapshotUpdate(
                sessionId: context.handle.sessionId,
                revision: context.revision,
                snapshot: snapshot,
                detailedActions: context.detailedActions
            )
        }
        _ = revisionGate.beginMatch(
            context.handle,
            initialRevision: context.revision
        )
    }
}
