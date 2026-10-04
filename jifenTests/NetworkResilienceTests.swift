import XCTest
@testable import jifen

/// 网络韧性批次（重试/退避 + WS 离线队列）的纯策略单测。
final class NetworkResilienceTests: XCTestCase {

    // MARK: APIClient 重试策略

    func testOnlyIdempotentGETRetries() {
        XCTAssertEqual(APIRetryPolicy.maxRetries(method: .get), 2)
        XCTAssertEqual(APIRetryPolicy.maxRetries(method: .post), 0)
        XCTAssertEqual(APIRetryPolicy.maxRetries(method: .put), 0)
        XCTAssertEqual(APIRetryPolicy.maxRetries(method: .patch), 0)
        XCTAssertEqual(APIRetryPolicy.maxRetries(method: .delete), 0)
    }

    func testRetryableStatusesMatchAndroid() {
        XCTAssertTrue(APIRetryPolicy.retryableStatuses.contains(429))
        XCTAssertTrue(APIRetryPolicy.retryableStatuses.contains(502))
        XCTAssertTrue(APIRetryPolicy.retryableStatuses.contains(503))
        XCTAssertTrue(APIRetryPolicy.retryableStatuses.contains(504))
        XCTAssertFalse(APIRetryPolicy.retryableStatuses.contains(500))
        XCTAssertFalse(APIRetryPolicy.retryableStatuses.contains(400))
        XCTAssertFalse(APIRetryPolicy.retryableStatuses.contains(401))
    }

    func testBackoffGrowsExponentiallyAndRespectsRetryAfter() {
        XCTAssertEqual(APIRetryPolicy.retryDelay(attempt: 1, retryAfterSeconds: nil), 0.4, accuracy: 0.001)
        XCTAssertEqual(APIRetryPolicy.retryDelay(attempt: 2, retryAfterSeconds: nil), 0.8, accuracy: 0.001)
        XCTAssertEqual(APIRetryPolicy.retryDelay(attempt: 1, retryAfterSeconds: 2.5), 2.5, accuracy: 0.001)
        XCTAssertEqual(APIRetryPolicy.retryDelay(attempt: 1, retryAfterSeconds: 999), 10.0, accuracy: 0.001)
    }

    func testRetryAfterHeaderParsing() {
        XCTAssertEqual(APIRetryPolicy.retryAfterSeconds(from: "3"), 3)
        XCTAssertEqual(APIRetryPolicy.retryAfterSeconds(from: " 7 "), 7)
        XCTAssertNil(APIRetryPolicy.retryAfterSeconds(from: nil))
        XCTAssertNil(APIRetryPolicy.retryAfterSeconds(from: ""))
        XCTAssertNil(APIRetryPolicy.retryAfterSeconds(from: "not-a-date"))
        XCTAssertNil(APIRetryPolicy.retryAfterSeconds(from: "NaN"))
        XCTAssertNil(APIRetryPolicy.retryAfterSeconds(from: "inf"))
        XCTAssertNil(APIRetryPolicy.retryAfterSeconds(from: "1e999"))
    }

