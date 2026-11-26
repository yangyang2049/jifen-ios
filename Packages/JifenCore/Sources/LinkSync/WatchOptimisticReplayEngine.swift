import Foundation
import LinkCore

public struct WatchPendingOperation: Codable, Equatable, Sendable {
    public let operation: LinkOperation
    public fileprivate(set) var hasBeenSent: Bool
}

/// Persist the confirmed state, cumulative dropped count, and outbox together.
/// Do not discard a checkpoint while it still has pending operations.
public struct WatchReplayCheckpoint<State> {
    public let handle: LinkedMatchHandle
    public fileprivate(set) var confirmedState: State
    public fileprivate(set) var committedRevision: UInt64
    public fileprivate(set) var watchClientSeq: UInt64
    public fileprivate(set) var effectiveEpochMilliseconds: Int64
    public fileprivate(set) var pendingOperations: [WatchPendingOperation]
    public fileprivate(set) var excludedScoringOperationCount: Int

    public init(handle: LinkedMatchHandle, confirmedState: State, initialEpochMilliseconds: Int64) {
        self.handle = handle
        self.confirmedState = confirmedState
        self.committedRevision = 0
        self.watchClientSeq = 0
        self.effectiveEpochMilliseconds = initialEpochMilliseconds
        self.pendingOperations = []
        self.excludedScoringOperationCount = 0
    }
}

extension WatchReplayCheckpoint: Codable where State: Codable {}
extension WatchReplayCheckpoint: Sendable where State: Sendable {}
extension WatchReplayCheckpoint: Equatable where State: Equatable {}

public enum WatchReplayReceiveResult: Equatable, Sendable {
    case advanced
    case alreadyConfirmed
    case wrongHandle
    case needsResync
}

public enum WatchReplayQueueError: Error, Equatable {
    case duplicateOperationID
    case queueFull
    case queueTooOld
    case awaitingFinishConfirmation
    case invalidSessionControl
    case matchFinished
    case sequenceExhausted
}

public struct WatchOptimisticReplayEngine<State> {
    public private(set) var checkpoint: WatchReplayCheckpoint<State>
    private let pendingLimit: Int
    private let pendingAgeLimitMilliseconds: Int64
    private let snapshot: (State) -> LinkedScoreboardSnapshot
    private let installSnapshot: (State, LinkedScoreboardSnapshot) -> State?
    private let isFinished: (State) -> Bool
    private let transition: (State, LinkOperation, Int64) -> LinkIntentTransition<State>

    /// Install a snapshot into a value state using the complete authority needed
    /// for future reducer operations. The service owns persistence and sending.
    public init(
        checkpoint: WatchReplayCheckpoint<State>,
        pendingLimit: Int = 500,
        pendingAgeLimitMilliseconds: Int64 = 7 * 24 * 60 * 60 * 1_000,
        snapshot: @escaping (State) -> LinkedScoreboardSnapshot,
        installSnapshot: @escaping (State, LinkedScoreboardSnapshot) -> State?,
        isFinished: @escaping (State) -> Bool,
        transition: @escaping (State, LinkOperation, Int64) -> LinkIntentTransition<State>
    ) {
        self.checkpoint = checkpoint
        self.pendingLimit = max(0, pendingLimit)
        self.pendingAgeLimitMilliseconds = max(0, pendingAgeLimitMilliseconds)
        self.snapshot = snapshot
        self.installSnapshot = installSnapshot
        self.isFinished = isFinished
        self.transition = transition
    }

    public var isPendingFinish: Bool {
        checkpoint.pendingOperations.contains { $0.operation.intent == .finish }
    }

    public var displayedState: State {
        var state = checkpoint.confirmedState
        var effectiveTime = checkpoint.effectiveEpochMilliseconds
        for pending in checkpoint.pendingOperations {
            let op = pending.operation
            guard !isFinished(state) else { break }
            effectiveTime = max(effectiveTime, op.createdAtEpochMilliseconds)
            if case .nextMatch = op.intent { continue }
            if case .accepted(let next, _) = transition(state, op, effectiveTime) {
                state = next
            }
        }
        return state
    }

