import ScoreCore
import XCTest
@testable import jifen

@MainActor
final class SportsSetupDraftTests: XCTestCase {
    // MARK: - Match feature matrix (对齐安卓 SportsSetupMatchFeatures)

    func testMatchFeatureMatrixMirrorsAndroid() {
        // 乒乓球：单打 3 个，双打 2 个。
        XCTAssertEqual(
            SportsSetupMatchFeature.features(for: .pingpong, isSingles: true),
            [.autoChangeSides, .showMatchTime, .voiceAnnouncement]
        )
        XCTAssertEqual(
            SportsSetupMatchFeature.features(for: .pingpong, isSingles: false),
            [.autoChangeSides, .voiceAnnouncement]
        )
        // 拍类：自动换边 + 语音播报。
        for gameType: jifen.GameType in [.badminton, .tennis, .pickleball, .shuttlecock, .squash, .softTennis, .padel] {
            XCTAssertEqual(
                SportsSetupMatchFeature.features(for: gameType, isSingles: true),
                [.autoChangeSides, .voiceAnnouncement]
            )
        }
        // 排球类：自动换边 + 显示时间 + 语音播报（对齐安卓，3 个排球均含语音播报）。
        for gameType: jifen.GameType in [.volleyball, .beachVolleyball, .airVolleyball] {
            XCTAssertEqual(
                SportsSetupMatchFeature.features(for: gameType, isSingles: true),
                [.autoChangeSides, .showMatchTime, .voiceAnnouncement]
            )
        }
        // 其余项目严格对齐安卓 else -> emptyList：无功能区块（含语音播报）。
        for gameType: jifen.GameType in [
            .basketball, .threeBasketball, .boxing, .archery, .foosball,
            .billiards, .eightBall, .nineBall, .snooker,
            .guandan, .doudizhu, .shengji, .uno,
            .simpleScore, .multiScoreboard, .counter
        ] {
            XCTAssertTrue(
                SportsSetupMatchFeature.features(for: gameType, isSingles: true).isEmpty,
                "\(gameType.rawValue) should expose no match features"
            )
        }
        // 纯计时与棋类：无功能区块。
        for gameType: jifen.GameType in [.stopwatch, .football, .football5v5, .go, .xiangqi, .chess, .checkers] {
            XCTAssertTrue(
                SportsSetupMatchFeature.features(for: gameType, isSingles: true).isEmpty,
                "\(gameType.rawValue) should expose no match features"
            )
        }
    }

    func testMakeResultWritesVoiceAnnouncementOnlyWhenFeaturePresent() {
        // 斯诺克不在矩阵内（安卓无功能区块），不输出该字段。
        var snookerDraft = SportsSetupDraft()
        snookerDraft.initialize(
            gameType: .snooker,
            initialSetup: nil,
            initialMaxSets: nil,
            initialPointsPerSet: nil,
            initialTieBreakPoints: nil
        )
        snookerDraft.voiceAnnouncement = true
        XCTAssertNil(snookerDraft.makeResult(gameType: .snooker, usesDoublesPlayerInputs: false).voiceAnnouncement)

        // 计时项目矩阵为空，不输出该字段。
        var stopwatchDraft = SportsSetupDraft()
        stopwatchDraft.initialize(
            gameType: .stopwatch,
            initialSetup: nil,
            initialMaxSets: nil,
            initialPointsPerSet: nil,
            initialTieBreakPoints: nil
        )
        stopwatchDraft.voiceAnnouncement = true
        XCTAssertNil(stopwatchDraft.makeResult(gameType: .stopwatch, usesDoublesPlayerInputs: false).voiceAnnouncement)
    }

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

