import LinkCore
import XCTest
@testable import jifen

final class ShotTrainingTests: XCTestCase {
    func testCountsCoverAllSixBucketsAndStayConsistent() {
        let shots = [
            ShotTrainingShot(points: 1, made: true),
            ShotTrainingShot(points: 1, made: false),
            ShotTrainingShot(points: 2, made: true),
            ShotTrainingShot(points: 2, made: false),
            ShotTrainingShot(points: 3, made: true),
            ShotTrainingShot(points: 3, made: false)
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
        for mode in ShotTrainingMode.allCases {
            let state = ShotTrainingResumeState(
                mode: mode,
                shots: [ShotTrainingShot(points: mode.fixedPoints ?? 2, made: true)],
                finished: false
            )
            let decoded = try JSONDecoder().decode(
                ShotTrainingResumeState.self,
                from: JSONEncoder().encode(state)
            )
            XCTAssertEqual(decoded, state)
        }
    }

    @MainActor
    func testLinkedAndStandaloneWatchRecordsKeepTrainingBreakdownAndReplayMode() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let state = LinkedShotTrainingState(
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
            id: "w_training_fixture", gameType: "basketballTraining",
            startTimeEpochMilliseconds: 1_700_000_000_000, endTimeEpochMilliseconds: 1_700_000_005_000,
            durationSeconds: 5, team1Name: "Miss", team2Name: "Made",
            team1FinalScore: 1, team2FinalScore: 2, team1SetScore: 0, team2SetScore: 0,
            winner: nil, actions: [], totalScoreChanges: 3, basketballTraining: state
        )
        let finished = LinkMatchFinishedPayload(
            snapshot: .basketballTraining(state), recordId: standalone.id,
            winnerSide: nil, manualEnd: true,
            startTimeEpochMilliseconds: standalone.startTimeEpochMilliseconds,
            endTimeEpochMilliseconds: standalone.endTimeEpochMilliseconds,
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
        let shotCount = LinkedShotTrainingState.maxDetailedShots + 10
        let state = LinkedShotTrainingState(
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
