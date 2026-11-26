import XCTest
@testable import jifenWatch_Watch_App

/// 记录缓存行为测试：验证缓存命中、写后一致性。
/// 背景：loadAllRecords() 原本每次都全量 JSON 解码（最多 500 条），
/// 而列表/详情/保存路径都会反复调用，记录多了会明显变慢。
final class WatchRecordCacheTests: XCTestCase {

    override func setUp() {
        super.setUp()
        WatchRecordManager.shared.clearAllRecords()
    }

    override func tearDown() {
        WatchRecordManager.shared.clearAllRecords()
        super.tearDown()
    }

    private func makeRecord(
        id: String, score: Int, gameType: WatchGameType = .pingpong, startTime: Date = Date()
    ) -> WatchScoreboardRecord {
        WatchScoreboardRecord(
            id: id,
            gameType: gameType,
            startTime: startTime,
            endTime: Date(),
            duration: 60,
            team1Name: "A",
            team2Name: "B",
            team1FinalScore: score,
            team2FinalScore: 0,
            team1SetScore: 1,
            team2SetScore: 0,
            winner: "A",
            actions: [],
            totalScoreChanges: score
        )
    }

    @MainActor
    func testStandaloneFinishRetryAfterRestartKeepsOriginalRecord() throws {
        let suite = "watch-finished-retry-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let record = makeRecord(id: "standalone-finish", score: 11)
        let first = WatchResumeSessionStore(defaults: defaults)
        XCTAssertFalse(first.saveFinishedRecord(record) { _ in false })

        let restarted = WatchResumeSessionStore(defaults: defaults)
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
        let suite = "watch-cancel-finish-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WatchResumeSessionStore(defaults: defaults)
        let startTime = Date()
        store.save(.init(
            startedAt: startTime, scoreLine: "1/1 = 100%", emoji: "🏀",
            payload: .basketballTraining(mode: .twoPoint, history: [])
        ))
        let training = makeRecord(id: "training", score: 1, gameType: .basketballTraining, startTime: startTime)
        let match = makeRecord(id: "other-match", score: 11, startTime: startTime)
        XCTAssertFalse(store.saveFinishedRecord(training) { _ in false })
        XCTAssertFalse(store.saveFinishedRecord(match) { _ in false })

        store.cancelPendingTrainingFinish(startedAt: startTime)

        let restarted = WatchResumeSessionStore(defaults: defaults)
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
                .init(
                    id: UUID().uuidString, gameType: game, startTime: Date(), endTime: Date(),
                    duration: 60, team1Name: "A", team2Name: "B", team1FinalScore: 8,
                    team2FinalScore: 3, team1SetScore: setScore, team2SetScore: 0,
                    winner: nil, actions: [], totalScoreChanges: 11
                )
            }
            let unfinishedSet = record(setScore: 0)
            XCTAssertTrue(unfinishedSet.usesPointScoreForDisplay, game.rawValue)
            XCTAssertEqual(WatchScoreboardRecordSummary(from: unfinishedSet).listDisplayText, "A 8 - 3 B")
            let completedSet = record(setScore: 2)
            XCTAssertFalse(completedSet.usesPointScoreForDisplay, game.rawValue)
            XCTAssertEqual(WatchScoreboardRecordSummary(from: completedSet).listDisplayText, "A 2 - 0 B")
        }
    }

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

    func testExternalInvalidateReloadsFromDefaults() {
        WatchRecordManager.shared.saveRecord(makeRecord(id: "r1", score: 5), transferToPhone: false)
        XCTAssertEqual(WatchRecordManager.shared.loadAllRecords().count, 1)

        // 模拟外部（如另一进程写入）后强制重读
        WatchRecordManager.shared.invalidateCache()
        XCTAssertEqual(WatchRecordManager.shared.loadAllRecords().count, 1)
    }
}
