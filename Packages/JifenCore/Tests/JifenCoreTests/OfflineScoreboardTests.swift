import Foundation
import Testing
import ScoreCore

private final class TestFootballClock: @unchecked Sendable, FootballClock {
    var monotonic: Int64 = 0
    var wall: Int64 = 1_000

    func monotonicSeconds() -> Int64 { monotonic }
    func wallClockMilliseconds() -> Int64 { wall }
}

@Test func newRallyProfilesUseUncappedTwoPointScoring() {
    let reducer = RallyMatchReducer()

    var shuttlecock = RallyMatchEngine.initial(
        leftName: "A",
        rightName: "B",
        rules: .shuttlecock(pointsPerSet: 21)
    )
    shuttlecock.leftPoints = 20
    shuttlecock.rightPoints = 20
    shuttlecock = reducer.reduce(state: shuttlecock, intent: .pointWon(.left), at: 1).state
    #expect(shuttlecock.leftPoints == 21)
    #expect(shuttlecock.rightPoints == 20)
    shuttlecock = reducer.reduce(state: shuttlecock, intent: .pointWon(.left), at: 2).state
    #expect(shuttlecock.leftSets == 1)

    var squash = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: .squash())
    squash.leftPoints = 10
    squash.rightPoints = 10
    squash = reducer.reduce(state: squash, intent: .pointWon(.right), at: 3).state
    #expect(squash.rightPoints == 11)
    #expect(!squash.finished)
    squash = reducer.reduce(state: squash, intent: .pointWon(.right), at: 4).state
    #expect(squash.rightSets == 1)
}

@Test func softTennisUsesSevenGameMatchAndTwoPointFinalGameSideChanges() {
    let rules = TennisRuleSet.softTennis(gamesPerSet: 7)
    #expect(rules.maxSets == 1)
    #expect(rules.gamesPerSet == 4)
    #expect(rules.softTennisMatchGames == 7)
    var state = TennisMatchState(leftName: "A", rightName: "B", rules: rules)
    state.leftGames = 3
    state.rightGames = 3
    state.isTieBreak = true
    state.leftPoints = 1
    state.rightPoints = 0
    let result = TennisMatchReducer().reduce(state: state, intent: .pointWon(.right), at: 1)
    #expect(result.state.sidesSwapped)
    #expect(result.state.leftPoints == 1)
    #expect(result.state.rightPoints == 1)
}

@Test func softTennisFinishesSevenGameMatchAtFourTwoAndNineGameAtFiveThree() {
    let reducer = TennisMatchReducer()
    for (matchGames, initialGames, expectedGames) in [(7, 3, 4), (9, 4, 5)] {
        var state = TennisMatchState(
            leftName: "A",
            rightName: "B",
            rules: .softTennis(gamesPerSet: matchGames)
        )
        state.leftGames = initialGames
        state.rightGames = initialGames - 1
        state.leftPoints = 3
        state.rightPoints = 0
        let result = reducer.reduce(state: state, intent: .pointWon(.left), at: 1)
        #expect(result.state.finished)
        #expect(result.state.leftGames == expectedGames)
        #expect(result.state.leftSets == 1)
    }
}

@Test func padelGoldenAndStarPointModesAreDeterministicAndUndoableBySnapshot() {
    let reducer = TennisMatchReducer()

    var golden = TennisMatchState(
        leftName: "A",
        rightName: "B",
        rules: .padel(deuceMode: .goldenPoint)
    )
    golden.leftPoints = 3
    golden.rightPoints = 3
    golden = reducer.reduce(state: golden, intent: .pointWon(.left), at: 1).state
    #expect(golden.leftGames == 1)
    #expect(golden.leftPoints == 0)

    var star = TennisMatchState(
        leftName: "A",
        rightName: "B",
        rules: .padel(deuceMode: .starPoint)
    )
    star.leftPoints = 3
    star.rightPoints = 3
    star = reducer.reduce(state: star, intent: .pointWon(.left), at: 1).state
    star = reducer.reduce(state: star, intent: .pointWon(.right), at: 2).state
    star = reducer.reduce(state: star, intent: .pointWon(.left), at: 3).state
    star = reducer.reduce(state: star, intent: .pointWon(.right), at: 4).state
    #expect(star.starPointReturnedAdvantages == 2)
    let beforeDecisive = star
    star = reducer.reduce(state: star, intent: .pointWon(.left), at: 5).state
    #expect(star.leftGames == 1)
    #expect(beforeDecisive.starPointReturnedAdvantages == 2)
}

