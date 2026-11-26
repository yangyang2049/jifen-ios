import Foundation
import LinkCore
import RecordCore

/// A complete, per-match durable cursor. `State` is a value containing any
/// reducer history necessary to apply or undo another operation after restart.
public struct PhoneHostCheckpoint<State: Sendable>: Sendable {
    public let handle: LinkedMatchHandle
    public let state: State
    public let committedRevision: UInt64
    public let phoneClientSeq: UInt64
    public let watchClientSeq: UInt64
    public let effectiveEpochMilliseconds: Int64
    public let phoneClockReferenceEpochMilliseconds: Int64
    /// A recorded rollover can be completed idempotently after restart.
    public let nextMatchHandle: LinkedMatchHandle?

    public init(handle: LinkedMatchHandle, state: State, initialEpochMilliseconds: Int64) {
        self.init(
            handle: handle,
            state: state,
            committedRevision: 0,
            phoneClientSeq: 0,
            watchClientSeq: 0,
            effectiveEpochMilliseconds: initialEpochMilliseconds,
            phoneClockReferenceEpochMilliseconds: initialEpochMilliseconds,
            nextMatchHandle: nil
        )
    }

    fileprivate init(
        handle: LinkedMatchHandle,
        state: State,
        committedRevision: UInt64,
        phoneClientSeq: UInt64,
        watchClientSeq: UInt64,
        effectiveEpochMilliseconds: Int64,
        phoneClockReferenceEpochMilliseconds: Int64,
        nextMatchHandle: LinkedMatchHandle?
    ) {
        self.handle = handle
        self.state = state
        self.committedRevision = committedRevision
        self.phoneClientSeq = phoneClientSeq
        self.watchClientSeq = watchClientSeq
        self.effectiveEpochMilliseconds = effectiveEpochMilliseconds
        self.phoneClockReferenceEpochMilliseconds = phoneClockReferenceEpochMilliseconds
        self.nextMatchHandle = nextMatchHandle
    }
}

extension PhoneHostCheckpoint: Codable where State: Codable {}
extension PhoneHostCheckpoint: Equatable where State: Equatable {}
extension PhoneHostCheckpoint: LinkOperationJournalCheckpoint where State: Codable {}

public enum PhoneHostSequenceError: Error, Equatable {
    case wrongHandle
    case wrongOrigin
    case conflictingOperationID
    case alreadyProcessedSequence
    case missingSequence(expected: UInt64)
    case sequenceExhausted
}

public struct PhoneHostSequencer<State: Sendable> {
    public private(set) var checkpoint: PhoneHostCheckpoint<State>
    private let futureToleranceMilliseconds: Int64
    private let snapshot: (State) -> LinkedScoreboardSnapshot
    private let isFinished: (State) -> Bool
    private let transition: (State, LinkOperation, Int64) -> LinkIntentTransition<State>

    /// The caller supplies pure transitions over value state and runs one
    /// sequencer at a time per handle. A transition validates the current undo
    /// target and maps shared finish to the appropriate reducer intent.
    public init(
        checkpoint: PhoneHostCheckpoint<State>,
        futureToleranceMilliseconds: Int64 = 2_000,
        snapshot: @escaping (State) -> LinkedScoreboardSnapshot,
        isFinished: @escaping (State) -> Bool,
        transition: @escaping (State, LinkOperation, Int64) -> LinkIntentTransition<State>
    ) {
        self.checkpoint = checkpoint
        self.futureToleranceMilliseconds = max(0, futureToleranceMilliseconds)
        self.snapshot = snapshot
        self.isFinished = isFinished
        self.transition = transition
    }

