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
    @Published private(set) var hasLoaded = false
    @Published private(set) var isLoading = false
    private let recordsLoader: RecordsLoader
    private var reloadAfterCurrentLoad = false

    init(
        recordsLoader: @escaping RecordsLoader = {
            TimerRecordManager.shared.getRecords()
        }
    ) {
        self.recordsLoader = recordsLoader
    }

    func ensureLoaded() {
        guard !hasLoaded, !isLoading else { return }
        loadFromStorage()
    }

    func loadFromStorage() {
        guard !isLoading else { reloadAfterCurrentLoad = true; return }
        isLoading = true
        let loader = recordsLoader
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let records = loader()
            DispatchQueue.main.async {
                guard let self else { return }
                if self.reloadAfterCurrentLoad {
                    // A mutation invalidated this snapshot while disk I/O ran.
                    // Never briefly republish deleted data or migrate stale IDs.
                    self.reloadAfterCurrentLoad = false
                    self.isLoading = false
                    self.loadFromStorage()
                    return
                }
                self.records = records
                self.groupRecords()
                self.hasLoaded = true
                self.isLoading = false
            }
        }
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
