import Foundation
import LinkCore
import Observation
import RecordCore
import ScoreCore

extension WatchLinkService {
    func sendSetupRejection(
        handle: LinkedMatchHandle,
        requestId: UUID,
        reason: LinkSetupRejectionReason,
        detail: String? = nil
    ) {
        sequence += 1
        let envelope = LinkEnvelope(
            correlationId: requestId,
            sessionId: handle.sessionId,
            matchId: handle.matchId,
            matchGeneration: handle.matchGeneration,
            kind: .setupRejected,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: 0,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkSetupRejectedPayload(reason: reason, detail: detail)
        )
        sendReportingError(envelope)
    }

    func receive(_ data: Data) {
        guard case .envelope(let head, let frame) = intentSessionEngine.route(data),
              head.kind == .setupRequest || head.protocolVersion == LinkProtocol.currentVersion else { return }
        let handled: Bool
        switch head.kind {
        case .setupRequest:
            handled = handleSetupRequest(frame, head: head)
        case .intentCommit, .intentCheckpoint, .matchStarted, .resyncRequest:
            handled = intentSync.handleIncoming(frame, head: head)
        case .sessionLeft:
            handled = handleSessionLeft(frame)
        case .statusQuery:
            handled = handleStatusQuery(frame)
        case .connectivityProbeResponse:
            handled = handleConnectivityProbeResponse(frame)
        default:
            // Scores and terminal results have exactly one authority: typed intents.
            handled = false
        }
        if handled { markCommunication() }
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

    private func handleSetupRequest(_ data: Data, head: LinkEnvelopeHead) -> Bool {
        let handle = LinkedMatchHandle(
            sessionId: head.sessionId, matchId: head.matchId, matchGeneration: head.matchGeneration
        )
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkedScoreboardSetup>.self, from: data) else {
            sendSetupRejection(handle: handle, requestId: head.messageId, reason: .malformedSetup)
            return true
        }
        let peer = envelope.capabilities.intersection(envelope.payload.capabilities)
        guard (LinkProtocol.minimumSupportedVersion...LinkProtocol.currentVersion).contains(envelope.protocolVersion),
              let negotiated = LinkProtocol.negotiate(local: LinkProtocol.capabilities, peer: peer),
              negotiated.contains(.sharedIntentSync) else {
            sendSetupRejection(handle: handle, requestId: head.messageId, reason: .incompatibleProtocol)
            return true
        }
        guard envelope.sessionRevision == 0, envelope.payload.initialSnapshot != nil,
              Self.isValidLinkedSetup(envelope.payload) else {
            sendSetupRejection(handle: handle, requestId: head.messageId, reason: .unsupportedSport)
            return true
        }

        do {
            if try isRetiredIntentHandle(handle) || pendingSessionEnds.contains(where: { $0.handle == handle }) {
                return false
            }
        } catch {
            reportPersistenceError(error)
            return false
        }
        let request = LinkedSetupRequest(
            handle: handle, messageId: envelope.messageId, setup: envelope.payload,
            senderEpochMilliseconds: envelope.sentAtEpochMilliseconds, peerCapabilities: negotiated
        )
        if activeHandle == handle {
            guard activeGameType == request.setup.gameType else { return false }
            sendSetupAcceptance(request)
        } else if hasPendingIntentFinish {
            sendSetupRejection(
                handle: handle, requestId: envelope.messageId, reason: .userDeclined, detail: "finish_pending"
            )
        } else if activeHandle?.sessionId == handle.sessionId {
            return false // A new match in this session requires a phone matchStarted frame.
        } else {
            pendingConfirmRequest = request
        }
        return true
    }

    private func handleSessionLeft(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: data) else {
            return false
        }
        let handle = envelope.handle
        if pendingConfirmRequest?.handle == handle {
            pendingConfirmRequest = nil
            return true
        }
        guard handle == activeHandle else { return false }
        guard endLocalSession() else { return true }
        WatchResumeSessionStore.shared.clear()
        return true
    }

    private func handleStatusQuery(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: data),
              envelope.sender == .phone,
              envelope.kind == .statusQuery,
              let sessionId = activeSessionId,
              envelope.handle == activeHandle else { return false }
        sequence += 1
        let response = LinkEnvelope(
            correlationId: envelope.messageId,
            sessionId: sessionId,
            matchId: activeHandle?.matchId,
            matchGeneration: activeHandle?.matchGeneration ?? 1,
            kind: .statusResponse,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: activeRevision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkStatusPayload(revision: activeRevision)
        )
        sendReportingError(response)
        return true
    }

}