@Test func tennisAndPadelReturnLostAdvantageToCanonicalDeuceLikeAndroid31() {
    let reducer = TennisMatchReducer()
    for rules in [TennisRuleSet(), .padel(deuceMode: .starPoint)] {
        var state = TennisMatchState(leftName: "A", rightName: "B", rules: rules)
        state.leftPoints = 4
        state.rightPoints = 3
        let result = reducer.reduce(state: state, intent: .pointWon(.right), at: 1)
        #expect(result.state.leftPoints == 3)
        #expect(result.state.rightPoints == 3)
    }
}

@Test func footballClockUsesMonotonicTimeAndRestoresRunningStateFromWallAnchor() {
    let clock = TestFootballClock()
    var session = FootballMatchClockSession(
        state: .init(halfLengthSeconds: 90, isRunning: false),
        clock: clock
    )
    session.start()
    clock.monotonic = 12
    #expect(session.elapsedSecondsNow() == 12)
    session.pause()
    #expect(session.state.elapsedSeconds == 12)
    #expect(!session.state.isRunning)

    var saved = session.state
    saved.isRunning = true
    saved.savedWallClockMilliseconds = clock.wall
    clock.wall += 5_000
    var restored = FootballMatchClockSession(state: saved, clock: clock)
    restored.reconcileAfterRestore()
    #expect(restored.state.elapsedSeconds == 17)
    #expect(restored.state.isRunning)
}

@Test func footballStoppageCannotBeUndoneBelowElapsedStoppageTime() {
    let clock = TestFootballClock()
    var session = FootballMatchClockSession(
        state: .init(halfLengthSeconds: 60),
        clock: clock
    )
    let didAdd = session.addStoppageSeconds(30)
    #expect(didAdd)
    session.start()
    clock.monotonic = 75
    let rejected = session.undoStoppageSeconds(30)
    #expect(!rejected)
    #expect(session.state.stoppageSeconds[0] == 30)
    let accepted = session.undoStoppageSeconds(15)
    #expect(accepted)
    #expect(session.state.stoppageSeconds[0] == 15)
}

@Test func officialBreakFreezesInputSupportsPreparationSkipUndoAndRestore() {
    var breaks = OfficialBreakSession()
    breaks.begin(
        sport: .badminton,
        kind: .gameBreak,
        durationSeconds: 90,
        afterAction: .advanceAndExchange,
        nowMilliseconds: 1_000
    )
    #expect(breaks.inputFrozen)
    _ = breaks.advance(seconds: 87)
    #expect(breaks.state?.phase == .preparation)
    #expect(breaks.state?.remainingSeconds == 3)
    breaks.skip()
    #expect(!breaks.inputFrozen)
    let didUndo = breaks.undo()
    #expect(didUndo)
    #expect(breaks.inputFrozen)

    breaks.reconcileAfterRestore(nowMilliseconds: 95_000)
    #expect(breaks.state?.remainingSeconds == 0)
    #expect(!breaks.inputFrozen)
}

@Test func restoredOfficialBreakKeepsUndoPredecessorAndAdministrativeTitle() throws {
    let saved = OfficialBreakState(
        sport: .pingpong,
        kind: .timeout,
        durationSeconds: 60,
        title: "暂停 · 张三",
        nowMilliseconds: 5_000
    )
    let restoredState = try JSONDecoder().decode(
        OfficialBreakState.self,
        from: JSONEncoder().encode(saved)
    )
    var restored = OfficialBreakSession(state: restoredState)

    #expect(restored.state?.title == "暂停 · 张三")
    #expect(restored.inputFrozen)
    let restoredUndoAccepted = restored.undo()
    #expect(restoredUndoAccepted)
    #expect(restored.state == nil)
    #expect(!restored.inputFrozen)
}

