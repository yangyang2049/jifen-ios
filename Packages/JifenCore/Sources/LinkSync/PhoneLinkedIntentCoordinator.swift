import Foundation
import LinkCore
import ScoreCore

/// The phone service owns one coordinator and its directory. Calls are
/// serialized on the main actor with the service's projection and routing.
@MainActor
public final class PhoneLinkedIntentCoordinator {
    public typealias Checkpoint = PhoneHostCheckpoint<LinkedReducerState>
    private typealias Journal = LinkOperationJournal<Checkpoint, LinkOperationCommitPayload>

    public struct Projection {
        public let checkpoint: Checkpoint
        public let snapshot: LinkedScoreboardSnapshot
        public let initialEpochMilliseconds: Int64
        public let commits: [LinkOperationCommitPayload]
        public let isActiveMatch: Bool
    }

    public enum Failure: Error, Equatable {
        case invalidInitialSnapshot
        case unknownMatch
        case inconsistentMatchSeed
        case inconsistentProjectionCursor
        case localOperationRequiresActiveMatch
        case unexpectedRollover
        case projectionInProgress
    }

    private struct Match {
        let seed: Checkpoint
        let journal: Journal
        var sequencer: PhoneHostSequencer<LinkedReducerState>
    }

    private let directoryURL: URL
    private let metadata: FileLinkDataStore
    private let adapter: LinkedReducerAdapter
    private let project: (Projection) throws -> Void
    private var active: Match?
    private var isProjecting = false

    /// Apply a projection idempotently by full handle, revision, and action
    /// ID. The callback may run again after a crash or partial write. Save a
    /// finished record by match ID, including when recovering an inactive
    /// match, and only update the visible scoreboard for an active projection.
    /// Send commits once the coordinating call returns. Resolve a recorded
    /// rollover after the call returns, using `Checkpoint.nextMatchHandle`.
    public init(
        directoryURL: URL,
        adapter: LinkedReducerAdapter,
        project: @escaping (Projection) throws -> Void
    ) {
        self.directoryURL = directoryURL
        self.adapter = adapter
        self.project = project
        self.metadata = FileLinkDataStore(directoryURL: directoryURL.appendingPathComponent("phone-match-metadata"))
    }

    public var activeCheckpoint: Checkpoint? { active?.sequencer.checkpoint }
    public var activeSeedCheckpoint: Checkpoint? { active?.seed }

    #if DEBUG
    public func diagnosticSummary() throws -> String? {
        guard let active else { return nil }
        let checkpoint = active.sequencer.checkpoint
        let revision = checkpoint.committedRevision
        let hash = try LinkStateHash.snapshot(adapter.snapshot(checkpoint.state))
        let outcomes = try active.journal.results(after: revision > 20 ? revision - 20 : 0)
        let recent = outcomes.map { "\($0.committedRevision)=\($0.rejectionReason ?? $0.outcome.rawValue)" }
        return "match=\(checkpoint.handle.matchId) revision=\(revision) hash=\(String(hash, radix: 16)) pending=0 outcomes=\(recent)"
    }
    #endif

    /// Save the seed once before accepting operations. A matching durable
    /// match always restores its own seed and latest journal head.
    @discardableResult
    public func activate(
        handle: LinkedMatchHandle,
        gameType: GameType,
        initialSnapshot: LinkedScoreboardSnapshot,
        initialEpochMilliseconds: Int64
    ) throws -> Checkpoint {
        try requireProjectionIdle()
        try requireAllowedActivation(handle)
        if let existing = try knownMatch(handle) {
            guard existing.seed.state.gameType == gameType else { throw Failure.inconsistentMatchSeed }
            return try installActive(existing)
        }
        guard let state = adapter.state(gameType: gameType, from: initialSnapshot),
              adapter.snapshot(state) == initialSnapshot else { throw Failure.invalidInitialSnapshot }
        let seed = Checkpoint(handle: handle, state: state, initialEpochMilliseconds: initialEpochMilliseconds)
        try metadata.setOrThrow(JSONEncoder().encode(seed), forKey: seedKey(handle))
        return try installActive(openMatch(seed: seed))
    }

    /// The app supplies its persisted active handle. The corresponding match
    /// seed and journal provide the reducer state and sequence after restart.
    @discardableResult
    public func recoverActiveMatch(handle: LinkedMatchHandle) throws -> Checkpoint {
        try requireProjectionIdle()
        try requireAllowedActivation(handle)
        return try installActive(match(for: handle))
    }

    public func deactivate(handle: LinkedMatchHandle) {
        if active?.seed.handle == handle { active = nil }
    }

    /// Reuse the op ID and original time when retrying a local submission.
    /// A surviving journal receipt also repairs any unfinished projection.
    public func submitLocal(
        _ intent: LinkedScoreboardIntent,
        handle: LinkedMatchHandle,
        opId: UUID,
        createdAtEpochMilliseconds: Int64,
        phoneClockReferenceEpochMilliseconds: Int64
    ) throws -> LinkOperationCommitPayload {
        try requireProjectionIdle()
        var match = try match(for: handle)

        if let prior = try match.journal.outcome(for: opId) {
            let operation = prior.op
            guard operation.origin == .phone, operation.intent == intent,
                  operation.createdAtEpochMilliseconds == createdAtEpochMilliseconds else {
                throw PhoneHostSequenceError.conflictingOperationID
            }
            try repairProjection(match)
            return prior
        }

        guard active?.seed.handle == handle else { throw Failure.localOperationRequiresActiveMatch }
        let current = match.sequencer.checkpoint
        guard current.phoneClientSeq < UInt64.max else { throw PhoneHostSequenceError.sequenceExhausted }
        let operation = LinkOperation(
            opId: opId,
            handle: handle,
            origin: .phone,
            clientSeq: current.phoneClientSeq + 1,
            baseRevision: current.committedRevision,
            createdAtEpochMilliseconds: createdAtEpochMilliseconds,
            intent: intent
        )
        return try process(operation, from: .phone, at: phoneClockReferenceEpochMilliseconds, match: &match)
    }