    /// Returns the exact durable result for retries. `persist` must atomically
    /// write the new checkpoint and receipt, and must throw only if neither was
    /// committed. The service updates projections before sending this result.
    /// Use a retained, finished match's sequencer to resolve late operations
    /// without applying them to the active match.
    public mutating func process(
        _ op: LinkOperation,
        from origin: LinkPeer,
        phoneClockReferenceEpochMilliseconds: Int64,
        isActiveMatch: Bool = true,
        lookup: (UUID) throws -> LinkOperationCommitPayload?,
        persist: (PhoneHostCheckpoint<State>, LinkOperationCommitPayload) throws -> Void
    ) throws -> LinkOperationCommitPayload {
        guard op.handle == checkpoint.handle else { throw PhoneHostSequenceError.wrongHandle }
        guard op.origin == origin else { throw PhoneHostSequenceError.wrongOrigin }
        if let previous = try lookup(op.opId) {
            guard previous.op == op else { throw PhoneHostSequenceError.conflictingOperationID }
            return previous
        }
        guard isActiveMatch || isFinished(checkpoint.state) else { throw PhoneHostSequenceError.wrongHandle }

        let lastClientSeq = origin == .phone ? checkpoint.phoneClientSeq : checkpoint.watchClientSeq
        guard op.clientSeq > lastClientSeq else { throw PhoneHostSequenceError.alreadyProcessedSequence }
        guard checkpoint.committedRevision < UInt64.max else { throw PhoneHostSequenceError.sequenceExhausted }
        guard op.clientSeq == lastClientSeq + 1 else {
            throw PhoneHostSequenceError.missingSequence(expected: lastClientSeq + 1)
        }

        let clockReference = max(checkpoint.phoneClockReferenceEpochMilliseconds, phoneClockReferenceEpochMilliseconds)
        let (limit, overflow) = clockReference.addingReportingOverflow(futureToleranceMilliseconds)
        let lowerBound = checkpoint.effectiveEpochMilliseconds
        let upperBound = max(lowerBound, overflow ? Int64.max : limit)
        let time = max(lowerBound, min(op.createdAtEpochMilliseconds, upperBound))
        let nextRevision = checkpoint.committedRevision + 1

        let result = apply(op, at: time, isActiveMatch: isActiveMatch)
        var state = checkpoint.state
        var nextMatchHandle = checkpoint.nextMatchHandle
        let reason: LinkOperationRejectionReason?
        let deltaActions: [DetailedScoreAction]
        switch result {
        case .accepted(let nextState, let actions):
            state = nextState
            deltaActions = actions
            reason = nil
            if case .nextMatch(let matchId, let generation) = op.intent {
                nextMatchHandle = LinkedMatchHandle(
                    sessionId: op.handle.sessionId, matchId: matchId, matchGeneration: generation
                )
            }
        case .rejected(let rejection):
            deltaActions = []
            reason = rejection
        }

        let authority = snapshot(state)
        let commit = LinkOperationCommitPayload(
            committedRevision: nextRevision,
            op: op,
            outcome: reason == nil ? .accepted : .rejected,
            effectiveEpochMilliseconds: time,
            timeWasClamped: time != op.createdAtEpochMilliseconds,
            rejectionReason: reason?.rawValue,
            stateHash: try LinkStateHash.snapshot(authority),
            authoritativeSnapshot: reason != nil || op.intent.needsAuthoritativeSnapshot
                || isFinished(state) || nextRevision.isMultiple(of: 10) ? authority : nil,
            deltaActions: deltaActions
        )
        let next = PhoneHostCheckpoint(
            handle: checkpoint.handle,
            state: state,
            committedRevision: nextRevision,
            phoneClientSeq: origin == .phone ? op.clientSeq : checkpoint.phoneClientSeq,
            watchClientSeq: origin == .watch ? op.clientSeq : checkpoint.watchClientSeq,
            effectiveEpochMilliseconds: time,
            phoneClockReferenceEpochMilliseconds: clockReference,
            nextMatchHandle: nextMatchHandle
        )
        try persist(next, commit)
        checkpoint = next
        return commit
    }

    /// Include receipts for outstanding Watch operations at or below the
    /// checkpoint watermark. A Watch keeps those operations if any receipt
    /// needed for reconciliation is missing.
    public func authoritativeCheckpoint(
        watchResults: [LinkOperationCommitPayload]
    ) throws -> LinkAuthoritativeCheckpoint {
        let authority = snapshot(checkpoint.state)
        let results = watchResults.filter {
            $0.op.handle == checkpoint.handle && $0.op.origin == .watch
                && $0.committedRevision <= checkpoint.committedRevision
                && $0.op.clientSeq <= checkpoint.watchClientSeq
        }
        return LinkAuthoritativeCheckpoint(
            handle: checkpoint.handle,
            committedRevision: checkpoint.committedRevision,
            watchClientSeq: checkpoint.watchClientSeq,
            effectiveEpochMilliseconds: checkpoint.effectiveEpochMilliseconds,
            snapshot: authority,
            stateHash: try LinkStateHash.snapshot(authority),
            watchResults: results.sorted { $0.op.clientSeq < $1.op.clientSeq }.map(LinkProcessedOperation.init)
        )
    }

    private func apply(
        _ op: LinkOperation,
        at time: Int64,
        isActiveMatch: Bool
    ) -> LinkIntentTransition<State> {
        if case .nextMatch(let matchId, let generation) = op.intent {
            guard isActiveMatch, isFinished(checkpoint.state),
                  checkpoint.nextMatchHandle == nil, op.handle.matchId != matchId,
                  op.handle.matchGeneration < UInt64.max, generation == op.handle.matchGeneration + 1,
                  op.baseRevision <= checkpoint.committedRevision else {
                return .rejected(.invalidNextMatch)
            }
            // Keep old-match scores immutable. The receipt durably names the new handle.
            return .accepted(state: checkpoint.state)
        }
        guard !isFinished(checkpoint.state) else { return .rejected(.matchFinished) }
        guard op.baseRevision <= checkpoint.committedRevision else { return .rejected(.invalidBaseRevision) }
        guard !op.intent.usesSportSpecificSessionControl else { return .rejected(.unsupportedSessionControl) }
        return transition(checkpoint.state, op, time)
    }
}
