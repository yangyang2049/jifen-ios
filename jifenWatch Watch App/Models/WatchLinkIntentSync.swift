import Foundation
import LinkCore
import LinkSync
import Observation
import RecordCore
import ScoreCore

struct WatchLinkedIntentUpdate: Equatable {
    let handle: LinkedMatchHandle
    let committedRevision: UInt64
    var presentationSequence: UInt64
    let startEpochMilliseconds: Int64
    let optimisticEpochMilliseconds: Int64
    let latestUndoableOperationId: UUID?
    let confirmedSnapshot: LinkedScoreboardSnapshot
    let displayedSnapshot: LinkedScoreboardSnapshot
    let detailedActions: [DetailedScoreAction]
    let isPendingFinish: Bool
    let excludedScoringOperationCount: Int
    let savedRecordID: String?
}

/// Connects the Watch transport to one durable replay queue per match.
@MainActor
@Observable
final class WatchLinkIntentSync {
    enum Failure: Error {
        case invalidInitialSnapshot
        case missingMatch
        case inconsistentMatchSeed
        case invalidFinishedPayload
        case recordSaveFailed
    }

    private struct MatchMetadata: Codable {
        let handle: LinkedMatchHandle
        let gameType: ScoreCore.GameType
        let startEpochMilliseconds: Int64
        let participantNames: [String]
        let peerSupportsFileTransfer: Bool
    }

    private struct Match {
        let metadata: MatchMetadata
        let coordinator: WatchLinkedIntentCoordinator
    }

    private struct FinishedProjection: Codable {
        let payload: LinkMatchFinishedPayload
        var saved: Bool
    }

    @ObservationIgnored private weak var service: WatchLinkService?
    @ObservationIgnored private let store: FileLinkDataStore
    @ObservationIgnored private var activeMatch: Match?
    @ObservationIgnored private var sendingHandles: Set<LinkedMatchHandle> = []
    @ObservationIgnored private var announcedNextMatches: [LinkedMatchHandle: LinkedMatchHandle] = [:]
    @ObservationIgnored private var presentationSequence: UInt64 = 0
    #if DEBUG
    @ObservationIgnored private var diagnosticHandle: LinkedMatchHandle?
    @ObservationIgnored private var diagnosticOutcomes: [UInt64: String] = [:]
    #endif

    /// Called after matchStarted has durably installed the new match seed.
    @ObservationIgnored var onMatchStarted: ((LinkedMatchHandle, LinkedScoreboardSetup) throws -> Void)?
    private(set) var update: WatchLinkedIntentUpdate?
    private(set) var retiredFinishUpdate: WatchLinkedIntentUpdate?

    private let adapter = LinkedReducerAdapter()

    init(service: WatchLinkService, store: FileLinkDataStore = WatchStorageContainer.shared.linkDataStore) {
        self.service = service
        self.store = store
    }

    /// The seed timestamp is the phone's initial match timestamp from the handshake.
    func activate(
        handle: LinkedMatchHandle,
        gameType: ScoreCore.GameType,
        initialSnapshot: LinkedScoreboardSnapshot,
        initialEpochMilliseconds: Int64,
        participantNames: [String] = [],
        initialActions: [DetailedScoreAction] = [],
        peerSupportsFileTransfer: Bool = false
    ) throws {
        if let current = try match(for: handle) {
            guard current.metadata.gameType == gameType else { throw Failure.inconsistentMatchSeed }
            try install(current)
            return
        }
        guard let state = adapter.state(gameType: gameType, from: initialSnapshot),
              adapter.snapshot(state) == initialSnapshot else { throw Failure.invalidInitialSnapshot }

        let seedKey = key("seed", handle)
        let metadata: MatchMetadata
        if let stored = try read(MatchMetadata.self, key: seedKey) {
            guard stored.handle == handle, stored.gameType == gameType else { throw Failure.inconsistentMatchSeed }
            metadata = stored
        } else {
            metadata = MatchMetadata(
                handle: handle, gameType: gameType,
                startEpochMilliseconds: initialEpochMilliseconds, participantNames: participantNames,
                peerSupportsFileTransfer: peerSupportsFileTransfer
            )
            try write(metadata, key: seedKey)
        }
        let coordinator = try WatchLinkedIntentCoordinator(
            handle: handle, initialState: state, initialEpochMilliseconds: metadata.startEpochMilliseconds,
            initialActions: initialActions, adapter: adapter, store: store
        )
        try install(Match(metadata: metadata, coordinator: coordinator))
    }

