import Foundation
import Testing
@testable import LinkCore

struct LinkOperationJournalTests {
    private struct Checkpoint: LinkOperationJournalCheckpoint, Equatable {
        let handle: LinkedMatchHandle
        let committedRevision: UInt64
        let score: Int
        let finished: Bool
    }

    private struct Outcome: LinkOperationJournalOutcome {
        let journalOperationHandle: LinkedMatchHandle
        let journalOperationID: UUID
        let committedRevision: UInt64
        let accepted: Bool
        let originalEpochMilliseconds: Int64
        let effectiveEpochMilliseconds: Int64
    }

    private typealias Journal = LinkOperationJournal<Checkpoint, Outcome>

    @Test func aRestartAfterAppendRecoversProjectionAndExactOutcomes() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let handle = LinkedMatchHandle(sessionId: UUID())
        let scoring = outcome(handle, revision: 1)
        let finish = outcome(handle, revision: 2)
        let lateScore = outcome(handle, revision: 3, accepted: false)
        let finished = checkpoint(handle, revision: 2, score: 1, finished: true)
        let closed = checkpoint(handle, revision: 3, score: 1, finished: true)

        do {
            let journal = try Journal(directoryURL: root, handle: handle)
            try journal.append(checkpoint: checkpoint(handle, revision: 1, score: 1), outcome: scoring)
            try journal.append(checkpoint: finished, outcome: finish)
            // The process ends immediately after durable append, before record save or ACK.
        }

        do {
            let journal = try Journal(directoryURL: root, handle: handle)
            #expect(journal.latestCheckpoint == finished)
            #expect(try journal.outcome(for: finish.journalOperationID) == finish)
            #expect(try journal.results(after: 0) == [scoring, finish])
            try journal.append(checkpoint: closed, outcome: lateScore)
        }

