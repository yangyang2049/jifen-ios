import Foundation
import SwiftUI
import Combine // Import Combine for ObservableObject and Published

// Remove @Observable and conform to ObservableObject
final class ScoreboardRecordsViewModel: ObservableObject { // Add final and ObservableObject
    static let shared = ScoreboardRecordsViewModel()
    
    @Published var records: [ScoreboardRecordSummary] = [] // Add @Published
    @Published private(set) var groupedRecords: [ScoreboardRecordGroup] = [] // Add @Published
    @Published private(set) var isLoading: Bool = false // Add @Published
    
    private var listeners: [UUID: () -> Void] = [:]
    private var lastRefreshTime: TimeInterval = 0
    private let refreshDebounceTime: TimeInterval = 1.0 // 1秒防抖
    
    private init() {
        loadRecordsInBackground()
    }
    
    // MARK: - Listener Management
    // With @Published, listeners might not be strictly necessary for SwiftUI views,
    // but they can be kept for other parts of the app or specific use cases.
    func addListener(_ listener: @escaping () -> Void) -> UUID {
        let id = UUID()
        listeners[id] = listener
        return id
    }
    
    func removeListener(_ id: UUID) {
        listeners.removeValue(forKey: id)
    }
    
    private func notifyListeners() {
        // This will be handled automatically by @Published,
        // but if there are non-SwiftUI consumers of this ViewModel,
        // these listeners might still be relevant.
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
        
        isLoading = true // Will publish change
        // notifyListeners() // Not strictly needed for @Published
        
        // Use DispatchQueue.main.async for UI updates, but ensure data fetching is off main thread if heavy
        DispatchQueue.main.async {
            let summaries = ScoreboardRecordManager.shared.getAllRecordSummaries()
            self.records = summaries // Will publish change
            self.groupedRecords = self.groupRecordsByDate(summaries) // Will publish change
            self.isLoading = false // Will publish change
            // self.notifyListeners() // Not strictly needed for @Published
        }
    }
    
    func loadRecordsInBackground() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.refreshRecords()
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
