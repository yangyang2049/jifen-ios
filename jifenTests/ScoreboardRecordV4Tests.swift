import LinkCore
import RecordCore
import ScoreCore
import SessionCore
import XCTest
@testable import jifen

@MainActor
final class ScoreboardRecordV4Tests: XCTestCase {
    func testV3RecordDecodesWithoutV4Fields() throws {
        let old = makeRecord(schemaVersion: 3, actions: ["left +1"])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encode(old)) as? [String: Any])
        object.removeValue(forKey: "detailedActions")
        object.removeValue(forKey: "setResults")
        object["schemaVersion"] = 3

        let decoded = try decoder().decode(ScoreboardRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.schemaVersion, 3)
        XCTAssertNil(decoded.detailedActions)
        XCTAssertNil(decoded.setResults)
        XCTAssertEqual(decoded.actions, ["left +1"])
    }

    func testV4DetailedActionsRoundTrip() throws {
        let action = DetailedScoreAction(
            type: .scoreChanged,
            epochMilliseconds: 1_700_000_000_000,
            team: .team1,
            scores: [1, 0],
            setScores: [0, 0],
            setNumber: 1,
            scoreChange: 1,
            operationCode: "point"
        )
        let result = RecordSetResult(number: 1, scores: [11, 7], winner: .team1)
        var record = makeRecord()
        record.detailedActions = [action]
        record.setResults = [result]

        let decoded = try decoder().decode(ScoreboardRecord.self, from: encode(record))
        XCTAssertEqual(decoded.schemaVersion, 4)
        XCTAssertEqual(decoded.detailedActions, [action])
        XCTAssertEqual(decoded.setResults, [result])
    }

    func testUserDefaultsBlobMigratesToIndividualAtomicFilesAndKeepsBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("record-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScoreboardRecordFileStore(rootURL: root)
        let records = [makeRecord(id: "one", actions: ["left +1"]), makeRecord(id: "two", actions: ["right +1"])]

        try store.migrateIfNeeded(legacyData: encode(records))
        let migrated = store.loadRecords()

        XCTAssertEqual(Set(migrated.map(\.id)), ["one", "two"])
        XCTAssertTrue(migrated.allSatisfy { $0.schemaVersion == 4 && $0.detailedActions?.isEmpty == false })
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("scoreboard-records-v3-backup.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("index.json").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".record.json") }.count, 2)
    }

    func testCorruptedRecordIsSkippedWithoutLosingHealthyRecord() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("record-corrupt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScoreboardRecordFileStore(rootURL: root)
        try store.migrateIfNeeded(legacyData: nil)
        try store.save(makeRecord(id: "healthy"))
        try Data("not-json".utf8).write(to: root.appendingPathComponent("broken.record.json"), options: .atomic)

        XCTAssertEqual(store.loadRecords().map(\.id), ["healthy"])
    }

    func testRecordStorePropagatesSaveFailureInsteadOfSilentlyDroppingRecord() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("record-save-failure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not-a-directory".utf8).write(to: root, options: .atomic)
        let store = ScoreboardRecordFileStore(rootURL: root)

        XCTAssertThrowsError(try store.save(makeRecord(id: "must-not-disappear")))
    }

    func testAll23ProjectPoliciesMatchDetailMatrix() {
        let trend: Set<jifen.GameType> = [
            .pingpong, .badminton, .pickleball, .basketball, .threeBasketball,
            .volleyball, .beachVolleyball, .airVolleyball, .archery, .billiards,
            .nineBall, .snooker, .foosball, .simpleScore
        ]
        let noTrend: Set<jifen.GameType> = [
            .tennis, .football, .boxing, .eightBall, .doudizhu, .guandan,
            .shengji, .uno, .multiScoreboard
        ]
        XCTAssertEqual(trend.count + noTrend.count, 23)
        for game in trend { XCTAssertTrue(ScoreboardRecordProjectPolicy.policy(for: game).trendAllowed, "\(game)") }
        for game in noTrend { XCTAssertFalse(ScoreboardRecordProjectPolicy.policy(for: game).trendAllowed, "\(game)") }
        XCTAssertEqual(ScoreboardRecordProjectPolicy.policy(for: .tennis).recapKind, .tennisSets)
        XCTAssertEqual(ScoreboardRecordProjectPolicy.policy(for: .basketball).recapKind, .periods)
        XCTAssertEqual(ScoreboardRecordProjectPolicy.policy(for: .boxing).recapKind, .rounds)
        XCTAssertEqual(ScoreboardRecordProjectPolicy.policy(for: .multiScoreboard).recapKind, .ranking)
    }

    func testTrendUsesRealScoreChangesAndResetStartsNewSegment() {
        var record = makeRecord()
        record.detailedActions = [
            .init(type: .scoreChanged, scores: [1, 0], scoreChange: 1),
            .init(type: .foul, scores: [1, 0]),
            .init(type: .scoreChanged, scores: [1, 1], scoreChange: 1),
            .init(type: .reset, scores: [1, 1]),
            .init(type: .scoreChanged, scores: [0, 1], scoreChange: 1),
            .init(type: .scoreChanged, scores: [1, 1], scoreChange: 1)
        ]
        let presentation = ScoreboardRecordPresentation(record: record)
        XCTAssertEqual(presentation.trend.map(\.segment), [0, 0, 1, 1])
        XCTAssertTrue(presentation.canShowTrend)
    }

    func testTrendFallsBackAcrossPeriodSetAndRoundNumbers() {
        var record = makeRecord()
        record.detailedActions = [
            .init(type: .scoreChanged, scores: [1, 0], setNumber: 1, scoreChange: 1),
            .init(type: .scoreChanged, scores: [0, 1], periodNumber: 2, scoreChange: 1),
            .init(type: .scoreChanged, scores: [2, 0], roundNumber: 3, scoreChange: 1),
        ]

        let presentation = ScoreboardRecordPresentation(record: record)

        XCTAssertEqual(presentation.trend.compactMap(\.period), [1, 2, 3])
        XCTAssertEqual(presentation.recap.count, 1)
        XCTAssertEqual(presentation.recap.first?.actions.count, 3)
    }

    func testStandaloneWatchIngestKeepsStructuredActions() throws {
        let id = "watch-ingest-\(UUID().uuidString)"
        let actions = [
            DetailedScoreAction(type: .matchStarted, epochMilliseconds: 1_000, scores: [0, 0]),
            DetailedScoreAction(type: .scoreChanged, epochMilliseconds: 2_000, team: .team1, scores: [1, 0], scoreChange: 1, operationCode: "point"),
            DetailedScoreAction(type: .setFinished, epochMilliseconds: 3_000, scores: [21, 19], setScores: [1, 0], setNumber: 1, winner: .team1)
        ]
        let payload = WatchRecordTransferPayload(
            id: id,
            gameType: "badminton",
            startTimeEpochMilliseconds: 1_000,
            endTimeEpochMilliseconds: 4_000,
            durationSeconds: 3,
            team1Name: "甲",
            team2Name: "乙",
            team1FinalScore: 21,
            team2FinalScore: 19,
            team1SetScore: 1,
            team2SetScore: 0,
            winner: "甲",
            actions: ["point"],
            detailedActions: actions,
            totalScoreChanges: 1,
            projectConfiguration: ["isDoubles": "true"]
        )

        let record = try WatchStandaloneRecordIngestor.makeRecord(payload)
        XCTAssertEqual(record.detailedActions, actions)
        XCTAssertEqual(record.setResults?.first?.scores, [21, 19])
        XCTAssertEqual(record.totalScoreChanges, 1)
        XCTAssertEqual(record.resolvedScoreCoreGameType, .badmintonDoubles)
        XCTAssertEqual(ScoreboardRecordConfiguration.setup(from: record).isSingles, false)
    }

    func testLinkedWatchIngestKeepsSameTimeline() throws {
        let id = "w_link_ingest_\(UUID().uuidString)"
        let action = DetailedScoreAction(
            type: .scoreChanged,
            epochMilliseconds: 2_000,
            team: .team2,
            scores: [0, 1],
            scoreChange: 1,
            operationCode: "point"
        )
        var state = RallyMatchEngine.initial(leftName: "甲", rightName: "乙", rules: .badminton())
        state.rightPoints = 1
        let payload = LinkMatchFinishedPayload(
            snapshot: .rally(state),
            recordId: id,
            winnerSide: .right,
            startTimeEpochMilliseconds: 1_000,
            endTimeEpochMilliseconds: 3_000,
            durationSeconds: 2,
            totalScoreChanges: 1,
            detailedActions: [action]
        )

        let record = try LinkedMatchRecordIngestor.makeRecord(
            payload: payload,
            gameType: ScoreCore.GameType.badmintonDoubles
        )
        XCTAssertEqual(record.detailedActions, [action])
        XCTAssertEqual(record.totalScoreChanges, 1)
        XCTAssertEqual(record.resolvedScoreCoreGameType, .badmintonDoubles)
    }

    func testTiebreakOnlyTennisConfigurationAndLegacyOverviewOmitGames() {
        for coreType in [ScoreCore.GameType.tennis, .tennisDoubles] {
            let state = TennisMatchState(
                leftName: "甲",
                rightName: "乙",
                rules: TennisRuleSet(
                    maxSets: 1,
                    tieBreakPoints: 10,
                    setScoringMode: .tiebreakOnly
                ),
                doublesPlayerNames: coreType == .tennisDoubles
                    ? ["甲A", "乙A", "甲B", "乙B"]
                    : nil
            )
            let configuration = ScoreboardRecordConfiguration.tennis(
                gameType: coreType,
                state: state,
                voiceAnnouncement: false
            )
            let record = ScoreboardRecord(
                id: coreType.rawValue,
                gameType: .tennis,
                startTime: Date(timeIntervalSince1970: 1),
                team1Name: "甲",
                team2Name: "乙",
                team1FinalScore: 10,
                team2FinalScore: 8,
                team1SetScore: 0,
                team2SetScore: 0,
                totalScoreChanges: 18,
                projectConfiguration: configuration
            )

            XCTAssertNil(configuration["gamesPerSet"], coreType.rawValue)
            XCTAssertTrue(record.isTennisTiebreakOnly, coreType.rawValue)
            XCTAssertFalse(record.shouldDisplaySecondaryScore, coreType.rawValue)
        }
    }

    func testLegacyTiebreakOnlySnapshotRestoresFormatWithoutGamesMetadata() throws {
        let state = TennisMatchState(
            leftName: "甲",
            rightName: "乙",
            rules: TennisRuleSet(
                maxSets: 1,
                tieBreakPoints: 10,
                setScoringMode: .tiebreakOnly
            )
        )
        let session = ScoreSession<TennisMatchState, TennisMatchEvent>(
            gameType: .tennisDoubles,
            ruleFamily: .s1,
            reducerType: ScoreboardKernelRegistry.descriptor(for: .tennisDoubles).reducerType,
            state: state
        )
        var record = ScoreboardRecord(
            id: "legacy-tiebreak-snapshot",
            gameType: .tennis,
            startTime: Date(timeIntervalSince1970: 1),
            team1Name: "甲",
            team2Name: "乙",
            team1FinalScore: 10,
            team2FinalScore: 8,
            team1SetScore: 0,
            team2SetScore: 0,
            totalScoreChanges: 18
        )
        record.stateSnapshot = try JSONEncoder().encode(session)

        XCTAssertTrue(record.isTennisTiebreakOnly)
        XCTAssertEqual(record.tennisTieBreakPoints, 10)
        XCTAssertFalse(record.shouldDisplaySecondaryScore)
        XCTAssertEqual(record.resolvedScoreCoreGameType, .tennisDoubles)
        let setup = ScoreboardRecordConfiguration.setup(from: record)
        XCTAssertEqual(setup.setScoringMode, "tiebreak_only")
        XCTAssertEqual(setup.tieBreakPoints, 10)
        XCTAssertNil(setup.gamesPerSet)
    }

    func testLinkedTiebreakOnlyTennisRecordUsesPointsAndStripsGamesData() throws {
        var state = TennisMatchState(
            leftName: "甲",
            rightName: "乙",
            rules: TennisRuleSet(
                maxSets: 1,
                tieBreakPoints: 10,
                setScoringMode: .tiebreakOnly
            )
        )
        state.leftPoints = 10
        state.rightPoints = 8
        state.finished = true
        let action = DetailedScoreAction(
            type: .matchFinished,
            scores: [10, 8],
            setScores: [0, 0],
            winner: .team1
        )
        let payload = LinkMatchFinishedPayload(
            snapshot: .tennis(state),
            recordId: "linked-tennis-tiebreak",
            winnerSide: .left,
            startTimeEpochMilliseconds: 1_000,
            endTimeEpochMilliseconds: 3_000,
            durationSeconds: 2,
            totalScoreChanges: 18,
            detailedActions: [action]
        )

        let record = try LinkedMatchRecordIngestor.makeRecord(
            payload: payload,
            gameType: .tennis
        )

        XCTAssertEqual(record.team1FinalScore, 10)
        XCTAssertEqual(record.team2FinalScore, 8)
        XCTAssertNil(record.team1SetScore)
        XCTAssertNil(record.team2SetScore)
        XCTAssertEqual(record.detailedActions?.first?.setScores, [])
        XCTAssertNil(record.projectConfiguration?["gamesPerSet"])
    }

    func testStandaloneWatchTiebreakOnlyTennisRecordStripsGamesData() throws {
        let action = DetailedScoreAction(
            type: .matchFinished,
            scores: [7, 5],
            setScores: [0, 0],
            winner: .team1
        )
        let payload = WatchRecordTransferPayload(
            id: "watch-tennis-tiebreak",
            gameType: "tennis_doubles",
            startTimeEpochMilliseconds: 1_000,
            endTimeEpochMilliseconds: 3_000,
            durationSeconds: 2,
            team1Name: "甲",
            team2Name: "乙",
            team1FinalScore: 7,
            team2FinalScore: 5,
            team1SetScore: 0,
            team2SetScore: 0,
            winner: "甲",
            actions: [],
            detailedActions: [action],
            totalScoreChanges: 12,
            projectConfiguration: [
                "setScoringMode": "tiebreak_only",
                "tieBreakPoints": "7"
            ]
        )

        let record = try WatchStandaloneRecordIngestor.makeRecord(payload)

        XCTAssertEqual(record.team1FinalScore, 7)
        XCTAssertEqual(record.team2FinalScore, 5)
        XCTAssertNil(record.team1SetScore)
        XCTAssertNil(record.team2SetScore)
        XCTAssertEqual(record.detailedActions?.first?.setScores, [])
        XCTAssertEqual(record.resolvedScoreCoreGameType, .tennisDoubles)
    }

    func testTiebreakOnlyTennisPresentationOmitsRedundantMatchFinishedAction() {
        for coreType in [ScoreCore.GameType.tennis, .tennisDoubles] {
            let scoreAction = DetailedScoreAction(
                type: .scoreChanged,
                scores: [7, 2],
                scoreChange: 1,
                operationCode: "point"
            )
            let finishedAction = DetailedScoreAction(
                type: .matchFinished,
                scores: [7, 2],
                winner: .team1,
                operationCode: "finish"
            )
            let record = ScoreboardRecord(
                id: "presentation-\(coreType.rawValue)",
                gameType: .tennis,
                startTime: Date(timeIntervalSince1970: 1),
                team1Name: "甲",
                team2Name: "乙",
                team1FinalScore: 7,
                team2FinalScore: 2,
                detailedActions: [scoreAction, finishedAction],
                totalScoreChanges: 7,
                projectConfiguration: [
                    "scoreCoreGameType": AnyCodable(coreType.rawValue),
                    "setScoringMode": AnyCodable("tiebreak_only"),
                    "tieBreakPoints": AnyCodable(7)
                ]
            )

            let presentation = ScoreboardRecordPresentation(record: record)

            XCTAssertEqual(presentation.actions.map(\.type), [.scoreChanged], coreType.rawValue)
            XCTAssertEqual(presentation.recap.first?.actions.map(\.type), [.scoreChanged], coreType.rawValue)
        }
    }

    func testAllTenSinglesAndDoublesModesRoundTripStableIdentityAndSetup() throws {
        let rallyModes: [(ScoreCore.GameType, RallyRuleSet)] = [
            (.pingpong, .pingPong(maxSets: 5, matchCompletionMode: .playAll)),
            (.pingpongDoubles, .pingPong(maxSets: 5, matchCompletionMode: .playAll)),
            (.badminton, .badminton(maxSets: 5, matchCompletionMode: .playAll)),
            (.badmintonDoubles, .badminton(maxSets: 5, matchCompletionMode: .playAll)),
            (.pickleball, .pickleball(maxSets: 5, matchCompletionMode: .playAll)),
            (.pickleballDoubles, .pickleball(maxSets: 5, matchCompletionMode: .playAll)),
            (.foosball, .foosball(maxSets: 5)),
            (.foosballDoubles, .foosball(maxSets: 5))
        ]
        let doublesParticipants: [SessionParticipant] = [
            .init(id: "left-top", name: "红A", role: "player"),
            .init(id: "left-bottom", name: "红B", role: "player"),
            .init(id: "right-top", name: "蓝A", role: "player"),
            .init(id: "right-bottom", name: "蓝B", role: "player")
        ]

        for (coreType, rules) in rallyModes {
            let appType = try XCTUnwrap(jifen.GameType(scoreCoreGameType: coreType))
            let store = RallySessionStore(
                leftName: "红队",
                rightName: "蓝队",
                gameType: coreType,
                rules: rules,
                participants: coreType.isDoublesScoreboard ? doublesParticipants : nil,
                openingServer: .right,
                voiceAnnouncementEnabled: true
            )
            let configuration = ScoreboardRecordConfiguration.rally(
                gameType: coreType,
                state: store.state,
                voiceAnnouncement: true
            )
            let record = makeConfigurationRecord(gameType: appType, configuration: configuration)
            let setup = ScoreboardRecordConfiguration.setup(from: record)

            XCTAssertEqual(record.resolvedScoreCoreGameType, coreType, coreType.rawValue)
            XCTAssertEqual(setup.isSingles, !coreType.isDoublesScoreboard, coreType.rawValue)
            XCTAssertEqual(setup.maxSets, rules.maxSets, coreType.rawValue)
            XCTAssertEqual(setup.pointsPerSet, rules.pointsToWinSet, coreType.rawValue)
            XCTAssertEqual(setup.servingSide, MatchSide.right.rawValue, coreType.rawValue)
            XCTAssertEqual(setup.voiceAnnouncement, true, coreType.rawValue)
            if coreType.isDoublesScoreboard {
                XCTAssertEqual(
                    [setup.team1Player1Name, setup.team2Player1Name, setup.team1Player2Name, setup.team2Player2Name],
                    ["红A", "蓝A", "红B", "蓝B"],
                    coreType.rawValue
                )
            }
        }

        for coreType in [ScoreCore.GameType.tennis, .tennisDoubles] {
            let doublesNames = coreType == .tennisDoubles ? ["红A", "蓝A", "红B", "蓝B"] : nil
            let rules = TennisRuleSet(
                maxSets: 5,
                tieBreakPoints: 10,
                gamesPerSet: 4,
                matchCompletionMode: .playAll,
                usesNoAdScoring: true,
                autoChangeSides: false
            )
            let state = TennisMatchState(
                leftName: "红队",
                rightName: "蓝队",
                rules: rules,
                openingServer: .right,
                doublesPlayerNames: doublesNames
            )
            let appType = try XCTUnwrap(jifen.GameType(scoreCoreGameType: coreType))
            let record = makeConfigurationRecord(
                gameType: appType,
                configuration: ScoreboardRecordConfiguration.tennis(
                    gameType: coreType,
                    state: state,
                    voiceAnnouncement: true
                )
            )
            let setup = ScoreboardRecordConfiguration.setup(from: record)

            XCTAssertEqual(record.resolvedScoreCoreGameType, coreType)
            XCTAssertEqual(setup.isSingles, coreType == .tennis)
            XCTAssertEqual(setup.maxSets, 5)
            XCTAssertEqual(setup.tieBreakPoints, 10)
            XCTAssertEqual(setup.gamesPerSet, 4)
            XCTAssertEqual(setup.matchCompletionMode, .playAll)
            XCTAssertEqual(setup.tennisDeuceMode, "no_ad")
            XCTAssertEqual(setup.autoChangeSides, false)
            XCTAssertEqual(setup.servingSide, MatchSide.right.rawValue)
            if coreType == .tennisDoubles {
                XCTAssertEqual(
                    [setup.team1Player1Name, setup.team2Player1Name, setup.team1Player2Name, setup.team2Player2Name],
                    ["红A", "蓝A", "红B", "蓝B"]
                )
            }
        }
    }

    func testOldRecordModeInferenceSupportsRawSessionAndResumeBundleButLeavesUnknownUnclassified() throws {
        let state = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: .badminton())
        let session = ScoreSession<RallyMatchState, RallyMatchEvent>(
            gameType: .badmintonDoubles,
            ruleFamily: .s1,
            reducerType: ScoreboardKernelRegistry.descriptor(for: .badmintonDoubles).reducerType,
            state: state
        )
        var rawRecord = makeConfigurationRecord(gameType: .badminton, configuration: nil)
        rawRecord.stateSnapshot = try JSONEncoder().encode(session)
        XCTAssertEqual(rawRecord.resolvedScoreCoreGameType, .badmintonDoubles)

        let bundle = ScoreSessionResumeBundle<RallyMatchState, RallyMatchEvent, RallyMatchIntent>(
            replaySeed: session,
            currentSession: session,
            undoFrames: [],
            timeline: []
        )
        var bundleRecord = makeConfigurationRecord(gameType: .badminton, configuration: nil)
        bundleRecord.stateSnapshot = try JSONEncoder().encode(bundle)
        XCTAssertEqual(bundleRecord.resolvedScoreCoreGameType, .badmintonDoubles)

        let unknown = makeConfigurationRecord(gameType: .badminton, configuration: nil)
        XCTAssertNil(unknown.resolvedScoreCoreGameType)
        XCTAssertEqual(unknown.competitionDisplayName, jifen.GameType.badminton.displayName)
    }

    func testGuandanUnoAndCustomAdjustmentConfigurationRestoresFromRecord() {
        let record = ScoreboardRecord(
            id: "configuration-special",
            gameType: .guandan,
            startTime: Date(timeIntervalSince1970: 1),
            team1Name: "甲",
            team2Name: "乙",
            team1FinalScore: 2,
            team2FinalScore: 1,
            totalScoreChanges: 1,
            extraData: [
                "guandanTripleA": AnyCodable(true),
                "guandanPassACondition": AnyCodable("double_up"),
                "guandanTripleAFallbackRank": AnyCodable("K"),
                "multiScoreCustomAdjustEnabled": AnyCodable(true),
                "unoTargetScore": AnyCodable(700)
            ],
            projectConfiguration: [
                ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(ScoreCore.GameType.guandan.rawValue)
            ]
        )
        let setup = ScoreboardRecordConfiguration.setup(from: record)
        XCTAssertEqual(setup.guandanTripleA, true)
        XCTAssertEqual(setup.guandanPassACondition, "double_up")
        XCTAssertEqual(setup.guandanTripleAFallbackRank, "K")
        XCTAssertEqual(setup.multiScoreCustomAdjustEnabled, true)
        XCTAssertEqual(setup.targetScore, 700)
    }

    func testWinnerResolutionUsesPositionsForDuplicateNamesAndSupportsMultipleWinners() {
        XCTAssertEqual(
            GameOverWinnerResolver.indices(
                explicit: nil,
                multiScores: [],
                leftScore: "11",
                rightScore: "7",
                participantNames: ["同名", "同名"],
                winnerName: "同名"
            ),
            [0]
        )
        XCTAssertEqual(
            GameOverWinnerResolver.indices(
                explicit: nil,
                multiScores: [12, 12, 5],
                leftScore: nil,
                rightScore: nil,
                participantNames: [],
                winnerName: ""
            ),
            [0, 1]
        )
        XCTAssertEqual(
            GameOverWinnerResolver.indices(
                explicit: nil,
                multiScores: [8, 8, 8],
                leftScore: nil,
                rightScore: nil,
                participantNames: [],
                winnerName: ""
            ),
            []
        )
    }

    func testCompletedMatchChineseResourcesUsePlayAnotherMatchWording() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let phone = try String(contentsOf: repositoryRoot.appendingPathComponent("jifen/Resources/zh-Hans.lproj/Localizable.strings"), encoding: .utf8)
        let watch = try String(contentsOf: repositoryRoot.appendingPathComponent("jifenWatch Watch App/Resources/zh-Hans.lproj/Localizable.strings"), encoding: .utf8)
        XCTAssertTrue(phone.contains(#""play_again" = "再来一场";"#))
        XCTAssertFalse(phone.contains(#""play_again" = "再来一局";"#))
        XCTAssertTrue(watch.contains(#""watch_play_again" = "再来一场";"#))
        XCTAssertFalse(watch.contains(#""watch_play_again" = "再来一局";"#))
    }

    func testAnyCodableEncodesNestedPlayerPayloadWithNegativeScores() throws {
        let payload = AnyCodable([
            ["name": "甲", "score": -3, "finalScore": -3] as [String: Any],
            ["name": "乙", "score": 12, "finalScore": 12] as [String: Any],
        ])

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        let players = try XCTUnwrap(decoded.value as? [Any])
        let first = try XCTUnwrap(players.first as? [String: Any])

        XCTAssertEqual(first["name"] as? String, "甲")
        XCTAssertEqual(first["score"] as? Int, -3)
    }

    func testLifecyclePersistenceNormalizesDraftAndFinishedMetadata() {
        let draftSource = makeRecord()
        let draft = ScoreboardLifecyclePersistence.normalizedRecord(
            draftSource,
            finished: false
        )
        XCTAssertEqual(draft.status.rawValue, ScoreboardRecordStatus.draft.rawValue)
        XCTAssertNil(draft.endTime)
        XCTAssertNil(draft.winner)

        var unfinishedSource = makeRecord()
        unfinishedSource.endTime = nil
        unfinishedSource.status = .draft
        let fallbackEnd = Date(timeIntervalSince1970: 1_700_000_120)
        let finished = ScoreboardLifecyclePersistence.normalizedRecord(
            unfinishedSource,
            finished: true,
            finishedAt: fallbackEnd
        )
        XCTAssertEqual(finished.status.rawValue, ScoreboardRecordStatus.finished.rawValue)
        XCTAssertEqual(finished.endTime, fallbackEnd)
        XCTAssertEqual(finished.winner, "left")
    }

    private func makeRecord(id: String = "record", schemaVersion: Int = 4, actions: [String] = []) -> ScoreboardRecord {
        var record = ScoreboardRecord(
            id: id,
            gameType: .pingpong,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_060),
            duration: 60,
            team1Name: "A",
            team2Name: "B",
            team1FinalScore: 11,
            team2FinalScore: 7,
            winner: "left",
            actions: actions,
            totalScoreChanges: actions.count
        )
        record.schemaVersion = schemaVersion
        return record
    }

    private func makeConfigurationRecord(
        gameType: jifen.GameType,
        configuration: [String: AnyCodable]?
    ) -> ScoreboardRecord {
        ScoreboardRecord(
            id: UUID().uuidString,
            gameType: gameType,
            startTime: Date(timeIntervalSince1970: 1),
            team1Name: "红队",
            team2Name: "蓝队",
            team1FinalScore: 0,
            team2FinalScore: 0,
            totalScoreChanges: 0,
            projectConfiguration: configuration
        )
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
