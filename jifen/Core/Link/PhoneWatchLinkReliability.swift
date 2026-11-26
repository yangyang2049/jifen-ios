import Foundation
import LinkCore
import Observation
import RecordCore
import ScoreCore
import UIKit


extension PhoneWatchLinkService {
    func startInteractiveSession(
        gameType: ScoreCore.GameType,
        maxSets: Int? = nil,
        initialSnapshot: LinkedScoreboardSnapshot,
        participantNames: [String]? = nil
    ) async throws -> UUID {
        if setupContinuation != nil {
            trackSetupAnalyticsResult(.timeout)
        }
        setupAnalyticsGameType = GameType(scoreCoreGameType: gameType)?.analyticsIdentifier
            ?? String(describing: gameType).lowercased()
        didTrackSetupAnalyticsResult = false
        AppAnalytics.track(.watchLinkStart, parameters: [
            .gameType: .string(setupAnalyticsGameType ?? "unknown"),
            .entryPoint: .string(AnalyticsEntryPoint.watchLink.rawValue),
            .sourceSurface: .string(AnalyticsSourceSurface.phone.rawValue)
        ])
        guard Self.phoneInteractiveStartSupported(gameType) else {
            trackSetupAnalyticsResult(.notReachable)
            throw InteractiveStartError.watchUnavailable
        }
        do {
            try validateInteractiveWatchAvailability()
        } catch {
            trackSetupAnalyticsResult(.notReachable)
            throw error
        }
        if setupContinuation != nil {
            let continuation = setupContinuation
            setupContinuation = nil
            if let existing = activeSession?.sessionId {
                leaveSession(existing)
            } else {
                clearSession()
            }
            continuation?.resume(throwing: InteractiveStartError.setupTimedOut)
        }
        setupTimeoutTask?.cancel()

        let sessionId = UUID()
        let setup = LinkedScoreboardSetup(
            gameType: gameType,
            maxSets: maxSets,
            initialSnapshot: initialSnapshot,
            participantNames: participantNames ?? []
        )
        if let session = activeRecordSession { retiredRecordSessions.retire(session) }
        if let existing = activeSession?.sessionId {
            leaveSession(existing)
        }
        pendingTakeoverMessageId = nil
        pendingReclaimGrantMessageId = nil
        pendingReclaimRequest = nil
        pendingTakeoverApplication = nil
        forceTakeoverConfirmationSessionId = nil
        pendingStatusCorrelationId = nil
        statusTimeoutTask?.cancel()
        statusTimeoutTask = nil
        resumeStatusContinuations(throwing: CancellationError())
        reclaimTimeoutTask?.cancel()
        reclaimTimeoutTask = nil
        pendingAck.clear()
        peerSupportsCompressedFinish = false
        negotiatedPeerCapabilities = []
        actionHistory = LinkSnapshotHistory()
        deltaActionTracker.reset()
        mergedDetailedActions = []
        watchBackgrounded = false
        activeSession = ActiveSession(
            handle: LinkedMatchHandle(sessionId: sessionId),
            gameType: gameType,
            revision: 0,
            role: .phoneFollower,
            authorityEpoch: 0,
            setup: setup,
            completedMatchIds: []
        )
        if let session = activeSession {
            installStateMachine(from: session, lifecycle: .starting)
        }
        controlRole = .phoneFollower
        latestRemoteSnapshot = nil
        finishedRecordId = nil
        publishedFinishedMatchIds.removeAll()
        lastErrorMessage = nil
        if let handle = activeSession?.handle {
            _ = revisionGate.beginMatch(handle, initialRevision: 0)
        }
        persistContext()
        sequence += 1
        let envelope = LinkEnvelope(
            supportsCompressedFinish: true,
            supportsSharedEditing: true,
            sessionId: sessionId,
            matchId: activeSession?.handle.matchId,
            matchGeneration: activeSession?.handle.matchGeneration ?? 1,
            authorityEpoch: 0,
            kind: .setupRequest,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: 0,
            sentAtEpochMilliseconds: nowMs(),
            payload: setup
        )
        pendingSetupMessageId = envelope.messageId
        _ = sessionMachine?.beginSetup(correlationId: envelope.messageId)
        return try await withCheckedThrowingContinuation { continuation in
            setupContinuation = continuation
            setupTimeoutTask = Task { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(Self.setupTimeoutSeconds * 1_000_000_000))
                } catch {
                    return
                }
                await MainActor.run {
                    guard let self,
                          self.activeSession?.sessionId == sessionId,
                          let cont = self.setupContinuation else { return }
                    self.setupContinuation = nil
                    self.setupTimeoutTask = nil
                    self.trackSetupAnalyticsResult(.timeout)
                    self.leaveSession(sessionId)
                    cont.resume(throwing: InteractiveStartError.setupTimedOut)
                }
            }
            Task { [weak self] in
                guard let self else { return }
                do {
                    // setup 信封内嵌 LinkedScoreboardSetup（含 detailedActions），
                    // 接管场景下可能超限，统一走裁剪编码。
                    let data = LinkEnvelopeEncoding.encodedData(envelope)
                    try self.transport.sendInteractive(data)
                } catch {
                    guard self.activeSession?.sessionId == sessionId,
                          let cont = self.setupContinuation else { return }
                    self.setupContinuation = nil
                    self.setupTimeoutTask?.cancel()
                    self.setupTimeoutTask = nil
                    self.clearSession()
                    if error as? WatchConnectivityTransportError == .peerNotReachable {
                        self.trackSetupAnalyticsResult(.notReachable)
                        cont.resume(throwing: InteractiveStartError.watchAppNotForeground)
                    } else {
                        self.trackSetupAnalyticsResult(.failed)
                        cont.resume(throwing: error)
                    }
                }
            }
        }
    }


    func sendSnapshotIfController(
        sessionId: UUID,
        gameType: ScoreCore.GameType,
        snapshot: LinkedScoreboardSnapshot,
        detailedActions: [DetailedScoreAction]? = nil,
        participantNames: [String]? = nil
    ) {
        guard let currentSession = activeSession,
              currentSession.sessionId == sessionId,
              currentSession.gameType == gameType,
              canEditLinkedMatch,
              !peerFinishedSharedMatch,
              !currentSession.completedMatchIds.contains(currentSession.handle.matchId),
              var machine = sessionMachine else { return }
        let shared = machine.role == .shared
        let baseRevision = machine.revision
        let priorActions = mergedDetailedActions
        let removedActions = applyLocalHistory(detailedActions)
        if shared, !removedActions, priorActions == mergedDetailedActions,
           baseRevision != 0 || currentSession.handle.matchGeneration == 1,
           snapshot == (latestRemoteSnapshot?.snapshot ?? currentSession.setup.initialSnapshot),
           participantNames == nil || participantNames == currentSession.setup.participantNames {
            return
        }
        _ = machine.advanceRevision(sender: .phone)
        sessionMachine = machine
        synchronizeActiveSessionFromStateMachine()
        guard var session = activeSession else { return }
        session.setup = LinkedScoreboardSetup(
            gameType: gameType,
            maxSets: maxSets(for: snapshot),
            initialSnapshot: snapshot,
            detailedActions: mergedDetailedActions,
            participantNames: participantNames ?? session.setup.participantNames
        )
        activeSession = session
        latestRemoteSnapshot = .init(
            sessionId: sessionId,
            revision: session.revision,
            matchGeneration: session.handle.matchGeneration,
            snapshot: snapshot,
            detailedActions: mergedDetailedActions
        )
        persistContext()
        sequence += 1
        let messageId = UUID()
        let envelope = LinkEnvelope(
            baseSnapshotRevision: shared ? baseRevision : nil,
            messageId: messageId,
            sessionId: sessionId,
            matchId: session.handle.matchId,
            matchGeneration: session.handle.matchGeneration,
            authorityEpoch: session.authorityEpoch,
            kind: .stateSnapshot,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: session.revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: deltaSnapshotSetup(
                snapshot: snapshot,
                gameType: gameType,
                maxSets: maxSets(for: snapshot),
                participantNames: session.setup.participantNames,
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
            guard let current = activeSession, current.handle == envelope.handle,
                  canEditLinkedMatch else { return }
            let isLatest = current.revision == envelope.sessionRevision
            let supersededByWatch = shared && LinkSharedRevision.writer(of: current.revision) == .watch
            guard isLatest || supersededByWatch else { return }
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
                if transport.isReachable {
                    try await transport.sendRealtime(frame.data)
                }
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    func sendAck(
        sessionId: UUID,
        messageId: UUID,
        revision: UInt64,
        handle: LinkedMatchHandle? = nil,
        authorityEpoch: UInt64? = nil,
        recordAck: Bool = false
    ) {
        let resolvedHandle = handle
            ?? activeSession?.handle
            ?? LinkedMatchHandle(sessionId: sessionId, matchId: sessionId)
        sequence += 1
        let envelope = LinkEnvelope(
            correlationId: messageId,
            sessionId: sessionId,
            matchId: resolvedHandle.matchId,
            matchGeneration: resolvedHandle.matchGeneration,
            authorityEpoch: authorityEpoch
                ?? activeSession?.authorityEpoch
                ?? 0,
            kind: recordAck ? .recordAcknowledgement : .acknowledgement,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkAcknowledgementPayload(
                acknowledgedMessageId: messageId,
                acknowledgedRevision: revision
            )
        )
        sendReportingError(envelope)
    }

    func sendReportingError<Payload: Codable & Sendable>(
        _ envelope: LinkEnvelope<Payload>
    ) {
        Task {
            do {
                try await sendEnvelope(envelope)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    func sendEnvelope<Payload: Codable & Sendable>(_ envelope: LinkEnvelope<Payload>) async throws {
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
                lastErrorMessage = error.localizedDescription
            }
        case .file:
            do {
                try transport.transferFileData(data, metadata: [
                    WatchConnectivityTransport.transferFileKindKey: WatchTransferFileKind.matchFinished.rawValue
                ])
            } catch {
                lastErrorMessage = error.localizedDescription
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
              machine.handle == frame.handle, machine.authorityEpoch == frame.authorityEpoch,
              machine.role == .shared || machine.revision == frame.sessionRevision,
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
            // Session-end delivery has no acknowledgement queue of its own. Keep
            // a one-second backoff only while an end request is actually pending.
            deadlines.append(now + 1_000)
        }
        guard let deadline = deadlines.min() else { return nil }
        let delayMilliseconds = max(0, deadline - now)
        return UInt64(delayMilliseconds) * 1_000_000
    }

    func performRetryWork(retryActionSnapshotImmediately: Bool = false) {
        let pendingMessageId = pendingAck.pending?.messageId
        let tracksHistory = peerSupportsDeltaActions
            && (pendingMessageId.map { deltaActionTracker.carriesHistory(messageId: $0) } ?? false)
        let authorityTransferPending = pendingMessageId == pendingTakeoverMessageId
            || pendingMessageId == pendingReclaimGrantMessageId
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
                    // 后台自动重发失败（如手表暂不可达）属于非致命事件，
                    // 重试循环会继续投递，不应弹出“联动失败”对话框。
                    #if DEBUG
                    print("[PhoneLink] pending ack retry send failed: \(error.localizedDescription)")
                    #endif
                }
            }
        } else if let pendingMessageId,
                  pendingAck.pending == nil {
            if var machine = sessionMachine {
                _ = machine.acknowledge(messageId: pendingMessageId)
                if authorityTransferPending {
                    _ = machine.rejectAuthorityTransfer(
                        correlationId: pendingMessageId
                    )
                }
                sessionMachine = machine
                synchronizeActiveSessionFromStateMachine()
            }
            if pendingTakeoverMessageId == pendingMessageId {
                pendingTakeoverMessageId = nil
            }
            if pendingReclaimGrantMessageId == pendingMessageId {
                pendingReclaimGrantMessageId = nil
            }
            lastErrorMessage = authorityTransferPending
                ? InteractiveStartError.authorityTransferTimedOut.localizedDescription
                : NSLocalizedString(
                    "linked_score_sync_timeout",
                    value: "比分同步超时，将在重新连接后继续同步。",
                    comment: ""
                )
            persistContext()
        }
        let dueTerminalItems = terminalOutbox.retryDueItems(
            nowEpochMilliseconds: nowMs()
        )
        if !dueTerminalItems.isEmpty {
            persistTerminalOutbox()
            for item in dueTerminalItems {
                let frame = item.data
                let override = item.peerSupportsFileTransfer
                Task {
                    await deliverTerminalFrame(frame, peerSupportsFileTransferOverride: override)
                }
            }
        }
        flushPendingSessionEnds()
    }

    func nowMs() -> Int64 {
        clock.nowEpochMilliseconds()
    }

    /// Returns true only when the outbox is confirmed on disk. Delivery,
    /// finish marking and ACK clearing gate on this.
    @discardableResult
    func persistTerminalOutbox() -> Bool {
        guard !terminalOutbox.isEmpty else {
            outboxStore.removeObject(forKey: terminalOutboxKey)
            return true
        }
        do {
            let data = try JSONEncoder().encode(terminalOutbox)
            try outboxStore.setOrThrow(data, forKey: terminalOutboxKey)
            return true
        } catch {
            reportPersistenceError(error)
            return false
        }
    }

    func persistPendingSessionEnds() {
        guard !pendingSessionEnds.isEmpty else {
            outboxStore.removeObject(forKey: pendingSessionEndsKey)
            return
        }
        do {
            let data = try JSONEncoder().encode(pendingSessionEnds)
            outboxStore.set(data, forKey: pendingSessionEndsKey)
        } catch {
            reportPersistenceError(error)
        }
    }

    func flushPendingSessionEnds() {
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
                authorityEpoch: request.authorityEpoch,
                kind: .sessionLeft,
                sender: .phone,
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
                    try await sendEnvelope(envelope)
                    pendingSessionEnds.removeAll { $0 == request }
                    persistPendingSessionEnds()
                    if activeSession?.handle == request.handle {
                        clearSession()
                    }
                } catch {
                    // 会话结束消息的后台重发失败（如手表暂不可达）不弹窗，
                    // 重试循环与连接恢复时的 flush 会继续投递。
                    #if DEBUG
                    print("[PhoneLink] flushPendingSessionEnds failed: \(error.localizedDescription)")
                    #endif
                }
            }
        }
    }

    func persistContext() {
        guard let session = activeSession else {
            contextStore.removeObject(forKey: contextKey)
            return
        }
        var storedSetup = session.setup
        storedSetup.detailedActions = []
        storedSetup.removedActionIDs = nil
        let context = PhoneLinkResumeContext(
            handle: session.handle,
            setup: storedSetup,
            role: session.role,
            authorityEpoch: session.authorityEpoch,
            revision: session.revision,
            latestAuthoritativeSnapshot: latestRemoteSnapshot?.snapshot
                ?? session.setup.initialSnapshot,
            detailedActions: mergedDetailedActions,
            completedMatchIds: session.completedMatchIds,
            pendingTerminalMessageIds: Set(terminalOutbox.items.map(\.messageId)),
            finishedRecordId: finishedRecordId,
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

    private func reportPersistenceError(_ error: Error) {
        lastErrorMessage = String(
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
                PhoneLinkResumeContext.self,
                from: data
              ) else {
            contextStore.removeObject(forKey: contextKey)
            return
        }
        var restoredSetup = context.setup
        restoredSetup.detailedActions = context.detailedActions
        activeSession = ActiveSession(
            handle: context.handle,
            gameType: context.setup.gameType,
            revision: context.revision,
            role: context.role,
            authorityEpoch: context.authorityEpoch,
            setup: restoredSetup,
            completedMatchIds: context.completedMatchIds
        )
        if let session = activeSession {
            installStateMachine(
                from: session,
                lifecycle: context.completedMatchIds.contains(context.handle.matchId) ? .matchFinished : .active
            )
            synchronizeActiveSessionFromStateMachine()
        }
        finishedRecordId = context.finishedRecordId
        peerSupportsCompressedFinish = context.peerSupportsCompressedFinish == true
        negotiatedPeerCapabilities = context.negotiatedPeerCapabilities ?? []
        actionHistory = context.actionHistory ?? LinkSnapshotHistory()
        mergedDetailedActions = context.detailedActions
        publishedFinishedMatchIds = context.completedMatchIds
        if let snapshot = context.latestAuthoritativeSnapshot {
            latestRemoteSnapshot = LinkedSnapshotUpdate(
                sessionId: context.handle.sessionId,
                revision: context.revision,
                matchGeneration: context.handle.matchGeneration,
                snapshot: snapshot,
                detailedActions: context.detailedActions
            )
        }
        _ = revisionGate.beginMatch(
            context.handle,
            initialRevision: context.revision
        )
    }
}
