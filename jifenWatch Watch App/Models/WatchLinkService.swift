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
    private(set) var connectivityStatus: WatchConnectivityStatus
    private(set) var phoneLinkTestState: WatchPhoneLinkTestState = .idle
    private(set) var phoneLinkTestFailure: WatchPhoneLinkTestFailure?
    private(set) var lastCommunicationAtEpochMilliseconds: Int64
    private(set) var commonNamesSyncFailed = false
    private(set) var lastLinkErrorMessage: String?

    private let transport: any WatchLinkTransport
    private let contextStore: any LinkDataStore
    private let outboxStore: any LinkDataStore
    private let clock: any LinkClock
    private var revisionGate = LinkRevisionGate()
    private var sequence: UInt64 = 0
    /// Authoritative linked-match and control lifecycle. The scalar fields
    /// below are projections used by existing Watch views and persistence.
    private var sessionMachine: LinkSessionStateMachine?
    private var pendingAck = LinkControlRetryQueue()
    private var terminalOutbox = LinkDurableOutbox()
    private var publishedFinishedMatchIds: Set<UUID> = []
    private var pendingReclaimRequestMessageId: UUID?
    private var reclaimRequestTimeoutTask: Task<Void, Never>?
    private var activeSessionId: UUID?
    private var activeHandle: LinkedMatchHandle?
    private var activeRevision: UInt64 = 0
    private var authorityEpoch: UInt64 = 0
    private var activeGameType: GameType?
    private var activeSetup: LinkedScoreboardSetup?
    private var mergedDetailedActions: [DetailedScoreAction] = []
    private var ackRetryTask: Task<Void, Never>?
    private let pendingWatchRecordsKey = "watch_pending_record_transfers_v1"
    private var pendingWatchRecords: [WatchRecordTransferPayload] = []
    private let pendingCommonNameUsageKey = "watch_pending_common_name_usage_v1"
    private var pendingCommonNameUsage: [CommonNameUsagePayload] = []
    private var lastQueuedCommonNameMutationIDs: [UUID] = []
    private var probeTracker = WatchPhoneLinkProbeTracker()
    private var probeTimeoutTask: Task<Void, Never>?
    private let lastCommunicationAtKey = "watch_phone_link_last_communication_at_v1"
    private let contextKey = "watch_link_context"
    private let terminalOutboxKey = "watch_link_terminal_outbox"
    private let pendingSessionEndsKey = "watch_link_pending_session_ends"
    private var pendingSessionEnds: [LinkPendingSessionEnd] = []
    private var pendingSessionEndInFlight: Set<UUID> = []

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
        contextStore.removeObject(forKey: "watch_link_context_v1")
        outboxStore.removeObject(forKey: "watch_link_terminal_outbox_v1")
        outboxStore.removeObject(forKey: "watch_link_pending_ack_v1")
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
        startAckRetryLoop()
        handleApplicationContext(transport.receivedApplicationContext)
        flushPendingCommonNameMutations(force: false)
        WatchRecordManager.shared.recordTransferHandler = { [weak self] payload in
            self?.transferFinishedRecord(payload)
        }
    }

    var isController: Bool {
        controlRole == .watchController
    }

    func clearLinkError() {
        lastLinkErrorMessage = nil
    }

    func requestReclaim() {
        guard let sessionId = activeSessionId,
              controlRole == .watchFollower,
              pendingReclaimRequestMessageId == nil,
              var machine = sessionMachine else { return }
        sequence += 1
        let messageId = UUID()
        guard machine.beginAuthorityTransfer(
            correlationId: messageId,
            targetRole: .watchController,
            kind: .watchReclaim
        ) else { return }
        sessionMachine = machine
        pendingReclaimRequestMessageId = messageId
        let envelope = LinkEnvelope(
            messageId: messageId,
            correlationId: messageId,
            sessionId: sessionId,
            matchId: activeHandle?.matchId,
            matchGeneration: activeHandle?.matchGeneration ?? 1,
            authorityEpoch: authorityEpoch,
            kind: .reclaimRequest,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: activeRevision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkAuthorityTransferPayload(baseRevision: activeRevision)
        )
        sendReportingError(envelope)
        reclaimRequestTimeoutTask?.cancel()
        reclaimRequestTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.pendingReclaimRequestMessageId == messageId else { return }
                if var machine = self?.sessionMachine {
                    _ = machine.rejectAuthorityTransfer(correlationId: messageId)
                    self?.sessionMachine = machine
                }
                self?.pendingReclaimRequestMessageId = nil
                self?.pendingReclaimAcceptance = nil
                self?.reclaimRequestTimeoutTask = nil
                self?.lastLinkErrorMessage = NSLocalizedString(
                    "linked_score_control_timeout",
                    value: "控制权切换超时，请重试。",
                    comment: ""
                )
            }
        }
    }

    func completeReclaimAcceptance(messageId: UUID) {
        guard let pending = pendingReclaimAcceptance,
              pending.messageId == messageId,
              pending.sessionId == activeSessionId,
              var machine = sessionMachine,
              machine.commitAuthorityTransfer(
                  correlationId: pending.correlationId
              ) else { return }
        sessionMachine = machine
        synchronizeSessionStateFromMachine()
        phoneTookOver = false
        pendingReclaimAcceptance = nil
        pendingReclaimRequestMessageId = nil
        reclaimRequestTimeoutTask?.cancel()
        reclaimRequestTimeoutTask = nil
        sendAck(
            sessionId: pending.sessionId,
            messageId: pending.messageId,
            revision: pending.revision
        )
        if let context = resumeContext {
            WatchResumeSessionStore.shared.refreshLinkContext(context)
        }
        persistContext()
    }

    var resumeContext: WatchLinkResumeContext? {
        guard let handle = activeHandle,
              let controlRole,
              let setup = activeSetup else { return nil }
        return WatchLinkResumeContext(
            handle: handle,
            setup: setup,
            role: controlRole,
            authorityEpoch: authorityEpoch,
            revision: activeRevision,
            latestAuthoritativeSnapshot: latestSnapshot?.snapshot
                ?? setup.initialSnapshot,
            detailedActions: mergedDetailedActions,
            completedMatchIds: publishedFinishedMatchIds,
            pendingTerminalMessageIds: Set(terminalOutbox.items.map(\.messageId))
        )
    }

    /// Auto-queue a finished local watch record to the phone.
    func transferFinishedRecord(_ payload: WatchRecordTransferPayload) {
        if let index = pendingWatchRecords.firstIndex(where: { $0.id == payload.id }) {
            pendingWatchRecords[index] = payload
        } else {
            pendingWatchRecords.append(payload)
        }
        persistPendingWatchRecords()
        flushPendingWatchRecords()
    }

    private func flushPendingWatchRecords() {
        guard transport.status.isActivated, !pendingWatchRecords.isEmpty else { return }
        var deliveredCount = 0
        for payload in pendingWatchRecords {
            do {
                let data = try JSONEncoder().encode(payload)
                try transport.transferWatchRecord(data)
                deliveredCount += 1
            } catch {
                lastLinkErrorMessage = error.localizedDescription
                break
            }
        }
        guard deliveredCount > 0 else { return }
        pendingWatchRecords.removeFirst(deliveredCount)
        persistPendingWatchRecords()
    }

    private func persistPendingWatchRecords() {
        if pendingWatchRecords.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingWatchRecordsKey)
        } else {
            do {
                let data = try JSONEncoder().encode(pendingWatchRecords)
                UserDefaults.standard.set(data, forKey: pendingWatchRecordsKey)
            } catch {
                reportPersistenceError(error)
            }
        }
    }

    /// Uses `transferUserInfo`, so usage survives an offline phone/watch interval.
    func recordCommonNameUsage(_ names: [String]) {
        let normalized = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return }

        let store = WatchCommonNamesStore.shared
        var addedLocally = false
        for name in normalized where store.recordUsage(name, type: .player) {
            addedLocally = true
        }

        pendingCommonNameUsage.append(CommonNameUsagePayload(names: normalized))
        persistPendingCommonNameUsage()
        flushPendingCommonNameUsage()
        if addedLocally {
            commonNamesDidChange()
        }
    }

    private func flushPendingCommonNameUsage() {
        guard transport.status.isActivated, !pendingCommonNameUsage.isEmpty else { return }
        var deliveredCount = 0
        for payload in pendingCommonNameUsage {
            do {
                let data = try JSONEncoder().encode(payload)
                try transport.transferCommonNameUsage(data)
                deliveredCount += 1
            } catch {
                lastLinkErrorMessage = error.localizedDescription
                break
            }
        }
        guard deliveredCount > 0 else { return }
        pendingCommonNameUsage.removeFirst(deliveredCount)
        persistPendingCommonNameUsage()
    }

    private func persistPendingCommonNameUsage() {
        if pendingCommonNameUsage.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingCommonNameUsageKey)
        } else {
            do {
                let data = try JSONEncoder().encode(pendingCommonNameUsage)
                UserDefaults.standard.set(data, forKey: pendingCommonNameUsageKey)
            } catch {
                reportPersistenceError(error)
            }
        }
    }

    private func handleApplicationContext(_ context: [String: Any]) {
        guard let snapshot = CommonNamesSyncSnapshot.fromApplicationContextValue(
            context[WatchConnectivityTransport.commonNamesContextKey]
        ) else { return }
        WatchCommonNamesStore.shared.apply(snapshot)
        commonNamesSyncFailed = false
        markCommunication()
    }

    func refreshConnectivity() {
        transport.refreshStatus()
        connectivityStatus = transport.status
    }

    func commonNamesDidChange() {
        lastQueuedCommonNameMutationIDs = []
        flushPendingCommonNameMutations(force: false)
    }

    @discardableResult
    func syncCommonNamesNow() -> WatchCommonNamesSyncRequestResult {
        refreshConnectivity()
        commonNamesSyncFailed = false
        flushPendingCommonNameMutations(force: true)
        guard connectivityStatus.isActivated else {
            commonNamesSyncFailed = true
            return .connectionInactive
        }
        guard connectivityStatus.isReachable else {
            commonNamesSyncFailed = true
            return .queuedUntilPhoneAvailable
        }
        requestCommonNamesSnapshot()
        return commonNamesSyncFailed ? .failed : .requested
    }

    func startConnectivityTest() {
        probeTimeoutTask?.cancel()
        phoneLinkTestFailure = nil
        refreshConnectivity()
        guard connectivityStatus.isActivated else {
            phoneLinkTestState = .failed
            phoneLinkTestFailure = .inactive
            return
        }
        guard connectivityStatus.isReachable else {
            phoneLinkTestState = .failed
            phoneLinkTestFailure = .unreachable
            return
        }
        let probeID = UUID()
        probeTracker.start(probeID)
        phoneLinkTestState = .testing
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: probeID,
            kind: .connectivityProbe,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: 0,
            sentAtEpochMilliseconds: nowMs(),
            payload: ConnectivityProbePayload(probeId: probeID)
        )
        do {
            try transport.sendInteractive(JSONEncoder().encode(envelope))
        } catch {
            probeTracker.cancel()
            phoneLinkTestState = .failed
            phoneLinkTestFailure = .sendFailed
            return
        }
        probeTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(WatchPhoneLinkProbeTracker.timeoutSeconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.probeTracker.timeout(probeID) else { return }
                self.phoneLinkTestState = .failed
                self.phoneLinkTestFailure = .timedOut
            }
        }
    }

    private func requestCommonNamesSnapshot() {
        guard connectivityStatus.isActivated, connectivityStatus.isReachable else {
            commonNamesSyncFailed = true
            return
        }
        let requestID = UUID()
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: requestID,
            kind: .commonNamesSyncRequest,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: 0,
            sentAtEpochMilliseconds: nowMs(),
            payload: CommonNamesSyncRequestPayload(requestId: requestID)
        )
        do {
            try transport.sendInteractive(JSONEncoder().encode(envelope))
        } catch {
            commonNamesSyncFailed = true
        }
    }

    private func flushPendingCommonNameMutations(force: Bool) {
        guard transport.status.isActivated,
              let batch = WatchCommonNamesStore.shared.pendingBatch() else { return }
        let ids = batch.mutations.map(\.id)
        guard force || ids != lastQueuedCommonNameMutationIDs else { return }
        do {
            let data = try JSONEncoder().encode(batch)
            try transport.transferCommonNameMutations(data)
            lastQueuedCommonNameMutationIDs = ids
        } catch {
            commonNamesSyncFailed = true
            lastLinkErrorMessage = error.localizedDescription
        }
    }

    private func handleCommonNameMutationAcknowledgement(_ data: Data) {
        guard let acknowledgement = try? JSONDecoder().decode(
            CommonNameMutationAcknowledgement.self,
            from: data
        ) else { return }
        WatchCommonNamesStore.shared.apply(acknowledgement)
        lastQueuedCommonNameMutationIDs = []
        commonNamesSyncFailed = false
        markCommunication()
        flushPendingCommonNameMutations(force: false)
    }

    private func markCommunication() {
        lastCommunicationAtEpochMilliseconds = nowMs()
        UserDefaults.standard.set(Int(lastCommunicationAtEpochMilliseconds), forKey: lastCommunicationAtKey)
    }

    var isFollower: Bool {
        controlRole == .watchFollower
    }

    var activeParticipantNames: [String]? {
        activeSetup?.participantNames
    }

    func clearRequestedSetup() {
        if let correlationId = pendingConfirmRequest?.messageId,
           var machine = sessionMachine {
            _ = machine.resolveSetup(
                correlationId: correlationId,
                acceptedRole: nil
            )
            sessionMachine = nil
        }
        pendingConfirmRequest = nil
    }

    func acceptPendingSetup() {
        guard let request = pendingConfirmRequest,
              var machine = sessionMachine,
              machine.handle == request.handle,
              machine.resolveSetup(
                  correlationId: request.messageId,
                  acceptedRole: .watchController
              ) else { return }
        pendingConfirmRequest = nil
        sessionMachine = machine
        synchronizeSessionStateFromMachine()
        activeGameType = request.setup.gameType
        activeSetup = request.setup
        phoneTookOver = false
        acceptedSetup = request
        persistContext()
        sequence += 1
        let envelope = LinkEnvelope(
            correlationId: request.messageId,
            sessionId: request.sessionId,
            matchId: request.handle.matchId,
            matchGeneration: request.handle.matchGeneration,
            authorityEpoch: request.authorityEpoch,
            kind: .setupAccepted,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: 0,
            sentAtEpochMilliseconds: nowMs(),
            payload: EmptyLinkPayload()
        )
        sendReportingError(envelope)
    }

    func rejectPendingSetup() {
        guard let request = pendingConfirmRequest else { return }
        pendingConfirmRequest = nil
        if var machine = sessionMachine {
            _ = machine.resolveSetup(
                correlationId: request.messageId,
                acceptedRole: nil
            )
            sessionMachine = nil
        }
        sequence += 1
        let envelope = LinkEnvelope(
            correlationId: request.messageId,
            sessionId: request.sessionId,
            matchId: request.handle.matchId,
            matchGeneration: request.handle.matchGeneration,
            authorityEpoch: request.authorityEpoch,
            kind: .setupRejected,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: 0,
            sentAtEpochMilliseconds: nowMs(),
            payload: EmptyLinkPayload()
        )
        sendReportingError(envelope)
        revisionGate.endSession(request.sessionId)
    }

    func clearAcceptedSetup() {
        acceptedSetup = nil
    }

    func publishSnapshot(
        _ snapshot: LinkedScoreboardSnapshot,
        detailedActions: [DetailedScoreAction]? = nil,
        participantNames: [String]? = nil
    ) {
        guard isController,
              let sessionId = activeSessionId,
              let gameType = activeGameType,
              var machine = sessionMachine else { return }
        _ = machine.advanceRevision()
        sessionMachine = machine
        synchronizeSessionStateFromMachine()
        mergeDetailedActions(detailedActions)
        activeSetup = LinkedScoreboardSetup(
            gameType: gameType,
            maxSets: maxSets(for: snapshot),
            initialSnapshot: snapshot,
            detailedActions: mergedDetailedActions,
            participantNames: participantNames ?? activeSetup?.participantNames ?? []
        )
        latestSnapshot = .init(
            sessionId: sessionId,
            revision: activeRevision,
            snapshot: snapshot,
            detailedActions: mergedDetailedActions
        )
        persistContext()
        sequence += 1
        let messageId = UUID()
        let envelope = LinkEnvelope(
            messageId: messageId,
            sessionId: sessionId,
            matchId: activeHandle?.matchId,
            matchGeneration: activeHandle?.matchGeneration ?? 1,
            authorityEpoch: authorityEpoch,
            kind: .stateSnapshot,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: activeRevision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkedScoreboardSetup(
                gameType: gameType,
                maxSets: maxSets(for: snapshot),
                initialSnapshot: snapshot,
                detailedActions: mergedDetailedActions,
                participantNames: activeSetup?.participantNames ?? []
            )
        )
        Task {
            do {
                let data = try JSONEncoder().encode(envelope)
                if var machine = sessionMachine {
                    machine.registerPendingAcknowledgement(messageId)
                    sessionMachine = machine
                }
                pendingAck.enqueue(.init(
                    messageId: messageId,
                    sessionId: sessionId,
                    revision: activeRevision,
                    data: data,
                    lastSentAtEpochMilliseconds: nowMs()
                ))
                try transport.publishLatestSnapshot(data)
                try await transport.sendRealtime(data)
            } catch {
                lastLinkErrorMessage = error.localizedDescription
            }
        }
    }

    func startNextMatch(
        snapshot: LinkedScoreboardSnapshot,
        detailedActions: [DetailedScoreAction] = [],
        participantNames: [String]? = nil
    ) {
        guard isController,
              let gameType = activeGameType,
              var machine = sessionMachine else { return }
        let nextHandle = machine.beginNextMatch()
        sessionMachine = machine
        synchronizeSessionStateFromMachine()
        mergedDetailedActions = detailedActions
        latestSnapshot = nil
        activeSetup = LinkedScoreboardSetup(
            gameType: gameType,
            maxSets: maxSets(for: snapshot),
            initialSnapshot: snapshot,
            detailedActions: detailedActions,
            participantNames: participantNames ?? activeSetup?.participantNames ?? []
        )
        _ = revisionGate.beginMatch(nextHandle, initialRevision: 0)
        persistContext()
        publishSnapshot(
            snapshot,
            detailedActions: detailedActions,
            participantNames: participantNames
        )
    }

    func publishMatchFinished(
        snapshot: LinkedScoreboardSnapshot,
        recordId: String,
        winnerSide: MatchSide?,
        manualEnd: Bool,
        startTime: Date? = nil,
        endTime: Date? = nil,
        totalScoreChanges: Int? = nil,
        detailedActions: [DetailedScoreAction]? = nil,
        participantNames: [String]? = nil
    ) {
        guard let sessionId = activeSessionId,
              let handle = activeHandle,
              var machine = sessionMachine else { return }
        if publishedFinishedMatchIds.contains(handle.matchId)
            || terminalOutbox.contains(sessionId: sessionId, matchId: handle.matchId) { return }
        let stableRecordId = recordId.isEmpty ? "w_\(UUID().uuidString)" : recordId
        mergeDetailedActions(detailedActions)
        _ = machine.markFinished(matchId: handle.matchId)
        _ = machine.advanceRevision()
        sessionMachine = machine
        synchronizeSessionStateFromMachine()
        sequence += 1
        let messageId = UUID()
        let end = endTime ?? Date()
        let start = startTime ?? end.addingTimeInterval(-60)
        let duration = max(1, end.timeIntervalSince(start))
        let envelope = LinkEnvelope(
            messageId: messageId,
            sessionId: sessionId,
            matchId: handle.matchId,
            matchGeneration: handle.matchGeneration,
            authorityEpoch: authorityEpoch,
            kind: .matchFinished,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: activeRevision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkMatchFinishedPayload(
                snapshot: snapshot,
                recordId: stableRecordId,
                winnerSide: winnerSide,
                manualEnd: manualEnd,
                startTimeEpochMilliseconds: Int64(start.timeIntervalSince1970 * 1000),
                endTimeEpochMilliseconds: Int64(end.timeIntervalSince1970 * 1000),
                durationSeconds: duration,
                totalScoreChanges: totalScoreChanges ?? 0,
                detailedActions: mergedDetailedActions,
                participantNames: participantNames ?? activeSetup?.participantNames ?? []
            )
        )
        Task {
            do {
                let data = try JSONEncoder().encode(envelope)
                if var machine = sessionMachine {
                    machine.registerPendingAcknowledgement(messageId)
                    sessionMachine = machine
                }
                terminalOutbox.enqueue(.init(
                    messageId: messageId,
                    handle: handle,
                    data: data,
                    lastSentAtEpochMilliseconds: nowMs()
                ))
                persistTerminalOutbox()
                persistContext()
                try transport.enqueueDurable(data)
            } catch {
                lastLinkErrorMessage = error.localizedDescription
            }
        }
    }

    func leaveSession() {
        guard let handle = activeHandle else { return }
        let request = LinkPendingSessionEnd(
            handle: handle,
            authorityEpoch: authorityEpoch,
            revision: activeRevision
        )
        if let index = pendingSessionEnds.firstIndex(where: {
            $0.handle.sessionId == handle.sessionId
        }) {
            pendingSessionEnds[index] = request
        } else {
            pendingSessionEnds.append(request)
        }
        persistPendingSessionEnds()
        flushPendingSessionEnds()
    }

    /// Keep the linked match alive while the watch returns to its home screen.
    func exitScoreboardToHome() {
        guard let sessionId = activeSessionId else { return }
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: sessionId,
            matchId: activeHandle?.matchId,
            matchGeneration: activeHandle?.matchGeneration ?? 1,
            authorityEpoch: authorityEpoch,
            kind: .scoreboardExitedToHome,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: activeRevision,
            sentAtEpochMilliseconds: nowMs(),
            payload: EmptyLinkPayload()
        )
        sendReportingError(envelope)
    }

    /// Notify the phone that the watch entered the background (e.g. system
    /// interruption such as an incoming call). The phone can then prompt the
    /// user to take over scoring control.
    func notifyBackgrounded() {
        guard let sessionId = activeSessionId, isController else { return }
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: sessionId,
            matchId: activeHandle?.matchId,
            matchGeneration: activeHandle?.matchGeneration ?? 1,
            authorityEpoch: authorityEpoch,
            kind: .watchBackgrounded,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: activeRevision,
            sentAtEpochMilliseconds: nowMs(),
            payload: EmptyLinkPayload()
        )
        sendReportingError(envelope)
    }

    /// Discard the watch resume entry and hand scoring control back to the phone.
    func discardResumableSession(reason: LinkResumeDiscardReason) {
        guard let sessionId = activeSessionId else { return }
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: sessionId,
            matchId: activeHandle?.matchId,
            matchGeneration: activeHandle?.matchGeneration ?? 1,
            authorityEpoch: authorityEpoch,
            kind: .resumeDiscarded,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: activeRevision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkResumeDiscardPayload(reason: reason)
        )
        sendReportingError(envelope)
        // Keep enough session state for status-query recovery if the immediate
        // handoff message is lost while either device is unreachable.
        if var machine = sessionMachine {
            _ = machine.adoptAuthority(
                role: .watchFollower,
                epoch: machine.authorityEpoch
            )
            sessionMachine = machine
            synchronizeSessionStateFromMachine()
        }
        phoneTookOver = true
        persistContext()
    }

    func restoreSuspendedSession(_ context: WatchLinkResumeContext) {
        _ = revisionGate.beginMatch(context.handle, initialRevision: context.revision)
        installStateMachine(from: context)
        synchronizeSessionStateFromMachine()
        activeGameType = context.setup.gameType
        activeSetup = context.setup
        phoneTookOver = context.controlRole == .watchFollower
        mergedDetailedActions = context.detailedActions
        if let snapshot = context.latestAuthoritativeSnapshot {
            latestSnapshot = .init(
                sessionId: context.sessionId,
                revision: context.revision,
                snapshot: snapshot,
                detailedActions: context.detailedActions
            )
        } else {
            latestSnapshot = nil
        }
        pendingReclaimAcceptance = nil
        pendingReclaimRequestMessageId = nil
        reclaimRequestTimeoutTask?.cancel()
        reclaimRequestTimeoutTask = nil
        persistContext()
    }

    private func receive(_ data: Data) {
        let handled = handleConnectivityProbeResponse(data)
            || handleSetupRequest(data)
            || handleAck(data)
            || handleSnapshotFromPhone(data)
            || handleTakeover(data)
            || handleReclaimResponse(data)
            || handleMatchFinishedFromPhone(data)
            || handleSessionLeft(data)
            || handleResyncRequest(data)
            || handleStatusQuery(data)
        if handled {
            markCommunication()
        }
    }

    private func handleConnectivityProbeResponse(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(
            LinkEnvelope<ConnectivityProbePayload>.self,
            from: data
        ), envelope.sender == .phone,
           envelope.kind == .connectivityProbeResponse,
           envelope.protocolVersion == LinkProtocol.currentVersion,
           probeTracker.accept(
               sessionID: envelope.sessionId,
               probeID: envelope.payload.probeId
           ) else { return false }
        probeTimeoutTask?.cancel()
        probeTimeoutTask = nil
        phoneLinkTestFailure = nil
        phoneLinkTestState = .success
        return true
    }

    private func handleSetupRequest(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkedScoreboardSetup>.self, from: data),
              envelope.sender == .phone,
              envelope.kind == .setupRequest else { return false }
        guard envelope.protocolVersion == LinkProtocol.currentVersion,
              envelope.capabilities == LinkProtocol.capabilities,
              envelope.payload.capabilities == LinkProtocol.capabilities,
              Self.isValidLinkedSetup(envelope.payload) else {
            sequence += 1
            let rejection = LinkEnvelope(
                correlationId: envelope.messageId,
                sessionId: envelope.sessionId,
                matchId: envelope.matchId,
                matchGeneration: envelope.matchGeneration,
                authorityEpoch: envelope.authorityEpoch,
                kind: .setupRejected,
                sender: .watch,
                senderSequence: sequence,
                sessionRevision: 0,
                sentAtEpochMilliseconds: nowMs(),
                payload: EmptyLinkPayload()
            )
            sendReportingError(rejection)
            return true
        }
        if let existing = revisionGate.activeSessionId, existing != envelope.sessionId {
            WatchResumeSessionStore.shared.clear()
            endLocalSession()
        }
        _ = revisionGate.beginMatch(envelope.handle, initialRevision: envelope.sessionRevision)
        sessionMachine = LinkSessionStateMachine(
            handle: envelope.handle,
            role: .watchController,
            authorityEpoch: envelope.authorityEpoch,
            revision: envelope.sessionRevision,
            lifecycle: .starting
        )
        _ = sessionMachine?.beginSetup(correlationId: envelope.messageId)
        latestSnapshot = nil
        acceptedSetup = nil
        phoneTookOver = false
        controlRole = nil
        pendingConfirmRequest = .init(
            handle: envelope.handle,
            messageId: envelope.messageId,
            authorityEpoch: envelope.authorityEpoch,
            setup: envelope.payload
        )
        mergeDetailedActions(envelope.payload.detailedActions)
        return true
    }

    private func handleAck(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkAcknowledgementPayload>.self, from: data),
              envelope.sender == .phone,
              envelope.kind == .acknowledgement || envelope.kind == .recordAcknowledgement,
              envelope.correlationId == envelope.payload.acknowledgedMessageId else {
            return false
        }
        let messageId = envelope.payload.acknowledgedMessageId
        _ = pendingAck.acknowledge(messageId: messageId)
        if var machine = sessionMachine {
            _ = machine.acknowledge(messageId: messageId)
            sessionMachine = machine
        }
        let terminalCandidate = terminalOutbox.items.first {
            $0.messageId == messageId
        }
        let terminalItem: LinkDurableOutbox.Item?
        if let terminalCandidate,
           envelope.kind == .recordAcknowledgement,
           envelope.handle == terminalCandidate.handle {
            terminalItem = terminalOutbox.acknowledge(messageId: messageId)
        } else {
            terminalItem = nil
        }
        if terminalItem != nil {
            persistTerminalOutbox()
            persistContext()
            flushPendingSessionEnds()
        }
        return true
    }

    private func handleSnapshotFromPhone(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkedScoreboardSetup>.self, from: data),
              envelope.sender == .phone,
              envelope.kind == .stateSnapshot,
              let snapshot = envelope.payload.initialSnapshot,
              envelope.sessionId == activeSessionId,
              Self.isValidLinkedSetup(envelope.payload),
              var machine = sessionMachine else { return false }

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
        if validation == .current {
            _ = machine.adoptAuthority(
                role: .watchFollower,
                epoch: envelope.authorityEpoch
            )
        }
        sessionMachine = machine
        synchronizeSessionStateFromMachine()

        if beganNewMatch {
            mergedDetailedActions = []
            latestSnapshot = nil
            phoneTookOver = true
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
        if validation == .current {
            activeSetup = envelope.payload
            mergeDetailedActions(envelope.payload.detailedActions)
            latestSnapshot = .init(
                sessionId: envelope.sessionId,
                revision: envelope.sessionRevision,
                snapshot: snapshot,
                detailedActions: mergedDetailedActions
            )
            if let context = resumeContext {
                WatchResumeSessionStore.shared.applyLinkedSnapshot(snapshot, context: context)
            }
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

    private func handleTakeover(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkAuthorityTransferPayload>.self, from: data),
              envelope.sender == .phone,
              envelope.kind == .takeoverByPhone,
              envelope.handle == activeHandle,
              var machine = sessionMachine else { return false }
        // The watch remains authoritative until this message is received. Use
        // its frozen latest state in the ACK so any point scored while the
        // takeover request was in flight cannot be lost.
        let authoritativeSnapshot = activeSetup?.initialSnapshot ?? envelope.payload.snapshot
        if envelope.authorityEpoch < machine.authorityEpoch {
            guard machine.role == .watchFollower,
                  envelope.authorityEpoch + 1 == machine.authorityEpoch else {
                return false
            }
            sendAck(
                sessionId: envelope.sessionId,
                messageId: envelope.messageId,
                revision: machine.revision,
                handle: envelope.handle,
                authorityEpoch: machine.authorityEpoch,
                authoritativeSnapshot: authoritativeSnapshot,
                detailedActions: mergedDetailedActions
            )
            return true
        }
        guard envelope.authorityEpoch == machine.authorityEpoch,
              machine.beginAuthorityTransfer(
                  correlationId: envelope.messageId,
                  targetRole: .watchFollower,
                  kind: .phoneTakeover
              ),
              machine.prepareAuthorityTransfer(
                  correlationId: envelope.messageId,
                  epoch: machine.authorityEpoch + 1
              ),
              machine.commitAuthorityTransfer(
                  correlationId: envelope.messageId
              ) else { return false }
        sessionMachine = machine
        synchronizeSessionStateFromMachine()
        phoneTookOver = true
        if let context = resumeContext {
            WatchResumeSessionStore.shared.refreshLinkContext(context)
        }
        persistContext()
        sendAck(
            sessionId: envelope.sessionId,
            messageId: envelope.messageId,
            revision: activeRevision,
            handle: envelope.handle,
            authorityEpoch: authorityEpoch,
            authoritativeSnapshot: authoritativeSnapshot,
            detailedActions: mergedDetailedActions
        )
        return true
    }

    private func handleReclaimResponse(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkAuthorityTransferPayload>.self, from: data),
              envelope.sender == .phone,
              envelope.handle == activeHandle,
              envelope.authorityEpoch >= authorityEpoch else { return false }
        switch envelope.kind {
        case .reclaimAccepted:
            if pendingReclaimAcceptance?.messageId == envelope.messageId {
                return true
            }
            if controlRole == .watchController {
                sendAck(
                    sessionId: envelope.sessionId,
                    messageId: envelope.messageId,
                    revision: envelope.sessionRevision
                )
                return true
            }
            guard let correlationId = pendingReclaimRequestMessageId,
                  envelope.correlationId == correlationId,
                  let snapshot = envelope.payload.snapshot,
                  var machine = sessionMachine,
                  machine.prepareAuthorityTransfer(
                      correlationId: correlationId,
                      epoch: envelope.authorityEpoch
                  ) else { return true }
            let validation = machine.accept(
                handle: envelope.handle,
                authorityEpoch: envelope.authorityEpoch,
                revision: envelope.sessionRevision
            )
            guard validation == .current || validation == .duplicateOrOlder else {
                _ = machine.rejectAuthorityTransfer(correlationId: correlationId)
                sessionMachine = machine
                return true
            }
            reclaimRequestTimeoutTask?.cancel()
            mergeDetailedActions(envelope.payload.detailedActions)
            sessionMachine = machine
            synchronizeSessionStateFromMachine()
            pendingReclaimAcceptance = .init(
                messageId: envelope.messageId,
                correlationId: correlationId,
                sessionId: envelope.sessionId,
                revision: envelope.sessionRevision,
                snapshot: snapshot,
                detailedActions: mergedDetailedActions
            )
            reclaimRequestTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self,
                          self.pendingReclaimAcceptance?.messageId
                            == envelope.messageId else { return }
                    if var machine = self.sessionMachine {
                        _ = machine.rejectAuthorityTransfer(
                            correlationId: correlationId
                        )
                        self.sessionMachine = machine
                        self.synchronizeSessionStateFromMachine()
                    }
                    self.pendingReclaimAcceptance = nil
                    self.pendingReclaimRequestMessageId = nil
                    self.reclaimRequestTimeoutTask = nil
                    self.lastLinkErrorMessage = NSLocalizedString(
                        "linked_score_control_timeout",
                        value: "控制权切换超时，请重试。",
                        comment: ""
                    )
                    self.persistContext()
                }
            }
            return true
        case .reclaimDenied:
            reclaimRequestTimeoutTask?.cancel()
            reclaimRequestTimeoutTask = nil
            if let correlationId = pendingReclaimRequestMessageId,
               envelope.correlationId == correlationId,
               var machine = sessionMachine {
                _ = machine.rejectAuthorityTransfer(correlationId: correlationId)
                sessionMachine = machine
            }
            pendingReclaimRequestMessageId = nil
            pendingReclaimAcceptance = nil
            return true
        default:
            return false
        }
    }

    private func handleMatchFinishedFromPhone(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkMatchFinishedPayload>.self, from: data),
              envelope.sender == .phone,
              envelope.kind == .matchFinished,
              envelope.sessionId == activeSessionId,
              let currentHandle = activeHandle,
              var machine = sessionMachine,
              envelope.matchGeneration <= currentHandle.matchGeneration else {
            return false
        }
        let isCurrentMatch = envelope.handle == currentHandle
        guard !isCurrentMatch || envelope.authorityEpoch >= authorityEpoch else {
            return false
        }
        if publishedFinishedMatchIds.contains(envelope.matchId) {
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
            let validation = machine.accept(
                handle: envelope.handle,
                authorityEpoch: envelope.authorityEpoch,
                revision: envelope.sessionRevision
            )
            guard validation == .current || validation == .duplicateOrOlder else {
                return false
            }
            _ = revisionGate.classify(
                handle: envelope.handle,
                revision: envelope.sessionRevision
            )
            mergeDetailedActions(envelope.payload.detailedActions)
            latestSnapshot = .init(
                sessionId: envelope.sessionId,
                revision: envelope.sessionRevision,
                snapshot: envelope.payload.snapshot,
                detailedActions: mergedDetailedActions
            )
            WatchResumeSessionStore.shared.clear()
        }
        _ = machine.markFinished(matchId: envelope.matchId)
        sessionMachine = machine
        synchronizeSessionStateFromMachine()
        persistContext()
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
              envelope.sender == .phone,
              envelope.kind == .sessionLeft else { return false }
        if pendingConfirmRequest?.sessionId == envelope.sessionId {
            revisionGate.endSession(envelope.sessionId)
            pendingConfirmRequest = nil
            return true
        }
        guard envelope.sessionId == activeSessionId else { return false }
        let pendingCount = pendingSessionEnds.count
        pendingSessionEnds.removeAll { $0.handle.sessionId == envelope.sessionId }
        if pendingSessionEnds.count != pendingCount {
            persistPendingSessionEnds()
        }
        WatchResumeSessionStore.shared.clear()
        endLocalSession()
        return true
    }

    private func handleStatusQuery(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: data),
              envelope.sender == .phone,
              envelope.kind == .statusQuery,
              let sessionId = activeSessionId,
              envelope.handle == activeHandle,
              envelope.authorityEpoch == authorityEpoch,
              let role = controlRole else { return false }
        sequence += 1
        let response = LinkEnvelope(
            correlationId: envelope.messageId,
            sessionId: sessionId,
            matchId: activeHandle?.matchId,
            matchGeneration: activeHandle?.matchGeneration ?? 1,
            authorityEpoch: authorityEpoch,
            kind: .statusResponse,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: activeRevision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkStatusPayload(role: role, revision: activeRevision)
        )
        sendReportingError(response)
        return true
    }

    private func handleResyncRequest(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: data),
              envelope.sender == .phone,
              envelope.kind == .resyncRequest,
              envelope.sessionId == activeSessionId,
              LinkManualResyncPolicy.watchCanRespond(role: controlRole),
              let setup = activeSetup,
              let snapshot = setup.initialSnapshot else { return false }
        publishSnapshot(
            snapshot,
            detailedActions: mergedDetailedActions,
            participantNames: setup.participantNames
        )
        return true
    }

    private func sendAck(
        sessionId: UUID,
        messageId: UUID,
        revision: UInt64,
        handle: LinkedMatchHandle? = nil,
        authorityEpoch: UInt64? = nil,
        recordAck: Bool = false,
        authoritativeSnapshot: LinkedScoreboardSnapshot? = nil,
        detailedActions: [DetailedScoreAction]? = nil
    ) {
        sequence += 1
        let resolvedHandle = handle
            ?? activeHandle
            ?? LinkedMatchHandle(sessionId: sessionId, matchId: sessionId)
        let envelope = LinkEnvelope(
            correlationId: messageId,
            sessionId: sessionId,
            matchId: resolvedHandle.matchId,
            matchGeneration: resolvedHandle.matchGeneration,
            authorityEpoch: authorityEpoch ?? self.authorityEpoch,
            kind: recordAck ? .recordAcknowledgement : .acknowledgement,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkAcknowledgementPayload(
                acknowledgedMessageId: messageId,
                acknowledgedRevision: revision,
                authoritativeSnapshot: authoritativeSnapshot,
                detailedActions: detailedActions ?? []
            )
        )
        sendReportingError(envelope)
    }

    private func sendReportingError<Payload: Codable & Sendable>(
        _ envelope: LinkEnvelope<Payload>
    ) {
        Task {
            do {
                try await send(envelope)
            } catch {
                lastLinkErrorMessage = error.localizedDescription
            }
        }
    }

    private func send<Payload: Codable & Sendable>(_ envelope: LinkEnvelope<Payload>) async throws {
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
                    if let data = self.pendingAck.retryIfDue(nowEpochMilliseconds: self.nowMs()) {
                        Task {
                            do {
                                try await self.transport.sendRealtime(data)
                            } catch {
                                self.lastLinkErrorMessage = error.localizedDescription
                            }
                        }
                    } else if let pendingMessageId,
                              self.pendingAck.pending == nil {
                        if var machine = self.sessionMachine {
                            _ = machine.acknowledge(messageId: pendingMessageId)
                            self.sessionMachine = machine
                        }
                        self.lastLinkErrorMessage = NSLocalizedString(
                            "linked_score_sync_timeout",
                            value: "比分同步超时，将在重新连接后继续同步。",
                            comment: ""
                        )
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
                                self.lastLinkErrorMessage = error.localizedDescription
                            }
                        }
                    }
                    self.flushPendingSessionEnds()
                }
            }
        }
    }

    private func endLocalSession() {
        sessionMachine?.endSession()
        if let id = revisionGate.activeSessionId {
            revisionGate.endSession(id)
        }
        sessionMachine = nil
        activeSessionId = nil
        activeHandle = nil
        activeRevision = 0
        activeGameType = nil
        activeSetup = nil
        controlRole = nil
        acceptedSetup = nil
        pendingConfirmRequest = nil
        latestSnapshot = nil
        mergedDetailedActions = []
        phoneTookOver = false
        publishedFinishedMatchIds.removeAll()
        pendingReclaimAcceptance = nil
        pendingReclaimRequestMessageId = nil
        reclaimRequestTimeoutTask?.cancel()
        reclaimRequestTimeoutTask = nil
        pendingAck.clear()
        persistContext()
    }

    private func installStateMachine(
        from context: WatchLinkResumeContext,
        lifecycle: LinkSessionStateMachine.Lifecycle = .active
    ) {
        sessionMachine = LinkSessionStateMachine(
            handle: context.handle,
            role: context.role,
            authorityEpoch: context.authorityEpoch,
            revision: context.revision,
            completedMatchIds: context.completedMatchIds,
            lifecycle: lifecycle,
            pendingAcknowledgementIds: Set(pendingAck.pending.map { [$0.messageId] } ?? [])
                .union(terminalOutbox.items.map(\.messageId))
        )
    }

    private func synchronizeSessionStateFromMachine() {
        guard let machine = sessionMachine else { return }
        activeSessionId = machine.handle.sessionId
        activeHandle = machine.handle
        activeRevision = machine.revision
        authorityEpoch = machine.authorityEpoch
        controlRole = machine.role
        publishedFinishedMatchIds = machine.completedMatchIds
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
                sender: .watch,
                senderSequence: sequence,
                sessionRevision: request.revision,
                sentAtEpochMilliseconds: nowMs(),
                payload: EmptyLinkPayload()
            )
            Task {
                defer { pendingSessionEndInFlight.remove(sessionId) }
                do {
                    try await send(envelope)
                    pendingSessionEnds.removeAll {
                        $0.handle.sessionId == sessionId
                    }
                    persistPendingSessionEnds()
                    if activeSessionId == sessionId {
                        endLocalSession()
                    }
                } catch {
                    lastLinkErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func nowMs() -> Int64 {
        clock.nowEpochMilliseconds()
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

    private static func isValidLinkedSetup(_ setup: LinkedScoreboardSetup) -> Bool {
        guard let snapshot = setup.initialSnapshot else { return false }
        switch (setup.gameType, snapshot) {
        case (.pingpong, .rally(let state)),
             (.badminton, .rally(let state)),
             (.pickleball, .rally(let state)):
            return state.doubles == nil
        case (.pingpongDoubles, .rally(let state)),
             (.badmintonDoubles, .rally(let state)),
             (.pickleballDoubles, .rally(let state)):
            return state.doubles?.playerNames.count == 4
        case (.tennis, .tennis(let state)):
            return state.doublesPlayerNames == nil
        case (.tennisDoubles, .tennis(let state)):
            return state.doublesPlayerNames?.count == 4
        case (.archeryDual, .archery):
            return true
        case (.eightBall, .eightBall), (.snooker, .snooker):
            return setup.participantNames.count == 2
        case (.nineBall, .nineBall(let state)):
            return (2...4).contains(state.playerCount)
        default:
            return false
        }
    }

    private func persistContext() {
        guard let handle = activeHandle,
              let setup = activeSetup,
              let role = controlRole else {
            contextStore.removeObject(forKey: contextKey)
            return
        }
        let context = WatchLinkResumeContext(
            handle: handle,
            setup: setup,
            role: role,
            authorityEpoch: authorityEpoch,
            revision: activeRevision,
            latestAuthoritativeSnapshot: latestSnapshot?.snapshot
                ?? setup.initialSnapshot,
            detailedActions: mergedDetailedActions,
            completedMatchIds: publishedFinishedMatchIds,
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
        lastLinkErrorMessage = String(
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
                WatchLinkResumeContext.self,
                from: data
              ) else {
            contextStore.removeObject(forKey: contextKey)
            return
        }
        installStateMachine(from: context)
        synchronizeSessionStateFromMachine()
        activeGameType = context.setup.gameType
        activeSetup = context.setup
        phoneTookOver = context.role == .watchFollower
        mergedDetailedActions = context.detailedActions
        if let snapshot = context.latestAuthoritativeSnapshot {
            latestSnapshot = LinkedSnapshotUpdate(
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
