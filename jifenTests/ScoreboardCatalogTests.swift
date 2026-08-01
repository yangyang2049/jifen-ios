import XCTest
import ScoreCore
import UIKit
@testable import jifen

@MainActor
final class ScoreboardCatalogTests: XCTestCase {
    func testCommonNamePolicyUsesPlayerNamesForSinglesAndDoublesMembers() {
        let playerGames: [jifen.GameType] = [
            .pingpong, .badminton, .tennis, .pickleball, .foosball,
            .archery, .boxing, .billiards, .eightBall, .nineBall, .snooker,
            .doudizhu, .uno, .multiScoreboard
        ]

        for game in playerGames {
            XCTAssertEqual(
                ScoreboardCommonNamePolicy.nameType(for: game),
                .player,
                "\(game) should use common player names"
            )
        }

        let rallyPlayerGames: [ScoreCore.GameType] = [
            .pingpong, .pingpongDoubles,
            .badminton, .badmintonDoubles,
            .tennis, .tennisDoubles,
            .pickleball, .pickleballDoubles,
            .foosball, .foosballDoubles
        ]
        for game in rallyPlayerGames {
            XCTAssertEqual(
                ScoreboardCommonNamePolicy.rallyNameType(for: game),
                .player,
                "\(game) should use common player names"
            )
        }
    }

    func testCommonNamePolicyKeepsActualTeamProjectsOnTeamNames() {
        let teamGames: [jifen.GameType] = [
            .football, .basketball, .threeBasketball,
            .volleyball, .beachVolleyball, .airVolleyball,
            .guandan, .shengji, .simpleScore
        ]

        for game in teamGames {
            XCTAssertEqual(
                ScoreboardCommonNamePolicy.nameType(for: game),
                .team,
                "\(game) should use common team names"
            )
        }

        for game: ScoreCore.GameType in [.volleyball, .beachVolleyball, .airVolleyball] {
            XCTAssertEqual(ScoreboardCommonNamePolicy.rallyNameType(for: game), .team)
        }
    }

    func testCommonNamePolicyExplicitlyPartitionsEveryGameType() {
        let playerGames: Set<jifen.GameType> = [
            .pingpong, .badminton, .tennis,
            .checkers, .boxing, .billiards, .eightBall, .nineBall, .snooker,
            .pickleball, .archery, .doudizhu, .uno, .foosball,
            .multiScoreboard, .stopwatch, .go, .xiangqi, .chess
        ]
        let teamGames: Set<jifen.GameType> = [
            .basketball, .threeBasketball, .football,
            .volleyball, .beachVolleyball, .airVolleyball,
            .guandan, .shengji, .simpleScore, .counter
        ]

        XCTAssertTrue(playerGames.isDisjoint(with: teamGames))
        XCTAssertEqual(playerGames.union(teamGames), Set(jifen.GameType.allCases))

        for game in playerGames {
            XCTAssertEqual(ScoreboardCommonNamePolicy.nameType(for: game), .player)
        }
        for game in teamGames {
            XCTAssertEqual(ScoreboardCommonNamePolicy.nameType(for: game), .team)
        }
    }

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

    func testDialogSurfaceUsesElevatedDarkBackgroundAndWhiteLightBackground() {
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)
        let actual = UIColor(Theme.dialogSurfaceBackground)

