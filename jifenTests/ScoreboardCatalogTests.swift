import XCTest
import ScoreCore
import UIKit
@testable import jifen

@MainActor
final class ScoreboardCatalogTests: XCTestCase {
    func testUnfinishedDoublesTitleGroupsPlayersByTeam() {
        let participants: [SessionParticipant] = [
            .init(id: "left-top", name: "红A"),
            .init(id: "right-top", name: "蓝A"),
            .init(id: "left-bottom", name: "红B"),
            .init(id: "right-bottom", name: "蓝B")
        ]
        XCTAssertEqual(
            UnfinishedGameSummary.matchTitle(participants: participants, gameType: .tennisDoubles),
            "红A/红B vs 蓝A/蓝B"
        )

        let legacy = participants.map { SessionParticipant(id: UUID().uuidString, name: $0.name) }
        XCTAssertEqual(
            UnfinishedGameSummary.matchTitle(participants: legacy, gameType: .foosballDoubles),
            "红A/红B vs 蓝A/蓝B"
        )
        XCTAssertEqual(
            UnfinishedGameSummary.matchTitle(participants: legacy, gameType: .nineBall),
            "红A vs 蓝A"
        )
    }

    func testFamilyRecordFilterKeepsLegacyUnclassifiedRecordsVisible() {
        let legacyRecord = ScoreboardRecord(
            id: "legacy-unclassified",
            gameType: .tennis,
            startTime: Date(timeIntervalSince1970: 1),
            team1Name: "A",
            team2Name: "B",
            team1FinalScore: 1,
            team2FinalScore: 0,
            totalScoreChanges: 1
        )
        let summary = ScoreboardRecordSummary(from: legacyRecord)
        let family = RecordsProjectFilter(gameType: .tennis, scope: .family)
        let singles = RecordsProjectFilter(gameType: .tennis, scope: .exact(.tennis))
        let doubles = RecordsProjectFilter(gameType: .tennis, scope: .exact(.tennisDoubles))

        XCTAssertTrue(family.matches(scoreboard: summary))
        XCTAssertFalse(singles.matches(scoreboard: summary))
        XCTAssertFalse(doubles.matches(scoreboard: summary))
        XCTAssertTrue(family.matches(scoreCoreGameType: .tennisDoubles))
        XCTAssertFalse(singles.matches(scoreCoreGameType: .tennisDoubles))
    }

    func testDialogControlGrayMatchesSegmentedControlFillInLightMode() {
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)
        let actual = UIColor(Theme.dialogControlBackground)

