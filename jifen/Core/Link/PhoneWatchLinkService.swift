import Foundation
import LinkCore
import Observation
import RecordCore
import ScoreCore

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

    private struct ActiveSession {
        let sessionId: UUID
        let gameType: ScoreCore.GameType
        var revision: UInt64
        var role: LinkControlRole
        var setup: LinkedScoreboardSetup
    }

    private let transport = WatchConnectivityTransport()
    private var sequence: UInt64 = 0
    private var activeSession: ActiveSession?
    private var pendingAck = LinkPendingAckQueue()
    private var terminalPendingAck = LinkPendingAckQueue()
    private var setupContinuation: CheckedContinuation<UUID, Error>?
    private var setupTimeoutTask: Task<Void, Never>?
    private var setupAnalyticsGameType: String?
    private var didTrackSetupAnalyticsResult = false
    private var ackRetryTask: Task<Void, Never>?
    private var revisionGate = LinkRevisionGate()
    private var pendingTakeoverMessageId: UUID?
    private var pendingReclaimGrantMessageId: UUID?
    private var reclaimTimeoutTask: Task<Void, Never>?
    private var mergedDetailedActions: [DetailedScoreAction] = []
    private var publishedFinishedRecordId: String?
    private let terminalOutboxKey = "phone_link_terminal_outbox_v1"
    private var pendingLeaveAfterFinish = false

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
            }
        }
    }

    struct LinkedSnapshotUpdate: Equatable {
        let sessionId: UUID
        let revision: UInt64
        let snapshot: LinkedScoreboardSnapshot
        let detailedActions: [DetailedScoreAction]
    }

    init() {
        connectivityStatus = transport.status
        if let data = UserDefaults.standard.data(forKey: terminalOutboxKey),
           let item = try? JSONDecoder().decode(LinkPendingAckQueue.PendingItem.self, from: data) {
            terminalPendingAck.enqueue(item)
            pendingLeaveAfterFinish = true
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
        guard let acknowledgementData = try? JSONEncoder().encode(acknowledgement) else { return }
        do {
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
            sessionId: session.sessionId,
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
            basketballThreeXThree: isThreeXThree(snapshot),
            initialSnapshot: snapshot,
            participantNames: participantNames
        )
    }

    func syncWatch(
        sessionId: UUID,
        state: BasketballMatchState,
        detailedActions: [DetailedScoreAction]? = nil
    ) {
        let gameType: ScoreCore.GameType = state.gameMode == .threeXThree ? .threeBasketball : .basketball
        sendSnapshotIfController(sessionId: sessionId, gameType: gameType, snapshot: .basketball(state), detailedActions: detailedActions)
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
        guard activeSession?.sessionId == sessionId,
              activeSession?.gameType == gameType,
              activeSession?.role == .phoneController else { return }
        publishedFinishedRecordId = nil
        finishedRecordId = nil
        mergedDetailedActions.removeAll()
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
              connectivityStatus.canStartInteractiveSession else {
            throw InteractiveStartError.watchUnavailable
        }
        sequence += 1
        let messageId = UUID()
        let update = latestRemoteSnapshot
        let envelope = LinkEnvelope(
            messageId: messageId,
            sessionId: sessionId,
            kind: .takeoverByPhone,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: session.revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkAuthorityTransferPayload(
                snapshot: update?.sessionId == sessionId ? update?.snapshot : nil,
                detailedActions: update?.sessionId == sessionId ? update?.detailedActions : nil,
                baseRevision: session.revision
            )
        )
        let data = try JSONEncoder().encode(envelope)
        pendingTakeoverMessageId = messageId
        pendingAck.enqueue(.init(
            messageId: messageId,
            sessionId: sessionId,
            revision: session.revision,
            data: data,
            lastSentAtEpochMilliseconds: nowMs()
        ))
        do {
            try await transport.send(data)
        } catch {
            _ = pendingAck.acknowledge(messageId: messageId)
            pendingTakeoverMessageId = nil
            throw error
        }
    }

    func resolveReclaimRequest(
        accepted: Bool,
        snapshot: LinkedScoreboardSnapshot?,
        detailedActions: [DetailedScoreAction]
    ) {
        guard let request = pendingReclaimRequest,
              var session = activeSession,
              session.sessionId == request.sessionId,
              session.role == .phoneController else { return }
        reclaimTimeoutTask?.cancel()
        reclaimTimeoutTask = nil
        pendingReclaimRequest = nil
        sequence += 1

        if !accepted || snapshot == nil {
            let envelope = LinkEnvelope(
                sessionId: request.sessionId,
                kind: .reclaimDenied,
                sender: .phone,
                senderSequence: sequence,
                sessionRevision: session.revision,
                sentAtEpochMilliseconds: nowMs(),
                payload: LinkAuthorityTransferPayload(baseRevision: session.revision)
            )
            Task { try? await sendEnvelope(envelope) }
            return
        }

        session.revision += 1
        activeSession = session
        let messageId = UUID()
        let envelope = LinkEnvelope(
            messageId: messageId,
            sessionId: request.sessionId,
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
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        pendingReclaimGrantMessageId = messageId
        pendingAck.enqueue(.init(
            messageId: messageId,
            sessionId: request.sessionId,
            revision: session.revision,
            data: data,
            lastSentAtEpochMilliseconds: nowMs()
        ))
        Task { try? await transport.send(data) }
    }

    func completePhoneTakeover(messageId: UUID) {
        guard let pending = pendingTakeoverApplication,
              pending.messageId == messageId,
              var session = activeSession,
              session.sessionId == pending.sessionId else { return }
        pendingTakeoverApplication = nil
        session.revision = max(session.revision, pending.revision)
        session.role = .phoneController
        activeSession = session
        latestRemoteSnapshot = .init(
            sessionId: pending.sessionId,
            revision: pending.revision,
            snapshot: pending.snapshot,
            detailedActions: pending.detailedActions
        )
        controlRole = .phoneController
        watchBackgrounded = false
    }

    func leaveSession(_ sessionId: UUID) {
        guard activeSession?.sessionId == sessionId else { return }
        if terminalPendingAck.pending?.sessionId == sessionId {
            pendingLeaveAfterFinish = true
            return
        }
        sendSessionLeftAndClear(sessionId)
    }

    private func sendSessionLeftAndClear(_ sessionId: UUID) {
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: sessionId,
            kind: .sessionLeft,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: activeSession?.revision ?? 0,
            sentAtEpochMilliseconds: nowMs(),
            payload: EmptyLinkPayload()
        )
        Task { try? await sendEnvelope(envelope) }
        if activeSession?.sessionId == sessionId {
            clearSession()
        }
    }

    func endWatchSession(_ sessionId: UUID) {
        leaveSession(sessionId)
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
        guard var session = activeSession,
              session.sessionId == sessionId,
              publishedFinishedRecordId == nil,
              terminalPendingAck.pending?.sessionId != sessionId else { return }
        publishedFinishedRecordId = recordId
        session.revision += 1
        activeSession = session
        sequence += 1
        let messageId = UUID()
        let end = endTime ?? Date()
        let start = startTime ?? end.addingTimeInterval(-60)
        let duration = max(1, end.timeIntervalSince(start))
        let envelope = LinkEnvelope(
            messageId: messageId,
            sessionId: sessionId,
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
                totalScoreChanges: totalScoreChanges,
                detailedActions: mergedDetailedActions,
                participantNames: participantNames
            )
        )
        Task {
            guard let data = try? JSONEncoder().encode(envelope) else { return }
            terminalPendingAck.enqueue(.init(
                messageId: messageId,
                sessionId: sessionId,
                revision: session.revision,
                data: data,
                lastSentAtEpochMilliseconds: nowMs()
            ))
            persistTerminalOutbox()
            try? await transport.send(data)
        }
    }

    // MARK: - Private

    private func startInteractiveSession(
        gameType: ScoreCore.GameType,
        maxSets: Int? = nil,
        basketballThreeXThree: Bool = false,
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
            basketballThreeXThree: basketballThreeXThree,
            initialSnapshot: initialSnapshot,
            participantNames: participantNames
        )
        if let existing = activeSession?.sessionId {
            leaveSession(existing)
        }
        activeSession = ActiveSession(
            sessionId: sessionId,
            gameType: gameType,
            revision: 0,
            role: .phoneFollower,
            setup: setup
        )
        controlRole = .phoneFollower
        latestRemoteSnapshot = nil
        finishedRecordId = nil
        publishedFinishedRecordId = nil
        if terminalPendingAck.pending == nil {
            pendingLeaveAfterFinish = false
        }
        lastErrorMessage = nil
        _ = revisionGate.beginSession(sessionId, initialRevision: 0)
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: sessionId,
            kind: .setupRequest,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: 0,
            sentAtEpochMilliseconds: nowMs(),
            payload: setup
        )
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
        guard var session = activeSession,
              session.sessionId == sessionId,
              session.gameType == gameType,
              session.role == .phoneController else { return }
        session.revision += 1
        mergeDetailedActions(detailedActions)
        session.setup = LinkedScoreboardSetup(
            gameType: gameType,
            maxSets: maxSets(for: snapshot),
            basketballThreeXThree: isThreeXThree(snapshot),
            initialSnapshot: snapshot,
            detailedActions: mergedDetailedActions,
            participantNames: participantNames ?? session.setup.participantNames
        )
        activeSession = session
        sequence += 1
        let messageId = UUID()
        let envelope = LinkEnvelope(
            messageId: messageId,
            sessionId: sessionId,
            kind: .stateSnapshot,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: session.revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkedScoreboardSetup(
                gameType: gameType,
                maxSets: maxSets(for: snapshot),
                basketballThreeXThree: isThreeXThree(snapshot),
                initialSnapshot: snapshot,
                detailedActions: mergedDetailedActions,
                participantNames: session.setup.participantNames
            )
        )
        Task {
            guard let data = try? JSONEncoder().encode(envelope) else { return }
            pendingAck.enqueue(.init(
                messageId: messageId,
                sessionId: sessionId,
                revision: session.revision,
                data: data,
                lastSentAtEpochMilliseconds: nowMs()
            ))
            try? await transport.send(data)
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
        guard let responseData = try? JSONEncoder().encode(response) else { return true }
        do {
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
           accepted.sessionId == activeSession?.sessionId {
            setupTimeoutTask?.cancel()
            setupTimeoutTask = nil
            if var session = activeSession {
                session.role = .phoneFollower
                activeSession = session
            }
            controlRole = .phoneFollower
            trackSetupAnalyticsResult(.success)
            setupContinuation?.resume(returning: accepted.sessionId)
            setupContinuation = nil
            return true
        }
        if let rejected = try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: data),
           rejected.kind == .setupRejected,
           rejected.sender == .watch,
           rejected.sessionId == activeSession?.sessionId {
            setupTimeoutTask?.cancel()
            setupTimeoutTask = nil
            clearSession()
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
              envelope.kind == .acknowledgement || envelope.kind == .recordAcknowledgement else {
            return false
        }
        let acknowledgedMessageId = envelope.payload.acknowledgedMessageId
        _ = pendingAck.acknowledge(messageId: acknowledgedMessageId)
        let terminalSessionId = terminalPendingAck.pending?.sessionId
        let terminalAcknowledged = terminalPendingAck.acknowledge(messageId: acknowledgedMessageId)
        if terminalAcknowledged {
            persistTerminalOutbox()
            if pendingLeaveAfterFinish, let sessionId = terminalSessionId {
                pendingLeaveAfterFinish = false
                sendSessionLeftAndClear(sessionId)
            }
        }
        if acknowledgedMessageId == pendingTakeoverMessageId,
           var session = activeSession,
           session.sessionId == envelope.sessionId {
            pendingTakeoverMessageId = nil
            if let snapshot = envelope.payload.authoritativeSnapshot,
               snapshot.rallyState != nil || snapshot.tennisState != nil
                    || snapshot.eightBallState != nil || snapshot.nineBallState != nil
                    || snapshot.snookerState != nil || snapshot.archeryState != nil {
                session.revision = max(session.revision, envelope.payload.acknowledgedRevision)
                activeSession = session
                mergeDetailedActions(envelope.payload.detailedActions)
                pendingTakeoverApplication = .init(
                    messageId: acknowledgedMessageId,
                    sessionId: envelope.sessionId,
                    revision: envelope.payload.acknowledgedRevision,
                    snapshot: snapshot,
                    detailedActions: mergedDetailedActions
                )
            } else {
                session.role = .phoneController
                activeSession = session
                controlRole = .phoneController
            }
        }
        if acknowledgedMessageId == pendingReclaimGrantMessageId,
           var session = activeSession,
           session.sessionId == envelope.sessionId {
            pendingReclaimGrantMessageId = nil
            session.role = .phoneFollower
            activeSession = session
            controlRole = .phoneFollower
        }
        return true
    }

    private func handleSnapshotFromWatch(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkedScoreboardSetup>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .stateSnapshot,
              let snapshot = envelope.payload.initialSnapshot,
              activeSession?.sessionId == envelope.sessionId else {
            return false
        }

        let disposition = revisionGate.classify(
            sessionId: envelope.sessionId,
            revision: envelope.sessionRevision
        )
        guard disposition != .wrongSession else { return false }
        if disposition == .newer, var session = activeSession {
            session.revision = max(session.revision, envelope.sessionRevision)
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
        }
        // ACK valid duplicates too: a retry usually means our prior ACK was lost.
        sendAck(
            sessionId: envelope.sessionId,
            messageId: envelope.messageId,
            revision: envelope.sessionRevision
        )
        return true
    }

    private func handleTakeoverRelated(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkAuthorityTransferPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.sessionId == activeSession?.sessionId else { return false }
        switch envelope.kind {
        case .reclaimRequest:
            guard activeSession?.role == .phoneController else {
                sequence += 1
                let denied = LinkEnvelope(
                    sessionId: envelope.sessionId,
                    kind: .reclaimDenied,
                    sender: .phone,
                    senderSequence: sequence,
                    sessionRevision: activeSession?.revision ?? envelope.sessionRevision,
                    sentAtEpochMilliseconds: nowMs(),
                    payload: LinkAuthorityTransferPayload(baseRevision: activeSession?.revision)
                )
                Task { try? await sendEnvelope(denied) }
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
            // Legacy direction used these cases. Do not change authority without
            // a locally initiated, acknowledged transfer.
            return true
        default:
            return false
        }
    }

    private func handleMatchFinishedFromWatch(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkMatchFinishedPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .matchFinished,
              envelope.sessionId == activeSession?.sessionId else { return false }

        let latestBefore = revisionGate.latestRevision ?? 0
        let disposition = revisionGate.classify(
            sessionId: envelope.sessionId,
            revision: envelope.sessionRevision
        )
        guard disposition != .wrongSession else { return false }
        if envelope.sessionRevision < latestBefore {
            sendAck(
                sessionId: envelope.sessionId,
                messageId: envelope.messageId,
                revision: envelope.sessionRevision,
                recordAck: true
            )
            return true
        }
        if var session = activeSession {
            session.revision = max(session.revision, envelope.sessionRevision)
            activeSession = session
        }

        mergeDetailedActions(envelope.payload.detailedActions)
        latestRemoteSnapshot = LinkedSnapshotUpdate(
            sessionId: envelope.sessionId,
            revision: envelope.sessionRevision,
            snapshot: envelope.payload.snapshot,
            detailedActions: mergedDetailedActions
        )

        // Once this session has been durably committed, acknowledge any retry
        // without replacing the accepted record.
        if finishedRecordId != nil {
            sendAck(
                sessionId: envelope.sessionId,
                messageId: envelope.messageId,
                revision: envelope.sessionRevision,
                recordAck: true
            )
            return true
        }

        guard let gameType = activeSession?.gameType else { return false }
        do {
            finishedRecordId = try LinkedMatchRecordIngestor.ingest(
                payload: envelope.payload,
                gameType: gameType,
                sessionId: envelope.sessionId
            )
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
            recordAck: true
        )
        return true
    }

    private func handleSessionLeft(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .sessionLeft,
              envelope.sessionId == activeSession?.sessionId else { return false }
        clearSession()
        return true
    }

    private func handleScoreboardExitedToHome(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .scoreboardExitedToHome,
              envelope.sessionId == activeSession?.sessionId else { return false }
        // Keep the watch as controller while its resumable game is on the home screen.
        return true
    }

    private func handleWatchBackgrounded(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .watchBackgrounded,
              envelope.sessionId == activeSession?.sessionId else { return false }
        watchBackgrounded = true
        return true
    }

    private func handleResumeDiscarded(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkResumeDiscardPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .resumeDiscarded,
              envelope.sessionId == activeSession?.sessionId else { return false }
        if var session = activeSession {
            session.revision = max(session.revision, envelope.sessionRevision)
            session.role = .phoneController
            activeSession = session
        }
        controlRole = .phoneController
        return true
    }

    private func handleStatus(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkStatusPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .statusResponse else { return false }
        if var session = activeSession, session.sessionId == envelope.sessionId {
            session.revision = max(session.revision, envelope.payload.revision)
            switch envelope.payload.role {
            case .watchController:
                session.role = .phoneFollower
            case .watchFollower:
                session.role = .phoneController
            case .phoneController, .phoneFollower:
                break
            }
            activeSession = session
            controlRole = session.role
        }
        return true
    }

    private func handleConnectivityStatusChange(_ status: WatchConnectivityStatus) {
        connectivityStatus = status
        pushCommonNamesToWatch()
        guard status.isReachable else { return }
        requestStatusForActiveSession()
    }

    private func requestStatusForActiveSession() {
        guard let session = activeSession else { return }
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: session.sessionId,
            kind: .statusQuery,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: session.revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: EmptyLinkPayload()
        )
        Task { try? await sendEnvelope(envelope) }
    }

    private func sendAck(
        sessionId: UUID,
        messageId: UUID,
        revision: UInt64,
        recordAck: Bool = false
    ) {
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: sessionId,
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
        Task { try? await sendEnvelope(envelope) }
    }

    private func sendEnvelope<Payload: Codable & Sendable>(_ envelope: LinkEnvelope<Payload>) async throws {
        let data = try JSONEncoder().encode(envelope)
        try await transport.send(data)
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
                        nowEpochMilliseconds: self.nowMs(),
                        retainAfterExhaustion: authorityTransferPending
                    ) {
                        Task { try? await self.transport.send(data) }
                    }
                    if let data = self.terminalPendingAck.retryIfDue(
                        nowEpochMilliseconds: self.nowMs(),
                        retainAfterExhaustion: true
                    ) {
                        self.persistTerminalOutbox()
                        Task { try? await self.transport.send(data) }
                    }
                }
            }
        }
    }

    private func clearSession() {
        if let id = activeSession?.sessionId {
            revisionGate.endSession(id)
        }
        activeSession = nil
        controlRole = nil
        pendingTakeoverMessageId = nil
        pendingReclaimGrantMessageId = nil
        pendingReclaimRequest = nil
        pendingTakeoverApplication = nil
        reclaimTimeoutTask?.cancel()
        reclaimTimeoutTask = nil
        pendingAck.clear()
        latestRemoteSnapshot = nil
        mergedDetailedActions = []
        publishedFinishedRecordId = nil
        watchBackgrounded = false
        if terminalPendingAck.pending == nil {
            pendingLeaveAfterFinish = false
        }
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
        Int64(Date().timeIntervalSince1970 * 1_000)
    }

    private func persistTerminalOutbox() {
        guard let item = terminalPendingAck.pending else {
            UserDefaults.standard.removeObject(forKey: terminalOutboxKey)
            return
        }
        if let data = try? JSONEncoder().encode(item) {
            UserDefaults.standard.set(data, forKey: terminalOutboxKey)
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

    private func isThreeXThree(_ snapshot: LinkedScoreboardSnapshot) -> Bool {
        guard case .basketball(let state) = snapshot else { return false }
        return state.gameMode == .threeXThree
    }
}
