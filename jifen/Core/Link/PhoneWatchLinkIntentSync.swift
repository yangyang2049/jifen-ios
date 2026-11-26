import Foundation
import LinkCore
import LinkSync
import RecordCore
import ScoreCore

struct PhoneLinkIntentProjection: Codable {
    let handle: LinkedMatchHandle
    let revision: UInt64
    let snapshot: LinkedScoreboardSnapshot
    let actions: [DetailedScoreAction]
    let finishedPayload: LinkMatchFinishedPayload?
    let finishedRecordId: String?
    let nextMatchHandle: LinkedMatchHandle?
    let nextMatchEpochMilliseconds: Int64?
}

extension PhoneWatchLinkService {
    private var intentReducerAdapter: LinkedReducerAdapter {
        LinkedReducerAdapter()
    }

    func makeIntentCoordinator(directoryURL: URL) -> PhoneLinkedIntentCoordinator {
        PhoneLinkedIntentCoordinator(directoryURL: directoryURL, adapter: intentReducerAdapter) { [weak self] projection in
            guard let self else { throw CancellationError() }
            try installIntentProjection(projection)
        }
    }

    @discardableResult
    func prepareIntentMatch(initialEpochMilliseconds: Int64? = nil) throws -> PhoneLinkedIntentCoordinator.Checkpoint {
        guard let activeSession else {
            throw PhoneLinkedIntentCoordinator.Failure.unknownMatch
        }
        if let current = intentCoordinator.activeCheckpoint, current.handle == activeSession.handle {
            return current
        }
        guard let snapshot = activeSession.setup.initialSnapshot else {
            throw PhoneLinkedIntentCoordinator.Failure.invalidInitialSnapshot
        }
        let checkpoint = try intentCoordinator.activate(
            handle: activeSession.handle,
            gameType: activeSession.gameType,
            initialSnapshot: snapshot,
            initialEpochMilliseconds: initialEpochMilliseconds ?? nowMs()
        )
        try restoreIntentProjection(handle: activeSession.handle)
        return checkpoint
    }

    func restoreIntentProjection(handle: LinkedMatchHandle) throws {
        if let previous = try storedIntentProjection(for: handle) {
            displayIntentProjection(previous)
        } else if let checkpoint = intentCoordinator.activeCheckpoint,
                  checkpoint.handle == handle, checkpoint.committedRevision == 0 {
            displayIntentProjection(PhoneLinkIntentProjection(
                handle: handle, revision: 0, snapshot: intentReducerAdapter.snapshot(checkpoint.state),
                actions: [], finishedPayload: nil, finishedRecordId: nil,
                nextMatchHandle: nil, nextMatchEpochMilliseconds: nil
            ))
        }
    }

    @discardableResult
    func submitLocalIntent(
        _ intent: LinkedScoreboardIntent,
        sessionId: UUID,
        opId: UUID = UUID(),
        at epochMilliseconds: Int64? = nil
    ) throws -> LinkOperationCommitPayload {
        guard sessionId == activeSession?.sessionId else {
            throw PhoneLinkedIntentCoordinator.Failure.localOperationRequiresActiveMatch
        }
        let current = try prepareIntentMatch()
        let now = nowMs()
        let result = try intentCoordinator.submitLocal(
            intent,
            handle: current.handle,
            opId: opId,
            createdAtEpochMilliseconds: epochMilliseconds ?? now,
            phoneClockReferenceEpochMilliseconds: now
        )
        sendIntentFrame(.intentCommit, payload: result, handle: current.handle, revision: result.committedRevision)
        if result.outcome == .accepted, case .nextMatch = intent {
            try finishIntentRollover()
        }
        return result
    }

    func startNextIntentMatch(sessionId: UUID) throws {
        let current = try prepareIntentMatch()
        guard current.handle.sessionId == sessionId, current.handle.matchGeneration < UInt64.max else {
            throw PhoneLinkedIntentCoordinator.Failure.localOperationRequiresActiveMatch
        }
        if current.nextMatchHandle != nil {
            try finishIntentRollover()
            return
        }
        let next = current.handle.nextMatch()
        let result = try submitLocalIntent(
            .nextMatch(matchId: next.matchId, matchGeneration: next.matchGeneration),
            sessionId: sessionId
        )
        guard result.outcome == .accepted else { throw PhoneLinkedIntentCoordinator.Failure.unexpectedRollover }
    }

