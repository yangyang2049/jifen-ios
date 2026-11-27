import Foundation
import RecordCore
import ScoreCore
import Testing
@testable import LinkCore

/// M2 验收：MatchRecordProjector 全运动投影 + ScoreboardWinnerIdentity 编解码/token。
struct M2ProjectorTests {
    @Test func winnerIdentityJSONIsSchemaV5Identical() throws {
        let team = ScoreboardWinnerIdentity.team(.team0)
        let data = try JSONEncoder().encode(team)
        let decoded = try JSONDecoder().decode(ScoreboardWinnerIdentity.self, from: data)
        #expect(decoded == team)
        #expect(team.legacyToken == "team_0")
        #expect(ScoreboardWinnerIdentity.participant(index: 2).legacyToken == "player_2")
        #expect(ScoreboardWinnerIdentity.fromStableLegacyToken("TEAM1") == .team(.team1))
        #expect(ScoreboardWinnerIdentity.fromStableLegacyToken("player_3") == .participant(index: 3))
        #expect(ScoreboardWinnerIdentity.fromStableLegacyToken("garbage") == nil)
        #expect(ScoreboardWinnerIdentity.fromStableLegacyToken("player_-1") == nil)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["kind"] as? String == "team")
        #expect(obj?["teamID"] as? String == "team_0")
    }

    @Test func rallyProjectionCarriesScoresSetsWinnerAndConfig() {
        var state = RallyMatchEngine.initial(leftName: "L", rightName: "R", rules: .badminton())
        state.leftPoints = 21
        state.rightPoints = 9
        state.leftSets = 2
        let snapshot = LinkedScoreboardSnapshot.rally(state)
        let projection = MatchRecordProjector.project(
            snapshot: snapshot, gameType: .badminton, winnerSide: nil, participantNames: []
        )
        #expect(projection.team1FinalScore == 21)
        #expect(projection.team2FinalScore == 9)
        #expect(projection.team1SetScore == 2)
        #expect(projection.winnerIdentity == .team(.team0))
        #expect(projection.projectConfiguration["maxSets"] == String(state.rules.maxSets))
    }

    @Test func canonicalRecordAtomicallyBuildsFromSnapshot() throws {
        let state = RallyMatchEngine.initial(leftName: "L", rightName: "R", rules: .pingPong())
        let snapshot = LinkedScoreboardSnapshot.rally(state)
        let record = MatchRecordProjector.canonicalRecord(
            id: "rec-1", kind: .sport(.pingpong), source: .watchLocal,
            snapshot: snapshot, gameType: .pingpong, winnerSide: .left,
            startEpochMilliseconds: 1_000, endEpochMilliseconds: 61_000,
            durationSeconds: 60, participantNames: [], detailedActions: [], totalScoreChanges: 3
        )
        #expect(record.schemaVersion == CanonicalMatchRecord.currentSchemaVersion)
        #expect(record.kind == .sport(.pingpong))
        #expect(record.winnerIdentity == .team(.team0))
        #expect(record.team1SetScore != nil)
        let decoded = try JSONDecoder().decode(CanonicalMatchRecord.self, from: JSONEncoder().encode(record))
        #expect(decoded == record)
    }

    @Test func standaloneRallyWithIdenticalNamesRetainsRightSideWinner() {
        var state = RallyMatchEngine.initial(leftName: "Same", rightName: "Same", rules: .pingPong())
        state.rightSets = 2
        let projection = MatchRecordProjector.project(
            snapshot: .rally(state), gameType: .pingpong, winnerSide: nil,
            participantNames: [], source: .watchLocal
        )
        #expect(projection.winnerIdentity == .team(.team1))
    }

    @Test func standaloneNineBallKeepsLocalSetScoresAndPositionalWinner() {
        let state = NineBallChaseState(
            playerCount: 3, playerPoints: [1, 2, 5], playerCounts: [[0], [0], [0]],
            config: NineBallChaseConfig(), finished: true
        )
        let projection = MatchRecordProjector.project(
            snapshot: .nineBall(state), gameType: .nineBall, winnerSide: nil,
            participantNames: ["Left", "Same", "Same"], source: .watchLocal
        )
        #expect(projection.team1SetScore == 1)
        #expect(projection.team2SetScore == 2)
        #expect(projection.participants?.map(\.score) == [1, 2, 5])
        #expect(projection.winnerIdentity == .participant(index: 2))
    }

