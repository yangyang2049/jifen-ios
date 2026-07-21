import RecordCore
import XCTest
@testable import jifen

@MainActor
final class ScoreboardRecordV4Tests: XCTestCase {
    func testV3RecordDecodesWithoutV4Fields() throws {
        let old = makeRecord(schemaVersion: 3, actions: ["left +1"])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encode(old)) as? [String: Any])
        object.removeValue(forKey: "detailedActions")
        object.removeValue(forKey: "setResults")
        object["schemaVersion"] = 3

        let decoded = try decoder().decode(ScoreboardRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.schemaVersion, 3)
        XCTAssertNil(decoded.detailedActions)
        XCTAssertNil(decoded.setResults)
        XCTAssertEqual(decoded.actions, ["left +1"])
    }

    func testV4DetailedActionsRoundTrip() throws {
        let action = DetailedScoreAction(
            type: .scoreChanged,
            epochMilliseconds: 1_700_000_000_000,
            team: .team1,
            scores: [1, 0],
            setScores: [0, 0],
            setNumber: 1,
            scoreChange: 1,
            operationCode: "point"
        )
        let result = RecordSetResult(number: 1, scores: [11, 7], winner: .team1)
        var record = makeRecord()
        record.detailedActions = [action]
        record.setResults = [result]

        let decoded = try decoder().decode(ScoreboardRecord.self, from: encode(record))
        XCTAssertEqual(decoded.schemaVersion, 4)
        XCTAssertEqual(decoded.detailedActions, [action])
        XCTAssertEqual(decoded.setResults, [result])
    }

    func testUserDefaultsBlobMigratesToIndividualAtomicFilesAndKeepsBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("record-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScoreboardRecordFileStore(rootURL: root)
        let records = [makeRecord(id: "one", actions: ["left +1"]), makeRecord(id: "two", actions: ["right +1"])]

        try store.migrateIfNeeded(legacyData: encode(records))
        let migrated = store.loadRecords()

        XCTAssertEqual(Set(migrated.map(\.id)), ["one", "two"])
        XCTAssertTrue(migrated.allSatisfy { $0.schemaVersion == 4 && $0.detailedActions?.isEmpty == false })
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("scoreboard-records-v3-backup.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("index.json").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".record.json") }.count, 2)
    }

    func testCorruptedRecordIsSkippedWithoutLosingHealthyRecord() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("record-corrupt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScoreboardRecordFileStore(rootURL: root)
        try store.migrateIfNeeded(legacyData: nil)
        try store.save(makeRecord(id: "healthy"))
        try Data("not-json".utf8).write(to: root.appendingPathComponent("broken.record.json"), options: .atomic)

        XCTAssertEqual(store.loadRecords().map(\.id), ["healthy"])
    }

    func testAll23ProjectPoliciesMatchDetailMatrix() {
        let trend: Set<GameType> = [
            .pingpong, .badminton, .pickleball, .basketball, .threeBasketball,
            .volleyball, .beachVolleyball, .airVolleyball, .archery, .billiards,
            .nineBall, .snooker, .foosball, .simpleScore
        ]
        let noTrend: Set<GameType> = [
            .tennis, .football, .boxing, .eightBall, .doudizhu, .guandan,
            .shengji, .uno, .multiScoreboard
        ]
        XCTAssertEqual(trend.count + noTrend.count, 23)
        for game in trend { XCTAssertTrue(ScoreboardRecordProjectPolicy.policy(for: game).trendAllowed, "\(game)") }
        for game in noTrend { XCTAssertFalse(ScoreboardRecordProjectPolicy.policy(for: game).trendAllowed, "\(game)") }
        XCTAssertEqual(ScoreboardRecordProjectPolicy.policy(for: .tennis).recapKind, .tennisSets)
        XCTAssertEqual(ScoreboardRecordProjectPolicy.policy(for: .basketball).recapKind, .periods)
        XCTAssertEqual(ScoreboardRecordProjectPolicy.policy(for: .boxing).recapKind, .rounds)
        XCTAssertEqual(ScoreboardRecordProjectPolicy.policy(for: .multiScoreboard).recapKind, .ranking)
    }

    func testTrendUsesRealScoreChangesAndResetStartsNewSegment() {
        var record = makeRecord()
        record.detailedActions = [
            .init(type: .scoreChanged, scores: [1, 0], scoreChange: 1),
            .init(type: .foul, scores: [1, 0]),
            .init(type: .scoreChanged, scores: [1, 1], scoreChange: 1),
            .init(type: .reset, scores: [1, 1]),
            .init(type: .scoreChanged, scores: [0, 1], scoreChange: 1),
            .init(type: .scoreChanged, scores: [1, 1], scoreChange: 1)
        ]
        let presentation = ScoreboardRecordPresentation(record: record)
        XCTAssertEqual(presentation.trend.map(\.segment), [0, 0, 1, 1])
        XCTAssertTrue(presentation.canShowTrend)
    }

    private func makeRecord(id: String = "record", schemaVersion: Int = 4, actions: [String] = []) -> ScoreboardRecord {
        var record = ScoreboardRecord(
            id: id,
            gameType: .pingpong,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_060),
            duration: 60,
            team1Name: "A",
            team2Name: "B",
            team1FinalScore: 11,
            team2FinalScore: 7,
            winner: "left",
            actions: actions,
            totalScoreChanges: actions.count
        )
        record.schemaVersion = schemaVersion
        return record
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