    @discardableResult
    func restoreActiveMatch(handle: LinkedMatchHandle) throws -> Bool {
        guard let match = try match(for: handle) else { return false }
        try install(match)
        return true
    }

    func deactivate(handle: LinkedMatchHandle, persistRetirement: () throws -> Void = {}) throws {
        if let activeMatch, activeMatch.metadata.handle == handle {
            try retainIfNeeded(activeMatch, recoverPhoneFinish: false)
        }
        try persistRetirement()
        guard activeMatch?.metadata.handle == handle else { return }
        activeMatch = nil
        update = nil
    }

    func confirmedActions(for handle: LinkedMatchHandle) -> [DetailedScoreAction] {
        guard activeMatch?.metadata.handle == handle else { return [] }
        return activeMatch?.coordinator.confirmedActions ?? []
    }

    func restoredContext(for pointer: WatchActiveIntentContext) throws -> WatchLinkResumeContext? {
        guard let match = try match(for: pointer.handle), match.metadata.gameType == pointer.setup.gameType else {
            return nil
        }
        let snapshot = match.coordinator.confirmedSnapshot
        let setup = LinkedScoreboardSetup(
            gameType: pointer.setup.gameType, maxSets: pointer.setup.maxSets,
            initialSnapshot: snapshot, detailedActions: match.coordinator.confirmedActions,
            participantNames: pointer.setup.participantNames, capabilities: pointer.setup.capabilities
        )
        return WatchLinkResumeContext(
            handle: pointer.handle, setup: setup, revision: match.coordinator.checkpoint.committedRevision,
            latestAuthoritativeSnapshot: snapshot, detailedActions: match.coordinator.confirmedActions,
            completedMatchIds: snapshot.isFinished ? [pointer.handle.matchId] : [],
            pendingTerminalMessageIds: [], negotiatedPeerCapabilities: pointer.capabilities
        )
    }

    var hasDurableRetryWork: Bool {
        if let activeMatch, !activeMatch.coordinator.pendingOperations.isEmpty
            || (activeMatch.coordinator.confirmedSnapshot.isFinished && update?.savedRecordID == nil) {
            return true
        }
        do {
            return try !retainedHandles().isEmpty
        } catch {
            report(error)
            return false
        }
    }

    func hasPendingOperations(for handle: LinkedMatchHandle) -> Bool {
        do {
            return try match(for: handle)?.coordinator.pendingOperations.isEmpty == false
        } catch {
            report(error)
            return true
        }
    }

    func replayPending(handle: LinkedMatchHandle) {
        sendPending(handle: handle)
    }

    @discardableResult
    func submit(
        _ intent: LinkedScoreboardIntent,
        handle: LinkedMatchHandle,
        createdAtEpochMilliseconds: Int64,
        opId: UUID = UUID()
    ) throws -> LinkOperation {
        let match = try requireActive(handle)
        let operation = try match.coordinator.enqueue(
            intent, opId: opId, createdAtEpochMilliseconds: createdAtEpochMilliseconds
        )
        publish(match, savedRecordID: update?.savedRecordID)
        sendPending(handle: handle)
        return operation
    }

    @discardableResult
    func undo(
        handle: LinkedMatchHandle, targetOpId: UUID? = nil, createdAtEpochMilliseconds: Int64
    ) throws -> Bool {
        let match = try requireActive(handle)
        guard let target = targetOpId ?? undoTarget(in: match.coordinator.displayedState) else { return false }
        if try match.coordinator.cancelUnsentScore(target) {
            publish(match, savedRecordID: update?.savedRecordID)
        } else {
            try submit(.undo(targetOpId: target), handle: handle, createdAtEpochMilliseconds: createdAtEpochMilliseconds)
        }
        return true
    }

