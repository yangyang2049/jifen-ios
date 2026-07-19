import XCTest
import ScoreCore
@testable import jifen

@MainActor
final class ScoreboardCatalogTests: XCTestCase {
    func testVisibleCatalogMatchesReferenceOrder() {
        XCTAssertEqual(GameCatalog.scoreboardItems.map(\.gameType), [
            .pingpong, .badminton, .tennis, .pickleball, .football, .basketball,
            .threeBasketball, .volleyball, .beachVolleyball, .airVolleyball, .archery, .boxing,
            .billiards, .eightBall, .nineBall, .snooker,
            .doudizhu, .guandan, .shengji, .uno,
            .foosball, .simpleScore, .multiScoreboard
        ])
        XCTAssertEqual(GameCatalog.scoreboardItems.count, 23)
    }

    func testLegacyAndCanonicalGameIdentifiersDecode() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(GameType.self, from: Data("\"archery\"".utf8)), .archery)
        XCTAssertEqual(try decoder.decode(GameType.self, from: Data("\"archery_dual\"".utf8)), .archery)
        XCTAssertEqual(try decoder.decode(GameType.self, from: Data("\"simpleScore\"".utf8)), .simpleScore)
        XCTAssertEqual(try decoder.decode(GameType.self, from: Data("\"simple_score\"".utf8)), .simpleScore)
        XCTAssertEqual(try decoder.decode(GameType.self, from: Data("\"multiScoreboard\"".utf8)), .multiScoreboard)
        XCTAssertEqual(try decoder.decode(GameType.self, from: Data("\"multi_scoreboard\"".utf8)), .multiScoreboard)
    }

    func testFontSizePolicyUsesPhoneAndLargeScreenBounds() {
        XCTAssertEqual(ScoreboardFontSizePolicy.normalized(0.5, isLargeScreen: false), 0.8)
        XCTAssertEqual(ScoreboardFontSizePolicy.normalized(0.5, isLargeScreen: true), 0.7)
        XCTAssertEqual(ScoreboardFontSizePolicy.normalized(1.57, isLargeScreen: false), 1.5)
        XCTAssertEqual(ScoreboardFontSizePolicy.normalized(1.13, isLargeScreen: false), 1.15)
    }

    func testFoosballSetupMapsEveryRuleFieldIntoReducerRules() {
        let setup = SportsSetupResult(
            team1Name: "A",
            team2Name: "B",
            maxSets: 5,
            matchCompletionMode: .playAll,
            pointsPerSet: 7,
            winByTwo: true,
            scoreCap: 10
        )
        let rules = setup.foosballRules
        XCTAssertEqual(rules.maxSets, 5)
        XCTAssertEqual(rules.matchCompletionMode, .playAll)
        XCTAssertEqual(rules.pointsToWinSet, 7)
        XCTAssertEqual(rules.finalSetWinByTwo, true)
        XCTAssertEqual(rules.finalSetPointCap, 10)
        XCTAssertEqual(rules.pointCap, nil)
    }

    func testNineBallSetupFieldsRoundTripWithoutDroppingPlayersOrPoints() throws {
        let setup = SportsSetupResult(
            team1Name: "A", team2Name: "B", team3Name: "C", team4Name: "D",
            nineBallBigGold: 12, nineBallSmallGold: 8, nineBallGoldenNine: 9,
            nineBallNormalWin: 5, nineBallBallInHand: 2, nineBallFoul: 3,
            playerCount: 4, playerNames: ["A", "B", "C", "D"]
        )
        let restored = try JSONDecoder().decode(SportsSetupResult.self, from: JSONEncoder().encode(setup))
        XCTAssertEqual(restored.playerCount, 4)
        XCTAssertEqual(restored.playerNames, ["A", "B", "C", "D"])
        XCTAssertEqual(restored.nineBallBigGold, 12)
        XCTAssertEqual(restored.nineBallFoul, 3)
    }
}