    /// Persist the queued operation before exposing the updated display state.
    @discardableResult
    public mutating func enqueue(
        _ intent: LinkedScoreboardIntent,
        opId: UUID,
        createdAtEpochMilliseconds: Int64,
        persist: (WatchReplayCheckpoint<State>) throws -> Void
    ) throws -> LinkOperation {
        guard !checkpoint.pendingOperations.contains(where: { $0.operation.opId == opId }) else {
            throw WatchReplayQueueError.duplicateOperationID
        }
        guard !intent.usesSportSpecificSessionControl else { throw WatchReplayQueueError.invalidSessionControl }
        guard !isPendingFinish else { throw WatchReplayQueueError.awaitingFinishConfirmation }
        switch intent {
        case .nextMatch:
            guard isFinished(checkpoint.confirmedState), checkpoint.pendingOperations.isEmpty else {
                throw WatchReplayQueueError.invalidSessionControl
            }
        default:
            guard !isFinished(checkpoint.confirmedState) else { throw WatchReplayQueueError.matchFinished }
        }

        if intent != .finish {
            guard checkpoint.pendingOperations.count < pendingLimit else { throw WatchReplayQueueError.queueFull }
            if let first = checkpoint.pendingOperations.first?.operation {
                let (limit, overflow) = first.createdAtEpochMilliseconds.addingReportingOverflow(pendingAgeLimitMilliseconds)
                if !overflow, createdAtEpochMilliseconds > limit { throw WatchReplayQueueError.queueTooOld }
            }
        }
        let previousSequence = checkpoint.pendingOperations.last?.operation.clientSeq ?? checkpoint.watchClientSeq
        guard previousSequence < UInt64.max else { throw WatchReplayQueueError.sequenceExhausted }
        let op = LinkOperation(
            opId: opId,
            handle: checkpoint.handle,
            origin: .watch,
            clientSeq: previousSequence + 1,
            baseRevision: checkpoint.committedRevision,
            createdAtEpochMilliseconds: createdAtEpochMilliseconds,
            intent: intent
        )
        var next = checkpoint
        next.pendingOperations.append(WatchPendingOperation(operation: op, hasBeenSent: false))
        try save(next, persist: persist)
        return op
    }

    /// Mark the operation durably before handing it to transport. A crash while
    /// sending may require a journaled undo even if transport never received it.
    public mutating func markSent(
        _ opId: UUID,
        persist: (WatchReplayCheckpoint<State>) throws -> Void
    ) throws {
        guard let index = checkpoint.pendingOperations.firstIndex(where: { $0.operation.opId == opId }),
              !checkpoint.pendingOperations[index].hasBeenSent else { return }
        var next = checkpoint
        next.pendingOperations[index].hasBeenSent = true
        try save(next, persist: persist)
    }

    /// Only the unsent scoring tail may be dropped without sending an undo.
    /// Removing the tail leaves no sequence gap and keeps submitted IDs stable.
    @discardableResult
    public mutating func cancelUnsentScore(
        _ opId: UUID,
        persist: (WatchReplayCheckpoint<State>) throws -> Void
    ) throws -> Bool {
        guard let tail = checkpoint.pendingOperations.last, tail.operation.opId == opId,
              tail.operation.intent.isScoring, !tail.hasBeenSent else { return false }
        var next = checkpoint
        next.pendingOperations.removeLast()
        try save(next, persist: persist)
        return true
    }

    public mutating func receive(
        _ commit: LinkOperationCommitPayload,
        persist: (WatchReplayCheckpoint<State>) throws -> Void
    ) throws -> WatchReplayReceiveResult {
        guard commit.op.handle == checkpoint.handle else { return .wrongHandle }
        guard commit.committedRevision > checkpoint.committedRevision else { return .alreadyConfirmed }
        guard commit.committedRevision == checkpoint.committedRevision + 1,
              commit.effectiveEpochMilliseconds >= checkpoint.effectiveEpochMilliseconds else { return .needsResync }

        var next = checkpoint
        if commit.op.origin == .watch {
            guard checkpoint.watchClientSeq < UInt64.max, commit.op.clientSeq == checkpoint.watchClientSeq + 1,
                  let pending = checkpoint.pendingOperations.first, pending.operation == commit.op else {
                return .needsResync
            }
            next.watchClientSeq = commit.op.clientSeq
            next.pendingOperations.removeFirst()
            accountForExclusion(pending.operation, outcome: commit.outcome, reason: commit.rejectionReason, in: &next)
        }

        let current = checkpoint.confirmedState
        let replayed: State?
        switch (commit.outcome, commit.op.intent) {
        case (.rejected, _), (.accepted, .nextMatch):
            replayed = current
        case (.accepted, _):
            if case .accepted(let state, _) = transition(current, commit.op, commit.effectiveEpochMilliseconds) {
                replayed = state
            } else {
                replayed = nil
            }
        }
        guard let state = try verifiedState(
            replayed, authoritative: commit.authoritativeSnapshot, hash: commit.stateHash
        ) else { return .needsResync }

        next.confirmedState = state
        next.committedRevision = commit.committedRevision
        next.effectiveEpochMilliseconds = commit.effectiveEpochMilliseconds
        try save(next, persist: persist)
        return .advanced
    }

