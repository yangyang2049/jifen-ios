//
//  ScoreboardRecordManager.swift
//  jifen
//
//  Schema-v4 finished-record persistence. Full records live in individual
//  atomic JSON files; active games are owned by ResumeSessionRepository.
//  index.json holds one summary row per finished record, so the records list
//  and Home read a single lightweight file instead of every record body.
//

import Foundation
import OSLog
import PersistenceCore
import RecordCore
import ScoreCore
import SessionCore

extension Notification.Name {
    static let scoreboardPersistenceFailed = Notification.Name("scoreboardPersistenceFailed")
    static let scoreboardRecordsDidChange = Notification.Name("scoreboardRecordsDidChange")
}

/// 笔记操作失败原因（对齐安卓 RecordNoteRecordingFailureReason / 仓库异常）。
enum RecordNoteError: Error {
    case recordMissing
    case invalidVoiceNote
    case fileMissing
    case fileCreateFailed
}

enum ScoreboardPersistenceFailureReporter {
    nonisolated private static let logger = Logger(
        subsystem: "com.douhua.jifen.ios",
        category: "ScoreboardPersistence"
    )
    nonisolated private static let lock = NSLock()
    private nonisolated(unsafe) static var lastPresentationAt: Date?

    /// Logs a failure that recovers by itself (a derived index rebuild) without
    /// presenting the "保存失败" banner, which would misreport the durable write.
    nonisolated static func note(_ error: Error, context: String) {
        logger.error("\(context, privacy: .public): \(String(describing: error), privacy: .public)")
        #if DEBUG
        print("[ScoreboardPersistence] 索引待重建：\(context) - \(String(describing: error))")
        #endif
    }

    nonisolated static func report(_ error: Error, context: String, forcePresentation: Bool = false) {
        logger.error("\(context, privacy: .public): \(String(describing: error), privacy: .public)")
        // DEBUG 构建额外打印到控制台，方便在 Xcode 里直接看到具体失败原因。
        #if DEBUG
        print("[ScoreboardPersistence] 保存失败：\(context) - \(String(describing: error))")
        #endif
        lock.lock()
        let now = Date()
        let shouldPresent = forcePresentation
            || lastPresentationAt.map { now.timeIntervalSince($0) >= 5 } != false
        if shouldPresent { lastPresentationAt = now }
        lock.unlock()
        guard shouldPresent else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .scoreboardPersistenceFailed, object: nil)
        }
    }
}

/// A finished match has two persistence phases with deliberately different
/// failure semantics: the formal record must become durable first, while
/// removing the resumable snapshot is cleanup that can safely be retried.
enum FinishedSessionCommitResult {
    case committed(recordWritten: Bool)
    case committedCleanupPending(recordWritten: Bool, error: Error)

    var recordWritten: Bool {
        switch self {
        case .committed(let recordWritten),
             .committedCleanupPending(let recordWritten, _):
            return recordWritten
        }
    }

    var cleanupError: Error? {
        guard case .committedCleanupPending(_, let error) = self else { return nil }
        return error
    }
}

struct FinishedSessionRecordCommit {
    let sessionId: UUID
    let recordWritten: Bool
}

/// Cleanup is best-effort for the foreground commit, but not one-shot. Retry a
/// transient failure in the background and let startup reconciliation provide
/// the final safety net if the process is suspended or terminated.
@MainActor
private final class FinishedResumeCleanupRetryScheduler {
    static let shared = FinishedResumeCleanupRetryScheduler()

    private var tasks: [UUID: Task<Void, Never>] = [:]

    func schedule(
        sessionId: UUID,
        resumeRemover: @escaping FinishedSessionCommitCoordinator.ResumeRemover
    ) {
        guard tasks[sessionId] == nil else { return }
        tasks[sessionId] = Task { [weak self] in
            var lastError: Error?
            for delayNanoseconds in [250_000_000, 1_000_000_000, 3_000_000_000] as [UInt64] {
                do {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                    try await resumeRemover(sessionId)
                    self?.tasks[sessionId] = nil
                    return
                } catch is CancellationError {
                    self?.tasks[sessionId] = nil
                    return
                } catch {
                    lastError = error
                }
            }
            self?.tasks[sessionId] = nil
            if let lastError {
                ScoreboardPersistenceFailureReporter.report(
                    lastError,
                    context: "Finished resume cleanup retries exhausted \(sessionId.uuidString)"
                )
            }
        }
    }
}

/// App-layer transaction boundary for SessionCore scoreboards. PersistenceCore
/// intentionally keeps its existing `finished => remove resume` behavior; app
/// callers use this coordinator so that behavior is never invoked before the
/// formal record write has succeeded.
@MainActor
struct FinishedSessionCommitCoordinator {
    private static let reopenedResumeIDKey = "reopenedResumeID"

    typealias RecordLookup = @MainActor (String) -> ScoreboardRecord?
    typealias RecordWriter = @MainActor (ScoreboardRecord) throws -> Void
    typealias ResumeRemover = @MainActor (UUID) async throws -> Void
    typealias CleanupRetryScheduler = @MainActor (UUID, @escaping ResumeRemover) -> Void

    private let recordLookup: RecordLookup
    private let recordWriter: RecordWriter
    private let resumeRemover: ResumeRemover
    private let cleanupRetryScheduler: CleanupRetryScheduler