    func finishIntentRollover() throws {
        guard let old = intentCoordinator.activeCheckpoint, let next = old.nextMatchHandle,
              let session = activeSession, session.handle == old.handle,
              let previous = try storedIntentProjection(for: old.handle),
              let seedEpoch = previous.nextMatchEpochMilliseconds else { return }
        guard let seed = intentReducerAdapter.nextMatchSnapshot(from: old.state, at: seedEpoch) else {
            throw PhoneLinkedIntentCoordinator.Failure.invalidInitialSnapshot
        }
        try intentCoordinator.activate(
            handle: next, gameType: session.gameType, initialSnapshot: seed, initialEpochMilliseconds: seedEpoch
        )
        let setup = LinkedScoreboardSetup(
            gameType: session.gameType, maxSets: maxSets(for: seed), initialSnapshot: seed,
            participantNames: session.setup.participantNames
        )
        activeSession = ActiveSession(
            handle: next, gameType: session.gameType, revision: 0, setup: setup,
            completedMatchIds: session.completedMatchIds
        )
        if let activeSession { installStateMachine(from: activeSession, lifecycle: .active) }
        mergedDetailedActions = []
        finishedRecordId = nil
        latestRemoteSnapshot = .init(
            sessionId: next.sessionId, revision: 0, matchGeneration: next.matchGeneration,
            snapshot: seed, detailedActions: []
        )
        try restoreIntentProjection(handle: next)
        sendIntentMatchStarted()
    }

    func sendIntentMatchStarted() {
        guard let seed = intentCoordinator.activeSeedCheckpoint, let activeSession,
              seed.handle == activeSession.handle, persistContext() else { return }
        let snapshot = intentReducerAdapter.snapshot(seed.state)
        let setup = LinkedScoreboardSetup(
            gameType: activeSession.gameType, maxSets: maxSets(for: snapshot), initialSnapshot: snapshot,
            participantNames: activeSession.setup.participantNames
        )
        sendIntentFrame(
            .matchStarted, payload: setup, handle: seed.handle, revision: 0,
            sentAt: seed.effectiveEpochMilliseconds
        )
    }

