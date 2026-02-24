import Foundation

final class WatchRecordManager {
    static let shared = WatchRecordManager()

    private let recordsKey = "watch_scoreboard_records"
    private let maxRecords = 500

    private init() {}

    func saveRecord(_ record: WatchScoreboardRecord) {
        var records = loadAllRecords()
        records.removeAll { $0.id == record.id }
        records.append(record)
        records.sort { $0.startTime > $1.startTime }
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            UserDefaults.standard.set(data, forKey: recordsKey)
        } catch {
            #if DEBUG
            print("[WatchRecordManager] Failed to save record: \(error)")
            #endif
        }
    }

    func loadAllRecords() -> [WatchScoreboardRecord] {
        guard let data = UserDefaults.standard.data(forKey: recordsKey) else {
            return []
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([WatchScoreboardRecord].self, from: data)
        } catch {
            #if DEBUG
            print("[WatchRecordManager] Failed to load records: \(error)")
            #endif
            return []
        }
    }

    func getSummaries() -> [WatchScoreboardRecordSummary] {
        loadAllRecords().map { WatchScoreboardRecordSummary(from: $0) }
    }

    func getRecord(id: String) -> WatchScoreboardRecord? {
        loadAllRecords().first { $0.id == id }
    }

    func deleteRecord(id: String) -> Bool {
        var records = loadAllRecords()
        let originalCount = records.count
        records.removeAll { $0.id == id }
        guard records.count < originalCount else { return false }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            UserDefaults.standard.set(data, forKey: recordsKey)
            return true
        } catch {
            #if DEBUG
            print("[WatchRecordManager] Failed to delete record: \(error)")
            #endif
            return false
        }
    }

    func clearAllRecords() -> Bool {
        do {
            let data = try JSONEncoder().encode([WatchScoreboardRecord]())
            UserDefaults.standard.set(data, forKey: recordsKey)
            return true
        } catch {
            #if DEBUG
            print("[WatchRecordManager] Failed to clear records: \(error)")
            #endif
            return false
        }
    }
}
