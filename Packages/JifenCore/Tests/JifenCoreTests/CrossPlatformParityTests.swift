import Foundation
import Testing
import LinkCore
import PersistenceCore
import ScoreCore
import SessionCore

@Test func lineScoreReducerClampsFootballAndAllowsNegativeSimpleScore() {
    let reducer = LineScoreReducer()
    var football = LineScoreState(leftName: "主队", rightName: "客队")
    football = reducer.reduce(state: football, intent: .adjust(side: .left, delta: -1), at: 1).state
    #expect(football.leftScore == 0)
    football = reducer.reduce(state: football, intent: .pointWon(.left), at: 2).state
    #expect(football.leftScore == 1)

    var simple = LineScoreState(leftName: "红方", rightName: "蓝方", rules: .freeCounter)
    simple = reducer.reduce(state: simple, intent: .adjust(side: .right, delta: -3), at: 3).state
    #expect(simple.rightScore == -3)
}

@Test func boxingReducerCompletesConfiguredRoundsLikeAndroid() {
    let reducer = BoxingMatchReducer()
    var state = BoxingMatchState(leftName: "红方", rightName: "蓝方", maxRounds: 2)
    state = reducer.reduce(state: state, intent: .submitRound(left: 10, right: 9), at: 1).state
    #expect(state.currentRound == 2)
    #expect(state.leftRoundsWon == 1)
    #expect(!state.finished)
    state = reducer.reduce(state: state, intent: .submitRound(left: 9, right: 10), at: 2).state
    #expect(state.leftTotal == 19)
    #expect(state.rightTotal == 19)
    #expect(state.rightRoundsWon == 1)
    #expect(state.finished)
}

@Test func tennisReducerHandlesAdvantageNoAdAndTieBreak() {
    let reducer = TennisMatchReducer()
    let rules = TennisRuleSet(autoChangeSides: false)
    var advantage = TennisMatchState(leftName: "A", rightName: "B", rules: rules)
    advantage.leftPoints = 3
    advantage.rightPoints = 3
    advantage = reducer.reduce(state: advantage, intent: .pointWon(.left), at: 1).state
    #expect(advantage.scoreDisplay(for: .left) == "AD")
    advantage = reducer.reduce(state: advantage, intent: .pointWon(.right), at: 2).state
    #expect(advantage.scoreDisplay(for: .left) == "40")
    #expect(advantage.scoreDisplay(for: .right) == "40")

    var noAd = TennisMatchState(
        leftName: "A",
        rightName: "B",
        rules: .init(usesNoAdScoring: true, autoChangeSides: false)
    )
    noAd.leftPoints = 3
    noAd.rightPoints = 3
    noAd = reducer.reduce(state: noAd, intent: .pointWon(.right), at: 3).state
    #expect(noAd.rightGames == 1)
    #expect(noAd.leftPoints == 0)
    #expect(noAd.rightPoints == 0)

    var tieBreak = TennisMatchState(leftName: "A", rightName: "B", rules: rules)
    tieBreak.leftGames = 6
    tieBreak.rightGames = 6
    tieBreak.isTieBreak = true
    tieBreak.leftPoints = 6
    tieBreak.rightPoints = 5
    tieBreak = reducer.reduce(state: tieBreak, intent: .pointWon(.left), at: 4).state
    #expect(tieBreak.leftSets == 1)
    #expect(tieBreak.leftGames == 0)
    #expect(tieBreak.rightGames == 0)
}

@Test func tennisSideExchangeKeepsStableTeamIdentity() {
    let reducer = TennisMatchReducer()
    var state = TennisMatchState(
        leftName: "A",
        rightName: "B",
        openingServer: .left,
        doublesPlayerNames: ["A1", "B1", "A2", "B2"]
    )
    state.leftPoints = 2
    state.rightPoints = 1
    state.leftGames = 3
    state.rightGames = 2
    state.leftSets = 1
    state.servingSide = .right
    state.firstServerInSet = .left

    let exchanged = reducer.reduce(state: state, intent: .exchangeSides, at: 1).state

    #expect(exchanged.sidesSwapped)
    #expect(exchanged.leftName == "A")
    #expect(exchanged.rightName == "B")
    #expect(exchanged.doublesPlayerNames == ["A1", "B1", "A2", "B2"])
    #expect(exchanged.leftPoints == 2)
    #expect(exchanged.rightPoints == 1)
    #expect(exchanged.leftGames == 3)
    #expect(exchanged.rightGames == 2)
    #expect(exchanged.leftSets == 1)
    #expect(exchanged.servingSide == .right)
    #expect(exchanged.openingServerSide == .left)
    #expect(exchanged.firstServerInSet == .left)

    let screenLayout = TeamScreenLayout(sidesSwapped: exchanged.sidesSwapped)
    #expect(screenLayout.engineSide(onScreen: .left) == .right)
    #expect(screenLayout.engineSide(onScreen: .right) == .left)
}

@Test func tennisAutomaticSideExchangeMovesScreenPlacementOnly() {
    let reducer = TennisMatchReducer()
    var state = TennisMatchState(leftName: "A", rightName: "B", openingServer: .left)

    for timestamp in 1 ... 4 {
        state = reducer.reduce(
            state: state,
            intent: .pointWon(.left),
            at: Int64(timestamp)
        ).state
    }

    #expect(state.leftGames == 1)
    #expect(state.rightGames == 0)
    #expect(state.leftName == "A")
    #expect(state.rightName == "B")
    #expect(state.sidesSwapped)
    #expect(state.servingSide == .right)
    #expect(state.firstServerInSet == .left)

    let screenLayout = TeamScreenLayout(sidesSwapped: state.sidesSwapped)
    #expect(screenLayout.engineSide(onScreen: .left) == .right)
}

@Test func tennisResetAfterSideExchangePreservesConfiguredPlayers() {
    let reducer = TennisMatchReducer()
    var state = TennisMatchState(
        leftName: "A",
        rightName: "B",
        openingServer: .right,
        doublesPlayerNames: ["A1", "B1", "A2", "B2"]
    )
    state = reducer.reduce(state: state, intent: .exchangeSides, at: 1).state
    state.leftGames = 2
    state.rightPoints = 3

    let reset = reducer.reduce(state: state, intent: .reset, at: 2).state

    #expect(reset.leftName == "A")
    #expect(reset.rightName == "B")
    #expect(reset.doublesPlayerNames == ["A1", "B1", "A2", "B2"])
    #expect(reset.openingServerSide == .right)
    #expect(reset.servingSide == .right)
    #expect(reset.firstServerInSet == .right)
    #expect(reset.leftPoints == 0)
    #expect(reset.rightPoints == 0)
    #expect(reset.leftGames == 0)
    #expect(reset.rightGames == 0)
    #expect(!reset.sidesSwapped)
}

@Test func tennisDoublesPlayerEditRebuildsJoinedNamesAndSurvivesReset() throws {
    let reducer = TennisMatchReducer()
    let state = TennisMatchState(
        leftName: "A1/A2",
        rightName: "B1/B2",
        doublesPlayerNames: ["A1", "B1", "A2", "B2"]
    )

    let edited = reducer.reduce(
        state: state,
        intent: .setDoublesPlayerName(slot: 2, name: " A3 "),
        at: 1
    )
    #expect(edited.accepted)
    #expect(edited.state.doublesPlayerNames == ["A1", "B1", "A3", "B2"])
    #expect(edited.state.leftName == "A1 / A3")
    #expect(edited.state.rightName == "B1 / B2")

    let decoded = try JSONDecoder().decode(
        TennisMatchState.self,
        from: JSONEncoder().encode(edited.state)
    )
    let reset = reducer.reduce(state: decoded, intent: .reset, at: 2).state
    #expect(reset.doublesPlayerNames == ["A1", "B1", "A3", "B2"])
    #expect(reset.leftName == "A1 / A3")
    #expect(reset.rightName == "B1 / B2")
}

