import Foundation
import LinkCore
import RecordCore
import ScoreCore
import XCTest
@testable import jifen

final class ShotTrainingTests: XCTestCase {
    func testCountsCoverAllSixBucketsAndStayConsistent() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let shots = [
            ShotTrainingShot(points: 1, made: true, timestamp: timestamp),
            ShotTrainingShot(points: 1, made: false, timestamp: timestamp),
            ShotTrainingShot(points: 2, made: true, timestamp: timestamp),
            ShotTrainingShot(points: 2, made: false, timestamp: timestamp),
            ShotTrainingShot(points: 3, made: true, timestamp: timestamp),
            ShotTrainingShot(points: 3, made: false, timestamp: timestamp)
        ]

        let counts = ShotTrainingCounts.build(from: shots)

        XCTAssertEqual(counts.oneMade, 1)
        XCTAssertEqual(counts.oneMiss, 1)
        XCTAssertEqual(counts.twoMade, 1)
        XCTAssertEqual(counts.twoMiss, 1)
        XCTAssertEqual(counts.threeMade, 1)
        XCTAssertEqual(counts.threeMiss, 1)
        XCTAssertEqual(counts.attempts, 6)
        XCTAssertEqual(counts.made, 3)
        XCTAssertEqual(counts.points, 6)
        XCTAssertEqual(counts.rate, 50)
    }

    func testResumeStateRoundTripsEveryScoringMode() throws {
        let shotID = UUID(uuidString: "12121212-3434-4545-8686-101010101010")
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000.125)
        for mode in ShotTrainingMode.allCases {
            let state = ShotTrainingResumeState(
                mode: mode,
                shots: [
                    ShotTrainingShot(id: shotID, points: mode.fixedPoints ?? 2, made: true, timestamp: timestamp)
                ],
                finished: false
            )
            let decoded = try JSONDecoder().decode(
                ShotTrainingResumeState.self,
                from: JSONEncoder().encode(state)
            )
            XCTAssertEqual(decoded, state)
        }
    }

    func testPublishedTrainingDraftRetainsLegacyJSONFields() throws {
        let shotID = "12121212-3434-4545-8686-101010101010"
        let countsJSON = #"{"oneMade":0,"oneMiss":0,"twoMade":4,"twoMiss":3,"threeMade":0,"threeMiss":0}"#
        let counts: [String: Int] = [
            "oneMade": 0, "oneMiss": 0, "twoMade": 4, "twoMiss": 3, "threeMade": 0, "threeMiss": 0
        ]
        // The standalone phone record stores its start time outside this draft.
        // A shot timestamp uses Foundation's default seconds since 2001.
        for hasEarlierCounts in [false, true] {
            let earlierCountsField = hasEarlierCounts ? ", \"earlierCounts\": \(countsJSON)" : ""
            let fixture = Data("""
                {
                  "schemaVersion": 1,
                  "mode": "fixed_2",
                  "finished": false,
                  "shots": [{"id": "\(shotID)", "points": 2, "made": true, "timestamp": 721692800.125}]
                  \(earlierCountsField)
                }
                """.utf8)

            let state = try JSONDecoder().decode(ShotTrainingResumeState.self, from: fixture)
            let shot = try XCTUnwrap(state.shots.first)
            XCTAssertEqual(state.schemaVersion, 1)
            XCTAssertEqual(state.mode.rawValue, "fixed_2")
            XCTAssertFalse(state.finished)
            XCTAssertEqual(state.shots.count, 1)
            XCTAssertEqual(shot.id, try XCTUnwrap(UUID(uuidString: shotID)))
            XCTAssertEqual(shot.points, 2)
            XCTAssertTrue(shot.made)
            XCTAssertEqual(shot.timestamp, Date(timeIntervalSince1970: 1_700_000_000.125))
            XCTAssertEqual(state.earlierCounts?.twoMade, hasEarlierCounts ? 4 : nil)
            XCTAssertEqual(state.earlierCounts?.twoMiss, hasEarlierCounts ? 3 : nil)

            let encoded = try JSONEncoder().encode(state)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            let shots = try XCTUnwrap(object["shots"] as? [[String: Any]])
            let encodedShot = try XCTUnwrap(shots.first)
            XCTAssertEqual(object["schemaVersion"] as? Int, 1)
            XCTAssertEqual(object["mode"] as? String, "fixed_2")
            XCTAssertEqual(object["finished"] as? Bool, false)
            XCTAssertEqual(shots.count, 1)
            XCTAssertEqual(encodedShot["id"] as? String, shotID)
            XCTAssertEqual(encodedShot["points"] as? Int, 2)
            XCTAssertEqual(encodedShot["made"] as? Bool, true)
            XCTAssertEqual(encodedShot["timestamp"] as? Double, 721_692_800.125)
            if hasEarlierCounts {
                XCTAssertEqual(object["earlierCounts"] as? [String: Int], counts)
            } else {
                XCTAssertNil(object["earlierCounts"])
            }
        }
    }

    @MainActor
    func testLinkedAndStandaloneWatchRecordsKeepTrainingBreakdownAndReplayMode() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let state = ShotTrainingState(
            mode: .free,
            startTime: start,
            shots: [
                .init(points: 1, made: false, timestamp: start.addingTimeInterval(1)),
                .init(points: 2, made: true, timestamp: start.addingTimeInterval(2)),
                .init(points: 3, made: true, timestamp: start.addingTimeInterval(3))
            ],
            finished: true
        )
        let standalone = WatchRecordTransferPayload(
            id: "w_training_fixture", kind: .sport(.basketballTraining), source: .watchLocal,
            startEpochMilliseconds: 1_700_000_000_000, endEpochMilliseconds: 1_700_000_005_000,
            durationSeconds: 5, team1Name: "Miss", team2Name: "Made",
            team1FinalScore: 1, team2FinalScore: 2, totalScoreChanges: 3, basketballTraining: state
        )
        let finished = LinkMatchFinishedPayload(
            snapshot: .basketballTraining(state), recordId: standalone.id,
            winnerSide: nil, manualEnd: true,
            startTimeEpochMilliseconds: standalone.startEpochMilliseconds,
            endTimeEpochMilliseconds: standalone.endEpochMilliseconds,
            durationSeconds: 5, totalScoreChanges: 3
        )

        let encoded = try JSONEncoder().encode(finished.snapshot)
        XCTAssertEqual(try JSONDecoder().decode(LinkedScoreboardSnapshot.self, from: encoded), finished.snapshot)
        for record in [
            try WatchStandaloneRecordIngestor.makeRecord(standalone),
            try LinkedMatchRecordIngestor.makeRecord(payload: finished, gameType: .basketballTraining)
        ] {
            XCTAssertEqual(record.id, standalone.id)
            XCTAssertEqual(record.gameType, .basketballTraining)
            XCTAssertEqual(record.team1FinalScore, 1)
            XCTAssertEqual(record.team2FinalScore, 2)
            XCTAssertNil(record.team1SetScore)
            XCTAssertNil(record.winner)
            XCTAssertEqual(record.extraData?["syncFrom"]?.value as? String, "watch")
            XCTAssertEqual(record.extraData?["threePointMade"]?.value as? Int, 1)
            XCTAssertEqual(record.detailedActions?.compactMap(\.operationCode), [
                "training_1pt_miss", "training_2pt_made", "training_3pt_made", "training_rate_67"
            ])
            XCTAssertEqual(ScoreboardRecordConfiguration.setup(from: record).basketballTrainingScoringMode, "free")
        }
    }

    func testLargeLinkedTrainingKeepsTotalsWithinWatchConnectivityLimit() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let shotCount = ShotTrainingState.maxDetailedShots + 10
        let state = ShotTrainingState(
            mode: .fixed3,
            startTime: start,
            shots: (0..<shotCount).map {
                .init(points: 3, made: $0.isMultiple(of: 2), timestamp: start.addingTimeInterval(Double($0)))
            }
        )
        let data = try JSONEncoder().encode(LinkedScoreboardSnapshot.basketballTraining(state))
        XCTAssertLessThan(data.count, LinkEnvelopeEncoding.defaultByteLimit / 2 + 2_000)
        let restored = try XCTUnwrap(
            JSONDecoder().decode(LinkedScoreboardSnapshot.self, from: data).basketballTrainingState
        )
        XCTAssertEqual(restored.earlierCounts.attempts, 10)
        XCTAssertEqual(restored.counts.attempts, shotCount)
        XCTAssertEqual(restored.counts.threeMade, shotCount / 2)
        XCTAssertEqual(restored.shots.first?.timestamp, start.addingTimeInterval(10))
    }

}
