import Foundation
import LinkCore
import LinkSync

struct WatchActiveIntentContext: Codable {
    let handle: LinkedMatchHandle
    let setup: LinkedScoreboardSetup
    let capabilities: Set<LinkCapability>
}

extension WatchLinkService {
    enum DeliveryFailure: LocalizedError {
        case noChannel
        case channelFailed(String)

        var errorDescription: String? {
            switch self {
            case .noChannel:
                NSLocalizedString("linked_score_sync_timeout", value: "比分同步超时，将在重新连接后继续同步。", comment: "")
            case .channelFailed(let message):
                message
            }
        }
    }

    func sendReportingError<Payload: Codable & Sendable>(_ envelope: LinkEnvelope<Payload>) {
        Task {
            do {
                try await send(envelope)
            } catch {
                lastLinkErrorMessage = error.localizedDescription
            }
        }
    }

    func send<Payload: Codable & Sendable>(_ envelope: LinkEnvelope<Payload>) async throws {
        let result = await intentSessionEngine.send(envelope)
        try checkDelivery(result)
    }

    /// Returns true when the frame was queued on a durable channel. A sender
    /// of ordered score operations waits for confirmation in that case.
    @discardableResult
    func sendReplayableIntentFrame(_ data: Data, peerSupportsFileTransfer: Bool) async throws -> Bool {
        let result = await intentSessionEngine.sendReplayableFrame(
            data, kind: .intentFrame, peerSupportsFileTransfer: peerSupportsFileTransfer
        )
        try checkDelivery(result)
        return result.steps.contains(.durableFile) || result.steps.contains(.durableUserInfo)
    }

    private func checkDelivery(_ result: LinkSendOutcome) throws {
        if result.steps.contains(where: { $0 != .hold && result.failures[$0] == nil }) { return }
        if let message = result.firstErrorDescription { throw DeliveryFailure.channelFailed(message) }
        throw DeliveryFailure.noChannel
    }

