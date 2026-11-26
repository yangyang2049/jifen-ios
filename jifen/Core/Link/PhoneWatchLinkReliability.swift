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
        pendingStatusCorrelationId = nil
        statusTimeoutTask?.cancel()
        statusTimeoutTask = nil
        resumeStatusContinuations(throwing: CancellationError())
        peerSupportsCompressedFinish = false
        negotiatedPeerCapabilities = []
        mergedDetailedActions = []
        activeSession = ActiveSession(
            handle: LinkedMatchHandle(sessionId: sessionId),
            gameType: gameType,
            revision: 0,
            setup: setup,
            completedMatchIds: []
        )
        if let session = activeSession {
            installStateMachine(from: session, lifecycle: .starting)
        }
        latestRemoteSnapshot = nil
        finishedRecordId = nil
        lastErrorMessage = nil
        let seedEpochMilliseconds = nowMs()
        do {
            try prepareIntentMatch(initialEpochMilliseconds: seedEpochMilliseconds)
        } catch {
            clearSession()
            throw error
        }
        sequence += 1
        let envelope = LinkEnvelope(
            supportsCompressedFinish: true,
            sessionId: sessionId,
            matchId: activeSession?.handle.matchId,
            matchGeneration: activeSession?.handle.matchGeneration ?? 1,
            kind: .setupRequest,
            sender: .phone,
            senderSequence: sequence,
            sessionRevision: 0,
            sentAtEpochMilliseconds: seedEpochMilliseconds,
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


    func sendEnvelope<Payload: Codable & Sendable>(_ envelope: LinkEnvelope<Payload>) async throws {
        try await transport.sendRealtime(JSONEncoder().encode(envelope))
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
        intentSessionEngine.nextRetryDelayNanoseconds(hasPendingSessionEnd: pendingSessionEnds.contains {
            !pendingSessionEndInFlight.contains($0.handle.sessionId)
        })
    }

    func performRetryWork() {
        flushPendingSessionEnds()
    }

    func nowMs() -> Int64 { clock.nowEpochMilliseconds() }

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
            guard !pendingSessionEndInFlight.contains(sessionId) else {
                continue
            }
            pendingSessionEndInFlight.insert(sessionId)
            sequence += 1
            let envelope = LinkEnvelope(
                sessionId: sessionId,
                matchId: request.handle.matchId,
                matchGeneration: request.handle.matchGeneration,
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
                    if activeSession?.handle == request.handle {
                        // Retire the durable resume pointer before dropping the queued end.
                        try contextStore.removeOrThrow(forKey: contextKey)
                        clearSession()
                    }
                    let previousRequests = pendingSessionEnds
                    pendingSessionEnds.removeAll { $0 == request }
                    if !persistPendingSessionEnds() {
                        pendingSessionEnds = previousRequests
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

    @discardableResult
    func persistContext() -> Bool {
        do {
            guard let session = activeSession else {
                try contextStore.removeOrThrow(forKey: contextKey)
                return true
            }
            let context = PhoneLinkResumeContext(
                handle: session.handle,
                setup: LinkedScoreboardSetup(
                    gameType: session.gameType, participantNames: session.setup.participantNames
                ),
                revision: 0,
                latestAuthoritativeSnapshot: nil,
                detailedActions: [],
                completedMatchIds: [],
                pendingTerminalMessageIds: [],
                finishedRecordId: nil,
                peerSupportsCompressedFinish: peerSupportsCompressedFinish,
                negotiatedPeerCapabilities: negotiatedPeerCapabilities
            )
            try contextStore.setOrThrow(JSONEncoder().encode(context), forKey: contextKey)
            return true
        } catch {
            reportPersistenceError(error)
            return false
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
              let context = try? JSONDecoder().decode(PhoneLinkResumeContext.self, from: data),
              let capabilities = context.negotiatedPeerCapabilities,
              LinkProtocol.requiredCapabilities.isSubset(of: capabilities),
              !pendingSessionEnds.contains(where: { $0.handle == context.handle }) else {
            contextStore.removeObject(forKey: contextKey)
            return
        }
        let session = ActiveSession(
            handle: context.handle, gameType: context.setup.gameType,
            revision: 0, setup: context.setup, completedMatchIds: []
        )
        activeSession = session
        installStateMachine(from: session)
        peerSupportsCompressedFinish = context.peerSupportsCompressedFinish == true
        negotiatedPeerCapabilities = capabilities
    }
}