    @Test func trainingProjectionUsesCountsAndKeepsState() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let shots = (0..<5).map { index in
            ShotTrainingShot(points: index % 3 + 1, made: index % 2 == 0, timestamp: start.addingTimeInterval(Double(index) * 5))
        }
        let training = ShotTrainingState(mode: .fixed2, startTime: start, shots: shots, finished: true)
        let record = MatchRecordProjector.canonicalRecord(
            id: "rec-t", kind: .sport(.basketballTraining), source: .watchLocal,
            snapshot: .basketballTraining(training), gameType: .basketballTraining,
            winnerSide: nil,
            startEpochMilliseconds: 1_000, endEpochMilliseconds: 2_000,
            durationSeconds: 1, participantNames: [], detailedActions: [], totalScoreChanges: 5
        )
        #expect(record.basketballTraining == training)
        #expect(record.team1FinalScore == training.counts.missed)
        #expect(record.team2FinalScore == training.counts.made)
        #expect(record.winnerIdentity == nil)
        #expect(record.projectConfiguration["basketballTrainingScoringMode"] == "fixed_2")
    }

    @Test func shotTrainingOverflowAggregatesIntoEarlierCounts() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let shots = (0..<2_100).map { index in
            ShotTrainingShot(points: 1, made: index % 2 == 0, timestamp: start.addingTimeInterval(Double(index) * 3))
        }
        let state = ShotTrainingState(mode: .free, startTime: start, shots: shots)
        #expect(state.shots.count == ShotTrainingState.maxDetailedShots)
        #expect(state.counts.attempts == 2_100, "溢出投折进 earlierCounts，总量不丢")
        let madeTotal = shots.filter { $0.made }.count
        #expect(state.counts.made == madeTotal)
    }

    @Test func shotTrainingDetailedActionsProjectionMatchesLegacyBehavior() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let shots = [
            ShotTrainingShot(points: 2, made: true, timestamp: start),
            ShotTrainingShot(points: 3, made: false, timestamp: start.addingTimeInterval(10))
        ]
        let state = ShotTrainingState(mode: .free, startTime: start, shots: shots)
        let end = start.addingTimeInterval(30)
        let actions = state.detailedActions(endingAt: end)
        #expect(actions.count == 3)
        #expect(actions[0].operationCode == "training_2pt_made")
        #expect(actions[1].operationCode == "training_3pt_miss")
        #expect(actions[0].scores == [0, 1], "missed在前 made在后（running 计数口径）")
        #expect(actions[1].scores == [1, 1], "第2投未中：missed=1 made=1")
        #expect(actions[2].type == .matchFinished)
        #expect(actions[2].operationCode?.hasPrefix("training_rate_") == true)
    }
}

/// Codex R5 核对：v5 保真投影与投篮兜底。
struct M2V5FidelityTests {
    @Test func tiebreakOnlyTennisHasNilSetScores() {
        var state = TennisMatchState(leftName: "L", rightName: "R", rules: TennisRuleSet(autoChangeSides: false))
        state.rules.setScoringMode = .tiebreakOnly
        state.leftPoints = 5
        state.rightPoints = 3
        let projection = MatchRecordProjector.project(
            snapshot: .tennis(state), gameType: .tennis, winnerSide: nil, participantNames: []
        )
        #expect(projection.team1SetScore == nil, "抢七局模式 v5 局分为 nil")
        #expect(projection.team2SetScore == nil)
        #expect(projection.team1FinalScore == 5)
    }

    @Test func eightBallAndNineBallHaveNilSetScores() {
        let eight = EightBallState(leftPoints: 5, rightPoints: 2, leftCounts: [1], rightCounts: [0], targetPoints: 7, finished: false, handicapRacks: 0, handicapBeneficiary: nil)
        let eightProjection = MatchRecordProjector.project(
            snapshot: .eightBall(eight), gameType: .eightBall, winnerSide: .left, participantNames: []
        )
        #expect(eightProjection.team1SetScore == nil, "八球 v5 无局分")

        let nine = NineBallChaseState(playerCount: 3, playerPoints: [2, 1, 0], playerCounts: [[1], [0], []], config: NineBallChaseConfig(), finished: false)
        let nineProjection = MatchRecordProjector.project(
            snapshot: .nineBall(nine), gameType: .nineBall, winnerSide: nil, participantNames: ["甲", "乙", "丙"]
        )
        #expect(nineProjection.team1SetScore == nil, "九球 v5 无局分")
        #expect(nineProjection.participants?.count == 3)
        #expect(nineProjection.participants?.allSatisfy { !$0.name.isEmpty } == true)
    }

    @Test func trainingProjectionBackfillsActionsAndTotals() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        // 模拟 earlierCounts 折叠：构造一个 >2048 的历史
        let big = ShotTrainingState(
            mode: .free, startTime: start,
            shots: (0..<2_100).map { index in
                ShotTrainingShot(points: 2, made: index % 3 == 0, timestamp: start.addingTimeInterval(Double(index)))
            },
            finished: true
        )
        let record = MatchRecordProjector.canonicalRecord(
            id: "t1", kind: .sport(.basketballTraining), source: .watchLocal,
            snapshot: .basketballTraining(big), gameType: .basketballTraining,
            winnerSide: nil,
            startEpochMilliseconds: 1_000, endEpochMilliseconds: 2_000_000,
            durationSeconds: 100, participantNames: [],
            detailedActions: [], totalScoreChanges: 0
        )
        #expect(!record.detailedActions.isEmpty, "空明细必须由状态兜底生成动作")
        #expect(record.totalScoreChanges == big.counts.attempts, "总尝试数含 earlierCounts")
        #expect(record.basketballTraining == big)
    }

    @Test func packedShotTrainingStateOmitsLocalShotIdentity() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000.125)
        let shotID = UUID(uuidString: "12121212-3434-4545-8686-101010101010")
        let state = ShotTrainingState(
            mode: .free,
            startTime: timestamp,
            shots: [ShotTrainingShot(id: shotID, points: 2, made: true, timestamp: timestamp)],
            earlierCounts: ShotTrainingCounts(threeMiss: 1),
            finished: true
        )

        let encoded = try JSONEncoder().encode(state)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(object.keys) == Set(["mode", "startTime", "finished", "earlierCounts", "packedShots"]))
        let decoded = try JSONDecoder().decode(ShotTrainingState.self, from: encoded)
        #expect(decoded == state)
        #expect(decoded.counts == ShotTrainingCounts(twoMade: 1, threeMiss: 1))
        #expect(decoded.shots == [ShotTrainingShot(points: 2, made: true, timestamp: timestamp)])
    }
}
