import Foundation
import Testing
@testable import LinkCore

/// The reconnect cursor is usually exactly one revision behind the head. That
/// path must not enumerate the archive, while wider cursors keep the complete
/// multi-revision replay and continuity validation.
struct LinkOperationJournalHeadCursorTests {
    private struct Checkpoint: LinkOperationJournalCheckpoint, Equatable {
        let handle: LinkedMatchHandle
        let committedRevision: UInt64
    }

    private struct Outcome: LinkOperationJournalOutcome {
        let journalOperationHandle: LinkedMatchHandle
        let journalOperationID: UUID
        let committedRevision: UInt64
    }

    private typealias Journal = LinkOperationJournal<Checkpoint, Outcome>

    private final class CountingStorage: LinkOperationJournalStorage, @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: Data] = [:]
        private(set) var allKeysCalls = 0

        func dataOrThrow(forKey key: String) throws -> Data? {
            lock.withLock { values[key] }
        }

        func setOrThrow(_ data: Data, forKey key: String) throws {
            lock.withLock { values[key] = data }
        }

        func allKeysOrThrow() throws -> [String] {
            lock.withLock {
                allKeysCalls += 1
                return Array(values.keys)
            }
        }

        func remove(_ key: String) {
            lock.withLock { values.removeValue(forKey: key) }
        }

        func recordAllKeysCalls() -> Int { lock.withLock { allKeysCalls } }
    }

    @Test func cursorOneBehindTheHeadReturnsTheHeadWithoutEnumeratingTheArchive() throws {
        let handle = LinkedMatchHandle(sessionId: UUID())
        let storage = CountingStorage()
        let journal = try Journal(handle: handle, storage: storage)
        var outcomes: [Outcome] = []
        for revision: UInt64 in 1...3 {
            let outcome = Outcome(
                journalOperationHandle: handle, journalOperationID: UUID(), committedRevision: revision
            )
            outcomes.append(outcome)
            try journal.append(
                checkpoint: Checkpoint(handle: handle, committedRevision: revision), outcome: outcome
            )
        }

        let callsBefore = storage.recordAllKeysCalls()
        #expect(try journal.results(after: 2) == [outcomes[2]])
        #expect(try journal.results(after: 2) == [outcomes[2]])
        #expect(storage.recordAllKeysCalls() == callsBefore)

        // Wider cursors still replay every revision and enumerate the archive.
        #expect(try journal.results(after: 1) == [outcomes[1], outcomes[2]])
        #expect(try journal.results(after: 0) == outcomes)
        #expect(storage.recordAllKeysCalls() > callsBefore)
        #expect(try journal.results(after: 3).isEmpty)
    }

    @Test func missingArchivedResultStillFailsAWiderReplayButNotTheHeadCursor() throws {
        let handle = LinkedMatchHandle(sessionId: UUID())
        let storage = CountingStorage()
        let journal = try Journal(handle: handle, storage: storage)
        var outcomes: [Outcome] = []
        for revision: UInt64 in 1...3 {
            let outcome = Outcome(
                journalOperationHandle: handle, journalOperationID: UUID(), committedRevision: revision
            )
            outcomes.append(outcome)
            try journal.append(
                checkpoint: Checkpoint(handle: handle, committedRevision: revision), outcome: outcome
            )
        }
        storage.remove("result-\(outcomes[1].journalOperationID.uuidString)")

        #expect(throws: LinkOperationJournalError.inconsistentHistory) {
            try journal.results(after: 0)
        }
        // Only the head is needed for the immediately preceding cursor.
        #expect(try journal.results(after: 2) == [outcomes[2]])
    }
}
