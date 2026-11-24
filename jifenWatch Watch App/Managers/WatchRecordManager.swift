import Foundation
import LinkCore

enum WatchRecordSyncState: String, Codable {
    case pending
    case sent
}

final class WatchRecordManager {
    static let shared = WatchRecordManager()

    /// 记录体量随 detailedActions 增长（长局单条可达数十 KB，500 条上限下
    /// UserDefaults blob 会逼近 watchOS 配额），改为 Application Support 单文件
    /// 存储、原子写入；首次启动自动迁移旧 defaults 数据。
    private static let legacyRecordsKey = "watch_scoreboard_records"
    private let syncStatesKey = "watch_record_sync_states"
    private let maxRecords = 500
    /// Injected by Watch app so save can auto-transfer to phone without creating a second WCSession.
    var recordTransferHandler: ((WatchRecordTransferPayload) -> Void)?

    /// 内存缓存：loadAllRecords() 每次都会 JSON 解码整个数组（最多 500 条），
    /// 而记录列表、详情页、保存路径都会反复调用它。缓存后避免重复解码。
    /// 串行队列保证缓存与文件互斥，使列表页可以放心在后台读取。
    private let queue = DispatchQueue(
        label: "com.douhua.jifen.watch.record-store",
        qos: .userInitiated
    )
    private let storeURL: URL
    private var cachedRecords: [WatchScoreboardRecord]?

