import Foundation
import LinkCore
import Observation
import RecordCore
import ScoreCore

extension WatchLinkService {
    /// 解码失败（未知 payload schema / 未知快照类型）的 setupRequest 也要显式拒绝：
    /// 否则手表无应答，手机会干等 20s 才报“等待手表确认超时”。头部不依赖
    /// payload，任何协议版本都能解析出 sessionId/messageId 用于回执。
    private func handleMalformedSetupRequest(_ data: Data) {
        guard let head = try? JSONDecoder().decode(LinkEnvelopeHead.self, from: data),
              head.sender == .phone,
              head.kind == .setupRequest else { return }
        sendSetupRejection(
            handle: .init(sessionId: head.sessionId, matchId: head.matchId, matchGeneration: head.matchGeneration),
            requestId: head.messageId, reason: .malformedSetup
        )
    }

    func sendSetupRejection(
        handle: LinkedMatchHandle,
        requestId: UUID,
        reason: LinkSetupRejectionReason
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
            payload: LinkSetupRejectedPayload(reason: reason)
        )
        sendReportingError(envelope)
    }

    func receive(_ data: Data) {
        // 压缩完赛帧无法按 JSON 解码，必须最先探测魔数。
        if LinkFinishedEncoding.isCompressedFrame(data) {
            _ = handleMatchFinishedFromPhone(data)
            markCommunication()
            return
        }
        // 单次解码信封头，按 kind 精确派发。
        let handled: Bool
        if let head = try? JSONDecoder().decode(LinkEnvelopeHead.self, from: data) {
            switch head.kind {
            case .setupRequest: handled = handleSetupRequest(data)
            case .stateSnapshot: handled = handleSnapshotFromPhone(data)
            case .acknowledgement, .recordAcknowledgement: handled = handleAck(data)
            case .matchFinished: handled = handleMatchFinishedFromPhone(data)
            case .sessionLeft: handled = handleSessionLeft(data)
            case .resyncRequest: handled = handleResyncRequest(data)
            case .statusQuery: handled = handleStatusQuery(data)
            case .connectivityProbeResponse: handled = handleConnectivityProbeResponse(data)
            case .setupAccepted, .setupRejected, .matchStarted,
                 .scoreboardExitedToHome, .commonNamesSyncRequest,
                 .connectivityProbe, .statusResponse:
                handled = false // 不由手表端处理
            }
        } else {
            handled = false
        }
        if handled {
            markCommunication()
        } else {
            handleMalformedSetupRequest(data)
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
        let peerCapabilities = envelope.capabilities.intersection(envelope.payload.capabilities)
        guard (LinkProtocol.minimumSupportedVersion...LinkProtocol.currentVersion).contains(envelope.protocolVersion),
              let negotiated = LinkProtocol.negotiate(local: LinkProtocol.capabilities, peer: peerCapabilities) else {
            sendSetupRejection(
                handle: envelope.handle,
                requestId: envelope.messageId, reason: .incompatibleProtocol
            )
            return true
        }
        let supportsCompressedFinish = negotiated.contains(.compressedFinish) && envelope.supportsCompressedFinish == true
        guard Self.isValidLinkedSetup(envelope.payload),
              envelope.payload.gameType != .basketballTraining || supportsCompressedFinish else {
            sendSetupRejection(
                handle: envelope.handle,
                requestId: envelope.messageId, reason: .unsupportedSport
            )
            return true
        }
        if let existing = revisionGate.activeSessionId, existing != envelope.sessionId {
            WatchResumeSessionStore.shared.clear()
            endLocalSession()
        }
        _ = revisionGate.beginMatch(envelope.handle, initialRevision: envelope.sessionRevision)
        sessionMachine = LinkSessionStateMachine(
            handle: envelope.handle,
            revision: envelope.sessionRevision,
            lifecycle: .starting
        )
        _ = sessionMachine?.beginSetup(correlationId: envelope.messageId)
        latestSnapshot = nil
        acceptedSetup = nil
        pendingConfirmRequest = .init(
            handle: envelope.handle,
            messageId: envelope.messageId,
            setup: envelope.payload,
            peerSupportsCompressedFinish: supportsCompressedFinish,
            peerCapabilities: negotiated
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
        let acknowledgedSnapshot = deltaActionTracker.acknowledgedSnapshot(by: envelope, pending: pendingAck.pending)
        if pendingAck.pending?.messageId == messageId,
           deltaActionTracker.carriesHistory(messageId: messageId), acknowledgedSnapshot == nil {
            return false
        }
        if pendingAck.acknowledge(messageId: messageId) {
            deltaActionTracker.noteAcknowledged(messageId: messageId)
        }
        if var machine = sessionMachine {
            _ = machine.acknowledge(messageId: messageId)
            sessionMachine = machine
        }
        let terminalCandidate = terminalOutbox.items.first {
            $0.messageId == messageId
        }
        let previousOutbox = terminalOutbox
        let terminalItem: LinkDurableOutbox.Item?
        if let terminalCandidate, terminalCandidate.pendingLocalRecord == nil,
           envelope.kind == .recordAcknowledgement,
           envelope.handle == terminalCandidate.handle {
            terminalItem = terminalOutbox.acknowledge(messageId: messageId)
        } else {
            terminalItem = nil
        }
        if let terminalItem {
            // 先确认 outbox 更新已落盘，再标记同步状态，避免断电窗口内重复回传。
            guard persistTerminalOutbox() else {
                terminalOutbox = previousOutbox
                rescheduleRetryIfNeeded()
                return true
            }
            if let finishedEnvelope = LinkFinishedEncoding.decode(terminalItem.data), !finishedEnvelope.payload.recordId.isEmpty {
                recordSink.markSynced(recordId: finishedEnvelope.payload.recordId)
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

    private func handleSnapshotFromPhone(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<LinkedScoreboardSetup>.self, from: data),
              envelope.sender == .phone,
              envelope.kind == .stateSnapshot,
              let snapshot = envelope.payload.initialSnapshot,
              envelope.sessionId == activeSessionId,
              envelope.payload.gameType == activeGameType,
              Self.isValidLinkedSetup(envelope.payload),
              var machine = sessionMachine else { return false }

        guard LinkSharedRevision.writer(of: envelope.sessionRevision) == .phone else { return false }
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
        let beganNewMatch = machine.handle != previousHandle
        if sharedEditTracker.shouldShowNotice(for: envelope, now: nowMs()) {
            simultaneousEditNotice = UUID()
        }
        sessionMachine = machine
        synchronizeSessionStateFromMachine()

        if beganNewMatch {
            if let pending = pendingAck.pending, deltaActionTracker.carriesHistory(messageId: pending.messageId) {
                pendingAck.clear()
                sessionMachine?.acknowledge(messageId: pending.messageId)
                rescheduleRetryIfNeeded()
            }
            actionHistory = LinkSnapshotHistory()
            deltaActionTracker.reset()
            mergedDetailedActions = []
            latestSnapshot = nil
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
        let history = envelope.payload.carriesHistory
        let hasCurrentHistory = history && envelope.sessionRevision == machine.revision
        if validation == .current || hasCurrentHistory {
            actionHistory.noteRemoteRemovals(envelope.payload.removedActionIDs ?? [])
            mergeDetailedActions(envelope.payload.detailedActions)
            var updatedSetup = envelope.payload
            updatedSetup.detailedActions = mergedDetailedActions
            activeSetup = updatedSetup
            latestSnapshot = .init(
                sessionId: envelope.sessionId,
                revision: envelope.sessionRevision,
                matchGeneration: envelope.matchGeneration,
                snapshot: snapshot,
                detailedActions: mergedDetailedActions,
                removedActionIDs: actionHistory.removedActionIDs
            )
            if let context = resumeContext {
                if validation == .current {
                    WatchResumeSessionStore.shared.applyLinkedSnapshot(snapshot, context: context)
                } else {
                    WatchResumeSessionStore.shared.refreshLinkContext(context)
                }
            }
            persistContext()
        } else if history {
            // A checkpoint or newer edit can arrive first. Incorporate
            // history without changing the accepted score revision.
            actionHistory.noteRemoteRemovals(envelope.payload.removedActionIDs ?? [])
            mergeDetailedActions(envelope.payload.detailedActions)
            activeSetup?.detailedActions = mergedDetailedActions
            latestSnapshot?.detailedActions = mergedDetailedActions
            latestSnapshot?.removedActionIDs = actionHistory.removedActionIDs
            if let context = resumeContext {
                WatchResumeSessionStore.shared.refreshLinkContext(context)
            }
            persistContext()
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

    private func handleMatchFinishedFromPhone(_ data: Data) -> Bool {
        guard let envelope = LinkFinishedEncoding.decode(data),
              envelope.sender == .phone,
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
            guard recordSink.ingest(
                payload: payload, gameType: session.gameType, matchId: envelope.matchId, syncState: .sent
            ) != nil else {
                reportPersistenceError(CocoaError(.fileWriteUnknown))
                return true
            }

            if isActiveSession, var machine {
                _ = machine.markFinished(matchId: envelope.matchId)
                sessionMachine = machine
                synchronizeSessionStateFromMachine()
                if isCurrentMatch || beginsNewMatch {
                    if beginsNewMatch {
                        pendingAck.clear()
                        actionHistory = LinkSnapshotHistory()
                        deltaActionTracker.reset()
                        _ = revisionGate.beginMatch(envelope.handle, initialRevision: envelope.sessionRevision)
                    } else {
                        _ = revisionGate.classify(handle: envelope.handle, revision: envelope.sessionRevision)
                    }
                    mergedDetailedActions = payload.detailedActions
                    latestSnapshot = .init(
                        sessionId: envelope.sessionId,
                        revision: envelope.sessionRevision,
                        matchGeneration: envelope.matchGeneration,
                        snapshot: payload.snapshot,
                        detailedActions: payload.detailedActions,
                        removedActionIDs: actionHistory.removedActionIDs
                    )
                    activeSetup = LinkedScoreboardSetup(
                        gameType: session.gameType, maxSets: maxSets(for: payload.snapshot),
                        initialSnapshot: payload.snapshot, detailedActions: payload.detailedActions,
                        participantNames: payload.participantNames
                    )
                    WatchResumeSessionStore.shared.clear()
                }
                persistContext()
            } else {
                retiredRecordSessions.markFinished(envelope.handle)
            }
        }
        if session.gameType == .basketballTraining {
            cancelPendingTrainingFinish(handle: envelope.handle)
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
              envelope.sender == .phone,
              envelope.kind == .sessionLeft else { return false }
        if pendingConfirmRequest?.sessionId == envelope.sessionId {
            revisionGate.endSession(envelope.sessionId)
            pendingConfirmRequest = nil
            return true
        }
        guard envelope.handle == activeHandle else {
            retiredRecordSessions.removeConfirmedSession(handle: envelope.handle)
            return false
        }
        let pendingCount = pendingSessionEnds.count
        pendingSessionEnds.removeAll { $0.handle.sessionId == envelope.sessionId }
        if pendingSessionEnds.count != pendingCount {
            persistPendingSessionEnds()
        }
        rescheduleRetryIfNeeded()
        WatchResumeSessionStore.shared.clear()
        endLocalSession()
        retiredRecordSessions.removeConfirmedSession(handle: envelope.handle)
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

    private func handleResyncRequest(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(LinkEnvelope<EmptyLinkPayload>.self, from: data),
              envelope.sender == .phone,
              envelope.kind == .resyncRequest,
              envelope.sessionId == activeSessionId,
              LinkManualResyncPolicy.canRequest(hasActiveSession: true),
              let setup = activeSetup,
              let snapshot = setup.initialSnapshot else { return false }
        // 手机端手动同步意味着它要全量动作历史：清空本地增量台账。
        deltaActionTracker.reset()
        publishSnapshot(
            snapshot,
            detailedActions: mergedDetailedActions,
            participantNames: setup.participantNames
        )
        return true
    }
}