@Test func tennisDoublesDerivedReceiverTracksPointParityAndLogicalSides() {
    let reducer = TennisMatchReducer()
    var state = TennisMatchState(
        leftName: "A",
        rightName: "B",
        openingServer: .left,
        doublesPlayerNames: ["A1", "B1", "A2", "B2"]
    )
    #expect(TennisDoublesServing.currentServerSlot(in: state) == 0)
    #expect(TennisDoublesServing.currentReceiverSlot(in: state) == 1)

    state.leftPoints = 1
    #expect(TennisDoublesServing.currentServerSlot(in: state) == 0)
    #expect(TennisDoublesServing.currentReceiverSlot(in: state) == 3)

    state = reducer.reduce(state: state, intent: .exchangeSides, at: 1).state
    #expect(state.sidesSwapped)
    #expect(TennisDoublesServing.currentReceiverSlot(in: state) == 3)

    state.isTieBreak = true
    state.leftPoints = 1
    state.rightPoints = 0
    #expect(TennisDoublesServing.currentServerSlot(in: state) == 1)
    #expect(TennisDoublesServing.currentReceiverSlot(in: state) == 2)
}

@Test func tennisDoublesServerRotationContinuesAcrossSetBoundaries() {
    let reducer = TennisMatchReducer()

    func completedSet(leftGames: Int, rightGames: Int, tieBreak: Bool = false) -> TennisMatchState {
        var state = TennisMatchState(
            leftName: "A",
            rightName: "B",
            rules: .init(maxSets: 3),
            openingServer: .left,
            doublesPlayerNames: ["A1", "B1", "A2", "B2"]
        )
        state.leftGames = leftGames
        state.rightGames = rightGames
        state.isTieBreak = tieBreak
        state.leftPoints = tieBreak ? 6 : 3
        state.rightPoints = tieBreak ? 5 : 0
        return reducer.reduce(state: state, intent: .pointWon(.left), at: 1).state
    }

    let sixFour = completedSet(leftGames: 5, rightGames: 4)
    #expect(sixFour.doublesFirstServerSlotInSet == 2)
    #expect(TennisDoublesServing.currentServerSlot(in: sixFour) == 2)

    let sevenFive = completedSet(leftGames: 6, rightGames: 5)
    #expect(sevenFive.doublesFirstServerSlotInSet == 0)
    #expect(TennisDoublesServing.currentServerSlot(in: sevenFive) == 0)

    let sevenSix = completedSet(leftGames: 6, rightGames: 6, tieBreak: true)
    #expect(sevenSix.doublesFirstServerSlotInSet == 1)
    #expect(TennisDoublesServing.currentServerSlot(in: sevenSix) == 1)
}

@Test func tennisTieBreakAdminAdjustmentRecomputesTeamAndPlayerServer() {
    let reducer = TennisMatchReducer()
    var state = TennisMatchState(
        leftName: "A",
        rightName: "B",
        openingServer: .left,
        doublesPlayerNames: ["A1", "B1", "A2", "B2"]
    )
    state.leftGames = 6
    state.rightGames = 6
    state.isTieBreak = true
    state.leftPoints = 2
    state.rightPoints = 1
    #expect(TennisDoublesServing.currentServerSlot(in: state) == 2)

    let adjusted = reducer.reduce(
        state: state,
        intent: .adjustPoints(side: .left, delta: -1),
        at: 1
    ).state
    #expect(TennisDoublesServing.currentServerSlot(in: adjusted) == 1)
    #expect(adjusted.servingSide == .right)
}

@Test func tennisGameAdjustmentNormalizesTieBreakPointsAndServingSlot() {
    let reducer = TennisMatchReducer()
    var state = TennisMatchState(
        leftName: "A",
        rightName: "B",
        openingServer: .left,
        doublesPlayerNames: ["A1", "B1", "A2", "B2"]
    )
    state.leftGames = 6
    state.rightGames = 6
    state.isTieBreak = true
    state.leftPoints = 4
    state.rightPoints = 3

    let adjusted = reducer.reduce(
        state: state,
        intent: .adjustGames(side: .right, delta: -1),
        at: 1
    ).state
    #expect(!adjusted.isTieBreak)
    #expect(adjusted.leftPoints == 0)
    #expect(adjusted.rightPoints == 0)
    #expect(TennisDoublesServing.currentServerSlot(in: adjusted) == 3)
    #expect(adjusted.servingSide == .right)
}

@Test func legacyTennisDoublesSnapshotInfersAPlayerForFirstServingTeam() throws {
    let state = TennisMatchState(
        leftName: "A",
        rightName: "B",
        openingServer: .right,
        doublesPlayerNames: ["A1", "B1", "A2", "B2"]
    )
    let encoded = try JSONEncoder().encode(state)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "doublesFirstServerSlotInSet")
    let legacy = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(TennisMatchState.self, from: legacy)

    #expect(decoded.doublesFirstServerSlotInSet == nil)
    #expect(TennisDoublesServing.firstServerSlot(in: decoded) == 1)
}

@Test func tennisFourGameAndTiebreakOnlyFormatsMatchMobileRules() throws {
    let reducer = TennisMatchReducer()
    var shortSet = TennisMatchState(
        leftName: "A",
        rightName: "B",
        rules: .init(maxSets: 1, gamesPerSet: 4, autoChangeSides: false)
    )
    shortSet.leftGames = 4
    shortSet.rightGames = 4
    shortSet.isTieBreak = true
    shortSet.leftPoints = 6
    shortSet.rightPoints = 5
    shortSet = reducer.reduce(state: shortSet, intent: .pointWon(.left), at: 1).state
    #expect(shortSet.leftGames == 5)
    #expect(shortSet.rightGames == 4)
    #expect(shortSet.finished)

    let matchRules = TennisRuleSet(
        maxSets: 5,
        tieBreakPoints: 10,
        setScoringMode: .tiebreakOnly,
        matchCompletionMode: .playAll,
        autoChangeSides: false
    )
    #expect(matchRules.maxSets == 1)
    #expect(matchRules.matchCompletionMode == .bestOf)
    var matchTieBreak = TennisMatchState(leftName: "A", rightName: "B", rules: matchRules)
    #expect(matchTieBreak.isTieBreak)
    matchTieBreak.leftPoints = 9
    matchTieBreak.rightPoints = 9
    matchTieBreak = reducer.reduce(state: matchTieBreak, intent: .pointWon(.left), at: 2).state
    #expect(!matchTieBreak.finished)
    let finalTieBreak = reducer.reduce(state: matchTieBreak, intent: .pointWon(.left), at: 3)
    matchTieBreak = finalTieBreak.state
    #expect(matchTieBreak.leftPoints == 11)
    #expect(matchTieBreak.rightPoints == 9)
    #expect(matchTieBreak.leftSets == 0)
    #expect(matchTieBreak.rightSets == 0)
    #expect(matchTieBreak.leftGames == 0)
    #expect(matchTieBreak.rightGames == 0)
    #expect(matchTieBreak.finished)
    #expect(!finalTieBreak.events.contains { event in
        if case .gameCompleted = event { return true }
        if case .setCompleted = event { return true }
        return false
    })
    #expect(finalTieBreak.events.contains(.matchFinished(winner: .left)))

    let edit = reducer.reduce(state: TennisMatchState(leftName: "A", rightName: "B", rules: matchRules), intent: .adjustGames(side: .left, delta: 1), at: 4)
    #expect(!edit.accepted)

    let legacy = Data(#"{"maxSets":3,"tieBreakPoints":7,"matchCompletionMode":"bestOf","usesNoAdScoring":false,"autoChangeSides":true}"#.utf8)
    let restored = try JSONDecoder().decode(TennisRuleSet.self, from: legacy)
    #expect(restored.gamesPerSet == 6)
    #expect(restored.setScoringMode == .regular)
}

@Test func kernelRegistryRoutesEveryGameTypeAndFactoriesRejectWrongFamilies() async {
    for gameType in GameType.allCases {
        #expect(ScoreboardKernelRegistry.descriptor(for: gameType).gameType == gameType)
    }
    #expect(ScoreboardKernelRegistry.descriptor(for: .tennis).kind == .tennis)
    #expect(ScoreboardKernelRegistry.descriptor(for: .football).kind == .line)
    #expect(ScoreboardKernelRegistry.descriptor(for: .boxing).ruleFamily == .s2)
    #expect(ScoreboardSessionFactory.line(gameType: .tennis, leftName: "A", rightName: "B") == nil)

    let core = ScoreboardSessionFactory.line(gameType: .simpleScore, leftName: "A", rightName: "B")
    let result = await core?.dispatch(actorId: "test", intent: .adjust(side: .left, delta: -2), at: 1)
    guard case .accepted(let session, _) = result else {
        Issue.record("Expected line session factory to create a working session")
        return
    }
    #expect(session.state.leftScore == -2)
    #expect(session.ruleFamily == .s1)
}

