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

    private func makeRecord(id: String, score: Int) -> WatchScoreboardRecord {
        WatchScoreboardRecord(
            id: id,
            gameType: .pingpong,
            startTime: Date(),
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
