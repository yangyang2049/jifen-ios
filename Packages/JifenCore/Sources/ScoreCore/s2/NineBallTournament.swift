import Foundation

extension NineBallChaseReducer {
    /// One rack result (including the third foul) is one session/undo operation.
    func tournament(state: NineBallChaseState, player: Int, kind: NineBallChaseKind) -> ReduceResult<NineBallChaseState, NineBallChaseEvent> {
        guard state.isTournament, (0..<2).contains(player), state.scoringKinds.contains(kind),
              kind != .bigGold || player == state.breakerPlayer else {
            return .rejected(state: state, reason: "Invalid tournament operation")
        }
        var next = state
        let third = kind == .foul && state.rackFouls[player] == 2
        let receiver = kind == .foul ? 1 - player : player
        let points: Int
        switch kind {
        case .bigGold: points = state.config.bigGold
        case .smallGold: points = state.config.smallGold
        case .normalWin: points = state.config.normalWin
        case .foul: points = third ? state.config.thirdFoul : state.config.foul
        default: return .rejected(state: state, reason: "Invalid tournament category")
        }
        next.playerPoints[receiver] += points
        if let index = NineBallChaseKind.allCases.firstIndex(of: kind) { next.playerCounts[player][index] += 1 }
        if kind == .foul { next.rackFouls[player] += 1 }
        if kind.endsRack || third {
            next.roundNumber += 1
            next.breakerPlayer = state.config.breakRule == .winner ? receiver : 1 - state.breakerPlayer
            next.currentShooter = next.breakerPlayer
            next.rackFouls = Array(repeating: 0, count: 4)
            let difference = abs(next.playerPoints[0] - next.playerPoints[1])
            let remaining = max(0, state.config.totalRacks - state.roundNumber)
            next.finished = state.roundNumber >= state.config.totalRacks
                ? difference != 0 : difference > remaining * state.config.maximumRackSwing
        } else {
            next.currentShooter = receiver
        }
        var deltas = Array(repeating: 0, count: 4)
        deltas[receiver] = points
        return .init(state: next, events: [.chaseTransferred(
            player: player, kind: kind, deltas: deltas, payer: nil,
            continuePlayer: kind == .foul ? receiver : nil, roundBefore: state.roundNumber,
            breakerBefore: state.breakerPlayer, nextBreaker: next.breakerPlayer
        )])
    }
}
