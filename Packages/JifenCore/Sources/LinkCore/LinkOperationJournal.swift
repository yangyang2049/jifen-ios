import Foundation

public protocol LinkOperationJournalCheckpoint: Codable, Sendable {
    var handle: LinkedMatchHandle { get }
    var committedRevision: UInt64 { get }
}

public protocol LinkOperationJournalOutcome: Codable, Equatable, Sendable {
    var journalOperationID: UUID { get }
    var journalOperationHandle: LinkedMatchHandle { get }
    var committedRevision: UInt64 { get }
}

public enum LinkOperationJournalError: Error, Equatable, Sendable {
    case handleMismatch
    case checkpointRevisionMismatch(checkpoint: UInt64, outcome: UInt64)
    case nonconsecutiveRevision(expected: UInt64, actual: UInt64)
    case revisionExhausted
    case alreadyRecorded(UUID)
    case inconsistentHistory
}

protocol LinkOperationJournalStorage: Sendable {
    func dataOrThrow(forKey key: String) throws -> Data?
    func setOrThrow(_ data: Data, forKey key: String) throws
    func allKeysOrThrow() throws -> [String]
}

extension FileLinkDataStore: LinkOperationJournalStorage {}

/// One journal per full match handle. Use one live instance per handle, owned by
/// the sequencer that serializes operations for that match.
///
/// The head holds the latest durable checkpoint and its exact operation result.
/// Each append archives the previous result before atomically replacing the head.
/// A restart can resume projection from the head and resend results by operation ID
/// or revision. No projection or ACK should be published until append returns.
public final class LinkOperationJournal<
    Checkpoint: LinkOperationJournalCheckpoint,
    Outcome: LinkOperationJournalOutcome
>: @unchecked Sendable {
    private struct Head: Codable {
        let checkpoint: Checkpoint
        let outcome: Outcome
    }

    private var head: Head?
    private let storage: any LinkOperationJournalStorage
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()
    public let handle: LinkedMatchHandle

    /// Each child directory is scoped to a session, match and generation.
    public convenience init(directoryURL: URL, handle: LinkedMatchHandle) throws {
        let name = "operations-\(handle.sessionId.uuidString)-\(handle.matchId.uuidString)-\(handle.matchGeneration)"
        let matchDirectory = directoryURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: matchDirectory, withIntermediateDirectories: true)
        try self.init(handle: handle, storage: FileLinkDataStore(directoryURL: matchDirectory))
    }

    init(handle: LinkedMatchHandle, storage: any LinkOperationJournalStorage) throws {
        self.handle = handle
        self.storage = storage
        if let data = try storage.dataOrThrow(forKey: "head") {
            let head = try decoder.decode(Head.self, from: data)
            try validate(checkpoint: head.checkpoint, outcome: head.outcome)
            guard head.outcome.committedRevision > 0 else {
                throw LinkOperationJournalError.inconsistentHistory
            }
            self.head = head
        } else if try storage.allKeysOrThrow().contains(where: { $0.hasPrefix("result-") }) {
            throw LinkOperationJournalError.inconsistentHistory
        }
    }

    public var latestCheckpoint: Checkpoint? {
        lock.withLock { head?.checkpoint }
    }

    /// Returns the original result, including rejections, for an operation retry.
    public func outcome(for opID: UUID) throws -> Outcome? {
        try lock.withLock { try storedOutcome(for: opID) }
    }

    /// Stores the complete process result before the caller installs the projection.
    public func append(checkpoint: Checkpoint, outcome: Outcome) throws {
        try lock.withLock {
            try validate(checkpoint: checkpoint, outcome: outcome)
            let opID = outcome.journalOperationID
            guard try storedOutcome(for: opID) == nil else {
                throw LinkOperationJournalError.alreadyRecorded(opID)
            }

            let currentRevision = head?.outcome.committedRevision ?? 0
            guard currentRevision < UInt64.max else {
                throw LinkOperationJournalError.revisionExhausted
            }
            let nextRevision = currentRevision + 1
            guard outcome.committedRevision == nextRevision else {
                throw LinkOperationJournalError.nonconsecutiveRevision(
                    expected: nextRevision, actual: outcome.committedRevision
                )
            }

            let next = Head(checkpoint: checkpoint, outcome: outcome)
            let data = try encoder.encode(next)
            if let previous = head?.outcome {
                let previousID = previous.journalOperationID
                // A failed head replacement may have already archived this result.
                if try archivedOutcome(for: previousID, through: previous) == nil {
                    try storage.setOrThrow(encoder.encode(previous), forKey: resultKey(previousID))
                }
            }
            try storage.setOrThrow(data, forKey: "head")
            head = next
        }
    }

    /// Returns every later operation result in revision order, including results
    /// older than the latest checkpoint. The caller supplies the confirmed cursor.
    public func results(after committedRevision: UInt64) throws -> [Outcome] {
        try lock.withLock {
            guard let latest = head?.outcome else { return [] }
            guard committedRevision < latest.committedRevision else { return [] }

            var results: [Outcome] = [latest]
            for key in try storage.allKeysOrThrow() where key.hasPrefix("result-") {
                guard let opID = UUID(uuidString: String(key.dropFirst("result-".count))),
                      let archived = try archivedOutcome(for: opID, through: latest) else {
                    throw LinkOperationJournalError.inconsistentHistory
                }
                if opID != latest.journalOperationID, archived.committedRevision > committedRevision {
                    results.append(archived)
                }
            }
            results.sort { $0.committedRevision < $1.committedRevision }
            let expectedCount = latest.committedRevision - committedRevision
            guard UInt64(results.count) == expectedCount,
                  results.enumerated().allSatisfy({ index, outcome in
                      outcome.committedRevision == committedRevision + UInt64(index) + 1
                  }) else {
                throw LinkOperationJournalError.inconsistentHistory
            }
            return results
        }
    }

    private func validate(checkpoint: Checkpoint, outcome: Outcome) throws {
        guard checkpoint.handle == handle, outcome.journalOperationHandle == handle else {
            throw LinkOperationJournalError.handleMismatch
        }
        guard checkpoint.committedRevision == outcome.committedRevision else {
            throw LinkOperationJournalError.checkpointRevisionMismatch(
                checkpoint: checkpoint.committedRevision, outcome: outcome.committedRevision
            )
        }
    }

    private func storedOutcome(for opID: UUID) throws -> Outcome? {
        guard let latest = head?.outcome else { return nil }
        if latest.journalOperationID == opID {
            return latest
        }
        return try archivedOutcome(for: opID, through: latest)
    }

    private func archivedOutcome(for opID: UUID, through latest: Outcome) throws -> Outcome? {
        guard let data = try storage.dataOrThrow(forKey: resultKey(opID)) else { return nil }
        let archived = try decoder.decode(Outcome.self, from: data)
        guard archived.journalOperationHandle == handle, archived.journalOperationID == opID,
              archived.committedRevision > 0,
              archived.committedRevision < latest.committedRevision || archived == latest else {
            throw LinkOperationJournalError.inconsistentHistory
        }
        return archived
    }

    private func resultKey(_ opID: UUID) -> String {
        "result-\(opID.uuidString)"
    }
}