    func testAndroid31SetupPresetOrderAndSportSpecificSetChoices() {
        var draft = SportsSetupDraft()
        XCTAssertEqual(draft.pointPresets(for: .pingpong), [5, 7, 9, 11])
        XCTAssertEqual(draft.pointPresets(for: .badminton), [11, 15, 21])
        XCTAssertEqual(draft.pointPresets(for: .shuttlecock), [11, 15, 21])
        XCTAssertEqual(draft.pointPresets(for: .foosball), [5, 7, 8])

        draft.matchCompletionMode = .bestOf
        XCTAssertEqual(draft.matchCompletionPresets(for: .tennis), [1, 3, 5, 7])
        XCTAssertEqual(draft.matchCompletionPresets(for: .foosball), [1, 3, 5, 7])

        draft.matchCompletionMode = .playAll
        XCTAssertEqual(draft.matchCompletionPresets(for: .tennis), [1, 2, 3, 4])
        XCTAssertEqual(draft.matchCompletionPresets(for: .badminton), [1, 2, 3, 4, 5])
        XCTAssertEqual(draft.matchCompletionPresets(for: .foosball), [1, 3, 5, 7])
    }

    func testNewSportDefaultsAndExplicitSetupProjectionMatchAndroid31() {
        var shuttlecock = SportsSetupDraft()
        shuttlecock.initialize(
            gameType: .shuttlecock,
            initialSetup: nil,
            initialMaxSets: nil,
            initialPointsPerSet: nil,
            initialTieBreakPoints: nil
        )
        XCTAssertEqual(shuttlecock.selectedMaxSets, 3)
        XCTAssertEqual(shuttlecock.selectedPointsPerSet, 21)
        let shuttlecockResult = shuttlecock.makeResult(gameType: .shuttlecock, usesDoublesPlayerInputs: false)
        XCTAssertEqual(shuttlecockResult.maxSets, 3)
        XCTAssertEqual(shuttlecockResult.matchCompletionMode, .bestOf)

        var squash = SportsSetupDraft()
        squash.initialize(
            gameType: .squash,
            initialSetup: nil,
            initialMaxSets: nil,
            initialPointsPerSet: nil,
            initialTieBreakPoints: nil
        )
        XCTAssertEqual(squash.selectedMaxSets, 5)

        var softTennis = SportsSetupDraft()
        softTennis.softTennisMatchGames = 9
        let softResult = softTennis.makeResult(gameType: .softTennis, usesDoublesPlayerInputs: true)
        XCTAssertEqual(softResult.maxSets, 1)
        XCTAssertEqual(softResult.gamesPerSet, 4)
        XCTAssertEqual(softResult.tieBreakPoints, 7)
        XCTAssertEqual(softResult.tennisDeuceMode, "advantage")
        XCTAssertEqual(softResult.softTennisMatchGames, 9)

        var padel = SportsSetupDraft()
        padel.padelDeuceMode = .goldenPoint
        let padelResult = padel.makeResult(gameType: .padel, usesDoublesPlayerInputs: true)
        XCTAssertEqual(padelResult.maxSets, 3)
        XCTAssertEqual(padelResult.gamesPerSet, 6)
        XCTAssertEqual(padelResult.tieBreakPoints, 7)
        XCTAssertEqual(padelResult.tennisDeuceMode, PadelDeuceMode.goldenPoint.rawValue)
        XCTAssertEqual(padelResult.padelDeuceMode, .goldenPoint)
    }

    func testPadelIsFixedDoublesAndPreservesFourNamedPlayers() {
        var draft = SportsSetupDraft()
        draft.initialize(
            gameType: .padel,
            initialSetup: nil,
            initialMaxSets: nil,
            initialPointsPerSet: nil,
            initialTieBreakPoints: nil
        )
        XCTAssertFalse(draft.isSingles)
        XCTAssertEqual(draft.competitionFormat, .doubles)

        draft.team1Player1Name = "甲一"
        draft.team1Player2Name = "甲二"
        draft.team2Player1Name = "乙一"
        draft.team2Player2Name = "乙二"
        let result = draft.makeResult(gameType: .padel, usesDoublesPlayerInputs: true)
        XCTAssertEqual(result.competitionFormat, .doubles)
        XCTAssertEqual(result.isSingles, false)
        XCTAssertEqual(result.team1Name, "甲一/甲二")
        XCTAssertEqual(result.team2Name, "乙一/乙二")
        XCTAssertEqual(result.team1Player1Name, "甲一")
        XCTAssertEqual(result.team1Player2Name, "甲二")
        XCTAssertEqual(result.team2Player1Name, "乙一")
        XCTAssertEqual(result.team2Player2Name, "乙二")
    }