        XCTAssertTrue(
            actual.resolvedColor(with: lightTraits).isEqual(
                UIColor.tertiarySystemFill.resolvedColor(with: lightTraits)
            )
        )
        XCTAssertTrue(
            actual.resolvedColor(with: darkTraits).isEqual(
                UIColor.secondarySystemFill.resolvedColor(with: darkTraits)
            )
        )
    }

    func testTimerAndToolCatalogCountsIncludeNewParityFeatures() {
        XCTAssertEqual(GameCatalog.timerAllItems.count, 7)
        XCTAssertEqual(Set(GameCatalog.timerAllItems).count, 7)
        XCTAssertTrue(GameCatalog.timerAllItems.contains(.checkers))
        XCTAssertEqual(ToolItem.allTools.count, 10)
        XCTAssertTrue(ToolItem.allTools.contains { $0.id == "random_team" })
        XCTAssertTrue(ToolItem.allTools.contains { $0.id == "fullscreen_barrage" })
    }

    func testHomeUsesWideLayoutOnlyForWideIPadWindows() {
        XCTAssertTrue(
            HomeLayoutPolicy.usesWideLayout(
                size: CGSize(width: 1_366, height: 1_024),
                isPad: true
            )
        )
        XCTAssertFalse(
            HomeLayoutPolicy.usesWideLayout(
                size: CGSize(width: 1_024, height: 1_366),
                isPad: true
            )
        )
        XCTAssertFalse(
            HomeLayoutPolicy.usesWideLayout(
                size: CGSize(width: 700, height: 500),
                isPad: true
            )
        )
        XCTAssertFalse(
            HomeLayoutPolicy.usesWideLayout(
                size: CGSize(width: 932, height: 430),
                isPad: false
            )
        )
    }

    func testWideHomeToolsUseCompleteCatalogAndCompactHomeKeepsCuratedTools() {
        XCTAssertEqual(
            HomeToolsLayoutPolicy.tools(isWide: true).map(\.id),
            ToolItem.allTools.map(\.id)
        )

        let compactIDs = HomeToolsLayoutPolicy.tools(isWide: false).map(\.id)
        XCTAssertEqual(compactIDs.count, 8)
        XCTAssertFalse(compactIDs.contains("random_team"))
        XCTAssertFalse(compactIDs.contains("fullscreen_barrage"))
    }

    func testWideHomeToolGridUsesFourToEightColumns() {
        XCTAssertEqual(HomeToolsLayoutPolicy.wideColumnCount(forWidth: 348, toolCount: 10), 4)
        XCTAssertEqual(HomeToolsLayoutPolicy.wideColumnCount(forWidth: 476, toolCount: 10), 4)
        XCTAssertEqual(HomeToolsLayoutPolicy.wideColumnCount(forWidth: 647, toolCount: 10), 6)
        XCTAssertEqual(HomeToolsLayoutPolicy.wideColumnCount(forWidth: 900, toolCount: 10), 8)
        XCTAssertEqual(HomeToolsLayoutPolicy.wideColumnCount(forWidth: 900, toolCount: 3), 3)
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

    func testPhoneWatchStartScopeMatchesExistingWatchMatchProjectsOnly() {
        let supported: Set<jifen.GameType> = [
            .pingpong, .badminton, .tennis, .pickleball,
            .archery, .eightBall, .nineBall, .snooker
        ]
        let actual = Set(GameCatalog.scoreboardItems.map(\.gameType).filter {
            AppFeatureFlags.isWatchLinkSupportedProject($0)
        })
        XCTAssertEqual(actual, supported)
        XCTAssertFalse(AppFeatureFlags.isWatchLinkSupportedProject(.basketball))
        XCTAssertFalse(AppFeatureFlags.isWatchLinkSupportedProject(.threeBasketball))
        XCTAssertFalse(AppFeatureFlags.isWatchLinkSupportedProject(.foosball))
        XCTAssertTrue(AppFeatureFlags.isWatchLinkSupportedSetup(gameType: .pingpong, isSingles: true))
        XCTAssertTrue(AppFeatureFlags.isWatchLinkSupportedSetup(gameType: .pingpong, isSingles: false))
        XCTAssertTrue(AppFeatureFlags.isWatchLinkSupportedSetup(gameType: .nineBall, nineBallPlayerCount: 2))
        XCTAssertTrue(AppFeatureFlags.isWatchLinkSupportedSetup(gameType: .nineBall, nineBallPlayerCount: 4))
        XCTAssertFalse(AppFeatureFlags.isWatchLinkSupportedSetup(gameType: .nineBall, nineBallPlayerCount: 5))
    }

    func testTwentyNineModeAuditMatrixIncludesWatchOnlyBasketballTraining() throws {
        let phoneModes = GameCatalog.scoreboardItems.count
            + GameCatalog.scoreboardItems.map(\.gameType).filter(\.supportsSinglesAndDoubles).count
        XCTAssertEqual(phoneModes, 28)

        let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let managerSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("jifenWatch Watch App/Managers/WatchRecordManager.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(managerSource.contains("guard record.gameType != .basketballTraining else { return }"))
        XCTAssertEqual(phoneModes + 1, 29, "第 29 个实际模式是仅手表端的投篮训练，不参与手机联动")
    }

    func testPickleballUsesTableTennisIcon() throws {
        let pickleballItem = try XCTUnwrap(
            GameCatalog.scoreboardItems.first { $0.gameType == .pickleball }
        )
        XCTAssertEqual(jifen.GameType.pickleball.icon, jifen.GameType.pingpong.icon)
        XCTAssertEqual(pickleballItem.emoji, jifen.GameType.pingpong.icon)
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

    func testPhoneBadmintonSinglesAndDoublesUseConfiguredPointCaps() {
        for isSingles in [true, false] {
            for (target, cap) in [(11, 15), (15, 21), (21, 30)] {
                let setup = SportsSetupResult(
                    team1Name: "A",
                    team2Name: "B",
                    pointsPerSet: target,
                    isSingles: isSingles
                )
                XCTAssertEqual(setup.badmintonRules.pointsToWinSet, target)
                XCTAssertEqual(setup.badmintonRules.pointCap, cap)
            }
        }
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

    func testTypedBilliardsSetupProjectionNormalizesEverySpecializedRule() throws {
        let eight = SportsSetupResult(
            team1Name: "A",
            team2Name: "B",
            maxSets: 5,
            eightBallHandicapRacks: 9,
            eightBallHandicapBeneficiary: "team2"
        )
        guard case let .eightBall(target, handicap, beneficiary) = eight.billiardsConfiguration(for: .eightBall) else {
            return XCTFail("missing eight-ball projection")
        }
        XCTAssertEqual(target, 5)
        XCTAssertEqual(handicap, 4)
        XCTAssertEqual(beneficiary, .right)

        let nine = SportsSetupResult(
            team1Name: "A", team2Name: "B", team3Name: "C",
            nineBallBigGold: 120, nineBallFoul: -1,
            playerCount: 3, playerNames: ["A", "B", "C"]
        )
        guard case let .nineBall(names, points) = nine.billiardsConfiguration(for: .nineBall) else {
            return XCTFail("missing nine-ball projection")
        }
        XCTAssertEqual(names, ["A", "B", "C"])
        XCTAssertEqual(points.bigGold, 99)
        XCTAssertEqual(points.foul, 0)

        let snooker = SportsSetupResult(team1Name: "A", team2Name: "B", maxSets: 4, servingSide: "right")
        guard case let .snooker(frames, breaker) = snooker.billiardsConfiguration(for: .snooker) else {
            return XCTFail("missing snooker projection")
        }
        XCTAssertEqual(frames, 5)
        XCTAssertEqual(breaker, .right)
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

    func testNineBallRecordDisplayUsesAllFourPlayers() {
        let players: [[String: Any]] = (0..<4).map { index in
            ["name": "P\(index + 1)", "finalScore": index * 3]
        }
        let record = ScoreboardRecord(
            id: "nine-four",
            gameType: .nineBall,
            startTime: Date(timeIntervalSince1970: 1),
            team1Name: "P1",
            team2Name: "P2",
            team1FinalScore: 0,
            team2FinalScore: 3,
            totalScoreChanges: 1,
            extraData: ["players": AnyCodable(players)]
        )
        XCTAssertEqual(record.displayParticipants.map(\.name), ["P1", "P2", "P3", "P4"])
        XCTAssertEqual(record.displayParticipants.map(\.score), [0, 3, 6, 9])
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

    func testFootballBoundariesExchangeUndoResetAndFinishLock() {
        let controller = FootballController()
        let viewModel = FootballViewModel(controller: controller)
        viewModel.leftTeam.name = "主队"
        viewModel.rightTeam.name = "客队"

        viewModel.subtractScore(isLeft: true, points: 1)
        XCTAssertEqual(viewModel.leftTeam.score, 0)
        viewModel.addScore(isLeft: true, points: 2)
        viewModel.addScore(isLeft: false, points: 1)

        viewModel.exchangeSides()
        XCTAssertEqual(viewModel.leftTeam.name, "客队")
        XCTAssertEqual(viewModel.leftTeam.score, 1)
        XCTAssertTrue(viewModel.undo())
        XCTAssertEqual(viewModel.leftTeam.name, "主队")
        XCTAssertEqual(viewModel.leftTeam.score, 2)

        viewModel.exchangeSides()
        viewModel.reset()
        XCTAssertEqual(viewModel.leftTeam.name, "主队")
        XCTAssertEqual(viewModel.rightTeam.name, "客队")
        XCTAssertEqual(viewModel.leftTeam.score, 0)
        XCTAssertEqual(viewModel.rightTeam.score, 0)

        viewModel.endGame()
        viewModel.addScore(isLeft: true, points: 1)
        XCTAssertEqual(viewModel.leftTeam.score, 0)
        XCTAssertTrue(viewModel.undo())
        XCTAssertFalse(viewModel.gameFinished)
    }

    func testBoxingFinalRoundUndoRestoresAnEditableMatch() {
        let controller = BoxingScoreboardController()
        let viewModel = BoxingViewModel(controller: controller)
        viewModel.leftTeam.name = "红方"
        viewModel.rightTeam.name = "蓝方"
        viewModel.setMaxRounds(2)

        viewModel.addRoundScore(leftPoints: 10, rightPoints: 10)
        XCTAssertEqual(viewModel.currentRound, 2)
        XCTAssertEqual(viewModel.leftTeam.sets, 0)
        XCTAssertEqual(viewModel.rightTeam.sets, 0)

        viewModel.addRoundScore(leftPoints: 10, rightPoints: 9)
        XCTAssertTrue(viewModel.gameFinished)
        XCTAssertEqual(viewModel.leftTeam.score, 20)
        XCTAssertTrue(viewModel.undo())
        XCTAssertFalse(viewModel.gameFinished)
        XCTAssertEqual(viewModel.currentRound, 2)
        XCTAssertEqual(viewModel.leftTeam.score, 10)
        XCTAssertEqual(viewModel.rightTeam.score, 10)

        viewModel.exchangeSides()
        XCTAssertEqual(viewModel.leftTeam.name, "蓝方")
        XCTAssertTrue(viewModel.undo())
        XCTAssertEqual(viewModel.leftTeam.name, "红方")
        XCTAssertEqual(viewModel.rightTeam.name, "蓝方")
    }

    func testGenericBilliardsScoreBoundariesAndUndo() {
        let controller = BilliardsScoreboardController()
        let viewModel = BaseScoreViewModel(controller: controller, scoreRange: 0 ... 9999)

        XCTAssertEqual(controller.getScoringOptions(), [])
        viewModel.subtractScore(isLeft: true, points: 1)
        XCTAssertEqual(viewModel.leftTeam.score, 0)
        viewModel.adjustScore(isLeft: true, delta: 20_000)
        XCTAssertEqual(viewModel.leftTeam.score, 9999)
        XCTAssertTrue(viewModel.undo())
        XCTAssertEqual(viewModel.leftTeam.score, 0)
    }

    func testSimpleScoreAllowsNegativeValuesButRespectsHardBounds() {
        let controller = SimpleScoreboardController()
        let viewModel = LineScoreViewModel(controller: controller, rules: .freeCounter)

        viewModel.adjustScore(isLeft: true, delta: -20_000)
        XCTAssertEqual(viewModel.leftTeam.score, -9999)
        viewModel.adjustScore(isLeft: true, delta: 40_000)
        XCTAssertEqual(viewModel.leftTeam.score, 9999)
        XCTAssertTrue(viewModel.undo())
        XCTAssertEqual(viewModel.leftTeam.score, -9999)
    }

    func testMultiScorePlayerScoreAndWinnerBoundaries() {
        XCTAssertEqual(MultiScoreRules.normalizedPlayerCount(1, gameType: .multiScoreboard), 3)
        XCTAssertEqual(MultiScoreRules.normalizedPlayerCount(12, gameType: .multiScoreboard), 9)
        XCTAssertEqual(MultiScoreRules.normalizedPlayerCount(1, gameType: .uno), 2)
        XCTAssertEqual(MultiScoreRules.normalizedPlayerCount(12, gameType: .uno), 10)
        XCTAssertEqual(MultiScoreRules.adjustedScore(9990, delta: 100), 9999)
        XCTAssertEqual(MultiScoreRules.adjustedScore(-9990, delta: -100), -9999)
        XCTAssertNil(MultiScoreRules.uniqueLeaderIndex(scores: [8, 8, 3]))
        XCTAssertEqual(MultiScoreRules.uniqueLeaderIndex(scores: [8, 6, 3]), 0)
        XCTAssertEqual(MultiScoreRules.targetWinnerIndex(scores: [499, 500, 700], target: 500), 1)
    }
}
