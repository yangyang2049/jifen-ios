import Foundation
import LinkCore
import RecordCore
import ScoreCore

enum WatchRecordSyncState: String, Codable {
    case pending
    case sent
}

/// `records/index.json` 的一行：摘要全字段 + 同步状态。
struct WatchRecordIndexEntry: Codable, Equatable {
    var summary: WatchScoreboardRecordSummary
    var syncState: WatchRecordSyncState?
    var fileIdentity: WatchRecordFileIdentity? = nil
}

struct WatchRecordFileIdentity: Codable, Equatable {
    let inode: UInt64
    let modifiedAt: TimeInterval

    init?(url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let inode = attributes[.systemFileNumber] as? NSNumber,
              let modifiedAt = attributes[.modificationDate] as? Date else { return nil }
        self.inode = inode.uint64Value
        self.modifiedAt = modifiedAt.timeIntervalSinceReferenceDate
    }
}

/// `records/<safe-id>.record.json` 的正文。syncState 与记录正文同文件持久化，
/// 这样 `index.json` 丢失后仍能从单记录文件重建完整的同步状态。
struct WatchRecordFileEntry: Codable {
    var record: WatchScoreboardRecord
    var syncState: WatchRecordSyncState?
}

/// 索引 + 单记录原子文件存储（与手机端 `ScoreboardRecordFileStore` 同构）：
/// - `records/index.json`：[WatchRecordIndexEntry]，列表/同步状态只读索引；
/// - `records/<safe-id>.record.json`：完整记录（含 actions），原子写入；
/// - 上限 500 条，淘汰时同步删除对应单记录文件；
/// - 索引丢失或损坏时扫描单记录文件重建（按 startTime 排序取最新 500），
///   部分写入/删除可互相恢复，删除与淘汰的记录不会复现。
/// 本存储为首发格式直接起算，不迁移任何旧版本地数据。
final class WatchRecordManager {
    static let shared = WatchRecordManager()

    private let maxRecords = 500
    /// Injected by Watch app so save can auto-transfer to phone without creating a second WCSession.
    var recordTransferHandler: ((WatchRecordTransferPayload) -> Void)?

    /// 测试注入点：返回 true 时模拟一次写盘失败（仅验证失败反馈路径）。
    var testWriteFailureHook: (() -> Bool)?

    /// 串行队列保证内存索引/缓存与磁盘互斥，使列表页可以放心在后台读取。
    private let queue = DispatchQueue(
        label: "com.douhua.jifen.watch.record-store",
        qos: .userInitiated
    )
    private let recordsDirectory: URL
    private var cachedIndex: [WatchRecordIndexEntry]?
    private var cachedRecords: [WatchScoreboardRecord]?