    /// Transport calls this for authenticated Watch submissions, including
    /// retransmissions against a previous full handle.
    public func receiveWatchOperation(
        _ operation: LinkOperation,
        phoneClockReferenceEpochMilliseconds: Int64
    ) throws -> LinkOperationCommitPayload {
        try requireProjectionIdle()
        guard operation.origin == .watch else { throw PhoneHostSequenceError.wrongOrigin }
        var match = try match(for: operation.handle)
        return try process(operation, from: .watch, at: phoneClockReferenceEpochMilliseconds, match: &match)
    }

    /// Context publications may omit results. A repair requests outstanding
    /// operation IDs or a confirmed revision so the reply reconciles that outbox.
    public func checkpoint(
        for handle: LinkedMatchHandle,
        watchOperationIds: [UUID] = [],
        afterConfirmedRevision: UInt64? = nil
    ) throws -> LinkAuthoritativeCheckpoint {
        try requireProjectionIdle()
        let match = try match(for: handle)
        try repairProjection(match)
        var outcomes = [UUID: LinkOperationCommitPayload]()
        if let revision = afterConfirmedRevision {
            for result in try match.journal.results(after: revision) where result.op.origin == .watch {
                outcomes[result.op.opId] = result
            }
        }
        for id in watchOperationIds {
            if let result = try match.journal.outcome(for: id), result.op.origin == .watch {
                outcomes[id] = result
            }
        }
        return try match.sequencer.authoritativeCheckpoint(watchResults: Array(outcomes.values))
    }

    private func process(
        _ operation: LinkOperation,
        from origin: LinkPeer,
        at phoneClockReference: Int64,
        match: inout Match
    ) throws -> LinkOperationCommitPayload {
        let isActive = active?.seed.handle == operation.handle
        let journal = match.journal
        let result = try match.sequencer.process(
            operation,
            from: origin,
            phoneClockReferenceEpochMilliseconds: phoneClockReference,
            isActiveMatch: isActive,
            lookup: journal.outcome(for:),
            persist: journal.append(checkpoint:outcome:)
        )
        if isActive { active = match }
        try repairProjection(match)
        return result
    }

    private func repairProjection(_ match: Match) throws {
        let checkpoint = match.sequencer.checkpoint
        let key = projectionKey(checkpoint.handle)
        let cursor = try metadata.dataOrThrow(forKey: key).map {
            try JSONDecoder().decode(UInt64.self, from: $0)
        } ?? 0
        guard cursor <= checkpoint.committedRevision else { throw Failure.inconsistentProjectionCursor }
        guard cursor < checkpoint.committedRevision else { return }

        let projection = Projection(
            checkpoint: checkpoint,
            snapshot: adapter.snapshot(checkpoint.state),
            initialEpochMilliseconds: match.seed.effectiveEpochMilliseconds,
            commits: try match.journal.results(after: cursor),
            isActiveMatch: active?.seed.handle == checkpoint.handle
        )
        isProjecting = true
        defer { isProjecting = false }
        try project(projection)
        try metadata.setOrThrow(JSONEncoder().encode(checkpoint.committedRevision), forKey: key)
    }

    private func requireProjectionIdle() throws {
        if isProjecting { throw Failure.projectionInProgress }
    }

    private func requireAllowedActivation(_ handle: LinkedMatchHandle) throws {
        guard let current = activeCheckpoint, current.handle != handle, current.handle.sessionId == handle.sessionId else { return }
        guard current.nextMatchHandle == handle else { throw Failure.unexpectedRollover }
    }

    private func installActive(_ match: Match) throws -> Checkpoint {
        active = match
        try repairProjection(match)
        return match.sequencer.checkpoint
    }

    private func match(for handle: LinkedMatchHandle) throws -> Match {
        guard let match = try knownMatch(handle) else { throw Failure.unknownMatch }
        return match
    }

    private func knownMatch(_ handle: LinkedMatchHandle) throws -> Match? {
        if let active, active.seed.handle == handle { return active }
        guard let data = try metadata.dataOrThrow(forKey: seedKey(handle)) else { return nil }
        let seed = try JSONDecoder().decode(Checkpoint.self, from: data)
        guard seed.handle == handle, seed.committedRevision == 0 else { throw Failure.inconsistentMatchSeed }
        return try openMatch(seed: seed)
    }

    private func openMatch(seed: Checkpoint) throws -> Match {
        let journal = try Journal(directoryURL: directoryURL, handle: seed.handle)
        let checkpoint = journal.latestCheckpoint ?? seed
        guard checkpoint.state.gameType == seed.state.gameType else { throw Failure.inconsistentMatchSeed }
        let sequencer = PhoneHostSequencer(
            checkpoint: checkpoint,
            snapshot: adapter.snapshot,
            isFinished: adapter.isFinished,
            transition: adapter.transition
        )
        return Match(seed: seed, journal: journal, sequencer: sequencer)
    }

    private func seedKey(_ handle: LinkedMatchHandle) -> String { "seed-\(matchKey(handle))" }
    private func projectionKey(_ handle: LinkedMatchHandle) -> String { "projection-\(matchKey(handle))" }

    private func matchKey(_ handle: LinkedMatchHandle) -> String {
        "\(handle.sessionId.uuidString)-\(handle.matchId.uuidString)-\(handle.matchGeneration)"
    }
}