@Test func eightBallRaceToMatchesAndroidFixture() {
    let reducer = EightBallReducer()
    var state = EightBallState.initial(targetPoints: 3)
    state = reducer.reduce(state: state, intent: .addRack(.left), at: 1).state
    state = reducer.reduce(state: state, intent: .addRack(.left), at: 2).state
    state = reducer.reduce(state: state, intent: .addRack(.right), at: 3).state
    #expect(state.leftPoints == 2)
    #expect(state.rightPoints == 1)
    #expect(!state.finished)

    let winningResult = reducer.reduce(state: state, intent: .addRack(.left), at: 4)
    #expect(winningResult.accepted)
    #expect(winningResult.state.leftPoints == 3)
    #expect(winningResult.state.finished)

    let postFinishResult = reducer.reduce(
        state: winningResult.state,
        intent: .addRack(.right),
        at: 5
    )
    #expect(!postFinishResult.accepted)
    #expect(postFinishResult.state.rightPoints == 1)
}

@Test func nineBallChaseFoulMatchesTwoAndFourPlayerRules() {
    let reducer = NineBallChaseReducer()
    var two = NineBallChaseState.initial(playerCount: 2)
    two = reducer.reduce(state: two, intent: .chaseEvent(player: 0, kind: .foul), at: 1).state
    #expect(two.playerPoints[0] == 0)
    #expect(two.playerPoints[1] == 1)

    var four = NineBallChaseState.initial(playerCount: 4)
    four = reducer.reduce(state: four, intent: .chaseEvent(player: 2, kind: .foul), at: 1).state
    #expect(four.playerPoints[2] == -1)
    #expect(four.playerCounts[2][5] == 1)
}

@Test func nineBallTwoPlayerExchangeOnlyChangesScreenPlacement() {
    let reducer = NineBallChaseReducer()
    var state = NineBallChaseState.initial(
        playerCount: 2,
        playerNames: ["甲", "乙"]
    )
    state.playerPoints[0] = 12
    state.playerPoints[1] = 7
    state.playerCounts[0][0] = 3

    let exchanged = reducer.reduce(state: state, intent: .exchangeSides, at: 1)
    #expect(exchanged.accepted)
    #expect(exchanged.state.sidesSwapped)
    #expect(exchanged.state.playerNames[0] == "甲")
    #expect(exchanged.state.playerPoints[0] == 12)
    #expect(exchanged.state.playerCounts[0][0] == 3)

    let fourPlayer = NineBallChaseState.initial(playerCount: 4)
    #expect(!reducer.reduce(state: fourPlayer, intent: .exchangeSides, at: 2).accepted)
}

@Test func legacyNineBallSnapshotDefaultsToUnswappedPlacement() throws {
    let state = NineBallChaseState.initial(playerCount: 2)
    let encoded = try JSONEncoder().encode(state)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "sidesSwapped")
    let legacy = try JSONSerialization.data(withJSONObject: object)
    #expect(try JSONDecoder().decode(NineBallChaseState.self, from: legacy).sidesSwapped == false)
}

@Test func shengjiTierReducerMatchesAndroidFixture() {
    let result = ShengjiTierReducer().reduce(
        state: ShengjiTierState(),
        intent: .addLevels(side: .left, delta: 3),
        at: 1
    )
    #expect(result.state.leftIndex == 3)
    #expect(result.state.rightIndex == 0)
    #expect(!result.state.finished)
}

@Test func shengjiResolveRoundTransfersDealerAndUpgrades() {
    let reducer = ShengjiTierReducer()
    var state = ShengjiTierState()
    state = reducer.reduce(state: state, intent: .claimDealer(.left), at: 1).state
    state = reducer.reduce(state: state, intent: .resolveRound(winner: .right, delta: 2), at: 2).state
    #expect(state.rightIndex == 2)
    #expect(state.dealer == .right)
    state = reducer.reduce(state: state, intent: .resolveRound(winner: .left, delta: 0), at: 3).state
    #expect(state.leftIndex == 0)
    #expect(state.dealer == .left)
}

@Test func shengjiAdministrativeTransitionsStayInsideReducer() {
    let reducer = ShengjiTierReducer()
    let seed = ShengjiTierState(leftIndex: 2, rightIndex: 4, maxTierIndex: 12, dealer: .right)
    let corrected = reducer.reduce(
        state: seed,
        intent: .adminCorrect(left: 12, right: 3),
        at: 1
    )
    #expect(corrected.accepted)
    #expect(corrected.state.leftIndex == 12)
    #expect(corrected.state.finished)

    let reset = reducer.reduce(state: corrected.state, intent: .reset, at: 2)
    #expect(reset.accepted)
    #expect(reset.state == ShengjiTierState(maxTierIndex: 12))

    let finished = reducer.reduce(state: reset.state, intent: .finish, at: 3)
    #expect(finished.accepted)
    #expect(finished.state.finished)
}

@Test func guandanUpgradeAndPassAFinishMatch() {
    let reducer = GuandanSessionReducer()
    var state = GuandanMatchState.initial(redName: "红", blueName: "蓝")
    state = reducer.reduce(state: state, intent: .startMatch, at: 1).state
    #expect(!guandanRankOrder.contains("王"))

    // Climb red to A via repeated step-3 upgrades from 2.
    for stepTick in 0..<4 {
        state = reducer.reduce(state: state, intent: .beginRoundResult(winner: .red), at: Int64(10 + stepTick * 2)).state
        state = reducer.reduce(state: state, intent: .applyRoundSettlement(step: 3), at: Int64(11 + stepTick * 2)).state
    }
    #expect(state.redTeam.currentRank == "A")
    #expect(state.isInAStage)
    #expect(state.aStageTeam == .red)

    // Pass A with step 2 (not_last).
    state = reducer.reduce(state: state, intent: .beginRoundResult(winner: .red), at: 100).state
    state = reducer.reduce(state: state, intent: .applyRoundSettlement(step: 2), at: 101).state
    #expect(state.phase == .finished)
    #expect(state.finalWinner == .red)
}

@Test func guandanAdministrativeTransitionsStayInsideReducer() {
    let reducer = GuandanSessionReducer()
    var state = GuandanMatchState.initial(redName: "红", blueName: "蓝")
    state = reducer.reduce(state: state, intent: .startMatch, at: 1).state
    state = reducer.reduce(
        state: state,
        intent: .adminCorrect(redName: "红队", blueName: "蓝队", redRank: "A", blueRank: "K"),
        at: 2
    ).state
    #expect(state.redTeam.name == "红队")
    #expect(state.redTeam.currentRank == "A")
    #expect(state.phase == .playing)

    let finished = reducer.reduce(state: state, intent: .finish, at: 3)
    #expect(finished.accepted)
    #expect(finished.state.phase == .finished)
    #expect(finished.state.finalWinner == .red)

    let reset = reducer.reduce(state: finished.state, intent: .reset, at: 4)
    #expect(reset.accepted)
    #expect(reset.state.phase == .playing)
    #expect(reset.state.redTeam.name == "红队")
    #expect(reset.state.redTeam.currentRank == "2")
}

