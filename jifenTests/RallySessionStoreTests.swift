import XCTest
import ScoreCore
@testable import jifen

@MainActor
final class RallySessionStoreTests: XCTestCase {
    private let participants: [SessionParticipant] = [
        .init(id: "left-top", name: "Red A", role: "player"),
        .init(id: "left-bottom", name: "Red B", role: "player"),
        .init(id: "right-top", name: "Blue A", role: "player"),
        .init(id: "right-bottom", name: "Blue B", role: "player")
    ]

    func testPingPongDoublesUsesCrossPlatformSlotOrder() {
        let store = RallySessionStore(
            leftName: "Red",
            rightName: "Blue",
            gameType: .pingpongDoubles,
            rules: .pingPong(),
            participants: participants
        )

        XCTAssertEqual(store.state.doubles?.playerNames, ["Red A", "Blue A", "Red B", "Blue B"])
        XCTAssertEqual(store.state.doubles?.serverSlotIndex, 0)
        XCTAssertEqual(store.state.doubles?.receiverSlotIndex, 1)
    }

    func testBadmintonDoublesUsesCrossPlatformSlotOrder() {
        let store = RallySessionStore(
            leftName: "Red",
            rightName: "Blue",
            gameType: .badmintonDoubles,
            rules: .badminton(),
            participants: participants
        )

        XCTAssertEqual(store.state.doubles?.playerNames, ["Red A", "Blue A", "Red B", "Blue B"])
        XCTAssertEqual(store.state.doubles?.serverSlotIndex, 2)
        XCTAssertEqual(store.state.doubles?.receiverSlotIndex, 1)
    }

    func testSinglesDoesNotCreateDoublesState() {
        let store = RallySessionStore(
            leftName: "Red",
            rightName: "Blue",
            gameType: .pingpong,
            rules: .pingPong()
        )

        XCTAssertNil(store.state.doubles)
    }

    func testPingPongDecidingSwitchPointIsHalfTarget() {
        var rules = RallyRuleSet.pingPong()
        let target = 11
        rules.pointsToWinSet = target
        rules.decidingSetSideSwitchPoint = RallyRuleSet.decidingSetSideSwitchPoint(for: .pingpong, pointsPerSet: target)
        XCTAssertEqual(rules.decidingSetSideSwitchPoint, 5)
    }

    func testRallyMatchStateRoundTripsThroughJSONSnapshot() throws {
        var rules = RallyRuleSet.pingPong(maxSets: 5)
        rules.autoChangeSides = true
        rules.decidingSetSideSwitchPoint = 5
        var state = RallyMatchEngine.initial(leftName: "红方", rightName: "蓝方", rules: rules)
        state.leftPoints = 7
        state.rightPoints = 5
        state.leftSets = 1
        state.sidesSwapped = true

        let data = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(RallyMatchState.self, from: data)

        XCTAssertEqual(restored.leftPoints, 7)
        XCTAssertEqual(restored.rightPoints, 5)
        XCTAssertEqual(restored.leftSets, 1)
        XCTAssertTrue(restored.sidesSwapped)
        XCTAssertEqual(restored.rules.decidingSetSideSwitchPoint, 5)
    }

    func testTennisPlayAllAcceptsEvenSetsAndFinishesInDraw() {
        let reducer = TennisMatchReducer()
        var state = TennisMatchState(
            leftName: "A",
            rightName: "B",
            rules: .init(maxSets: 4, matchCompletionMode: .playAll, autoChangeSides: false)
        )

        state = reducer.reduce(state: state, intent: .adjustSets(side: .left, delta: 1), at: 1).state
        state = reducer.reduce(state: state, intent: .adjustSets(side: .left, delta: 1), at: 2).state
        state = reducer.reduce(state: state, intent: .adjustSets(side: .right, delta: 1), at: 3).state
        XCTAssertFalse(state.rules.isMatchFinished(leftSets: state.leftSets, rightSets: state.rightSets))
        state = reducer.reduce(state: state, intent: .adjustSets(side: .right, delta: 1), at: 4).state

        XCTAssertTrue(state.rules.isMatchFinished(leftSets: state.leftSets, rightSets: state.rightSets))
        XCTAssertEqual(state.leftSets, 2)
        XCTAssertEqual(state.rightSets, 2)
    }

    func testTennisClassicStillFinishesEarly() {
        let reducer = TennisMatchReducer()
        var state = TennisMatchState(
            leftName: "A",
            rightName: "B",
            rules: .init(maxSets: 5, matchCompletionMode: .bestOf, autoChangeSides: false)
        )

        state = reducer.reduce(state: state, intent: .adjustSets(side: .left, delta: 1), at: 1).state
        state = reducer.reduce(state: state, intent: .adjustSets(side: .left, delta: 1), at: 2).state
        state = reducer.reduce(state: state, intent: .adjustSets(side: .left, delta: 1), at: 3).state

        XCTAssertTrue(state.rules.isMatchFinished(leftSets: state.leftSets, rightSets: state.rightSets))
        XCTAssertEqual(state.leftSets, 3)
    }

    func testTennisTieBreakServeUsesOneThenTwoPointBlocks() {
        let reducer = TennisMatchReducer()
        var state = TennisMatchState(
            leftName: "A",
            rightName: "B",
            rules: .init(maxSets: 3, autoChangeSides: false),
            openingServer: .left
        )
        state.leftGames = 6
        state.rightGames = 6
        state.isTieBreak = true
        state.firstServerInSet = .left
        state.servingSide = .left
        state.leftPoints = 0
        state.rightPoints = 0

        XCTAssertEqual(state.servingSide, .left)
        state = reducer.reduce(state: state, intent: .pointWon(.left), at: 1).state
        XCTAssertEqual(state.servingSide, .right)
        state = reducer.reduce(state: state, intent: .pointWon(.right), at: 2).state
        XCTAssertEqual(state.servingSide, .right)
        state = reducer.reduce(state: state, intent: .pointWon(.left), at: 3).state
        XCTAssertEqual(state.servingSide, .left)
    }

    func testSportsSetupResultDefaultsMissingCompletionMode() throws {
        let oldJSON = Data(#"{"team1Name":"A","team2Name":"B","maxSets":5}"#.utf8)
        let restored = try JSONDecoder().decode(SportsSetupResult.self, from: oldJSON)

        XCTAssertNil(restored.matchCompletionMode)
        XCTAssertEqual(restored.maxSets, 5)
    }
}
