import Foundation
import LinkCore
import LinkSync
import RecordCore
import ScoreCore

extension WatchLinkService {
    var resumeContext: WatchLinkResumeContext? {
        guard let handle = activeHandle, let setup = activeSetup,
              !pendingSessionEnds.contains(where: { $0.handle == handle }) else { return nil }
        return WatchLinkResumeContext(
            handle: handle, setup: setup, revision: activeRevision,
            latestAuthoritativeSnapshot: latestSnapshot?.snapshot,
            detailedActions: mergedDetailedActions, completedMatchIds: publishedFinishedMatchIds,
            pendingTerminalMessageIds: [], negotiatedPeerCapabilities: negotiatedPeerCapabilities
        )
    }

    var activeParticipantNames: [String]? { activeSetup?.participantNames }

    func clearRequestedSetup() {
        pendingConfirmRequest = nil
    }

    func acceptPendingSetup() {
        guard let request = pendingConfirmRequest, let snapshot = request.setup.initialSnapshot else { return }
        let previous = activeHandle
        if request.handle != previous, hasPendingIntentFinish {
            pendingConfirmRequest = nil
            sendSetupRejection(
                handle: request.handle, requestId: request.messageId, reason: .userDeclined, detail: "finish_pending"
            )
            return
        }
        do {
            try intentSync.activate(
                handle: request.handle, gameType: request.setup.gameType, initialSnapshot: snapshot,
                initialEpochMilliseconds: request.senderEpochMilliseconds,
                participantNames: request.setup.participantNames, initialActions: request.setup.detailedActions,
                peerSupportsFileTransfer: request.peerCapabilities.contains(.fileTransfer)
            )
            try persistActiveIntentContext(handle: request.handle, setup: request.setup, capabilities: request.peerCapabilities)
        } catch {
            if let previous {
                _ = try? intentSync.restoreActiveMatch(handle: previous)
            } else {
                try? intentSync.deactivate(handle: request.handle)
            }
            reportPersistenceError(error)
            return
        }
        installIntentMatch(handle: request.handle, setup: request.setup, capabilities: request.peerCapabilities)
        pendingConfirmRequest = nil
        acceptedSetup = request
        sendSetupAcceptance(request)
    }

    func sendSetupAcceptance(_ request: LinkedSetupRequest) {
        sequence += 1
        let envelope = LinkEnvelope(
            capabilities: request.peerCapabilities,
            correlationId: request.messageId,
            sessionId: request.sessionId, matchId: request.handle.matchId, matchGeneration: request.handle.matchGeneration,
            kind: .setupAccepted, sender: .watch, senderSequence: sequence, sessionRevision: 0,
            sentAtEpochMilliseconds: nowMs(), payload: EmptyLinkPayload()
        )
        sendReportingError(envelope)
    }

    func rejectPendingSetup() {
        guard let request = pendingConfirmRequest else { return }
        pendingConfirmRequest = nil
        sendSetupRejection(handle: request.handle, requestId: request.messageId, reason: .userDeclined)
    }

    func clearAcceptedSetup() {
        acceptedSetup = nil
    }

    func installAuthoritativeIntentStart(handle: LinkedMatchHandle, setup: LinkedScoreboardSetup) throws {
        guard let current = activeHandle, current.sessionId == handle.sessionId,
              current.matchGeneration < handle.matchGeneration,
              !pendingSessionEnds.contains(where: { $0.handle == current }) else {
            throw WatchLinkIntentSync.Failure.missingMatch
        }
        try persistActiveIntentContext(handle: handle, setup: setup, capabilities: negotiatedPeerCapabilities)
        installIntentMatch(handle: handle, setup: setup, capabilities: negotiatedPeerCapabilities)
        acceptedSetup = .init(
            handle: handle, messageId: UUID(), setup: setup,
            senderEpochMilliseconds: intentSync.update?.startEpochMilliseconds ?? 0,
            peerCapabilities: negotiatedPeerCapabilities
        )
    }

    func installIntentMatch(handle: LinkedMatchHandle, setup: LinkedScoreboardSetup, capabilities: Set<LinkCapability>) {
        activeSetup = setup
        activeSessionId = handle.sessionId
        activeHandle = handle
        activeGameType = setup.gameType
        activeRevision = 0
        latestSnapshot = nil
        mergedDetailedActions = []
        publishedFinishedMatchIds = []
        negotiatedPeerCapabilities = capabilities
        sessionMachine = LinkSessionStateMachine(handle: handle)
        if let update = intentSync.update {
            applyConfirmedIntentProjection(update, actions: intentSync.confirmedActions(for: handle))
        }
    }

