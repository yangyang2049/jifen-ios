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
        authorityEpoch: UInt64? = nil,
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
            authorityEpoch: authorityEpoch ?? self.authorityEpoch,
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
            deadlines.append(now + 1_000)
        }
        guard let deadline = deadlines.min() else { return nil }
        return UInt64(max(0, deadline - now)) * 1_000_000
    }

    private func performRetryWork() {
        let pendingMessageId = pendingAck.pending?.messageId
        if let data = pendingAck.retryIfDue(nowEpochMilliseconds: nowMs()) {
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
        let dueTerminalData = terminalOutbox.retryDue(
            nowEpochMilliseconds: nowMs()
        )
        if !dueTerminalData.isEmpty {
            persistTerminalOutbox()
            for data in dueTerminalData {
                do {
                    try transport.enqueueDurable(data)
                } catch {
                    lastLinkErrorMessage = error.localizedDescription
                }
            }
        }
        flushPendingSessionEnds()
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
                    pendingSessionEnds.removeAll {
                        $0.handle.sessionId == sessionId
                    }
                    persistPendingSessionEnds()
                    if activeSessionId == sessionId {
                        endLocalSession()
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


    func persistContext() {
        guard let handle = activeHandle,
              let setup = activeSetup,
              let role = controlRole else {
            contextStore.removeObject(forKey: contextKey)
            return
        }
        let context = WatchLinkResumeContext(
            handle: handle,
            setup: setup,
            role: role,
            authorityEpoch: authorityEpoch,
            revision: activeRevision,
            latestAuthoritativeSnapshot: latestSnapshot?.snapshot
                ?? setup.initialSnapshot,
            detailedActions: mergedDetailedActions,
            completedMatchIds: publishedFinishedMatchIds,
            pendingTerminalMessageIds: Set(terminalOutbox.items.map(\.messageId))
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
        installStateMachine(from: context)
        synchronizeSessionStateFromMachine()
        activeGameType = context.setup.gameType
        activeSetup = context.setup
        phoneTookOver = context.role == .watchFollower
        mergedDetailedActions = context.detailedActions
        if let snapshot = context.latestAuthoritativeSnapshot {
            latestSnapshot = LinkedSnapshotUpdate(
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
