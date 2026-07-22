import XCTest
import ScoreCore
@testable import jifen

final class LocalScoreboardDisplayStateTests: XCTestCase {
    func testLegacySnapshotWithoutKeyPointStillDecodes() throws {
        let json = #"{"gameID":"badminton","title":"羽毛球","leftName":"A","rightName":"B","leftScore":"20","rightScore":"18","themeID":"default","fontID":"default","finished":false,"revision":3}"#
        let state = try JSONDecoder().decode(LocalScoreboardDisplayState.self, from: Data(json.utf8))

        XCTAssertNil(state.keyPoint)
        XCTAssertEqual(state.revision, 3)
    }

    func testKeyPointRoundTripPreservesSemanticKindAndScreenSide() throws {
        let state = LocalScoreboardDisplayState(
            gameID: "tennis",
            title: "网球",
            leftName: "A",
            rightName: "B",
            leftScore: "40",
            rightScore: "30",
            themeID: "default",
            fontID: "default",
            finished: false,
            keyPoint: LocalScoreboardKeyPoint(
                status: KeyPointStatus(kind: .set, side: .right),
                sidesSwapped: false
            ),
            revision: 4
        )

        let decoded = try JSONDecoder().decode(
            LocalScoreboardDisplayState.self,
            from: JSONEncoder().encode(state)
        )
        XCTAssertEqual(decoded.keyPoint?.kind, .set)
        XCTAssertEqual(decoded.keyPoint?.side, .right)
        XCTAssertTrue(decoded.keyPoint?.isRenderable == true)
    }

    func testUnknownKeyPointValuesDoNotRejectTheScoreSnapshot() throws {
        let json = #"{"gameID":"badminton","title":"羽毛球","leftName":"A","rightName":"B","leftScore":"20","rightScore":"18","themeID":"default","fontID":"default","finished":false,"keyPoint":{"kind":"future","side":"middle"},"revision":5}"#
        let state = try JSONDecoder().decode(LocalScoreboardDisplayState.self, from: Data(json.utf8))

        XCTAssertEqual(state.keyPoint?.kind, .unknown)
        XCTAssertEqual(state.keyPoint?.side, .unknown)
        XCTAssertFalse(state.keyPoint?.isRenderable ?? true)
    }

    func testSideSwapIsAppliedBeforePublishing() {
        let keyPoint = LocalScoreboardKeyPoint(
            status: KeyPointStatus(kind: .match, side: .left),
            sidesSwapped: true
        )

        XCTAssertEqual(keyPoint?.kind, .match)
        XCTAssertEqual(keyPoint?.side, .right)
    }

    func testEditingAndFinishedSnapshotsOmitKeyPoint() {
        let keyPoint = LocalScoreboardKeyPoint(
            status: KeyPointStatus(kind: .match, side: .left),
            sidesSwapped: false
        )

        XCTAssertEqual(
            LocalScoreboardKeyPoint.syncValue(keyPoint, finished: false, isEditing: false),
            keyPoint
        )
        XCTAssertNil(LocalScoreboardKeyPoint.syncValue(keyPoint, finished: false, isEditing: true))
        XCTAssertNil(LocalScoreboardKeyPoint.syncValue(keyPoint, finished: true, isEditing: false))
    }

    func testTennisTiebreakOnlySevenAndTenOmitGameAndSetDetails() {
        for target in [7, 10] {
            var state = TennisMatchState(
                leftName: "A",
                rightName: "B",
                rules: TennisRuleSet(
                    maxSets: 1,
                    tieBreakPoints: target,
                    setScoringMode: .tiebreakOnly
                )
            )
            state.leftPoints = target - 1
            state.rightPoints = target - 3
            state.leftGames = 1
            state.leftSets = 1

            XCTAssertNil(tennisLocalSyncDetail(state: state, side: .left))
            XCTAssertNil(tennisLocalSyncDetail(state: state, side: .right))
        }
    }

    func testRegularTennisKeepsGameAndSetDetails() {
        var state = TennisMatchState(leftName: "A", rightName: "B")
        state.leftGames = 5
        state.leftSets = 1

        XCTAssertNotNil(tennisLocalSyncDetail(state: state, side: .left))
    }

    func testBadgeCenterUsesCompactAndLargeViewportSpacing() {
        XCTAssertEqual(
            ScoreboardServeGeometry.keyPointBadgeCenterY(
                height: 360,
                doublesTopRow: nil,
                largeWindow: false
            ),
            138
        )
        XCTAssertEqual(
            ScoreboardServeGeometry.keyPointBadgeCenterY(
                height: 640,
                doublesTopRow: nil,
                largeWindow: true
            ),
            274
        )
    }

    func testDoublesBadgeReusesServingRowGeometry() {
        let topAnchor = ScoreboardServeGeometry.doublesAnchorY(height: 600, topRow: true)
        let bottomAnchor = ScoreboardServeGeometry.doublesAnchorY(height: 600, topRow: false)

        XCTAssertEqual(topAnchor, 100)
        XCTAssertEqual(bottomAnchor, 500)
    }
}
