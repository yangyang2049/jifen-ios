//
//  ScoreboardRecordManager.swift
//  jifen
//
//  Schema-v4 finished-record persistence. Full records live in individual
//  atomic JSON files; active games are owned by ResumeSessionRepository.
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

    nonisolated static func report(_ error: Error, context: String, forcePresentation: Bool = false) {
        logger.error("\(context, privacy: .public): \(String(describing: error), privacy: .public)")
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
        replaceExisting: Bool = false
    ) throws -> FinishedSessionRecordCommit {
        let alreadyCommitted = recordLookup(record.id)?.status == .finished
        if !alreadyCommitted || replaceExisting {
            try recordWriter(record)
        }
        return FinishedSessionRecordCommit(
            sessionId: sessionId,
            recordWritten: !alreadyCommitted || replaceExisting
        )
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
        sessionId: UUID
    ) async -> FinishedSessionCommitResult? {
        guard recordLookup(recordID)?.status == .finished else { return nil }
        return await cleanupResume(after: FinishedSessionRecordCommit(
            sessionId: sessionId,
            recordWritten: false
        ))
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

struct ScoreboardRecordIndexEntry: Codable, Equatable {
    let id: String
    let fileName: String
    let startTime: Date
    let status: ScoreboardRecordStatus
}

final class ScoreboardRecordFileStore {
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

    func migrateIfNeeded(legacyData: Data?) throws {
        try ensureDirectory()
        guard !fileManager.fileExists(atPath: migrationMarkerURL.path) else { return }

        if let legacyData, !legacyData.isEmpty {
            let oldRecords = try decoder.decode([ScoreboardRecord].self, from: legacyData)
            try legacyData.write(to: backupURL, options: .atomic)
            let historicalRecords = oldRecords.filter { $0.status.isHistorical }
            for var record in historicalRecords {
                record.schemaVersion = ScoreboardRecord.currentSchemaVersion
                let detailed = record.detailedActions ?? ScoreboardRecordActionAdapter.actions(for: record)
                record.detailedActions = detailed
                record.setResults = record.setResults ?? ScoreboardRecordActionAdapter.setResults(from: detailed)
                try writeRecord(record)
            }
            let recoveredIDs = Set(loadRecords().map(\.id))
            guard recoveredIDs == Set(historicalRecords.map(\.id)) else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }

        try Data("v4".utf8).write(to: migrationMarkerURL, options: .atomic)
    }

    func loadRecords() -> [ScoreboardRecord] {
        guard (try? ensureDirectory()) != nil else { return [] }
        let entries = loadIndex() ?? rebuildIndex()
        var records: [ScoreboardRecord] = []
        var indexNeedsRepair = false

        for entry in entries {
            let url = rootURL.appendingPathComponent(entry.fileName, isDirectory: false)
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(ScoreboardRecord.self, from: data) else {
                indexNeedsRepair = true
                continue
            }
            if record.status.isHistorical {
                records.append(record)
            } else {
                try? fileManager.removeItem(at: url)
                indexNeedsRepair = true
            }
        }

        records.sort { $0.startTime > $1.startTime }
        if indexNeedsRepair { try? writeIndex(for: records) }
        return records
    }

    func save(_ record: ScoreboardRecord) throws {
        guard record.status.isHistorical else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try ensureDirectory()
        try writeRecord(record)
        var records = loadRecords().filter { $0.id != record.id }
        records.append(record)
        records.sort { $0.startTime > $1.startTime }
        try writeIndex(for: records)
    }

    @discardableResult
    func delete(id: String) -> Bool {
        var records = loadRecords()
        guard records.contains(where: { $0.id == id }) else { return false }
        records.removeAll { $0.id == id }
        let url = recordURL(id: id)
        do {
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
            try writeIndex(for: records)
            return true
        } catch {
            return false
        }
    }

    func removeRecords(_ records: [ScoreboardRecord]) {
        for record in records {
            let url = recordURL(id: record.id)
            if fileManager.fileExists(atPath: url.path) { try? fileManager.removeItem(at: url) }
        }
        try? writeIndex(for: loadRecords().filter { candidate in
            !records.contains(where: { $0.id == candidate.id })
        })
    }

    /// Removes the complete record store, including files that are corrupt or
    /// absent from the index, then recreates only the migration marker. A
    /// record-by-record delete cannot guarantee a complete local-data reset
    /// because unreadable files are deliberately skipped by `loadRecords()`.
    func clearAllStoredData() throws {
        if fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.removeItem(at: rootURL)
        }
        try ensureDirectory()
        try Data("v4".utf8).write(to: migrationMarkerURL, options: .atomic)
    }

    func discardDraftFiles() {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        var removedAny = false
        for url in urls where url.lastPathComponent.hasSuffix(".record.json") {
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(ScoreboardRecord.self, from: data),
                  record.status == .draft else {
                continue
            }
            try? fileManager.removeItem(at: url)
            removedAny = true
        }
        if removedAny {
            try? writeIndex(for: loadRecords())
        }
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    private func writeRecord(_ record: ScoreboardRecord) throws {
        let data = try encoder.encode(record)
        try data.write(to: recordURL(id: record.id), options: .atomic)
    }

    private func loadIndex() -> [ScoreboardRecordIndexEntry]? {
        guard let data = try? Data(contentsOf: indexURL) else { return nil }
        return try? decoder.decode([ScoreboardRecordIndexEntry].self, from: data)
    }

    private func rebuildIndex() -> [ScoreboardRecordIndexEntry] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let records = urls
            .filter { $0.lastPathComponent.hasSuffix(".record.json") }
            .compactMap { url -> ScoreboardRecord? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                guard let record = try? decoder.decode(ScoreboardRecord.self, from: data),
                      record.status.isHistorical else {
                    try? fileManager.removeItem(at: url)
                    return nil
                }
                return record
            }
            .sorted { $0.startTime > $1.startTime }
        try? writeIndex(for: records)
        return records.map(indexEntry)
    }

    private func writeIndex(for records: [ScoreboardRecord]) throws {
        let data = try encoder.encode(records.map(indexEntry))
        try data.write(to: indexURL, options: .atomic)
    }

    private func indexEntry(_ record: ScoreboardRecord) -> ScoreboardRecordIndexEntry {
        ScoreboardRecordIndexEntry(
            id: record.id,
            fileName: recordURL(id: record.id).lastPathComponent,
            startTime: record.startTime,
            status: record.status
        )
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
    private let maxRecords = 1000
    private let defaults: UserDefaults
    private let store: ScoreboardRecordFileStore
    private let lock = NSRecursiveLock()

    private init() {
        defaults = .standard
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = applicationSupport
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.douhua.jifen", isDirectory: true)
            .appendingPathComponent("ScoreboardRecords-v4", isDirectory: true)
        store = ScoreboardRecordFileStore(rootURL: root)
        migrateIfNeeded()
        store.discardDraftFiles()
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

        var record = input
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

        var records = store.loadRecords()
        let previousRecord = records.first { $0.id == record.id }

        do {
            try store.save(record)
        } catch {
            AppAnalytics.scoreboardRecordSaveFailed(record)
            throw error
        }
        records.removeAll { $0.id == record.id }
        records.append(record)
        records.sort { $0.startTime > $1.startTime }
        if records.count > maxRecords {
            store.removeRecords(Array(records.dropFirst(maxRecords)))
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
        guard var record = store.loadRecords().first(where: { $0.id == id }) else {
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
        guard let record = store.loadRecords().first(where: { $0.id == id }) else {
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
        guard var record = store.loadRecords().first(where: { $0.id == id }) else {
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
        guard var record = store.loadRecords().first(where: { $0.id == id }) else {
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

    func getAllRecordSummaries() -> [ScoreboardRecordSummary] {
        loadAllRecords().filter { $0.status.isHistorical }.map { ScoreboardRecordSummary(from: $0) }
    }

    func getRecordById(_ id: String) -> ScoreboardRecord? {
        loadAllRecords().first { $0.id == id }
    }

    func deleteRecord(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        migrateIfNeeded()
        guard store.delete(id: id) else { return false }
        AppAnalytics.track(.deleteRecords, parameters: [
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
        let records = store.loadRecords()
        // Remove the legacy aggregate before rebuilding the empty v4 store so
        // a later migration cannot restore records the user just cleared.
        defaults.removeObject(forKey: recordsKey)
        do {
            try store.clearAllStoredData()
        } catch {
            return false
        }
        if !records.isEmpty {
            AppAnalytics.track(.deleteRecords, parameters: [
                .recordType: .string("scoreboard"),
                .actionName: .string("clear_all"),
                .result: .string(AnalyticsResult.success.rawValue)
            ])
        }
        notifyRecordsChanged()
        return store.loadRecords().isEmpty
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