@Test func guandanTripleAFailsFallbackToConfiguredRank() {
    let reducer = GuandanSessionReducer()
    var state = GuandanMatchState(
        phase: .playing,
        redTeam: GuandanTeamState(name: "红", currentRank: "A"),
        blueTeam: GuandanTeamState(name: "蓝", currentRank: "2"),
        lastRoundWinner: .red,
        isInAStage: true,
        aStageTeam: .red,
        aStageMode: .tripleA,
        passACondition: .notLast,
        tripleAFallbackRank: "10"
    )

    // Fail 1: A-side loses banker.
    state = reducer.reduce(state: state, intent: .beginRoundResult(winner: .blue), at: 20).state
    state = reducer.reduce(state: state, intent: .applyRoundSettlement(step: 1), at: 21).state
    #expect(state.redTeam.currentRank == "A")
    #expect(state.redAFailCount == 1)
    #expect(state.aStageTeam == nil)

    // Reclaim A stage without resetting fail count.
    state = reducer.reduce(state: state, intent: .beginRoundResult(winner: .red), at: 22).state
    state = reducer.reduce(state: state, intent: .applyRoundSettlement(step: 1), at: 23).state
    #expect(state.aStageTeam == .red)
    #expect(state.redAFailCount == 1)

    // Fail 2: A-side wins but step 1 is not enough to pass A.
    state = reducer.reduce(state: state, intent: .beginRoundResult(winner: .red), at: 24).state
    state = reducer.reduce(state: state, intent: .applyRoundSettlement(step: 1), at: 25).state
    #expect(state.redAFailCount == 2)
    #expect(state.aStageTeam == .red)

    // Fail 3: lose again → fallback.
    state = reducer.reduce(state: state, intent: .beginRoundResult(winner: .blue), at: 26).state
    state = reducer.reduce(state: state, intent: .applyRoundSettlement(step: 1), at: 27).state
    #expect(state.redTeam.currentRank == "10")
    #expect(state.redAFailCount == 0)
    #expect(state.phase == .playing)
}

@Test func unoRoundScoreMatchesAndroidFormula() {
    #expect(UnoRoundScore.total(number: 15, action20: 1, wild40: 1, wild50: 1) == 15 + 20 + 40 + 50)
    #expect(UnoRoundScore.total(number: 0, action20: 0, wild40: 0, wild50: 0) == 0)
}

@Test func doudizhuSettlementMatchesOneAndTwoWinnerSplits() {
    #expect(DoudizhuSettlement.deltas(winners: [true, false, false], baseScore: 5, multiplierPower: 1) == [20, -10, -10])
    #expect(DoudizhuSettlement.deltas(winners: [false, true, true], baseScore: 5, multiplierPower: 0) == [-10, 5, 5])
    #expect(DoudizhuSettlement.deltas(winners: [true, true, true], baseScore: 1, multiplierPower: 0) == nil)
}

@Test func archeryNextShooterPrefersTrailingSetPoints() {
    #expect(ArcheryShooterRules.nextStartingIsLeft(leftSetPoints: 2, rightSetPoints: 4, openingIsLeft: true) == true)
    #expect(ArcheryShooterRules.nextStartingIsLeft(leftSetPoints: 4, rightSetPoints: 2, openingIsLeft: true) == false)
    #expect(ArcheryShooterRules.nextStartingIsLeft(leftSetPoints: 3, rightSetPoints: 3, openingIsLeft: false) == false)
}

@Test func archeryReducerAwardsSetPointsLikeSharedRules() {
    let reducer = ArcheryMatchReducer()
    var state = ArcheryMatchState(leftName: "红", rightName: "蓝")
    for _ in 0..<3 {
        state = reducer.reduce(state: state, intent: .recordArrow(side: nil, value: 10), at: 0).state
        state = reducer.reduce(state: state, intent: .recordArrow(side: nil, value: 8), at: 0).state
    }
    #expect(state.setCompletionPending)
    #expect(state.pendingLeftSetPoints == 2)
    #expect(state.pendingRightSetPoints == 0)
    state = reducer.reduce(state: state, intent: .completeSet(closestToCenterWinner: nil), at: 0).state
    #expect(state.leftSetPoints == 2)
    #expect(state.rightSetPoints == 0)
    #expect(state.currentSet == 2)
}

@Test func guandanTripleADisplayRankShowsAttemptNumber() {
    var state = GuandanMatchState.initial(
        redName: "红",
        blueName: "蓝",
        aStageMode: .tripleA,
        passACondition: .notLast,
        tripleAFallbackRank: "10"
    )
    state.phase = .playing
    state.redTeam.currentRank = "A"
    state.blueTeam.currentRank = "A"
    state.redAFailCount = 1
    state.blueAFailCount = 0
    state.lastRoundWinner = .red
    #expect(state.displayRank(for: .red) == "A2")
    #expect(state.displayRank(for: .blue) == "A1")
}

@Test func snookerPotAndFoulMatchAndroidSemantics() {
    let reducer = SnookerReducer()
    var state = SnookerState.initial()
    state = reducer.reduce(state: state, intent: .potBall(points: 5), at: 1).state
    state = reducer.reduce(state: state, intent: .potBall(points: 3), at: 2).state
    #expect(state.leftScore == 8)
    #expect(state.leftBreak == 8)
    #expect(state.striker == .left)

    state = reducer.reduce(state: state, intent: .foul(pointsToOpponent: 2, switchTurn: true), at: 3).state
    #expect(state.rightScore == 4)
    #expect(state.striker == .right)
    #expect(state.leftBreak == 0)
}

@Test func snookerClearanceRequiresExplicitFrameSettlement() {
    let reducer = SnookerReducer()
    var state = SnookerState.initial(maxFrames: 3)
    state.redBallsRemaining = 0
    state.nextBallStage = .black
    state.leftScore = 50
    state.rightScore = 40

    state = reducer.reduce(state: state, intent: .potBall(points: 7), at: 1).state
    #expect(state.nextBallStage == .complete)
    #expect(state.leftFrames == 0)
    #expect(state.currentFrame == 1)
    #expect(!state.finished)

    state = reducer.reduce(state: state, intent: .settleFrame(winner: .left), at: 2).state
    #expect(state.leftFrames == 1)
    #expect(state.currentFrame == 2)
    #expect(state.leftScore == 0)
    #expect(state.striker == .right)
}

@Test func legacySnookerPendingFrameSnapshotNormalizesOnRestore() throws {
    var state = SnookerState.initial(maxFrames: 3)
    state.frameCompletePending = true
    state.pendingFrameWinner = .left
    let restored = try JSONDecoder().decode(SnookerState.self, from: JSONEncoder().encode(state))
    #expect(!restored.frameCompletePending)
    #expect(restored.pendingFrameWinner == nil)
}

@Test func specializedBilliardsAdministrativeTransitionsStayInsideReducers() {
    let eightReducer = EightBallReducer()
    let eightInitial = EightBallState.initial(targetPoints: 5, handicapRacks: 2, handicapBeneficiary: .right)
    let eightFinished = eightReducer.reduce(
        state: eightInitial,
        intent: .finishMatch,
        at: 1
    )
    #expect(eightFinished.accepted)
    #expect(eightFinished.state.finished)
    #expect(eightFinished.events == [.matchFinished])

    let chaseReducer = NineBallChaseReducer()
    let chaseInitial = NineBallChaseState.initial(playerCount: 3, playerNames: ["A", "B", "C"])
    let chaseEdited = chaseReducer.reduce(
        state: chaseInitial,
        intent: .adminCorrect(
            playerNames: ["甲", "乙", "丙"],
            playerPoints: [-10_500, 22, 10_500]
        ),
        at: 2
    )
    #expect(chaseEdited.accepted)
    #expect(Array(chaseEdited.state.playerNames.prefix(3)) == ["甲", "乙", "丙"])
    #expect(Array(chaseEdited.state.playerPoints.prefix(3)) == [-9_999, 22, 9_999])
    let chaseFinished = chaseReducer.reduce(
        state: chaseEdited.state,
        intent: .finishMatch,
        at: 3
    )
    #expect(chaseFinished.accepted)
    #expect(chaseFinished.state.finished)
    #expect(chaseFinished.events == [.matchFinished])

    let snookerReducer = SnookerReducer()
    var snooker = SnookerState.initial(striker: .right, maxFrames: 5)
    snooker = snookerReducer.reduce(state: snooker, intent: .potBall(points: 7), at: 4).state
    let reset = snookerReducer.reduce(state: snooker, intent: .reset, at: 5)
    #expect(reset.accepted)
    #expect(reset.state == .initial(striker: .right, maxFrames: 5))
    #expect(reset.events == [.reset])
}

