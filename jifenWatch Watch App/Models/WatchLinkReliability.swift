import Foundation
import LinkCore
import Observation
import RecordCore
import ScoreCore

extension WatchLinkService {
    func sendAck(
        sessionId: UUID,
        messageId: UUID,
        revision: UInt64,
        handle: LinkedMatchHandle? = nil,
        recordAck: Bool = false,
        authoritativeSnapshot: LinkedScoreboardSnapshot? = nil,
        detailedActions: [DetailedScoreAction]? = nil
    ) {
        sequence += 1
        let resolvedHandle = handle
            ?? activeHandle
            ?? LinkedMatchHandle(sessionId: sessionId, matchId: sessionId)
        let envelope = LinkEnvelope(
            correlationId: messageId,
            sessionId: sessionId,
            matchId: resolvedHandle.matchId,
            matchGeneration: resolvedHandle.matchGeneration,
            kind: recordAck ? .recordAcknowledgement : .acknowledgement,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkAcknowledgementPayload(
                acknowledgedMessageId: messageId,
                acknowledgedRevision: revision,
                authoritativeSnapshot: authoritativeSnapshot,
                detailedActions: detailedActions ?? []
            )
        )
        sendReportingError(envelope)
    }

    func sendReportingError<Payload: Codable & Sendable>(
        _ envelope: LinkEnvelope<Payload>
    ) {
        Task {
            do {
                try await send(envelope)
            } catch {
                lastLinkErrorMessage = error.localizedDescription
            }
        }
    }

    func send<Payload: Codable & Sendable>(_ envelope: LinkEnvelope<Payload>) async throws {
        // 统一经类型分派裁剪：ACK/接管等信封若未来携带长动作历史也不会超限。
        let data = LinkEnvelopeEncoding.encodedData(envelope)
        switch envelope.kind {
        case .stateSnapshot:
            try transport.publishLatestSnapshot(
                LinkEnvelopeEncoding.applicationContextData(envelope)
            )
            if transport.isReachable {
                try await transport.sendRealtime(data)
            }
        case .matchFinished:
            // Terminal frames route through the durable-channel helper; the
            // outbox already persisted the full payload before this call.
            await deliverTerminalFrame(data)
        default:
            try await transport.sendRealtime(data)
        }
    }

    /// Durable-channel selection for terminal frames (≤32KB → transferUserInfo,
    /// larger → transferFile when negotiated, else hold in the outbox).
    /// Durable-channel selection for terminal frames. The override comes from
    /// the outbox item's negotiated snapshot so retries after a next-match or
    /// restart use the frame's own session context.
    func deliverTerminalFrame(_ data: Data, peerSupportsFileTransferOverride: Bool? = nil) async {
        switch LinkFinishedRouting.chooseDurableChannel(
            frameByteCount: data.count,
            peerSupportsFileTransfer: peerSupportsFileTransferOverride ?? peerSupportsFileTransfer
        ) {
        case .userInfo:
            do {
                try transport.enqueueDurable(data)
            } catch {
                lastLinkErrorMessage = error.localizedDescription
            }
        case .file:
            do {
                try transport.transferFileData(data, metadata: [
                    WatchConnectivityTransport.transferFileKindKey: WatchTransferFileKind.matchFinished.rawValue
                ])
            } catch {
                lastLinkErrorMessage = error.localizedDescription
            }
        case .hold:
            break // outbox keeps the full payload; retries revisit the channel
        }
        if data.count <= LinkFinishedRouting.realtimeBudgetBytes, transport.isReachable {
            try? await transport.sendRealtime(data)
        }
    }

    func deltaSnapshotSetup(
        snapshot: LinkedScoreboardSnapshot,
        gameType: ScoreCore.GameType,
        maxSets: Int?,
        participantNames: [String],
        fullActions: [DetailedScoreAction]
    ) -> LinkedScoreboardSetup {
        var setup = deltaActionTracker.snapshotSetup(
            snapshot: snapshot, gameType: gameType, maxSets: maxSets,
            participantNames: participantNames, fullActions: fullActions,
            deltaEnabled: peerSupportsDeltaActions
        ).setup
        let removals = deltaActionTracker.pendingRemovalIDs(actionHistory.removedActionIDs)
        if !removals.isEmpty {
            setup.isDeltaActions = false
            setup.removedActionIDs = removals
        }
        return setup
    }

