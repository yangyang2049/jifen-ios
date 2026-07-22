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
    private var activeSessionId: UUID?
    private var activeRevision: UInt64 = 0
    private var activeGameType: GameType?
    private var ackRetryTask: Task<Void, Never>?

    init() {
        transport.onReceive = { [weak self] data in
            DispatchQueue.main.async {
                self?.receive(data)
            }
        }
        transport.activate()
        startAckRetryLoop()
    }

    var isController: Bool {
        controlRole == .watchController
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
        manualEnd: Bool
    ) {
        guard let sessionId = activeSessionId else { return }
        activeRevision += 1
        sequence += 1
        let messageId = UUID()
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
                recordId: recordId,
                winnerSide: winnerSide,
                manualEnd: manualEnd
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
              envelope.protocolVersion == LinkProtocol.currentVersion,
              envelope.sender == .phone,
              envelope.kind == .setupRequest else { return false }
        if let existing = revisionGate.activeSessionId, existing != envelope.sessionId {
            revisionGate.endSession(existing)
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
              envelope.sessionId == activeSessionId,
              revisionGate.accept(sessionId: envelope.sessionId, revision: envelope.sessionRevision)
                || activeRevision < envelope.sessionRevision else { return false }
        activeRevision = max(activeRevision, envelope.sessionRevision)
        latestSnapshot = .init(
            sessionId: envelope.sessionId,
            revision: envelope.sessionRevision,
            snapshot: snapshot
        )
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
        return true
    }

    private func handleSessionLeft(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: data),
              envelope.sender == .phone,
              envelope.kind == .sessionLeft,
              envelope.sessionId == activeSessionId else { return false }
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
        if let id = activeSessionId {
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