    /// A durable coordinator checkpoint is the only source for linked progress.
    func applyConfirmedIntentProjection(_ update: WatchLinkedIntentUpdate, actions: [DetailedScoreAction]) {
        guard update.handle == activeHandle, update.committedRevision >= activeRevision,
              let gameType = activeGameType else { return }
        let changed = activeRevision != update.committedRevision || latestSnapshot?.snapshot != update.confirmedSnapshot
            || actions != mergedDetailedActions
        activeRevision = update.committedRevision
        let finished = update.confirmedSnapshot.isFinished
        publishedFinishedMatchIds = finished ? [update.handle.matchId] : []
        sessionMachine = LinkSessionStateMachine(
            handle: update.handle, revision: activeRevision, completedMatchIds: publishedFinishedMatchIds,
            lifecycle: finished ? .matchFinished : .active
        )
        activeSetup = LinkedScoreboardSetup(
            gameType: gameType, maxSets: maxSets(for: update.confirmedSnapshot),
            initialSnapshot: update.confirmedSnapshot, detailedActions: actions,
            participantNames: activeSetup?.participantNames ?? [], capabilities: activeSetup?.capabilities ?? LinkProtocol.capabilities
        )
        mergedDetailedActions = actions
        latestSnapshot = .init(
            sessionId: update.handle.sessionId, revision: activeRevision, matchGeneration: update.handle.matchGeneration,
            snapshot: update.confirmedSnapshot, detailedActions: actions
        )
        if WatchResumeSessionStore.shared.session?.linkHandle == update.handle {
            if update.savedRecordID != nil {
                WatchResumeSessionStore.shared.clear()
            } else if changed, !finished, let context = resumeContext {
                WatchResumeSessionStore.shared.applyLinkedSnapshot(update.confirmedSnapshot, context: context)
            }
        }
        scheduleRetryIfNeeded()
    }

    func syncLinkedScores() {
        guard let handle = activeHandle else { return }
        #if DEBUG
        if let summary = intentSync.diagnosticSummary() { print("[WatchLink] \(summary)") }
        #endif
        intentSync.requestRecovery(handle: handle)
        intentSync.replayPending(handle: handle)
    }

    func leaveSession() {
        guard let handle = activeHandle else { return }
        let previous = pendingSessionEnds
        pendingSessionEnds.removeAll { $0.handle == handle }
        pendingSessionEnds.append(.init(handle: handle, revision: activeRevision))
        guard persistPendingSessionEnds() else {
            pendingSessionEnds = previous
            return
        }
        _ = endLocalSession()
        flushPendingSessionEnds()
        rescheduleRetryIfNeeded()
    }

    func exitScoreboard(sessionId: UUID) {
        guard activeHandle?.sessionId == sessionId else { return }
        if intentSync.update?.savedRecordID != nil {
            leaveSession()
        } else {
            exitScoreboardToHome()
        }
    }

    func exitScoreboardToHome() {
        guard let handle = activeHandle else { return }
        sequence += 1
        let envelope = LinkEnvelope(
            sessionId: handle.sessionId, matchId: handle.matchId, matchGeneration: handle.matchGeneration,
            kind: .scoreboardExitedToHome, sender: .watch, senderSequence: sequence,
            sessionRevision: activeRevision, sentAtEpochMilliseconds: nowMs(), payload: EmptyLinkPayload()
        )
        sendReportingError(envelope)
    }

    func discardResumableSession() {
        leaveSession()
    }

    @discardableResult
    func restoreSuspendedSession(_ context: WatchLinkResumeContext) -> Bool {
        if let live = activeHandle { return live == context.handle && intentSync.update?.handle == live }
        return restoreActiveIntentMatch(matching: context.handle)
    }

    @discardableResult
    func endLocalSession() -> Bool {
        guard let handle = activeHandle else { return true }
        do {
            try intentSync.deactivate(handle: handle) {
                try retireActiveIntentContext(handle)
            }
        } catch {
            reportPersistenceError(error)
            return false
        }
        activeSessionId = nil
        activeHandle = nil
        activeRevision = 0
        activeGameType = nil
        activeSetup = nil
        sessionMachine = nil
        acceptedSetup = nil
        latestSnapshot = nil
        mergedDetailedActions = []
        publishedFinishedMatchIds = []
        negotiatedPeerCapabilities = []
        rescheduleRetryIfNeeded()
        return true
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