    init(
        recordLookup: @escaping RecordLookup = {
            ScoreboardRecordManager.shared.getRecordById($0)
        },
        recordWriter: @escaping RecordWriter = {
            try ScoreboardRecordManager.shared.saveScoreboardRecord(
                $0,
                cleanupResumeAfterWrite: false
            )
        },
        resumeRemover: @escaping ResumeRemover = { sessionId in
            try await ResumeSessionRepository().remove(sessionId: sessionId)
        },
        cleanupRetryScheduler: @escaping CleanupRetryScheduler = { sessionId, resumeRemover in
            FinishedResumeCleanupRetryScheduler.shared.schedule(
                sessionId: sessionId,
                resumeRemover: resumeRemover
            )
        }
    ) {
        self.recordLookup = recordLookup
        self.recordWriter = recordWriter
        self.resumeRemover = resumeRemover
        self.cleanupRetryScheduler = cleanupRetryScheduler
    }

    /// Completes the durable phase synchronously. A retry for an already saved
    /// record skips the writer, avoiding duplicate outbox work and analytics.
    func commitRecord(
        _ record: ScoreboardRecord,
        sessionId: UUID,
        replaceExisting: Bool = false,
        reopenedResumeID: UUID? = nil
    ) throws -> FinishedSessionRecordCommit {
        let existing = recordLookup(record.id)
        let alreadyCommitted = existing?.status == .finished
        let sameReopenedResume = reopenedResumeID.map {
            existing?.syncMetadata?[Self.reopenedResumeIDKey] == $0.uuidString
        } ?? false
        let writeRecord = !alreadyCommitted || (replaceExisting && !sameReopenedResume)
        if writeRecord {
            var record = record
            if let reopenedResumeID {
                record.syncMetadata = (record.syncMetadata ?? [:]).merging(
                    [Self.reopenedResumeIDKey: reopenedResumeID.uuidString], uniquingKeysWith: { _, new in new }
                )
            }
            try recordWriter(record)
        }
        return FinishedSessionRecordCommit(sessionId: sessionId, recordWritten: writeRecord)
    }

    /// Cleanup failure is returned as a committed result instead of throwing:
    /// the formal record is already durable and the stale resume can be retried.
    func cleanupResume(
        after commit: FinishedSessionRecordCommit
    ) async -> FinishedSessionCommitResult {
        do {
            try await resumeRemover(commit.sessionId)
            return .committed(recordWritten: commit.recordWritten)
        } catch {
            cleanupRetryScheduler(commit.sessionId, resumeRemover)
            return .committedCleanupPending(
                recordWritten: commit.recordWritten,
                error: error
            )
        }
    }

    func commit(
        _ record: ScoreboardRecord,
        sessionId: UUID
    ) async throws -> FinishedSessionCommitResult {
        let recordCommit = try commitRecord(record, sessionId: sessionId)
        return await cleanupResume(after: recordCommit)
    }

    /// Startup reconciliation removes a stale resume without rewriting an
    /// already durable record. `nil` means no formal record exists yet.
    func reconcileCommittedRecord(
        recordID: String,
        sessionId: UUID,
        repository: ResumeSessionRepository
    ) async -> FinishedSessionCommitResult? {
        guard let record = recordLookup(recordID), record.status == .finished else { return nil }
        do {
            guard let envelope = try ResumeSessionRepository.loadEnvelope(
                sessionId: sessionId, rootURL: repository.rootURL
            ) else { return .committed(recordWritten: false) }
            // Only the finish committed for this reopened draft makes it stale.
            if envelope.payloadKind == .scoreSessionBundle,
               let reopenedResumeID = ScoreSessionPersistenceSupport.reopenedResumeID(in: envelope.payload),
               record.syncMetadata?[Self.reopenedResumeIDKey] != reopenedResumeID.uuidString {
                return nil
            }
            let token = ResumeSessionRepository.cleanupToken(for: envelope)
            let guardedCleanup = FinishedSessionCommitCoordinator(
                resumeRemover: { sessionId in
                    _ = try await repository.remove(sessionId: sessionId, ifUnchanged: token)
                },
                cleanupRetryScheduler: cleanupRetryScheduler
            )
            return await guardedCleanup.cleanupResume(after: FinishedSessionRecordCommit(
                sessionId: sessionId,
                recordWritten: false
            ))
        } catch {
            return .committedCleanupPending(recordWritten: false, error: error)
        }
    }
}

/// Finished-record writes can arrive repeatedly from dialog actions and view
/// teardown. Coalesce cleanup for the same match and route every removal
/// through one repository so concurrent callers never race on the resume index.
private actor FinishedResumeSessionCleanup {
    static let shared = FinishedResumeSessionCleanup()

    private let repository = ResumeSessionRepository()
    private var pendingSessionIDs: Set<UUID> = []

    func remove(sessionId: UUID) async {
        guard pendingSessionIDs.insert(sessionId).inserted else { return }
        defer { pendingSessionIDs.remove(sessionId) }
        do {
            try await repository.remove(sessionId: sessionId)
        } catch {
            ScoreboardPersistenceFailureReporter.report(
                error,
                context: "remove finished resume session"
            )
        }
    }
}

