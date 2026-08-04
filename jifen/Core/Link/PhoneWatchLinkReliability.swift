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
        if let existing = activeSession?.sessionId {
            leaveSession(existing)
        }
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
                    let data = try JSONEncoder().encode(envelope)
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
              currentSession.role == .phoneController,
              var machine = sessionMachine else { return }
        _ = machine.advanceRevision()
        sessionMachine = machine
        synchronizeActiveSessionFromStateMachine()
        guard var session = activeSession else { return }
        mergeDetailedActions(detailedActions)
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
            payload: LinkedScoreboardSetup(
                gameType: gameType,
                maxSets: maxSets(for: snapshot),
                initialSnapshot: snapshot,
                detailedActions: mergedDetailedActions,
                participantNames: session.setup.participantNames
            )
        )
        Task {
            do {
                let data = try JSONEncoder().encode(envelope)
                sessionMachine?.registerPendingAcknowledgement(messageId)
                pendingAck.enqueue(.init(
                    messageId: messageId,
                    sessionId: sessionId,
                    revision: session.revision,
                    data: data,
                    lastSentAtEpochMilliseconds: nowMs()
                ))
                rescheduleRetryIfNeeded()
                try transport.publishLatestSnapshot(data)
                if transport.isReachable {
                    try await transport.sendRealtime(data)
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
        let data = try JSONEncoder().encode(envelope)
        switch envelope.kind {
        case .stateSnapshot:
            try transport.publishLatestSnapshot(data)
            if transport.isReachable {
                try await transport.sendRealtime(data)
            }
        case .matchFinished:
            try transport.enqueueDurable(data)
        default:
            try await transport.sendRealtime(data)
        }
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
        if let pending = pendingAck.pending {
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

    private func performRetryWork() {
        let pendingMessageId = pendingAck.pending?.messageId
        let authorityTransferPending = pendingMessageId == pendingTakeoverMessageId
            || pendingMessageId == pendingReclaimGrantMessageId
        if let data = pendingAck.retryIfDue(nowEpochMilliseconds: nowMs()) {
            Task {
                do {
                    try await transport.sendRealtime(data)
                } catch {
                    lastErrorMessage = error.localizedDescription
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
        let dueTerminalData = terminalOutbox.retryDue(
            nowEpochMilliseconds: nowMs()
        )
        if !dueTerminalData.isEmpty {
            persistTerminalOutbox()
            for data in dueTerminalData {
                do {
                    try transport.enqueueDurable(data)
                } catch {
                    lastErrorMessage = error.localizedDescription
                }
            }
        }
        flushPendingSessionEnds()
    }

    func nowMs() -> Int64 {
        clock.nowEpochMilliseconds()
    }

    func persistTerminalOutbox() {
        guard !terminalOutbox.isEmpty else {
            outboxStore.removeObject(forKey: terminalOutboxKey)
            return
        }
        do {
            let data = try JSONEncoder().encode(terminalOutbox)
            outboxStore.set(data, forKey: terminalOutboxKey)
        } catch {
            reportPersistenceError(error)
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
                    pendingSessionEnds.removeAll {
                        $0.handle.sessionId == sessionId
                    }
                    persistPendingSessionEnds()
                    if activeSession?.sessionId == sessionId {
                        clearSession()
                    }
                } catch {
                    lastErrorMessage = error.localizedDescription
                }
            }
        }
    }

    func persistContext() {
        guard let session = activeSession else {
            contextStore.removeObject(forKey: contextKey)
            return
        }
        let context = PhoneLinkResumeContext(
            handle: session.handle,
            setup: session.setup,
            role: session.role,
            authorityEpoch: session.authorityEpoch,
            revision: session.revision,
            latestAuthoritativeSnapshot: latestRemoteSnapshot?.snapshot
                ?? session.setup.initialSnapshot,
            detailedActions: mergedDetailedActions,
            completedMatchIds: session.completedMatchIds,
            pendingTerminalMessageIds: Set(terminalOutbox.items.map(\.messageId))
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
        activeSession = ActiveSession(
            handle: context.handle,
            gameType: context.setup.gameType,
            revision: context.revision,
            role: context.role,
            authorityEpoch: context.authorityEpoch,
            setup: context.setup,
            completedMatchIds: context.completedMatchIds
        )
        if let session = activeSession {
            installStateMachine(from: session)
            synchronizeActiveSessionFromStateMachine()
        }
        mergedDetailedActions = context.detailedActions
        publishedFinishedMatchIds = context.completedMatchIds
        if let snapshot = context.latestAuthoritativeSnapshot {
            latestRemoteSnapshot = LinkedSnapshotUpdate(
                sessionId: context.handle.sessionId,
                revision: context.revision,
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
