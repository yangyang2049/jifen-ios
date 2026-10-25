import Foundation
import Testing
@testable import ScoreCore
import SessionCore

@Suite("Nine-ball 14710 transfers")
struct NineBall14710Tests {
    private struct Fixture: Decodable {
        let id: String
        let count: Int
        let kind: NineBallChaseKind
        let actor: Int
        let payer: Int?
        let continuePlayer: Int?
        let allPay: Bool?
        let retain: Bool?
        let scores: [Int]
        let nextBreaker: Int
        let round: Int
        let shooter: Int?
    }

    @Test func commonPayoutAndRotationFixtures() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let path = root.appendingPathComponent("docs/contracts/nine-ball-14710-v2-fixtures.json")
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: path))
        #expect(fixtures.count == 20)
        for fixture in fixtures {
            let state = NineBallChaseState.initial(
                config: .init(smallGoldAllPay: fixture.allPay ?? false, goldRetainsBreak: fixture.retain ?? true),
                playerCount: fixture.count
            )
            let result = NineBallChaseReducer().reduce(
                state: state,
                intent: .chaseTransfer(player: fixture.actor, kind: fixture.kind, payer: fixture.payer, continuePlayer: fixture.continuePlayer),
                at: 1
            )
            #expect(result.accepted, "\(fixture.id)")
            #expect(result.state.playerPoints == fixture.scores, "\(fixture.id)")
            #expect(result.state.playerPoints.reduce(0, +) == 0, "\(fixture.id)")
            #expect(result.state.breakerPlayer == fixture.nextBreaker, "\(fixture.id)")
            #expect(result.state.roundNumber == fixture.round, "\(fixture.id)")
            #expect(result.state.currentShooter == (fixture.kind.endsRack ? fixture.nextBreaker : fixture.shooter), "\(fixture.id)")
            #expect(result.events.count == 1, "\(fixture.id)")
            #expect(result.state.playerCounts[fixture.actor].reduce(0, +) == 1, "\(fixture.id)")
            #expect(result.state.playerCounts[fixture.actor][4] == 0, "Legacy free-ball points must not be counted in v2")
        }
    }

    @Test func oldSnapshotWithoutRuleVersionKeepsOldScoresAndRules() throws {
        var state = NineBallChaseState.initial(config: .init(goldenNine: 8), playerCount: 2, ruleVersion: 1)
        state.playerPoints = [21, -2, 0, 0]
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        for key in ["ruleVersion", "roundNumber", "breakerPlayer", "currentShooter"] { json.removeValue(forKey: key) }
        var config = try #require(json["config"] as? [String: Any])
        config.removeValue(forKey: "smallGoldAllPay")
        config.removeValue(forKey: "goldRetainsBreak")
        json["config"] = config
        let restored = try JSONDecoder().decode(NineBallChaseState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.ruleVersion == 1)
        #expect(restored.playerPoints == [21, -2, 0, 0])
        #expect(restored.playerCounts.allSatisfy { $0.count == 6 })
        #expect(restored.config.goldenNine == 8)
        let foul = NineBallChaseReducer().reduce(state: restored, intent: .chaseEvent(player: 0, kind: .foul), at: 1)
        #expect(foul.accepted)
        #expect(foul.state.playerPoints == [21, -1, 0, 0])
        let gold = NineBallChaseReducer().reduce(state: restored, intent: .chaseEvent(player: 0, kind: .goldenNine), at: 2)
        #expect(gold.state.playerPoints == [29, -2, 0, 0])
    }

    @Test func newAndLegacyIntentsCannotCrossRuleVersions() {
        let reducer = NineBallChaseReducer()
        let fresh = NineBallChaseState.initial()
        let old = NineBallChaseState.initial(ruleVersion: 1)
        #expect(fresh.ruleVersion == 2)
        #expect(fresh.config.goldenNine == 4)
        #expect(fresh.playerCounts.allSatisfy { $0.count == 7 })
        #expect(!reducer.reduce(state: fresh, intent: .chaseEvent(player: 0, kind: .normalWin), at: 1).accepted)
        #expect(!reducer.reduce(state: old, intent: .chaseTransfer(player: 0, kind: .normalWin, payer: nil, continuePlayer: nil), at: 1).accepted)
        #expect(!reducer.reduce(state: old, intent: .setBreaker(player: 1), at: 1).accepted)
        #expect(!reducer.reduce(state: fresh, intent: .chaseTransfer(player: 0, kind: .ballInHand, payer: nil, continuePlayer: nil), at: 1).accepted)
        var future = fresh
        future.ruleVersion = 4
        #expect(!reducer.reduce(state: future, intent: .finishMatch, at: 1).accepted)
    }

    @Test func invalidTransfersLeaveStateUnchanged() {
        let state = NineBallChaseState.initial(playerCount: 3)
        let intents: [NineBallChaseIntent] = [
            .chaseTransfer(player: 1, kind: .bigGold, payer: nil, continuePlayer: nil),
            .chaseTransfer(player: 0, kind: .smallGold, payer: nil, continuePlayer: nil),
            .chaseTransfer(player: 1, kind: .normalWin, payer: 1, continuePlayer: nil),
            .chaseTransfer(player: 1, kind: .normalWin, payer: 8, continuePlayer: nil),
            .chaseTransfer(player: 1, kind: .handoff, payer: nil, continuePlayer: nil),
            .chaseTransfer(player: 1, kind: .handoff, payer: nil, continuePlayer: 1),
            .chaseTransfer(player: -1, kind: .goldenNine, payer: nil, continuePlayer: nil)
        ]
        for intent in intents {
            let result = NineBallChaseReducer().reduce(state: state, intent: intent, at: 1)
            #expect(!result.accepted)
            #expect(result.state == state)
            #expect(result.events.isEmpty)
        }
    }

    @Test func correctedSmallGoldPersistsPayerAndRackContext() throws {
        let result = NineBallChaseReducer().reduce(
            state: .initial(playerCount: 4),
            intent: .chaseTransfer(player: 2, kind: .smallGold, payer: 3, continuePlayer: nil), at: 1
        )
        guard case let .chaseTransferred(player, kind, deltas, payer, continuing, round, breaker, next) = try #require(result.events.first) else {
            Issue.record("Missing transfer event")
            return
        }
        #expect(player == 2 && kind == .smallGold && payer == 3 && continuing == nil)
        #expect(deltas == [0, 0, 7, -7] && round == 1 && breaker == 3 && next == 3)
    }

    @Test func sessionUndoRestoresEveryoneAndWholeRackContext() async {
        let state = NineBallChaseState.initial(playerCount: 4, playerNames: ["A", "B", "C", "D"])
        let seed = ScoreSession<NineBallChaseState, NineBallChaseEvent>(
            gameType: .nineBall, ruleFamily: .s2, reducerType: "nine_ball/v1", state: state
        )
        let core = ScoreSessionCore(seedSession: seed, reducer: NineBallChaseReducer())
        _ = await core.dispatch(actorId: "phone", intent: .chaseTransfer(player: 0, kind: .bigGold, payer: nil, continuePlayer: nil), at: 1)
        let scored = await core.snapshot().state
        #expect(scored.playerPoints == [30, -10, -10, -10])
        #expect(scored.roundNumber == 2)
        #expect(await core.undo(actorId: "phone"))
        #expect(await core.snapshot().state == state)
        #expect(!(await core.undo(actorId: "phone")))
    }
}