    func receiveWatchIntent(_ data: Data) {
        guard let frame = try? JSONDecoder().decode(LinkEnvelope<LinkOperation>.self, from: data),
              frame.kind == .intentSubmit, frame.sender == .watch,
              frame.protocolVersion == LinkProtocol.currentVersion,
              frame.handle == frame.payload.handle else { return }
        do {
            if frame.handle == activeSession?.handle { _ = try prepareIntentMatch() }
            let result = try intentCoordinator.receiveWatchOperation(
                frame.payload, phoneClockReferenceEpochMilliseconds: nowMs()
            )
            sendIntentFrame(.intentCommit, payload: result, handle: frame.handle, revision: result.committedRevision)
            if result.outcome == .accepted, case .nextMatch = result.op.intent {
                try finishIntentRollover()
            }
        } catch PhoneHostSequenceError.missingSequence {
            requestWatchIntentReplay(handle: frame.handle)
        } catch PhoneLinkedIntentCoordinator.Failure.unknownMatch {
            // Unknown handles have no journal and cannot affect this session.
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func receiveWatchIntentRecoveryRequest(_ data: Data) {
        guard let frame = try? JSONDecoder().decode(LinkEnvelope<LinkIntentRecoveryRequest>.self, from: data),
              frame.kind == .resyncRequest, frame.sender == .watch,
              frame.protocolVersion == LinkProtocol.currentVersion,
              frame.payload.pendingOperationIds.count <= 502 else { return }
        do {
            if frame.handle == activeSession?.handle { _ = try prepareIntentMatch() }
            let checkpoint = try intentCoordinator.checkpoint(
                for: frame.handle, watchOperationIds: frame.payload.pendingOperationIds
            )
            let stored = try storedIntentProjection(for: frame.handle)
            var finished = stored?.finishedPayload
            finished?.detailedActions = []
            let payload = LinkIntentRecoveryPayload(
                checkpoint: checkpoint,
                detailedActions: stored?.actions ?? [],
                nextMatchHandle: stored?.nextMatchHandle, finishedPayload: finished
            )
            sendIntentFrame(
                .intentCheckpoint, payload: payload, handle: frame.handle,
                revision: checkpoint.committedRevision, correlationId: frame.messageId
            )
            if let successor = stored?.nextMatchHandle, successor == activeSession?.handle {
                _ = try prepareIntentMatch()
                sendIntentMatchStarted()
            }
        } catch PhoneLinkedIntentCoordinator.Failure.unknownMatch {
            // A stale or unknown request cannot start a linked match.
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func requestWatchIntentReplay(handle: LinkedMatchHandle) {
        sendIntentFrame(
            .resyncRequest, payload: EmptyLinkPayload(), handle: handle,
            revision: intentCoordinator.activeCheckpoint.flatMap {
                $0.handle == handle ? $0.committedRevision : nil
            } ?? 0
        )
    }

    private func installIntentProjection(_ projection: PhoneLinkedIntentCoordinator.Projection) throws {
        let checkpoint = projection.checkpoint
        let handle = checkpoint.handle
        let prior = try storedIntentProjection(for: handle)
        var actions = prior?.actions ?? []
        var actionIds = Set(actions.map(\.id))
        for action in projection.commits.flatMap(\.deltaActions) where actionIds.insert(action.id).inserted {
            actions.append(action)
        }

        var terminal = prior?.finishedPayload
        var recordId = prior?.finishedRecordId
        if terminal == nil, projection.snapshot.isFinished,
           let terminalCommit = projection.commits.first(where: {
               $0.outcome == .accepted && $0.authoritativeSnapshot?.isFinished == true
           }) {
            let end = terminalCommit.effectiveEpochMilliseconds
            let duration = max(0, Double(end) - Double(projection.initialEpochMilliseconds)) / 1_000
            let payload = LinkMatchFinishedPayload(
                snapshot: projection.snapshot,
                recordId: "w_\(handle.matchId.uuidString)",
                manualEnd: terminalCommit.op.intent == .finish,
                startTimeEpochMilliseconds: projection.initialEpochMilliseconds,
                endTimeEpochMilliseconds: end,
                durationSeconds: duration,
                totalScoreChanges: actions.filter { $0.type != .undo }.count,
                detailedActions: actions,
                participantNames: activeSession?.handle == handle ? activeSession?.setup.participantNames ?? [] : []
            )
            recordId = try recordSink.ingest(payload: payload, gameType: checkpoint.state.gameType, matchId: handle.matchId)
            terminal = payload
        }
        let saved = PhoneLinkIntentProjection(
            handle: handle, revision: checkpoint.committedRevision, snapshot: projection.snapshot,
            actions: actions, finishedPayload: terminal, finishedRecordId: recordId,
            nextMatchHandle: checkpoint.nextMatchHandle,
            nextMatchEpochMilliseconds: prior?.nextMatchEpochMilliseconds ?? projection.commits.first {
                guard $0.outcome == .accepted, case .nextMatch = $0.op.intent else { return false }
                return true
            }?.effectiveEpochMilliseconds
        )
        try intentProjectionStore.setOrThrow(JSONEncoder().encode(saved), forKey: intentProjectionKey(handle))
        if projection.isActiveMatch {
            displayIntentProjection(saved)
        }
    }

    private func displayIntentProjection(_ projection: PhoneLinkIntentProjection) {
        guard let current = activeSession, projection.handle == current.handle,
              projection.revision >= current.revision else { return }
        let setup = LinkedScoreboardSetup(
            gameType: current.gameType, maxSets: maxSets(for: projection.snapshot),
            initialSnapshot: projection.snapshot, detailedActions: projection.actions,
            participantNames: current.setup.participantNames, capabilities: current.setup.capabilities
        )
        activeSession?.setup = setup
        activeSession?.revision = projection.revision
        if var machine = sessionMachine {
            _ = machine.accept(handle: projection.handle, revision: projection.revision)
            if projection.snapshot.isFinished {
                _ = machine.markFinished(matchId: projection.handle.matchId)
            }
            sessionMachine = machine
            synchronizeActiveSessionFromStateMachine()
        }
        mergedDetailedActions = projection.actions
        finishedRecordId = projection.finishedRecordId
        latestRemoteSnapshot = .init(
            sessionId: projection.handle.sessionId,
            revision: projection.revision,
            matchGeneration: projection.handle.matchGeneration,
            snapshot: projection.snapshot,
            detailedActions: projection.actions
        )
    }

    private func storedIntentProjection(for handle: LinkedMatchHandle) throws -> PhoneLinkIntentProjection? {
        guard let data = try intentProjectionStore.dataOrThrow(forKey: intentProjectionKey(handle)) else { return nil }
        let projection = try JSONDecoder().decode(PhoneLinkIntentProjection.self, from: data)
        guard projection.handle == handle else { throw PhoneHostSequenceError.wrongHandle }
        return projection
    }

    private func intentProjectionKey(_ handle: LinkedMatchHandle) -> String {
        "intent-projection-\(handle.sessionId.uuidString)-\(handle.matchId.uuidString)-\(handle.matchGeneration)"
    }

    private func sendIntentFrame<Payload: Codable & Sendable>(
        _ kind: LinkMessageKind,
        payload: Payload,
        handle: LinkedMatchHandle,
        revision: UInt64,
        correlationId: UUID? = nil,
        sentAt: Int64? = nil
    ) {
        sequence += 1
        let frame = LinkEnvelope(
            correlationId: correlationId, sessionId: handle.sessionId, matchId: handle.matchId,
            matchGeneration: handle.matchGeneration, kind: kind, sender: .phone,
            senderSequence: sequence, sessionRevision: revision, sentAtEpochMilliseconds: sentAt ?? nowMs(), payload: payload
        )
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = await intentSessionEngine.sendReplayableFrame(
                    try JSONEncoder().encode(frame), kind: .intentFrame,
                    peerSupportsFileTransfer: transport.supportsFileTransfer
                )
                if let channel = result.steps.last, let error = result.failures[channel] {
                    lastErrorMessage = error
                }
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }
}