    /// Replay the current match and any matches replaced with work still pending.
    func retryPendingAfterReconnect() {
        do {
            var handles = try retainedHandles()
            if let handle = activeMatch?.metadata.handle { handles.insert(handle) }
            for handle in handles {
                do {
                    if let match = try match(for: handle) {
                        let savedRecordID = try projectFinishedRecord(match)
                        publish(match, savedRecordID: savedRecordID)
                        try retireIfComplete(match, savedRecordID: savedRecordID)
                    }
                } catch {
                    report(error)
                }
                requestRecovery(handle: handle)
                sendPending(handle: handle)
            }
        } catch {
            report(error)
        }
    }

    func requestRecovery(handle: LinkedMatchHandle) {
        guard let service, service.transport.isReachable else { return }
        do {
            guard let match = try match(for: handle) else { return }
            let coordinator = match.coordinator
            let request = LinkIntentRecoveryRequest(
                confirmedRevision: coordinator.checkpoint.committedRevision,
                pendingOperationIds: coordinator.pendingOperations.map(\.operation.opId)
            )
            let frame = envelope(
                kind: .resyncRequest, handle: handle, revision: request.confirmedRevision,
                payload: request, using: service
            )
            let canTransfer = match.metadata.peerSupportsFileTransfer
            Task { [weak self, weak service] in
                guard let service else { return }
                do {
                    let data = try JSONEncoder().encode(frame)
                    try await service.sendReplayableIntentFrame(data, peerSupportsFileTransfer: canTransfer)
                } catch {
                    self?.report(error)
                }
            }
        } catch {
            report(error)
        }
    }

    /// Entry for realtime, application-context and intent-file deliveries.
    @discardableResult
    func handleIncoming(_ data: Data, head: LinkEnvelopeHead) -> Bool {
        guard head.sender == .phone, head.protocolVersion == LinkProtocol.currentVersion else { return false }
        let decoder = JSONDecoder()
        do {
            switch head.kind {
            case .intentCommit:
                let frame = try decoder.decode(LinkEnvelope<LinkOperationCommitPayload>.self, from: data)
                guard frame.handle == frame.payload.op.handle,
                      frame.sessionRevision == frame.payload.committedRevision,
                      let match = try match(for: frame.handle) else { return false }
                try receiveCommit(frame, match: match)
            case .intentCheckpoint:
                let frame = try decoder.decode(LinkEnvelope<LinkIntentRecoveryPayload>.self, from: data)
                guard frame.handle == frame.payload.checkpoint.handle,
                      frame.sessionRevision == frame.payload.checkpoint.committedRevision,
                      let match = try match(for: frame.handle) else { return false }
                try receiveCheckpoint(frame, match: match)
            case .resyncRequest:
                let frame = try decoder.decode(LinkEnvelope<EmptyLinkPayload>.self, from: data)
                guard try match(for: frame.handle) != nil else { return false }
                requestRecovery(handle: frame.handle)
                sendPending(handle: frame.handle)
            case .matchStarted:
                let frame = try decoder.decode(LinkEnvelope<LinkedScoreboardSetup>.self, from: data)
                return try receiveMatchStart(frame)
            default:
                return false
            }
            return true
        } catch {
            report(error)
            return true
        }
    }

    private func receiveCommit(_ frame: LinkEnvelope<LinkOperationCommitPayload>, match: Match) throws {
        let commit = frame.payload
        switch try match.coordinator.receive(commit) {
        case .wrongHandle:
            return
        case .needsResync:
            requestRecovery(handle: frame.handle)
        case .advanced, .alreadyConfirmed:
            #if DEBUG
            rememberOutcomes([LinkProcessedOperation(commit: commit)], for: frame.handle)
            #endif
            if commit.outcome == .accepted, case .nextMatch(let matchId, let generation) = commit.op.intent {
                announceNextMatch(
                    LinkedMatchHandle(sessionId: frame.handle.sessionId, matchId: matchId, matchGeneration: generation),
                    after: frame.handle
                )
            }
            let finish = finishedPayload(for: commit, match: match)
            try projectAndAcknowledge(frame, match: match, authority: finish)
        }
    }

