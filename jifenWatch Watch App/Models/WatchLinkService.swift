import Foundation
import LinkCore
import Observation
import ScoreCore

struct LinkedSetupRequest: Equatable {
    let sessionId: UUID
    let setup: LinkedScoreboardSetup
}

struct LinkedSnapshotUpdate: Equatable {
    let sessionId: UUID
    let revision: UInt64
    let snapshot: LinkedScoreboardSnapshot
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

    private let transport = WatchConnectivityTransport()
    private var revisionGate = LinkRevisionGate()
    private var sequence: UInt64 = 0
    private var pendingAck = LinkPendingAckQueue()
    private var publishedFinishedRecordId: String?
    private var activeSessionId: UUID?
    private var activeRevision: UInt64 = 0
    private var activeGameType: GameType?
    private var ackRetryTask: Task<Void, Never>?
    private let pendingWatchRecordsKey = "watch_pending_record_transfers_v1"
    private var pendingWatchRecords: [WatchRecordTransferPayload] = []
    private let pendingCommonNameUsageKey = "watch_pending_common_name_usage_v1"
    private var pendingCommonNameUsage: [CommonNameUsagePayload] = []

    init() {
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
        transport.onStatusChange = { [weak self] status in
            guard status.isActivated else { return }
            DispatchQueue.main.async {
                self?.flushPendingWatchRecords()
                self?.flushPendingCommonNameUsage()
            }
        }
        transport.activate()
        startAckRetryLoop()
        handleApplicationContext(transport.receivedApplicationContext)
        WatchRecordManager.shared.recordTransferHandler = { [weak self] payload in
            self?.transferFinishedRecord(payload)
        }
    }

    var isController: Bool {
        controlRole == .watchController
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
        pendingCommonNameUsage.append(CommonNameUsagePayload(names: normalized))
        persistPendingCommonNameUsage()
        flushPendingCommonNameUsage()
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
    }

    var isFollower: Bool {
        controlRole == .watchFollower
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

    func publishSnapshot(_ snapshot: LinkedScoreboardSnapshot) {
        guard isController,
              let sessionId = activeSessionId,
              let gameType = activeGameType else { return }
        activeRevision += 1
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
                initialSnapshot: snapshot
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
        totalScoreChanges: Int? = nil
    ) {
        guard let sessionId = activeSessionId else { return }
        // One finished record per linked session — keep a stable id for ACK retries.
        if publishedFinishedRecordId != nil { return }
        let stableRecordId = recordId.isEmpty ? "w_\(UUID().uuidString)" : recordId
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
                totalScoreChanges: totalScoreChanges
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

    func leaveSession() {
        guard let sessionId = activeSessionId else { return }
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
        endLocalSession()
    }

    private func receive(_ data: Data) {
        if handleSetupRequest(data) { return }
        if handleAck(data) { return }
        if handleSnapshotFromPhone(data) { return }
        if handleTakeover(data) { return }
        if handleSessionLeft(data) { return }
        _ = handleStatusQuery(data)
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
            endLocalSession()
        }
        _ = revisionGate.beginSession(envelope.sessionId, initialRevision: envelope.sessionRevision)
        latestSnapshot = nil
        acceptedSetup = nil
        phoneTookOver = false
        controlRole = nil
        pendingConfirmRequest = .init(sessionId: envelope.sessionId, setup: envelope.payload)
        return true
    }

    private func handleAck(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkAcknowledgementPayload>.self, from: data),
              envelope.sender == .phone,
              envelope.kind == .acknowledgement || envelope.kind == .recordAcknowledgement else {
            return false
        }
        _ = pendingAck.acknowledge(messageId: envelope.payload.acknowledgedMessageId)
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
            latestSnapshot = .init(
                sessionId: envelope.sessionId,
                revision: envelope.sessionRevision,
                snapshot: snapshot
            )
        }
        // ACK valid duplicates too: a retry usually means our prior ACK was lost.
        sendAck(sessionId: envelope.sessionId, messageId: envelope.messageId, revision: envelope.sessionRevision)
        return true
    }

    private func handleTakeover(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: data),
              envelope.sender == .phone,
              envelope.kind == .takeoverByPhone,
              envelope.sessionId == activeSessionId else { return false }
        controlRole = .watchFollower
        phoneTookOver = true
        sendAck(
            sessionId: envelope.sessionId,
            messageId: envelope.messageId,
            revision: envelope.sessionRevision
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

    private func sendAck(sessionId: UUID, messageId: UUID, revision: UInt64) {
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: sessionId,
            kind: .acknowledgement,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkAcknowledgementPayload(
                acknowledgedMessageId: messageId,
                acknowledgedRevision: revision
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
        controlRole = nil
        acceptedSetup = nil
        pendingConfirmRequest = nil
        latestSnapshot = nil
        phoneTookOver = false
        publishedFinishedRecordId = nil
        pendingAck.clear()
    }

    private func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
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
