import Foundation
import Testing
import LinkCore
import ScoreCore
import SessionCore

@Test func eightBallRaceToMatchesAndroidFixture() {
    let reducer = EightBallReducer()
    var state = EightBallState.initial(targetPoints: 3)
    state = reducer.reduce(state: state, intent: .addRack(.left), at: 1).state
    state = reducer.reduce(state: state, intent: .addRack(.left), at: 2).state
    state = reducer.reduce(state: state, intent: .addRack(.right), at: 3).state
    #expect(state.leftPoints == 2)
    #expect(state.rightPoints == 1)
    #expect(!state.finished)
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

@Test func badmintonPointCapHelperMatchesAndroidMatrix() {
    #expect(RallyRuleSet.badmintonPointCap(for: 11) == 21)
    #expect(RallyRuleSet.badmintonPointCap(for: 15) == 21)
    #expect(RallyRuleSet.badmintonPointCap(for: 21) == 30)
    #expect(RallyRuleSet.badmintonPointCap(for: 25) == nil)
    #expect(RallyRuleSet.badmintonPointCap(for: 999) == nil)
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
