import Foundation
import LinkCore
import RecordCore

/// Owns one Watch replay queue and its projection for a full match handle.
/// The link service owns transport, UI, and routing to retained old handles.
@MainActor
public final class WatchLinkedIntentCoordinator {
    public enum RecoveryError: Error, Equatable {
        case handleMismatch
        case gameTypeMismatch
        case invalidCheckpoint
    }

    private typealias Checkpoint = WatchReplayCheckpoint<LinkedReducerState>

    private struct Stored: Codable {
        let checkpoint: Checkpoint
        let confirmedActions: [DetailedScoreAction]
    }

    private let store: FileLinkDataStore
    private let storageKey: String
    private let adapter: LinkedReducerAdapter
    private var engine: WatchOptimisticReplayEngine<LinkedReducerState>

    public private(set) var confirmedActions: [DetailedScoreAction]

    /// Opens an existing queue or durably creates the supplied match seed.
    public convenience init(
        handle: LinkedMatchHandle,
        initialState: LinkedReducerState,
        initialEpochMilliseconds: Int64,
        initialActions: [DetailedScoreAction] = [],
        adapter: LinkedReducerAdapter,
        store: FileLinkDataStore
    ) throws {
        let key = Self.key(for: handle)
        if let stored = try Self.load(handle: handle, store: store) {
            guard stored.checkpoint.confirmedState.gameType == initialState.gameType else {
                throw RecoveryError.gameTypeMismatch
            }
            self.init(stored: stored, key: key, adapter: adapter, store: store)
        } else {
            let checkpoint = Checkpoint(
                handle: handle,
                confirmedState: initialState,
                initialEpochMilliseconds: initialEpochMilliseconds
            )
            let stored = Stored(checkpoint: checkpoint, confirmedActions: initialActions)
            try store.setOrThrow(JSONEncoder().encode(stored), forKey: key)
            self.init(stored: stored, key: key, adapter: adapter, store: store)
        }
    }

    /// Reopens an old match without requiring a UI seed.
    public static func restore(
        handle: LinkedMatchHandle,
        adapter: LinkedReducerAdapter,
        store: FileLinkDataStore
    ) throws -> WatchLinkedIntentCoordinator? {
        guard let stored = try load(handle: handle, store: store) else { return nil }
        return WatchLinkedIntentCoordinator(stored: stored, key: key(for: handle), adapter: adapter, store: store)
    }

    private init(stored: Stored, key: String, adapter: LinkedReducerAdapter, store: FileLinkDataStore) {
        self.store = store
        storageKey = key
        self.adapter = adapter
        confirmedActions = stored.confirmedActions
        engine = WatchOptimisticReplayEngine(
            checkpoint: stored.checkpoint,
            snapshot: adapter.snapshot,
            installSnapshot: adapter.installSnapshot,
            isFinished: adapter.isFinished,
            transition: adapter.transition
        )
    }

    public var checkpoint: WatchReplayCheckpoint<LinkedReducerState> { engine.checkpoint }
    public var pendingOperations: [WatchPendingOperation] { checkpoint.pendingOperations }
    public var isPendingFinish: Bool { engine.isPendingFinish }
    public var excludedScoringOperationCount: Int { checkpoint.excludedScoringOperationCount }
    public var confirmedSnapshot: LinkedScoreboardSnapshot { adapter.snapshot(checkpoint.confirmedState) }
    public var displayedState: LinkedReducerState { engine.displayedState }
    public var displayedSnapshot: LinkedScoreboardSnapshot { adapter.snapshot(displayedState) }

    /// The action projection uses the same operation order and optimistic clock
    /// as the display state. Only confirmed actions are stored as history.
    public var displayedActions: [DetailedScoreAction] {
        var state = checkpoint.confirmedState
        var effectiveTime = checkpoint.effectiveEpochMilliseconds
        var actions = confirmedActions
        for pending in pendingOperations {
            let operation = pending.operation
            guard !adapter.isFinished(state) else { break }
            effectiveTime = max(effectiveTime, operation.createdAtEpochMilliseconds)
            if case .nextMatch = operation.intent { continue }
            if case .accepted(let next, let delta) = adapter.transition(state, operation, effectiveTime) {
                state = next
                actions.append(contentsOf: delta)
            }
        }
        return actions
    }

