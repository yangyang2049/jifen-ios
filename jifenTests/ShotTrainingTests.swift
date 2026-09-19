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
}
