import Foundation
import LinkCore
import Observation
import RecordCore
import ScoreCore
import UIKit


extension PhoneWatchLinkService {
    /// Ask the authoritative Watch controller to resend its latest full state.
    /// This is user initiated and deliberately does not change control roles.
    @discardableResult
    func requestScoreResync() -> Bool {
        guard let session = activeSession,
              LinkManualResyncPolicy.phoneCanRequest(role: session.role) else {
            return false
        }
        sequence += 1
        deltaActionTracker.reset()
        let envelope = LinkEnvelope(
            messageId: UUID(),
            correlationId: nil,
            sessionId: session.sessionId,
            matchId: session.handle.matchId,
            matchGeneration: session.handle.matchGeneration,
            authorityEpoch: session.authorityEpoch,
            kind: .resyncRequest,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: session.revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: EmptyLinkPayload()
        )
        Task {
            do {
                try await sendEnvelope(envelope)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
        return true
    }

    func startInteractiveOnWatch(
        gameType: ScoreCore.GameType,
        state: RallyMatchState,
        participantNames: [String]? = nil
    ) async throws -> UUID {
        try await startInteractiveSession(
            gameType: gameType,
            maxSets: state.rules.maxSets,
            initialSnapshot: .rally(state),
            participantNames: participantNames
        )
    }

    func startInteractiveOnWatch(
        gameType: ScoreCore.GameType,
        state: TennisMatchState,
        participantNames: [String]? = nil
    ) async throws -> UUID {
        try await startInteractiveSession(
            gameType: gameType,
            maxSets: state.rules.maxSets,
            initialSnapshot: .tennis(state),
            participantNames: participantNames
        )
    }

    func startInteractiveOnWatch(
        snapshot: LinkedScoreboardSnapshot,
        gameType: ScoreCore.GameType,
        participantNames: [String]? = nil
    ) async throws -> UUID {
        try await startInteractiveSession(
            gameType: gameType,
            maxSets: maxSets(for: snapshot),
            initialSnapshot: snapshot,
            participantNames: participantNames
        )
    }

    func syncWatch(sessionId: UUID, gameType: ScoreCore.GameType, state: RallyMatchState, detailedActions: [DetailedScoreAction]? = nil) {
        sendSnapshotIfController(sessionId: sessionId, gameType: gameType, snapshot: .rally(state), detailedActions: detailedActions)
    }

    func syncWatch(sessionId: UUID, gameType: ScoreCore.GameType, state: TennisMatchState, detailedActions: [DetailedScoreAction]? = nil) {
        sendSnapshotIfController(sessionId: sessionId, gameType: gameType, snapshot: .tennis(state), detailedActions: detailedActions)
    }

    func syncWatch(
        sessionId: UUID,
        gameType: ScoreCore.GameType,
        snapshot: LinkedScoreboardSnapshot,
        detailedActions: [DetailedScoreAction]? = nil,
        participantNames: [String]? = nil
    ) {
        sendSnapshotIfController(
            sessionId: sessionId,
            gameType: gameType,
            snapshot: snapshot,
            detailedActions: detailedActions,
            participantNames: participantNames
        )
    }

    /// Reuses the current link for a distinct match while
    /// clearing match-scoped terminal and action state from the previous one.
    func prepareControllerForNewMatch(
        sessionId: UUID,
        gameType: ScoreCore.GameType,
        snapshot: LinkedScoreboardSnapshot,
        participantNames: [String]? = nil
    ) {
        guard let currentSession = activeSession,
              currentSession.sessionId == sessionId,
              currentSession.gameType == gameType,
              canEditLinkedMatch,
              var machine = sessionMachine else { return }
        let nextHandle = machine.beginNextMatch()
        pendingAck.clear()
        actionHistory = LinkSnapshotHistory()
        deltaActionTracker.reset()
        pendingSessionEnds.removeAll { $0.handle.sessionId == sessionId }
        persistPendingSessionEnds()
        sessionMachine = machine
        synchronizeActiveSessionFromStateMachine()
        guard activeSession != nil else { return }
        finishedRecordId = nil
        latestRemoteSnapshot = nil
        mergedDetailedActions.removeAll()
        _ = revisionGate.beginMatch(nextHandle, initialRevision: 0)
        persistContext()
        sendSnapshotIfController(
            sessionId: sessionId,
            gameType: gameType,
            snapshot: snapshot,
            detailedActions: [],
            participantNames: participantNames
        )
    }

    func takeover(sessionId: UUID) async throws {
        guard let session = activeSession,
              session.sessionId == sessionId,
              session.role == .phoneFollower,
              connectivityStatus.canStartInteractiveSession else {
            throw InteractiveStartError.watchUnavailable
        }
        sequence += 1
        let messageId = UUID()
        let update = latestRemoteSnapshot
        let envelope = LinkEnvelope(
            messageId: messageId,
            correlationId: messageId,
            sessionId: sessionId,
            matchId: session.handle.matchId,
            matchGeneration: session.handle.matchGeneration,
            authorityEpoch: session.authorityEpoch,
            kind: .takeoverByPhone,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: session.revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkAuthorityTransferPayload(
                snapshot: update?.sessionId == sessionId ? update?.snapshot : nil,
                detailedActions: update?.sessionId == sessionId ? update?.detailedActions ?? [] : [],
                baseRevision: session.revision
            )
        )
        let data = LinkEnvelopeEncoding.data(
            envelope,
            actionsKeyPath: \LinkAuthorityTransferPayload.detailedActions
        )
        pendingTakeoverMessageId = messageId
        if var machine = sessionMachine {
            guard machine.beginAuthorityTransfer(
                correlationId: messageId,
                targetRole: .phoneController,
                kind: .phoneTakeover
            ) else { throw InteractiveStartError.notFollower }
            machine.registerPendingAcknowledgement(messageId)
            sessionMachine = machine
        }
        pendingAck.enqueue(.init(
            messageId: messageId,
            sessionId: sessionId,
            revision: session.revision,
            data: data,
            lastSentAtEpochMilliseconds: nowMs()
        ))
        rescheduleRetryIfNeeded()
        do {
            try await transport.sendRealtime(data)
        } catch {
            _ = pendingAck.acknowledge(messageId: messageId)
            rescheduleRetryIfNeeded()
            pendingTakeoverMessageId = nil
            if var machine = sessionMachine {
                _ = machine.acknowledge(messageId: messageId)
                _ = machine.rejectAuthorityTransfer(correlationId: messageId)
                sessionMachine = machine
            }
            throw error
        }
    }

    /// Emergency authority transfer. A correlated status query gets a full
    /// three-second opportunity to complete first. If the peer cannot answer,
    /// takeover is allowed only from the last snapshot the Watch previously
    /// confirmed or published.
    func forceTakeover(sessionId: UUID) async throws {
        guard activeSession?.sessionId == sessionId,
              activeSession?.role == .phoneFollower else {
            throw InteractiveStartError.notFollower
        }

        _ = try? await queryStatus(timeoutSeconds: 3)

        guard let currentSession = activeSession,
              currentSession.sessionId == sessionId,
              currentSession.role == .phoneFollower,
              var machine = sessionMachine else {
            throw InteractiveStartError.notFollower
        }
        guard let snapshot = latestRemoteSnapshot?.sessionId == sessionId
                ? latestRemoteSnapshot?.snapshot
                : currentSession.setup.initialSnapshot else {
            throw InteractiveStartError.noConfirmedSnapshot
        }

        _ = machine.forceAuthority(to: .phoneController)
        _ = machine.advanceRevision()
        sessionMachine = machine
        synchronizeActiveSessionFromStateMachine()
        guard var session = activeSession else {
            throw InteractiveStartError.notFollower
        }
        session.setup = LinkedScoreboardSetup(
            gameType: session.gameType,
            maxSets: maxSets(for: snapshot),
            initialSnapshot: snapshot,
            detailedActions: mergedDetailedActions,
            participantNames: session.setup.participantNames
        )
        activeSession = session
        controlRole = .phoneController
        watchBackgrounded = false
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
            payload: session.setup
        )
        let data = LinkEnvelopeEncoding.data(
            envelope,
            actionsKeyPath: \LinkedScoreboardSetup.detailedActions
        )
        sessionMachine?.registerPendingAcknowledgement(messageId)
        pendingAck.enqueue(.init(
            messageId: messageId,
            sessionId: sessionId,
            revision: session.revision,
            data: data,
            lastSentAtEpochMilliseconds: nowMs()
        ))
        rescheduleRetryIfNeeded()
        try transport.publishLatestSnapshot(
            LinkEnvelopeEncoding.applicationContextData(envelope)
        )
        if transport.isReachable {
            try await transport.sendRealtime(data)
        }
    }

    @discardableResult
    func queryStatus(timeoutSeconds: TimeInterval) async throws -> LinkStatusPayload {
        guard let session = activeSession else {
            throw InteractiveStartError.notFollower
        }
        if pendingStatusCorrelationId != nil {
            return try await withCheckedThrowingContinuation { continuation in
                statusContinuations.append(continuation)
            }
        }
        statusTimeoutTask?.cancel()

        sequence += 1
        let envelope = LinkEnvelope(
            messageId: UUID(),
            sessionId: session.sessionId,
            matchId: session.handle.matchId,
            matchGeneration: session.handle.matchGeneration,
            authorityEpoch: session.authorityEpoch,
            kind: .statusQuery,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: session.revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: EmptyLinkPayload()
        )
        pendingStatusCorrelationId = envelope.messageId

        return try await withCheckedThrowingContinuation { continuation in
            statusContinuations.append(continuation)
            statusTimeoutTask = Task { [weak self] in
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(timeoutSeconds * 1_000_000_000)
                    )
                } catch {
                    return
                }
                await MainActor.run {
                    guard let self,
                          self.pendingStatusCorrelationId == envelope.messageId else { return }
                    self.pendingStatusCorrelationId = nil
                    self.statusTimeoutTask = nil
                    self.resumeStatusContinuations(
                        throwing: InteractiveStartError.statusQueryTimedOut
                    )
                }
            }
            Task { [weak self] in
                do {
                    try await self?.sendEnvelope(envelope)
                } catch {
                    // The three-second timeout is intentional even when the
                    // immediate send fails: a delayed reachability change can
                    // still deliver a newer application-context snapshot.
                }
            }
        }
    }

    func resolveReclaimRequest(
        accepted: Bool,
        snapshot: LinkedScoreboardSnapshot?,
        detailedActions: [DetailedScoreAction]
    ) {
        guard let request = pendingReclaimRequest,
              let currentSession = activeSession,
              currentSession.sessionId == request.sessionId,
              currentSession.role == .phoneController else { return }
        reclaimTimeoutTask?.cancel()
        reclaimTimeoutTask = nil
        pendingReclaimRequest = nil
        sequence += 1

        if !accepted || snapshot == nil {
            let envelope = LinkEnvelope(
                correlationId: request.messageId,
                sessionId: request.sessionId,
                matchId: currentSession.handle.matchId,
                matchGeneration: currentSession.handle.matchGeneration,
                authorityEpoch: currentSession.authorityEpoch,
                kind: .reclaimDenied,
                sender: .phone,
                senderSequence: sequence,
                sessionRevision: currentSession.revision,
                sentAtEpochMilliseconds: nowMs(),
                payload: LinkAuthorityTransferPayload(baseRevision: currentSession.revision)
            )
            sendReportingError(envelope)
            return
        }

        let messageId = UUID()
        guard var machine = sessionMachine,
              machine.beginAuthorityTransfer(
                  correlationId: messageId,
                  targetRole: .phoneFollower,
                  kind: .watchReclaim
              ),
              machine.prepareAuthorityTransfer(
                  correlationId: messageId,
                  epoch: machine.authorityEpoch + 1
              ) else { return }
        _ = machine.advanceRevision()
        machine.registerPendingAcknowledgement(messageId)
        sessionMachine = machine
        synchronizeActiveSessionFromStateMachine()
        guard let session = activeSession else { return }
        persistContext()
        let envelope = LinkEnvelope(
            messageId: messageId,
            correlationId: request.messageId,
            sessionId: request.sessionId,
            matchId: session.handle.matchId,
            matchGeneration: session.handle.matchGeneration,
            authorityEpoch: session.authorityEpoch,
            kind: .reclaimAccepted,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: session.revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkAuthorityTransferPayload(
                snapshot: snapshot,
                detailedActions: detailedActions,
                baseRevision: session.revision
            )
        )
        do {
            let data = LinkEnvelopeEncoding.data(
                envelope,
                actionsKeyPath: \LinkAuthorityTransferPayload.detailedActions
            )
            pendingReclaimGrantMessageId = messageId
            pendingAck.enqueue(.init(
                messageId: messageId,
                sessionId: request.sessionId,
                revision: session.revision,
                data: data,
                lastSentAtEpochMilliseconds: nowMs()
            ))
            rescheduleRetryIfNeeded()
            Task {
                do {
                    try await transport.sendRealtime(data)
                } catch {
                    lastErrorMessage = error.localizedDescription
                }
            }
        } catch {
            if var machine = sessionMachine {
                _ = machine.acknowledge(messageId: messageId)
                _ = machine.rejectAuthorityTransfer(correlationId: messageId)
                sessionMachine = machine
                synchronizeActiveSessionFromStateMachine()
            }
            pendingReclaimGrantMessageId = nil
            lastErrorMessage = error.localizedDescription
            persistContext()
        }
    }

    func completePhoneTakeover(messageId: UUID) {
        guard let pending = pendingTakeoverApplication,
              pending.messageId == messageId,
              activeSession?.sessionId == pending.sessionId,
              sessionMachine?.role == .phoneController else { return }
        pendingTakeoverApplication = nil
        latestRemoteSnapshot = .init(
            sessionId: pending.sessionId,
            revision: pending.revision,
            matchGeneration: activeSession?.handle.matchGeneration ?? 0,
            snapshot: pending.snapshot,
            detailedActions: pending.detailedActions
        )
        watchBackgrounded = false
        persistContext()
    }

    func leaveSession(_ sessionId: UUID) {
        guard let session = activeSession, session.sessionId == sessionId else { return }
        let request = LinkPendingSessionEnd(
            handle: session.handle,
            authorityEpoch: session.authorityEpoch,
            revision: session.revision
        )
        if let index = pendingSessionEnds.firstIndex(where: {
            $0.handle.sessionId == sessionId
        }) {
            pendingSessionEnds[index] = request
        } else {
            pendingSessionEnds.append(request)
        }
        persistPendingSessionEnds()
        flushPendingSessionEnds()
        rescheduleRetryIfNeeded()
    }

    @discardableResult
    func attachPage(sessionId: UUID) -> LinkedSnapshotUpdate? {
        guard activeSession?.sessionId == sessionId else { return nil }
        persistContext()
        return latestRemoteSnapshot
    }

    /// Ends the linked session when the match is already finished. Exiting a
    /// finished linked scoreboard must not leave a stale session behind that
    /// keeps the Resume GameBar alive — the finished record is already on the
    /// phone (watch ingest or local commit), so there is nothing left to resume.
    func leaveSessionIfMatchFinished(_ sessionId: UUID) {
        guard let session = activeSession, session.sessionId == sessionId,
              session.completedMatchIds.contains(session.handle.matchId) else { return }
        leaveSession(sessionId)
    }

    func detachPage(sessionId: UUID) {
        guard activeSession?.sessionId == sessionId else { return }
        persistContext()
    }

    func notifyMatchFinished(
        sessionId: UUID,
        snapshot: LinkedScoreboardSnapshot,
        recordId: String,
        winnerSide: MatchSide?,
        manualEnd: Bool,
        startTime: Date? = nil,
        endTime: Date? = nil,
        totalScoreChanges: Int? = nil,
        participantNames: [String]? = nil,
        detailedActions: [DetailedScoreAction]? = nil,
        recordAlreadySaved: Bool = false
    ) {
        guard let currentSession = activeSession,
              currentSession.sessionId == sessionId,
              canEditLinkedMatch,
              !peerFinishedSharedMatch,
              !currentSession.completedMatchIds.contains(currentSession.handle.matchId),
              !publishedFinishedMatchIds.contains(currentSession.handle.matchId),
              !terminalOutbox.contains(
                  sessionId: sessionId,
                  matchId: currentSession.handle.matchId
              ),
              var machine = sessionMachine else { return }
        mergeDetailedActions(detailedActions)
        publishedFinishedMatchIds.insert(currentSession.handle.matchId)
        _ = machine.markFinished(matchId: currentSession.handle.matchId)
        _ = machine.advanceRevision(sender: .phone)
        sessionMachine = machine
        synchronizeActiveSessionFromStateMachine()
        guard let session = activeSession else { return }
        sequence += 1
        let messageId = UUID()
        let end = endTime ?? Date()
        let start = startTime ?? end.addingTimeInterval(-60)
        let duration = max(1, end.timeIntervalSince(start))
        let envelope = LinkEnvelope(
            messageId: messageId,
            sessionId: sessionId,
            matchId: session.handle.matchId,
            matchGeneration: session.handle.matchGeneration,
            authorityEpoch: session.authorityEpoch,
            kind: .matchFinished,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: session.revision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkMatchFinishedPayload(
                snapshot: snapshot,
                recordId: recordId,
                winnerSide: winnerSide,
                manualEnd: manualEnd,
                startTimeEpochMilliseconds: Int64(start.timeIntervalSince1970 * 1000),
                endTimeEpochMilliseconds: Int64(end.timeIntervalSince1970 * 1000),
                durationSeconds: duration,
                totalScoreChanges: totalScoreChanges ?? 0,
                detailedActions: mergedDetailedActions,
                participantNames: participantNames ?? session.setup.participantNames
            )
        )
        if recordAlreadySaved, !recordId.isEmpty {
            finishedRecordId = recordId
        }
        latestRemoteSnapshot = .init(
            sessionId: sessionId,
            revision: session.revision,
            matchGeneration: session.handle.matchGeneration,
            snapshot: snapshot,
            detailedActions: mergedDetailedActions
        )
        // 完整完赛包先持久化（outbox 即权威载荷），再按协商结果选通道；
        // 裁剪回退路径在选通道前绝不调用。
        let data = LinkFinishedFrameBuilder.buildFrame(
            envelope,
            peerSupportsCompressedFinish: peerSupportsCompressedFinish
        )
        sessionMachine?.registerPendingAcknowledgement(messageId)
        terminalOutbox.enqueue(.init(
            messageId: messageId,
            handle: session.handle,
            data: data,
            lastSentAtEpochMilliseconds: nowMs(),
            peerSupportsFileTransfer: peerSupportsFileTransfer
        ))
        // 落盘确认成功才允许发送；失败时保留内存 outbox 等待重试。
        guard persistTerminalOutbox() else {
            lastErrorMessage = NSLocalizedString("save_failed", value: "保存失败", comment: "")
            rescheduleRetryIfNeeded()
            return
        }
        persistContext()
        rescheduleRetryIfNeeded()
        Task {
            await deliverTerminalFrame(data)
        }
    }

    // MARK: - Private


    static func phoneInteractiveStartSupported(_ gameType: ScoreCore.GameType) -> Bool {
        WatchSportRegistry.supportsPhoneWatchLink(gameType)
    }


    func clearSession() {
        if let session = activeRecordSession { retiredRecordSessions.retire(session) }
        sessionMachine?.endSession()
        if let id = activeSession?.sessionId {
            revisionGate.endSession(id)
        }
        activeSession = nil
        sharedEditTracker = LinkSharedEditTracker()
        simultaneousEditNotice = nil
        peerSupportsCompressedFinish = false
        sessionMachine = nil
        controlRole = nil
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
        actionHistory = LinkSnapshotHistory()
        deltaActionTracker.reset()
        negotiatedPeerCapabilities = []
        pendingAck.clear()
        rescheduleRetryIfNeeded()
        latestRemoteSnapshot = nil
        mergedDetailedActions = []
        publishedFinishedMatchIds.removeAll()
        watchBackgrounded = false
        persistContext()
    }

    func installStateMachine(
        from session: ActiveSession,
        lifecycle: LinkSessionStateMachine.Lifecycle = .active
    ) {
        sessionMachine = LinkSessionStateMachine(
            handle: session.handle,
            role: session.role,
            authorityEpoch: session.authorityEpoch,
            revision: session.revision,
            completedMatchIds: session.completedMatchIds,
            lifecycle: lifecycle,
            pendingAcknowledgementIds: Set(
                pendingAck.pending.map { [$0.messageId] } ?? []
            )
                .union(terminalOutbox.items.map(\.messageId))
        )
    }

    func synchronizeActiveSessionFromStateMachine() {
        guard let machine = sessionMachine,
              var session = activeSession,
              session.sessionId == machine.handle.sessionId else { return }
        session.handle = machine.handle
        session.revision = machine.revision
        session.role = machine.role
        session.authorityEpoch = machine.authorityEpoch
        session.completedMatchIds = machine.completedMatchIds
        activeSession = session
        controlRole = machine.role
    }

    func trackSetupAnalyticsResult(_ result: AnalyticsResult) {
        guard !didTrackSetupAnalyticsResult else { return }
        didTrackSetupAnalyticsResult = true
        AppAnalytics.track(.watchLinkResult, parameters: [
            .gameType: .string(setupAnalyticsGameType ?? "unknown"),
            .entryPoint: .string(AnalyticsEntryPoint.watchLink.rawValue),
            .sourceSurface: .string(AnalyticsSourceSurface.phone.rawValue),
            .result: .string(result.rawValue)
        ])
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

    func resumeStatusContinuations(returning payload: LinkStatusPayload) {
        let continuations = statusContinuations
        statusContinuations.removeAll()
        continuations.forEach { $0.resume(returning: payload) }
    }

    func resumeStatusContinuations(throwing error: Error) {
        let continuations = statusContinuations
        statusContinuations.removeAll()
        continuations.forEach { $0.resume(throwing: error) }
    }

    func maxSets(for snapshot: LinkedScoreboardSnapshot) -> Int? {
        switch snapshot {
        case .rally(let state): return state.rules.maxSets
        case .tennis(let state): return state.rules.maxSets
        default: return nil
        }
    }
}
