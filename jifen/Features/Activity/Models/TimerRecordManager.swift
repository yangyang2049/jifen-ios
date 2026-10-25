//
//  TimerRecordManager.swift
//  jifen
//
//  Timer history uses individual atomic files, with a lossless migration from
//  the legacy UserDefaults aggregate. History is never truncated by a UI cap.
//

import Foundation

final class TimerRecordManager {
    static let shared = TimerRecordManager(
        defaults: AppTestRuntime.persistenceDefaults,
        rootURL: AppTestRuntime.storageRootURL?.appendingPathComponent("TimerRecords-v2", isDirectory: true)
    )

    private let key = "timer_records"
    private let defaults: UserDefaults
    private let rootURL: URL
    private let lock = NSRecursiveLock()
    private var cachedRecords: [String: GameRecordSummary]?

    init(defaults: UserDefaults = .standard, rootURL: URL? = nil) {
        self.defaults = defaults
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.rootURL = rootURL ?? support
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.douhua.jifen", isDirectory: true)
            .appendingPathComponent("TimerRecords-v2", isDirectory: true)
    }

    func getRecords() -> [GameRecordSummary] {
        lock.lock()
        defer { lock.unlock() }
        do { return try loadRecords().values.sorted { $0.timestamp > $1.timestamp } }
        catch { report(error); return [] }
    }

    func getRecordsInBackground() async -> [GameRecordSummary] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.getRecords())
            }
        }
    }

    func saveRecords(_ records: [GameRecordSummary]) {
        lock.lock()
        defer { lock.unlock() }
        do {
            let previous = try loadRecords()
            var next: [String: GameRecordSummary] = [:]
            for record in records {
                try write(record)
                next[record.id] = record
            }
            for id in previous.keys where next[id] == nil {
                try FileManager.default.removeItem(at: recordURL(id))
            }
            cachedRecords = next
        } catch { cachedRecords = nil; report(error) }
    }

    @MainActor
    func addRecord(_ record: GameRecordSummary, identity: ParticipantIdentityStore? = nil) {
        lock.lock()
        defer { lock.unlock() }
        do {
            var records = try loadRecords()
            try write(record)
            records[record.id] = record
            cachedRecords = records
        } catch { report(error); return }
        // Bind the successful write before returning to the event loop. A
        // deferred task could otherwise attach this new ID after logout or an
        // account switch, making the previous account's timer visible there.
        try? (identity ?? .shared).registerRecord(record.id)
        if identity == nil { PersonalRecordsCloudSync.shared.schedule() }
    }

    @MainActor
    func deleteRecord(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        do {
            var records = try loadRecords()
            guard records[id] != nil else { return false }
            try FileManager.default.removeItem(at: recordURL(id))
            records.removeValue(forKey: id)
            cachedRecords = records
        } catch { report(error); return false }
        PersonalRecordsCloudSync.shared.markDeleted(recordKey: id)
        return true
    }

    func clearAllRecords() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        do {
            if FileManager.default.fileExists(atPath: rootURL.path) {
                try FileManager.default.removeItem(at: rootURL)
            }
            defaults.removeObject(forKey: key)
            cachedRecords = [:]
            return true
        } catch { report(error); return false }
    }

    private func loadRecords() throws -> [String: GameRecordSummary] {
        if let cachedRecords { return cachedRecords }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let decoder = JSONDecoder()
        var records: [String: GameRecordSummary] = [:]
        for url in try FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
            where url.lastPathComponent.hasSuffix(".record.json") {
            if let data = try? Data(contentsOf: url), let record = try? decoder.decode(GameRecordSummary.self, from: data) {
                records[record.id] = record
            }
        }
        if let legacy = defaults.data(forKey: key) {
            if let legacyRecords = try? decoder.decode([GameRecordSummary].self, from: legacy) {
                for record in legacyRecords where records[record.id] == nil {
                    try write(record)
                    records[record.id] = record
                }
            } else {
                // Keep the exact corrupt source for recovery without blocking
                // new timer saves. Do not remove it until its backup is durable.
                try legacy.write(to: rootURL.appendingPathComponent("legacy-corrupt.json"), options: .atomic)
                report(CocoaError(.fileReadCorruptFile))
            }
            // Remove only after every record is durable; interrupted migration retries.
            defaults.removeObject(forKey: key)
        }
        cachedRecords = records
        return records
    }

    private func write(_ record: GameRecordSummary) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: recordURL(record.id), options: .atomic)
    }

    private func recordURL(_ id: String) -> URL {
        let safe = Data(id.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return rootURL.appendingPathComponent(safe + ".record.json")
    }

    private func report(_ error: Error) {
        #if DEBUG
        print("[TimerRecordManager] persistence error: \(error)")
        #endif
    }
}