@Test func threeSpecializedBilliardsSessionsUseCoreUndoAndRebaseBoundaries() async {
    let eightSeed = ScoreSession<EightBallState, EightBallEvent>(
        gameType: .eightBall,
        ruleFamily: .s2,
        reducerType: "eight_ball/v1",
        state: .initial(targetPoints: 5)
    )
    let eightCore = ScoreSessionCore(
        seedSession: eightSeed,
        reducer: EightBallReducer(),
        shouldFinish: { _, state in state.finished }
    )
    _ = await eightCore.dispatch(actorId: "phone", intent: .addRack(.left), at: 1)
    _ = await eightCore.updateParticipants([
        .init(id: "team_0", name: "新红方", role: "team"),
        .init(id: "team_1", name: "新蓝方", role: "team")
    ])
    #expect(await eightCore.snapshot().state.leftPoints == 1)
    #expect(await eightCore.undo(actorId: "phone"))
    #expect(await eightCore.snapshot().state.leftPoints == 0)
    #expect(await eightCore.snapshot().participants.map(\.name) == ["新红方", "新蓝方"])

    let chaseSeed = ScoreSession<NineBallChaseState, NineBallChaseEvent>(
        gameType: .nineBall,
        ruleFamily: .s2,
        reducerType: "nine_ball/v1",
        state: .initial(playerCount: 3, playerNames: ["A", "B", "C"])
    )
    let chaseCore = ScoreSessionCore(
        seedSession: chaseSeed,
        reducer: NineBallChaseReducer(),
        shouldFinish: { _, state in state.finished }
    )
    _ = await chaseCore.dispatch(actorId: "phone", intent: .chaseEvent(player: 2, kind: .foul), at: 2)
    #expect(await chaseCore.snapshot().state.playerPoints[2] == -1)
    var authoritativeChase = await chaseCore.snapshot().state
    authoritativeChase.playerPoints[2] = 88
    _ = await chaseCore.rebase(to: authoritativeChase, status: .live)
    #expect(!(await chaseCore.undo(actorId: "phone")))
    #expect(await chaseCore.snapshot().state.playerPoints[2] == 88)

    let snookerSeed = ScoreSession<SnookerState, SnookerEvent>(
        gameType: .snooker,
        ruleFamily: .s2,
        reducerType: "snooker/v1",
        state: .initial(striker: .left, maxFrames: 3)
    )
    let snookerCore = ScoreSessionCore(
        seedSession: snookerSeed,
        reducer: SnookerReducer(),
        shouldFinish: { _, state in state.finished }
    )
    _ = await snookerCore.dispatch(actorId: "phone", intent: .potBall(points: 1), at: 3)
    #expect(await snookerCore.snapshot().state.leftScore == 1)
    #expect(await snookerCore.undo(actorId: "phone"))
    #expect(await snookerCore.snapshot().state.redBallsRemaining == 15)
}

@Test func specializedBilliardsResumeBundleRepositoryPreservesTypedUndoTimeline() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let repository = SessionArchiveRepository(rootURL: root)
    let seed = ScoreSession<EightBallState, EightBallEvent>(
        gameType: .eightBall,
        ruleFamily: .s2,
        reducerType: "eight_ball/v1",
        state: .initial(targetPoints: 7)
    )
    let core = ScoreSessionCore(seedSession: seed, reducer: EightBallReducer())
    _ = await core.dispatch(actorId: "phone", intent: .addRack(.right), at: 10)
    let bundle = await core.resumeBundle()

    try await repository.saveResumeBundle(bundle, updatedAtEpochMilliseconds: 20)
    let restored: ScoreSessionResumeBundle<EightBallState, EightBallEvent, EightBallIntent>? =
        try await repository.loadResumeBundle(sessionId: seed.sessionId, as: ScoreSessionResumeBundle<EightBallState, EightBallEvent, EightBallIntent>.self)

    #expect(restored?.currentSession.state.rightPoints == 1)
    #expect(restored?.undoFrames.count == 1)
    #expect(restored?.timeline.count == 1)
}

@Test func pingPongCompletesASetAndResetsPointsLikeHarmony() {
    let reducer = RallyMatchReducer()
    var state = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: .pingPong())

    for point in 0..<11 {
        state = reducer.reduce(state: state, intent: .pointWon(.left), at: Int64(point)).state
    }

    #expect(state.leftSets == 1)
    #expect(state.rightSets == 0)
    #expect(state.leftPoints == 0)
    #expect(state.rightPoints == 0)
    #expect(!state.finished)
}

@Test func bestOfOneRallyFinishesAfterFirstSetLikeHarmony() {
    let reducer = RallyMatchReducer()
    let rules = RallyRuleSet(
        maxSets: 1,
        pointsToWinSet: 3,
        pointCap: 99,
        winByTwo: false
    )
    var state = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: rules)

    for point in 0..<3 {
        state = reducer.reduce(state: state, intent: .pointWon(.left), at: Int64(point)).state
    }

    #expect(state.leftSets == 1)
    #expect(state.finished)
}

@Test func matchCompletionModesFollowAndroidAndHarmonyRules() {
    #expect(MatchCompletionMode.bestOf.isMatchFinished(maxSets: 5, leftSets: 3, rightSets: 0))
    #expect(!MatchCompletionMode.playAll.isMatchFinished(maxSets: 5, leftSets: 3, rightSets: 0))
    #expect(!MatchCompletionMode.playAll.isMatchFinished(maxSets: 5, leftSets: 3, rightSets: 1))
    #expect(MatchCompletionMode.playAll.isMatchFinished(maxSets: 5, leftSets: 3, rightSets: 2))

    #expect(!MatchCompletionMode.bestOf.allowsSetScore(maxSets: 4, leftSets: 2, rightSets: 2))
    #expect(MatchCompletionMode.playAll.allowsSetScore(maxSets: 4, leftSets: 2, rightSets: 2))
}

@Test func playAllRallyCanFinishInADraw() {
    let reducer = RallyMatchReducer()
    let rules = RallyRuleSet(
        maxSets: 4,
        pointsToWinSet: 1,
        winByTwo: false,
        matchCompletionMode: .playAll
    )
    var state = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: rules)
    var lastEvents: [RallyMatchEvent] = []

    for (index, side) in [MatchSide.left, .left, .right, .right].enumerated() {
        let result = reducer.reduce(state: state, intent: .pointWon(side), at: Int64(index))
        state = result.state
        lastEvents = result.events
    }

    #expect(state.leftSets == 2)
    #expect(state.rightSets == 2)
    #expect(state.finished)
    #expect(lastEvents.contains(.matchFinished(winner: nil)))
}

@Test func rallyRulesDecodeOldAndUnknownCompletionModesAsClassic() throws {
    let rules = RallyRuleSet.pingPong(maxSets: 5, matchCompletionMode: .playAll)
    let encoded = try JSONEncoder().encode(rules)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

    object.removeValue(forKey: "matchCompletionMode")
    let oldData = try JSONSerialization.data(withJSONObject: object)
    #expect(try JSONDecoder().decode(RallyRuleSet.self, from: oldData).matchCompletionMode == .bestOf)

    object["matchCompletionMode"] = "future_mode"
    let unknownData = try JSONSerialization.data(withJSONObject: object)
    #expect(try JSONDecoder().decode(RallyRuleSet.self, from: unknownData).matchCompletionMode == .bestOf)
}

@Test func linkedRallySnapshotPreservesPlayAllMode() throws {
    let state = RallyMatchEngine.initial(
        leftName: "A",
        rightName: "B",
        rules: .badminton(maxSets: 4, matchCompletionMode: .playAll)
    )
    let snapshot = LinkedScoreboardSnapshot.rally(state)
    let restored = try JSONDecoder().decode(
        LinkedScoreboardSnapshot.self,
        from: JSONEncoder().encode(snapshot)
    )

    #expect(restored.rallyState?.rules.matchCompletionMode == .playAll)
    #expect(restored.rallyState?.rules.maxSets == 4)
}