@Test func officialBreakSourcePersistsAndMigratesLegacyAdministrativeSnapshots() throws {
    let administrative = OfficialBreakState(
        sport: .pingpong,
        kind: .medical,
        durationSeconds: 600,
        source: .administrative
    )
    let roundTripped = try JSONDecoder().decode(
        OfficialBreakState.self,
        from: JSONEncoder().encode(administrative)
    )
    #expect(roundTripped.source == .administrative)

    let legacyTimeout = Data(#"{"sport":"pingpong","kind":"timeout","phase":"countdown","durationSeconds":60,"remainingSeconds":42,"isRunning":true,"startedWallClockMilliseconds":1000,"updatedWallClockMilliseconds":19000,"afterAction":"none"}"#.utf8)
    let migratedTimeout = try JSONDecoder().decode(OfficialBreakState.self, from: legacyTimeout)
    #expect(migratedTimeout.source == .administrative)

    let legacyOrdinary = Data(#"{"sport":"badminton","kind":"game_break","phase":"countdown","durationSeconds":120,"remainingSeconds":90,"isRunning":true,"startedWallClockMilliseconds":1000,"updatedWallClockMilliseconds":31000,"afterAction":"advance_and_exchange"}"#.utf8)
    let migratedOrdinary = try JSONDecoder().decode(OfficialBreakState.self, from: legacyOrdinary)
    #expect(migratedOrdinary.source == .official)
}

@Test func football31SeparatesElevenAsideAndFiveAsideClockPolicies() {
    let clock = TestFootballClock()
    var football = FootballMatchClockSession(
        state: .init(halfLengthSeconds: 60),
        gameType: .football,
        clock: clock
    )
    football.resetForNewGame()
    #expect(football.state.isRunning)
    football.toggleRunning()
    #expect(football.state.isRunning)
    let addedStoppage = football.addStoppageSeconds(15)
    #expect(addedStoppage)
    clock.monotonic = 65
    #expect(football.mainDisplaySeconds == 60)
    #expect(football.elapsedStoppageSeconds == 5)
    #expect(football.elapsedSecondsNow() == 65)

    var fiveAside = FootballMatchClockSession(
        state: .init(halfLengthSeconds: 60),
        gameType: .football5v5,
        clock: clock
    )
    fiveAside.resetForNewGame()
    #expect(!fiveAside.state.isRunning)
    fiveAside.toggleRunning()
    #expect(fiveAside.state.isRunning)
    let rejectedStoppage = fiveAside.addStoppageSeconds(15)
    #expect(!rejectedStoppage)
}

@Test func football31ClampsPeriodsAndRestrictsExtraTimeToElevenAside() {
    let clock = TestFootballClock()
    var football = FootballMatchClockSession(
        state: .init(stage: 2, halfLengthSeconds: 60, elapsedSeconds: 60),
        gameType: .football,
        clock: clock
    )
    #expect(football.periodCompleted)
    let enteredExtraTime = football.enterExtraTime()
    #expect(enteredExtraTime)
    #expect(football.state.stage == 3)
    #expect(football.state.isRunning)

    var fiveAside = FootballMatchClockSession(
        state: .init(stage: 2, halfLengthSeconds: 60, elapsedSeconds: 60),
        gameType: .football5v5,
        clock: clock
    )
    let rejectedExtraTime = fiveAside.enterExtraTime()
    #expect(!rejectedExtraTime)
    #expect(fiveAside.state.stage == 2)
}

@Test func officialBreakStatePersistsWithAfterActionInsideMatchSnapshots() throws {
    var breaks = OfficialBreakSession()
    breaks.begin(
        sport: .tennis,
        kind: .setBreak,
        durationSeconds: 120,
        afterAction: .advanceAndExchange,
        nowMilliseconds: 10_000
    )

    let rallyReducer = RallyMatchReducer()
    var rally = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: .badminton())
    rally = rallyReducer.reduce(
        state: rally,
        intent: .setOfficialBreakState(breaks.state),
        at: 10_000
    ).state
    let restoredRally = try JSONDecoder().decode(
        RallyMatchState.self,
        from: JSONEncoder().encode(rally)
    )
    #expect(restoredRally.officialBreakState?.afterAction == .advanceAndExchange)
    #expect(restoredRally.officialBreakState?.remainingSeconds == 120)

    let tennisReducer = TennisMatchReducer()
    var tennis = TennisMatchState(leftName: "A", rightName: "B")
    tennis = tennisReducer.reduce(
        state: tennis,
        intent: .setOfficialBreakState(breaks.state),
        at: 10_000
    ).state
    let restoredTennis = try JSONDecoder().decode(
        TennisMatchState.self,
        from: JSONEncoder().encode(tennis)
    )
    #expect(restoredTennis.officialBreakState == breaks.state)
}

@Test func officialBreakSubsecondRefreshDoesNotStretchDuration() {
    #expect(Set(OfficialBreakSport.allCases) == Set([
        .badminton, .pingpong, .tennis, .pickleball,
        .squash, .shuttlecock, .softTennis, .padel
    ]))
    var breaks = OfficialBreakSession()
    breaks.begin(
        sport: .squash,
        kind: .gameBreak,
        durationSeconds: 5,
        nowMilliseconds: 1_000
    )
    _ = breaks.tick(nowMilliseconds: 1_500)
    #expect(breaks.state?.remainingSeconds == 5)
    _ = breaks.tick(nowMilliseconds: 2_000)
    #expect(breaks.state?.remainingSeconds == 4)
}