    /// Returns the operation only after its queued state is durable.
    @discardableResult
    public func enqueue(
        _ intent: LinkedScoreboardIntent,
        opId: UUID,
        createdAtEpochMilliseconds: Int64
    ) throws -> LinkOperation {
        let persist = persistence(actions: confirmedActions)
        return try engine.enqueue(
            intent, opId: opId, createdAtEpochMilliseconds: createdAtEpochMilliseconds, persist: persist
        )
    }

    /// Passes the retained operation to the caller only after its sent bit has
    /// been persisted. An operation already removed from the queue returns nil.
    @discardableResult
    public func markSent(_ opId: UUID) throws -> LinkOperation? {
        guard let pending = pendingOperations.first(where: { $0.operation.opId == opId }) else { return nil }
        let persist = persistence(actions: confirmedActions)
        try engine.markSent(opId, persist: persist)
        return pending.operation
    }

    @discardableResult
    public func cancelUnsentScore(_ opId: UUID) throws -> Bool {
        let persist = persistence(actions: confirmedActions)
        return try engine.cancelUnsentScore(opId, persist: persist)
    }

    @discardableResult
    public func receive(_ commit: LinkOperationCommitPayload) throws -> WatchReplayReceiveResult {
        var actions = confirmedActions
        if commit.outcome == .accepted {
            var known = Set(actions.map(\.id))
            actions.append(contentsOf: commit.deltaActions.filter { known.insert($0.id).inserted })
        }
        let persist = persistence(actions: actions)
        let result = try engine.receive(commit, persist: persist)
        if result == .advanced { confirmedActions = actions }
        return result
    }

    /// A repair snapshot can be accompanied by the complete confirmed history.
    /// History for this revision may also arrive after the score checkpoint.
    @discardableResult
    public func receive(
        _ authority: LinkAuthoritativeCheckpoint,
        confirmedActions history: [DetailedScoreAction]? = nil
    ) throws -> WatchReplayReceiveResult {
        let actions = history ?? confirmedActions
        let persist = persistence(actions: actions)
        let result = try engine.receive(authority, persist: persist)
        if result == .advanced {
            confirmedActions = actions
        } else if result == .alreadyConfirmed,
                  authority.committedRevision == checkpoint.committedRevision,
                  actions != confirmedActions {
            try persist(checkpoint)
            confirmedActions = actions
        }
        return result
    }

    private func persistence(actions: [DetailedScoreAction]) -> (Checkpoint) throws -> Void {
        { [store, storageKey] checkpoint in
            let data = try JSONEncoder().encode(Stored(checkpoint: checkpoint, confirmedActions: actions))
            try store.setOrThrow(data, forKey: storageKey)
        }
    }

    private static func key(for handle: LinkedMatchHandle) -> String {
        "watch-intent-\(handle.sessionId.uuidString)-\(handle.matchId.uuidString)-\(handle.matchGeneration)"
    }

    private static func load(handle: LinkedMatchHandle, store: FileLinkDataStore) throws -> Stored? {
        guard let data = try store.dataOrThrow(forKey: key(for: handle)) else { return nil }
        let stored = try JSONDecoder().decode(Stored.self, from: data)
        let checkpoint = stored.checkpoint
        guard checkpoint.handle == handle else { throw RecoveryError.handleMismatch }
        guard checkpoint.watchClientSeq <= checkpoint.committedRevision,
              checkpoint.excludedScoringOperationCount >= 0 else { throw RecoveryError.invalidCheckpoint }

        var lastSequence = checkpoint.watchClientSeq
        var opIDs: Set<UUID> = []
        for pending in checkpoint.pendingOperations {
            let operation = pending.operation
            guard operation.handle == handle, operation.origin == .watch,
                  lastSequence < UInt64.max, operation.clientSeq == lastSequence + 1,
                  operation.baseRevision <= checkpoint.committedRevision,
                  opIDs.insert(operation.opId).inserted else { throw RecoveryError.invalidCheckpoint }
            lastSequence = operation.clientSeq
        }
        return stored
    }
}