    func testShuttlecockTeamFormatBuildsThreePlayerTeamNames() {
        var draft = SportsSetupDraft()
        draft.initialize(
            gameType: .shuttlecock,
            initialSetup: nil,
            initialMaxSets: nil,
            initialPointsPerSet: nil,
            initialTieBreakPoints: nil
        )
        XCTAssertEqual(draft.competitionFormat, .team)
        draft.team1Player1Name = "甲一"
        draft.team1Player2Name = "甲二"
        draft.team1Player3Name = "甲三"
        draft.team2Player1Name = "乙一"
        draft.team2Player2Name = "乙二"
        draft.team2Player3Name = "乙三"

        let result = draft.makeResult(gameType: .shuttlecock, usesDoublesPlayerInputs: false)
        XCTAssertEqual(result.team1Name, "甲一/甲二/甲三")
        XCTAssertEqual(result.team2Name, "乙一/乙二/乙三")
        XCTAssertEqual(result.team1Player3Name, "甲三")
        XCTAssertEqual(result.team2Player3Name, "乙三")
    }

    func testSnookerMatchTitleNormalizesWhitespaceAndFortyCodePointLimit() {
        var draft = SportsSetupDraft()
        draft.matchTitleEnabled = true
        draft.matchTitle = "  全国\n邀请赛   决赛  "
        XCTAssertEqual(
            draft.makeResult(gameType: .snooker, usesDoublesPlayerInputs: false).matchTitle,
            "全国 邀请赛 决赛"
        )

        draft.matchTitle = String(repeating: "赛", count: 45)
        let limited = draft.makeResult(gameType: .snooker, usesDoublesPlayerInputs: false).matchTitle
        XCTAssertEqual(limited?.unicodeScalars.count, 40)

        let setup = SportsSetupResult(team1Name: "A", team2Name: "B", matchTitle: "  半决赛  ")
        var restored = SportsSetupDraft()
        restored.initialize(
            gameType: .snooker,
            initialSetup: setup,
            initialMaxSets: nil,
            initialPointsPerSet: nil,
            initialTieBreakPoints: nil
        )
        XCTAssertTrue(restored.matchTitleEnabled)
        XCTAssertEqual(restored.matchTitle, "  半决赛  ")
        XCTAssertEqual(
            restored.makeResult(gameType: .snooker, usesDoublesPlayerInputs: false).matchTitle,
            "半决赛"
        )
    }

    func testBoxingCustomRoundCountRestoresFromDedicatedField() {
        var setup = SportsSetupResult(team1Name: "A", team2Name: "B")
        setup.maxRounds = 15
        var draft = SportsSetupDraft()
        draft.initialize(
            gameType: .boxing,
            initialSetup: setup,
            initialMaxSets: nil,
            initialPointsPerSet: nil,
            initialTieBreakPoints: nil
        )

        XCTAssertEqual(draft.selectedMaxSets, 15)
        XCTAssertEqual(draft.customMaxSetsText, "15")
        XCTAssertEqual(
            draft.makeResult(gameType: .boxing, usesDoublesPlayerInputs: false).maxRounds,
            15
        )
    }

