//
//  ScoreboardRecordManager.swift
//  jifen
//
//  Schema-v4 record persistence. Full records live in individual atomic JSON
//  files; UserDefaults only keeps the unfinished-record pointer and migration
//  source for older installations.
//

import Foundation
import PersistenceCore

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
            for var record in oldRecords {
                record.schemaVersion = 4
                let detailed = record.detailedActions ?? ScoreboardRecordActionAdapter.actions(for: record)
                record.detailedActions = detailed
                record.setResults = record.setResults ?? ScoreboardRecordActionAdapter.setResults(from: detailed)
                try writeRecord(record)
            }
            let recoveredIDs = Set(loadRecords().map(\.id))
            guard recoveredIDs == Set(oldRecords.map(\.id)) else {
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
            records.append(record)
        }

        records.sort { $0.startTime > $1.startTime }
        if indexNeedsRepair { try? writeIndex(for: records) }
        return records
    }

    func save(_ record: ScoreboardRecord) throws {
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
                return try? decoder.decode(ScoreboardRecord.self, from: data)
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
    private let unfinishedRecordIdKey = "scoreboard_unfinished_record_id"
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
    }

    func saveScoreboardRecord(_ input: ScoreboardRecord) throws {
        lock.lock()
        defer { lock.unlock() }
        migrateIfNeeded()

        var record = input
        record.schemaVersion = 4
        if record.detailedActions == nil {
            record.detailedActions = ScoreboardRecordActionAdapter.actions(for: record)
        }
        if record.setResults == nil, let detailedActions = record.detailedActions {
            record.setResults = ScoreboardRecordActionAdapter.setResults(from: detailedActions)
        }

        var records = store.loadRecords()
        if record.status == .draft {
            if let previousDraftId = getUnfinishedRecordId(), previousDraftId != record.id {
                _ = store.delete(id: previousDraftId)
                records.removeAll { $0.id == previousDraftId }
            }
            defaults.set(record.id, forKey: unfinishedRecordIdKey)
            // Keep Resume GameBar singular across v1 drafts and v2 live sessions.
            discardConflictingLiveSessions(keeping: UUID(uuidString: record.id))
        } else if getUnfinishedRecordId() == record.id {
            defaults.removeObject(forKey: unfinishedRecordIdKey)
        }

        try store.save(record)
        records.removeAll { $0.id == record.id }
        records.append(record)
        records.sort { $0.startTime > $1.startTime }
        if records.count > maxRecords {
            store.removeRecords(Array(records.dropFirst(maxRecords)))
        }
        RecordSyncOutbox.shared.enqueueUpsert(record)
    }

    func loadAllRecords() -> [ScoreboardRecord] {
        lock.lock()
        defer { lock.unlock() }
        migrateIfNeeded()
        return store.loadRecords()
    }

    func getAllRecordSummaries() -> [ScoreboardRecordSummary] {
        loadAllRecords().filter { $0.status == .finished }.map { ScoreboardRecordSummary(from: $0) }
    }

    func getRecordById(_ id: String) -> ScoreboardRecord? {
        loadAllRecords().first { $0.id == id }
    }

    func getUnfinishedRecordId() -> String? {
        defaults.string(forKey: unfinishedRecordIdKey)
    }

    func getUnfinishedRecord() -> ScoreboardRecord? {
        let records = loadAllRecords()
        if let id = getUnfinishedRecordId(),
           let record = records.first(where: { $0.id == id && $0.status == .draft }) {
            return record
        }
        if let fallback = records.first(where: { $0.status == .draft }) {
            defaults.set(fallback.id, forKey: unfinishedRecordIdKey)
            return fallback
        }
        return nil
    }

    @discardableResult
    func discardUnfinishedRecord() -> Bool {
        guard let id = getUnfinishedRecordId() else { return false }
        let deleted = deleteRecord(id)
        defaults.removeObject(forKey: unfinishedRecordIdKey)
        return deleted
    }

    func deleteRecord(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        migrateIfNeeded()
        guard store.delete(id: id) else { return false }
        RecordSyncOutbox.shared.enqueueDelete(recordID: id)
        if getUnfinishedRecordId() == id { defaults.removeObject(forKey: unfinishedRecordIdKey) }
        return true
    }

    func clearAllRecords() {
        lock.lock()
        defer { lock.unlock() }
        let records = store.loadRecords()
        records.forEach { RecordSyncOutbox.shared.enqueueDelete(recordID: $0.id) }
        store.removeRecords(records)
        defaults.removeObject(forKey: unfinishedRecordIdKey)
    }

    private func discardConflictingLiveSessions(keeping sessionId: UUID?) {
        Task {
            let repository = SessionArchiveRepository()
            if let sessionId {
                try? await repository.discardOtherLiveSessions(except: sessionId)
            } else {
                try? await repository.discardAllLiveSessions()
            }
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