/// Current-format persistence for manually managed scoreboards. Live state is
/// kept outside the finished-record manager and never enters its file store.
enum ManualResumeSessionStore {
    static func load(recordID: String) -> ManualScoreboardResumeState? {
        guard let sessionId = sessionID(for: recordID),
              let data = try? ResumeSessionRepository.loadManualPayload(sessionId: sessionId),
              let state = try? JSONDecoder().decode(ManualScoreboardResumeState.self, from: data),
              state.schemaVersion == ManualScoreboardResumeState.currentSchemaVersion else {
            return nil
        }
        return state
    }

    static func save(_ record: ScoreboardRecord) throws {
        guard let sessionId = sessionID(for: record.id),
              let exactGameType = record.resolvedScoreCoreGameType ?? record.gameType.scoreCoreGameType else {
            throw CocoaError(.fileWriteUnknown)
        }
        let state = ManualScoreboardResumeState(
            record: record,
            scoreCoreGameType: exactGameType
        )
        let payload = try JSONEncoder().encode(state)
        let displayParticipants = record.displayParticipants
        let participants: [SessionParticipant]
        if displayParticipants.isEmpty {
            participants = [
                .init(id: TeamID.team0.rawValue, name: record.team1Name, role: "team"),
                .init(id: TeamID.team1.rawValue, name: record.team2Name, role: "team")
            ]
        } else {
            participants = displayParticipants.enumerated().map { index, participant in
                .init(id: "participant-\(index)", name: participant.name, role: "player")
            }
        }
        try ResumeSessionRepository.saveManualPayload(
            sessionId: sessionId,
            gameType: exactGameType,
            startedAtEpochMilliseconds: Int64(record.startTime.timeIntervalSince1970 * 1_000),
            participants: participants,
            scoreSummary: record.finalScoreLine(),
            payload: payload
        )
        Task { @MainActor in try? ParticipantIdentityStore.shared.reconcileSelections(record: record) }
    }

    static func sessionID(for recordID: String) -> UUID? {
        if let exact = UUID(uuidString: recordID) {
            return exact
        }
        guard let suffix = recordID.split(separator: "_").last else { return nil }
        return UUID(uuidString: String(suffix))
    }

    /// Manual scoreboards keep the stable record identifier inside the v1
    /// payload while the resume index is keyed by its UUID suffix. Startup
    /// reconciliation must recover that identifier before looking for an
    /// already committed formal record.
    static func recordID(
        for sessionID: UUID,
        rootURL: URL = ResumeSessionRepository.defaultRootURL()
    ) -> String? {
        guard let data = try? ResumeSessionRepository.loadManualPayload(
            sessionId: sessionID,
            rootURL: rootURL
        ),
        let state = try? JSONDecoder().decode(ManualScoreboardResumeState.self, from: data),
        state.schemaVersion == ManualScoreboardResumeState.currentSchemaVersion else {
            return nil
        }
        return state.recordId
    }
}

enum ScoreboardLifecyclePersistence {
    /// Enforce one lifecycle contract at the persistence boundary so manually
    /// managed scoreboards cannot accidentally store a live match as finished.
    static func normalizedRecord(
        _ record: ScoreboardRecord,
        finished: Bool,
        finishedAt: Date = Date()
    ) -> ScoreboardRecord {
        var normalized = record
        normalized.status = finished ? .finished : .draft
        normalized.endTime = finished ? (record.endTime ?? finishedAt) : nil
        if !finished {
            normalized.winner = nil
            normalized.winnerIdentity = nil
        }
        return normalized
    }

    static func save(_ record: ScoreboardRecord, finished: Bool) throws {
        let record = normalizedRecord(record, finished: finished)
        if finished {
            try ScoreboardRecordManager.shared.saveScoreboardRecord(record)
        } else {
            try ManualResumeSessionStore.save(record)
        }
    }
}

/// One row of the lightweight list index: every field the records list renders
/// plus the file the row belongs to. Listing a library decodes only this file;
/// individual `.record.json` bodies stay closed for detail and cloud sync.
struct ScoreboardRecordSummaryIndexEntry: Codable, Equatable {
    let fileName: String
    var summary: ScoreboardRecordSummary
}

/// On-disk envelope for the summary index. The version is what makes an
/// interrupted write safe: a payload that is not the current version is never
/// trusted and is rebuilt from the record files instead.
private struct ScoreboardRecordSummaryIndexFile: Codable {
    // Version 1 stored the incoming timestamp before the record was encoded.
    static let currentVersion = 2
    var version: Int
    var entries: [ScoreboardRecordSummaryIndexEntry]
}

/// The authoritative record file is durable, but replacing the derived list
/// index failed. Callers must keep (and publish) the record change; the next
/// read rebuilds the index from the record files.
struct ScoreboardRecordIndexWriteFailure: Error {
    let recordID: String
    let underlying: Error
}

/// The derived index could not be invalidated, so a restart could still read the
/// previous rows. The change is rejected *before* the authoritative write, which
/// keeps the stored record and its summary on the old value.
struct ScoreboardRecordIndexInvalidationFailure: Error {
    /// The record whose change was rejected, or nil for a whole-library operation.
    let recordID: String?
}

/// One read of the derived index. `isComplete` is false when a record body
/// exists but could not be read: that row must not be dropped, and such a
/// snapshot must never be persisted as if it were the whole library.
private struct ScoreboardRecordIndexSnapshot {
    var entries: [ScoreboardRecordSummaryIndexEntry]
    var isComplete: Bool
}