@Test func badmintonDeuceRequiresTwoPointLeadBeforeCapLikeHarmony() {
    let reducer = RallyMatchReducer()
    var state = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: .badminton())
    state.leftPoints = 20
    state.rightPoints = 20

    state = reducer.reduce(state: state, intent: .pointWon(.left), at: 1).state
    #expect(state.leftSets == 0)
    #expect(state.leftPoints == 21)

    state = reducer.reduce(state: state, intent: .pointWon(.left), at: 2).state
    #expect(state.leftSets == 1)
    #expect(state.leftPoints == 0)
}

@Test func decidingSetSideSwitchReminderFiresOnceLikeHarmony() {
    let reducer = RallyMatchReducer()
    var state = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: .pingPong(maxSets: 5))
    state.leftSets = 2
    state.rightSets = 2
    state.leftPoints = 4
    state.rightPoints = 3

    let crossing = reducer.reduce(state: state, intent: .pointWon(.left), at: 1)
    #expect(crossing.events.contains(.sidesExchangeReminder))
    #expect(crossing.state.leftPoints == 5)

    let following = reducer.reduce(state: crossing.state, intent: .pointWon(.right), at: 2)
    #expect(!following.events.contains(.sidesExchangeReminder))
}

@Test func decidingSetSideSwitchPointHelperMatchesAndroidFormulas() {
    #expect(RallyRuleSet.decidingSetSideSwitchPoint(for: .pingpong, pointsPerSet: 11) == 5)
    #expect(RallyRuleSet.decidingSetSideSwitchPoint(for: .pingpongDoubles, pointsPerSet: 11) == 5)
    #expect(RallyRuleSet.decidingSetSideSwitchPoint(for: .pingpong, pointsPerSet: 21) == 10)
    #expect(RallyRuleSet.decidingSetSideSwitchPoint(for: .badminton, pointsPerSet: 21) == 11)
    #expect(RallyRuleSet.decidingSetSideSwitchPoint(for: .badmintonDoubles, pointsPerSet: 15) == 8)
    #expect(RallyRuleSet.decidingSetSideSwitchPoint(for: .volleyball, pointsPerSet: 25) == nil)
}

@Test func badmintonPointCapHelperMatchesIOSFormats() {
    #expect(RallyRuleSet.badmintonPointCap(for: 11) == 15)
    #expect(RallyRuleSet.badmintonPointCap(for: 15) == 21)
    #expect(RallyRuleSet.badmintonPointCap(for: 21) == 30)
    #expect(RallyRuleSet.badmintonPointCap(for: 25) == nil)
    #expect(RallyRuleSet.badmintonPointCap(for: 999) == nil)
}

@Test func badmintonSupportedFormatsEndAtTheirCaps() {
    let reducer = RallyMatchReducer()
    for (target, cap) in [(11, 15), (15, 21), (21, 30)] {
        var rules = RallyRuleSet.badminton()
        rules.pointsToWinSet = target
        rules.pointCap = RallyRuleSet.badmintonPointCap(for: target)
        var state = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: rules)
        state.leftPoints = cap - 1
        state.rightPoints = cap - 1

        let result = reducer.reduce(state: state, intent: .pointWon(.left), at: 1)
        #expect(result.state.leftSets == 1)
        #expect(result.events.contains(.setCompleted(
            winner: .left,
            setNumber: 1,
            leftPoints: cap,
            rightPoints: cap - 1,
            leftSets: 1,
            rightSets: 0
        )))
    }
}

@Test func badmintonFifteenPointSetCapsAtTwentyOne() {
    let reducer = RallyMatchReducer()
    var rules = RallyRuleSet.badminton()
    rules.pointsToWinSet = 15
    rules.pointCap = RallyRuleSet.badmintonPointCap(for: 15)
    var state = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: rules)
    state.leftPoints = 20
    state.rightPoints = 19

    let result = reducer.reduce(state: state, intent: .pointWon(.left), at: 1)
    #expect(result.state.leftSets == 1)
    #expect(result.state.leftPoints == 0)
    #expect(result.events.contains(.setCompleted(
        winner: .left,
        setNumber: 1,
        leftPoints: 21,
        rightPoints: 19,
        leftSets: 1,
        rightSets: 0
    )))
}

@Test func pingPongDecidingSetAutoExchangesAtFiveNotSix() {
    var rules = RallyRuleSet.pingPong(maxSets: 5)
    rules.autoChangeSides = true
    let reducer = RallyMatchReducer()
    var state = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: rules)
    state.leftSets = 2
    state.rightSets = 2
    state.leftPoints = 4
    state.rightPoints = 3
    let beforeSwapped = state.sidesSwapped

    let atFive = reducer.reduce(state: state, intent: .pointWon(.left), at: 1)
    #expect(atFive.events.contains(.sidesExchanged))
    #expect(atFive.state.sidesSwapped != beforeSwapped)
    #expect(atFive.state.leftPoints == 5)

    // Crossing 6 must not exchange again.
    let atSix = reducer.reduce(state: atFive.state, intent: .pointWon(.left), at: 2)
    #expect(!atSix.events.contains(.sidesExchanged))
    #expect(atSix.state.sidesSwapped == atFive.state.sidesSwapped)
}

@Test func pingPongDoublesRotatesServerAndReceiverAfterTwoPoints() {
    let initial = createPingPongDoublesRotation(openingServerSlotIndex: 0, openingReceiverSlotIndex: 1)
    let afterFirst = advancePingPongDoublesRotation(
        current: initial,
        previousTeam0Score: 0,
        previousTeam1Score: 0,
        nextTeam0Score: 1,
        nextTeam1Score: 0,
        pointsToWin: 11,
        isDecidingSet: false
    )
    let afterSecond = advancePingPongDoublesRotation(
        current: afterFirst.state,
        previousTeam0Score: 1,
        previousTeam1Score: 0,
        nextTeam0Score: 2,
        nextTeam1Score: 0,
        pointsToWin: 11,
        isDecidingSet: false
    )

    #expect(afterFirst.state.serverSlotIndex == 0)
    #expect(afterFirst.state.receiverSlotIndex == 1)
    #expect(afterSecond.state.serverSlotIndex == 1)
    #expect(afterSecond.state.receiverSlotIndex == 2)
}

@Test func pingPongDoublesDeciderChangesReceivingOrderAtFive() {
    let initial = createPingPongDoublesRotation(openingServerSlotIndex: 0, openingReceiverSlotIndex: 1)
    let result = advancePingPongDoublesRotation(
        current: initial,
        previousTeam0Score: 4,
        previousTeam1Score: 3,
        nextTeam0Score: 5,
        nextTeam1Score: 3,
        pointsToWin: 11,
        isDecidingSet: true
    )

    #expect(result.shouldExchangeEnds)
    #expect(result.state.decidingReceiverOrderChanged)
    #expect(result.state.serverSlotIndex == 3)
    #expect(result.state.receiverSlotIndex == 2)
}

@Test func badmintonDoublesServingTeamKeepsServerAndSwapsCourts() {
    let initial = createBadmintonDoublesRotation(servingTeam0: true)
    let result = advanceBadmintonDoublesRotation(
        current: initial,
        scoringTeam0: true,
        nextTeam0Score: 1,
        nextTeam1Score: 0
    )

    #expect(result.serverSlotIndex == initial.serverSlotIndex)
    #expect(result.team0CourtOrderSwapped)
    #expect(!result.team1CourtOrderSwapped)
}

@Test func badmintonDoublesReceivingTeamTakesServiceWithoutCourtSwap() {
    let initial = createBadmintonDoublesRotation(servingTeam0: true)
    let result = advanceBadmintonDoublesRotation(
        current: initial,
        scoringTeam0: false,
        nextTeam0Score: 0,
        nextTeam1Score: 1
    )

    #expect(result.serverSlotIndex == 3)
    #expect(!result.team0CourtOrderSwapped)
    #expect(!result.team1CourtOrderSwapped)
}