    private init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        try? FileManager.default.createDirectory(
            at: applicationSupport,
            withIntermediateDirectories: true
        )
        storeURL = applicationSupport.appendingPathComponent(
            "watch_scoreboard_records.json",
            isDirectory: false
        )
    }

    /// 外部写入或测试需要重读时调用。
    func invalidateCache() {
        queue.sync { cachedRecords = nil }
    }

    func saveRecord(_ record: WatchScoreboardRecord, transferToPhone: Bool = true) {
        let payload: WatchRecordTransferPayload? = queue.sync {
            var records = cachedRecords ?? loadFromDiskLocked()
            records.removeAll { $0.id == record.id }
            records.append(record)
            records.sort { $0.startTime > $1.startTime }
            if records.count > maxRecords {
                records = Array(records.prefix(maxRecords))
            }
            persistToDiskLocked(records)
            cachedRecords = records
            pruneSyncStatesLocked(validIDs: Set(records.map(\.id)))
            return transferPayload(for: record)
        }

        if transferToPhone, WatchPreferences.shared.recordAutoSyncEnabled, let payload {
            setSyncState(.pending, for: record.id)
            #if DEBUG
            print("[WatchRecord] autoTransferToPhone triggered: record=\(record.id) gameType=\(record.gameType.rawValue)")
            print("[WatchRecord] recordTransferHandler is nil? \(recordTransferHandler == nil)")
            #endif
            recordTransferHandler?(payload)
        }
    }

    // MARK: - Sync state

    func syncState(for recordID: String) -> WatchRecordSyncState? {
        queue.sync {
            loadSyncStatesLocked()[recordID].flatMap(WatchRecordSyncState.init(rawValue:))
        }
    }

    func setSyncState(_ state: WatchRecordSyncState, for recordID: String) {
        queue.sync {
            var states = loadSyncStatesLocked()
            states[recordID] = state.rawValue
            saveSyncStatesLocked(states)
        }
    }

    func markSynced(ids: [String]) {
        guard !ids.isEmpty else { return }
        queue.sync {
            var states = loadSyncStatesLocked()
            for id in ids {
                states[id] = WatchRecordSyncState.sent.rawValue
            }
            saveSyncStatesLocked(states)
        }
    }

    /// Manual "sync now" from the record detail. Returns false when the record
    /// is a watch-only tool session or the payload cannot be rebuilt.
    @discardableResult
    func requestTransfer(recordID: String) -> Bool {
        guard let payload = queue.sync(execute: { loadAllRecordsLocked() })
            .first(where: { $0.id == recordID })
            .flatMap({ transferPayload(for: $0) }) else { return false }
        setSyncState(.pending, for: recordID)
        recordTransferHandler?(payload)
        return true
    }

    private func loadSyncStatesLocked() -> [String: String] {
        WatchPreferences.shared.stringDictionary(forKey: syncStatesKey) ?? [:]
    }

    private func saveSyncStatesLocked(_ states: [String: String]) {
        WatchPreferences.shared.setStringDictionary(states, forKey: syncStatesKey)
    }

    /// 只保留仍存在的记录的同步状态，避免字典随删除记录无限增长；
    /// 此前的“超限全清”会把所有记录的已同步标记一次性抹掉。
    private func pruneSyncStatesLocked(validIDs: Set<String>) {
        var states = loadSyncStatesLocked()
        let before = states.count
        states = states.filter { validIDs.contains($0.key) }
        guard states.count != before else { return }
        saveSyncStatesLocked(states)
    }

    func transferPayload(for record: WatchScoreboardRecord) -> WatchRecordTransferPayload? {
        // Basketball training / counter are local tool sessions — keep them watch-only.
        guard record.gameType != .basketballTraining, record.gameType != .counter else { return nil }
        return WatchRecordTransferPayload(
            id: record.id,
            gameType: record.gameType.rawValue,
            startTimeEpochMilliseconds: Int64(record.startTime.timeIntervalSince1970 * 1000),
            endTimeEpochMilliseconds: Int64(record.endTime.timeIntervalSince1970 * 1000),
            durationSeconds: record.duration,
            team1Name: record.team1Name,
            team2Name: record.team2Name,
            team1FinalScore: record.team1FinalScore,
            team2FinalScore: record.team2FinalScore,
            team1SetScore: record.team1SetScore,
            team2SetScore: record.team2SetScore,
            winner: record.winner,
            actions: record.actions.map(\.description),
            detailedActions: record.actions.map(\.detailedAction),
            totalScoreChanges: record.totalScoreChanges,
            participants: record.participants?.map {
                WatchRecordParticipantPayload(name: $0.name, score: $0.score)
            },
            projectConfiguration: record.projectConfiguration
        )
    }

    func loadAllRecords() -> [WatchScoreboardRecord] {
        queue.sync { loadAllRecordsLocked() }
    }

    /// 后台线程读取摘要；完成回调在主线程。列表页用它避免首载解码阻塞 UI。
    func loadSummaries(onComplete: @escaping ([WatchScoreboardRecordSummary]) -> Void) {
        queue.async {
            let summaries = self.loadAllRecordsLocked().map {
                WatchScoreboardRecordSummary(from: $0)
            }
            DispatchQueue.main.async {
                onComplete(summaries)
            }
        }
    }

    func getSummaries() -> [WatchScoreboardRecordSummary] {
        loadAllRecords().map { WatchScoreboardRecordSummary(from: $0) }
    }

    func getRecord(id: String) -> WatchScoreboardRecord? {
        loadAllRecords().first { $0.id == id }
    }

    func deleteRecord(id: String) -> Bool {
        let deleted: Bool = queue.sync {
            var records = cachedRecords ?? loadFromDiskLocked()
            let originalCount = records.count
            records.removeAll { $0.id == id }
            guard records.count < originalCount else { return false }
            persistToDiskLocked(records)
            cachedRecords = records
            pruneSyncStatesLocked(validIDs: Set(records.map(\.id)))
            return true
        }
        return deleted
    }

    func clearAllRecords() -> Bool {
        let cleared: Bool = queue.sync {
            do {
                try JSONEncoder().encode([WatchScoreboardRecord]()).write(
                    to: storeURL,
                    options: .atomic
                )
                cachedRecords = []
                WatchPreferences.shared.remove(forKey: syncStatesKey)
                return true
            } catch {
                #if DEBUG
                print("[WatchRecordManager] Failed to clear records: \(error)")
                #endif
                return false
            }
        }
        return cleared
    }

    // MARK: - Disk store

    private func loadAllRecordsLocked() -> [WatchScoreboardRecord] {
        if let cachedRecords {
            return cachedRecords
        }
        let records = loadFromDiskLocked()
        cachedRecords = records
        return records
    }

    /// 旧 defaults blob 存在时迁移到文件；此后文件是唯一事实来源。
    private func loadFromDiskLocked() -> [WatchScoreboardRecord] {
        if let data = try? Data(contentsOf: storeURL), !data.isEmpty {
            return decodeRecords(data)
        }
        if let data = WatchPreferences.shared.data(forKey: Self.legacyRecordsKey) {
            let records = decodeRecords(data)
            if persistToDiskLocked(records) {
                WatchPreferences.shared.remove(forKey: Self.legacyRecordsKey)
                #if DEBUG
                print("[WatchRecordManager] migrated \(records.count) records from UserDefaults to \(storeURL.lastPathComponent)")
                #endif
            }
            return records
        }
        return []
    }

    private func decodeRecords(_ data: Data) -> [WatchScoreboardRecord] {
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

    @discardableResult
    private func persistToDiskLocked(_ records: [WatchScoreboardRecord]) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(records).write(to: storeURL, options: .atomic)
            return true
        } catch {
            #if DEBUG
            print("[WatchRecordManager] Failed to save record: \(error)")
            #endif
            return false
        }
    }
}
