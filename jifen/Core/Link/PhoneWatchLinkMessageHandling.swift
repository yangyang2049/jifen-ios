import Foundation
import LinkCore
import Observation
import RecordCore
import ScoreCore
import UIKit


extension PhoneWatchLinkService {
    func handleIncoming(_ data: Data) {
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
                    matchGeneration: session.handle.matchGeneration,
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
                    matchGeneration: session.handle.matchGeneration,
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
        rescheduleRetryIfNeeded()
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
                matchGeneration: envelope.matchGeneration,
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
                matchGeneration: envelope.matchGeneration,
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
        resumeStatusContinuations(returning: envelope.payload)
        return true
    }
}