    func scheduleRetryIfNeeded() {
        guard ackRetryTask == nil, transport.status.isActivated else { return }
        let wantsReplay = transport.isReachable && intentSync.hasDurableRetryWork
        let hasPendingEnd = pendingSessionEnds.contains {
            !pendingSessionEndInFlight.contains($0.handle.sessionId)
                && (transport.isReachable || !intentSync.hasPendingOperations(for: $0.handle))
        }
        let pendingEndDelay = intentSessionEngine.nextRetryDelayNanoseconds(hasPendingSessionEnd: hasPendingEnd)
        guard let delay = pendingEndDelay ?? (wantsReplay ? 3_000_000_000 : nil) else { return }

        ackRetryTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard let self else { return }
            ackRetryTask = nil
            if transport.isReachable { intentSync.retryPendingAfterReconnect() }
            flushPendingSessionEnds()
            scheduleRetryIfNeeded()
        }
    }

    func rescheduleRetryIfNeeded() {
        ackRetryTask?.cancel()
        ackRetryTask = nil
        scheduleRetryIfNeeded()
    }

    @discardableResult
    func persistPendingSessionEnds() -> Bool {
        do {
            if pendingSessionEnds.isEmpty {
                try outboxStore.removeOrThrow(forKey: pendingSessionEndsKey)
            } else {
                try outboxStore.setOrThrow(JSONEncoder().encode(pendingSessionEnds), forKey: pendingSessionEndsKey)
            }
            return true
        } catch {
            reportPersistenceError(error)
            return false
        }
    }

    func flushPendingSessionEnds() {
        guard transport.status.isActivated, !pendingSessionEnds.isEmpty, persistPendingSessionEnds() else { return }
        for request in pendingSessionEnds {
            let handle = request.handle
            guard !pendingSessionEndInFlight.contains(handle.sessionId) else { continue }
            if intentSync.hasPendingOperations(for: handle) {
                intentSync.replayPending(handle: handle)
                continue
            }
            if activeHandle == handle {
                guard endLocalSession() else { continue }
            } else {
                do {
                    try retireActiveIntentContext(handle)
                } catch {
                    reportPersistenceError(error)
                    continue
                }
            }

            pendingSessionEndInFlight.insert(handle.sessionId)
            sequence += 1
            let frame = LinkEnvelope(
                sessionId: handle.sessionId, matchId: handle.matchId, matchGeneration: handle.matchGeneration,
                kind: .sessionLeft, sender: .watch, senderSequence: sequence,
                sessionRevision: request.revision, sentAtEpochMilliseconds: nowMs(), payload: EmptyLinkPayload()
            )
            Task {
                defer {
                    pendingSessionEndInFlight.remove(handle.sessionId)
                    rescheduleRetryIfNeeded()
                }
                do {
                    let data = try JSONEncoder().encode(frame)
                    // The peer may be offline when the user leaves. Queuing
                    // this small frame reliably is what permits local dequeue.
                    try transport.enqueueDurable(data)
                    let previous = pendingSessionEnds
                    pendingSessionEnds.removeAll { $0 == request }
                    if !persistPendingSessionEnds() { pendingSessionEnds = previous }
                } catch {
                    lastLinkErrorMessage = error.localizedDescription
                }
            }
        }
    }

    func nowMs() -> Int64 { clock.nowEpochMilliseconds() }

    var storedLinkContext: WatchLinkResumeContext? {
        if let live = resumeContext { return live }
        do {
            guard let pointer = try activeIntentPointer() else { return nil }
            return try intentSync.restoredContext(for: pointer)
        } catch {
            reportPersistenceError(error)
            return nil
        }
    }

    func persistActiveIntentContext(handle: LinkedMatchHandle, setup: LinkedScoreboardSetup, capabilities: Set<LinkCapability>) throws {
        let descriptor = LinkedScoreboardSetup(
            gameType: setup.gameType, maxSets: setup.maxSets,
            participantNames: setup.participantNames, capabilities: setup.capabilities
        )
        let pointer = WatchActiveIntentContext(handle: handle, setup: descriptor, capabilities: capabilities)
        try contextStore.setOrThrow(JSONEncoder().encode(pointer), forKey: contextKey)
    }

    func retireActiveIntentContext(_ handle: LinkedMatchHandle) throws {
        try contextStore.setOrThrow(Data([1]), forKey: retiredIntentKey(handle))
        do {
            if let data = try storedContextData(forKey: contextKey),
               try JSONDecoder().decode(WatchActiveIntentContext.self, from: data).handle == handle {
                try contextStore.removeOrThrow(forKey: contextKey)
            }
        } catch {
            // The durable tombstone still prevents this pointer from reopening.
            reportPersistenceError(error)
        }
    }

    func isRetiredIntentHandle(_ handle: LinkedMatchHandle) throws -> Bool {
        try storedContextData(forKey: retiredIntentKey(handle)) != nil
    }

    private func retiredIntentKey(_ handle: LinkedMatchHandle) -> String {
        "watch-intent-ended-\(handle.sessionId.uuidString)-\(handle.matchId.uuidString)-\(handle.matchGeneration)"
    }

    private func storedContextData(forKey key: String) throws -> Data? {
        if let fileStore = contextStore as? FileLinkDataStore {
            return try fileStore.dataOrThrow(forKey: key)
        }
        return contextStore.data(forKey: key)
    }

    private func activeIntentPointer() throws -> WatchActiveIntentContext? {
        guard let data = try storedContextData(forKey: contextKey) else { return nil }
        let pointer = try JSONDecoder().decode(WatchActiveIntentContext.self, from: data)
        guard pointer.capabilities.contains(.sharedIntentSync), try !isRetiredIntentHandle(pointer.handle),
              !pendingSessionEnds.contains(where: { $0.handle == pointer.handle }) else { return nil }
        return pointer
    }

    func restoreContext() {
        _ = restoreActiveIntentMatch()
    }

    @discardableResult
    func restoreActiveIntentMatch(matching handle: LinkedMatchHandle? = nil) -> Bool {
        do {
            guard let pointer = try activeIntentPointer(),
                  handle == nil || pointer.handle == handle,
                  let context = try intentSync.restoredContext(for: pointer),
                  try intentSync.restoreActiveMatch(handle: pointer.handle) else { return false }
            installIntentMatch(handle: pointer.handle, setup: context.setup, capabilities: pointer.capabilities)
            return true
        } catch {
            reportPersistenceError(error)
            return false
        }
    }

    func reportPersistenceError(_ error: Error) {
        lastLinkErrorMessage = String(
            format: NSLocalizedString(
                "linked_score_persistence_failed", value: "无法保存联动恢复数据：%@", comment: ""
            ),
            error.localizedDescription
        )
    }
}
