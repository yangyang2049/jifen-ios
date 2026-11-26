import XCTest
import RecordCore
import os
@testable import jifenWatch_Watch_App

/// 记录缓存行为测试：验证缓存命中、写后一致性，以及索引+单记录原子文件
/// 存储的重建、淘汰与持久化失败反馈。
final class WatchRecordCacheTests: XCTestCase {

    override func setUp() {
        super.setUp()
        WatchRecordManager.shared.clearAllRecords()
    }

    override func tearDown() {
        WatchRecordManager.shared.clearAllRecords()
        super.tearDown()
    }

    /// 每个用例独立的临时存储目录。
    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeRecord(
        id: String, score: Int, gameType: WatchGameType = .pingpong, startTime: Date = Date()
    ) -> WatchScoreboardRecord {
        WatchScoreboardRecord(canonical: CanonicalMatchRecord(
            id: id,
            kind: gameType.scoreCoreGameType.map(RecordGameKind.sport) ?? .counter,
            source: .watchLocal,
            startEpochMilliseconds: Int64((startTime.timeIntervalSince1970 * 1_000).rounded()),
            endEpochMilliseconds: Int64((Date().timeIntervalSince1970 * 1_000).rounded()),
            durationSeconds: 60,
            team1Name: "A",
            team2Name: "B",
            team1FinalScore: score,
            team2FinalScore: 0,
            team1SetScore: 1,
            team2SetScore: 0,
            winnerIdentity: .team(.team0),
            totalScoreChanges: score
        ))!
    }

    // MARK: - Pending finished records (file-backed resume store)

    @MainActor
    func testStandaloneFinishRetryAfterRestartKeepsOriginalRecord() throws {
        let directory = makeTemporaryDirectory()
        let record = makeRecord(id: "standalone-finish", score: 11)
        let first = WatchResumeSessionStore(directoryURL: directory)
        XCTAssertFalse(first.saveFinishedRecord(record) { _ in false })

        let restarted = WatchResumeSessionStore(directoryURL: directory)
        var savedIDs: [String] = []
        restarted.retryPendingFinishedRecords { recovered in
            XCTAssertEqual(recovered.team1FinalScore, 11)
            savedIDs.append(recovered.id)
            return true
        }
        restarted.retryPendingFinishedRecords { recovered in
            savedIDs.append(recovered.id)
            return true
        }
        XCTAssertEqual(savedIDs, [record.id])
    }