    private func receiveCheckpoint(_ frame: LinkEnvelope<LinkIntentRecoveryPayload>, match: Match) throws {
        let payload = frame.payload
        if let finished = payload.finishedPayload {
            guard finished.snapshot.isFinished, finished.snapshot == payload.checkpoint.snapshot,
                  finished.recordId == recordID(frame.handle) else { throw Failure.invalidFinishedPayload }
        }
        switch try match.coordinator.receive(payload.checkpoint, confirmedActions: payload.detailedActions) {
        case .wrongHandle:
            return
        case .needsResync:
            requestRecovery(handle: frame.handle)
        case .advanced, .alreadyConfirmed:
            #if DEBUG
            rememberOutcomes(payload.checkpoint.watchResults, for: frame.handle)
            #endif
            if let next = payload.nextMatchHandle { announceNextMatch(next, after: frame.handle) }
            let authoritativeFinish = payload.finishedPayload.flatMap { terminal -> LinkMatchFinishedPayload? in
                guard terminal.snapshot == match.coordinator.confirmedSnapshot else { return nil }
                var complete = terminal
                complete.detailedActions = match.coordinator.confirmedActions
                return complete
            }
            try projectAndAcknowledge(frame, match: match, authority: authoritativeFinish)
        }
    }

    private func projectAndAcknowledge<Payload: Codable & Sendable>(
        _ frame: LinkEnvelope<Payload>, match: Match, authority: LinkMatchFinishedPayload? = nil
    ) throws {
        defer { sendPending(handle: frame.handle) }
        do {
            let savedRecordID = try projectFinishedRecord(match, authority: authority)
            publish(match, savedRecordID: savedRecordID)
            if match.coordinator.confirmedSnapshot.isFinished, savedRecordID == nil {
                if frame.kind == .intentCommit { requestRecovery(handle: frame.handle) }
                return
            }
            try retireIfComplete(match, savedRecordID: savedRecordID)
            acknowledge(frame)
        } catch {
            publish(match, savedRecordID: nil)
            throw error
        }
    }

    private func receiveMatchStart(_ frame: LinkEnvelope<LinkedScoreboardSetup>) throws -> Bool {
        guard let current = activeMatch, let service,
              service.negotiatedPeerCapabilities.contains(.sharedIntentSync),
              frame.sessionId == current.metadata.handle.sessionId, frame.sessionRevision == 0,
              frame.payload.gameType == current.metadata.gameType,
              WatchLinkService.isValidLinkedSetup(frame.payload),
              let snapshot = frame.payload.initialSnapshot else { return false }

        let previous = current.metadata.handle
        if frame.handle == previous { return true }
        guard frame.matchGeneration > previous.matchGeneration, frame.matchId != previous.matchId else { return false }
        if let expected = announcedNextMatches[previous],
           frame.matchGeneration == expected.matchGeneration, frame.handle != expected { return false }

        do {
            try activate(
                handle: frame.handle, gameType: frame.payload.gameType, initialSnapshot: snapshot,
                initialEpochMilliseconds: frame.sentAtEpochMilliseconds,
                participantNames: frame.payload.participantNames, initialActions: frame.payload.detailedActions,
                peerSupportsFileTransfer: service.peerSupportsFileTransfer
            )
            try onMatchStarted?(frame.handle, frame.payload)
        } catch {
            _ = try? restoreActiveMatch(handle: previous)
            throw error
        }
        requestRecovery(handle: previous)
        sendPending(handle: previous)
        return true
    }

    private func announceNextMatch(_ next: LinkedMatchHandle, after previous: LinkedMatchHandle) {
        guard next.sessionId == previous.sessionId, next.matchId != previous.matchId,
              previous.matchGeneration < UInt64.max,
              next.matchGeneration == previous.matchGeneration + 1 else { return }
        announcedNextMatches[previous] = next
    }

