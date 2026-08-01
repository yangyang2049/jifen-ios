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
}

enum ScoreboardPersistenceFailureReporter {
    private static let logger = Logger(
        subsystem: "com.douhua.jifen.ios",
        category: "ScoreboardPersistence"
    )
    private static let lock = NSLock()
    private nonisolated(unsafe) static var lastPresentationAt: Date?

    static func report(_ error: Error, context: String, forcePresentation: Bool = false) {
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
            scoreSummary: record.displayScore(),
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
}

enum ScoreboardLifecyclePersistence {
    static func save(_ record: ScoreboardRecord, finished: Bool) throws {
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
            let finishedRecords = oldRecords.filter { $0.status == .finished }
            for var record in finishedRecords {
                record.schemaVersion = 4
                let detailed = record.detailedActions ?? ScoreboardRecordActionAdapter.actions(for: record)
                record.detailedActions = detailed
                record.setResults = record.setResults ?? ScoreboardRecordActionAdapter.setResults(from: detailed)
                try writeRecord(record)
            }
            let recoveredIDs = Set(loadRecords().map(\.id))
            guard recoveredIDs == Set(finishedRecords.map(\.id)) else {
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
            if record.status == .finished {
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
        guard record.status == .finished else {
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
                      record.status == .finished else {
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

    func saveScoreboardRecord(_ input: ScoreboardRecord) throws {
        lock.lock()
        defer { lock.unlock() }
        migrateIfNeeded()
        guard input.status == .finished else {
            throw CocoaError(.fileWriteUnsupportedScheme)
        }

        var record = input
        record.schemaVersion = 4
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
        RecordSyncOutbox.shared.enqueueUpsert(record)
        AppAnalytics.scoreboardRecordSaved(record, previous: previousRecord)
        if let sessionId = ManualResumeSessionStore.sessionID(for: record.id) {
            Task {
                do {
                    try await ResumeSessionRepository().remove(sessionId: sessionId)
                } catch {
                    ScoreboardPersistenceFailureReporter.report(
                        error,
                        context: "remove finished resume session"
                    )
                }
            }
        }
    }

    func loadAllRecords() -> [ScoreboardRecord] {
        lock.lock()
        defer { lock.unlock() }
        migrateIfNeeded()
        return store.loadRecords().filter { $0.status == .finished }
    }

    func getAllRecordSummaries() -> [ScoreboardRecordSummary] {
        loadAllRecords().filter { $0.status == .finished }.map { ScoreboardRecordSummary(from: $0) }
    }

    func getRecordById(_ id: String) -> ScoreboardRecord? {
        loadAllRecords().first { $0.id == id }
    }

    func deleteRecord(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        migrateIfNeeded()
        guard store.delete(id: id) else { return false }
        RecordSyncOutbox.shared.enqueueDelete(recordID: id)
        AppAnalytics.track(.deleteRecords, parameters: [
            .recordType: .string("scoreboard"),
            .result: .string(AnalyticsResult.success.rawValue)
        ])
        return true
    }

    func clearAllRecords() {
        lock.lock()
        defer { lock.unlock() }
        let records = store.loadRecords()
        records.forEach { RecordSyncOutbox.shared.enqueueDelete(recordID: $0.id) }
        store.removeRecords(records)
        if !records.isEmpty {
            AppAnalytics.track(.deleteRecords, parameters: [
                .recordType: .string("scoreboard"),
                .actionName: .string("clear_all"),
                .result: .string(AnalyticsResult.success.rawValue)
            ])
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
