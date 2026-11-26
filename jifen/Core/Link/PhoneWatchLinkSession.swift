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
              LinkManualResyncPolicy.canRequest(hasActiveSession: true) else {
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

    /// Query the Watch for the status of the current linked match.
    @discardableResult
    func queryStatus(timeoutSeconds: TimeInterval) async throws -> LinkStatusPayload {
        guard let session = activeSession else {
            throw CancellationError()
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

    func leaveSession(_ sessionId: UUID) {
        guard let session = activeSession, session.sessionId == sessionId else { return }
        let request = LinkPendingSessionEnd(
            handle: session.handle,
            revision: session.revision
        )
        if let index = pendingSessionEnds.firstIndex(where: {
            $0.handle.sessionId == sessionId
        }) {
            pendingSessionEnds[index] = request
        } else {
            pendingSessionEnds.append(request)
        }
        // 先持久化退役上下文（含 pending end 记录）再清空内存待发状态：
        // 崩溃窗口内重启也不会把该 handle 当成可恢复联动。
        persistPendingSessionEnds()
        persistContext()
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
        pendingStatusCorrelationId = nil
        statusTimeoutTask?.cancel()
        statusTimeoutTask = nil
        resumeStatusContinuations(throwing: CancellationError())
        actionHistory = LinkSnapshotHistory()
        deltaActionTracker.reset()
        negotiatedPeerCapabilities = []
        pendingAck.clear()
        rescheduleRetryIfNeeded()
        latestRemoteSnapshot = nil
        mergedDetailedActions = []
        publishedFinishedMatchIds.removeAll()
        persistContext()
    }

    func installStateMachine(
        from session: ActiveSession,
        lifecycle: LinkSessionStateMachine.Lifecycle = .active
    ) {
        sessionMachine = LinkSessionStateMachine(
            handle: session.handle,
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
        session.completedMatchIds = machine.completedMatchIds
        activeSession = session
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
