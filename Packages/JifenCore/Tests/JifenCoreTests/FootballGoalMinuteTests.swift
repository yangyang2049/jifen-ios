import XCTest
@testable import ScoreCore

final class FootballGoalMinuteTests: XCTestCase {
    func testRegulationMinutesUseMatchClock() {
        XCTAssertEqual(
            FootballGoalMinute.label(isFiveAside: false, halfLengthSeconds: 45 * 60, period: 1, elapsedSeconds: 0),
            "1′"
        )
        XCTAssertEqual(
            FootballGoalMinute.label(isFiveAside: false, halfLengthSeconds: 45 * 60, period: 1, elapsedSeconds: 600),
            "10′"
        )
        XCTAssertEqual(
            FootballGoalMinute.label(isFiveAside: false, halfLengthSeconds: 45 * 60, period: 2, elapsedSeconds: 600),
            "55′"
        )
    }

    func testStoppageTimeShowsBasePlusInjury() {
        XCTAssertEqual(
            FootballGoalMinute.label(isFiveAside: false, halfLengthSeconds: 45 * 60, period: 1, elapsedSeconds: 45 * 60 + 60),
            "45+1′"
        )
        XCTAssertEqual(
            FootballGoalMinute.label(isFiveAside: false, halfLengthSeconds: 45 * 60, period: 2, elapsedSeconds: 45 * 60 + 180),
            "90+3′"
        )
    }

    func testExtraTimeHalvesContinueTheClock() {
        XCTAssertEqual(
            FootballGoalMinute.label(isFiveAside: false, halfLengthSeconds: 45 * 60, period: 3, elapsedSeconds: 60),
            "91′"
        )
        XCTAssertEqual(
            FootballGoalMinute.label(isFiveAside: false, halfLengthSeconds: 45 * 60, period: 4, elapsedSeconds: 600),
            "115′"
        )
    }

    func testFiveASideUsesConfiguredHalfLength() {
        XCTAssertEqual(
            FootballGoalMinute.label(isFiveAside: true, halfLengthSeconds: 20 * 60, period: 1, elapsedSeconds: 300),
            "5′"
        )
        XCTAssertEqual(
            FootballGoalMinute.label(isFiveAside: true, halfLengthSeconds: 20 * 60, period: 2, elapsedSeconds: 60),
            "21′"
        )
        XCTAssertNil(
            FootballGoalMinute.label(isFiveAside: true, halfLengthSeconds: 20 * 60, period: 3, elapsedSeconds: 60)
        )
    }


    func testClockAnnotationRoundTrips() {
        let token = FootballClockAnnotation.encode(period: 2, elapsedSeconds: 600)
        XCTAssertEqual(token, "football:2:600")
        XCTAssertEqual(FootballClockAnnotation.decode("football:2:600")?.period, 2)
        XCTAssertEqual(FootballClockAnnotation.decode("football:2:600")?.elapsedSeconds, 600)
    }

    func testClockAnnotationRejectsInvalidValues() {
        XCTAssertNil(FootballClockAnnotation.encode(period: 0, elapsedSeconds: 10))
        XCTAssertNil(FootballClockAnnotation.encode(period: 5, elapsedSeconds: 10))
        XCTAssertNil(FootballClockAnnotation.encode(period: 1, elapsedSeconds: -1))
        XCTAssertNil(FootballClockAnnotation.decode("football:1"))
        XCTAssertNil(FootballClockAnnotation.decode("basketball:1:10"))
        XCTAssertNil(FootballClockAnnotation.decode("football:9:10"))
        XCTAssertNil(FootballClockAnnotation.decode("football:1:-5"))
    }

    func testInvalidSnapshotsReturnNil() {
        XCTAssertNil(FootballGoalMinute.label(isFiveAside: false, halfLengthSeconds: 45 * 60, period: nil, elapsedSeconds: 60))
        XCTAssertNil(FootballGoalMinute.label(isFiveAside: false, halfLengthSeconds: 45 * 60, period: 5, elapsedSeconds: 60))
        XCTAssertNil(FootballGoalMinute.label(isFiveAside: false, halfLengthSeconds: 45 * 60, period: 1, elapsedSeconds: nil))
        XCTAssertNil(FootballGoalMinute.label(isFiveAside: false, halfLengthSeconds: 45 * 60, period: 1, elapsedSeconds: -1))
    }
}