    private func sendPending(handle: LinkedMatchHandle) {
        guard service?.transport.isReachable == true, sendingHandles.insert(handle).inserted else { return }
        Task { [weak self] in
            guard let self else { return }
            defer { sendingHandles.remove(handle) }
            do {
                guard let service else { return }
                var attempted: Set<UUID> = []
                while service.transport.isReachable {
                    guard let match = try match(for: handle),
                          let pending = match.coordinator.pendingOperations.first(where: {
                              !attempted.contains($0.operation.opId)
                          }) else { return }
                    let id = pending.operation.opId
                    attempted.insert(id)
                    guard let operation = try match.coordinator.markSent(id) else { continue }
                    let frame = envelope(
                        kind: .intentSubmit, handle: handle, revision: operation.baseRevision,
                        payload: operation, messageId: operation.opId, using: service
                    )
                    let data = try JSONEncoder().encode(frame)
                    let queued = try await service.sendReplayableIntentFrame(
                        data, peerSupportsFileTransfer: match.metadata.peerSupportsFileTransfer
                    )
                    // A durable delivery on a different channel must be confirmed
                    // before later sequences resume realtime delivery.
                    if queued { return }
                }
            } catch {
                report(error)
            }
        }
    }

    private func acknowledge<Payload: Codable & Sendable>(_ frame: LinkEnvelope<Payload>) {
        guard let service else { return }
        let ack = envelope(
            kind: .acknowledgement, handle: frame.handle, revision: frame.sessionRevision,
            payload: LinkAcknowledgementPayload(
                acknowledgedMessageId: frame.messageId, acknowledgedRevision: frame.sessionRevision
            ),
            correlationId: frame.messageId, using: service
        )
        Task { [weak self, weak service] in
            guard let service, service.transport.status.isActivated else { return }
            do {
                let data = try JSONEncoder().encode(ack)
                try await service.sendReplayableIntentFrame(data, peerSupportsFileTransfer: false)
            } catch {
                self?.report(error)
            }
        }
    }

    private func envelope<Payload: Codable & Sendable>(
        kind: LinkMessageKind, handle: LinkedMatchHandle, revision: UInt64,
        payload: Payload, messageId: UUID = UUID(), correlationId: UUID? = nil,
        using service: WatchLinkService
    ) -> LinkEnvelope<Payload> {
        service.sequence += 1
        return LinkEnvelope(
            messageId: messageId, correlationId: correlationId,
            sessionId: handle.sessionId, matchId: handle.matchId, matchGeneration: handle.matchGeneration,
            kind: kind, sender: .watch, senderSequence: service.sequence, sessionRevision: revision,
            sentAtEpochMilliseconds: service.nowMs(), payload: payload
        )
    }

    private func projectFinishedRecord(
        _ match: Match, authority: LinkMatchFinishedPayload? = nil
    ) throws -> String? {
        let coordinator = match.coordinator
        guard coordinator.confirmedSnapshot.isFinished else { return nil }
        let handle = match.metadata.handle
        let id = recordID(handle)
        let storageKey = key("finish", handle)
        var projection: FinishedProjection
        if let stored = try read(FinishedProjection.self, key: storageKey) {
            guard stored.payload.recordId == id, stored.payload.snapshot == coordinator.confirmedSnapshot else {
                throw Failure.invalidFinishedPayload
            }
            projection = stored
        } else {
            // A restored checkpoint can be ahead of the record write. Ask
            // the phone for the original finish before projecting that record.
            guard let authority else { return nil }
            projection = FinishedProjection(payload: authority, saved: false)
            // Keep the first confirmed finish across an interruption or failed record write.
            try write(projection, key: storageKey)
        }
        if !projection.saved {
            guard let service,
                  service.recordSink.ingest(
                      payload: projection.payload, gameType: match.metadata.gameType,
                      matchId: handle.matchId, syncState: .sent
                  ) == id else { throw Failure.recordSaveFailed }
            projection.saved = true
            try write(projection, key: storageKey)
        }
        return id
    }

