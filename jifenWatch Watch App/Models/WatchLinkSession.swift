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
        return WatchLinkResumeContext(
            handle: handle,
            setup: setup,
            role: controlRole,
            authorityEpoch: authorityEpoch,
            revision: activeRevision,
            latestAuthoritativeSnapshot: latestSnapshot?.snapshot
                ?? setup.initialSnapshot,
            detailedActions: mergedDetailedActions,
            completedMatchIds: publishedFinishedMatchIds,
            pendingTerminalMessageIds: Set(terminalOutbox.items.map(\.messageId))
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
                  acceptedRole: .watchController
              ) else { return }
        pendingConfirmRequest = nil
        sessionMachine = machine
        synchronizeSessionStateFromMachine()
        activeGameType = request.setup.gameType
        activeSetup = request.setup
        phoneTookOver = false
        acceptedSetup = request
        persistContext()
        sequence += 1
        let envelope = LinkEnvelope(
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
        sequence += 1
        let envelope = LinkEnvelope(
            correlationId: request.messageId,
            sessionId: request.sessionId,
            matchId: request.handle.matchId,
            matchGeneration: request.handle.matchGeneration,
            authorityEpoch: request.authorityEpoch,
            kind: .setupRejected,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: 0,
            sentAtEpochMilliseconds: nowMs(),
            payload: EmptyLinkPayload()
        )
        sendReportingError(envelope)
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
        guard isController,
              let sessionId = activeSessionId,
              let gameType = activeGameType,
              var machine = sessionMachine else { return }
        _ = machine.advanceRevision()
        sessionMachine = machine
        synchronizeSessionStateFromMachine()
        mergeDetailedActions(detailedActions)
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
            snapshot: snapshot,
            detailedActions: mergedDetailedActions
        )
        persistContext()
        sequence += 1
        let messageId = UUID()
        let envelope = LinkEnvelope(
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
            payload: LinkedScoreboardSetup(
                gameType: gameType,
                maxSets: maxSets(for: snapshot),
                initialSnapshot: snapshot,
                detailedActions: mergedDetailedActions,
                participantNames: activeSetup?.participantNames ?? []
            )
        )
        Task {
            do {
                let data = try JSONEncoder().encode(envelope)
                if var machine = sessionMachine {
                    machine.registerPendingAcknowledgement(messageId)
                    sessionMachine = machine
                }
                pendingAck.enqueue(.init(
                    messageId: messageId,
                    sessionId: sessionId,
                    revision: activeRevision,
                    data: data,
                    lastSentAtEpochMilliseconds: nowMs()
                ))
                rescheduleRetryIfNeeded()
                try transport.publishLatestSnapshot(data)
                try await transport.sendRealtime(data)
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
        guard isController,
              let gameType = activeGameType,
              var machine = sessionMachine else { return }
        let nextHandle = machine.beginNextMatch()
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
    ) {
        guard let sessionId = activeSessionId,
              let handle = activeHandle,
              var machine = sessionMachine else { return }
        if publishedFinishedMatchIds.contains(handle.matchId)
            || terminalOutbox.contains(sessionId: sessionId, matchId: handle.matchId) { return }
        let stableRecordId = recordId.isEmpty ? "w_\(UUID().uuidString)" : recordId
        mergeDetailedActions(detailedActions)
        _ = machine.markFinished(matchId: handle.matchId)
        _ = machine.advanceRevision()
        sessionMachine = machine
        synchronizeSessionStateFromMachine()
        sequence += 1
        let messageId = UUID()
        let end = endTime ?? Date()
        let start = startTime ?? end.addingTimeInterval(-60)
        let duration = max(1, end.timeIntervalSince(start))
        let envelope = LinkEnvelope(
            messageId: messageId,
            sessionId: sessionId,
            matchId: handle.matchId,
            matchGeneration: handle.matchGeneration,
            authorityEpoch: authorityEpoch,
            kind: .matchFinished,
            sender: .watch,
            senderSequence: sequence,
            sessionRevision: activeRevision,
            sentAtEpochMilliseconds: nowMs(),
            payload: LinkMatchFinishedPayload(
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
        )
        Task {
            do {
                let data = try JSONEncoder().encode(envelope)
                if var machine = sessionMachine {
                    machine.registerPendingAcknowledgement(messageId)
                    sessionMachine = machine
                }
                terminalOutbox.enqueue(.init(
                    messageId: messageId,
                    handle: handle,
                    data: data,
                    lastSentAtEpochMilliseconds: nowMs()
                ))
                persistTerminalOutbox()
                persistContext()
                rescheduleRetryIfNeeded()
                try transport.enqueueDurable(data)
            } catch {
                lastLinkErrorMessage = error.localizedDescription
            }
        }
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

    /// Discard the watch resume entry and hand scoring control back to the phone.
    func discardResumableSession(reason: LinkResumeDiscardReason) {
        guard let sessionId = activeSessionId else { return }
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
        _ = revisionGate.beginMatch(context.handle, initialRevision: context.revision)
        installStateMachine(from: context)
        synchronizeSessionStateFromMachine()
        activeGameType = context.setup.gameType
        activeSetup = context.setup
        phoneTookOver = context.controlRole == .watchFollower
        mergedDetailedActions = context.detailedActions
        if let snapshot = context.latestAuthoritativeSnapshot {
            latestSnapshot = .init(
                sessionId: context.sessionId,
                revision: context.revision,
                snapshot: snapshot,
                detailedActions: context.detailedActions
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
        controlRole = nil
        acceptedSetup = nil
        pendingConfirmRequest = nil
        latestSnapshot = nil
        mergedDetailedActions = []
        phoneTookOver = false
        publishedFinishedMatchIds.removeAll()
        pendingReclaimAcceptance = nil
        pendingReclaimRequestMessageId = nil
        reclaimRequestTimeoutTask?.cancel()
        reclaimRequestTimeoutTask = nil
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
        guard let incoming, !incoming.isEmpty else { return }
        mergedDetailedActions = incoming.sorted {
            ($0.epochMilliseconds ?? 0, $0.id.uuidString) < ($1.epochMilliseconds ?? 0, $1.id.uuidString)
        }
    }

    func maxSets(for snapshot: LinkedScoreboardSnapshot) -> Int? {
        switch snapshot {
        case .rally(let state): return state.rules.maxSets
        case .tennis(let state): return state.rules.maxSets
        default: return nil
        }
    }

    static func isValidLinkedSetup(_ setup: LinkedScoreboardSetup) -> Bool {
        guard let snapshot = setup.initialSnapshot else { return false }
        switch (setup.gameType, snapshot) {
        case (.pingpong, .rally(let state)),
             (.badminton, .rally(let state)),
             (.pickleball, .rally(let state)):
            return state.doubles == nil
        case (.pingpongDoubles, .rally(let state)),
             (.badmintonDoubles, .rally(let state)),
             (.pickleballDoubles, .rally(let state)):
            return state.doubles?.playerNames.count == 4
        case (.tennis, .tennis(let state)):
            return state.doublesPlayerNames == nil
        case (.tennisDoubles, .tennis(let state)):
            return state.doublesPlayerNames?.count == 4
        case (.archeryDual, .archery):
            return true
        case (.eightBall, .eightBall), (.snooker, .snooker):
            return setup.participantNames.count == 2
        case (.nineBall, .nineBall(let state)):
            return (2...4).contains(state.playerCount)
        default:
            return false
        }
    }
}
