//
//  ScoreboardRecordsViewModel.swift
//  jifen
//
//  Scoreboard records view model - manages loading and grouping records
//

import Foundation
import SwiftUI

@Observable
class ScoreboardRecordsViewModel {
    static let shared = ScoreboardRecordsViewModel()
    
    var records: [ScoreboardRecordSummary] = []
    private(set) var groupedRecords: [ScoreboardRecordGroup] = []
    private(set) var isLoading: Bool = false
    
    private var listeners: [UUID: () -> Void] = [:]
    private var lastRefreshTime: TimeInterval = 0
    private let refreshDebounceTime: TimeInterval = 1.0 // 1秒防抖
    
    private init() {
        loadRecordsInBackground()
    }
    
    // MARK: - Listener Management
    
    func addListener(_ listener: @escaping () -> Void) -> UUID {
        let id = UUID()
        listeners[id] = listener
        return id
    }
    
    func removeListener(_ id: UUID) {
        listeners.removeValue(forKey: id)
    }
    
    private func notifyListeners() {
        listeners.values.forEach { $0() }
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
        notifyListeners()
        
        DispatchQueue.main.async {
            let summaries = ScoreboardRecordManager.shared.getAllRecordSummaries()
            self.records = summaries
            self.groupedRecords = self.groupRecordsByDate(summaries)
            self.isLoading = false
            self.notifyListeners()
        }
    }
    
    func loadRecordsInBackground() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.refreshRecords()
        }
    }
    
    // MARK: - Get Records
    
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
            refreshRecords()
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
            let recordsForDate = groups[date]!.sorted { $0.timestamp > $1.timestamp }
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

