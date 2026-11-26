import Foundation
import LinkCore
import Observation
import RecordCore
import ScoreCore

extension WatchLinkService {
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
        var storedSetup = setup
        storedSetup.detailedActions = []
        storedSetup.removedActionIDs = nil
        return WatchLinkResumeContext(
            handle: handle,
            setup: storedSetup,
            role: controlRole,
            authorityEpoch: authorityEpoch,
            revision: activeRevision,
            latestAuthoritativeSnapshot: latestSnapshot?.snapshot
                ?? setup.initialSnapshot,
            detailedActions: mergedDetailedActions,
            completedMatchIds: publishedFinishedMatchIds,
            pendingTerminalMessageIds: Set(terminalOutbox.items.map(\.messageId)),
            peerSupportsCompressedFinish: peerSupportsCompressedFinish,
            negotiatedPeerCapabilities: negotiatedPeerCapabilities,
            actionHistory: actionHistory
        )
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
                  acceptedRole: request.peerSupportsSharedEditing ? .shared : .watchController
              ) else { return }
        pendingConfirmRequest = nil
        sessionMachine = machine
        synchronizeSessionStateFromMachine()
        activeGameType = request.setup.gameType
        activeSetup = request.setup
        peerSupportsCompressedFinish = request.peerSupportsCompressedFinish
        negotiatedPeerCapabilities = request.peerCapabilities
        phoneTookOver = false
        acceptedSetup = request
        persistContext()
        sequence += 1
        let envelope = LinkEnvelope(
            capabilities: request.peerCapabilities,
            supportsCompressedFinish: request.peerCapabilities.contains(.compressedFinish),
            supportsSharedEditing: request.peerSupportsSharedEditing ? true : nil,
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
        sendSetupRejection(
            handle: request.handle, authorityEpoch: request.authorityEpoch,
            requestId: request.messageId, reason: .userDeclined
        )
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
        guard canEditLinkedMatch,
              let sessionId = activeSessionId,
              let gameType = activeGameType,
              var machine = sessionMachine,
              !machine.completedMatchIds.contains(machine.handle.matchId) else { return }
        let shared = machine.role == .shared
        let baseRevision = machine.revision
        _ = machine.advanceRevision(sender: .watch)
        sessionMachine = machine
        synchronizeSessionStateFromMachine()
        applyLocalHistory(detailedActions)
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
            matchGeneration: machine.handle.matchGeneration,
            snapshot: snapshot,
            detailedActions: mergedDetailedActions,
            removedActionIDs: actionHistory.removedActionIDs
        )
        persistContext()
        sequence += 1
        let messageId = UUID()
        let envelope = LinkEnvelope(
            baseSnapshotRevision: shared ? baseRevision : nil,
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
            payload: deltaSnapshotSetup(
                snapshot: snapshot,
                gameType: gameType,
                maxSets: maxSets(for: snapshot),
                participantNames: activeSetup?.participantNames ?? [],
                fullActions: mergedDetailedActions
            )
        )
        if shared {
            sharedEditTracker.recordLocalEdit(
                handle: envelope.handle, revision: envelope.sessionRevision,
                baseRevision: baseRevision, sentAt: envelope.sentAtEpochMilliseconds
            )
        }
        Task {
            guard activeHandle == envelope.handle, canEditLinkedMatch else { return }
            let isLatest = activeRevision == envelope.sessionRevision
            let supersededByPhone = shared && LinkSharedRevision.writer(of: activeRevision) == .phone
            guard isLatest || supersededByPhone else { return }
            let frame = LinkEnvelopeEncoding.snapshotFrame(envelope)
            if !isLatest {
                // Retain the history from a concurrent local edit without
                // publishing its now-older score as the latest checkpoint.
                guard !frame.data.isEmpty else { return }
                if frame.carriesHistory, (pendingAck.pending?.revision ?? 0) < envelope.sessionRevision {
                    enqueueLiveSnapshot(envelope, frame: frame)
                }
                if transport.isReachable { try? await transport.sendRealtime(frame.data) }
                return
            }
            if !frame.data.isEmpty { enqueueLiveSnapshot(envelope, frame: frame) }
            do {
                try transport.publishLatestSnapshot(
                    LinkEnvelopeEncoding.applicationContextData(envelope)
                )
                guard !frame.data.isEmpty else { return }
                if transport.isReachable || !shared {
                    try await transport.sendRealtime(frame.data)
                }
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
        guard canEditLinkedMatch,
              let gameType = activeGameType,
              var machine = sessionMachine else { return }
        let nextHandle = machine.beginNextMatch()
        pendingAck.clear()
        actionHistory = LinkSnapshotHistory()
        deltaActionTracker.reset()
        pendingSessionEnds.removeAll { $0.handle.sessionId == nextHandle.sessionId }
        persistPendingSessionEnds()
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

    @discardableResult
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
    ) -> Bool {
        guard canEditLinkedMatch, let handle = activeHandle, let gameType = activeGameType,
              var machine = sessionMachine else { return false }
        if peerFinishedSharedMatch || machine.completedMatchIds.contains(handle.matchId) {
            return true
        }
        if let item = terminalOutbox.items.first(where: { $0.handle == handle }) {
            guard item.pendingLocalRecord != nil else { return true }
            return saveLocalFinishedRecordAndSend(item)
        }
        if publishedFinishedMatchIds.contains(handle.matchId) { return true }
        let stableRecordId = recordId.isEmpty ? "w_\(handle.matchId.uuidString)" : recordId
        mergeDetailedActions(detailedActions)
        let finishRevision = machine.advanceRevision(sender: .watch)
        sequence += 1
        let messageId = UUID()
        let end = endTime ?? Date()
        let start = startTime ?? end.addingTimeInterval(-60)
        let duration = max(1, end.timeIntervalSince(start))
        let payload = LinkMatchFinishedPayload(
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
        let envelope = LinkEnvelope(
            messageId: messageId,
            sessionId: handle.sessionId,
            matchId: handle.matchId,
            matchGeneration: handle.matchGeneration,
            authorityEpoch: authorityEpoch,
            kind: .matchFinished,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: finishRevision,
            sentAtEpochMilliseconds: nowMs(),
            payload: payload
        )
        // 完整完赛包先持久化（outbox + pendingLocalRecord），再按协商结果选通道。
        let data = LinkFinishedFrameBuilder.buildFrame(
            envelope,
            peerSupportsCompressedFinish: peerSupportsCompressedFinish
        )
        guard !data.isEmpty else {
            reportPersistenceError(CocoaError(.fileWriteUnknown))
            return false
        }
        let item = LinkDurableOutbox.Item(
            messageId: messageId,
            handle: handle,
            data: data,
            lastSentAtEpochMilliseconds: nowMs(),
            pendingLocalRecord: .init(gameType: gameType, payload: payload),
            peerSupportsFileTransfer: peerSupportsFileTransfer
        )
        terminalOutbox.enqueue(item)
        // 落盘确认成功才允许继续（本地记录保存 + 发送）。
        guard persistTerminalOutbox() else {
            reportPersistenceError(CocoaError(.fileWriteUnknown))
            rescheduleRetryIfNeeded()
            return false
        }
        rescheduleRetryIfNeeded()
        return saveLocalFinishedRecordAndSend(item)
    }

    private func saveLocalFinishedRecordAndSend(_ item: LinkDurableOutbox.Item) -> Bool {
        guard prepareLocalFinishedRecord(item) else { return false }
        Task {
            await deliverTerminalFrame(item.data)
        }
        return true
    }

    func cancelPendingTrainingFinish(handle: LinkedMatchHandle) {
        guard let item = terminalOutbox.items.first(where: {
            $0.handle == handle && $0.pendingLocalRecord?.gameType == .basketballTraining
        }) else { return }
        // No terminal message is sent before its local record is saved.
        terminalOutbox.acknowledge(messageId: item.messageId)
        persistTerminalOutbox()
        rescheduleRetryIfNeeded()
    }

    func prepareLocalFinishedRecord(_ item: LinkDurableOutbox.Item) -> Bool {
        guard let local = item.pendingLocalRecord else { return true }
        guard let envelope = LinkFinishedEncoding.decode(item.data),
              recordSink.ingest(
                  payload: local.payload, gameType: local.gameType, matchId: item.handle.matchId, syncState: .pending
              ) != nil else {
            reportPersistenceError(CocoaError(.fileWriteUnknown))
            return false
        }
        if var machine = sessionMachine, machine.handle == item.handle {
            _ = machine.accept(handle: item.handle, authorityEpoch: envelope.authorityEpoch, revision: envelope.sessionRevision)
            _ = machine.markFinished(matchId: item.handle.matchId)
            machine.registerPendingAcknowledgement(item.messageId)
            sessionMachine = machine
            synchronizeSessionStateFromMachine()
            latestSnapshot = .init(
                sessionId: item.handle.sessionId, revision: envelope.sessionRevision,
                matchGeneration: item.handle.matchGeneration,
                snapshot: local.payload.snapshot, detailedActions: local.payload.detailedActions
            )
        }
        terminalOutbox.markLocalRecordSaved(messageId: item.messageId)
        persistContext()
        persistTerminalOutbox()
        return true
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
        rescheduleRetryIfNeeded()
    }

    func exitScoreboard(sessionId: UUID) {
        guard let handle = activeHandle, handle.sessionId == sessionId else { return }
        if publishedFinishedMatchIds.contains(handle.matchId) {
            leaveSession()
        } else {
            exitScoreboardToHome()
        }
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

    /// Discard the watch resume entry. Legacy links also transfer scoring to the phone.
    func discardResumableSession(reason: LinkResumeDiscardReason) {
        guard let sessionId = activeSessionId else { return }
        if controlRole == .shared {
            leaveSession()
            return
        }
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
        if let session = activeRecordSession, session.handle.sessionId != context.sessionId {
            retiredRecordSessions.retire(session)
        }
        _ = revisionGate.beginMatch(context.handle, initialRevision: context.revision)
        installStateMachine(from: context)
        synchronizeSessionStateFromMachine()
        activeGameType = context.setup.gameType
        activeSetup = context.setup
        activeSetup?.detailedActions = context.detailedActions
        peerSupportsCompressedFinish = context.peerSupportsCompressedFinish == true
        negotiatedPeerCapabilities = context.negotiatedPeerCapabilities ?? []
        actionHistory = context.actionHistory ?? LinkSnapshotHistory()
        phoneTookOver = context.controlRole == .watchFollower
        mergedDetailedActions = context.detailedActions
        if let snapshot = context.latestAuthoritativeSnapshot {
            latestSnapshot = .init(
                sessionId: context.sessionId,
                revision: context.revision,
                matchGeneration: context.handle.matchGeneration,
                snapshot: snapshot,
                detailedActions: context.detailedActions,
                removedActionIDs: actionHistory.removedActionIDs
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

    func endLocalSession() {
        if let session = activeRecordSession { retiredRecordSessions.retire(session) }
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
        peerSupportsCompressedFinish = false
        controlRole = nil
        acceptedSetup = nil
        pendingConfirmRequest = nil
        latestSnapshot = nil
        sharedEditTracker = LinkSharedEditTracker()
        simultaneousEditNotice = nil
        mergedDetailedActions = []
        phoneTookOver = false
        publishedFinishedMatchIds.removeAll()
        pendingReclaimAcceptance = nil
        pendingReclaimRequestMessageId = nil
        reclaimRequestTimeoutTask?.cancel()
        reclaimRequestTimeoutTask = nil
        actionHistory = LinkSnapshotHistory()
        deltaActionTracker.reset()
        negotiatedPeerCapabilities = []
        pendingAck.clear()
        rescheduleRetryIfNeeded()
        persistContext()
    }

    func installStateMachine(
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

    func synchronizeSessionStateFromMachine() {
        guard let machine = sessionMachine else { return }
        activeSessionId = machine.handle.sessionId
        activeHandle = machine.handle
        activeRevision = machine.revision
        authorityEpoch = machine.authorityEpoch
        controlRole = machine.role
        publishedFinishedMatchIds = machine.completedMatchIds
    }

    func mergeDetailedActions(_ incoming: [DetailedScoreAction]?) {
        mergedDetailedActions = actionHistory.merging(incoming ?? [], into: mergedDetailedActions)
    }

    @discardableResult
    func applyLocalHistory(_ actions: [DetailedScoreAction]?) -> Bool {
        guard let actions else { return false }
        let removedActions = actionHistory.noteLocalPublication(actions)
        if removedActions { deltaActionTracker.reset() }
        mergeDetailedActions(actions)
        return removedActions
    }

    func maxSets(for snapshot: LinkedScoreboardSnapshot) -> Int? {
        switch snapshot {
        case .rally(let state): return state.rules.maxSets
        case .tennis(let state): return state.rules.maxSets
        default: return nil
        }
    }

    static func isValidLinkedSetup(_ setup: LinkedScoreboardSetup) -> Bool {
        WatchSportRegistry.isValidLinkedSetup(setup)
    }
}