        let recovered = try Journal(directoryURL: root, handle: handle)
        #expect(recovered.latestCheckpoint == closed)
        #expect(try recovered.outcome(for: scoring.journalOperationID) == scoring)
        #expect(try recovered.outcome(for: finish.journalOperationID) == finish)
        #expect(try recovered.outcome(for: lateScore.journalOperationID) == lateScore)
        #expect(try recovered.results(after: 1) == [finish, lateScore])
        #expect(try recovered.results(after: 3).isEmpty)
    }

    @Test func failureBeforeFirstAppendLeavesNoProjectionOrDedupAdvance() throws {
        let handle = LinkedMatchHandle(sessionId: UUID())
        let storage = FaultStorage()
        let pending = outcome(handle, revision: 1)
        let first = checkpoint(handle, revision: 1, score: 1)
        let journal = try Journal(handle: handle, storage: storage)
        storage.failWrite(after: 0)

        #expect(throws: FaultStorage.Failure.write) {
            try journal.append(checkpoint: first, outcome: pending)
        }
        #expect(journal.latestCheckpoint == nil)
        #expect(try journal.outcome(for: pending.journalOperationID) == nil)
        #expect(try journal.results(after: 0).isEmpty)

        let recovered = try Journal(handle: handle, storage: storage)
        #expect(recovered.latestCheckpoint == nil)
        try recovered.append(checkpoint: first, outcome: pending)
        #expect(recovered.latestCheckpoint == first)
    }

    @Test func archivedPreviousResultDoesNotAdvanceOrDuplicateHeadAfterWriteFailure() throws {
        let handle = LinkedMatchHandle(sessionId: UUID())
        let storage = FaultStorage()
        let first = outcome(handle, revision: 1, accepted: false)
        let second = outcome(handle, revision: 2)
        let firstCheckpoint = checkpoint(handle, revision: 1, score: 0)
        let secondCheckpoint = checkpoint(handle, revision: 2, score: 1)

        do {
            let journal = try Journal(handle: handle, storage: storage)
            try journal.append(checkpoint: firstCheckpoint, outcome: first)
            // Allows the old result's archival and fails the atomic head replacement.
            storage.failWrite(after: 1)
            #expect(throws: FaultStorage.Failure.write) {
                try journal.append(checkpoint: secondCheckpoint, outcome: second)
            }
            #expect(journal.latestCheckpoint == firstCheckpoint)
        }

        let recovered = try Journal(handle: handle, storage: storage)
        #expect(recovered.latestCheckpoint == firstCheckpoint)
        #expect(try recovered.outcome(for: second.journalOperationID) == nil)
        #expect(try recovered.results(after: 0) == [first])
        try recovered.append(checkpoint: secondCheckpoint, outcome: second)
        #expect(recovered.latestCheckpoint == secondCheckpoint)
        #expect(try recovered.results(after: 0) == [first, second])
    }

    @Test func archivedOperationRemainsDeduplicatedBeyondTheMemoryCacheSize() throws {
        let handle = LinkedMatchHandle(sessionId: UUID())
        let storage = FaultStorage()
        let first = outcome(handle, revision: 1, accepted: false)

        do {
            let journal = try Journal(handle: handle, storage: storage)
            try journal.append(checkpoint: checkpoint(handle, revision: 1, score: 0), outcome: first)
            for revision: UInt64 in 2...1_002 {
                try journal.append(
                    checkpoint: checkpoint(handle, revision: revision, score: Int(revision - 1)),
                    outcome: outcome(handle, revision: revision)
                )
            }
        }

        let recovered = try Journal(handle: handle, storage: storage)
        #expect(try recovered.outcome(for: first.journalOperationID) == first)
        let duplicate = outcome(handle, id: first.journalOperationID, revision: 1_003)
        #expect(throws: LinkOperationJournalError.alreadyRecorded(first.journalOperationID)) {
            try recovered.append(checkpoint: checkpoint(handle, revision: 1_003, score: 1_002), outcome: duplicate)
        }
        #expect(recovered.latestCheckpoint?.committedRevision == 1_002)
        #expect(try recovered.results(after: 1_000).map(\.committedRevision) == [1_001, 1_002])
    }

    @Test func allThreeHandleComponentsIsolateReplays() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = LinkedMatchHandle(sessionId: UUID())
        let handles = [
            first,
            LinkedMatchHandle(sessionId: UUID(), matchId: first.matchId),
            LinkedMatchHandle(sessionId: first.sessionId, matchId: UUID()),
            LinkedMatchHandle(sessionId: first.sessionId, matchId: first.matchId, matchGeneration: 2)
        ]
        let reusedID = UUID()
        for (index, handle) in handles.enumerated() {
            let journal = try Journal(directoryURL: root, handle: handle)
            #expect(try journal.outcome(for: reusedID) == nil)
            try journal.append(
                checkpoint: checkpoint(handle, revision: 1, score: index),
                outcome: outcome(handle, id: reusedID, revision: 1)
            )
        }

        for (index, handle) in handles.enumerated() {
            let journal = try Journal(directoryURL: root, handle: handle)
            #expect(journal.latestCheckpoint?.score == index)
            #expect(try journal.outcome(for: reusedID)?.journalOperationHandle == handle)
        }
    }

    @Test func incompatibleCheckpointOrRevisionCannotBePersisted() throws {
        let handle = LinkedMatchHandle(sessionId: UUID())
        let storage = FaultStorage()
        let journal = try Journal(handle: handle, storage: storage)
        let first = checkpoint(handle, revision: 1, score: 1)
        let second = checkpoint(handle, revision: 2, score: 2)

        #expect(throws: LinkOperationJournalError.handleMismatch) {
            try journal.append(checkpoint: first, outcome: outcome(handle.nextMatch(), revision: 1))
        }
        #expect(throws: LinkOperationJournalError.checkpointRevisionMismatch(checkpoint: 2, outcome: 1)) {
            try journal.append(checkpoint: second, outcome: outcome(handle, revision: 1))
        }
        #expect(throws: LinkOperationJournalError.nonconsecutiveRevision(expected: 1, actual: 2)) {
            try journal.append(checkpoint: second, outcome: outcome(handle, revision: 2))
        }
        #expect(journal.latestCheckpoint == nil)
        #expect(try storage.allKeysOrThrow().isEmpty)
    }

    @Test func startupDoesNotTreatReadFailureOrAnInconsistentHeadAsAnEmptyMatch() throws {
        let handle = LinkedMatchHandle(sessionId: UUID())
        let storage = FaultStorage()
        storage.failReads()
        #expect(throws: FaultStorage.Failure.read) {
            try Journal(handle: handle, storage: storage)
        }

        let corrupt = FaultStorage()
        struct WrongHead: Encodable {
            let checkpoint: Checkpoint
            let outcome: Outcome
        }
        try corrupt.setOrThrow(JSONEncoder().encode(WrongHead(
            checkpoint: checkpoint(handle, revision: 2, score: 1),
            outcome: outcome(handle, revision: 1)
        )), forKey: "head")
        #expect(throws: LinkOperationJournalError.checkpointRevisionMismatch(checkpoint: 2, outcome: 1)) {
            try Journal(handle: handle, storage: corrupt)
        }

        let missing = FaultStorage()
        let archived = outcome(handle, revision: 1)
        try missing.setOrThrow(
            JSONEncoder().encode(archived), forKey: "result-\(archived.journalOperationID.uuidString)"
        )
        #expect(throws: LinkOperationJournalError.inconsistentHistory) {
            try Journal(handle: handle, storage: missing)
        }
    }

    @Test func fileStoreDistinguishesAnAbsentValueFromAnActualReadFailure() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = FileLinkDataStore(directoryURL: root)
        #expect(try store.dataOrThrow(forKey: "missing") == nil)
        let invalidFile = FileLinkDataStore.fileURL(directory: root, key: "directory")
        try FileManager.default.createDirectory(at: invalidFile, withIntermediateDirectories: false)
        #expect(throws: CocoaError.self) {
            try store.dataOrThrow(forKey: "directory")
        }
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "LinkOperationJournalTests-\(UUID().uuidString)", isDirectory: true
        )
    }

    private func checkpoint(
        _ handle: LinkedMatchHandle, revision: UInt64, score: Int, finished: Bool = false
    ) -> Checkpoint {
        Checkpoint(handle: handle, committedRevision: revision, score: score, finished: finished)
    }

    private func outcome(
        _ handle: LinkedMatchHandle, id: UUID = UUID(), revision: UInt64, accepted: Bool = true
    ) -> Outcome {
        Outcome(
            journalOperationHandle: handle,
            journalOperationID: id,
            committedRevision: revision,
            accepted: accepted,
            originalEpochMilliseconds: 1_700_000_000_005,
            effectiveEpochMilliseconds: 1_700_000_000_123
        )
    }
}

private final class FaultStorage: LinkOperationJournalStorage, @unchecked Sendable {
    enum Failure: Error, Equatable { case read, write }

    private let lock = NSLock()
    private var data: [String: Data] = [:]
    private var writesBeforeFailure: Int?
    private var readsFail = false

    func failWrite(after successfulWrites: Int) {
        lock.withLock { writesBeforeFailure = successfulWrites }
    }

    func failReads() {
        lock.withLock { readsFail = true }
    }

    func dataOrThrow(forKey key: String) throws -> Data? {
        try lock.withLock {
            if readsFail { throw Failure.read }
            return data[key]
        }
    }

    func setOrThrow(_ value: Data, forKey key: String) throws {
        try lock.withLock {
            if let writesBeforeFailure {
                if writesBeforeFailure == 0 {
                    self.writesBeforeFailure = nil
                    throw Failure.write
                }
                self.writesBeforeFailure = writesBeforeFailure - 1
            }
            data[key] = value
        }
    }

    func allKeysOrThrow() throws -> [String] {
        try lock.withLock {
            if readsFail { throw Failure.read }
            return Array(data.keys)
        }
    }
}
