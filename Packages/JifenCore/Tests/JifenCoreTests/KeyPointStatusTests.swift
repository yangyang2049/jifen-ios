import Testing
@testable import ScoreCore

@Suite("Key point status")
struct KeyPointStatusTests {
    @Test func tableTennisGameAndMatchPoint() {
        var state = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: .pingPong(maxSets: 3))
        state.leftPoints = 10
        #expect(KeyPointResolver.rally(state: state) == .init(kind: .game, side: .left))

        state.leftSets = 1
        #expect(KeyPointResolver.rally(state: state) == .init(kind: .match, side: .left))
    }

    @Test func cappedTieHidesTwoSameLevelStatuses() {
        var rules = RallyRuleSet.badminton(maxSets: 3)
        rules.pointCap = 30
        var state = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: rules)
        state.leftPoints = 29
        state.rightPoints = 29
        #expect(KeyPointResolver.rally(state: state) == nil)
    }

    @Test func traditionalPickleballOnlyServerCanHaveKeyPoint() {
        var state = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: .pickleball(maxSets: 3), openingServer: .right)
        state.leftPoints = 9
        state.rightPoints = 10
        #expect(KeyPointResolver.rally(state: state) == .init(kind: .game, side: .right))
    }

    @Test func singleSetUsesMatchPoint() {
        var state = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: .foosball(maxSets: 1))
        state.leftPoints = 4
        #expect(KeyPointResolver.rally(state: state) == .init(kind: .match, side: .left))
    }

    @Test func tennisOmitsGamePointAndFindsSetPoint() {
        var snapshot = tennisSnapshot()
        snapshot.leftPoints = 3
        #expect(KeyPointResolver.tennis(snapshot: snapshot) == nil)

        snapshot.leftGames = 5
        #expect(KeyPointResolver.tennis(snapshot: snapshot) == .init(kind: .set, side: .left))
    }

    @Test func tennisTieBreakMatchPoint() {
        var snapshot = tennisSnapshot()
        snapshot.leftPoints = 6
        snapshot.rightPoints = 5
        snapshot.leftGames = 6
        snapshot.rightGames = 6
        snapshot.leftSets = 1
        snapshot.isTieBreak = true
        #expect(KeyPointResolver.tennis(snapshot: snapshot) == .init(kind: .match, side: .left))
    }

    @Test func higherLevelStatusWinsWhenBothSidesDiffer() {
        var snapshot = tennisSnapshot()
        snapshot.leftPoints = 3
        snapshot.rightPoints = 3
        snapshot.leftGames = 6
        snapshot.rightGames = 6
        snapshot.leftSets = 1
        snapshot.usesNoAdScoring = true
        #expect(KeyPointResolver.tennis(snapshot: snapshot) == .init(kind: .match, side: .left))
    }

    @Test func tennisNewFormatsProduceSetAndMatchPoints() {
        var shortSet = tennisSnapshot()
        shortSet.gamesPerSet = 4
        shortSet.leftGames = 3
        shortSet.leftPoints = 3
        #expect(KeyPointResolver.tennis(snapshot: shortSet) == .init(kind: .set, side: .left))

        var matchTieBreak = tennisSnapshot()
        matchTieBreak.maxSets = 1
        matchTieBreak.setScoringMode = "tiebreak_only"
        matchTieBreak.isTieBreak = true
        matchTieBreak.tieBreakTarget = 10
        matchTieBreak.leftPoints = 9
        matchTieBreak.rightPoints = 8
        #expect(KeyPointResolver.tennis(snapshot: matchTieBreak) == .init(kind: .match, side: .left))
    }

    private func tennisSnapshot() -> TennisKeyPointSnapshot {
        .init(
            leftPoints: 0,
            rightPoints: 0,
            leftGames: 0,
            rightGames: 0,
            leftSets: 0,
            rightSets: 0,
            maxSets: 3,
            matchCompletionMode: .bestOf,
            isTieBreak: false,
            tieBreakTarget: 7,
            usesNoAdScoring: false,
            finished: false
        )
    }
}
