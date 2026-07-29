import Foundation
import LinkCore
import Observation
import RecordCore
import ScoreCore

struct LinkedSetupRequest: Equatable {
    let sessionId: UUID
    let setup: LinkedScoreboardSetup
}

struct LinkedSnapshotUpdate: Equatable {
    let sessionId: UUID
    let revision: UInt64
    let snapshot: LinkedScoreboardSnapshot
    let detailedActions: [DetailedScoreAction]
}

struct PendingWatchReclaimAcceptance: Equatable {
    let messageId: UUID
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

    private let transport = WatchConnectivityTransport()
    private var revisionGate = LinkRevisionGate()
    private var sequence: UInt64 = 0
    private var pendingAck = LinkPendingAckQueue()
    private var terminalPendingAck = LinkPendingAckQueue()
    private var publishedFinishedRecordId: String?
    private var pendingReclaimRequestMessageId: UUID?
    private var reclaimRequestTimeoutTask: Task<Void, Never>?
    private var activeSessionId: UUID?
    private var activeRevision: UInt64 = 0
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
    private let terminalOutboxKey = "watch_link_terminal_outbox_v1"
    private var pendingLeaveAfterFinish = false

    init() {
        connectivityStatus = transport.status
        lastCommunicationAtEpochMilliseconds = Int64(
            UserDefaults.standard.integer(forKey: lastCommunicationAtKey)
        )
        if let data = UserDefaults.standard.data(forKey: terminalOutboxKey),
           let item = try? JSONDecoder().decode(LinkPendingAckQueue.PendingItem.self, from: data) {
            terminalPendingAck.enqueue(item)
            pendingLeaveAfterFinish = true
        }
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

    func requestReclaim() {
        guard let sessionId = activeSessionId,
              controlRole == .watchFollower,
              pendingReclaimRequestMessageId == nil else { return }
        sequence += 1
        let messageId = UUID()
        pendingReclaimRequestMessageId = messageId
        let envelope = LinkEnvelope(
            messageId: messageId,
            sessionId: sessionId,
            kind: .reclaimRequest,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: activeRevision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkAuthorityTransferPayload(baseRevision: activeRevision)
        )
        Task { try? await send(envelope) }
        reclaimRequestTimeoutTask?.cancel()
        reclaimRequestTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.pendingReclaimRequestMessageId == messageId else { return }
                self?.pendingReclaimRequestMessageId = nil
                self?.pendingReclaimAcceptance = nil
                self?.reclaimRequestTimeoutTask = nil
            }
        }
    }

    func completeReclaimAcceptance(messageId: UUID) {
        guard let pending = pendingReclaimAcceptance,
              pending.messageId == messageId,
              pending.sessionId == activeSessionId else { return }
        activeRevision = max(activeRevision, pending.revision)
        controlRole = .watchController
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
    }

    var resumeContext: WatchResumeLinkContext? {
        guard let sessionId = activeSessionId,
              let controlRole,
              let setup = activeSetup else { return nil }
        return WatchResumeLinkContext(
            sessionId: sessionId,
            revision: activeRevision,
            controlRole: controlRole,
            setup: setup
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
            guard let data = try? JSONEncoder().encode(payload) else { break }
            do {
                try transport.transferWatchRecord(data)
                deliveredCount += 1
            } catch {
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
        } else if let data = try? JSONEncoder().encode(pendingWatchRecords) {
            UserDefaults.standard.set(data, forKey: pendingWatchRecordsKey)
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
            guard let data = try? JSONEncoder().encode(payload) else { break }
            do {
                try transport.transferCommonNameUsage(data)
                deliveredCount += 1
            } catch {
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
        } else if let data = try? JSONEncoder().encode(pendingCommonNameUsage) {
            UserDefaults.standard.set(data, forKey: pendingCommonNameUsageKey)
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
        guard let data = try? JSONEncoder().encode(batch) else { return }
        do {
            try transport.transferCommonNameMutations(data)
            lastQueuedCommonNameMutationIDs = ids
        } catch {
            commonNamesSyncFailed = true
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
        pendingConfirmRequest = nil
    }

    func acceptPendingSetup() {
        guard let request = pendingConfirmRequest else { return }
        pendingConfirmRequest = nil
        activeSessionId = request.sessionId
        activeRevision = 0
        activeGameType = request.setup.gameType
        activeSetup = request.setup
        controlRole = .watchController
        phoneTookOver = false
        acceptedSetup = request
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: request.sessionId,
            kind: .setupAccepted,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: 0,
            sentAtEpochMilliseconds: nowMs(),
            payload: EmptyLinkPayload()
        )
        Task { try? await send(envelope) }
    }

    func rejectPendingSetup() {
        guard let request = pendingConfirmRequest else { return }
        pendingConfirmRequest = nil
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: request.sessionId,
            kind: .setupRejected,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: 0,
            sentAtEpochMilliseconds: nowMs(),
            payload: EmptyLinkPayload()
        )
        Task { try? await send(envelope) }
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
              let gameType = activeGameType else { return }
        activeRevision += 1
        mergeDetailedActions(detailedActions)
        activeSetup = LinkedScoreboardSetup(
            gameType: gameType,
            maxSets: maxSets(for: snapshot),
            basketballThreeXThree: isThreeXThree(snapshot),
            initialSnapshot: snapshot,
            detailedActions: mergedDetailedActions,
            participantNames: participantNames ?? activeSetup?.participantNames
        )
        sequence += 1
        let messageId = UUID()
        let envelope = LinkEnvelope(
            messageId: messageId,
            sessionId: sessionId,
            kind: .stateSnapshot,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: activeRevision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkedScoreboardSetup(
                gameType: gameType,
                maxSets: maxSets(for: snapshot),
                basketballThreeXThree: isThreeXThree(snapshot),
                initialSnapshot: snapshot,
                detailedActions: mergedDetailedActions,
                participantNames: activeSetup?.participantNames
            )
        )
        Task {
            guard let data = try? JSONEncoder().encode(envelope) else { return }
            pendingAck.enqueue(.init(
                messageId: messageId,
                sessionId: sessionId,
                revision: activeRevision,
                data: data,
                lastSentAtEpochMilliseconds: nowMs()
            ))
            try? await transport.send(data)
        }
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
        guard let sessionId = activeSessionId else { return }
        // One finished record per linked session — keep a stable id for ACK retries.
        if publishedFinishedRecordId != nil
            || terminalPendingAck.pending?.sessionId == sessionId { return }
        let stableRecordId = recordId.isEmpty ? "w_\(UUID().uuidString)" : recordId
        mergeDetailedActions(detailedActions)
        publishedFinishedRecordId = stableRecordId
        activeRevision += 1
        sequence += 1
        let messageId = UUID()
        let end = endTime ?? Date()
        let start = startTime ?? end.addingTimeInterval(-60)
        let duration = max(1, end.timeIntervalSince(start))
        let envelope = LinkEnvelope(
            messageId: messageId,
            sessionId: sessionId,
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
                totalScoreChanges: totalScoreChanges,
                detailedActions: mergedDetailedActions,
                participantNames: participantNames ?? activeSetup?.participantNames
            )
        )
        Task {
            guard let data = try? JSONEncoder().encode(envelope) else { return }
            terminalPendingAck.enqueue(.init(
                messageId: messageId,
                sessionId: sessionId,
                revision: activeRevision,
                data: data,
                lastSentAtEpochMilliseconds: nowMs()
            ))
            persistTerminalOutbox()
            try? await transport.send(data)
        }
    }

    func leaveSession() {
        guard let sessionId = activeSessionId else { return }
        if terminalPendingAck.pending?.sessionId == sessionId {
            pendingLeaveAfterFinish = true
            return
        }
        sendSessionLeftAndEnd(sessionId: sessionId)
    }

    private func sendSessionLeftAndEnd(sessionId: UUID) {
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: sessionId,
            kind: .sessionLeft,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: activeRevision,
            sentAtEpochMilliseconds: nowMs(),
            payload: EmptyLinkPayload()
        )
        Task { try? await send(envelope) }
        if activeSessionId == sessionId {
            endLocalSession()
        }
    }

    /// Keep the linked match alive while the watch returns to its home screen.
    func exitScoreboardToHome() {
        guard let sessionId = activeSessionId else { return }
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: sessionId,
            kind: .scoreboardExitedToHome,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: activeRevision,
            sentAtEpochMilliseconds: nowMs(),
            payload: EmptyLinkPayload()
        )
        Task { try? await send(envelope) }
    }

    /// Notify the phone that the watch entered the background (e.g. system
    /// interruption such as an incoming call). The phone can then prompt the
    /// user to take over scoring control.
    func notifyBackgrounded() {
        guard let sessionId = activeSessionId, isController else { return }
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: sessionId,
            kind: .watchBackgrounded,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: activeRevision,
            sentAtEpochMilliseconds: nowMs(),
            payload: EmptyLinkPayload()
        )
        Task { try? await send(envelope) }
    }

    /// Discard the watch resume entry and hand scoring control back to the phone.
    func discardResumableSession(reason: LinkResumeDiscardReason) {
        guard let sessionId = activeSessionId else { return }
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: sessionId,
            kind: .resumeDiscarded,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: activeRevision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkResumeDiscardPayload(reason: reason)
        )
        Task { try? await send(envelope) }
        // Keep enough session state for status-query recovery if the immediate
        // handoff message is lost while either device is unreachable.
        controlRole = .watchFollower
        phoneTookOver = true
    }

    func restoreSuspendedSession(_ context: WatchResumeLinkContext) {
        _ = revisionGate.beginSession(context.sessionId, initialRevision: context.revision)
        activeSessionId = context.sessionId
        activeRevision = context.revision
        activeGameType = context.setup.gameType
        activeSetup = context.setup
        controlRole = context.controlRole
        phoneTookOver = context.controlRole == .watchFollower
        latestSnapshot = nil
        publishedFinishedRecordId = nil
        pendingReclaimAcceptance = nil
        pendingReclaimRequestMessageId = nil
        reclaimRequestTimeoutTask?.cancel()
        reclaimRequestTimeoutTask = nil
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
        guard envelope.protocolVersion == LinkProtocol.currentVersion else {
            sequence += 1
            let rejection = LinkEnvelope(
                sessionId: envelope.sessionId,
                kind: .setupRejected,
                sender: .watch,
                senderSequence: sequence,
                sessionRevision: 0,
                sentAtEpochMilliseconds: nowMs(),
                payload: EmptyLinkPayload()
            )
            Task { try? await send(rejection) }
            return true
        }
        if let existing = revisionGate.activeSessionId, existing != envelope.sessionId {
            WatchResumeSessionStore.shared.clear()
            endLocalSession()
        }
        _ = revisionGate.beginSession(envelope.sessionId, initialRevision: envelope.sessionRevision)
        latestSnapshot = nil
        acceptedSetup = nil
        phoneTookOver = false
        controlRole = nil
        pendingConfirmRequest = .init(sessionId: envelope.sessionId, setup: envelope.payload)
        mergeDetailedActions(envelope.payload.detailedActions)
        return true
    }

    private func handleAck(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkAcknowledgementPayload>.self, from: data),
              envelope.sender == .phone,
              envelope.kind == .acknowledgement || envelope.kind == .recordAcknowledgement else {
            return false
        }
        let messageId = envelope.payload.acknowledgedMessageId
        _ = pendingAck.acknowledge(messageId: messageId)
        let terminalSessionId = terminalPendingAck.pending?.sessionId
        let terminalAcknowledged = terminalPendingAck.acknowledge(messageId: messageId)
        if terminalAcknowledged {
            persistTerminalOutbox()
            if pendingLeaveAfterFinish, let sessionId = terminalSessionId {
                pendingLeaveAfterFinish = false
                sendSessionLeftAndEnd(sessionId: sessionId)
            }
        }
        return true
    }

    private func handleSnapshotFromPhone(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkedScoreboardSetup>.self, from: data),
              envelope.sender == .phone,
              envelope.kind == .stateSnapshot,
              let snapshot = envelope.payload.initialSnapshot,
              envelope.sessionId == activeSessionId else { return false }

        let disposition = revisionGate.classify(
            sessionId: envelope.sessionId,
            revision: envelope.sessionRevision
        )
        guard disposition != .wrongSession else { return false }
        if disposition == .newer {
            activeRevision = max(activeRevision, envelope.sessionRevision)
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
        }
        // ACK valid duplicates too: a retry usually means our prior ACK was lost.
        sendAck(sessionId: envelope.sessionId, messageId: envelope.messageId, revision: envelope.sessionRevision)
        return true
    }

    private func handleTakeover(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkAuthorityTransferPayload>.self, from: data),
              envelope.sender == .phone,
              envelope.kind == .takeoverByPhone,
              envelope.sessionId == activeSessionId else { return false }
        // The watch remains authoritative until this message is received. Use
        // its frozen latest state in the ACK so any point scored while the
        // takeover request was in flight cannot be lost.
        let authoritativeSnapshot = activeSetup?.initialSnapshot ?? envelope.payload.snapshot
        controlRole = .watchFollower
        phoneTookOver = true
        if let context = resumeContext {
            WatchResumeSessionStore.shared.refreshLinkContext(context)
        }
        sendAck(
            sessionId: envelope.sessionId,
            messageId: envelope.messageId,
            revision: activeRevision,
            authoritativeSnapshot: authoritativeSnapshot,
            detailedActions: mergedDetailedActions
        )
        return true
    }

    private func handleReclaimResponse(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkAuthorityTransferPayload>.self, from: data),
              envelope.sender == .phone,
              envelope.sessionId == activeSessionId else { return false }
        switch envelope.kind {
        case .reclaimAccepted:
            if controlRole == .watchController {
                sendAck(
                    sessionId: envelope.sessionId,
                    messageId: envelope.messageId,
                    revision: envelope.sessionRevision
                )
                return true
            }
            guard pendingReclaimRequestMessageId != nil,
                  let snapshot = envelope.payload.snapshot else { return true }
            reclaimRequestTimeoutTask?.cancel()
            reclaimRequestTimeoutTask = nil
            mergeDetailedActions(envelope.payload.detailedActions)
            pendingReclaimAcceptance = .init(
                messageId: envelope.messageId,
                sessionId: envelope.sessionId,
                revision: envelope.sessionRevision,
                snapshot: snapshot,
                detailedActions: mergedDetailedActions
            )
            return true
        case .reclaimDenied:
            reclaimRequestTimeoutTask?.cancel()
            reclaimRequestTimeoutTask = nil
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
              envelope.sessionId == activeSessionId else { return false }
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
        activeRevision = max(activeRevision, envelope.sessionRevision)
        mergeDetailedActions(envelope.payload.detailedActions)
        latestSnapshot = .init(
            sessionId: envelope.sessionId,
            revision: envelope.sessionRevision,
            snapshot: envelope.payload.snapshot,
            detailedActions: mergedDetailedActions
        )
        WatchResumeSessionStore.shared.clear()
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
              envelope.sender == .phone,
              envelope.kind == .sessionLeft else { return false }
        if pendingConfirmRequest?.sessionId == envelope.sessionId {
            revisionGate.endSession(envelope.sessionId)
            pendingConfirmRequest = nil
            return true
        }
        guard envelope.sessionId == activeSessionId else { return false }
        WatchResumeSessionStore.shared.clear()
        endLocalSession()
        return true
    }

    private func handleStatusQuery(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: data),
              envelope.sender == .phone,
              envelope.kind == .statusQuery,
              let sessionId = activeSessionId,
              envelope.sessionId == sessionId,
              let role = controlRole else { return false }
        sequence += 1
        let response = LinkEnvelope(
            sessionId: sessionId,
            kind: .statusResponse,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: activeRevision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkStatusPayload(role: role, revision: activeRevision)
        )
        Task { try? await send(response) }
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
        recordAck: Bool = false,
        authoritativeSnapshot: LinkedScoreboardSnapshot? = nil,
        detailedActions: [DetailedScoreAction]? = nil
    ) {
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: sessionId,
            kind: recordAck ? .recordAcknowledgement : .acknowledgement,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkAcknowledgementPayload(
                acknowledgedMessageId: messageId,
                acknowledgedRevision: revision,
                authoritativeSnapshot: authoritativeSnapshot,
                detailedActions: detailedActions
            )
        )
        Task { try? await send(envelope) }
    }

    private func send<Payload: Codable & Sendable>(_ envelope: LinkEnvelope<Payload>) async throws {
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
                    if let data = self.pendingAck.retryIfDue(nowEpochMilliseconds: self.nowMs()) {
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

    private func endLocalSession() {
        if let id = revisionGate.activeSessionId {
            revisionGate.endSession(id)
        }
        activeSessionId = nil
        activeRevision = 0
        activeGameType = nil
        activeSetup = nil
        controlRole = nil
        acceptedSetup = nil
        pendingConfirmRequest = nil
        latestSnapshot = nil
        mergedDetailedActions = []
        phoneTookOver = false
        publishedFinishedRecordId = nil
        pendingReclaimAcceptance = nil
        pendingReclaimRequestMessageId = nil
        reclaimRequestTimeoutTask?.cancel()
        reclaimRequestTimeoutTask = nil
        pendingAck.clear()
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

    private func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
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
