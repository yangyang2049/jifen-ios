import XCTest
import ScoreCore
@testable import jifen

@MainActor
final class ScoreboardCatalogTests: XCTestCase {
    func testTimerAndToolCatalogCountsIncludeNewParityFeatures() {
        XCTAssertEqual(GameCatalog.timerAllItems.count, 9)
        XCTAssertEqual(Set(GameCatalog.timerAllItems).count, 9)
        XCTAssertTrue(GameCatalog.timerAllItems.contains(.checkers))
        XCTAssertTrue(GameCatalog.timerAllItems.contains(.basketball24))
        XCTAssertTrue(GameCatalog.timerAllItems.contains(.basketball12))
        XCTAssertEqual(ToolItem.allTools.count, 10)
        XCTAssertTrue(ToolItem.allTools.contains { $0.id == "random_team" })
        XCTAssertTrue(ToolItem.allTools.contains { $0.id == "fullscreen_barrage" })
    }

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
        XCTAssertEqual(try decoder.decode(jifen.GameType.self, from: Data("\"archery\"".utf8)), .archery)
        XCTAssertEqual(try decoder.decode(jifen.GameType.self, from: Data("\"archery_dual\"".utf8)), .archery)
        XCTAssertEqual(try decoder.decode(jifen.GameType.self, from: Data("\"simpleScore\"".utf8)), .simpleScore)
        XCTAssertEqual(try decoder.decode(jifen.GameType.self, from: Data("\"simple_score\"".utf8)), .simpleScore)
        XCTAssertEqual(try decoder.decode(jifen.GameType.self, from: Data("\"multiScoreboard\"".utf8)), .multiScoreboard)
        XCTAssertEqual(try decoder.decode(jifen.GameType.self, from: Data("\"multi_scoreboard\"".utf8)), .multiScoreboard)
    }

    func testFontSizePolicyUsesPhoneAndLargeScreenBounds() {
        XCTAssertEqual(ScoreboardFontSizePolicy.normalized(0.5, isLargeScreen: false), 0.8)
        XCTAssertEqual(ScoreboardFontSizePolicy.normalized(0.5, isLargeScreen: true), 0.7)
        XCTAssertEqual(ScoreboardFontSizePolicy.normalized(1.57, isLargeScreen: false), 1.5)
        XCTAssertEqual(ScoreboardFontSizePolicy.normalized(1.13, isLargeScreen: false), 1.15, accuracy: 0.000_001)
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


    func testMultiParticipantRecordDisplayUsesEveryStoredPlayer() {
        let record = ScoreboardRecord(
            id: "multi-test",
            gameType: .multiScoreboard,
            startTime: Date(timeIntervalSince1970: 1),
            team1Name: "甲",
            team2Name: "乙",
            team1FinalScore: 1,
            team2FinalScore: 2,
            totalScoreChanges: 3,
            extraData: [
                "players": AnyCodable([
                    ["name": "甲", "finalScore": 1] as [String: Any],
                    ["name": "乙", "finalScore": 2] as [String: Any],
                    ["name": "丙", "finalScore": 3] as [String: Any]
                ])
            ]
        )
        let summary = ScoreboardRecordSummary(from: record)
        XCTAssertEqual(summary.displayMatchTitle, "甲 vs 乙 vs 丙")
        XCTAssertEqual(summary.displayScore(), "1 : 2 : 3")
    }

    func testDoublesMetadataDoesNotReplaceTwoTeamRecordDisplay() {
        let record = ScoreboardRecord(
            id: "foosball-test",
            gameType: .foosball,
            startTime: Date(timeIntervalSince1970: 1),
            team1Name: "红A/红B",
            team2Name: "蓝A/蓝B",
            team1FinalScore: 2,
            team2FinalScore: 1,
            totalScoreChanges: 3,
            extraData: ["players": AnyCodable([["name": "红A"], ["name": "蓝A"], ["name": "红B"], ["name": "蓝B"]])]
        )
        XCTAssertEqual(record.displayMatchTitle, "红A/红B vs 蓝A/蓝B")
        XCTAssertEqual(record.displayScore(), "2 : 1")
    }
}
