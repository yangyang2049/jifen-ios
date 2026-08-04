import ScoreCore
import XCTest
@testable import jifen

@MainActor
final class SportsSetupDraftTests: XCTestCase {
    func testInitializationAppliesSportDefaults() {
        var draft = SportsSetupDraft()

        draft.initialize(
            gameType: .pingpong,
            initialSetup: nil,
            initialMaxSets: nil,
            initialPointsPerSet: nil,
            initialTieBreakPoints: nil
        )

        let names = DefaultParticipantNames.resolve(for: .pingpong)
        XCTAssertEqual(draft.team1Name, names.left)
        XCTAssertEqual(draft.team2Name, names.right)
        XCTAssertTrue(draft.isSingles)
        XCTAssertEqual(draft.selectedMaxSets, 5)
        XCTAssertEqual(draft.selectedPointsPerSet, 11)
        XCTAssertEqual(draft.matchCompletionMode, .bestOf)
    }

    func testInitializationRestoresTennisConfiguration() {
        let setup = SportsSetupResult(
            team1Name: "A",
            team2Name: "B",
            maxSets: 1,
            matchCompletionMode: .playAll,
            tieBreakPoints: 10,
            gamesPerSet: 4,
            setScoringMode: "tiebreak_only",
            autoChangeSides: false,
            isSingles: false,
            tennisDeuceMode: "no_ad",
            servingSide: MatchSide.right.rawValue
        )
        var draft = SportsSetupDraft()

        draft.initialize(
            gameType: .tennis,
            initialSetup: setup,
            initialMaxSets: nil,
            initialPointsPerSet: nil,
            initialTieBreakPoints: nil
        )

        XCTAssertFalse(draft.isSingles)
        XCTAssertEqual(draft.tennisSetScoringMode, "tiebreak_only")
        XCTAssertEqual(draft.matchTieBreakPoints, 10)
        XCTAssertEqual(draft.tennisGamesPerSet, 4)
        XCTAssertEqual(draft.tennisDeuceMode, "no_ad")
        XCTAssertEqual(draft.servingSide, .right)
        XCTAssertFalse(draft.autoChangeSides)
    }

    func testModeSwitchUsesDefaultDoublesMembersAndSportSeparator() {
        var draft = SportsSetupDraft()
        let singles = DefaultParticipantNames.resolve(for: .foosball)
        draft.team1Name = singles.left
        draft.team2Name = singles.right

        draft.applyDefaultsWhenSwitchingToDoubles(
            gameType: .foosball,
            configuredLeftName: singles.left,
            configuredRightName: singles.right
        )

        let members = DefaultParticipantNames.doublesMembers
        XCTAssertEqual(draft.team1Player1Name, members[0])
        XCTAssertEqual(draft.team1Player2Name, members[1])
        XCTAssertEqual(draft.team2Player1Name, members[2])
        XCTAssertEqual(draft.team2Player2Name, members[3])
        XCTAssertEqual(draft.team1Name, "\(members[0])/\(members[1])")
        XCTAssertEqual(draft.team2Name, "\(members[2])/\(members[3])")
    }

    func testValidationCoversCompletionPointsAndFoosballCap() {
        var draft = SportsSetupDraft()
        draft.matchCompletionMode = .bestOf
        draft.selectedMaxSets = 4
        XCTAssertFalse(draft.hasValidMatchCompletionSets)

        draft.matchCompletionMode = .playAll
        XCTAssertTrue(draft.hasValidMatchCompletionSets)

        draft.selectedPointsPerSet = 0
        XCTAssertFalse(draft.hasValidPointsPerSet(for: .pingpong))
        draft.selectedPointsPerSet = 11
        XCTAssertTrue(draft.hasValidPointsPerSet(for: .pingpong))

        draft.foosballWinByTwo = true
        draft.foosballScoreCap = 10
        draft.selectedPointsPerSet = 11
        XCTAssertFalse(draft.hasValidFoosballScoreCap(for: .foosball))
        draft.foosballScoreCap = 15
        XCTAssertTrue(draft.hasValidFoosballScoreCap(for: .foosball))
    }

    func testResultMappingPreservesRallyAndEightBallRules() {
        var rally = SportsSetupDraft()
        rally.team1Name = "A"
        rally.team2Name = "B"
        rally.selectedMaxSets = 7
        rally.selectedPointsPerSet = 15
        rally.matchCompletionMode = .playAll
        rally.autoChangeSides = false
        rally.servingSide = .right
        rally.voiceAnnouncement = true

        let pingpong = rally.makeResult(gameType: .pingpong, usesDoublesPlayerInputs: false)
        XCTAssertEqual(pingpong.maxSets, 7)
        XCTAssertEqual(pingpong.pointsPerSet, 15)
        XCTAssertEqual(pingpong.matchCompletionMode, .playAll)
        XCTAssertEqual(pingpong.autoChangeSides, false)
        XCTAssertEqual(pingpong.servingSide, MatchSide.right.rawValue)
        XCTAssertEqual(pingpong.voiceAnnouncement, true)

        var eightBall = rally
        eightBall.selectedMaxSets = 5
        eightBall.eightBallHandicapMode = "team2"
        eightBall.eightBallHandicapRacks = 8
        let result = eightBall.makeResult(gameType: .eightBall, usesDoublesPlayerInputs: false)
        XCTAssertEqual(result.maxSets, 5)
        XCTAssertEqual(result.eightBallHandicapRacks, 4)
        XCTAssertEqual(result.eightBallHandicapBeneficiary, "team2")
    }
}
