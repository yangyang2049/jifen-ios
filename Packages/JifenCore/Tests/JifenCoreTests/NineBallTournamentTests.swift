import Foundation
import Testing
import ScoreCore
import SessionCore

@Suite("Nine-ball rule presets v3")
struct NineBallTournamentTests {
    let reducer = NineBallChaseReducer()
    func initial(_ config: NineBallChaseConfig = .init(ruleFamily: .tournament)) -> NineBallChaseState {
        .initial(config: config, playerCount: 4, ruleVersion: 3)
    }
    func apply(_ state: NineBallChaseState, _ kind: NineBallChaseKind, _ player: Int = 0) -> NineBallChaseState {
        reducer.reduce(state: state, intent: .tournamentEvent(player: player, kind: kind), at: 1).state
    }
    @Test func singlesAndIntentIsolation() {
        let state = initial()
        #expect(state.playerCount == 2)
        #expect(state.scoringKinds == [.bigGold, .smallGold, .normalWin, .foul])
        #expect(apply(state, .smallGold).playerPoints == [7, 0, 0, 0])
        #expect(!reducer.reduce(state: state, intent: .chaseTransfer(player: 0, kind: .normalWin, payer: nil, continuePlayer: nil), at: 1).accepted)
        for kind in [NineBallChaseKind.goldenNine, .handoff, .ballInHand] {
            #expect(!reducer.reduce(state: state, intent: .tournamentEvent(player: 0, kind: kind), at: 1).accepted)
        }
        #expect(!reducer.reduce(state: .initial(), intent: .tournamentEvent(player: 0, kind: .normalWin), at: 1).accepted)
    }
    @Test func rackFoulsArePerPlayerAndNotConsecutive() {
        var state = initial()
        state = apply(state, .foul)
        state = apply(state, .foul, 1)
        state = apply(state, .foul)
        #expect(state.rackFouls == [2, 1, 0, 0])
        let result = reducer.reduce(state: state, intent: .tournamentEvent(player: 0, kind: .foul), at: 1)
        #expect(result.events.count == 1)
        #expect(result.state.playerPoints == [1, 4, 0, 0])
        #expect(result.state.roundNumber == 2 && result.state.breakerPlayer == 1)
        #expect(result.state.rackFouls == [0, 0, 0, 0])
        #expect(result.state.playerCounts[0][5] == 3)
    }
    @Test func normalRackClearsFoulsAndAlternateBreaks() {
        var state = initial(.init(ruleFamily: .tournament, breakRule: .alternate))
        state = apply(state, .foul)
        state = apply(state, .smallGold)
        #expect(state.playerPoints == [7, 1, 0, 0])
        #expect(state.breakerPlayer == 1 && state.rackFouls == [0, 0, 0, 0])
        state = apply(state, .normalWin)
        #expect(state.breakerPlayer == 0)
    }
    @Test func extraRacksUntilUntiedAndCustomPoints() {
        var state = initial(.init(normalWin: 3, ruleFamily: .tournament, totalRacks: 2))
        state = apply(state, .normalWin)
        state = apply(state, .normalWin, 1)
        #expect(state.roundNumber == 3 && !state.finished)
        state = apply(state, .normalWin)
        #expect(state.finished && state.playerPoints == [6, 3, 0, 0])
    }
    @Test func earlyFinishCountsFoulsAndLargestCustomAward() {
        let config = NineBallChaseConfig(bigGold: 3, smallGold: 20, normalWin: 4, foul: 2, ruleFamily: .tournament, thirdFoul: 30, totalRacks: 2)
        #expect(config.maximumRackSwing == 34)
        var state = initial(config)
        state.playerPoints[0] = 30
        state = apply(state, .normalWin)
        #expect(!state.finished) // exactly 34 can still be tied
        state = initial(config); state.playerPoints[0] = 31
        state = apply(state, .normalWin)
        #expect(state.finished)
        // Old demo's remaining * bigGold would incorrectly stop this rack.
        state = initial(config); state.playerPoints[0] = 5
        #expect(!apply(state, .normalWin).finished)
    }
    @Test func negativeTournamentEditsRejectAtomicallyAndSnapshotRoundTrips() throws {
        var state = apply(initial(), .foul)
        let bad = reducer.reduce(state: state, intent: .adminCorrect(playerNames: ["Changed"], playerPoints: [-1, 4]), at: 1)
        #expect(!bad.accepted && bad.state == state)
        #expect(!reducer.reduce(state: state, intent: .adminSetTotals(left: -1, right: 2), at: 1).accepted)
        #expect(!reducer.reduce(state: state, intent: .deltaTotal(player: 0, delta: -1), at: 1).accepted)
        state = apply(state, .foul)
        #expect(try JSONDecoder().decode(NineBallChaseState.self, from: JSONEncoder().encode(state)) == state)
    }
    @Test func folkSchemesAndDisabledHandoff() {
        for scheme in NineBallPointScheme.allCases {
            var config = NineBallChaseConfig.preset(scheme); config.handoffEnabled = false
            let state = initial(config)
            #expect(!state.scoringKinds.contains(.handoff))
            #expect(!reducer.reduce(state: state, intent: .chaseTransfer(player: 0, kind: .handoff, payer: nil, continuePlayer: 1), at: 1).accepted)
            let result = reducer.reduce(state: state, intent: .chaseTransfer(player: 0, kind: .goldenNine, payer: nil, continuePlayer: nil), at: 1)
            #expect(result.state.playerPoints == [3 * config.goldenNine, -config.goldenNine, -config.goldenNine, -config.goldenNine])
        }
        let old = NineBallChaseState.initial(config: .init(handoffEnabled: false))
        #expect(reducer.reduce(state: old, intent: .chaseTransfer(player: 0, kind: .handoff, payer: nil, continuePlayer: 1), at: 1).accepted)
    }
    @Test func thirdFoulUndoRestoresCompleteState() async {
        let before = apply(apply(initial(), .foul), .foul)
        let seed = ScoreSession<NineBallChaseState, NineBallChaseEvent>(gameType: .nineBall, ruleFamily: .s2, reducerType: "nine_ball/v3", state: before)
        let core = ScoreSessionCore(seedSession: seed, reducer: reducer)
        _ = await core.dispatch(actorId: "phone", intent: .tournamentEvent(player: 0, kind: .foul), at: 1)
        #expect(await core.snapshot().state.roundNumber == 2)
        #expect(await core.undo(actorId: "phone"))
        #expect(await core.snapshot().state == before)
        #expect(!(await core.undo(actorId: "phone")))
    }
    @Test func resetRestoresConfiguredOpeningBreakerAfterScoringAndPersistence() throws {
        for family in [NineBallRuleFamily.folk, .tournament] {
            let initial = NineBallChaseState.initial(config: .init(ruleFamily: family), playerCount: 3,
                ruleVersion: 3, breakerPlayer: 1)
            var played = reducer.reduce(state: initial, intent: .setBreaker(player: 0), at: 1).state
            played = family == .folk
                ? reducer.reduce(state: played, intent: .chaseTransfer(player: 0, kind: .normalWin, payer: 1, continuePlayer: nil), at: 2).state
                : apply(played, .normalWin)
            let restored = try JSONDecoder().decode(NineBallChaseState.self, from: JSONEncoder().encode(played))
            let reset = reducer.reduce(state: restored, intent: .resetScores, at: 3).state
            #expect(reset.initialBreakerPlayer == 1 && reset.breakerPlayer == 1)
            #expect(reset.roundNumber == 1 && reset.playerPoints == [0, 0, 0, 0])
            #expect(reset.rackFouls == [0, 0, 0, 0])
        }
    }
    @Test func olderSnapshotWithoutOpeningBreakerKeepsCompatibleResetDefault() throws {
        let played = NineBallChaseState.initial(ruleVersion: 3, breakerPlayer: 1)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(played)) as? [String: Any])
        json.removeValue(forKey: "initialBreakerPlayer")
        let restored = try JSONDecoder().decode(NineBallChaseState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.breakerPlayer == 1 && restored.initialBreakerPlayer == 0)
        #expect(reducer.reduce(state: restored, intent: .resetScores, at: 1).state.breakerPlayer == 0)
    }

}