@Test func tennisDoublesReceiverAlternatesBetweenPartners() {
    #expect(resolveTennisDoublesReceiverSlot(
        serverSlotIndex: 0,
        pointIndexInGame: 0,
        team0FirstReceiverSlotIndex: 0,
        team1FirstReceiverSlotIndex: 1
    ) == 1)
    #expect(resolveTennisDoublesReceiverSlot(
        serverSlotIndex: 0,
        pointIndexInGame: 1,
        team0FirstReceiverSlotIndex: 0,
        team1FirstReceiverSlotIndex: 1
    ) == 3)
    #expect(resolveTennisDoublesReceiverSlot(
        serverSlotIndex: 1,
        pointIndexInGame: 0,
        team0FirstReceiverSlotIndex: 0,
        team1FirstReceiverSlotIndex: 1
    ) == 0)
    #expect(resolveTennisDoublesReceiverSlot(
        serverSlotIndex: 1,
        pointIndexInGame: 1,
        team0FirstReceiverSlotIndex: 0,
        team1FirstReceiverSlotIndex: 1
    ) == 2)
}

@Test func rallyReducerAdvancesPingPongDoublesRotationWithScore() {
    let reducer = RallyMatchReducer()
    var state = RallyMatchEngine.initial(
        leftName: "Red",
        rightName: "Blue",
        rules: .pingPong(),
        doubles: .pingPong(playerNames: ["Red A", "Blue A", "Red B", "Blue B"])
    )

    state = reducer.reduce(state: state, intent: .pointWon(.left), at: 1).state
    #expect(state.doubles?.serverSlotIndex == 0)
    #expect(state.doubles?.receiverSlotIndex == 1)

    state = reducer.reduce(state: state, intent: .pointWon(.right), at: 2).state
    #expect(state.doubles?.serverSlotIndex == 1)
    #expect(state.doubles?.receiverSlotIndex == 2)
    #expect(state.servingSide == .right)
}

@Test func pingPongDoublesStartsNextSetWithAlternatingTeamServer() {
    let reducer = RallyMatchReducer()
    var state = RallyMatchEngine.initial(
        leftName: "Red",
        rightName: "Blue",
        rules: .pingPong(),
        doubles: .pingPong(playerNames: ["Red A", "Blue A", "Red B", "Blue B"])
    )

    for point in 0..<11 {
        state = reducer.reduce(state: state, intent: .pointWon(.left), at: Int64(point)).state
    }

    #expect(state.currentSet == 2)
    #expect(state.servingSide == .right)
    #expect(state.doubles?.serverSlotIndex == 1)
    #expect(state.doubles?.receiverSlotIndex == 0)
}

@Test func rallyReducerAdvancesBadmintonDoublesCourtsAndService() {
    let reducer = RallyMatchReducer()
    var state = RallyMatchEngine.initial(
        leftName: "Red",
        rightName: "Blue",
        rules: .badminton(),
        doubles: .badminton(playerNames: ["Red A", "Blue A", "Red B", "Blue B"])
    )

    state = reducer.reduce(state: state, intent: .pointWon(.left), at: 1).state
    #expect(state.doubles?.serverSlotIndex == 2)
    #expect(state.doubles?.receiverSlotIndex == 3)
    #expect(state.doubles?.serverName == "Red B")

    state = reducer.reduce(state: state, intent: .pointWon(.right), at: 2).state
    #expect(state.doubles?.serverSlotIndex == 3)
    #expect(state.doubles?.receiverSlotIndex == 2)
    #expect(state.servingSide == .right)
}

@Test func rallyUndoRestoresDoublesRotationAtomically() async {
    let initial = RallyMatchEngine.initial(
        leftName: "Red",
        rightName: "Blue",
        rules: .pingPong(),
        doubles: .pingPong(playerNames: ["Red A", "Blue A", "Red B", "Blue B"])
    )
    let seed = ScoreSession<RallyMatchState, RallyMatchEvent>(
        gameType: .pingpongDoubles,
        ruleFamily: .s1,
        reducerType: "rally/v1",
        state: initial
    )
    let session = ScoreSessionCore(seedSession: seed, reducer: RallyMatchReducer())

    _ = await session.dispatch(actorId: "phone", intent: .pointWon(.left), at: 1)
    _ = await session.dispatch(actorId: "phone", intent: .pointWon(.right), at: 2)
    #expect(await session.snapshot().state.doubles?.serverSlotIndex == 1)

    #expect(await session.undo(actorId: "phone"))
    #expect(await session.snapshot().state.doubles?.serverSlotIndex == 0)
    #expect(await session.snapshot().state.doubles?.receiverSlotIndex == 1)
}

@Test func badmintonAdministrativeDecrementReplaysSelectedTeamsLatestPoint() {
    let reducer = RallyMatchReducer()
    var state = RallyMatchEngine.initial(
        leftName: "Red",
        rightName: "Blue",
        rules: .badminton(),
        doubles: .badminton(playerNames: ["R1", "B1", "R2", "B2"])
    )
    state = reducer.reduce(state: state, intent: .pointWon(.left), at: 1).state
    state = reducer.reduce(state: state, intent: .pointWon(.right), at: 2).state
    state = reducer.reduce(state: state, intent: .pointWon(.left), at: 3).state
    let corrected = reducer.reduce(state: state, intent: .adjustPoints(side: .right, delta: -1), at: 4)

    #expect(corrected.state.leftPoints == 2)
    #expect(corrected.state.rightPoints == 0)
    #expect(corrected.state.servingSide == .left)
    #expect(corrected.state.doubles?.serverSlotIndex == 2)
    #expect(corrected.state.doubles?.receiverSlotIndex == 1)
    #expect(corrected.events == [.pointsAdjusted(side: .right, delta: -1, leftPoints: 2, rightPoints: 0)])
}

@Test func pingPongAdministrativeDecrementRecomputesServeFromReplay() {
    let reducer = RallyMatchReducer()
    var state = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: .pingPong())
    state = reducer.reduce(state: state, intent: .pointWon(.left), at: 1).state
    state = reducer.reduce(state: state, intent: .pointWon(.left), at: 2).state
    #expect(state.servingSide == .right)

    state = reducer.reduce(state: state, intent: .adjustPoints(side: .left, delta: -1), at: 3).state
    #expect(state.leftPoints == 1)
    #expect(state.rightPoints == 0)
    #expect(state.servingSide == .left)
}

@Test func rallyCorrectionHistorySurvivesAuthorityRebaseWithoutRestoringUndo() async {
    let reducer = RallyMatchReducer()
    var authoritative = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: .pingPong())
    authoritative = reducer.reduce(state: authoritative, intent: .pointWon(.left), at: 1).state
    authoritative = reducer.reduce(state: authoritative, intent: .pointWon(.left), at: 2).state
    let seed = ScoreSession<RallyMatchState, RallyMatchEvent>(
        gameType: .pingpong,
        ruleFamily: .s1,
        reducerType: "rally/v1",
        state: RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: .pingPong())
    )
    let session = ScoreSessionCore(seedSession: seed, reducer: reducer)

    _ = await session.rebase(to: authoritative, status: .live)
    #expect(!(await session.undo(actorId: "phone")))
    _ = await session.dispatch(actorId: "phone", intent: .adjustPoints(side: .left, delta: -1), at: 3)
    let corrected = await session.snapshot().state
    #expect(corrected.leftPoints == 1)
    #expect(corrected.servingSide == .left)
}

@Test func legacyRallySnapshotWithoutReplayStillDecodes() throws {
    let state = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: .badminton())
    let encoded = try JSONEncoder().encode(state)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "currentSetReplay")
    let legacy = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(RallyMatchState.self, from: legacy)
    #expect(decoded.currentSetReplay == nil)
    #expect(decoded.leftPoints == 0)
}

