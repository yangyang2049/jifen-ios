//
//  TimerRecordManager.swift
//  jifen
//
//  计时记录持久化，与 ScoreboardRecordManager 对齐。
//

import Foundation

final class TimerRecordManager {
    static let shared = TimerRecordManager()

    private let key = "timer_records"
    private let maxRecords = 500

    private init() {}

    func getRecords() -> [GameRecordSummary] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        do {
            let decoder = JSONDecoder()
            let list = try decoder.decode([GameRecordSummary].self, from: data)
            return list.sorted { $0.timestamp > $1.timestamp }
        } catch {
            #if DEBUG
            print("[TimerRecordManager] decode error: \(error)")
            #endif
            return []
        }
    }

    func saveRecords(_ records: [GameRecordSummary]) {
        let toSave = Array(records.sorted { $0.timestamp > $1.timestamp }.prefix(maxRecords))
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(toSave)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            #if DEBUG
            print("[TimerRecordManager] encode error: \(error)")
            #endif
        }
    }

    func addRecord(_ record: GameRecordSummary) {
        var list = getRecords()
        list.removeAll { $0.id == record.id }
        list.insert(record, at: 0)
        saveRecords(list)
    }

    func deleteRecord(_ id: String) -> Bool {
        var list = getRecords()
        let before = list.count
        list.removeAll { $0.id == id }
        if list.count < before {
            saveRecords(list)
            return true
        }
        return false
    }

    func clearAllRecords() -> Bool {
        saveRecords([])
        return true
    }
}
