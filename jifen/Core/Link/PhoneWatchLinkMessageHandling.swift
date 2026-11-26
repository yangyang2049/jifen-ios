import Foundation
import LinkCore
import Observation
import RecordCore
import ScoreCore
import UIKit


extension PhoneWatchLinkService {
    func handleIncoming(_ data: Data) {
        guard case .envelope(let head, let data) = intentSessionEngine.route(data) else { return }
        switch head.kind {
        case .commonNamesSyncRequest: _ = handleCommonNamesSyncRequest(data)
        case .connectivityProbe: _ = handleConnectivityProbe(data)
        case .setupAccepted, .setupRejected: _ = handleSetupResponse(data)
        case .intentSubmit: receiveWatchIntent(data)
        case .resyncRequest: receiveWatchIntentRecoveryRequest(data)
        case .scoreboardExitedToHome: _ = handleScoreboardExitedToHome(data)
        case .sessionLeft: _ = handleSessionLeft(data)
        case .statusQuery, .statusResponse: _ = handleStatus(data)
        case .setupRequest, .matchStarted, .intentCommit, .intentCheckpoint, .acknowledgement, .recordAcknowledgement,
             .stateSnapshot, .matchFinished, .connectivityProbeResponse:
            break
        }
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
           accepted.correlationId == pendingSetupMessageId {
            setupTimeoutTask?.cancel()
            setupTimeoutTask = nil
            guard (LinkProtocol.minimumSupportedVersion...LinkProtocol.currentVersion).contains(accepted.protocolVersion),
                  let negotiated = LinkProtocol.negotiate(local: LinkProtocol.capabilities, peer: accepted.capabilities) else {
                failSetupAcceptance(sessionId: accepted.sessionId, reason: .incompatibleProtocol)
                return true
            }
            let supportsCompressedFinish = negotiated.contains(.compressedFinish) && accepted.supportsCompressedFinish == true
            if activeSession?.gameType == .basketballTraining, !supportsCompressedFinish {
                failSetupAcceptance(sessionId: accepted.sessionId, reason: .unsupportedSport)
                return true
            }
            peerSupportsCompressedFinish = supportsCompressedFinish
            negotiatedPeerCapabilities = negotiated
            if let correlationId = accepted.correlationId,
               var machine = sessionMachine,
               machine.resolveSetup(
                   correlationId: correlationId,
                   accepted: true
               ) {
                sessionMachine = machine
                synchronizeActiveSessionFromStateMachine()
            }
            if let session = activeSession,
               let snapshot = session.setup.initialSnapshot {
                latestRemoteSnapshot = .init(
                    sessionId: session.sessionId,
                    revision: session.revision,
                    matchGeneration: session.handle.matchGeneration,
                    snapshot: snapshot,
                    detailedActions: session.setup.detailedActions
                )
            }
            guard persistContext() else {
                failSetupAcceptance(sessionId: accepted.sessionId, reason: .malformedSetup)
                return true
            }
            pendingSetupMessageId = nil
            trackSetupAnalyticsResult(.success)
            setupContinuation?.resume(returning: accepted.sessionId)
            setupContinuation = nil
            return true
        }
        if let rejected = try? JSONDecoder().decode(LinkEnvelope<LinkSetupRejectedPayload>.self, from: data),
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
                    accepted: false
                )
                sessionMachine = machine
            }
            clearSession()
            pendingSetupMessageId = nil
            lastSetupRejectionReason = rejected.payload.reason
            trackSetupAnalyticsResult(.rejected)
            setupContinuation?.resume(throwing: InteractiveStartError.setupRejected)
            setupContinuation = nil
            return true
        }
        return false
    }

    private func failSetupAcceptance(sessionId: UUID, reason: LinkSetupRejectionReason) {
        let continuation = setupContinuation
        setupContinuation = nil
        pendingSetupMessageId = nil
        leaveSession(sessionId)
        clearSession()
        lastSetupRejectionReason = reason
        trackSetupAnalyticsResult(.rejected)
        continuation?.resume(throwing: InteractiveStartError.setupRejected)
    }

    private func handleSessionLeft(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .sessionLeft else { return false }
        guard envelope.handle == activeSession?.handle else { return false }
        let pendingCount = pendingSessionEnds.count
        pendingSessionEnds.removeAll { $0.handle.sessionId == envelope.sessionId }
        if pendingSessionEnds.count != pendingCount {
            persistPendingSessionEnds()
            rescheduleRetryIfNeeded()
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

    private func handleStatus(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkStatusPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .statusResponse,
              envelope.correlationId == pendingStatusCorrelationId,
              let session = activeSession,
              envelope.sessionId == session.sessionId,
              envelope.handle == session.handle else { return false }
        pendingStatusCorrelationId = nil
        statusTimeoutTask?.cancel()
        statusTimeoutTask = nil
        resumeStatusContinuations(returning: envelope.payload)
        return true
    }
}
