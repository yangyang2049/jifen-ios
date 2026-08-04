import LinkCore
import RecordCore
import ScoreCore
import XCTest
@testable import jifen

@MainActor
final class CardResumeAndWinnerIdentityTests: XCTestCase {
    func testWinnerIdentityRoundTripsAndDualWritesCanonicalLegacyToken() throws {
        let record = makeRecord(
            gameType: .doudizhu,
            winnerIdentity: .participant(index: 2),
            players: [("甲", 1), ("乙", 2), ("丙", 9)]
        )

        XCTAssertEqual(record.schemaVersion, ScoreboardRecord.currentSchemaVersion)
        XCTAssertEqual(record.winner, "player_2")
        XCTAssertEqual(record.resolvedWinnerIdentity, .participant(index: 2))
        XCTAssertEqual(record.resolvedWinnerName, "丙")

        let decoded = try JSONDecoder().decode(
            ScoreboardRecord.self,
            from: JSONEncoder().encode(record)
        )
        XCTAssertEqual(decoded.winnerIdentity, .participant(index: 2))
        XCTAssertEqual(decoded.winner, "player_2")

        let teamRecord = makeRecord(winnerIdentity: .team(.team1))
        XCTAssertEqual(teamRecord.winner, "team_1")
        XCTAssertEqual(teamRecord.resolvedWinnerName, "乙队")
    }

    func testManagerPromotesStableLegacyWinnerToSchemaV5Identity() throws {
        let id = "winner-v5-\(UUID().uuidString)"
        defer { _ = ScoreboardRecordManager.shared.deleteRecord(id) }
        let record = makeRecord(id: id, winner: "left")

        try ScoreboardRecordManager.shared.saveScoreboardRecord(record)

        let saved = try XCTUnwrap(ScoreboardRecordManager.shared.getRecordById(id))
        XCTAssertEqual(saved.schemaVersion, ScoreboardRecord.currentSchemaVersion)
        XCTAssertEqual(saved.winner, "left")
        XCTAssertEqual(saved.winnerIdentity, .team(.team0))
    }

    func testAuthoritativeGuandanSnapshotBeatsConflictingLegacyToken() throws {
        let state = GuandanMatchState(
            phase: .finished,
            redTeam: .init(name: "红队", currentRank: "K"),
            blueTeam: .init(name: "蓝队", currentRank: "A"),
            lastRoundWinner: .blue,
            finalWinner: .blue
        )
        let wrapper = GuandanResumeState(
            state: state,
            undoHistory: [.initial(redName: "红队", blueName: "蓝队")],
            intentTimeline: ["1|snapshot|guandan_round_finished|12,14|"],
            actionCount: 1
        )
        let record = makeRecord(
            gameType: .guandan,
            winner: "team_0",
            stateSnapshot: try JSONEncoder().encode(wrapper)
        )

        XCTAssertNil(record.winnerIdentity)
        XCTAssertEqual(record.resolvedWinnerIdentity, .team(.team1))
        XCTAssertEqual(record.resolvedWinnerName, "乙队")

        var typedOverride = record
        typedOverride.winnerIdentity = .team(.team0)
        XCTAssertEqual(typedOverride.resolvedWinnerIdentity, .team(.team0))
    }

    func testAuthoritativeShengjiWrapperBeatsConflictingLegacyToken() throws {
        let state = ShengjiTierState(leftIndex: 4, rightIndex: 12, finished: true, dealer: .right)
        let wrapper = ReducerScoreboardRecordPersistence.StateSnapshot(
            state: state,
            undoStates: [ShengjiTierState(leftIndex: 4, rightIndex: 10, dealer: .right)],
            intentTimeline: ["1|snapshot|shengji_round_finished|4,12|"],
            detailedActions: [
                shengjiDetailedAction(
                    for: .resolveRound(winner: .right, delta: 2),
                    resultingState: state,
                    epochMilliseconds: 1,
                    roundNumber: 3
                )
            ]
        )
        let record = makeRecord(
            gameType: .shengji,
            winner: "team_0",
            stateSnapshot: try JSONEncoder().encode(wrapper)
        )

        XCTAssertEqual(record.resolvedWinnerIdentity, .team(.team1))
        XCTAssertEqual(record.resolvedWinnerName, "乙队")
    }