    func enqueueLiveSnapshot(
        _ envelope: LinkEnvelope<LinkedScoreboardSetup>,
        frame: LinkEnvelopeEncoding.SnapshotFrame
    ) {
        if let prior = pendingAck.pending, deltaActionTracker.carriesHistory(messageId: prior.messageId) {
            sessionMachine?.acknowledge(messageId: prior.messageId)
        }
        deltaActionTracker.noteLatestSnapshot(messageId: envelope.messageId, frame: frame)
        sessionMachine?.registerPendingAcknowledgement(envelope.messageId)
        pendingAck.enqueue(.init(
            messageId: envelope.messageId, sessionId: envelope.sessionId,
            revision: envelope.sessionRevision, data: frame.data,
            lastSentAtEpochMilliseconds: nowMs()
        ))
        rescheduleRetryIfNeeded()
    }

    func sendRemainingActions(after frame: LinkEnvelope<LinkedScoreboardSetup>) {
        guard pendingAck.pending == nil, peerSupportsDeltaActions, canEditLinkedMatch,
              let machine = sessionMachine, machine.lifecycle == .active,
              machine.handle == frame.handle,
              let next = deltaActionTracker.continuation(
                of: frame, actions: mergedDetailedActions, removedActionIDs: actionHistory.removedActionIDs,
                sequence: sequence + 1, now: nowMs()
              ) else { return }
        let wire = LinkEnvelopeEncoding.snapshotFrame(next)
        guard wire.carriesHistory else { return }
        sequence += 1
        enqueueLiveSnapshot(next, frame: wire)
        if transport.isReachable {
            Task {
                guard pendingAck.pending?.messageId == next.messageId, transport.isReachable else { return }
                try? await transport.sendRealtime(wire.data)
            }
        }
    }

    /// 恢复上下文后没有内存 pendingAck：用同一 handle 的已持久化动作/删除
    /// 重建一帧待发增量（仅历史，不改比分）。
    func sendRestoredDeltaIfNeeded() {
        guard let sessionId = activeSessionId, let gameType = activeGameType,
              let handle = activeHandle, sessionMachine?.lifecycle == .active,
              let snapshot = activeSetup?.initialSnapshot,
              !mergedDetailedActions.isEmpty || !actionHistory.removedActionIDs.isEmpty else { return }
        let removals = deltaActionTracker.pendingRemovalIDs(actionHistory.removedActionIDs)
        sequence += 1
        let payload = LinkedScoreboardSetup(
            gameType: gameType,
            maxSets: maxSets(for: snapshot),
            initialSnapshot: snapshot,
            detailedActions: mergedDetailedActions,
            participantNames: activeSetup?.participantNames ?? [],
            isDeltaActions: removals.isEmpty,
            removedActionIDs: removals.isEmpty ? nil : removals
        )
        let envelope = LinkEnvelope(
            messageId: UUID(),
            sessionId: sessionId,
            matchId: handle.matchId,
            matchGeneration: handle.matchGeneration,
            kind: .stateSnapshot,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: activeRevision,
            sentAtEpochMilliseconds: nowMs(),
            payload: payload
        )
        let wire = LinkEnvelopeEncoding.snapshotFrame(envelope)
        guard wire.carriesHistory else { return }
        enqueueLiveSnapshot(envelope, frame: wire)
        guard transport.isReachable else { return }
        Task {
            guard pendingAck.pending?.messageId == envelope.messageId else { return }
            try? await transport.sendRealtime(wire.data)
        }
    }

    func retryLiveSnapshotOnReconnect() {
        guard let pending = pendingAck.pending, peerSupportsDeltaActions,
              deltaActionTracker.carriesHistory(messageId: pending.messageId) else { return }
        performRetryWork(retryActionSnapshotImmediately: true)
        rescheduleRetryIfNeeded()
    }