    private func finishedPayload(
        for commit: LinkOperationCommitPayload, match: Match
    ) -> LinkMatchFinishedPayload? {
        if case .nextMatch = commit.op.intent { return nil }
        let coordinator = match.coordinator
        guard commit.outcome == .accepted, let snapshot = commit.authoritativeSnapshot,
              snapshot.isFinished, snapshot == coordinator.confirmedSnapshot else { return nil }

        let start = match.metadata.startEpochMilliseconds
        let end = commit.effectiveEpochMilliseconds
        let actions = coordinator.confirmedActions
        return LinkMatchFinishedPayload(
            snapshot: snapshot,
            recordId: recordID(match.metadata.handle), manualEnd: commit.op.intent == .finish,
            startTimeEpochMilliseconds: start, endTimeEpochMilliseconds: end,
            durationSeconds: max(0, (Double(end) - Double(start)) / 1_000),
            totalScoreChanges: actions.filter { $0.type != .undo }.count,
            detailedActions: actions, participantNames: match.metadata.participantNames
        )
    }

    private func install(_ match: Match) throws {
        if let activeMatch, activeMatch.metadata.handle != match.metadata.handle {
            try retainIfNeeded(
                activeMatch, recoverPhoneFinish: activeMatch.metadata.handle.sessionId == match.metadata.handle.sessionId
            )
        }
        activeMatch = match
        do {
            let savedRecordID = try projectFinishedRecord(match)
            publish(match, savedRecordID: savedRecordID)
        } catch {
            publish(match, savedRecordID: nil)
            throw error
        }
    }

    private func publish(_ match: Match, savedRecordID: String?) {
        let handle = match.metadata.handle
        let isActive = activeMatch?.metadata.handle == handle
        let coordinator = match.coordinator
        guard isActive || coordinator.confirmedSnapshot.isFinished else { return }
        let previous = isActive ? update : retiredFinishUpdate
        let displayed = coordinator.displayedState
        let optimisticTime = coordinator.pendingOperations.reduce(coordinator.checkpoint.effectiveEpochMilliseconds) {
            max($0, $1.operation.createdAtEpochMilliseconds)
        }
        var projection = WatchLinkedIntentUpdate(
            handle: handle, committedRevision: coordinator.checkpoint.committedRevision,
            presentationSequence: previous?.presentationSequence ?? presentationSequence,
            startEpochMilliseconds: match.metadata.startEpochMilliseconds, optimisticEpochMilliseconds: optimisticTime,
            latestUndoableOperationId: undoTarget(in: displayed),
            confirmedSnapshot: coordinator.confirmedSnapshot, displayedSnapshot: adapter.snapshot(displayed),
            detailedActions: coordinator.displayedActions, isPendingFinish: coordinator.isPendingFinish,
            excludedScoringOperationCount: coordinator.excludedScoringOperationCount, savedRecordID: savedRecordID
        )
        guard projection != previous else { return }
        presentationSequence &+= 1
        projection.presentationSequence = presentationSequence
        if isActive {
            update = projection
            service?.applyConfirmedIntentProjection(projection, actions: coordinator.confirmedActions)
        } else {
            retiredFinishUpdate = projection
        }
        service?.scheduleRetryIfNeeded()
    }

    private func undoTarget(in state: LinkedReducerState) -> UUID? {
        if case .football = state.current { return state.latestFootballScoreUndoTargetId }
        return state.latestUndoableOperationId
    }

    #if DEBUG
    func diagnosticSummary() -> String? {
        guard let match = activeMatch,
              let hash = try? LinkStateHash.snapshot(match.coordinator.confirmedSnapshot) else { return nil }
        let handle = match.metadata.handle
        let revision = match.coordinator.checkpoint.committedRevision
        let recent = diagnosticHandle == handle
            ? diagnosticOutcomes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
            : []
        return "match=\(handle.matchId) revision=\(revision) hash=\(String(hash, radix: 16)) pending=\(match.coordinator.pendingOperations.count) outcomes=\(recent)"
    }

