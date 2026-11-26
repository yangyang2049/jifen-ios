import Foundation
import LinkCore
import Observation
import RecordCore
import ScoreCore
import UIKit


extension PhoneWatchLinkService {
    func handleIncoming(_ data: Data) {
        // 压缩完赛帧无法按 JSON 解码，必须最先探测魔数。
        if LinkFinishedEncoding.isCompressedFrame(data) {
            _ = handleMatchFinishedFromWatch(data)
            return
        }
        // 单次解码信封头，按 kind 精确派发；解码失败的帧直接丢弃。
        guard let head = try? JSONDecoder().decode(LinkEnvelopeHead.self, from: data) else { return }
        switch head.kind {
        case .commonNamesSyncRequest: _ = handleCommonNamesSyncRequest(data)
        case .connectivityProbe: _ = handleConnectivityProbe(data)
        case .setupAccepted, .setupRejected: _ = handleSetupResponse(data)
        case .acknowledgement, .recordAcknowledgement: _ = handleAck(data)
        case .stateSnapshot: _ = handleSnapshotFromWatch(data)
        case .matchFinished: _ = handleMatchFinishedFromWatch(data)
        case .scoreboardExitedToHome: _ = handleScoreboardExitedToHome(data)
        case .sessionLeft: _ = handleSessionLeft(data)
        case .statusQuery, .statusResponse: _ = handleStatus(data)
        case .setupRequest, .matchStarted, .resyncRequest, .connectivityProbeResponse:
            break // 不由手机端处理
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
            pendingSetupMessageId = nil
            persistContext()
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

    private func handleAck(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkAcknowledgementPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .acknowledgement || envelope.kind == .recordAcknowledgement,
              envelope.correlationId == envelope.payload.acknowledgedMessageId else {
            return false
        }
        let acknowledgedMessageId = envelope.payload.acknowledgedMessageId
        let acknowledgedSnapshot = deltaActionTracker.acknowledgedSnapshot(by: envelope, pending: pendingAck.pending)
        if pendingAck.pending?.messageId == acknowledgedMessageId,
           deltaActionTracker.carriesHistory(messageId: acknowledgedMessageId), acknowledgedSnapshot == nil {
            return false
        }
        if pendingAck.acknowledge(messageId: acknowledgedMessageId) {
            deltaActionTracker.noteAcknowledged(messageId: acknowledgedMessageId)
        }
        if var machine = sessionMachine {
            _ = machine.acknowledge(messageId: acknowledgedMessageId)
            sessionMachine = machine
        }
        let terminalCandidate = terminalOutbox.items.first {
            $0.messageId == acknowledgedMessageId
        }
        let previousOutbox = terminalOutbox
        let terminalItem: LinkDurableOutbox.Item?
        if let terminalCandidate,
           envelope.kind == .recordAcknowledgement,
           envelope.handle == terminalCandidate.handle {
            terminalItem = terminalOutbox.acknowledge(messageId: acknowledgedMessageId)
        } else {
            terminalItem = nil
        }
        if terminalItem != nil {
            guard persistTerminalOutbox() else {
                terminalOutbox = previousOutbox
                rescheduleRetryIfNeeded()
                return true
            }
            persistContext()
            flushPendingSessionEnds()
        }
        if let acknowledgedSnapshot {
            sendRemainingActions(after: acknowledgedSnapshot)
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
              snapshot.matches(gameType: session.gameType),
              var machine = sessionMachine else {
            return false
        }

        guard LinkSharedRevision.writer(of: envelope.sessionRevision) == .watch else { return false }
        if machine.completedMatchIds.contains(envelope.matchId) {
            sendAck(
                sessionId: envelope.sessionId, messageId: envelope.messageId,
                revision: envelope.sessionRevision, handle: envelope.handle
            )
            return true
        }
        let previousHandle = machine.handle
        let validation = machine.accept(
            handle: envelope.handle,
            revision: envelope.sessionRevision
        )
        guard validation == .current || validation == .duplicateOrOlder else {
            return false
        }
        if sharedEditTracker.shouldShowNotice(for: envelope, now: nowMs()) {
            simultaneousEditNotice = UUID()
        }
        let beganNewMatch = machine.handle != previousHandle
        sessionMachine = machine
        synchronizeActiveSessionFromStateMachine()

        if beganNewMatch {
            if let pending = pendingAck.pending, deltaActionTracker.carriesHistory(messageId: pending.messageId) {
                pendingAck.clear()
                sessionMachine?.acknowledge(messageId: pending.messageId)
                rescheduleRetryIfNeeded()
            }
            actionHistory = LinkSnapshotHistory()
            deltaActionTracker.reset()
            if var newSession = activeSession {
                newSession.setup = envelope.payload
                activeSession = newSession
            }
            finishedRecordId = nil
            mergedDetailedActions = []
            latestRemoteSnapshot = nil
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

        // Application context can arrive ahead of the realtime copy with the
        // same revision. The realtime copy can still supply the action history.
        let history = envelope.payload.carriesHistory
        if validation == .current, var session = activeSession {
            actionHistory.noteRemoteRemovals(envelope.payload.removedActionIDs ?? [])
            mergeDetailedActions(envelope.payload.detailedActions)
            var updatedSetup = envelope.payload
            updatedSetup.detailedActions = mergedDetailedActions
            session.setup = updatedSetup
            activeSession = session
            latestRemoteSnapshot = LinkedSnapshotUpdate(
                sessionId: envelope.sessionId,
                revision: envelope.sessionRevision,
                matchGeneration: envelope.matchGeneration,
                snapshot: snapshot,
                detailedActions: mergedDetailedActions
            )
            persistContext()
        } else if history {
            // A checkpoint or newer edit can arrive first. Incorporate
            // history without changing the accepted score revision.
            actionHistory.noteRemoteRemovals(envelope.payload.removedActionIDs ?? [])
            mergeDetailedActions(envelope.payload.detailedActions)
            if var session = activeSession {
                session.setup.detailedActions = mergedDetailedActions
                activeSession = session
            }
            latestRemoteSnapshot?.detailedActions = mergedDetailedActions
            persistContext()
        }
        if validation == .duplicateOrOlder, snapshot.isFinished {
            // Mirror HarmonyOS: a finished snapshot is authoritative for the
            // finish dialog even when its revision is older than the machine's —
            // the match-finished envelope may have been accepted first, leaving
            // the machine's revision ahead of the final state snapshot. Surfacing
            // the finished duplicate is idempotent: it can only keep or re-open
            // the dialog, never dismiss it, and the view-side revision gate still
            // rejects stale unfinished states.
            latestRemoteSnapshot = LinkedSnapshotUpdate(
                sessionId: envelope.sessionId,
                revision: envelope.sessionRevision,
                matchGeneration: envelope.matchGeneration,
                snapshot: snapshot,
                detailedActions: mergedDetailedActions
            )
        }
        // ACK valid duplicates too: a retry usually means our prior ACK was lost.
        sendAck(
            sessionId: envelope.sessionId,
            messageId: envelope.messageId,
            revision: envelope.sessionRevision,
            handle: envelope.handle
        )
        return true
    }

    func handleMatchFinishedFromWatch(_ data: Data) -> Bool {
        guard let envelope = LinkFinishedEncoding.decode(data),
              envelope.sender == .watch,
              envelope.kind == .matchFinished,
              envelope.protocolVersion == LinkProtocol.currentVersion else { return false }
        let liveSession = activeRecordSession
        let isActiveSession = liveSession?.handle.sessionId == envelope.sessionId
        let session = isActiveSession ? liveSession : retiredRecordSessions[envelope.sessionId]
        guard let session, session.accepts(handle: envelope.handle),
              envelope.payload.snapshot.matches(gameType: session.gameType) else { return false }

        if !session.completedMatchIds.contains(envelope.matchId) {
            let isCurrentMatch = liveSession?.handle == envelope.handle
            let beginsNewMatch = isActiveSession && envelope.matchGeneration > session.handle.matchGeneration
            var machine = sessionMachine
            if isCurrentMatch || beginsNewMatch {
                let validation = machine?.accept(
                    handle: envelope.handle,
                    revision: envelope.sessionRevision
                )
                guard validation == .current || validation == .duplicateOrOlder else { return false }
            }
            var payload = envelope.payload
            if isCurrentMatch {
                mergeDetailedActions(payload.detailedActions)
                payload.detailedActions = mergedDetailedActions
            }

            let recordID: String
            do {
                recordID = try recordSink.ingest(payload: payload, gameType: session.gameType, matchId: envelope.matchId)
            } catch {
                // Keeping the ACK pending lets the sender retry a failed write.
                lastErrorMessage = error.localizedDescription
                return true
            }

            if isActiveSession, var machine {
                _ = machine.markFinished(matchId: envelope.matchId)
                sessionMachine = machine
                synchronizeActiveSessionFromStateMachine()
                if isCurrentMatch || beginsNewMatch {
                    if beginsNewMatch {
                        pendingAck.clear()
                        _ = revisionGate.beginMatch(envelope.handle, initialRevision: envelope.sessionRevision)
                    } else {
                        _ = revisionGate.classify(handle: envelope.handle, revision: envelope.sessionRevision)
                    }
                    mergedDetailedActions = payload.detailedActions
                    finishedRecordId = recordID
                    latestRemoteSnapshot = .init(
                        sessionId: envelope.sessionId,
                        revision: envelope.sessionRevision,
                        matchGeneration: envelope.matchGeneration,
                        snapshot: payload.snapshot,
                        detailedActions: payload.detailedActions
                    )
                    activeSession?.setup = LinkedScoreboardSetup(
                        gameType: session.gameType, maxSets: maxSets(for: payload.snapshot),
                        initialSnapshot: payload.snapshot, detailedActions: payload.detailedActions,
                        participantNames: payload.participantNames
                    )
                }
                persistContext()
            } else {
                retiredRecordSessions.markFinished(envelope.handle)
            }
        }
        sendAck(
            sessionId: envelope.sessionId,
            messageId: envelope.messageId,
            revision: envelope.sessionRevision,
            handle: envelope.handle,
            recordAck: true
        )
        return true
    }

    private func handleSessionLeft(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: data),
              envelope.sender == .watch,
              envelope.kind == .sessionLeft else { return false }
        guard envelope.handle == activeSession?.handle else {
            retiredRecordSessions.removeConfirmedSession(handle: envelope.handle)
            return false
        }
        let pendingCount = pendingSessionEnds.count
        pendingSessionEnds.removeAll { $0.handle.sessionId == envelope.sessionId }
        if pendingSessionEnds.count != pendingCount {
            persistPendingSessionEnds()
            rescheduleRetryIfNeeded()
        }
        clearSession()
        retiredRecordSessions.removeConfirmedSession(handle: envelope.handle)
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
