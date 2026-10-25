import Foundation

extension NineBallChaseReducer {
    /// Computes one complete transfer. SessionCore owns the single atomic undo frame.
    func transfer(
        state: NineBallChaseState,
        player: Int,
        kind: NineBallChaseKind,
        payer: Int?,
        continuePlayer: Int?
    ) -> ReduceResult<NineBallChaseState, NineBallChaseEvent> {
        let players = 0..<state.playerCount
        guard players.contains(player) else { return .rejected(state: state, reason: "Invalid player") }
        if let payer, !players.contains(payer) { return .rejected(state: state, reason: "Invalid payer") }
        if let continuePlayer, !players.contains(continuePlayer) { return .rejected(state: state, reason: "Invalid continuing player") }
        guard kind != .ballInHand else { return .rejected(state: state, reason: "Ball in hand is included in a foul; use handoff for a non-scoring operation") }

        var next = state
        var deltas = Array(repeating: 0, count: 4)
        var resolvedPayer: Int?
        var receiver: Int?
        var breakerBefore = state.breakerPlayer
        func pay(_ from: Int, _ to: Int, _ points: Int) {
            deltas[from] -= points
            deltas[to] += points
        }
        func allOthersPay(_ points: Int) {
            for opponent in players where opponent != player { pay(opponent, player, points) }
        }

        switch kind {
        case .bigGold:
            guard player == state.breakerPlayer else { return .rejected(state: state, reason: "Big gold requires the rack breaker") }
            allOthersPay(state.config.bigGold)
        case .goldenNine:
            allOthersPay(state.config.goldenNine)
        case .smallGold:
            if state.config.smallGoldAllPay {
                allOthersPay(state.config.smallGold)
            } else {
                let payingPlayer = payer ?? state.breakerPlayer
                guard payingPlayer != player else { return .rejected(state: state, reason: "Small gold winner cannot be the rack breaker; correct the breaker") }
                resolvedPayer = payingPlayer
                breakerBefore = payingPlayer
                pay(payingPlayer, player, state.config.smallGold)
            }
        case .normalWin:
            let payingPlayer = payer ?? (player + state.playerCount - 1) % state.playerCount
            guard payingPlayer != player else { return .rejected(state: state, reason: "Winner cannot pay themselves") }
            resolvedPayer = payingPlayer
            pay(payingPlayer, player, state.config.normalWin)
        case .foul:
            resolvedPayer = player
            receiver = (player + 1) % state.playerCount
            pay(player, receiver!, state.config.foul)
        case .handoff:
            guard state.ruleVersion == 2 || state.config.handoffEnabled else { return .rejected(state: state, reason: "Handoff disabled") }
            let continuing = continuePlayer ?? (state.playerCount == 2 ? (player + 1) % 2 : nil)
            guard let continuing, players.contains(continuing), continuing != player else {
                return .rejected(state: state, reason: "Select another player to continue")
            }
            receiver = continuing
        case .ballInHand:
            return .rejected(state: state, reason: "Unsupported legacy event")
        }

        guard deltas.reduce(0, +) == 0 else { return .rejected(state: state, reason: "Unbalanced transfer") }
        for index in players { next.playerPoints[index] += deltas[index] }
        guard let index = NineBallChaseKind.allCases.firstIndex(of: kind) else {
            return .rejected(state: state, reason: "Invalid event kind")
        }
        next.playerCounts[player][index] += 1
        if kind.endsRack {
            let retains = (kind == .bigGold || kind == .goldenNine) && state.config.goldRetainsBreak
            next.breakerPlayer = retains ? player : (player + 1) % state.playerCount
            next.roundNumber += 1
            next.currentShooter = next.breakerPlayer
        } else {
            next.currentShooter = receiver
        }
        return .init(state: next, events: [
            .chaseTransferred(player: player, kind: kind, deltas: deltas, payer: resolvedPayer,
                              continuePlayer: receiver, roundBefore: state.roundNumber,
                              breakerBefore: breakerBefore, nextBreaker: next.breakerPlayer)
        ])
    }
}
