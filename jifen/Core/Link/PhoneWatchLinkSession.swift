import Foundation
import LinkCore
import LinkSync
import Observation
import RecordCore
import ScoreCore
import UIKit


extension PhoneWatchLinkService {
    static func phoneInteractiveStartSupported(_ gameType: ScoreCore.GameType) -> Bool {
        WatchSportRegistry.supportsPhoneWatchLink(gameType)
    }

    /// Ask the Watch to replay operations and request the phone checkpoint.
    @discardableResult
    func requestScoreResync() -> Bool {
        guard let session = activeSession else { return false }
        #if DEBUG
        if let summary = try? intentCoordinator.diagnosticSummary() { print("[PhoneLink] \(summary)") }
        #endif
        requestWatchIntentReplay(handle: session.handle)
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

    func clearSession() {
        if let handle = activeSession?.handle { intentCoordinator.deactivate(handle: handle) }
        sessionMachine?.endSession()
        activeSession = nil
        peerSupportsCompressedFinish = false
        sessionMachine = nil
        pendingStatusCorrelationId = nil
        statusTimeoutTask?.cancel()
        statusTimeoutTask = nil
        resumeStatusContinuations(throwing: CancellationError())
        negotiatedPeerCapabilities = []
        rescheduleRetryIfNeeded()
        latestRemoteSnapshot = nil
        mergedDetailedActions = []
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
            lifecycle: lifecycle
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