    func testPickleballRestoreKeepsAndroid31TargetAndCapInsteadOfReapplyingDefaults() {
        var setup = SportsSetupResult(team1Name: "A", team2Name: "B")
        setup.maxSets = 3
        setup.targetScore = 21
        var restored = SportsSetupDraft()
        restored.initialize(
            gameType: .pickleball,
            initialSetup: setup,
            initialMaxSets: nil,
            initialPointsPerSet: nil,
            initialTieBreakPoints: nil
        )
        XCTAssertEqual(restored.pickleballTargetScore, 21)

        setup.targetScore = 11
        setup.scoreCap = 15
        restored.initialize(
            gameType: .pickleball,
            initialSetup: setup,
            initialMaxSets: nil,
            initialPointsPerSet: nil,
            initialTieBreakPoints: nil
        )
        XCTAssertEqual(restored.pickleballTargetScore, 11)
        XCTAssertEqual(restored.pickleballScoreCap, 15)
    }

    func testPickleballPresetSetSelectionUpdatesTargetLikeAndroid31() {
        var draft = SportsSetupDraft()
        draft.initialize(
            gameType: .pickleball,
            initialSetup: nil,
            initialMaxSets: nil,
            initialPointsPerSet: nil,
            initialTieBreakPoints: nil
        )

        draft.pickleballScoreCap = 15
        draft.selectMatchCompletionPreset(1, gameType: .pickleball)
        XCTAssertEqual(draft.selectedMaxSets, 1)
        XCTAssertEqual(draft.pickleballTargetScore, 15)
        XCTAssertNil(draft.pickleballScoreCap)

        draft.selectMatchCompletionPreset(3, gameType: .pickleball)
        XCTAssertEqual(draft.selectedMaxSets, 3)
        XCTAssertEqual(draft.pickleballTargetScore, 11)
    }

    func testRacketSetupResultProjectsIntoExactScoreCoreRules() {
        var pingPongDraft = SportsSetupDraft()
        pingPongDraft.selectedMaxSets = 7
        pingPongDraft.selectedPointsPerSet = 9
        pingPongDraft.isSingles = false
        pingPongDraft.autoChangeSides = false
        let pingPong = pingPongDraft.makeResult(
            gameType: .pingpong,
            usesDoublesPlayerInputs: true
        )
        XCTAssertEqual(pingPong.pingPongRules.maxSets, 7)
        XCTAssertEqual(pingPong.pingPongRules.pointsToWinSet, 9)
        XCTAssertEqual(pingPong.pingPongRules.decidingSetSideSwitchPoint, 4)
        XCTAssertFalse(pingPong.pingPongRules.autoChangeSides)

        for (target, cap) in [(11, 15), (15, 21), (21, 30)] {
            var badmintonDraft = SportsSetupDraft()
            badmintonDraft.selectedMaxSets = 3
            badmintonDraft.selectedPointsPerSet = target
            badmintonDraft.isSingles = false
            let badminton = badmintonDraft.makeResult(
                gameType: .badminton,
                usesDoublesPlayerInputs: true
            )
            XCTAssertEqual(badminton.badmintonRules.pointsToWinSet, target)
            XCTAssertEqual(badminton.badmintonRules.pointCap, cap)
            XCTAssertEqual(
                badminton.badmintonRules.decidingSetSideSwitchPoint,
                RallyRuleSet.decidingSetSideSwitchPoint(
                    for: .badmintonDoubles,
                    pointsPerSet: target
                )
            )
        }

        var tennisDraft = SportsSetupDraft()
        tennisDraft.selectedMaxSets = 5
        tennisDraft.tennisGamesPerSet = 4
        tennisDraft.regularTieBreakPoints = 10
        tennisDraft.tennisDeuceMode = "no_ad"
        tennisDraft.isSingles = false
        let tennis = tennisDraft.makeResult(gameType: .tennis, usesDoublesPlayerInputs: true)
        XCTAssertEqual(tennis.tennisRules.maxSets, 5)
        XCTAssertEqual(tennis.tennisRules.gamesPerSet, 4)
        XCTAssertEqual(tennis.tennisRules.tieBreakPoints, 10)
        XCTAssertTrue(tennis.tennisRules.usesNoAdScoring)
        XCTAssertEqual(tennis.tennisRules.familyProfile, .tennis)

        var softDraft = SportsSetupDraft()
        softDraft.softTennisMatchGames = 9
        XCTAssertEqual(
            softDraft.makeResult(gameType: .softTennis, usesDoublesPlayerInputs: true)
                .softTennisRules.familyProfile,
            .softTennis
        )
        var padelDraft = SportsSetupDraft()
        padelDraft.padelDeuceMode = .goldenPoint
        let padel = padelDraft.makeResult(gameType: .padel, usesDoublesPlayerInputs: true)
        XCTAssertEqual(padel.padelRules.familyProfile, .padel)
        XCTAssertEqual(padel.padelRules.padelDeuceMode, .goldenPoint)
    }