    @MainActor
    func testCancelTrainingFinishKeepsDraftAndDoesNotRetryOldScore() throws {
        let directory = makeTemporaryDirectory()
        let store = WatchResumeSessionStore(directoryURL: directory)
        let startTime = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down) + 0.12535)
        store.save(.init(
            startedAt: startTime, scoreLine: "1/1 = 100%", emoji: "🏀",
            payload: trainingResumeFixture(mode: .fixed2, startedAt: startTime)
        ))
        let training = makeRecord(id: "training", score: 1, gameType: .basketballTraining, startTime: startTime)
        let match = makeRecord(id: "other-match", score: 11, startTime: startTime)
        XCTAssertFalse(store.saveFinishedRecord(training) { _ in false })
        XCTAssertFalse(store.saveFinishedRecord(match) { _ in false })

        store.cancelPendingTrainingFinish(startedAt: startTime)

        let restarted = WatchResumeSessionStore(directoryURL: directory)
        XCTAssertEqual(restarted.session?.startedAt, startTime)
        var recoveredIDs: [String] = []
        restarted.retryPendingFinishedRecords {
            recoveredIDs.append($0.id)
            return true
        }
        XCTAssertEqual(recoveredIDs, [match.id])
        let revised = makeRecord(id: "training-revised", score: 2, gameType: .basketballTraining, startTime: startTime)
        XCTAssertTrue(restarted.saveFinishedRecord(revised) {
            XCTAssertEqual($0.id, revised.id)
            XCTAssertEqual($0.team1FinalScore, 2)
            return true
        })
        XCTAssertNil(restarted.session)
    }

    func testCounterFailedSaveKeepsCountUndoAndStartTimeUntilRetry() {
        var counter = WatchCounterSession()
        counter.increment()
        counter.increment()
        var initialRecord: WatchScoreboardRecord?
        XCTAssertFalse(counter.finish { record in
            initialRecord = record
            return false
        })

        XCTAssertEqual(counter.count, 2)
        XCTAssertTrue(counter.canUndo)
        counter.undo()
        XCTAssertEqual(counter.count, 1)
        counter.increment()
        XCTAssertTrue(counter.finish { record in
            XCTAssertEqual(record.team1FinalScore, 2)
            XCTAssertEqual(record.startTime, initialRecord?.startTime)
            return true
        })
        XCTAssertEqual(counter.count, 0)
        XCTAssertFalse(counter.canUndo)
    }

    func testRacketRecordFallsBackToPointsOnlyBeforeASetIsCompleted() {
        for game in [WatchGameType.pingpong, .badminton, .pickleball, .tennis, .shuttlecock, .squash, .foosball] {
            func record(setScore: Int) -> WatchScoreboardRecord {
                WatchScoreboardRecord(canonical: CanonicalMatchRecord(
                    id: UUID().uuidString, kind: .sport(game.scoreCoreGameType!), source: .watchLocal,
                    startEpochMilliseconds: 1_700_000_000_000, endEpochMilliseconds: 1_700_000_060_000,
                    durationSeconds: 60, team1Name: "A", team2Name: "B", team1FinalScore: 8,
                    team2FinalScore: 3, team1SetScore: setScore, team2SetScore: 0,
                    totalScoreChanges: 11
                ))!
            }
            let unfinishedSet = record(setScore: 0)
            XCTAssertTrue(unfinishedSet.usesPointScoreForDisplay, game.rawValue)
            XCTAssertEqual(WatchScoreboardRecordSummary(from: unfinishedSet).listDisplayText, "A 8 - 3 B")
            let completedSet = record(setScore: 2)
            XCTAssertFalse(completedSet.usesPointScoreForDisplay, game.rawValue)
            XCTAssertEqual(WatchScoreboardRecordSummary(from: completedSet).listDisplayText, "A 2 - 0 B")
        }
    }

    func testStoredCanonicalRecordIsTheExactTransferBodyAndUsesTypedWinner() throws {
        let directory = makeTemporaryDirectory()
        let manager = WatchRecordManager(directoryURL: directory)
        let point = DetailedScoreAction(
            type: .scoreChanged, epochMilliseconds: 1_700_000_000_250, team: .team2, scores: [0, 1]
        )
        let canonical = CanonicalMatchRecord(
            id: "typed-winner",
            kind: .sport(.badminton),
            source: .watchLocal,
            startEpochMilliseconds: 1_700_000_000_125,
            endEpochMilliseconds: 1_700_000_060_125,
            durationSeconds: 60,
            team1Name: "同名",
            team2Name: "同名",
            team1FinalScore: 0,
            team2FinalScore: 1,
            winnerIdentity: .team(.team1),
            detailedActions: [point]
        )
        let record = try XCTUnwrap(WatchScoreboardRecord(canonical: canonical))
        XCTAssertTrue(manager.saveRecord(record, transferToPhone: false))
        let file = directory.appendingPathComponent("typed-winner.record.json")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let body = try XCTUnwrap(json["record"] as? [String: Any])
        XCTAssertNil(body["canonical"])
        XCTAssertNil(body["gameType"])
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        XCTAssertEqual(try JSONDecoder().decode(CanonicalMatchRecord.self, from: bodyData), canonical)

        let restarted = WatchRecordManager(directoryURL: directory)
        let restored = try XCTUnwrap(restarted.getRecord(id: canonical.id))
        XCTAssertEqual(restarted.transferPayload(for: restored), canonical)
        XCTAssertFalse(restored.isWinner(at: 0))
        XCTAssertTrue(restored.isWinner(at: 1))
        XCTAssertEqual(restored.winnerName, "同名")
    }

    func testCounterRecordStaysLocal() throws {
        let manager = WatchRecordManager(directoryURL: makeTemporaryDirectory())
        let record = makeRecord(id: "counter-only", score: 3, gameType: .counter)
        XCTAssertTrue(manager.saveRecord(record, transferToPhone: false))
        let restored = try XCTUnwrap(manager.getRecord(id: record.id))
        XCTAssertEqual(restored.canonical.kind, .counter)
        XCTAssertNil(manager.transferPayload(for: restored))
        XCTAssertFalse(manager.requestTransfer(recordID: record.id))
    }

    // MARK: - Cache behavior

    func testLoadIsCachedAcrossCalls() {
        WatchRecordManager.shared.saveRecord(makeRecord(id: "r1", score: 5), transferToPhone: false)

        let first = WatchRecordManager.shared.loadAllRecords()
        let second = WatchRecordManager.shared.loadAllRecords()

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(first.first?.id, second.first?.id)
    }

    func testSaveInvalidatesCacheSoNewRecordIsVisible() {
        WatchRecordManager.shared.saveRecord(makeRecord(id: "r1", score: 5), transferToPhone: false)
        XCTAssertEqual(WatchRecordManager.shared.loadAllRecords().count, 1)

        WatchRecordManager.shared.saveRecord(makeRecord(id: "r2", score: 7), transferToPhone: false)
        let records = WatchRecordManager.shared.loadAllRecords()
        XCTAssertEqual(records.count, 2, "保存后缓存必须更新，不能返回旧数组")
        XCTAssertEqual(Set(records.map(\.id)), ["r1", "r2"])
    }

    func testDeleteInvalidatesCache() {
        WatchRecordManager.shared.saveRecord(makeRecord(id: "r1", score: 5), transferToPhone: false)
        WatchRecordManager.shared.saveRecord(makeRecord(id: "r2", score: 7), transferToPhone: false)

        XCTAssertTrue(WatchRecordManager.shared.deleteRecord(id: "r1"))
        let records = WatchRecordManager.shared.loadAllRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, "r2")
    }

    func testClearAllInvalidatesCache() {
        WatchRecordManager.shared.saveRecord(makeRecord(id: "r1", score: 5), transferToPhone: false)
        XCTAssertEqual(WatchRecordManager.shared.loadAllRecords().count, 1)

        XCTAssertTrue(WatchRecordManager.shared.clearAllRecords())
        XCTAssertTrue(WatchRecordManager.shared.loadAllRecords().isEmpty)
    }

    func testExternalInvalidateReloadsFromDisk() {
        WatchRecordManager.shared.saveRecord(makeRecord(id: "r1", score: 5), transferToPhone: false)
        XCTAssertEqual(WatchRecordManager.shared.loadAllRecords().count, 1)

        // 模拟外部（如另一进程写入）后强制重读
        WatchRecordManager.shared.invalidateCache()
        XCTAssertEqual(WatchRecordManager.shared.loadAllRecords().count, 1)
    }

    // MARK: - Index + single-record files

    /// 删除 index.json 后，从单记录文件目录全量重建：记录内容与 syncState 恢复。
    func testIndexRebuildRestoresRecordsAndSyncStatesFromSingleFiles() throws {
        let directory = makeTemporaryDirectory()
        let manager = WatchRecordManager(directoryURL: directory)
        let base = Date(timeIntervalSince1970: 1_000_000)
        for index in 0..<3 {
            XCTAssertTrue(manager.saveRecord(
                makeRecord(id: "rebuild-\(index)", score: index, startTime: base.addingTimeInterval(Double(index))),
                transferToPhone: false
            ))
        }
        manager.setSyncState(.sent, for: "rebuild-1")
        manager.setSyncState(.pending, for: "rebuild-2")

        let indexURL = directory.appendingPathComponent("index.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL.path))
        try FileManager.default.removeItem(at: indexURL)

        let restarted = WatchRecordManager(directoryURL: directory)
        let records = restarted.loadAllRecords()
        XCTAssertEqual(records.map(\.id).sorted(), ["rebuild-0", "rebuild-1", "rebuild-2"])
        XCTAssertEqual(records.map(\.team1FinalScore).sorted(), [0, 1, 2])
        XCTAssertEqual(restarted.syncState(for: "rebuild-1"), .sent)
        XCTAssertEqual(restarted.syncState(for: "rebuild-2"), .pending)
        XCTAssertNil(restarted.syncState(for: "rebuild-0"))
    }

    /// 淘汰超出 500 条上限时，被淘汰记录的单记录文件同步删除（不复现）。
    func testEvictionDeletesSingleRecordFiles() throws {
        let directory = makeTemporaryDirectory()
        let manager = WatchRecordManager(directoryURL: directory)
        let base = Date(timeIntervalSince1970: 2_000_000)
        for index in 0..<502 {
            XCTAssertTrue(manager.saveRecord(
                makeRecord(
                    id: "evict-\(index)",
                    score: index,
                    startTime: base.addingTimeInterval(Double(index))
                ),
                transferToPhone: false
            ))
        }

        let records = manager.loadAllRecords()
        XCTAssertEqual(records.count, 500)
        XCTAssertFalse(records.contains { $0.id == "evict-0" })
        XCTAssertEqual(records.first?.id, "evict-501")

        let items = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(items.filter { $0.hasSuffix(".record.json") }.count, 500, "淘汰记录的单文件必须同步删除")
        XCTAssertEqual(items.filter { $0 == "index.json" }.count, 1)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("evict-0.record.json").path
            )
        )

        // 重启后也不会复现。
        let restarted = WatchRecordManager(directoryURL: directory)
        XCTAssertFalse(restarted.loadAllRecords().contains { $0.id == "evict-0" })
    }

    /// saveRecord 持久化失败必须返回 false，且索引保持不变。
    func testSaveRecordPersistenceFailureReturnsFalseAndKeepsIndex() {
        let directory = makeTemporaryDirectory()
        let manager = WatchRecordManager(directoryURL: directory)
        XCTAssertTrue(manager.saveRecord(makeRecord(id: "keep-1", score: 5), transferToPhone: false))
        let before = manager.loadAllRecords()
        let indexURL = directory.appendingPathComponent("index.json")
        let indexBefore = (try? Data(contentsOf: indexURL))

        manager.testWriteFailureHook = { true }
        defer { manager.testWriteFailureHook = nil }

        XCTAssertFalse(manager.saveRecord(makeRecord(id: "keep-2", score: 7), transferToPhone: false))
        let after = manager.loadAllRecords()
        XCTAssertEqual(after.map(\.id), before.map(\.id), "失败后索引/内存状态必须不变")
        XCTAssertEqual(after.count, 1)
        XCTAssertNil(after.first { $0.id == "keep-2" })
        XCTAssertEqual(try? Data(contentsOf: indexURL), indexBefore)
    }
    /// 有效但陈旧的索引（正文已写、索引写入中断）必须与单记录文件对账恢复：
    /// 缺失条目从正文补齐（syncState 一并恢复），指向已删正文的条目被移除。
    func testStaleIndexReconcilesWithRecordFiles() throws {
        let directory = makeTemporaryDirectory()
        let manager = WatchRecordManager(directoryURL: directory)
        let base = Date(timeIntervalSince1970: 3_000_000)
        XCTAssertTrue(manager.saveRecord(
            makeRecord(id: "stale-a", score: 1, startTime: base),
            transferToPhone: false
        ))
        manager.setSyncState(.pending, for: "stale-a")

        // 模拟崩溃序列：正文落盘成功，index.json 尚未写入该条目。
        let indexURL = directory.appendingPathComponent("index.json")
        let recordURL = directory.appendingPathComponent("stale-a.record.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordURL.path))
        // 手工写回不含该条目的索引：仅保留一个伪造的、正文已删除的条目。
        let ghost = WatchRecordIndexEntry(
            summary: WatchScoreboardRecordSummary(from: makeRecord(id: "ghost", score: 0)),
            syncState: nil
        )
        try JSONEncoder().encode([ghost]).write(to: indexURL, options: .atomic)
        manager.invalidateCache()

        let summaries = manager.getSummaries()
        XCTAssertTrue(summaries.contains { $0.id == "stale-a" }, "陈旧索引必须从正文文件补齐缺失条目")
        XCTAssertFalse(summaries.contains { $0.id == "ghost" }, "指向已删正文的索引条目必须被移除")
        XCTAssertEqual(manager.syncState(for: "stale-a"), .pending, "syncState 从正文恢复")
    }

    /// R4/D4：同 ID 覆盖 = 新正文 → 同步状态重置；索引写入失败后重开，
    /// 必须从正文文件恢复新记录（真相源），摘要取自新正文而非旧索引。
    func testSameIDOverwriteRecoversFromRecordFileWhenIndexWriteFails() throws {
        let directory = makeTemporaryDirectory()
        let manager = WatchRecordManager(directoryURL: directory)
        let base = Date(timeIntervalSince1970: 4_000_000)
        XCTAssertTrue(manager.saveRecord(
            makeRecord(id: "overwrite-me", score: 1, startTime: base),
            transferToPhone: false
        ))
        manager.setSyncState(.sent, for: "overwrite-me")

        // 同 ID 覆盖（比分变化）：正文先写（成功），索引写入失败模拟中断。
        // writeRecordFileLocked 先于 writeIndexLocked 调用：只拦第二次。
        let box = OSAllocatedUnfairLock(initialState: 0)
        manager.testWriteFailureHook = {
            let call = box.withLock { state -> Int in
                state += 1
                return state
            }
            return call == 2 // 第 1 次=正文写（放行），第 2 次=索引写（拦截）
        }
        XCTAssertFalse(manager.saveRecord(
            makeRecord(id: "overwrite-me", score: 99, startTime: base),
            transferToPhone: false
        ), "索引写失败必须反馈 false")
        manager.testWriteFailureHook = nil

        // 重开：真相源 = 正文文件。新摘要（score 99）+ 同步状态重置。
        let restarted = WatchRecordManager(directoryURL: directory)
        let record = restarted.getRecord(id: "overwrite-me")
        XCTAssertEqual(record?.team1FinalScore, 99, "正文为新内容")
        let summary = restarted.getSummaries().first { $0.id == "overwrite-me" }
        XCTAssertEqual(summary?.team1FinalScore, 99, "摘要从新正文恢复，不保留旧索引摘要")
        XCTAssertNil(restarted.syncState(for: "overwrite-me"), "同 ID 覆盖重置同步状态")
    }

    /// R4/D4：同步状态落盘失败（正文侧 updateRecordFileSyncStateLocked 失败
    //  不吞错路径由索引失败钩子模拟）→ 重开重建后状态仍一致。
    func testSyncStateUpdateFailureRecoversOnRebuild() throws {
        let directory = makeTemporaryDirectory()
        let manager = WatchRecordManager(directoryURL: directory)
        XCTAssertTrue(manager.saveRecord(
            makeRecord(id: "state-fail", score: 5),
            transferToPhone: false
        ))
        // 索引写失败 → setSyncState 的索引提交失败，但正文侧状态更新也必须
        // 失败回退：重开后状态取自正文/重建，不会出现“索引 pending 正文 sent”的分裂。
        manager.testWriteFailureHook = { true }
        manager.setSyncState(.pending, for: "state-fail")
        manager.testWriteFailureHook = nil

        let restarted = WatchRecordManager(directoryURL: directory)
        // 正文里仍是 nil（写入被钩子拦截），索引也是旧值：一致即可。
        let rawIndex = (try? String(contentsOf: directory.appendingPathComponent("index.json"))) ?? "?"
        let rawBody = (try? String(contentsOf: directory.appendingPathComponent("state-fail.record.json"))) ?? "?"
        XCTAssertNil(restarted.syncState(for: "state-fail"))
    }

    /// R4/D4：对账后同样应用 500 条上限（正文孤儿超限被淘汰）。
    func testReconcileAppliesMaxRecordsCap() throws {
        let directory = makeTemporaryDirectory()
        let manager = WatchRecordManager(directoryURL: directory)
        let base = Date(timeIntervalSince1970: 5_000_000)
        for index in 0..<505 {
            XCTAssertTrue(manager.saveRecord(
                makeRecord(id: "cap-\(index)", score: index, startTime: base.addingTimeInterval(Double(index))),
                transferToPhone: false
            ))
        }
        XCTAssertEqual(manager.loadAllRecords().count, 500)
        // 删除索引触发从正文重建（正文 500 个文件），上限仍成立。
        try FileManager.default.removeItem(at: directory.appendingPathComponent("index.json"))
        manager.invalidateCache()
        let rebuilt = manager.loadAllRecords()
        XCTAssertEqual(rebuilt.count, 500)
        XCTAssertFalse(rebuilt.contains { $0.id == "cap-0" }, "超限最旧记录淘汰")
        XCTAssertTrue(rebuilt.contains { $0.id == "cap-504" }, "最新记录保留")
    }
}