    func testDoudizhuStableTokenThenUniqueHighScoreThenUniqueNamePriority() {
        let players = [("甲", 0), ("乙", 1), ("丙", 8)]

        let stable = makeRecord(gameType: .doudizhu, winner: "player_0", players: players)
        XCTAssertEqual(stable.resolvedWinnerIdentity, .participant(index: 0))

        let conflictingName = makeRecord(gameType: .doudizhu, winner: "甲", players: players)
        XCTAssertEqual(conflictingName.resolvedWinnerIdentity, .participant(index: 2))

        let tiedScores = makeRecord(
            gameType: .doudizhu,
            winner: "丙",
            players: [("甲", 8), ("乙", 8), ("丙", 1)]
        )
        XCTAssertEqual(tiedScores.resolvedWinnerIdentity, .participant(index: 2))
    }

    func testAllMultiParticipantRecordsUseUniqueHighScoreAndLeaveTiesUnresolved() {
        let unique = makeRecord(
            gameType: .multiScoreboard,
            players: [("甲", 3), ("乙", 9), ("丙", 4)]
        )
        XCTAssertEqual(unique.resolvedWinnerIdentity, .participant(index: 1))
        XCTAssertEqual(ScoreboardRecordSummary(from: unique).resolvedWinnerIdentity, .participant(index: 1))

        let tie = makeRecord(
            gameType: .uno,
            players: [("甲", 9), ("乙", 9), ("丙", 4)]
        )
        XCTAssertNil(tie.resolvedWinnerIdentity)
        XCTAssertNil(ScoreboardRecordSummary(from: tie).resolvedWinnerIdentity)
    }

    func testDoudizhuResumeRoundTripKeepsUndoTimelineAndLegacyCompatibility() throws {
        let current = DoudizhuResumeState(
            names: ["甲", "乙", "丙"],
            scores: [2, -1, -1],
            finished: false,
            undoHistory: [[0, 0, 0], [1, 0, -1]],
            intentTimeline: ["1|settleRound|2,-1,-1", "2|undo"],
            actionCount: 2
        )
        let decoded = try JSONDecoder().decode(
            DoudizhuResumeState.self,
            from: JSONEncoder().encode(current)
        )
        XCTAssertEqual(decoded, current)

        let legacyData = try JSONSerialization.data(withJSONObject: [
            "names": ["甲", "乙", "丙"],
            "scores": [3, -1, -2],
            "finished": false
        ])
        let legacy = try JSONDecoder().decode(DoudizhuResumeState.self, from: legacyData)
        XCTAssertEqual(legacy.schemaVersion, 1)
        XCTAssertEqual(legacy.undoHistory, [])
        XCTAssertEqual(legacy.intentTimeline, [])
        XCTAssertEqual(legacy.actionCount, 0)
    }

    func testGuandanResumeRoundTripKeepsUndoTimelineAndDetailedRoundBoundary() throws {
        let initial = GuandanMatchState.initial(redName: "红队", blueName: "蓝队")
        var settled = initial
        settled.phase = .playing
        settled.redTeam.currentRank = "5"
        settled.lastRoundWinner = .red
        let boundary = guandanDetailedAction(
            for: .applyRoundSettlement(step: 3),
            previousState: initial,
            resultingState: settled,
            epochMilliseconds: 12,
            roundNumber: 2
        )
        let snapshot = GuandanResumeState(
            state: settled,
            undoHistory: [initial],
            intentTimeline: ["12|snapshot|guandan_round_finished|5,2|"],
            detailedActions: [boundary],
            actionCount: 1
        )

        let decoded = try JSONDecoder().decode(
            GuandanResumeState.self,
            from: JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.detailedActions.first?.type, .roundFinished)
        XCTAssertEqual(decoded.detailedActions.first?.roundNumber, 2)
        XCTAssertEqual(decoded.detailedActions.first?.operationCode, "guandan_round_finished")
    }

    func testSharedReducerSnapshotDecodesWrappedAndLegacyRawState() throws {
        let state = ShengjiTierState(leftIndex: 5, rightIndex: 3, dealer: .left)
        let undo = ShengjiTierState(leftIndex: 3, rightIndex: 3, dealer: .left)
        let detail = shengjiDetailedAction(
            for: .resolveRound(winner: .left, delta: 2),
            resultingState: state,
            epochMilliseconds: 10,
            roundNumber: 4
        )
        let wrappedData = try JSONEncoder().encode(
            ReducerScoreboardRecordPersistence.StateSnapshot(
                state: state,
                undoStates: [undo],
                intentTimeline: ["10|snapshot|shengji_round_finished|5,3|"],
                detailedActions: [detail]
            )
        )

        let wrapped = try XCTUnwrap(
            ReducerScoreboardRecordPersistence.decodeSnapshot(wrappedData, as: ShengjiTierState.self)
        )
        XCTAssertTrue(wrapped.isWrapped)
        XCTAssertEqual(wrapped.state, state)
        XCTAssertEqual(wrapped.undoStates, [undo])
        XCTAssertEqual(wrapped.detailedActions, [detail])
        XCTAssertEqual(wrapped.detailedActions.first?.roundNumber, 4)

        let raw = try XCTUnwrap(ReducerScoreboardRecordPersistence.decodeSnapshot(
            JSONEncoder().encode(state),
            as: ShengjiTierState.self
        ))
        XCTAssertFalse(raw.isWrapped)
        XCTAssertEqual(raw.state, state)
        XCTAssertEqual(raw.undoStates, [])
    }

