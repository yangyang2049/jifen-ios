import Testing
@testable import ScoreCore

@Suite("Archery match reducer")
struct ArcheryMatchReducerTests {
    private let reducer = ArcheryMatchReducer()

    private func initial() -> ArcheryMatchState {
        ArcheryMatchState(leftName: "红方", rightName: "蓝方")
    }

    private func reduce(_ state: ArcheryMatchState, _ intent: ArcheryMatchIntent) -> ArcheryMatchState {
        let result = reducer.reduce(state: state, intent: intent, at: 0)
        #expect(result.accepted)
        return result.state
    }

    @Test
    func normalSetAwardsTwoPointsOnWin() {
        var state = initial()
        for _ in 0..<3 {
            state = reduce(state, .recordArrow(side: nil, value: 10))
            state = reduce(state, .recordArrow(side: nil, value: 9))
        }
        #expect(state.setCompletionPending)
        #expect(state.pendingLeftSetPoints == 2)
        #expect(state.pendingRightSetPoints == 0)
        state = reduce(state, .completeSet(closestToCenterWinner: nil))
        #expect(state.leftSetPoints == 2)
        #expect(state.rightSetPoints == 0)
        #expect(state.currentSet == 2)
        #expect(state.leftArrowSum == 0)
    }

    @Test
    func tiedSetAwardsOnePointEach() {
        var state = initial()
        for _ in 0..<3 {
            state = reduce(state, .recordArrow(side: nil, value: 9))
            state = reduce(state, .recordArrow(side: nil, value: 9))
        }
        state = reduce(state, .completeSet(closestToCenterWinner: nil))
        #expect(state.leftSetPoints == 1)
        #expect(state.rightSetPoints == 1)
    }

    @Test
    func shootOffTieRequiresClosestToCenter() {
        var state = ArcheryMatchState(
            leftName: "A",
            rightName: "B",
            leftSetPoints: 5,
            rightSetPoints: 5,
            arrowsPerSet: 1
        )
        state = reduce(state, .recordArrow(side: nil, value: 10))
        state = reduce(state, .recordArrow(side: nil, value: 10))
        #expect(state.closestToCenterPending)
        let rejected = reducer.reduce(state: state, intent: .completeSet(closestToCenterWinner: nil), at: 0)
        #expect(!rejected.accepted)
        state = reduce(state, .completeSet(closestToCenterWinner: .left))
        #expect(state.finished)
        #expect(state.winnerSide == .left)
        #expect(state.leftSetPoints == 6)
    }

    @Test
    func tiedShootOffCanRepeatUntilResolved() {
        var state = ArcheryMatchState(
            leftName: "A",
            rightName: "B",
            leftSetPoints: 5,
            rightSetPoints: 5,
            arrowsPerSet: 1
        )
        state = reduce(state, .recordArrow(side: nil, value: nil))
        state = reduce(state, .recordArrow(side: nil, value: nil))
        #expect(state.closestToCenterPending)
        state = reduce(state, .repeatShootOff)
        #expect(state.leftSetPoints == 5)
        #expect(state.rightSetPoints == 5)
        #expect(state.leftArrowSum == 0)
        #expect(state.rightArrowSum == 0)
        #expect(state.arrowsLeftThisSet == 0)
        #expect(state.arrowsRightThisSet == 0)
        #expect(state.arrowsPerSet == 1)
        #expect(!state.setCompletionPending)

        state = reduce(state, .recordArrow(side: nil, value: 9))
        state = reduce(state, .recordArrow(side: nil, value: 9))
        state = reduce(state, .repeatShootOff)
        state = reduce(state, .recordArrow(side: nil, value: 10))
        state = reduce(state, .recordArrow(side: nil, value: 9))
        state = reduce(state, .completeSet(closestToCenterWinner: nil))
        #expect(state.finished)
        #expect(state.winnerSide == .left)
    }

    @Test
    func zeroRingAndMissProduceDistinctEvents() {
        let zero = reducer.reduce(
            state: initial(),
            intent: .recordArrow(side: nil, value: 0),
            at: 0
        )
        let miss = reducer.reduce(
            state: initial(),
            intent: .recordArrow(side: nil, value: nil),
            at: 0
        )

        #expect(zero.accepted)
        #expect(miss.accepted)
        #expect(zero.state.leftArrowSum == 0)
        #expect(miss.state.leftArrowSum == 0)
        #expect(zero.state.arrowsLeftThisSet == 1)
        #expect(miss.state.arrowsLeftThisSet == 1)
        #expect(zero.events == [
            .arrowScored(side: .left, points: 0, leftArrowSum: 0, rightArrowSum: 0)
        ])
        #expect(miss.events == [
            .arrowMissed(side: .left, leftArrowSum: 0, rightArrowSum: 0)
        ])
    }

    @Test
    func resetAfterSideExchangeRestoresNamesAndOpeningShooterIdentity() {
        var state = ArcheryMatchState(
            leftName: "A",
            rightName: "B",
            currentShooterIsLeft: true,
            openingShooterIsLeft: true
        )
        state = reduce(state, .exchangeSides)
        #expect(state.sidesSwapped)
        #expect(state.leftName == "A")
        #expect(state.rightName == "B")
        #expect(state.currentShooterIsLeft)
        #expect(state.openingShooterIsLeft)
        state = reduce(state, .reset)
        #expect(state.leftName == "A")
        #expect(state.rightName == "B")
        #expect(state.openingShooterIsLeft)
        #expect(state.currentShooterIsLeft)
        #expect(!state.sidesSwapped)
    }

    @Test
    func firstToSixFinishesMatch() {
        var state = ArcheryMatchState(
            leftName: "A",
            rightName: "B",
            leftSetPoints: 4,
            rightSetPoints: 2
        )
        for _ in 0..<3 {
            state = reduce(state, .recordArrow(side: nil, value: 10))
            state = reduce(state, .recordArrow(side: nil, value: 8))
        }
        state = reduce(state, .completeSet(closestToCenterWinner: nil))
        #expect(state.finished)
        #expect(state.leftSetPoints == 6)
    }
}