    init(directoryURL: URL? = nil) {
        let directory = directoryURL ?? WatchStorageContainer.shared.recordsDirectory
        self.recordsDirectory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var indexURL: URL {
        recordsDirectory.appendingPathComponent("index.json", isDirectory: false)
    }

    /// 外部写入或测试需要重读时调用。
    func invalidateCache() {
        queue.sync {
            cachedIndex = nil
            cachedRecords = nil
        }
    }

    @discardableResult
    func saveRecord(_ record: WatchScoreboardRecord, transferToPhone: Bool = true) -> Bool {
        let persisted = queue.sync { saveRecordLocked(record) }
        guard persisted else { return false }

        if transferToPhone, WatchPreferences.shared.recordAutoSyncEnabled,
           let payload = transferPayload(for: record) {
            setSyncState(.pending, for: record.id)
            #if DEBUG
            print("[WatchRecord] autoTransferToPhone triggered: record=\(record.id) gameType=\(record.gameType.rawValue)")
            print("[WatchRecord] recordTransferHandler is nil? \(recordTransferHandler == nil)")
            #endif
            recordTransferHandler?(payload)
        }
        return true
    }

    // MARK: - Sync state

    func syncState(for recordID: String) -> WatchRecordSyncState? {
        queue.sync {
            loadIndexLocked().first { $0.summary.id == recordID }?.syncState
        }
    }

    /// 真相源顺序：先写正文，成功后才提交索引。正文写失败时索引保持旧值
    /// （不出现「索引已改、正文仍旧」的分裂——索引丢失重建会读出旧状态）。
    func setSyncState(_ state: WatchRecordSyncState, for recordID: String) {
        queue.sync {
            var entries = loadIndexLocked()
            guard let index = entries.firstIndex(where: { $0.summary.id == recordID }),
                  updateRecordFileSyncStateLocked(recordID, state) else { return }
            entries[index].syncState = state
            entries[index].fileIdentity = fileIdentity(for: recordID)
            writeIndexLocked(entries)
            cachedIndex = entries
        }
    }

    func markSynced(ids: [String]) {
        guard !ids.isEmpty else { return }
        queue.sync {
            var entries = loadIndexLocked()
            let ids = Set(ids)
            var hasChanges = false
            for index in entries.indices {
                let id = entries[index].summary.id
                guard ids.contains(id), entries[index].syncState != .sent,
                      updateRecordFileSyncStateLocked(id, .sent) else { continue }
                entries[index].syncState = .sent
                entries[index].fileIdentity = fileIdentity(for: id)
                hasChanges = true
            }
            if hasChanges {
                writeIndexLocked(entries)
                cachedIndex = entries
            }
        }
    }

    /// Manual "sync now" from the record detail. Returns false when the record
    /// is a watch-only tool session or the payload cannot be rebuilt.
    @discardableResult
    func requestTransfer(recordID: String) -> Bool {
        guard let record = getRecord(id: recordID),
              let payload = transferPayload(for: record) else { return false }
        setSyncState(.pending, for: recordID)
        recordTransferHandler?(payload)
        return true
    }

    func transferPayload(for record: WatchScoreboardRecord) -> WatchRecordTransferPayload? {
        guard record.canonical.kind != .counter else { return nil }
        return record.canonical
    }

    func loadAllRecords() -> [WatchScoreboardRecord] {
        queue.sync { loadAllRecordsLocked() }
    }

    /// 后台线程读取摘要；完成回调在主线程。列表页用它避免首载解码阻塞 UI
    /// （摘要直接来自内存/磁盘索引，无需解码全部记录正文）。
    func loadSummaries(onComplete: @escaping ([WatchScoreboardRecordSummary]) -> Void) {
        queue.async {
            let summaries = self.loadIndexLocked().map(\.summary)
            DispatchQueue.main.async {
                onComplete(summaries)
            }
        }
    }

    func getSummaries() -> [WatchScoreboardRecordSummary] {
        queue.sync { loadIndexLocked().map(\.summary) }
    }

    /// 单条正文读取：不经全量解码（D4 列表只读轻量索引，详情按单条读取）。
    func getRecord(id: String) -> WatchScoreboardRecord? {
        queue.sync {
            guard loadIndexLocked().contains(where: { $0.summary.id == id }) else { return nil }
            return loadRecordFile(recordID: id)?.record
        }
    }

    @discardableResult
    func deleteRecord(id: String) -> Bool {
        queue.sync {
            var entries = loadIndexLocked()
            let recordFileURL = Self.recordFileURL(directory: recordsDirectory, id: id)
            let indexHit = entries.contains { $0.summary.id == id }
            let fileHit = FileManager.default.fileExists(atPath: recordFileURL.path)
            guard indexHit || fileHit else { return false }

            // 先删正文文件再写索引：正文删除失败必须如实返回失败（此时索引
            // 若先行收缩会导致“索引说没有、文件还在”的幽灵记录）；删除成功
            // 后任一后续中断都不会让已删记录复现（残留索引条目在读取时因缺
            // 文件被对账剔除）。
            if fileHit {
                do {
                    try FileManager.default.removeItem(at: recordFileURL)
                } catch {
                    #if DEBUG
                    print("[WatchRecordManager] Failed to delete record file: \(error)")
                    #endif
                    return false
                }
            }
            entries.removeAll { $0.summary.id == id }
            cachedIndex = entries
            cachedRecords = cachedRecords?.filter { $0.id != id }
            writeIndexLocked(entries)
            return true
        }
    }

    @discardableResult
    func clearAllRecords() -> Bool {
        queue.sync {
            do {
                let items = (try? FileManager.default.contentsOfDirectory(
                    at: recordsDirectory,
                    includingPropertiesForKeys: nil
                )) ?? []
                for item in items {
                    try FileManager.default.removeItem(at: item)
                }
                cachedIndex = []
                cachedRecords = []
                return true
            } catch {
                #if DEBUG
                print("[WatchRecordManager] Failed to clear records: \(error)")
                #endif
                cachedIndex = nil
                cachedRecords = nil
                return false
            }
        }
    }

    // MARK: - Index + single-record files

    private static func recordFileURL(directory: URL, id: String) -> URL {
        directory.appendingPathComponent(Self.safeFileName(for: id) + ".record.json", isDirectory: false)
    }

    /// 与 `FileLinkDataStore` 相同的安全文件名映射思路：白名单字符保留，
    /// 其余 percent-escape，限长，保证任意 record id 落成稳定文件名。
    private static let allowedFilenameCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"
    )