    func testAndroid31PickleballTargetCapAndRallyScoringReachTheEngineUnchanged() {
        var draft = SportsSetupDraft()
        draft.selectedMaxSets = 3
        draft.isSingles = false
        draft.pickleballTargetScore = 21
        draft.pickleballScoreCap = 15
        draft.pickleballUseRallyScoring = true
        let twentyOne = draft.makeResult(gameType: .pickleball, usesDoublesPlayerInputs: true)
        XCTAssertEqual(twentyOne.targetScore, 21)
        XCTAssertNil(twentyOne.scoreCap, "Android 3.1 only projects a cap for target 11")
        XCTAssertEqual(twentyOne.pickleballRules.pointsToWinSet, 21)
        XCTAssertNil(twentyOne.pickleballRules.pointCap)
        XCTAssertTrue(twentyOne.pickleballRules.useRallyScoring)
        XCTAssertEqual(twentyOne.pickleballRules.nextSetServerModel, .alternateFromOpening)
        XCTAssertEqual(twentyOne.pickleballRules.sportProfile, .pickleball)

        draft.pickleballTargetScore = 11
        draft.pickleballScoreCap = 15
        let eleven = draft.makeResult(gameType: .pickleball, usesDoublesPlayerInputs: true)
        XCTAssertEqual(eleven.pickleballRules.pointsToWinSet, 11)
        XCTAssertEqual(eleven.pickleballRules.pointCap, 15)

        var legacy = SportsSetupResult(team1Name: "A", team2Name: "B")
        legacy.targetScore = 99
        legacy.maxSets = nil
        legacy.isSingles = true
        XCTAssertEqual(legacy.pickleballRules.pointsToWinSet, 11)
        XCTAssertEqual(legacy.pickleballRules.maxSets, 3)
        XCTAssertEqual(legacy.pickleballRules.nextSetServerModel, .opening)
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

    func testMatchTimeDraftUsesProjectPreferenceAndExplicitSetupWins() throws {
        let suiteName = "SportsSetupDraftTests.MatchTime.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreferencesManager(defaults: defaults)
        preferences.setScoreboardMatchTimeVisible(true, for: .pingpong)
        preferences.setScoreboardMatchTimeVisible(true, for: .badminton)

        var preferred = SportsSetupDraft()
        preferred.initialize(
            gameType: .pingpong,
            initialSetup: nil,
            initialMaxSets: nil,
            initialPointsPerSet: nil,
            initialTieBreakPoints: nil,
            preferences: preferences
        )
        XCTAssertTrue(preferred.showMatchTime)

        var explicitOff = SportsSetupDraft()
        explicitOff.initialize(
            gameType: .pingpong,
            initialSetup: SportsSetupResult(
                team1Name: "A",
                team2Name: "B",
                isSingles: true,
                showMatchTime: false
            ),
            initialMaxSets: nil,
            initialPointsPerSet: nil,
            initialTieBreakPoints: nil,
            preferences: preferences
        )
        XCTAssertFalse(explicitOff.showMatchTime)

        var unsupported = SportsSetupDraft()
        unsupported.initialize(
            gameType: .badminton,
            initialSetup: nil,
            initialMaxSets: nil,
            initialPointsPerSet: nil,
            initialTieBreakPoints: nil,
            preferences: preferences
        )
        XCTAssertFalse(unsupported.showMatchTime)
    }

    func testMatchTimeResultIsLimitedToSupportedSportsAndModes() {
        var draft = SportsSetupDraft()
        draft.showMatchTime = true
        draft.isSingles = true

        XCTAssertEqual(
            draft.makeResult(gameType: .pingpong, usesDoublesPlayerInputs: false).showMatchTime,
            true
        )
        XCTAssertEqual(
            draft.makeResult(gameType: .volleyball, usesDoublesPlayerInputs: false).showMatchTime,
            true
        )

        draft.isSingles = false
        XCTAssertNil(
            draft.makeResult(gameType: .pingpong, usesDoublesPlayerInputs: true).showMatchTime
        )
        XCTAssertNil(
            draft.makeResult(gameType: .tennis, usesDoublesPlayerInputs: true).showMatchTime
        )
    }

    func testMatchTimePreferencesStayIndependentAndDedicatedClocksAreExcluded() throws {
        let suiteName = "SportsSetupDraftTests.MatchTimeIsolation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreferencesManager(defaults: defaults)

        preferences.setScoreboardMatchTimeVisible(true, for: .volleyball)
        preferences.setScoreboardMatchTimeVisible(false, for: .beachVolleyball)
        preferences.setScoreboardMatchTimeVisible(true, for: .airVolleyball)
        preferences.setScoreboardMatchTimeVisible(true, for: .guandan)
        preferences.setScoreboardMatchTimeVisible(false, for: .shengji)
        preferences.setScoreboardMatchTimeVisible(true, for: .simpleScore)

        XCTAssertTrue(preferences.scoreboardMatchTimeVisible(for: .volleyball))
        XCTAssertFalse(preferences.scoreboardMatchTimeVisible(for: .beachVolleyball))
        XCTAssertTrue(preferences.scoreboardMatchTimeVisible(for: .airVolleyball))
        XCTAssertTrue(preferences.scoreboardMatchTimeVisible(for: .guandan))
        XCTAssertFalse(preferences.scoreboardMatchTimeVisible(for: .shengji))
        XCTAssertTrue(preferences.scoreboardMatchTimeVisible(for: .simpleScore))

        XCTAssertFalse(ScoreboardMatchTimePolicy.supportsGenericClock(
            for: .pingpong,
            setup: SportsSetupResult(team1Name: "A", team2Name: "B", isSingles: false),
            exactScoreCoreGameType: .pingpongDoubles
        ))
        XCTAssertFalse(ScoreboardMatchTimePolicy.supportsGenericClock(for: .basketball, setup: nil))
        XCTAssertFalse(ScoreboardMatchTimePolicy.supportsGenericClock(for: .football, setup: nil))
    }

    func testInMatchClockToggleDoesNotPersistAndFormatsElapsedTime() throws {
        let suiteName = "SportsSetupDraftTests.MatchClockSession.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreferencesManager(defaults: defaults)
        preferences.setScoreboardMatchTimeVisible(true, for: .simpleScore)
        let setup = SportsSetupResult(team1Name: "A", team2Name: "B")
        let session = ScoreboardMatchClockSession(
            isVisible: ScoreboardMatchTimePolicy.initialVisibility(
                for: .simpleScore,
                setup: setup,
                preferences: preferences
            ),
            startedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertTrue(session.isVisible)
        session.isVisible = false
        XCTAssertTrue(preferences.scoreboardMatchTimeVisible(for: .simpleScore))
        XCTAssertEqual(session.elapsed(at: Date(timeIntervalSince1970: 161)), 61)
        XCTAssertEqual(ScoreboardMatchClockSession.formatElapsed(61), "01:01")
        XCTAssertEqual(ScoreboardMatchClockSession.formatElapsed(3_661), "1:01:01")
    }
}
