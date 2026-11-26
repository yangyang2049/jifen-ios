import XCTest
import LinkCore
@testable import jifenWatch_Watch_App

@MainActor
final class WatchStartupOptimizationTests: XCTestCase {
    func testDuplicateCommonNamesContextRevisionIsIgnored() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchStartupCommonNames.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WatchCommonNamesStore(directoryURL: directory)

        XCTAssertTrue(store.apply(.init(
            teams: ["Team A"],
            players: ["Alice"],
            revision: 8
        )))
        XCTAssertFalse(store.apply(.init(
            teams: ["Duplicate"],
            players: ["Duplicate"],
            revision: 8
        )))

        XCTAssertEqual(store.teams, ["Team A"])
        XCTAssertEqual(store.players, ["Alice"])
        XCTAssertEqual(store.revision, 8)
    }

    /// 干净初始化：restore 每实例只跑一次；文件存储跨实例恢复已保存的续玩会话。
    func testResumeRestoreRunsOncePerInstanceAndPersistsAcrossRestart() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchStartupResume.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = WatchResumeSessionStore(directoryURL: directory)
        XCTAssertEqual(first.restoreAttemptCount, 1)
        XCTAssertNil(first.session)

        let startedAt = Date(timeIntervalSince1970: 5_000)
        first.save(.init(
            startedAt: startedAt,
            scoreLine: "3 : 1",
            emoji: "🏸",
            payload: .basketballTraining(mode: .free, history: [])
        ))
        first.flushPendingWrite()

        let second = WatchResumeSessionStore(directoryURL: directory)
        XCTAssertEqual(second.restoreAttemptCount, 1)
        XCTAssertEqual(second.session?.scoreLine, "3 : 1")
        XCTAssertEqual(second.session?.startedAt, startedAt)
    }
}

private final class WatchStartupDataStore: @unchecked Sendable, LinkDataStore {
    private var values: [String: Data] = [:]
    private(set) var removalCounts: [String: Int] = [:]

    func data(forKey key: String) -> Data? {
        values[key]
    }

    func set(_ data: Data, forKey key: String) {
        values[key] = data
    }

    func removeObject(forKey key: String) {
        removalCounts[key, default: 0] += 1
        values.removeValue(forKey: key)
    }

    func setOrThrow(_ data: Data, forKey key: String) throws {
        values[key] = data
    }

    @discardableResult
    func removeOrThrow(forKey key: String) throws -> Bool {
        let existed = values[key] != nil
        removalCounts[key, default: 0] += 1
        values.removeValue(forKey: key)
        return existed
    }
}

private final class WatchStartupTransport: @unchecked Sendable, WatchLinkTransport {
    var status = WatchConnectivityStatus(
        isSupported: true,
        isActivated: true,
        isPaired: true,
        isWatchAppInstalled: true,
        isReachable: true
    )
    var receivedApplicationContext: [String: Any] = [:]
    var isReachable: Bool { status.isReachable }

    var onReceive: (@Sendable (Data) -> Void)?
    var onSendError: (@Sendable (Error) -> Void)?
    var onStatusChange: (@Sendable (WatchConnectivityStatus) -> Void)?
    var onApplicationContext: (@Sendable ([String: Any]) -> Void)?
    var onWatchRecordData: (@Sendable (Data) -> Void)?
    var onCommonNameMutationsData: (@Sendable (Data) -> Void)?
    var onCommonNameMutationAckData: (@Sendable (Data) -> Void)?
    var onCatchUpRequest: (@Sendable () -> Void)?
    var onClearPendingRequest: (@Sendable ([String]) -> Void)?
    var onPendingRecords: (@Sendable ([Data]) -> Void)?

    func activate() {}
    func refreshStatus() { onStatusChange?(status) }
    func sendRealtime(_ data: Data) async throws {}
    func publishLatestSnapshot(_ data: Data) throws {}
    func enqueueDurable(_ data: Data) throws {}
    func sendInteractive(_ data: Data) throws {}
    func updateApplicationContext(_ context: [String: Any]) throws {
        receivedApplicationContext.merge(context) { _, latest in latest }
    }
    func transferWatchRecord(_ data: Data) throws {}
    var supportsFileTransfer = true
    var onReceivedFile: (@Sendable (Data, [String: Any]) -> Void)?
    var transferredFiles: [(data: Data, metadata: [String: Any])] = []

    func transferFileData(_ data: Data, metadata: [String: Any]) throws {
        transferredFiles.append((data, metadata))
    }

    func transferCommonNameMutations(_ data: Data) throws {}
    func transferCommonNameMutationAcknowledgement(_ data: Data) throws {}
    func requestPendingWatchRecords() {}
    func sendPendingWatchRecords(_ datas: [Data]) {}
    func clearPendingWatchRecords(ids: [String]) {}
}