    private static func safeFileName(for id: String) -> String {
        let scalars = id.unicodeScalars.map { scalar -> String in
            allowedFilenameCharacters.contains(scalar)
                ? String(scalar)
                : String(format: "%%%02X", scalar.value)
        }
        let joined = scalars.joined()
        return joined.isEmpty ? "_" : String(joined.prefix(180))
    }

    private func fileIdentity(for id: String) -> WatchRecordFileIdentity? {
        WatchRecordFileIdentity(url: Self.recordFileURL(directory: recordsDirectory, id: id))
    }

    private func saveRecordLocked(_ record: WatchScoreboardRecord) -> Bool {
        var entries = loadIndexLocked()
        guard writeRecordFileLocked(record, syncState: nil) else { return false }
        cachedRecords = nil
        entries.removeAll { $0.summary.id == record.id }
        entries.append(WatchRecordIndexEntry(
            summary: WatchScoreboardRecordSummary(from: record),
            syncState: nil,
            fileIdentity: fileIdentity(for: record.id)
        ))
        entries.sort(by: Self.newestFirst)
        guard let kept = trimRecordsLocked(entries), writeIndexLocked(kept) else {
            cachedIndex = nil
            return false
        }
        cachedIndex = kept
        return true
    }

    private static func newestFirst(_ lhs: WatchRecordIndexEntry, _ rhs: WatchRecordIndexEntry) -> Bool {
        if lhs.summary.timestamp == rhs.summary.timestamp { return lhs.summary.id < rhs.summary.id }
        return lhs.summary.timestamp > rhs.summary.timestamp
    }

    private func trimRecordsLocked(_ sorted: [WatchRecordIndexEntry]) -> [WatchRecordIndexEntry]? {
        do {
            for entry in sorted.dropFirst(maxRecords) {
                try FileManager.default.removeItem(at: Self.recordFileURL(directory: recordsDirectory, id: entry.summary.id))
            }
            return Array(sorted.prefix(maxRecords))
        } catch {
            #if DEBUG
            print("[WatchRecordManager] Failed to evict record: \(error)")
            #endif
            return nil
        }
    }

    private func loadIndexLocked() -> [WatchRecordIndexEntry] {
        if let cachedIndex { return cachedIndex }
        let stored = (try? Data(contentsOf: indexURL)).flatMap {
            try? Self.decoder().decode([WatchRecordIndexEntry].self, from: $0)
        }
        let reconciled = reconcileIndexLocked(stored ?? [])
        if stored == nil || reconciled != stored {
            writeIndexLocked(reconciled)
        }
        cachedIndex = reconciled
        return reconciled
    }

