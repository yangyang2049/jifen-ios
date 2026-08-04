import Foundation
import Observation
import OSLog
import SwiftUI

@Observable
final class ScoreboardRecordsViewModel {
    static let shared = ScoreboardRecordsViewModel()

    typealias SummaryLoader = () -> [ScoreboardRecordSummary]

    var records: [ScoreboardRecordSummary] = []
    private(set) var groupedRecords: [ScoreboardRecordGroup] = []
    private(set) var isLoading: Bool = false
    private(set) var hasLoaded: Bool = false

    private static let startupLog = OSLog(
        subsystem: "com.douhua.jifen.ios",
        category: "Startup"
    )
    private let summaryLoader: SummaryLoader
    private let notificationCenter: NotificationCenter
    private var recordsChangedObserver: NSObjectProtocol?
    private var lastRefreshTime: TimeInterval = 0
    private let refreshDebounceTime: TimeInterval = 1.0 // 1秒防抖
    private var refreshAfterCurrentLoad = false

    init(
        summaryLoader: @escaping SummaryLoader = {
            ScoreboardRecordManager.shared.getAllRecordSummaries()
        },
        notificationCenter: NotificationCenter = .default
    ) {
        self.summaryLoader = summaryLoader
        self.notificationCenter = notificationCenter
        recordsChangedObserver = notificationCenter.addObserver(
            forName: .scoreboardRecordsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshRecordsImmediately()
            }
        }
    }

    deinit {
        if let recordsChangedObserver {
            notificationCenter.removeObserver(recordsChangedObserver)
        }
    }

    // MARK: - Refresh Records

    /// Loads the shared record summary exactly once for startup consumers.
    /// Explicit mutations continue to use the refresh methods below.
    func ensureLoaded() {
        guard !hasLoaded, !isLoading else { return }
        requestLoad()
    }

    func refreshRecords() {
        let now = Date().timeIntervalSince1970

        // 防抖：如果距离上次刷新小于1秒，则跳过
        if now - lastRefreshTime < refreshDebounceTime {
            return
        }

        lastRefreshTime = now
        requestLoad()
    }

    func refreshRecordsImmediately() {
        requestLoad()
    }

    private func requestLoad() {
        guard !isLoading else {
            refreshAfterCurrentLoad = true
            return
        }
        isLoading = true
        let loader = summaryLoader
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            os_signpost(
                .begin,
                log: Self.startupLog,
                name: "ScoreboardRecordSummaryLoad"
            )
            let summaries = loader()
            let grouped = Self.groupRecordsByDate(summaries)
            os_signpost(
                .end,
                log: Self.startupLog,
                name: "ScoreboardRecordSummaryLoad",
                "count=%{public}d",
                summaries.count
            )
            DispatchQueue.main.async {
                self.records = summaries
                self.groupedRecords = grouped
                self.isLoading = false
                self.hasLoaded = true
                guard self.refreshAfterCurrentLoad else { return }
                self.refreshAfterCurrentLoad = false
                self.requestLoad()
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
    
    private static func groupRecordsByDate(
        _ records: [ScoreboardRecordSummary]
    ) -> [ScoreboardRecordGroup] {
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