    func testRetryDelayAlwaysStaysWithinFiniteBudget() {
        XCTAssertEqual(APIRetryPolicy.retryDelay(attempt: 1, retryAfterSeconds: -10), 0)
        for value in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(APIRetryPolicy.retryDelay(attempt: 1, retryAfterSeconds: value), 0.4, accuracy: 0.001)
        }
        XCTAssertEqual(APIRetryPolicy.retryDelay(attempt: 10_000, retryAfterSeconds: nil), 10)
    }

    func testTransportErrorRetryability() {
        XCTAssertTrue(APIRetryPolicy.isRetryableTransport(URLError(.timedOut)))
        XCTAssertTrue(APIRetryPolicy.isRetryableTransport(URLError(.networkConnectionLost)))
        XCTAssertTrue(APIRetryPolicy.isRetryableTransport(URLError(.notConnectedToInternet)))
        XCTAssertFalse(APIRetryPolicy.isRetryableTransport(URLError(.cancelled)))
        XCTAssertFalse(APIRetryPolicy.isRetryableTransport(URLError(.badServerResponse)))
    }

    // MARK: WS 离线队列策略

    @MainActor func testSnapshotKeepsOnlyLatestFrame() {
        let manager = MatchWebSocketManager.shared
        func snapshot(_ score: Int) -> WsEnvelope {
            WsEnvelope(
                type: WsMessageType.participantUpdate.rawValue,
                payload: ["participants": [["id": "p1", "score": score]]],
                timestamp: Int64(score)
            )
        }
        manager.debugEnqueueOffline(snapshot(1))
        manager.debugEnqueueOffline(snapshot(2))
        manager.debugEnqueueOffline(snapshot(3))
        let queued = manager.debugPendingQueueSnapshot()
        // 每一帧都被下一帧覆盖，队列里只剩最新一帧
        XCTAssertEqual(queued.count, 1)
        XCTAssertEqual(queued.last?.timestamp, 3)
    }

    @MainActor func testGameOverAndLeaveKeepLastWins() {
        let manager = MatchWebSocketManager.shared
        manager.debugSeedOfflineQueue([])
        manager.debugEnqueueOffline(WsEnvelope(type: "GAME_OVER", payload: ["round": 1], timestamp: 1))
        manager.debugEnqueueOffline(WsEnvelope(type: "LEAVE", payload: ["reason": "a"], timestamp: 2))
        manager.debugEnqueueOffline(WsEnvelope(type: "GAME_OVER", payload: ["round": 2], timestamp: 3))
        manager.debugEnqueueOffline(WsEnvelope(type: "LEAVE", payload: ["reason": "b"], timestamp: 4))
        let queued = manager.debugPendingQueueSnapshot()
        // 同类各自去重：GAME_OVER 与 LEAVE 互不顶掉，各自只留最后一条
        XCTAssertEqual(queued.filter { $0.type == "GAME_OVER" }.map(\.timestamp), [3])
        XCTAssertEqual(queued.filter { $0.type == "LEAVE" }.map(\.timestamp), [4])
    }

    @MainActor func testOrderedEventsKeepSequenceAndJoinPingAreDropped() {
        let manager = MatchWebSocketManager.shared
        manager.debugSeedOfflineQueue([])
        manager.debugEnqueueOffline(WsEnvelope(type: "CONTROLLER_AWAY", payload: nil, timestamp: 1))
        manager.debugEnqueueOffline(WsEnvelope(type: "MATCH_STARTED", payload: nil, timestamp: 2))
        manager.debugEnqueueOffline(WsEnvelope(type: "CONTROLLER_RESUME", payload: nil, timestamp: 3))
        manager.debugEnqueueOffline(WsEnvelope(type: "JOIN", payload: nil, timestamp: 4))
        manager.debugEnqueueOffline(WsEnvelope(type: "PING", payload: nil, timestamp: 5))
        manager.debugEnqueueOffline(WsEnvelope(type: "UNKNOWN_FUTURE_TYPE", payload: nil, timestamp: 6))
        let queued = manager.debugPendingQueueSnapshot()
        XCTAssertEqual(queued.map(\.timestamp), [1, 2, 3])
    }

    @MainActor func testQueueOverflowEvictsOldestSnapshotBeforeOrderedEvents() {
        let manager = MatchWebSocketManager.shared
        var seed: [WsEnvelope] = [WsEnvelope(
            type: WsMessageType.participantUpdate.rawValue,
            payload: ["participants": [["id": "p1", "score": 7]]],
            timestamp: 0
        )]
        for index in 1..<WsOfflineQueuePolicy.capacity {
            seed.append(WsEnvelope(type: "MATCH_STARTED", payload: nil, timestamp: Int64(index)))
        }
        manager.debugSeedOfflineQueue(seed)
        // 第 17 条入队：先丢可被覆盖的快照，按序事件一条不丢
        manager.debugEnqueueOffline(WsEnvelope(type: "CONTROLLER_RESUME", payload: nil, timestamp: 100))
        let queued = manager.debugPendingQueueSnapshot()
        XCTAssertEqual(queued.count, WsOfflineQueuePolicy.capacity)
        XCTAssertEqual(queued.filter { $0.type == WsMessageType.participantUpdate.rawValue }.count, 0)
        XCTAssertEqual(queued.filter { $0.type == "MATCH_STARTED" }.count, WsOfflineQueuePolicy.capacity - 1)
        XCTAssertEqual(queued.last?.timestamp, 100)

        // 队列里已无快照时，丢最老的一条按序事件
        manager.debugEnqueueOffline(WsEnvelope(type: "CONTROLLER_AWAY", payload: nil, timestamp: 200))
        let after = manager.debugPendingQueueSnapshot()
        XCTAssertEqual(after.count, WsOfflineQueuePolicy.capacity)
        XCTAssertFalse(after.contains { $0.timestamp == 1 }, "oldest ordered event should be evicted")
        XCTAssertEqual(after.last?.timestamp, 200)
    }

    @MainActor override func tearDown() {
        MatchWebSocketManager.shared.debugClearOfflineQueue()
        super.tearDown()
    }
}