/// Two files per library:
/// - `<safe-id>.record.json` - the authoritative body, written atomically;
/// - `index.json` - derived summary rows (`ScoreboardRecordSummaryIndexFile`),
///   read once by the list and never trusted without a matching version.
///
/// Crash safety follows from write order: the index is invalidated before the
/// body is written and rebuilt from the bodies afterwards. A crash or a failed
/// index write therefore falls back to a scan of the real files instead of a
/// stale index that would report old scores or hide a new record.
final class ScoreboardRecordFileStore {
    /// Record bodies are the only authoritative files in the store.
    static let recordFileSuffix = ".record.json"

    private let rootURL: URL
    private let indexURL: URL
    private let migrationMarkerURL: URL
    private let backupURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        indexURL = rootURL.appendingPathComponent("index.json", isDirectory: false)
        migrationMarkerURL = rootURL.appendingPathComponent("migration-v4-complete", isDirectory: false)
        backupURL = rootURL.appendingPathComponent("scoreboard-records-v3-backup.json", isDirectory: false)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    /// 测试注入点：按阶段模拟一次索引写盘或正文删除失败，便于确定性回归。
    enum SimulatedFailure: Equatable {
        case indexInvalidation
        case indexReplacement
        case recordRemoval(String)
    }

    var testFailureHook: ((SimulatedFailure) -> Bool)?

    func migrateIfNeeded(legacyData: Data?) throws {
        try ensureDirectory()
        guard !fileManager.fileExists(atPath: migrationMarkerURL.path) else { return }

        if let legacyData, !legacyData.isEmpty {
            let oldRecords = try decoder.decode([ScoreboardRecord].self, from: legacyData)
            try legacyData.write(to: backupURL, options: .atomic)
            let historicalRecords = oldRecords.filter { $0.status.isHistorical }
            if !historicalRecords.isEmpty, !ensureIndexInvalidated() {
                throw ScoreboardRecordIndexInvalidationFailure(recordID: nil)
            }
            for var record in historicalRecords {
                record.schemaVersion = ScoreboardRecord.currentSchemaVersion
                let detailed = record.detailedActions ?? ScoreboardRecordActionAdapter.actions(for: record)
                record.detailedActions = detailed
                record.setResults = record.setResults ?? ScoreboardRecordActionAdapter.setResults(from: detailed)
                try writeRecord(encoder.encode(record), id: record.id)
            }
            // Verify against the files that were actually written: an index left
            // behind by an interrupted migration must not vouch for the data.
            let recoveredIDs = Set((rebuildIndex()?.entries ?? []).map(\.summary.id))
            guard recoveredIDs == Set(historicalRecords.map(\.id)) else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }

        try Data("v4".utf8).write(to: migrationMarkerURL, options: .atomic)
    }

    /// The list path: one lightweight index read. No record file is opened,
    /// decoded or stat'ed, and a cold start with a valid index is the same work.
    func loadSummaries() -> [ScoreboardRecordSummary] {
        guard (try? ensureDirectory()) != nil else { return [] }
        return currentEntries()?.entries.map(\.summary) ?? []
    }

    /// Full-record read for the detail page, cloud sync and group repair. The
    /// records list never goes through here.
    func loadRecords() -> [ScoreboardRecord] {
        guard (try? ensureDirectory()) != nil, let snapshot = currentEntries() else { return [] }
        var records: [ScoreboardRecord] = []
        var missingIDs: Set<String> = []

        for entry in snapshot.entries {
            let url = rootURL.appendingPathComponent(entry.fileName, isDirectory: false)
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(ScoreboardRecord.self, from: data),
                  record.status.isHistorical else {
                // A body that is gone is really gone; a body that exists but
                // cannot be read keeps its row so the read can be retried
                // instead of persisting a library with a hole in it.
                if !fileManager.fileExists(atPath: url.path) { missingIDs.insert(entry.summary.id) }
                continue
            }
            records.append(record)
        }

        records.sort(by: Self.newestRecordFirst)
        if !missingIDs.isEmpty, snapshot.isComplete {
            try? writeIndex(snapshot.entries.filter { !missingIDs.contains($0.summary.id) })
        }
        return records
    }

    /// A detail lookup reads one record, independent of library size.
    func loadRecord(id: String) -> ScoreboardRecord? {
        guard let data = try? Data(contentsOf: recordURL(id: id)),
              let record = try? decoder.decode(ScoreboardRecord.self, from: data),
              record.id == id, record.status.isHistorical else { return nil }
        return record
    }

