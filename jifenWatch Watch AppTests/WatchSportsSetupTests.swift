import XCTest
@testable import jifenWatch_Watch_App

final class WatchSportsSetupTests: XCTestCase {
    private var defaults: UserDefaults!
    private var preferences: WatchPreferences!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "WatchSportsSetupTests")
        defaults.removePersistentDomain(forName: "WatchSportsSetupTests")
        preferences = WatchPreferences(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "WatchSportsSetupTests")
        defaults = nil
        preferences = nil
        super.tearDown()
    }

    func testAndroid29Defaults() {
        let badminton = WatchSportsSetupDraft(sport: .badminton, preferences: preferences)
        XCTAssertEqual(badminton.maxSets, 3)
        XCTAssertEqual(badminton.pointsPerSet, 21)

        let pingpong = WatchSportsSetupDraft(sport: .pingpong, preferences: preferences)
        XCTAssertEqual(pingpong.maxSets, 5)
        XCTAssertEqual(pingpong.pointsPerSet, 11)

        let tennis = WatchSportsSetupDraft(sport: .tennis, preferences: preferences)
        XCTAssertEqual(tennis.maxSets, 3)
        XCTAssertEqual(tennis.tennisDeuceMode, "advantage")

        let pickleball = WatchSportsSetupDraft(sport: .pickleball, preferences: preferences)
        XCTAssertEqual(pickleball.maxSets, 3)
        XCTAssertEqual(pickleball.pickleballTargetScore, 11)
        XCTAssertFalse(pickleball.pickleballUseRallyScoring)

        let eightBall = WatchSportsSetupDraft(sport: .eightBall, preferences: preferences)
        XCTAssertEqual(eightBall.eightBallTargetRacks, 5)
        XCTAssertEqual(eightBall.eightBallHandicapBeneficiary, .none)

        let snooker = WatchSportsSetupDraft(sport: .snooker, preferences: preferences)
        XCTAssertEqual(snooker.maxSets, 1)
    }

    func testInvalidStoredValuesFallBackToDefaults() {
        defaults.set(2, forKey: "watchBadmintonSetupMaxSets")
        defaults.set(99, forKey: "watchPingpongSetupPointsPerSet")
        defaults.set("unexpected", forKey: "watchTennisSetupDeuceMode")
        defaults.set(13, forKey: "watchPickleballSetupTargetScore")

        XCTAssertEqual(
            WatchSportsSetupDraft(sport: .badminton, preferences: preferences).maxSets,
            3
        )
        XCTAssertEqual(
            WatchSportsSetupDraft(sport: .pingpong, preferences: preferences).pointsPerSet,
            11
        )
        XCTAssertEqual(
            WatchSportsSetupDraft(sport: .tennis, preferences: preferences).tennisDeuceMode,
            "advantage"
        )
        XCTAssertEqual(
            WatchSportsSetupDraft(sport: .pickleball, preferences: preferences).pickleballTargetScore,
            11
        )
    }

    func testRulesPersistButNamesDoNot() {
        var draft = WatchSportsSetupDraft(sport: .badminton, preferences: preferences)
        draft.maxSets = 5
        draft.pointsPerSet = 15
        draft.playerNames[0] = "Alice"
        draft.persistRules(to: preferences)

        let restored = WatchSportsSetupDraft(sport: .badminton, preferences: preferences)
        XCTAssertEqual(restored.maxSets, 5)
        XCTAssertEqual(restored.pointsPerSet, 15)
        XCTAssertTrue(restored.playerNames.allSatisfy(\.isEmpty))
    }

    func testExpandedPartialNamesAreRejected() {
        var draft = WatchSportsSetupDraft(sport: .badminton, preferences: preferences)
        draft.playerNames[0] = "Alice"
        XCTAssertFalse(draft.namesAreValid(whenExpanded: true))
        XCTAssertTrue(draft.namesAreValid(whenExpanded: false))

        draft.playerNames[1] = "Bob"
        XCTAssertTrue(draft.namesAreValid(whenExpanded: true))
    }

    func testNineBallCountIsClampedAndBlankNamesFallBack() {
        let low = WatchSportsSetupDraft(sport: .nineBall, playerCount: 1, preferences: preferences)
        let high = WatchSportsSetupDraft(sport: .nineBall, playerCount: 8, preferences: preferences)
        XCTAssertEqual(low.playerCount, 2)
        XCTAssertEqual(high.playerCount, 4)

        let config = WatchScoreboardLaunchConfig(draft: high)
        let names = WatchSetupPayloadMapper.resolvedPlayerNames(config)
        XCTAssertEqual(names.count, 4)
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
    }

    func testDoublesUIOrderMapsToCoreInterleavedSlots() {
        var draft = WatchSportsSetupDraft(sport: .badmintonDoubles, preferences: preferences)
        draft.playerNames = ["Red A", "Red B", "Blue A", "Blue B"]
        let state = WatchSetupPayloadMapper.rallyState(
            for: WatchScoreboardLaunchConfig(draft: draft)
        )
        XCTAssertEqual(
            state?.doubles?.playerNames,
            ["Red A", "Blue A", "Red B", "Blue B"]
        )
    }

    func testEightBallHandicapResetsAndCaps() {
        var draft = WatchSportsSetupDraft(sport: .eightBall, preferences: preferences)
        draft.eightBallTargetRacks = 3
        draft.eightBallHandicapBeneficiary = .team2
        draft.eightBallHandicapRacks = 5
        draft.normalizeEightBallHandicap()
        XCTAssertEqual(draft.eightBallHandicapRacks, 2)

        draft.eightBallTargetRacks = 1
        draft.normalizeEightBallHandicap()
        XCTAssertEqual(draft.eightBallHandicapBeneficiary, .none)
        XCTAssertEqual(draft.eightBallHandicapRacks, 0)
    }

    func testEightBallKeepsAndroidHandicapDraftWhenBeneficiaryIsNone() {
        var draft = WatchSportsSetupDraft(sport: .eightBall, preferences: preferences)
        draft.eightBallTargetRacks = 5
        draft.eightBallHandicapBeneficiary = .none
        draft.eightBallHandicapRacks = 3
        draft.normalizeEightBallHandicap()
        XCTAssertEqual(draft.eightBallHandicapRacks, 3)

        draft.eightBallHandicapBeneficiary = .team1
        draft.eightBallHandicapRacks = 0
        draft.normalizeEightBallHandicap()
        XCTAssertEqual(draft.eightBallHandicapRacks, 0)
    }

    func testSnookerEvenFramesNormalizeUpInCore() {
        var draft = WatchSportsSetupDraft(sport: .snooker, preferences: preferences)
        draft.maxSets = 4
        let state = WatchSetupPayloadMapper.snookerState(
            for: WatchScoreboardLaunchConfig(draft: draft)
        )
        XCTAssertEqual(state?.maxFrames, 5)
    }

    func testSetupRulesReachScoreCoreState() {
        var badminton = WatchSportsSetupDraft(sport: .badminton, preferences: preferences)
        badminton.maxSets = 5
        badminton.pointsPerSet = 15
        let badmintonState = WatchSetupPayloadMapper.rallyState(
            for: WatchScoreboardLaunchConfig(draft: badminton)
        )
        XCTAssertEqual(badmintonState?.rules.maxSets, 5)
        XCTAssertEqual(badmintonState?.rules.pointsToWinSet, 15)

        var pickleball = WatchSportsSetupDraft(sport: .pickleball, preferences: preferences)
        pickleball.pickleballTargetScore = 21
        pickleball.pickleballUseRallyScoring = true
        let pickleballState = WatchSetupPayloadMapper.rallyState(
            for: WatchScoreboardLaunchConfig(draft: pickleball)
        )
        XCTAssertEqual(pickleballState?.rules.pointsToWinSet, 21)
        XCTAssertEqual(pickleballState?.rules.useRallyScoring, true)

        var tennis = WatchSportsSetupDraft(sport: .tennis, preferences: preferences)
        tennis.tennisDeuceMode = "no_ad"
        let tennisState = WatchSetupPayloadMapper.tennisState(
            for: WatchScoreboardLaunchConfig(draft: tennis)
        )
        XCTAssertEqual(tennisState?.rules.usesNoAdScoring, true)

        var eightBall = WatchSportsSetupDraft(sport: .eightBall, preferences: preferences)
        eightBall.eightBallTargetRacks = 7
        eightBall.eightBallHandicapBeneficiary = .team2
        eightBall.eightBallHandicapRacks = 2
        let eightBallState = WatchSetupPayloadMapper.eightBallState(
            for: WatchScoreboardLaunchConfig(draft: eightBall)
        )
        XCTAssertEqual(eightBallState?.targetPoints, 7)
        XCTAssertEqual(eightBallState?.rightPoints, 2)
    }

    func testLegacyWatchRecordDecodesWithoutNewOptionalFields() throws {
        let json = """
        [{
          "id": "legacy",
          "gameType": "basketballTraining",
          "startTime": "2026-07-23T00:00:00Z",
          "endTime": "2026-07-23T00:01:00Z",
          "duration": 60,
          "team1Name": "出手",
          "team2Name": "命中",
          "team1FinalScore": 10,
          "team2FinalScore": 6,
          "team1SetScore": 0,
          "team2SetScore": 0,
          "actions": [],
          "totalScoreChanges": 16
        }]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let records = try decoder.decode(
            [WatchScoreboardRecord].self,
            from: Data(json.utf8)
        )
        XCTAssertNil(records[0].participants)
        XCTAssertNil(records[0].projectConfiguration)
        XCTAssertNil(records[0].basketballTrainingDetails)
        XCTAssertEqual(records[0].team1FinalScore, 10)
    }

    func testBasketballTrainingDetailsKeepSixAndroidStatsAndDecodeFirstVersion() throws {
        let shots = [
            WatchBasketballTrainingShot(points: 1, made: true),
            WatchBasketballTrainingShot(points: 1, made: false),
            WatchBasketballTrainingShot(points: 2, made: true),
            WatchBasketballTrainingShot(points: 3, made: false)
        ]
        let details = WatchBasketballTrainingDetails(mode: .free, shots: shots)
        XCTAssertEqual(details.count(points: 1, made: true), 1)
        XCTAssertEqual(details.count(points: 1, made: false), 1)
        XCTAssertEqual(details.count(points: 2, made: true), 1)
        XCTAssertEqual(details.count(points: 2, made: false), 0)
        XCTAssertEqual(details.count(points: 3, made: true), 0)
        XCTAssertEqual(details.count(points: 3, made: false), 1)

        let encoded = try JSONEncoder().encode(details)
        let roundTrip = try JSONDecoder().decode(
            WatchBasketballTrainingDetails.self,
            from: encoded
        )
        XCTAssertEqual(roundTrip.onePointMade, 1)
        XCTAssertEqual(roundTrip.threePointMiss, 1)

        let firstVersionJSON = """
        {
          "mode": "free",
          "shots": [
            {
              "id": "legacy-shot",
              "points": 2,
              "made": true,
              "timestamp": 0
            }
          ]
        }
        """
        let legacy = try JSONDecoder().decode(
            WatchBasketballTrainingDetails.self,
            from: Data(firstVersionJSON.utf8)
        )
        XCTAssertNil(legacy.twoPointMade)
        XCTAssertEqual(legacy.count(points: 2, made: true), 1)
    }
}