    /// A standalone repair checkpoint must reconcile every local operation at
    /// or below its watermark. A missing receipt cannot distinguish an accepted
    /// score from a rejected one, so preserve the pending queue on that path.
    public mutating func receive(
        _ authority: LinkAuthoritativeCheckpoint,
        persist: (WatchReplayCheckpoint<State>) throws -> Void
    ) throws -> WatchReplayReceiveResult {
        guard authority.handle == checkpoint.handle else { return .wrongHandle }
        guard authority.committedRevision >= checkpoint.committedRevision else { return .alreadyConfirmed }
        if authority.committedRevision == checkpoint.committedRevision {
            guard authority.watchClientSeq == checkpoint.watchClientSeq,
                  authority.effectiveEpochMilliseconds == checkpoint.effectiveEpochMilliseconds else { return .needsResync }
            if try LinkStateHash.snapshot(snapshot(checkpoint.confirmedState)) == authority.stateHash {
                return .alreadyConfirmed
            }
        }
        guard authority.watchClientSeq >= checkpoint.watchClientSeq,
              authority.watchClientSeq <= authority.committedRevision,
              authority.effectiveEpochMilliseconds >= checkpoint.effectiveEpochMilliseconds,
              let state = try verifiedState(nil, authoritative: authority.snapshot, hash: authority.stateHash) else {
            return .needsResync
        }

        var results: [UInt64: LinkProcessedOperation] = [:]
        for result in authority.watchResults {
            guard result.clientSeq > 0, result.clientSeq <= authority.watchClientSeq,
                  result.committedRevision >= result.clientSeq, result.committedRevision <= authority.committedRevision,
                  results.updateValue(result, forKey: result.clientSeq) == nil else { return .needsResync }
        }

        var next = checkpoint
        for pending in checkpoint.pendingOperations where pending.operation.clientSeq <= authority.watchClientSeq {
            guard let result = results[pending.operation.clientSeq], result.opId == pending.operation.opId,
                  result.committedRevision > checkpoint.committedRevision else { return .needsResync }
            next.watchClientSeq = pending.operation.clientSeq
            accountForExclusion(pending.operation, outcome: result.outcome, reason: result.rejectionReason, in: &next)
        }
        // A new installation may have an empty outbox and install the remote watermark.
        // A nonempty outbox always knows its last issued sequence.
        guard checkpoint.pendingOperations.isEmpty || next.watchClientSeq == authority.watchClientSeq else {
            return .needsResync
        }

        next.confirmedState = state
        next.committedRevision = authority.committedRevision
        next.watchClientSeq = authority.watchClientSeq
        next.effectiveEpochMilliseconds = authority.effectiveEpochMilliseconds
        next.pendingOperations.removeAll { $0.operation.clientSeq <= authority.watchClientSeq }
        try save(next, persist: persist)
        return .advanced
    }

    private func verifiedState(
        _ replayed: State?,
        authoritative: LinkedScoreboardSnapshot?,
        hash: UInt64
    ) throws -> State? {
        if let authoritative, try LinkStateHash.snapshot(authoritative) != hash { return nil }
        if let replayed, try LinkStateHash.snapshot(snapshot(replayed)) == hash { return replayed }
        guard let authoritative, let installed = installSnapshot(checkpoint.confirmedState, authoritative),
              try LinkStateHash.snapshot(snapshot(installed)) == hash else { return nil }
        return installed
    }

    private func accountForExclusion(
        _ op: LinkOperation,
        outcome: LinkOperationOutcome,
        reason: String?,
        in checkpoint: inout WatchReplayCheckpoint<State>
    ) {
        if op.intent.isScoring, outcome == .rejected, reason == LinkOperationRejectionReason.matchFinished.rawValue {
            checkpoint.excludedScoringOperationCount += 1
        }
    }

    private mutating func save(
        _ next: WatchReplayCheckpoint<State>,
        persist: (WatchReplayCheckpoint<State>) throws -> Void
    ) throws {
        try persist(next)
        checkpoint = next
    }
}