    private func rememberOutcomes(_ outcomes: [LinkProcessedOperation], for handle: LinkedMatchHandle) {
        guard activeMatch?.metadata.handle == handle else { return }
        if diagnosticHandle != handle {
            diagnosticHandle = handle
            diagnosticOutcomes.removeAll()
        }
        for outcome in outcomes {
            diagnosticOutcomes[outcome.committedRevision] = outcome.rejectionReason ?? outcome.outcome.rawValue
        }
        for older in diagnosticOutcomes.keys.sorted().dropLast(20) {
            diagnosticOutcomes.removeValue(forKey: older)
        }
    }
    #endif

    private func retainIfNeeded(_ match: Match, recoverPhoneFinish: Bool) throws {
        let coordinator = match.coordinator
        let handle = match.metadata.handle
        let finish = try read(FinishedProjection.self, key: key("finish", handle))
        // Recover the old handle even if the Watch has no queue and the phone
        // might have finished while it was offline.
        let mayHaveUnprojectedFinish = (recoverPhoneFinish || coordinator.confirmedSnapshot.isFinished)
            && finish?.saved != true
        guard !coordinator.pendingOperations.isEmpty || mayHaveUnprojectedFinish else { return }
        var retained = try retainedHandles()
        if retained.insert(handle).inserted { try write(retained, key: "watch-intent-retained") }
    }

    private func retireIfComplete(_ match: Match, savedRecordID: String?) throws {
        let handle = match.metadata.handle
        guard handle != activeMatch?.metadata.handle,
              match.coordinator.pendingOperations.isEmpty, savedRecordID != nil else { return }
        var retained = try retainedHandles()
        if retained.remove(handle) != nil { try write(retained, key: "watch-intent-retained") }
    }

    private func retainedHandles() throws -> Set<LinkedMatchHandle> {
        try read(Set<LinkedMatchHandle>.self, key: "watch-intent-retained") ?? []
    }

    private func requireActive(_ handle: LinkedMatchHandle) throws -> Match {
        guard let activeMatch, activeMatch.metadata.handle == handle, service?.canEditLinkedMatch == true else {
            throw Failure.missingMatch
        }
        return activeMatch
    }

    private func match(for handle: LinkedMatchHandle) throws -> Match? {
        if let activeMatch, activeMatch.metadata.handle == handle { return activeMatch }
        guard let metadata = try read(MatchMetadata.self, key: key("seed", handle)) else { return nil }
        guard metadata.handle == handle else { throw Failure.inconsistentMatchSeed }
        guard let coordinator = try WatchLinkedIntentCoordinator.restore(handle: handle, adapter: adapter, store: store) else {
            return nil
        }
        guard metadata.gameType == coordinator.checkpoint.confirmedState.gameType else { throw Failure.inconsistentMatchSeed }
        return Match(metadata: metadata, coordinator: coordinator)
    }

    private func key(_ category: String, _ handle: LinkedMatchHandle) -> String {
        "watch-intent-\(category)-\(handle.sessionId.uuidString)-\(handle.matchId.uuidString)-\(handle.matchGeneration)"
    }

    private func recordID(_ handle: LinkedMatchHandle) -> String {
        "w_\(handle.matchId.uuidString)"
    }

    private func read<Value: Decodable>(_ type: Value.Type, key: String) throws -> Value? {
        guard let data = try store.dataOrThrow(forKey: key) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    private func write<Value: Encodable>(_ value: Value, key: String) throws {
        try store.setOrThrow(JSONEncoder().encode(value), forKey: key)
    }

    func report(_ error: Error) {
        if let queueError = error as? WatchReplayQueueError,
           queueError == .queueFull || queueError == .queueTooOld {
            service?.lastLinkErrorMessage = NSLocalizedString(
                "linked_score_reconnect_to_continue",
                value: "Reconnect to your iPhone to continue scoring.",
                comment: "The queue has reached its offline limit"
            )
            return
        }
        service?.lastLinkErrorMessage = error.localizedDescription
    }
}
