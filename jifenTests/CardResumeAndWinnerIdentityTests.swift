import LinkCore
import PersistenceCore
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
        XCTAssertEqual(decoded.detailedActions.first?.operationCode, "guandan_upgrade")
        XCTAssertEqual(decoded.detailedActions.first?.scoreChange, 3)
    }

    func testGuandanDetailedSettlementRecordsActualCapDeltaAndPassAOutcome() throws {
        var cappedBefore = GuandanMatchState(
            phase: .playing,
            redTeam: .init(name: "红队", currentRank: "K"),
            blueTeam: .init(name: "蓝队", currentRank: "2")
        )
        cappedBefore.lastRoundWinner = .blue
        let cappedAfter = try XCTUnwrap(guandanRoundStateAfterTap(
            state: cappedBefore,
            winner: .red,
            step: 3,
            at: 1
        ))
        let cappedActions = guandanDetailedActions(
            for: .applyRoundSettlement(step: 3),
            previousState: cappedBefore,
            resultingState: cappedAfter,
            epochMilliseconds: 1,
            roundNumber: 1
        )
        XCTAssertEqual(cappedActions.count, 1)
        XCTAssertEqual(cappedActions[0].operationCode, "guandan_upgrade")
        XCTAssertEqual(cappedActions[0].team, .team1)
        XCTAssertEqual(cappedActions[0].scoreChange, 1)
        XCTAssertEqual(cappedActions[0].scores, [14, 2])

        var passBefore = GuandanMatchState(
            phase: .playing,
            redTeam: .init(name: "红队", currentRank: "A"),
            blueTeam: .init(name: "蓝队", currentRank: "8"),
            lastRoundWinner: .red,
            isInAStage: true,
            aStageTeam: .red,
            aStageMode: .tripleA,
            passACondition: .notLast
        )
        passBefore.redAFailCount = 1
        let passAfter = try XCTUnwrap(guandanRoundStateAfterTap(
            state: passBefore,
            winner: .red,
            step: 2,
            at: 2
        ))
        let passActions = guandanDetailedActions(
            for: .applyRoundSettlement(step: 2),
            previousState: passBefore,
            resultingState: passAfter,
            epochMilliseconds: 2,
            roundNumber: 2
        )
        XCTAssertEqual(passActions.map(\.operationCode), ["guandan_upgrade", "gd_pass_a_ok"])
        XCTAssertEqual(passActions.map(\.roundNumber), [2, 2])
        XCTAssertEqual(passActions[0].scoreChange, 2)
        XCTAssertEqual(passActions[1].team, .team1)
        XCTAssertEqual(passAfter.finalWinner, .red)
    }

    func testGuandanDetailedSettlementRecordsTripleAFailureAndFallbackResult() throws {
        let before = GuandanMatchState(
            phase: .playing,
            redTeam: .init(name: "红队", currentRank: "A"),
            blueTeam: .init(name: "蓝队", currentRank: "J"),
            lastRoundWinner: .red,
            isInAStage: true,
            aStageTeam: .red,
            aStageMode: .tripleA,
            passACondition: .notLast,
            tripleAFallbackRank: "J",
            redAFailCount: 2
        )
        let after = try XCTUnwrap(guandanRoundStateAfterTap(
            state: before,
            winner: .blue,
            step: 1,
            at: 3
        ))
        let actions = guandanDetailedActions(
            for: .applyRoundSettlement(step: 1),
            previousState: before,
            resultingState: after,
            epochMilliseconds: 3,
            roundNumber: 3
        )

        XCTAssertEqual(
            actions.map(\.operationCode),
            ["guandan_upgrade", "gd_pass_a_fail_triple", "gd_triple_a_fallback"]
        )
        XCTAssertEqual(actions.map(\.roundNumber), [3, 3, 3])
        XCTAssertEqual(actions[0].team, .team2)
        XCTAssertEqual(actions[0].scoreChange, 1)
        XCTAssertEqual(actions[1].team, .team1)
        XCTAssertEqual(actions[1].scoreChange, 3)
        XCTAssertEqual(actions[2].team, .team1)
        XCTAssertEqual(actions[2].operationPayload, "J")
        XCTAssertEqual(actions[2].scores, [11, 12])
        XCTAssertEqual(after.redTeam.currentRank, "J")
    }

    func testGuandanFirstRoundAndUndoToLegacyNotStartedRemainScoreable() throws {
        let untouched = GuandanMatchState.initial(redName: "红队", blueName: "蓝队")
        let presented = guandanPresentationStartedState(untouched, at: 1)
        XCTAssertEqual(presented.phase, .playing)
        XCTAssertEqual(presented.redTeam.currentRank, "2")

        let firstRound = try XCTUnwrap(guandanRoundStateAfterTap(
            state: untouched,
            winner: .red,
            step: 1,
            at: 2
        ))
        XCTAssertEqual(firstRound.phase, .playing)
        XCTAssertEqual(firstRound.redTeam.currentRank, "3")
        XCTAssertEqual(firstRound.lastRoundWinner, .red)

        // A legacy undo frame can still be notStarted. A second tap must start
        // and settle again instead of being accepted as a reducer no-op.
        let afterUndoAndRetap = try XCTUnwrap(guandanRoundStateAfterTap(
            state: untouched,
            winner: .blue,
            step: 2,
            at: 3
        ))
        XCTAssertEqual(afterUndoAndRetap.blueTeam.currentRank, "4")
        XCTAssertEqual(afterUndoAndRetap.lastRoundWinner, .blue)
    }

    /// 复现真机“掼蛋 +1 后弹保存失败”：按 GuandanScoreboardView.saveRecord 的
    /// 完整链路（编码快照 → 未结束走 ManualResumeSessionStore.save）走一遍。
    func testGuandanSaveAfterFirstPlusOneRoundPersists() throws {
        let recordID = ScoreboardRecordIdentity.next(prefix: GameType.guandan.canonicalScoreboardIdentifier)
        let state = GuandanMatchState.initial(redName: "红队", blueName: "蓝队")
        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
        let settled = try XCTUnwrap(guandanRoundStateAfterTap(
            state: state,
            winner: .red,
            step: 1,
            at: timestamp
        ))

        var actionLog: [String] = []
        var detailedActions: [DetailedScoreAction] = []
        let snapshotCode = ReducerScoreboardRecordPersistence.normalizedOperationCode("round_red_plus_1")
        let scores = [
            GuandanMatchState.rankDisplayScore(settled.redTeam.currentRank),
            GuandanMatchState.rankDisplayScore(settled.blueTeam.currentRank)
        ]
        actionLog.append("\(timestamp)|snapshot|\(snapshotCode)|\(scores.map(String.init).joined(separator: ","))|")
        detailedActions.append(DetailedScoreAction(
            type: .matchStarted,
            epochMilliseconds: timestamp,
            scores: [2, 2],
            operationCode: "guandan_match_started"
        ))
        detailedActions.append(contentsOf: guandanDetailedActions(
            for: .applyRoundSettlement(step: 1),
            previousState: state,
            resultingState: settled,
            epochMilliseconds: timestamp,
            roundNumber: 1
        ))

        let history = [state]
        let historyTimeline = [GuandanUndoTimelineCheckpoint(
            actionLogCount: 0,
            detailedActionsCount: 0,
            actionCount: 0
        )]

        let snapshotData = try JSONEncoder().encode(GuandanResumeState(
            state: settled,
            undoHistory: history,
            intentTimeline: actionLog,
            detailedActions: detailedActions,
            actionCount: 1,
            undoTimeline: historyTimeline
        ))

        let start = Date()
        let record = ScoreboardRecord(
            id: recordID,
            gameType: .guandan,
            startTime: start,
            endTime: Date(),
            duration: Date().timeIntervalSince(start),
            team1Name: settled.redTeam.name,
            team2Name: settled.blueTeam.name,
            team1FinalScore: GuandanMatchState.rankDisplayScore(settled.redTeam.currentRank),
            team2FinalScore: GuandanMatchState.rankDisplayScore(settled.blueTeam.currentRank),
            actions: actionLog,
            detailedActions: detailedActions,
            setResults: ScoreboardRecordActionAdapter.setResults(from: detailedActions),
            totalScoreChanges: 1,
            extraData: [
                "schemaVersion": AnyCodable(3),
                "guandanTripleAEnabled": AnyCodable(settled.aStageMode == .tripleA),
                "guandanPassACondition": AnyCodable(settled.passACondition.rawValue),
                "guandanTripleAFallbackRank": AnyCodable(settled.tripleAFallbackRank),
                "guandanPhase": AnyCodable(settled.projectedPhaseName),
                "guandanRedRank": AnyCodable(settled.redTeam.currentRank),
                "guandanBlueRank": AnyCodable(settled.blueTeam.currentRank),
                "guandanIsInAStage": AnyCodable(settled.isInAStage),
                "guandanRoundWinner": AnyCodable(settled.lastRoundWinner?.rawValue),
                "guandanAStageTeam": AnyCodable(settled.aStageTeam?.rawValue),
                "guandanFinalWinner": AnyCodable(settled.finalWinner?.rawValue),
                "guandanRedAFailCount": AnyCodable(settled.aFailCount(for: .red)),
                "guandanBlueAFailCount": AnyCodable(settled.aFailCount(for: .blue)),
                "showMatchTime": AnyCodable(false)
            ],
            projectConfiguration: [
                ScoreboardRecordConfiguration.Key.scoreCoreGameType: AnyCodable(ScoreCore.GameType.guandan.rawValue),
                "showMatchTime": AnyCodable(false)
            ],
            stateSnapshot: snapshotData,
            status: .finished
        )

        try ScoreboardLifecyclePersistence.save(record, finished: false)

        let restored = ManualResumeSessionStore.load(recordID: recordID)
        XCTAssertEqual(restored?.recordId, recordID)

        // 清理测试写入的 resume 会话，避免污染测试容器目录。
        if let sessionId = ManualResumeSessionStore.sessionID(for: recordID) {
            let repository = ResumeSessionRepository()
            Task {
                try? await repository.remove(sessionId: sessionId)
            }
        }
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
