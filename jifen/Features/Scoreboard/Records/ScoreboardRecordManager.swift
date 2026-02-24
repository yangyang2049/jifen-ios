//
//  ScoreboardRecordManager.swift
//  jifen
//
//  Scoreboard record manager - handles saving and loading records
//

import Foundation

class ScoreboardRecordManager {
    static let shared = ScoreboardRecordManager()
    
    private let recordsKey = "scoreboard_records"
    private let unfinishedRecordIdKey = "scoreboard_unfinished_record_id"
    private let maxRecords = 1000 // Maximum number of records to keep
    
    private init() {}
    
    // MARK: - Save Record
    
    func saveScoreboardRecord(_ record: ScoreboardRecord) throws {
        var records = loadAllRecords()

        if record.status == .draft {
            if let previousDraftId = getUnfinishedRecordId(), previousDraftId != record.id {
                records.removeAll { $0.id == previousDraftId }
            }
            UserDefaults.standard.set(record.id, forKey: unfinishedRecordIdKey)
        } else if getUnfinishedRecordId() == record.id {
            UserDefaults.standard.removeObject(forKey: unfinishedRecordIdKey)
        }
        
        // Remove old record with same ID if exists
        records.removeAll { $0.id == record.id }
        
        // Add new record
        records.append(record)
        
        // Sort by start time (newest first)
        records.sort { $0.startTime > $1.startTime }
        
        // Limit number of records
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        
        // Save to UserDefaults
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(records)
        UserDefaults.standard.set(data, forKey: recordsKey)
        
        #if DEBUG
        print("[ScoreboardRecordManager] ✅ Saved record: \(record.id)")
        #endif
    }
    
    // MARK: - Load Records
    
    func loadAllRecords() -> [ScoreboardRecord] {
        guard let data = UserDefaults.standard.data(forKey: recordsKey) else {
            return []
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let records = try decoder.decode([ScoreboardRecord].self, from: data)
            return records
        } catch {
            #if DEBUG
            print("[ScoreboardRecordManager] ❌ Failed to load records: \(error)")
            #endif
            return []
        }
    }
    
    func getAllRecordSummaries() -> [ScoreboardRecordSummary] {
        let records = loadAllRecords()
        return records
            .filter { $0.status == .finished }
            .map { ScoreboardRecordSummary(from: $0) }
    }
    
    func getRecordById(_ id: String) -> ScoreboardRecord? {
        let records = loadAllRecords()
        return records.first { $0.id == id }
    }

    func getUnfinishedRecordId() -> String? {
        UserDefaults.standard.string(forKey: unfinishedRecordIdKey)
    }

    func getUnfinishedRecord() -> ScoreboardRecord? {
        let records = loadAllRecords()
        if let id = getUnfinishedRecordId(), let record = records.first(where: { $0.id == id && $0.status == .draft }) {
            return record
        }

        if let fallback = records.first(where: { $0.status == .draft }) {
            UserDefaults.standard.set(fallback.id, forKey: unfinishedRecordIdKey)
            return fallback
        }

        return nil
    }

    @discardableResult
    func discardUnfinishedRecord() -> Bool {
        guard let unfinishedId = getUnfinishedRecordId() else {
            return false
        }
        let deleted = deleteRecord(unfinishedId)
        UserDefaults.standard.removeObject(forKey: unfinishedRecordIdKey)
        return deleted
    }
    
    // MARK: - Delete Record
    
    func deleteRecord(_ id: String) -> Bool {
        var records = loadAllRecords()
        let originalCount = records.count
        records.removeAll { $0.id == id }
        
        if records.count < originalCount {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(records)
                UserDefaults.standard.set(data, forKey: recordsKey)
                if getUnfinishedRecordId() == id {
                    UserDefaults.standard.removeObject(forKey: unfinishedRecordIdKey)
                }
                #if DEBUG
                print("[ScoreboardRecordManager] ✅ Deleted record: \(id)")
                #endif
                return true
            } catch {
                #if DEBUG
                print("[ScoreboardRecordManager] ❌ Failed to delete record: \(error)")
                #endif
                return false
            }
        }
        
        return false
    }
    
    // MARK: - Clear All
    
    func clearAllRecords() {
        UserDefaults.standard.removeObject(forKey: recordsKey)
        UserDefaults.standard.removeObject(forKey: unfinishedRecordIdKey)
        #if DEBUG
        print("[ScoreboardRecordManager] ✅ Cleared all records")
        #endif
    }
}
