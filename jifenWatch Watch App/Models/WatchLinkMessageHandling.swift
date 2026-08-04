import Foundation
import LinkCore
import Observation
import RecordCore
import ScoreCore

extension WatchLinkService {
    func receive(_ data: Data) {
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
        rescheduleRetryIfNeeded()
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
        rescheduleRetryIfNeeded()
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
}