    func save(_ record: ScoreboardRecord) throws {
        guard record.status.isHistorical else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        let recordData = try encoder.encode(record)
        // Derive list fields from the same representation a rebuild reads.
        // The record's ISO 8601 encoding stores its start time to whole seconds.
        let persistedRecord = try decoder.decode(ScoreboardRecord.self, from: recordData)
        try ensureDirectory()
        // Snapshot the index while it is still trustworthy; the invalidation
        // below happens *before* the authoritative write so a crash after the
        // record lands can only leave an index that rebuilds, never one that
        // reports old scores or silently hides the new record.
        let snapshot = currentEntries()
        var entries = (snapshot?.entries ?? []).filter { $0.summary.id != record.id }
        entries.append(indexEntry(persistedRecord))
        entries.sort(by: Self.newestEntryFirst)

        // The index is invalidated *before* the body is written. When that fails
        // we may only continue if the path provably cannot serve stale rows;
        // otherwise a restart would read the old score, so the change is refused
        // with the previous record and its summary intact.
        guard ensureIndexInvalidated() else {
            throw ScoreboardRecordIndexInvalidationFailure(recordID: record.id)
        }

        try writeRecord(recordData, id: record.id)
        guard let snapshot, snapshot.isComplete else {
            // Some other body could not be read, so this record set is not the
            // whole library. Leave the index invalidated instead of persisting
            // a version with missing rows.
            invalidateIndex()
            throw ScoreboardRecordIndexWriteFailure(
                recordID: record.id,
                underlying: CocoaError(.fileReadUnknown)
            )
        }
        do {
            try writeIndex(entries)
        } catch {
            invalidateIndex()
            throw ScoreboardRecordIndexWriteFailure(recordID: record.id, underlying: error)
        }
    }

    @discardableResult
    func delete(id: String) -> Bool {
        guard loadRecord(id: id) != nil else { return false }
        let snapshot = currentEntries()
        let url = recordURL(id: id)
        // A restart would still read the row we are about to delete unless the
        // index is gone or provably unable to serve rows.
        guard ensureIndexInvalidated() else { return false }
        do {
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        } catch {
            return false
        }
        // Removing the file is the authoritative change; the row set is derived
        // and rebuilds on its own if this write fails.
        if let snapshot, snapshot.isComplete {
            try? writeIndex(snapshot.entries.filter { $0.summary.id != id })
        }
        return true
    }

    /// Batch cleanup keeps the surviving rows from the index instead of
    /// decoding every remaining record file. A body that could not be removed
    /// keeps its row: the derived index must never claim that a record which is
    /// still on disk is gone.
    @discardableResult
    func removeRecords(_ records: [ScoreboardRecord]) -> Bool {
        let requestedIDs = Set(records.map(\.id))
        guard !requestedIDs.isEmpty else { return true }
        let snapshot = currentEntries()
        guard ensureIndexInvalidated() else { return false }

        var removedIDs: Set<String> = []
        for id in requestedIDs {
            let url = recordURL(id: id)
            guard fileManager.fileExists(atPath: url.path) else {
                removedIDs.insert(id)
                continue
            }
            guard testFailureHook?(.recordRemoval(id)) != true else { continue }
            do {
                try fileManager.removeItem(at: url)
                removedIDs.insert(id)
            } catch {
                continue
            }
        }

        if let snapshot, snapshot.isComplete {
            try? writeIndex(snapshot.entries.filter { !removedIDs.contains($0.summary.id) })
        }
        return requestedIDs.isSubset(of: removedIDs)
    }

    /// Removes the complete record store, including files that are corrupt or
    /// absent from the index, then recreates only the migration marker. A
    /// record-by-record delete cannot guarantee a complete local-data reset
    /// because unreadable files are deliberately skipped by `loadRecords()`.
    func clearAllStoredData() throws {
        // Same rule as a record write: a recursive removal can fail halfway and
        // leave a valid index describing files that are already gone, so the
        // index is invalidated first and the reset is refused when the path
        // cannot be proven stale-free.
        guard ensureIndexInvalidated() else {
            throw ScoreboardRecordIndexInvalidationFailure(recordID: nil)
        }
        if fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.removeItem(at: rootURL)
        }
        try ensureDirectory()
        try Data("v4".utf8).write(to: migrationMarkerURL, options: .atomic)
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    private func writeRecord(_ data: Data, id: String) throws {
        try data.write(to: recordURL(id: id), options: .atomic)
    }

    /// Reads the derived index exactly once. A missing, legacy, corrupted or
    /// invalidated index is rebuilt from the record files that actually exist.
    private func currentEntries() -> ScoreboardRecordIndexSnapshot? {
        if let entries = loadTrustedEntries() {
            return ScoreboardRecordIndexSnapshot(entries: entries, isComplete: true)
        }
        return rebuildIndex()
    }

    private func loadTrustedEntries() -> [ScoreboardRecordSummaryIndexEntry]? {
        guard let data = try? Data(contentsOf: indexURL),
              let file = try? decoder.decode(ScoreboardRecordSummaryIndexFile.self, from: data),
              file.version == ScoreboardRecordSummaryIndexFile.currentVersion else {
            // Unreadable, legacy (`[ScoreboardRecordIndexEntry]`) or invalidated.
            return nil
        }
        return file.entries
    }

    /// Prepares the derived index for an authoritative write: the placeholder is
    /// written first, and a failure only lets the caller continue when the path
    /// provably cannot serve stale rows into a restart. An unreadable index is
    /// *not* "no index" - a transient read error would otherwise let the change
    /// through while the old rows are still on disk.
    private func ensureIndexInvalidated() -> Bool {
        if invalidateIndex() { return true }
        return !indexMayServeStaleRows()
    }

