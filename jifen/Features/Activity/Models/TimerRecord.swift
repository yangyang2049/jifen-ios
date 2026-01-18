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


// A dummy view model for timer records
class TimerRecordsViewModel: ObservableObject {
    static let shared = TimerRecordsViewModel()
    
    @Published var records: [GameRecordSummary] = []
    @Published var groupedRecords: [RecordGroup] = []
    
    private init() {

        groupRecords()
    }
    
    func deleteRecord(_ id: String) -> Bool {
        let originalCount = records.count
        records.removeAll { $0.id == id }
        if records.count < originalCount {
            groupRecords()
            return true
        }
        return false
    }
    
    private func groupRecords() {
        let groupedByDate = Dictionary(grouping: records) { $0.date }
        
        self.groupedRecords = groupedByDate.map { date, records in
            RecordGroup(id: date, date: date, displayDate: formatDisplayDate(date), records: records.sorted(by: { $0.timestamp > $1.timestamp }))
        }.sorted(by: { $0.date > $1.date })
    }
}