    func scheduleRetryIfNeeded() {
        guard ackRetryTask == nil,
              let delayNanoseconds = nextRetryDelayNanoseconds() else { return }
        ackRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.ackRetryTask = nil
            self.performRetryWork()
            self.scheduleRetryIfNeeded()
        }
    }

    func rescheduleRetryIfNeeded() {
        ackRetryTask?.cancel()
        ackRetryTask = nil
        scheduleRetryIfNeeded()
    }

    private func nextRetryDelayNanoseconds() -> UInt64? {
        let now = nowMs()
        var deadlines: [Int64] = []
        if let pending = pendingAck.pending,
           transport.isReachable || !peerSupportsDeltaActions || !deltaActionTracker.carriesHistory(messageId: pending.messageId) {
            deadlines.append(
                pending.lastSentAtEpochMilliseconds
                    + LinkControlRetryQueue.retryIntervalMilliseconds
            )
        }
        deadlines.append(contentsOf: terminalOutbox.items.map {
            $0.lastSentAtEpochMilliseconds
                + LinkDurableOutbox.retryIntervalMilliseconds
        })
        if pendingSessionEnds.contains(where: {
            !pendingSessionEndInFlight.contains($0.handle.sessionId)
        }) {
            deadlines.append(now + 1_000)
        }
        guard let deadline = deadlines.min() else { return nil }
        return UInt64(max(0, deadline - now)) * 1_000_000
    }

    func performRetryWork(retryActionSnapshotImmediately: Bool = false) {
        let pendingMessageId = pendingAck.pending?.messageId
        let tracksHistory = peerSupportsDeltaActions
            && (pendingMessageId.map { deltaActionTracker.carriesHistory(messageId: $0) } ?? false)
        if !tracksHistory || transport.isReachable,
           let data = pendingAck.retryIfDue(
               nowEpochMilliseconds: nowMs(),
               retainAfterExhaustion: tracksHistory,
               sendImmediately: tracksHistory && retryActionSnapshotImmediately
           ) {
            Task {
                do {
                    try await transport.sendRealtime(data)
                } catch {
                    lastLinkErrorMessage = error.localizedDescription
                }
            }
        } else if let pendingMessageId,
                  pendingAck.pending == nil {
            if var machine = sessionMachine {
                _ = machine.acknowledge(messageId: pendingMessageId)
                sessionMachine = machine
            }
            lastLinkErrorMessage = NSLocalizedString(
                "linked_score_sync_timeout",
                value: "比分同步超时，将在重新连接后继续同步。",
                comment: ""
            )
        }
        let dueTerminalItems = terminalOutbox.retryDueItems(
            nowEpochMilliseconds: nowMs()
        )
        if !dueTerminalItems.isEmpty {
            // 先确认 outbox 已落盘再投影/发送；落盘失败保留待发，下一轮重试。
            guard persistTerminalOutbox() else {
                rescheduleRetryIfNeeded()
                return
            }
            for item in dueTerminalItems {
                if item.pendingLocalRecord != nil, !prepareLocalFinishedRecord(item) { continue }
                let frame = item.data
                let override = item.peerSupportsFileTransfer
                Task {
                    await deliverTerminalFrame(frame, peerSupportsFileTransferOverride: override)
                }
            }
        }
        flushPendingSessionEnds()
    }

    /// Returns true only when the outbox is confirmed on disk. Delivery,
    /// finish marking and ACK clearing gate on this.
    @discardableResult
    func persistTerminalOutbox() -> Bool {
        do {
            if terminalOutbox.isEmpty {
                try outboxStore.removeOrThrow(forKey: terminalOutboxKey)
            } else {
                let data = try JSONEncoder().encode(terminalOutbox)
                try outboxStore.setOrThrow(data, forKey: terminalOutboxKey)
            }
            return true
        } catch {
            reportPersistenceError(error)
            return false
        }
    }

    @discardableResult
    func persistPendingSessionEnds() -> Bool {
        do {
            if pendingSessionEnds.isEmpty {
                try outboxStore.removeOrThrow(forKey: pendingSessionEndsKey)
            } else {
                let data = try JSONEncoder().encode(pendingSessionEnds)
                try outboxStore.setOrThrow(data, forKey: pendingSessionEndsKey)
            }
            return true
        } catch {
            reportPersistenceError(error)
            return false
        }
    }

    func flushPendingSessionEnds() {
        guard !pendingSessionEnds.isEmpty, persistPendingSessionEnds() else { return }
        for request in pendingSessionEnds {
            let sessionId = request.handle.sessionId
            guard !pendingSessionEndInFlight.contains(sessionId),
                  !terminalOutbox.items.contains(where: {
                      $0.handle.sessionId == sessionId
                  }) else {
                continue
            }
            pendingSessionEndInFlight.insert(sessionId)
            sequence += 1
            let envelope = LinkEnvelope(
                sessionId: sessionId,
                matchId: request.handle.matchId,
                matchGeneration: request.handle.matchGeneration,
                kind: .sessionLeft,
                sender: .watch,
                senderSequence: sequence,
                sessionRevision: request.revision,
                sentAtEpochMilliseconds: nowMs(),
                payload: EmptyLinkPayload()
            )
            Task {
                defer {
                    pendingSessionEndInFlight.remove(sessionId)
                    rescheduleRetryIfNeeded()
                }
                do {
                    try await send(envelope)
                    if activeHandle == request.handle {
                        // Retire the durable resume pointer before dropping the queued end.
                        try contextStore.removeOrThrow(forKey: contextKey)
                        endLocalSession()
                    }
                    let previousRequests = pendingSessionEnds
                    pendingSessionEnds.removeAll { $0 == request }
                    if !persistPendingSessionEnds() {
                        pendingSessionEnds = previousRequests
                    }
                } catch {
                    lastLinkErrorMessage = error.localizedDescription
                }
            }
        }
    }

    func nowMs() -> Int64 {
        clock.nowEpochMilliseconds()
    }


    /// `link/` 下已持久化的权威联动上下文（只读）。续玩草稿只能与它匹配，
    /// 不能凭草稿重建或覆盖服务状态；上下文缺失、损坏或不匹配即返回 nil。
    var storedLinkContext: WatchLinkResumeContext? {
        guard let data = contextStore.data(forKey: contextKey),
              let context = try? JSONDecoder().decode(WatchLinkResumeContext.self, from: data),
              let snapshot = context.latestAuthoritativeSnapshot,
              snapshot.matches(gameType: context.setup.gameType) else { return nil }
        return context
    }

    func persistContext() {
        guard let handle = activeHandle, let setup = activeSetup else {
            contextStore.removeObject(forKey: contextKey)
            return
        }
        var storedSetup = setup
        storedSetup.detailedActions = []
        storedSetup.removedActionIDs = nil
        let context = WatchLinkResumeContext(
            handle: handle,
            setup: storedSetup,
            revision: activeRevision,
            latestAuthoritativeSnapshot: latestSnapshot?.snapshot
                ?? setup.initialSnapshot,
            detailedActions: mergedDetailedActions,
            completedMatchIds: publishedFinishedMatchIds,
            pendingTerminalMessageIds: Set(terminalOutbox.items.map(\.messageId)),
            peerSupportsCompressedFinish: peerSupportsCompressedFinish,
            negotiatedPeerCapabilities: negotiatedPeerCapabilities.isEmpty ? nil : negotiatedPeerCapabilities,
            actionHistory: actionHistory
        )
        do {
            let data = try JSONEncoder().encode(context)
            contextStore.set(data, forKey: contextKey)
        } catch {
            reportPersistenceError(error)
        }
    }

    func reportPersistenceError(_ error: Error) {
        lastLinkErrorMessage = String(
            format: NSLocalizedString(
                "linked_score_persistence_failed",
                value: "无法保存联动恢复数据：%@",
                comment: ""
            ),
            error.localizedDescription
        )
    }

    func restoreContext() {
        guard let data = contextStore.data(forKey: contextKey),
              let context = try? JSONDecoder().decode(
                WatchLinkResumeContext.self,
                from: data
              ) else {
            contextStore.removeObject(forKey: contextKey)
            return
        }
        guard !pendingSessionEnds.contains(where: { $0.handle == context.handle }) else {
            contextStore.removeObject(forKey: contextKey)
            return
        }
        installStateMachine(from: context)
        synchronizeSessionStateFromMachine()
        activeGameType = context.setup.gameType
        activeSetup = context.setup
        peerSupportsCompressedFinish = context.peerSupportsCompressedFinish == true
        negotiatedPeerCapabilities = context.negotiatedPeerCapabilities ?? []
        actionHistory = context.actionHistory ?? LinkSnapshotHistory()
        mergedDetailedActions = context.detailedActions
        activeSetup?.detailedActions = mergedDetailedActions
        if let snapshot = context.latestAuthoritativeSnapshot {
            latestSnapshot = LinkedSnapshotUpdate(
                sessionId: context.handle.sessionId,
                revision: context.revision,
                matchGeneration: context.handle.matchGeneration,
                snapshot: snapshot,
                detailedActions: context.detailedActions,
                removedActionIDs: actionHistory.removedActionIDs
            )
        }
        _ = revisionGate.beginMatch(
            context.handle,
            initialRevision: context.revision
        )
    }
}