@Test func pingPongDoublesRequiresOpeningConfirmationAndDerivesNextReceiver() {
    let reducer = RallyMatchReducer()
    var state = RallyMatchEngine.initial(
        leftName: "Red",
        rightName: "Blue",
        rules: .pingPong(),
        doubles: .pingPong(
            playerNames: ["R1", "B1", "R2", "B2"],
            requiresOpeningConfirmation: true
        )
    )
    #expect(!reducer.reduce(state: state, intent: .pointWon(.left), at: 1).accepted)
    state = reducer.reduce(
        state: state,
        intent: .confirmPingPongDoublesOpening(serverSlot: 2, receiverSlot: 3),
        at: 2
    ).state
    #expect(state.doubles?.serverSlotIndex == 2)
    #expect(state.doubles?.receiverSlotIndex == 3)

    for point in 0..<11 {
        state = reducer.reduce(state: state, intent: .pointWon(.left), at: Int64(point + 3)).state
    }

    guard case .pingPong(let pendingRotation) = state.doubles?.rotation else {
        Issue.record("Expected ping-pong doubles rotation")
        return
    }
    #expect(pendingRotation.pendingGameOpening != nil)
    #expect(!reducer.reduce(state: state, intent: .pointWon(.right), at: 20).accepted)

    state = reducer.reduce(
        state: state,
        intent: .confirmPingPongDoublesOpening(serverSlot: 1, receiverSlot: nil),
        at: 21
    ).state
    #expect(state.doubles?.serverSlotIndex == 1)
    #expect(state.doubles?.receiverSlotIndex == 0)
}

@Test func legacyPingPongSnapshotWithoutReplayCanRecomputeAfterDecrement() {
    var state = RallyMatchEngine.initial(
        leftName: "A",
        rightName: "B",
        rules: .pingPong(maxSets: 5),
        openingServer: .left
    )
    state.leftPoints = 2
    state.rightPoints = 0
    state.servingSide = .right
    state.currentSetReplay = nil

    let result = RallyMatchReducer().reduce(
        state: state,
        intent: .adjustPoints(side: .left, delta: -1),
        at: 1
    )

    #expect(result.accepted)
    #expect(result.state.leftPoints == 1)
    #expect(result.state.rightPoints == 0)
    #expect(result.state.servingSide == .left)
    #expect(result.state.currentSetReplay != nil)
}

@Test func legacyPingPongDeuceSnapshotRebuildDoesNotPrematurelyCompleteSet() {
    var state = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: .pingPong())
    state.leftPoints = 11
    state.rightPoints = 11
    state.currentSetReplay = nil

    let result = RallyMatchReducer().reduce(
        state: state,
        intent: .adjustPoints(side: .left, delta: -1),
        at: 1
    )

    #expect(result.accepted)
    #expect(result.state.leftPoints == 10)
    #expect(result.state.rightPoints == 11)
    #expect(result.state.leftSets == 0)
    #expect(result.state.rightSets == 0)
}

@Test func rallyDoublesDisplayUsesBadmintonCourtOrderOnPhoneAndWatch() {
    var doubles = RallyDoublesState.badminton(
        playerNames: ["R1", "B1", "R2", "B2"],
        servingTeam0: true
    )
    doubles.rotation = .badminton(.init(
        serverSlotIndex: 2,
        receiverSlotIndex: 3,
        team0CourtOrderSwapped: true,
        team1CourtOrderSwapped: true
    ))
    let left = RallyDoublesDisplayState.resolve(doubles: doubles, logicalSide: .left, screenSide: .left)
    let right = RallyDoublesDisplayState.resolve(doubles: doubles, logicalSide: .right, screenSide: .right)
    #expect(left.topPlayerIndex == 2)
    #expect(left.bottomPlayerIndex == 0)
    #expect(left.serverIsTop == true)
    #expect(right.topPlayerIndex == 3)
    #expect(right.bottomPlayerIndex == 1)
    #expect(right.receiverIsTop == true)
}

@Test func linkedRallySnapshotPreservesDoublesNamesAndRotation() throws {
    let reducer = RallyMatchReducer()
    var state = RallyMatchEngine.initial(
        leftName: "Red",
        rightName: "Blue",
        rules: .pingPong(),
        doubles: .pingPong(playerNames: ["Red A", "Blue A", "Red B", "Blue B"])
    )
    state = reducer.reduce(state: state, intent: .pointWon(.left), at: 1).state
    state = reducer.reduce(state: state, intent: .pointWon(.right), at: 2).state
    let setup = LinkedScoreboardSetup(
        gameType: .pingpongDoubles,
        maxSets: 5,
        initialSnapshot: .rally(state)
    )

    let restored = try JSONDecoder().decode(
        LinkedScoreboardSetup.self,
        from: JSONEncoder().encode(setup)
    )

    #expect(restored.initialSnapshot?.rallyState?.doubles?.playerNames == [
        "Red A", "Blue A", "Red B", "Blue B"
    ])
    #expect(restored.initialSnapshot?.rallyState?.doubles?.serverSlotIndex == 1)
    #expect(restored.initialSnapshot?.rallyState?.doubles?.receiverSlotIndex == 2)
}

@Test func linkRevisionGateRejectsDuplicateOutOfOrderAndWrongSessionSnapshots() {
    let activeSession = UUID()
    let otherSession = UUID()
    var gate = LinkRevisionGate()

    let began = gate.beginSession(activeSession)
    let acceptedFirst = gate.accept(sessionId: activeSession, revision: 1)
    let acceptedDuplicate = gate.accept(sessionId: activeSession, revision: 1)
    let acceptedOlder = gate.accept(sessionId: activeSession, revision: 0)
    let acceptedOtherSession = gate.accept(sessionId: otherSession, revision: 2)
    let acceptedSecond = gate.accept(sessionId: activeSession, revision: 2)

    #expect(began)
    #expect(acceptedFirst)
    #expect(!acceptedDuplicate)
    #expect(!acceptedOlder)
    #expect(!acceptedOtherSession)
    #expect(acceptedSecond)
    #expect(gate.latestRevision == 2)
}

@Test func linkRevisionGateDoesNotResetForDuplicateSetup() {
    let sessionId = UUID()
    var gate = LinkRevisionGate()

    let began = gate.beginSession(sessionId)
    let accepted = gate.accept(sessionId: sessionId, revision: 4)
    let duplicateSetup = gate.beginSession(sessionId)

    #expect(began)
    #expect(accepted)
    #expect(!duplicateSetup)
    #expect(gate.latestRevision == 4)

    gate.endSession(sessionId)
    let restarted = gate.beginSession(sessionId)
    #expect(restarted)
    #expect(gate.latestRevision == 0)
}

@Test func threeByThreeOvertimeFinishesAfterTwoAdditionalPoints() {
    var state = BasketballMatchEngine.initial(leftName: "A", rightName: "B", gameMode: .threeXThree)
    state.leftScore = 18
    state.rightScore = 18
    state.gameTimeSeconds = 1
    state.gameRunning = true
    state.shotRunning = true
    state = BasketballMatchEngine.tickClock(state)

    #expect(state.isOvertime)
    #expect(!state.finished)
    state = BasketballMatchEngine.addPoints(state, side: .left, points: 1)
    #expect(!state.finished)
    state = BasketballMatchEngine.addPoints(state, side: .left, points: 1)
    #expect(state.finished)
    #expect(state.leftScore == 20)
}

@Test func fiveByFivePeriodExpiryCanAdvanceAndResetsPeriodState() {
    var state = BasketballMatchEngine.initial(leftName: "A", rightName: "B", gameMode: .fiveVFive)
    state.gameTimeSeconds = 1
    state.gameRunning = true
    state.shotRunning = true
    state.leftFouls = 4

    state = BasketballMatchEngine.tickClock(state)
    #expect(state.periodEnded)
    #expect(state.canAdvancePeriod)
    #expect(!state.finished)

    state = BasketballMatchEngine.advanceToNextPeriod(state)
    #expect(state.currentPeriod == 2)
    #expect(state.gameTimeSeconds == 600)
    #expect(state.leftFouls == 0)
    #expect(!state.periodEnded)
    #expect(!state.canAdvancePeriod)
}

@Test func basketballTimeoutStopsClocksAndRestoresShotClock() {
    var state = BasketballMatchEngine.initial(leftName: "A", rightName: "B", gameMode: .fiveVFive)
    state.gameRunning = true
    state.shotRunning = true
    state.shotTimeSeconds = 7
    let initialTimeouts = state.leftTimeouts

    state = BasketballMatchEngine.useTeamTimeout(state, side: .left)

    #expect(state.leftTimeouts == initialTimeouts - 1)
    #expect(!state.gameRunning)
    #expect(!state.shotRunning)
    #expect(state.shotTimeSeconds == 24)
}
