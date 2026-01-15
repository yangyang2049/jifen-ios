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
    private let maxRecords = 1000 // Maximum number of records to keep
    
    private init() {}
    
    // MARK: - Save Record
    
    func saveScoreboardRecord(_ record: ScoreboardRecord) throws {
        var records = loadAllRecords()
        
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
        
        print("[ScoreboardRecordManager] ✅ Saved record: \(record.id)")
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
            print("[ScoreboardRecordManager] ❌ Failed to load records: \(error)")
            return []
        }
    }
    
    func getAllRecordSummaries() -> [ScoreboardRecordSummary] {
        let records = loadAllRecords()
        return records.map { ScoreboardRecordSummary(from: $0) }
    }
    
    func getRecordById(_ id: String) -> ScoreboardRecord? {
        let records = loadAllRecords()
        return records.first { $0.id == id }
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
                print("[ScoreboardRecordManager] ✅ Deleted record: \(id)")
                return true
            } catch {
                print("[ScoreboardRecordManager] ❌ Failed to delete record: \(error)")
                return false
            }
        }
        
        return false
    }
    
    // MARK: - Clear All
    
    func clearAllRecords() {
        UserDefaults.standard.removeObject(forKey: recordsKey)
        print("[ScoreboardRecordManager] ✅ Cleared all records")
    }
}

