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
        let viewModel = TennisViewModel()
        viewModel.setConfig(maxSets: 4, matchCompletionMode: .playAll)

        viewModel.adjustSets(isLeft: true, delta: 1)
        viewModel.adjustSets(isLeft: true, delta: 1)
        viewModel.adjustSets(isLeft: false, delta: 1)
        XCTAssertFalse(viewModel.gameFinished)
        viewModel.adjustSets(isLeft: false, delta: 1)

        XCTAssertTrue(viewModel.gameFinished)
        XCTAssertEqual(viewModel.leftTeam.sets, 2)
        XCTAssertEqual(viewModel.rightTeam.sets, 2)
        XCTAssertEqual(viewModel.getWinnerName(), "")
    }

    func testTennisClassicStillFinishesEarly() {
        let viewModel = TennisViewModel()
        viewModel.setConfig(maxSets: 5, matchCompletionMode: .bestOf)

        viewModel.adjustSets(isLeft: true, delta: 1)
        viewModel.adjustSets(isLeft: true, delta: 1)
        viewModel.adjustSets(isLeft: true, delta: 1)

        XCTAssertTrue(viewModel.gameFinished)
    }

    func testTennisTieBreakServeUsesOneThenTwoPointBlocks() {
        let viewModel = TennisViewModel()
        viewModel.setConfig(maxSets: 3, openingServerSide: .left)
        viewModel.leftTeam.games = 6
        viewModel.rightTeam.games = 6
        viewModel.isTieBreak = true
        viewModel.tieBreakFirstServer = .left
        viewModel.leftTeam.score = 0
        viewModel.rightTeam.score = 0

        XCTAssertTrue(viewModel.isLeftServing()) // point 0 → block 0 → left
        viewModel.leftTeam.score = 1
        XCTAssertFalse(viewModel.isLeftServing()) // point 1 → block 1 → right
        viewModel.rightTeam.score = 1 // total 2
        XCTAssertFalse(viewModel.isLeftServing()) // block 1 still
        viewModel.leftTeam.score = 2 // total 3
        XCTAssertTrue(viewModel.isLeftServing()) // block 2 → left
    }

    func testTennisDoublesServerSlotAdvancesEachGame() {
        let viewModel = TennisViewModel()
        viewModel.setConfig(maxSets: 3, openingServerSide: .left, isSingles: false)
        XCTAssertEqual(viewModel.currentServerSlot(), 0)
        viewModel.leftTeam.games = 1
        XCTAssertEqual(viewModel.currentServerSlot(), 1)
        viewModel.rightTeam.games = 1 // total 2
        XCTAssertEqual(viewModel.currentServerSlot(), 2)
    }

    func testTennisNewFormatsNormalizeAndFinishCorrectly() {
        let shortSet = TennisViewModel()
        shortSet.setConfig(maxSets: 1, autoChangeSides: false, gamesPerSet: 4)
        shortSet.leftTeam.games = 4
        shortSet.rightTeam.games = 4
        shortSet.isTieBreak = true
        shortSet.tieBreakTarget = 7
        shortSet.leftTeam.score = 6
        shortSet.rightTeam.score = 5
        shortSet.addScore(isLeft: true, points: 1)
        XCTAssertEqual(shortSet.leftTeam.games, 5)
        XCTAssertTrue(shortSet.gameFinished)

        let matchTieBreak = TennisViewModel()
        matchTieBreak.setConfig(
            maxSets: 5,
            autoChangeSides: false,
            matchCompletionMode: .playAll,
            gamesPerSet: 6,
            setScoringMode: "tiebreak_only"
        )
        matchTieBreak.tieBreakTarget = 10
        XCTAssertEqual(matchTieBreak.maxSets, 1)
        XCTAssertEqual(matchTieBreak.matchCompletionMode, .bestOf)
        XCTAssertTrue(matchTieBreak.isTieBreak)
        matchTieBreak.leftTeam.score = 9
        matchTieBreak.rightTeam.score = 9
        matchTieBreak.addScore(isLeft: true, points: 1)
        XCTAssertFalse(matchTieBreak.gameFinished)
        matchTieBreak.addScore(isLeft: true, points: 1)
        XCTAssertEqual(matchTieBreak.leftTeam.sets, 1)
        XCTAssertTrue(matchTieBreak.gameFinished)

        matchTieBreak.adjustGames(isLeft: true, delta: 1)
        XCTAssertEqual(matchTieBreak.leftTeam.games, 1)
    }

    func testSportsSetupResultDefaultsMissingCompletionMode() throws {
        let oldJSON = Data(#"{"team1Name":"A","team2Name":"B","maxSets":5}"#.utf8)
        let restored = try JSONDecoder().decode(SportsSetupResult.self, from: oldJSON)

        XCTAssertNil(restored.matchCompletionMode)
        XCTAssertEqual(restored.maxSets, 5)
    }
}
