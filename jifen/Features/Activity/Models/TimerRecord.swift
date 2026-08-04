import Foundation
import Combine

// GameRecordSummary is defined in HomeModels.swift
// This file uses that shared definition

// Represents a group of timer records, grouped by date
struct RecordGroup: Identifiable {
    let id: String
    let date: String
    let displayDate: String
    var records: [GameRecordSummary]
}


// View model for timer records，从 TimerRecordManager 持久化读写
class TimerRecordsViewModel: ObservableObject {
    static let shared = TimerRecordsViewModel()

    typealias RecordsLoader = () -> [GameRecordSummary]

    @Published var records: [GameRecordSummary] = []
    @Published var groupedRecords: [RecordGroup] = []
    private(set) var hasLoaded = false
    private let recordsLoader: RecordsLoader

    init(
        recordsLoader: @escaping RecordsLoader = {
            TimerRecordManager.shared.getRecords()
        }
    ) {
        self.recordsLoader = recordsLoader
    }

    func ensureLoaded() {
        guard !hasLoaded else { return }
        loadFromStorage()
    }

    func loadFromStorage() {
        records = recordsLoader()
        groupRecords()
        hasLoaded = true
    }

    func addRecord(_ record: GameRecordSummary) {
        TimerRecordManager.shared.addRecord(record)
        loadFromStorage()
    }

    func deleteRecord(_ id: String) -> Bool {
        let ok = TimerRecordManager.shared.deleteRecord(id)
        if ok { loadFromStorage() }
        return ok
    }

    private func groupRecords() {
        let groupedByDate = Dictionary(grouping: records) { $0.date }
        
        self.groupedRecords = groupedByDate.map { date, records in
            RecordGroup(id: date, date: date, displayDate: formatDisplayDate(date), records: records.sorted(by: { $0.timestamp > $1.timestamp }))
        }.sorted(by: { $0.date > $1.date })
    }
}
