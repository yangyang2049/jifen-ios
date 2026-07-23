import Foundation
import SwiftUI
import Observation

@Observable
final class ScoreboardRecordsViewModel {
    static let shared = ScoreboardRecordsViewModel()
    
    var records: [ScoreboardRecordSummary] = []
    private(set) var groupedRecords: [ScoreboardRecordGroup] = []
    private(set) var isLoading: Bool = false
    
    private var lastRefreshTime: TimeInterval = 0
    private let refreshDebounceTime: TimeInterval = 1.0 // 1秒防抖
    
    private init() {
        loadRecordsInBackground()
    }
    
    // MARK: - Refresh Records
    
    func refreshRecords() {
        let now = Date().timeIntervalSince1970
        
        // 防抖：如果距离上次刷新小于1秒，则跳过
        if now - lastRefreshTime < refreshDebounceTime {
            return
        }
        
        lastRefreshTime = now
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let summaries = ScoreboardRecordManager.shared.getAllRecordSummaries()
            let grouped = self.groupRecordsByDate(summaries)
            DispatchQueue.main.async {
                self.records = summaries
                self.groupedRecords = grouped
                self.isLoading = false
            }
        }
    }
    
    func loadRecordsInBackground() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.refreshRecords()
        }
    }

    func refreshRecordsImmediately() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let summaries = ScoreboardRecordManager.shared.getAllRecordSummaries()
            let grouped = self.groupRecordsByDate(summaries)
            DispatchQueue.main.async {
                self.records = summaries
                self.groupedRecords = grouped
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Get Records
    // These getters can be removed if direct access to @Published properties is preferred,
    // but keeping them doesn't hurt.
    func getRecords() -> [ScoreboardRecordSummary] {
        return records
    }
    
    func getGroupedRecords() -> [ScoreboardRecordGroup] {
        return groupedRecords
    }
    
    func getIsLoading() -> Bool {
        return isLoading
    }
    
    // MARK: - Delete Record

    func deleteRecord(_ id: String) -> Bool {
        let success = ScoreboardRecordManager.shared.deleteRecord(id)
        if success {
            refreshRecordsImmediately()
        }
        return success
    }
    
    // MARK: - Group Records
    
    private func groupRecordsByDate(_ records: [ScoreboardRecordSummary]) -> [ScoreboardRecordGroup] {
        var groups: [String: [ScoreboardRecordSummary]] = [:]
        
        for record in records {
            if groups[record.date] == nil {
                groups[record.date] = []
            }
            groups[record.date]?.append(record)
        }
        
        var result: [ScoreboardRecordGroup] = []
        let sortedDates = groups.keys.sorted(by: >) // Newest first
        
        for date in sortedDates {
            guard let recordsForDate = groups[date]?.sorted(by: { $0.timestamp > $1.timestamp }) else {
                continue // Skip if somehow the group doesn't exist
            }
            let displayDate = formatDisplayDate(date)
            result.append(ScoreboardRecordGroup(
                id: date,
                date: date,
                displayDate: displayDate,
                records: recordsForDate
            ))
        }
        
        return result
    }
}