    /// True unless the path is known to hold no readable index: it is absent, or
    /// it is not a regular file (the historical "a directory sits at index.json"
    /// fault shape). Any attribute or read error keeps the answer conservative.
    private func indexMayServeStaleRows() -> Bool {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: indexURL.path)
            return (attributes[.type] as? FileAttributeType) != .typeDirectory
        } catch let error as NSError where error.code == NSFileReadNoSuchFileError {
            return false
        } catch {
            return true
        }
    }

    /// Marks the derived index unusable before an authoritative write. A false
    /// result means the placeholder could not be written; the caller decides
    /// whether the path can still serve stale rows.
    @discardableResult
    private func invalidateIndex() -> Bool {
        if testFailureHook?(.indexInvalidation) == true { return false }
        let invalid = ScoreboardRecordSummaryIndexFile(version: 0, entries: [])
        do {
            try encoder.encode(invalid).write(to: indexURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Rebuilds from the record files that are really on disk - never from the
    /// possibly stale file list. Returns nil without writing anything when the
    /// directory cannot be listed, so an I/O failure can never be persisted as
    /// an authoritative empty library.
    private func rebuildIndex() -> ScoreboardRecordIndexSnapshot? {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var entries: [ScoreboardRecordSummaryIndexEntry] = []
        var isComplete = true
        for url in urls where url.lastPathComponent.hasSuffix(Self.recordFileSuffix) {
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(ScoreboardRecord.self, from: data) else {
                // The file stays and the row is retried later: neither the
                // record nor a row-less index version may be dropped here.
                isComplete = false
                continue
            }
            guard record.status.isHistorical else {
                // A draft is a leftover live session, not history. This is also
                // where legacy draft files are swept, so startup never has to
                // open every record file again.
                try? fileManager.removeItem(at: url)
                continue
            }
            entries.append(indexEntry(record, fileName: url.lastPathComponent))
        }
        entries.sort(by: Self.newestEntryFirst)
        if isComplete {
            try? writeIndex(entries)
        } else {
            // Keep the index untrusted so the next read rebuilds and retries the
            // body that could not be read, instead of persisting a short list.
            invalidateIndex()
        }
        return ScoreboardRecordIndexSnapshot(entries: entries, isComplete: isComplete)
    }

    private func writeIndex(_ entries: [ScoreboardRecordSummaryIndexEntry]) throws {
        if testFailureHook?(.indexReplacement) == true { throw CocoaError(.fileWriteUnknown) }
        let payload = ScoreboardRecordSummaryIndexFile(
            version: ScoreboardRecordSummaryIndexFile.currentVersion,
            entries: entries
        )
        try encoder.encode(payload).write(to: indexURL, options: .atomic)
    }

    private func indexEntry(
        _ record: ScoreboardRecord,
        fileName: String? = nil
    ) -> ScoreboardRecordSummaryIndexEntry {
        ScoreboardRecordSummaryIndexEntry(
            fileName: fileName ?? recordURL(id: record.id).lastPathComponent,
            summary: ScoreboardRecordSummary(from: record)
        )
    }

    private static func newestEntryFirst(
        _ lhs: ScoreboardRecordSummaryIndexEntry,
        _ rhs: ScoreboardRecordSummaryIndexEntry
    ) -> Bool {
        if lhs.summary.timestamp == rhs.summary.timestamp { return lhs.summary.id < rhs.summary.id }
        return lhs.summary.timestamp > rhs.summary.timestamp
    }

    private static func newestRecordFirst(_ lhs: ScoreboardRecord, _ rhs: ScoreboardRecord) -> Bool {
        if lhs.startTime == rhs.startTime { return lhs.id < rhs.id }
        return lhs.startTime > rhs.startTime
    }

    private func recordURL(id: String) -> URL {
        let safe = Data(id.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return rootURL.appendingPathComponent("\(safe).record.json", isDirectory: false)
    }
}

final class ScoreboardRecordManager {
    static let shared = ScoreboardRecordManager()

    private let recordsKey = "scoreboard_records"
    private let defaults: UserDefaults
    private let store: ScoreboardRecordFileStore
    private let lock = NSRecursiveLock()

    private init() {
        defaults = AppTestRuntime.persistenceDefaults
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = AppTestRuntime.storageRootURL?.appendingPathComponent("ScoreboardRecords-v4", isDirectory: true)
            ?? applicationSupport
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.douhua.jifen", isDirectory: true)
            .appendingPathComponent("ScoreboardRecords-v4", isDirectory: true)
        store = ScoreboardRecordFileStore(rootURL: root)
        // Draft leftovers are swept when the index is rebuilt, so a cold start
        // with a valid index never opens or stats individual record files.
        migrateIfNeeded()
        // The unpublished draft pointer is intentionally not migrated.
        defaults.removeObject(forKey: "scoreboard_unfinished_record_id")
    }

    func saveScoreboardRecord(
        _ input: ScoreboardRecord,
        cleanupResumeAfterWrite: Bool = true
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        migrateIfNeeded()
        guard input.status.isHistorical else {
            throw CocoaError(.fileWriteUnsupportedScheme)
        }

        // 台球注解自身不抛错（损坏的本地文件只降级），不得阻断任何记分记录的保存。
        var record = GroupBilliardsPersistence.shared.annotate(GroupLocalPersistence.shared.annotate(input))
        record.schemaVersion = ScoreboardRecord.currentSchemaVersion
        if record.winnerIdentity == nil {
            record.winnerIdentity = ScoreboardWinnerIdentity.fromStableLegacyToken(record.winner)
        }
        if record.winner == nil {
            record.winner = record.winnerIdentity?.legacyToken
        }
        record.note = ScoreboardRecordNote.normalize(record.note)
        if record.detailedActions == nil {
            record.detailedActions = ScoreboardRecordActionAdapter.actions(for: record)
        }
        if record.setResults == nil, let detailedActions = record.detailedActions {
            record.setResults = ScoreboardRecordActionAdapter.setResults(from: detailedActions)
        }

        let previousRecord = store.loadRecord(id: record.id)

        var derivedIndexFailure: Error?
        do {
            try store.save(record)
        } catch let failure as ScoreboardRecordIndexWriteFailure {
            // The record file is already durable and the derived index rebuilds
            // from the record files on the next read. Publishing the real change
            // beats reporting a failure for a write that succeeded.
            derivedIndexFailure = failure.underlying
        } catch {
            AppAnalytics.scoreboardRecordSaveFailed(record)
            throw error
        }
        if let derivedIndexFailure {
            ScoreboardPersistenceFailureReporter.note(
                derivedIndexFailure,
                context: "record index will rebuild"
            )
        }
        do {
            try GroupLocalPersistence.shared.enqueue(record)
            try GroupBilliardsPersistence.shared.enqueue(record)
            if record.billiardsSource != nil { Task { @MainActor in await GroupBilliardsSync.shared.sync() } }
            if record.groupMatchContext != nil { Task { @MainActor in await GroupStore.shared.sync() } }
        } catch {
            // The saved record retains the context so foreground repair can retry.
            print("[Groups] Outbox write will be retried: \(error)")
        }
        // Retention is a cache concern after private-cloud support. Never turn
        // a local list threshold into deletion of historical records or audio.
        Task { @MainActor in
            try? ParticipantIdentityStore.shared.reconcileSelections(record: record)
            PersonalRecordsCloudSync.shared.schedule()
        }
        AppAnalytics.scoreboardRecordSaved(record, previous: previousRecord)
        if cleanupResumeAfterWrite,
           let sessionId = ManualResumeSessionStore.sessionID(for: record.id) {
            Task {
                await FinishedResumeSessionCleanup.shared.remove(sessionId: sessionId)
            }
        }
        notifyRecordsChanged()
    }

    /// Updates only the local annotation while preserving the complete
    /// finished record. The atomic record write means a failed update leaves
    /// the previous note (and every other field) untouched.
    func updateRecordNote(id: String, note: String?) throws {
        lock.lock()
        defer { lock.unlock() }
        migrateIfNeeded()
        guard var record = store.loadRecord(id: id) else {
            throw CocoaError(.fileNoSuchFile)
        }
        record.note = ScoreboardRecordNote.normalize(note)
        try saveScoreboardRecord(record, cleanupResumeAfterWrite: false)
    }

    /// 结果纠错：修改已完成两队制记录的最终比分/局分并重算胜者，变换逻辑见
    /// `ScoreboardRecordCorrection.applied`。首次纠错时把原始分值写入
    /// `correction` 留痕；`stateSnapshot` 与 `detailedActions` 保持原样。
    func updateRecordFinalScores(
        id: String,
        team1FinalScore: Int,
        team2FinalScore: Int,
        team1SetScore: Int?,
        team2SetScore: Int?
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        migrateIfNeeded()
        guard let record = store.loadRecord(id: id) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let corrected = ScoreboardRecordCorrection.applied(
            to: record,
            team1FinalScore: team1FinalScore,
            team2FinalScore: team2FinalScore,
            team1SetScore: team1SetScore,
            team2SetScore: team2SetScore
        )
        try saveScoreboardRecord(corrected, cleanupResumeAfterWrite: false)
    }

    // ---- 本地语音笔记（对齐安卓 ScoreboardRecordRepository） ----

    static var voiceNotesDirectoryURL: URL {
        if let root = AppTestRuntime.storageRootURL {
            return root.appendingPathComponent("RecordNotes", isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("RecordNotes", isDirectory: true)
    }

    static func voiceNoteFileURL(_ relativePath: String) -> URL {
        voiceNotesDirectoryURL.appendingPathComponent(relativePath)
    }

    static func deleteVoiceNoteFile(_ relativePath: String?) {
        guard let relativePath, !relativePath.isEmpty else { return }
        try? FileManager.default.removeItem(at: voiceNoteFileURL(relativePath))
    }

    /// 创建录音临时文件，返回相对路径；录音成功后经 `updateRecordVoiceNote` 转正。
    static func createVoiceNoteTempFile(recordId: String) throws -> String {
        let sanitized = String(
            recordId.map { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" || $0 == "_" ? $0 : "_" }.prefix(48)
        )
        let token = Int.random(in: 100_000...999_999)
        let relativePath = "temp_\(sanitized)_\(Int(Date().timeIntervalSince1970 * 1_000))_\(token).m4a"
        try FileManager.default.createDirectory(at: voiceNotesDirectoryURL, withIntermediateDirectories: true)
        let url = voiceNoteFileURL(relativePath)
        if !FileManager.default.createFile(atPath: url.path, contents: nil) {
            throw RecordNoteError.fileCreateFailed
        }
        return relativePath
    }

    /// 用临时录音替换当前语音笔记：转正文件名、更新记录字段、清理旧音频。
    func updateRecordVoiceNote(id: String, tempRelativePath: String, durationMs: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        migrateIfNeeded()
        guard ScoreboardRecordVoiceNoteLimits.isDurationValid(durationMs) else {
            throw RecordNoteError.invalidVoiceNote
        }
        guard tempRelativePath.hasPrefix("temp_"), tempRelativePath.hasSuffix(".m4a") else {
            throw RecordNoteError.invalidVoiceNote
        }
        guard var record = store.loadRecord(id: id) else {
            throw RecordNoteError.recordMissing
        }
        let tempURL = Self.voiceNoteFileURL(tempRelativePath)
        let attributes = try? FileManager.default.attributesOfItem(atPath: tempURL.path)
        if let size = (attributes?[.size] as? NSNumber)?.intValue, size > 0 {
            // 文件存在且非空
        } else {
            throw RecordNoteError.fileMissing
        }
        let finalRelativePath = tempRelativePath.hasPrefix("temp_")
            ? "voice_" + tempRelativePath.dropFirst(5)
            : tempRelativePath
        let finalURL = Self.voiceNoteFileURL(finalRelativePath)
        let previousPath = record.voiceNote?.relativePath
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try? FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: finalURL)
        record.voiceNote = ScoreboardRecordVoiceNote(relativePath: finalRelativePath, durationMs: durationMs)
        do {
            try saveScoreboardRecord(record, cleanupResumeAfterWrite: false)
        } catch {
            Self.deleteVoiceNoteFile(finalRelativePath)
            throw error
        }
        if previousPath != finalRelativePath {
            Self.deleteVoiceNoteFile(previousPath)
        }
    }

    /// 删除语音笔记：清空记录字段并移除音频文件。
    func deleteRecordVoiceNote(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        migrateIfNeeded()
        guard var record = store.loadRecord(id: id) else {
            throw RecordNoteError.recordMissing
        }
        let previousPath = record.voiceNote?.relativePath
        record.voiceNote = nil
        try saveScoreboardRecord(record, cleanupResumeAfterWrite: false)
        Self.deleteVoiceNoteFile(previousPath)
    }

    /// 清理未被任何记录引用的遗留音频（临时文件与孤儿正式文件）。
    static func cleanupOrphanVoiceNoteFiles(referencedPaths: Set<String>) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(atPath: voiceNotesDirectoryURL.path) else { return }
        for file in files where file.hasSuffix(".m4a") {
            if file.hasPrefix("temp_") || !referencedPaths.contains(file) {
                try? fileManager.removeItem(at: voiceNotesDirectoryURL.appendingPathComponent(file))
            }
        }
    }

    func loadAllRecords() -> [ScoreboardRecord] {
        lock.lock()
        defer { lock.unlock() }
        migrateIfNeeded()
        return store.loadRecords().filter { $0.status.isHistorical }
    }

    /// List rows for Records and Home: one lightweight index read, no record
    /// file is opened or decoded.
    func getAllRecordSummaries() -> [ScoreboardRecordSummary] {
        lock.lock()
        defer { lock.unlock() }
        migrateIfNeeded()
        return store.loadSummaries()
    }

    func loadAllRecordsInBackground() async -> [ScoreboardRecord] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.loadAllRecords())
            }
        }
    }

    func getRecordById(_ id: String) -> ScoreboardRecord? {
        lock.lock()
        defer { lock.unlock() }
        migrateIfNeeded()
        return store.loadRecord(id: id)
    }

    @MainActor
    func deleteRecord(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        migrateIfNeeded()
        let previousPath = store.loadRecord(id: id)?.voiceNote?.relativePath
        guard store.delete(id: id) else { return false }
        PersonalRecordsCloudSync.shared.markDeleted(recordKey: id)
        Self.deleteVoiceNoteFile(previousPath)
        AppAnalytics.track(.recordAction, parameters: [
            .actionName: .string("delete"),
            .recordType: .string("scoreboard"),
            .result: .string(AnalyticsResult.success.rawValue)
        ])
        notifyRecordsChanged()
        return true
    }

    @discardableResult
    func clearAllRecords() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let hadRecords = !store.loadSummaries().isEmpty
        // Remove the legacy aggregate before rebuilding the empty v4 store so
        // a later migration cannot restore records the user just cleared.
        defaults.removeObject(forKey: recordsKey)
        do {
            try store.clearAllStoredData()
        } catch {
            return false
        }
        // 空引用集 = 全量移除音频，连带清掉从未被记录引用的 temp_ 残留。
        Self.cleanupOrphanVoiceNoteFiles(referencedPaths: [])
        if hadRecords {
            AppAnalytics.track(.recordAction, parameters: [
                .recordType: .string("scoreboard"),
                .actionName: .string("clear_all"),
                .result: .string(AnalyticsResult.success.rawValue)
            ])
        }
        notifyRecordsChanged()
        return store.loadSummaries().isEmpty
    }

    private func notifyRecordsChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .scoreboardRecordsDidChange, object: nil)
        }
    }

    private func migrateIfNeeded() {
        do {
            try store.migrateIfNeeded(legacyData: defaults.data(forKey: recordsKey))
        } catch {
            #if DEBUG
            print("[ScoreboardRecordManager] migration failed: \(error)")
            #endif
        }
    }
}