@Test func officialBreak31WarningCuesOnlyEmitNearCrossedThresholds() {
    #expect(officialBreakCuesCrossed(
        sport: .badminton,
        previousRemainingMilliseconds: 20_500,
        currentRemainingMilliseconds: 19_900
    ) == [.twentySeconds])
    #expect(officialBreakCuesCrossed(
        sport: .badminton,
        previousRemainingMilliseconds: 50_000,
        currentRemainingMilliseconds: 10_000
    ).isEmpty)
    #expect(officialBreakCuesCrossed(
        sport: .squash,
        previousRemainingMilliseconds: 45_500,
        currentRemainingMilliseconds: 44_900
    ) == [.halfTime])
    #expect(officialBreakCuesCrossed(
        sport: .squash,
        previousRemainingMilliseconds: 15_500,
        currentRemainingMilliseconds: 14_900
    ) == [.fifteenSeconds])
    #expect(officialBreakCuesCrossed(
        sport: .tennis,
        previousRemainingMilliseconds: 30_500,
        currentRemainingMilliseconds: 29_900
    ) == [.time])
    #expect(officialBreakCuesCrossed(
        sport: .pingpong,
        previousRemainingMilliseconds: 20_500,
        currentRemainingMilliseconds: 19_900
    ).isEmpty)
}

@Test func officialBreakKindMigratesPre31SnapshotNames() throws {
    let decoder = JSONDecoder()
    #expect(try decoder.decode(OfficialBreakKind.self, from: Data("\"mid_set\"".utf8)) == .midGame)
    #expect(try decoder.decode(OfficialBreakKind.self, from: Data("\"between_sets\"".utf8)) == .gameBreak)
    #expect(try decoder.decode(OfficialBreakKind.self, from: Data("\"medical_timeout\"".utf8)) == .medical)
}

@Test func pingPongAdministrativeRulesMatchAndroid31Limits() {
    let reducer = RallyMatchReducer()
    var state = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: .pingPong())
    state = reducer.reduce(state: state, intent: .pingPongAdministrativeAction(type: .timeout, side: .left), at: 1).state
    #expect(!reducer.reduce(state: state, intent: .pingPongAdministrativeAction(type: .timeout, side: .left), at: 2).accepted)
    state = reducer.reduce(state: state, intent: .pingPongAdministrativeAction(type: .yellowCard, side: .left), at: 3).state
    let repeatedYellow = reducer.reduce(
        state: state,
        intent: .pingPongAdministrativeAction(type: .yellowCard, side: .left),
        at: 4
    )
    #expect(repeatedYellow.accepted)
    state = repeatedYellow.state
    state = reducer.reduce(state: state, intent: .pingPongAdministrativeAction(type: .redCard, side: .left), at: 5).state
    #expect(state.pingPongAdministrativeStatus(for: .left).hasYellowCard)
    state = reducer.reduce(state: state, intent: .pingPongAdministrativeAction(type: .redCard, side: .left), at: 6).state
    #expect(!reducer.reduce(state: state, intent: .pingPongAdministrativeAction(type: .redCard, side: .left), at: 7).accepted)
    #expect(state.pingPongAdministrativeStatus(for: .left).redCardCount == 2)
}