    func testDetailedRoundActionsUseReliableNumbersAndLowercaseOperationCodes() {
        let shengji = shengjiDetailedAction(
            for: .resolveRound(winner: .right, delta: 2),
            resultingState: ShengjiTierState(leftIndex: 2, rightIndex: 6, dealer: .right),
            epochMilliseconds: 9,
            roundNumber: 7
        )
        XCTAssertEqual(shengji.type, .roundFinished)
        XCTAssertEqual(shengji.roundNumber, 7)
        XCTAssertEqual(shengji.winner, .team2)
        XCTAssertEqual(shengji.operationCode, "shengji_round_finished")

        XCTAssertEqual(
            ReducerScoreboardRecordPersistence.normalizedOperationCode("ApplyRoundSettlement(step: 2)"),
            "applyroundsettlement_step_2"
        )
    }

    func testSummaryDecodesWithoutTypedWinnerAndUsesResolver() throws {
        let summary = ScoreboardRecordSummary(from: makeRecord(winner: "right"))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(summary)) as? [String: Any]
        )
        object.removeValue(forKey: "winnerIdentity")
        let decoded = try JSONDecoder().decode(
            ScoreboardRecordSummary.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertNil(decoded.winnerIdentity)
        XCTAssertEqual(decoded.resolvedWinnerIdentity, .team(.team1))
        XCTAssertEqual(decoded.resolvedWinnerName, "乙队")
    }

    func testDraftNormalizationClearsBothWinnerRepresentations() {
        let draft = ScoreboardLifecyclePersistence.normalizedRecord(
            makeRecord(winnerIdentity: .team(.team0)),
            finished: false
        )
        XCTAssertNil(draft.winner)
        XCTAssertNil(draft.winnerIdentity)
    }

    func testWatchDoudizhuIngestKeepsThirdParticipantWinnerIdentity() throws {
        let payload = WatchRecordTransferPayload(
            id: "doudizhu-third",
            gameType: "doudizhu",
            startTimeEpochMilliseconds: 1_000,
            endTimeEpochMilliseconds: 2_000,
            durationSeconds: 1,
            team1Name: "甲",
            team2Name: "乙",
            team1FinalScore: -2,
            team2FinalScore: -1,
            team1SetScore: 0,
            team2SetScore: 0,
            winner: "丙",
            actions: [],
            totalScoreChanges: 1,
            participants: [
                .init(name: "甲", score: -2),
                .init(name: "乙", score: -1),
                .init(name: "丙", score: 3)
            ]
        )

        let record = try WatchStandaloneRecordIngestor.makeRecord(payload)
        XCTAssertEqual(record.winnerIdentity, .participant(index: 2))
        XCTAssertEqual(record.winner, "player_2")
        XCTAssertEqual(record.resolvedWinnerName, "丙")
    }

    private func makeRecord(
        id: String = UUID().uuidString,
        gameType: jifen.GameType = .pingpong,
        winner: String? = nil,
        winnerIdentity: ScoreboardWinnerIdentity? = nil,
        stateSnapshot: Data? = nil,
        players: [(String, Int)] = []
    ) -> ScoreboardRecord {
        ScoreboardRecord(
            id: id,
            gameType: gameType,
            startTime: Date(timeIntervalSince1970: 1),
            endTime: Date(timeIntervalSince1970: 2),
            duration: 1,
            team1Name: "甲队",
            team2Name: "乙队",
            team1FinalScore: players.first?.1 ?? 3,
            team2FinalScore: players.dropFirst().first?.1 ?? 2,
            winner: winner,
            winnerIdentity: winnerIdentity,
            totalScoreChanges: 1,
            extraData: players.isEmpty ? nil : [
                "players": AnyCodable(players.map { ["name": $0.0, "finalScore": $0.1] as [String: Any] })
            ],
            stateSnapshot: stateSnapshot,
            status: .finished
        )
    }
}