        XCTAssertTrue(
            actual.resolvedColor(with: lightTraits).isEqual(
                UIColor.systemBackground.resolvedColor(with: lightTraits)
            )
        )
        XCTAssertTrue(
            actual.resolvedColor(with: darkTraits).isEqual(
                UIColor.secondarySystemBackground.resolvedColor(with: darkTraits)
            )
        )
    }

    func testPrimaryPageCardsShareTheSameStableSurfaceColor() {
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)
        let standard = UIColor(Theme.appCardBackground)
        let expectedDark = UIColor(red: 32 / 255, green: 32 / 255, blue: 34 / 255, alpha: 1)

        XCTAssertTrue(standard.resolvedColor(with: lightTraits).isEqual(UIColor.white))
        XCTAssertTrue(standard.resolvedColor(with: darkTraits).isEqual(expectedDark))

        for cardColor in [Theme.homeNeutralCardBackground, Theme.homeCardDark, Theme.surface] {
            let actual = UIColor(cardColor)
            XCTAssertTrue(
                actual.resolvedColor(with: lightTraits).isEqual(
                    standard.resolvedColor(with: lightTraits)
                )
            )
            XCTAssertTrue(
                actual.resolvedColor(with: darkTraits).isEqual(
                    standard.resolvedColor(with: darkTraits)
                )
            )
        }
    }

    func testTennisInlineScoresReserveCenterLineSpaceAndUseASmallerMainScore() {
        XCTAssertEqual(
            ScoreboardLayoutMetrics.tennisMainScoreScale(hasInlineSecondary: true),
            0.78,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ScoreboardLayoutMetrics.tennisMainScoreScale(hasInlineSecondary: false),
            1,
            accuracy: 0.001
        )

        let halfPanel = CGSize(width: 912, height: 1_365)
        let indicator = ScoreboardLayoutMetrics.serveIndicatorSize(halfViewportSize: halfPanel)
        let clearance = ScoreboardLayoutMetrics.tennisCenterLineClearance(halfViewportSize: halfPanel)
        XCTAssertGreaterThan(clearance, indicator)

        let nameRegion = ScoreboardLayoutMetrics.tennisSinglesNameRegionHeight(
            panelHeight: halfPanel.height,
            nameFontSize: 72
        )
        XCTAssertGreaterThan(nameRegion, 72)
    }

    func testTennisDoublesEditLayoutFitsShortAndRegularLandscapeHeights() {
        func metrics(
            panelHeight: CGFloat,
            screenWidth: CGFloat,
            isLargeScreen: Bool,
            secondaryRowCount: Int = 2
        ) -> TennisDoublesEditLayoutMetrics {
            let namesHeight = ScoreboardLayoutMetrics.doublesEditNamesRegionHeight(
                isLargeScreen: isLargeScreen,
                screenWidth: screenWidth
            )
            return ScoreboardLayoutMetrics.tennisDoublesEditLayout(
                regularMainSize: 148,
                regularSecondarySize: 58,
                panelHeight: panelHeight,
                namesRegionHeight: namesHeight,
                secondaryRowCount: secondaryRowCount,
                isLargeScreen: isLargeScreen
            )
        }

        let compact375 = metrics(panelHeight: 375, screenWidth: 844, isLargeScreen: false)
        let compact390 = metrics(panelHeight: 390, screenWidth: 844, isLargeScreen: false)
        let regular430 = metrics(panelHeight: 430, screenWidth: 932, isLargeScreen: false)
        let tablet684 = metrics(panelHeight: 684, screenWidth: 1_366, isLargeScreen: true)

        for result in [compact375, compact390, regular430, tablet684] {
            XCTAssertLessThanOrEqual(
                result.estimatedContentHeight,
                result.availableScoreHeight + 0.01
            )
        }

        XCTAssertGreaterThan(compact375.mainFontSize, 34)
        XCTAssertGreaterThan(compact375.secondaryFontSize, 24)
        XCTAssertGreaterThan(compact390.mainFontSize, compact375.mainFontSize)
        XCTAssertEqual(
            regular430.mainFontSize,
            ScoreboardLayoutMetrics.tennisDoublesEditMainScoreFontSize(
                regularSize: 148,
                isLargeScreen: false
            )
        )
        XCTAssertEqual(
            tablet684.mainFontSize,
            ScoreboardLayoutMetrics.tennisDoublesEditMainScoreFontSize(
                regularSize: 148,
                isLargeScreen: true
            )
        )

        let tieBreakOnly = metrics(
            panelHeight: 375,
            screenWidth: 844,
            isLargeScreen: false,
            secondaryRowCount: 0
        )
        XCTAssertEqual(tieBreakOnly.mainFontSize, regular430.mainFontSize)
        XCTAssertLessThanOrEqual(
            tieBreakOnly.estimatedContentHeight,
            tieBreakOnly.availableScoreHeight + 0.01
        )
    }

    func testScoreboardNameEditorBreakpointsAndDoublesRegionFitFields() {
        XCTAssertEqual(ScoreboardLayoutMetrics.scoreboardNameEditorWidth(screenWidth: 667), 180)
        XCTAssertEqual(ScoreboardLayoutMetrics.scoreboardNameEditorWidth(screenWidth: 844), 220)
        XCTAssertEqual(ScoreboardLayoutMetrics.scoreboardNameEditorWidth(screenWidth: 1_024), 252)
        XCTAssertEqual(ScoreboardLayoutMetrics.scoreboardNameEditorWidth(screenWidth: 1_200), 300)
        XCTAssertEqual(ScoreboardLayoutMetrics.scoreboardNameEditorWidth(screenWidth: 1_400), 330)
        XCTAssertEqual(ScoreboardLayoutMetrics.scoreboardNameEditorWidth(screenWidth: 1_600), 360)

        XCTAssertEqual(
            ScoreboardLayoutMetrics.scoreboardNameEditorHeight(screenWidth: 844),
            ScoreboardConstants.minimumTouchTarget
        )
        XCTAssertEqual(ScoreboardLayoutMetrics.scoreboardNameEditorHeight(screenWidth: 1_200), 46)
        XCTAssertEqual(ScoreboardLayoutMetrics.scoreboardNameEditorHeight(screenWidth: 1_400), 48)
        XCTAssertEqual(ScoreboardLayoutMetrics.scoreboardNameEditorHeight(screenWidth: 1_600), 52)

        let phoneNamesHeight = ScoreboardLayoutMetrics.doublesEditNamesRegionHeight(
            isLargeScreen: false,
            screenWidth: 844
        )
        let phoneFieldsHeight = ScoreboardConstants.minimumTouchTarget * 2 + 4 + 6 + 4
        XCTAssertGreaterThanOrEqual(phoneNamesHeight, phoneFieldsHeight)
        XCTAssertEqual(
            ScoreboardLayoutMetrics.doublesEditNamesRegionHeight(
                isLargeScreen: true,
                screenWidth: 1_366
            ),
            138
        )
    }

    func testThreeDigitRallyScoresCompactOnTopOfTheUserMultiplier() {
        XCTAssertEqual(ScoreboardLayoutMetrics.threeDigitMainScoreScale(scoreText: "99"), 1)
        XCTAssertEqual(ScoreboardLayoutMetrics.threeDigitMainScoreScale(scoreText: "100"), 0.75)
        XCTAssertEqual(ScoreboardLayoutMetrics.threeDigitMainScoreScale(scoreText: "1,000"), 0.75)

        let preference = ScoreboardTypographyPreference(
            font: .default,
            scoreMultiplier: 1.4,
            nameMultiplier: 1,
            secondaryMultiplier: 1
        )
        let twoDigit = ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .rally,
                containerSize: CGSize(width: 2_000, height: 720),
                nameText: "",
                scoreText: "99",
                preference: preference,
                isLargeScreen: true
            )
        )
        let threeDigit = ScoreboardTypographyResolver.resolve(
            ScoreboardTypographyLayoutContext(
                profile: .rally,
                containerSize: CGSize(width: 2_000, height: 720),
                nameText: "",
                scoreText: "100",
                preference: preference,
                scoreBaseScale: ScoreboardLayoutMetrics.threeDigitMainScoreScale(scoreText: "100"),
                isLargeScreen: true
            )
        )

        XCTAssertEqual(
            threeDigit.scoreFontSize,
            (twoDigit.scoreFontSize * 0.75).rounded(),
            accuracy: 1
        )
    }

    func testFullscreenBarrageControlsClearSafeAreasInPortraitAndLandscape() {
        let portrait = FullscreenBarrageOverlayLayout.padding(
            for: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0),
            rotatesContentClockwise: false
        )
        XCTAssertEqual(portrait.top, 65)
        XCTAssertEqual(portrait.leading, 16)
        XCTAssertEqual(portrait.trailing, 16)

        let landscape = FullscreenBarrageOverlayLayout.padding(
            for: UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 59),
            rotatesContentClockwise: false
        )
        XCTAssertEqual(landscape.top, 6)
        XCTAssertEqual(landscape.leading, 65)
        XCTAssertEqual(landscape.trailing, 65)
    }

    func testFullscreenBarrageControlsRemapSafeAreasForRotatedWindowContent() {
        let rotated = FullscreenBarrageOverlayLayout.padding(
            for: UIEdgeInsets(top: 24, left: 8, bottom: 20, right: 12),
            rotatesContentClockwise: true
        )

        XCTAssertEqual(rotated.top, 18)
        XCTAssertEqual(rotated.leading, 30)
        XCTAssertEqual(rotated.trailing, 26)
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

    func testNormalPageOrientationPolicyAllowsIPadRotationButLocksPhonePortrait() {
        XCTAssertEqual(OrientationLock.defaultOrientation(for: .pad), .all)
        XCTAssertEqual(OrientationLock.defaultOrientation(for: .phone), .portrait)
    }

    func testPadHomeShowsAtMostTenToolsAndPhoneKeepsCuratedTools() {
        XCTAssertEqual(
            HomeToolsLayoutPolicy.tools(isPad: true).map(\.id),
            Array(ToolItem.allTools.prefix(10)).map(\.id)
        )
        XCTAssertLessThanOrEqual(HomeToolsLayoutPolicy.tools(isPad: true).count, 10)

        let compactIDs = HomeToolsLayoutPolicy.tools(isPad: false).map(\.id)
        XCTAssertEqual(compactIDs.count, 8)
        XCTAssertFalse(compactIDs.contains("random_team"))
        XCTAssertFalse(compactIDs.contains("fullscreen_barrage"))
    }

    func testWideHomeToolGridUsesFourToTenColumns() {
        XCTAssertEqual(HomeToolsLayoutPolicy.wideColumnCount(forWidth: 348, toolCount: 10), 4)
        XCTAssertEqual(HomeToolsLayoutPolicy.wideColumnCount(forWidth: 476, toolCount: 10), 4)
        XCTAssertEqual(HomeToolsLayoutPolicy.wideColumnCount(forWidth: 647, toolCount: 10), 6)
        XCTAssertEqual(HomeToolsLayoutPolicy.wideColumnCount(forWidth: 900, toolCount: 10), 9)
        XCTAssertEqual(HomeToolsLayoutPolicy.wideColumnCount(forWidth: 1_200, toolCount: 10), 10)
        XCTAssertEqual(HomeToolsLayoutPolicy.wideColumnCount(forWidth: 2_000, toolCount: 20), 10)
        XCTAssertEqual(HomeToolsLayoutPolicy.wideColumnCount(forWidth: 900, toolCount: 3), 3)
    }

    func testExpandedWhistleCardsUseUpToEightHundredPointsOfContentWidth() {
        XCTAssertEqual(
            WhistleLayoutPolicy.expandedCardSize(
                in: CGSize(width: 1_366, height: 1_024)
            ),
            388
        )
        XCTAssertEqual(
            WhistleLayoutPolicy.expandedCardSize(
                in: CGSize(width: 768, height: 1_024)
            ),
            340
        )
        XCTAssertEqual(
            WhistleLayoutPolicy.expandedCardSize(
                in: CGSize(width: 1_366, height: 300)
            ),
            236
        )
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

    func testBilliardsNewMatchUsesFreshUUIDAndClearsControllerLifecycle() throws {
        let resumedID = "legacy-billiards-record"
        XCTAssertEqual(BilliardsRecordIdentity.initial(resuming: resumedID), resumedID)

        let freshID = BilliardsRecordIdentity.initial(resuming: nil)
        let nextID = BilliardsRecordIdentity.next()
        XCTAssertNotNil(UUID(uuidString: freshID))
        XCTAssertNotNil(UUID(uuidString: nextID))
        XCTAssertNotEqual(freshID, nextID)

        let controller = BilliardsScoreboardController()
        controller.gameActions = ["old-action"]
        controller.gameRecordSaved = true
        let newStart = Date(timeIntervalSince1970: 123)
        controller.beginNewMatch(at: newStart)

        XCTAssertEqual(controller.gameStartTime, newStart)
        XCTAssertTrue(controller.gameActions.isEmpty)
        XCTAssertFalse(controller.gameRecordSaved)
    }

    func testScoreboardRecordIdentityPreservesResumeIDAndUsesFreshUUIDSuffixes() {
        let resumedID = "legacy-record"
        XCTAssertEqual(
            ScoreboardRecordIdentity.initial(prefix: "boxing", resuming: resumedID),
            resumedID
        )

        let prefixes = [
            "simple_score", "multi_scoreboard", "archery_dual", "boxing", "football",
            "guandan", "doudizhu", "shengji", "go", "xiangqi", "chess", "checkers"
        ]
        let ids = prefixes.map { ScoreboardRecordIdentity.next(prefix: $0) }
        XCTAssertEqual(Set(ids).count, ids.count)
        for (prefix, id) in zip(prefixes, ids) {
            XCTAssertTrue(id.hasPrefix("\(prefix)_"))
            XCTAssertNotNil(UUID(uuidString: String(id.dropFirst(prefix.count + 1))))
        }
    }

    func testManualResumeStatesRoundTripWithoutLosingUndoState() throws {
        let lineState = LineScoreState(
            leftName: "红方",
            rightName: "蓝方",
            rules: .freeCounter,
            leftScore: -3,
            rightScore: 8,
            sidesSwapped: true
        )
        let lineResume = LineScoreResumeState(
            state: lineState,
            undoHistory: [.init(state: lineState, restoresNames: true)],
            intentTimeline: ["line-action"]
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                LineScoreResumeState.self,
                from: JSONEncoder().encode(lineResume)
            ).state,
            lineState
        )

        let multiResume = MultiScoreResumeState(
            players: [
                .init(id: 0, name: "甲", score: 12),
                .init(id: 1, name: "乙", score: -2),
                .init(id: 2, name: "丙", score: 7)
            ],
            undoHistory: [[11, -2, 7]],
            intentTimeline: ["multi-action"],
            unoRoundCount: 2,
            targetScore: 500,
            customAdjustEnabled: true,
            useLandscapeLayout: false
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                MultiScoreResumeState.self,
                from: JSONEncoder().encode(multiResume)
            ),
            multiResume
        )

        let boxingState = BoxingMatchState(
            leftName: "拳手 A",
            rightName: "拳手 B",
            maxRounds: 3,
            leftTotal: 10,
            rightTotal: 9,
            leftRoundsWon: 1,
            currentRound: 2
        )
        let boxingResume = BoxingResumeState(
            state: boxingState,
            undoHistory: [.init(state: boxingState, restoresNames: false)],
            intentTimeline: ["boxing-action"]
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                BoxingResumeState.self,
                from: JSONEncoder().encode(boxingResume)
            ),
            boxingResume
        )

        let archeryState = ArcheryMatchState(
            leftName: "射手 A",
            rightName: "射手 B",
            leftArrowSum: 19,
            rightArrowSum: 18,
            leftSetPoints: 2,
            currentSet: 2,
            arrowsLeftThisSet: 2,
            arrowsRightThisSet: 2
        )
        let archeryResume = ArcheryResumeState(
            state: archeryState,
            undoHistory: [archeryState],
            intentTimeline: ["archery-action"]
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                ArcheryResumeState.self,
                from: JSONEncoder().encode(archeryResume)
            ),
            archeryResume
        )
    }

    func testBoxingRestoredSessionKeepsUndoAndNewMatchClearsIt() {
        let controller = BoxingScoreboardController()
        let viewModel = BoxingViewModel(controller: controller)
        let beforeRound = BoxingMatchState(leftName: "A", rightName: "B", maxRounds: 3)
        let afterRound = BoxingMatchState(
            leftName: "A",
            rightName: "B",
            maxRounds: 3,
            leftTotal: 10,
            rightTotal: 9,
            leftRoundsWon: 1,
            currentRound: 2
        )
        viewModel.restoreSession(BoxingResumeState(
            state: afterRound,
            undoHistory: [.init(state: beforeRound, restoresNames: false)],
            intentTimeline: ["round"]
        ))

        XCTAssertTrue(viewModel.undo())
        XCTAssertEqual(viewModel.leftTeam.score, 0)
        XCTAssertEqual(viewModel.currentRound, 1)

        viewModel.addRoundScore(leftPoints: 10, rightPoints: 9)
        viewModel.startNewMatch()
        XCTAssertEqual(viewModel.leftTeam.score, 0)
        XCTAssertEqual(viewModel.rightTeam.score, 0)
        XCTAssertFalse(viewModel.undo())
    }

    func testFootballRestoredSessionKeepsUndoAndNewLifecycleClearsControllerState() {
        let controller = FootballScoreboardController()
        let viewModel = FootballViewModel(controller: controller)
        let initial = LineScoreState(leftName: "主队", rightName: "客队")
        let scored = LineScoreState(
            leftName: "主队",
            rightName: "客队",
            leftScore: 1,
            rightScore: 0
        )
        viewModel.restoreSession(
            state: scored,
            history: [.init(state: initial, restoresNames: false)]
        )
        controller.gameActions = ["goal"]
        controller.gameRecordSaved = true

        XCTAssertTrue(viewModel.undo())
        XCTAssertEqual(viewModel.leftTeam.score, 0)

        controller.beginNewMatch(at: Date(timeIntervalSince1970: 456))
        viewModel.restoreSession(state: initial, history: [])
        XCTAssertEqual(controller.gameStartTime, Date(timeIntervalSince1970: 456))
        XCTAssertTrue(controller.gameActions.isEmpty)
        XCTAssertFalse(controller.gameRecordSaved)
        XCTAssertFalse(viewModel.undo())
    }

    func testLineScoreFreshMatchRestoresOriginalSidesAndClearsFinishedState() {
        let controller = SimpleScoreboardController()
        let viewModel = LineScoreViewModel(controller: controller, rules: .freeCounter)
        viewModel.leftTeam.name = "A"
        viewModel.rightTeam.name = "B"
        viewModel.adjustScore(isLeft: true, delta: 3)
        viewModel.exchangeSides()
        viewModel.endGame()

        let fresh = viewModel.makeFreshMatchState()
        XCTAssertEqual(fresh.leftName, "A")
        XCTAssertEqual(fresh.rightName, "B")
        XCTAssertEqual(fresh.leftScore, 0)
        XCTAssertEqual(fresh.rightScore, 0)
        XCTAssertFalse(fresh.sidesSwapped)
        XCTAssertFalse(fresh.finished)
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

    func testWatchLinkEntryIsAvailableOnlyOnPhone() {
        XCTAssertTrue(AppFeatureFlags.isWatchLinkSupportedHostDevice(.phone))
        XCTAssertFalse(AppFeatureFlags.isWatchLinkSupportedHostDevice(.pad))
        XCTAssertFalse(AppFeatureFlags.isWatchLinkSupportedHostDevice(.mac))
        XCTAssertFalse(AppFeatureFlags.isWatchLinkSupportedHostDevice(.tv))
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

    func testFoosballSetupRejectsScoreCapBelowTarget() {
        let setup = SportsSetupResult(
            team1Name: "A",
            team2Name: "B",
            pointsPerSet: 8,
            winByTwo: true,
            scoreCap: 7
        )

        XCTAssertNil(setup.foosballRules.finalSetPointCap)
    }

    func testSingleSetRallyResultPresentsFinalPointsInsteadOfOneNilSetScore() {
        var state = RallyMatchEngine.initial(
            leftName: "A",
            rightName: "B",
            rules: .foosball(maxSets: 1)
        )
        state.leftPoints = 5
        state.rightPoints = 3
        state.leftSets = 1
        state.finished = true

        let scores = RallyFinishedScorePresentation.scores(for: state)
        XCTAssertEqual(scores.left, 5)
        XCTAssertEqual(scores.right, 3)
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
        let controller = FootballScoreboardController()
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

    func testStandardTeamNamesNormalizeEmptyAndLegacyLabelsWithoutReplacingCustomNames() {
        let expectedRed = NSLocalizedString("watch_team_red", value: "红方", comment: "")
        let expectedBlue = NSLocalizedString("watch_team_blue", value: "蓝方", comment: "")

        let emptyNames = BaseScoreViewModel()
        emptyNames.leftTeam.name = ""
        emptyNames.rightTeam.name = ""
        emptyNames.applyStandardTeamNamesIfNeeded()
        XCTAssertEqual(emptyNames.leftTeam.name, expectedRed)
        XCTAssertEqual(emptyNames.rightTeam.name, expectedBlue)

        let legacyNames = BaseScoreViewModel()
        legacyNames.leftTeam.name = NSLocalizedString("red_team", comment: "")
        legacyNames.rightTeam.name = NSLocalizedString("blue_team", comment: "")
        legacyNames.applyStandardTeamNamesIfNeeded()
        XCTAssertEqual(legacyNames.leftTeam.name, expectedRed)
        XCTAssertEqual(legacyNames.rightTeam.name, expectedBlue)

        let customNames = BaseScoreViewModel()
        customNames.leftTeam.name = "主队"
        customNames.rightTeam.name = "客队"
        customNames.applyStandardTeamNamesIfNeeded()
        XCTAssertEqual(customNames.leftTeam.name, "主队")
        XCTAssertEqual(customNames.rightTeam.name, "客队")
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
