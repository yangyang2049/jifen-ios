import Testing
@testable import ScoreCore

@Suite("Edit score guards")
struct EditScoreGuardTests {
    @Test
    func rallyStopsBeforeSetWinAndAllowsOnePointLeadAtDeuce() {
        let reducer = RallyMatchReducer()
        var state = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: .pingPong())
        state.leftPoints = 10

        let winningEdit = reducer.reduce(state: state, intent: .adjustPoints(side: .left, delta: 1), at: 1)
        #expect(!winningEdit.accepted)
        #expect(winningEdit.state.leftPoints == 10)
        #expect(winningEdit.events.isEmpty)

        state.rightPoints = 10
        let oneAhead = reducer.reduce(state: state, intent: .adjustPoints(side: .left, delta: 1), at: 2)
        #expect(oneAhead.accepted)
        #expect(oneAhead.state.leftPoints == 11)
        let twoAhead = reducer.reduce(state: oneAhead.state, intent: .adjustPoints(side: .left, delta: 1), at: 3)
        #expect(!twoAhead.accepted)
        #expect(twoAhead.state.leftPoints == 11)
    }

    @Test
    func rallyUsesFinalSetTargetAndCap() {
        var rules = RallyRuleSet.foosball(maxSets: 3)
        rules.finalSetPointsToWin = 5
        rules.finalSetWinByTwo = true
        rules.finalSetPointCap = 8
        #expect(rules.maxEditablePointsBeforeSetWin(opponentScore: 4, setNumber: 3) == 5)
        #expect(rules.maxEditablePointsBeforeSetWin(opponentScore: 7, setNumber: 3) == 7)
    }

    @Test
    func tennisGuardsTieBreakGamesAndSetsForSinglesAndDoublesState() {
        var state = TennisMatchState(leftName: "A", rightName: "B", rules: .init(maxSets: 3))
        state.leftGames = 6
        state.rightGames = 6
        state.isTieBreak = true
        state.leftPoints = 6
        #expect(!state.canAdjustPoints(side: .left, delta: 1))
        state.rightPoints = 6
        #expect(state.canAdjustPoints(side: .left, delta: 1))

        state.leftGames = 7
        state.rightGames = 6
        #expect(!state.canAdjustGames(side: .right, delta: 1))
        state.leftSets = 2
        state.rightSets = 1
        #expect(!state.canAdjustSets(side: .right, delta: 1))

        var doubles = state
        doubles.doublesPlayerNames = ["A1", "B1", "A2", "B2"]
        #expect(doubles.canAdjustPoints(side: .left, delta: 1))
        #expect(!doubles.canAdjustGames(side: .right, delta: 1))
    }

    @Test
    func archeryAllowsPerfectArrowSumButRejectsScoreOverflowAndWinningSetEdit() {
        let archeryReducer = ArcheryMatchReducer()
        let archery = ArcheryMatchState(leftName: "A", rightName: "B", leftArrowSum: 29)
        let perfectArrowSum = archeryReducer.reduce(
            state: archery,
            intent: .adjustArrowSum(side: .left, delta: 1),
            at: 1
        )
        #expect(perfectArrowSum.accepted)
        #expect(perfectArrowSum.state.leftArrowSum == 30)

        let arrowOverflow = archeryReducer.reduce(
            state: perfectArrowSum.state,
            intent: .adjustArrowSum(side: .left, delta: 1),
            at: 2
        )
        #expect(!arrowOverflow.accepted)
        #expect(arrowOverflow.state == perfectArrowSum.state)

        let onePointFromWin = ArcheryMatchState(
            leftName: "A",
            rightName: "B",
            leftSetPoints: ArcheryMatchRules.default.setPointsToWin - 1
        )
        let winningSetEdit = archeryReducer.reduce(
            state: onePointFromWin,
            intent: .adjustSetPoints(side: .left, delta: 1),
            at: 3
        )
        #expect(!winningSetEdit.accepted)
        #expect(winningSetEdit.state == onePointFromWin)
    }

    @Test
    func eightBallAndBoxingRejectOverflowWithoutMutation() {

        let eightBall = EightBallState.initial(targetPoints: 5, handicapRacks: 1, handicapBeneficiary: .left)
        let rackOverflow = EightBallReducer().reduce(
            state: eightBall,
            intent: .adminAdjust(left: 5, right: 0),
            at: 1
        )
        #expect(!rackOverflow.accepted)
        #expect(rackOverflow.state == eightBall)

        let boxing = BoxingMatchState(
            leftName: "A",
            rightName: "B",
            maxRounds: 3,
            leftRoundsWon: 1,
            rightRoundsWon: 1,
            currentRound: 3
        )
        let roundOverflow = BoxingMatchReducer().reduce(
            state: boxing,
            intent: .adjust(
                leftTotal: 20,
                rightTotal: 18,
                currentRound: 3,
                leftRoundsWon: 2,
                rightRoundsWon: 1
            ),
            at: 2
        )
        #expect(!roundOverflow.accepted)
        #expect(roundOverflow.state == boxing)
    }

    @Test
    func rallyPositiveEditAdvancesServeAndDoublesRotation() {
        let reducer = RallyMatchReducer()
        var rules = RallyRuleSet.pickleball()
        rules.useRallyScoring = true
        let makeState = {
            RallyMatchEngine.initial(
                leftName: "Red",
                rightName: "Blue",
                rules: rules,
                openingServer: .left,
                doubles: .pickleball(playerNames: ["Red A", "Blue A", "Red B", "Blue B"])
            )
        }

        // 正常得分路径：右队接发赢球
        let viaPoint = reducer.reduce(state: makeState(), intent: .pointWon(.right), at: 1).state
        // 编辑 +1 应产生相同的轮转状态（发球方、发球员、接发员、搭档换位）
        let viaEdit = reducer.reduce(state: makeState(), intent: .adjustPoints(side: .right, delta: 1), at: 1).state
        #expect(viaEdit.rightPoints == 1)
        #expect(viaEdit.servingSide == viaPoint.servingSide)
        #expect(viaEdit.doubles?.serverSlotIndex == viaPoint.doubles?.serverSlotIndex)
        #expect(viaEdit.doubles?.receiverSlotIndex == viaPoint.doubles?.receiverSlotIndex)
        #expect(viaEdit.doubles?.pickleballServerNumber == viaPoint.doubles?.pickleballServerNumber)

        // 编辑 +1 后继续正常得分，应从正确轮转推进（而不是陈旧状态）
        let nextPoint = reducer.reduce(state: viaEdit, intent: .pointWon(.right), at: 2).state
        let nextPointRef = reducer.reduce(state: viaPoint, intent: .pointWon(.right), at: 2).state
        #expect(nextPoint.rightPoints == 2)
        #expect(nextPoint.servingSide == nextPointRef.servingSide)
        #expect(nextPoint.doubles?.serverSlotIndex == nextPointRef.doubles?.serverSlotIndex)
    }

    @Test
    func pingPongDoublesPositiveEditAdvancesRotation() {
        let reducer = RallyMatchReducer()
        let makeState = {
            RallyMatchEngine.initial(
                leftName: "Red",
                rightName: "Blue",
                rules: .pingPong(maxSets: 5),
                openingServer: .left,
                doubles: .pingPong(playerNames: ["Red A", "Blue A", "Red B", "Blue B"])
            )
        }
        let viaPoint = reducer.reduce(state: makeState(), intent: .pointWon(.left), at: 1).state
        let viaEdit = reducer.reduce(state: makeState(), intent: .adjustPoints(side: .left, delta: 1), at: 1).state
        #expect(viaEdit.leftPoints == 1)
        #expect(viaEdit.servingSide == viaPoint.servingSide)
        #expect(viaEdit.doubles?.serverSlotIndex == viaPoint.doubles?.serverSlotIndex)
        #expect(viaEdit.doubles?.receiverSlotIndex == viaPoint.doubles?.receiverSlotIndex)
    }
}