    /// Atomic body writes change the file identity before the index is committed.
    /// Healthy entries are reused without reading action history.
    private func reconcileIndexLocked(_ entries: [WatchRecordIndexEntry]) -> [WatchRecordIndexEntry] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: recordsDirectory, includingPropertiesForKeys: nil
        ) else { return entries }
        let indexedByFilename = Dictionary(entries.map {
            (Self.recordFileURL(directory: recordsDirectory, id: $0.summary.id).lastPathComponent, $0)
        }, uniquingKeysWith: { first, _ in first })
        var reconciled = [WatchRecordIndexEntry]()
        for url in items where url.lastPathComponent.hasSuffix(".record.json") {
            let identity = WatchRecordFileIdentity(url: url)
            if let indexed = indexedByFilename[url.lastPathComponent],
               let identity, identity == indexed.fileIdentity {
                reconciled.append(indexed)
            } else if let file = try? Self.decoder().decode(WatchRecordFileEntry.self, from: Data(contentsOf: url)),
                      Self.recordFileURL(directory: recordsDirectory, id: file.record.id).lastPathComponent == url.lastPathComponent {
                reconciled.append(WatchRecordIndexEntry(
                    summary: WatchScoreboardRecordSummary(from: file.record),
                    syncState: file.syncState,
                    fileIdentity: identity
                ))
            }
        }
        reconciled.sort(by: Self.newestFirst)
        return trimRecordsLocked(reconciled) ?? Array(reconciled.prefix(maxRecords))
    }

    private func loadRecordFile(recordID: String) -> WatchRecordFileEntry? {
        let url = Self.recordFileURL(directory: recordsDirectory, id: recordID)
        guard let data = try? Data(contentsOf: url),
              let file = try? Self.decoder().decode(WatchRecordFileEntry.self, from: data),
              file.record.id == recordID else { return nil }
        return file
    }

    private func loadAllRecordsLocked() -> [WatchScoreboardRecord] {
        if let cachedRecords {
            return cachedRecords
        }
        let entries = loadIndexLocked()
        var records: [WatchScoreboardRecord] = []
        var missingIDs = false
        for entry in entries {
            guard let fileEntry = loadRecordFile(recordID: entry.summary.id) else {
                // 索引在先、正文写入中断：缺失的正文不会复现，索引侧剔除。
                missingIDs = true
                continue
            }
            records.append(fileEntry.record)
        }
        if missingIDs {
            let keptIDs = Set(records.map(\.id))
            let kept = entries.filter { keptIDs.contains($0.summary.id) }
            writeIndexLocked(kept)
            cachedIndex = kept
        }
        records.sort { $0.startTime > $1.startTime }
        cachedRecords = records
        return records
    }

    /// 同步状态变更同步写回单记录文件：index.json 丢失后的重建才能恢复
    /// pending/sent 状态（正文文件与索引持有同一份状态）。
    /// 正文侧同步状态更新（真相源）：失败必须返回 false，调用方据此回退索引，
    /// 杜绝「索引已改、正文仍旧」的分裂（索引丢失重建会读出旧状态）。
    @discardableResult
    private func updateRecordFileSyncStateLocked(_ id: String, _ state: WatchRecordSyncState?) -> Bool {
        let url = Self.recordFileURL(directory: recordsDirectory, id: id)
        guard let data = try? Data(contentsOf: url),
              var entry = try? Self.decoder().decode(WatchRecordFileEntry.self, from: data) else {
            return false
        }
        entry.syncState = state
        if testWriteFailureHook?() == true { return false }
        do {
            try Self.encoder().encode(entry).write(to: url, options: .atomic)
            return true
        } catch {
            #if DEBUG
            print("[WatchRecordManager] Failed to update record file sync state: \(error)")
            #endif
            return false
        }
    }

    private func writeRecordFileLocked(_ record: WatchScoreboardRecord, syncState: WatchRecordSyncState?) -> Bool {
        if testWriteFailureHook?() == true { return false }
        do {
            let entry = WatchRecordFileEntry(record: record, syncState: syncState)
            try Self.encoder().encode(entry).write(
                to: Self.recordFileURL(directory: recordsDirectory, id: record.id),
                options: .atomic
            )
            return true
        } catch {
            #if DEBUG
            print("[WatchRecordManager] Failed to save record: \(error)")
            #endif
            return false
        }
    }

    @discardableResult
    private func writeIndexLocked(_ entries: [WatchRecordIndexEntry]) -> Bool {
        if testWriteFailureHook?() == true { return false }
        do {
            try Self.encoder().encode(entries).write(to: indexURL, options: .atomic)
            return true
        } catch {
            #if DEBUG
            print("[WatchRecordManager] Failed to save record index: \(error)")
            #endif
            return false
        }
    }

    private static func encoder() -> JSONEncoder {
        JSONEncoder()
    }

    private static func decoder() -> JSONDecoder {
        JSONDecoder()
    }
}
