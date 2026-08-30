import Foundation

public struct DoudizhuScoreState: Codable, Equatable, Sendable {
    public var scores: [Int]

    public init(scores: [Int] = [0, 0, 0]) {
        self.scores = Array((scores + [0, 0, 0]).prefix(3))
    }
}

public enum DoudizhuScoreIntent: Codable, Equatable, Sendable {
    case adjustScore(playerIndex: Int, delta: Int)
    case confirmRound(winners: [Bool], baseScore: Int, multiplierPower: Int)
    case resetScores
}

public enum DoudizhuScoreEvent: Codable, Equatable, Sendable {
    case scoreAdjusted(playerIndex: Int, delta: Int, scores: [Int])
    case roundConfirmed(
        winners: [Int],
        losers: [Int],
        landlord: Int,
        farmers: [Int],
        scoreChange: Int,
        scores: [Int]
    )
    case scoresReset
}

/// Android 3.1 S4 parity reducer. The UI projects its three columns from this
/// accepted state and records the typed event, rather than duplicating the
/// settlement formula in the view.
public struct DoudizhuScoreReducer: DomainReducer {
    public init() {}

    public func reduce(
        state: DoudizhuScoreState,
        intent: DoudizhuScoreIntent,
        at epochMilliseconds: Int64
    ) -> ReduceResult<DoudizhuScoreState, DoudizhuScoreEvent> {
        switch intent {
        case .adjustScore(let playerIndex, let delta):
            guard state.scores.indices.contains(playerIndex) else {
                return .rejected(state: state, reason: "Invalid player index")
            }
            guard delta != 0 else {
                return .rejected(state: state, reason: "Score delta cannot be 0")
            }
            let (score, overflow) = state.scores[playerIndex].addingReportingOverflow(delta)
            guard !overflow else {
                return .rejected(state: state, reason: "Score overflow")
            }
            var next = state
            next.scores[playerIndex] = score
            return .init(
                state: next,
                events: [.scoreAdjusted(playerIndex: playerIndex, delta: delta, scores: next.scores)]
            )

        case .confirmRound(let winners, let baseScore, let multiplierPower):
            guard (1 ... 3).contains(baseScore), (0 ... 5).contains(multiplierPower),
                  let deltas = DoudizhuSettlement.deltas(
                    winners: winners,
                    baseScore: baseScore,
                    multiplierPower: multiplierPower
                  ) else {
                return .rejected(state: state, reason: "Invalid round configuration")
            }
            var next = state
            for index in next.scores.indices {
                let (score, overflow) = next.scores[index].addingReportingOverflow(deltas[index])
                guard !overflow else {
                    return .rejected(state: state, reason: "Score overflow")
                }
                next.scores[index] = score
            }
            let winnerIndexes = winners.indices.filter { winners[$0] }
            let loserIndexes = winners.indices.filter { !winners[$0] }
            let landlord = winnerIndexes.count == 1 ? winnerIndexes[0] : loserIndexes[0]
            let farmers = winnerIndexes.count == 1 ? loserIndexes : winnerIndexes
            let scoreChange = winnerIndexes.count == 1
                ? deltas[landlord]
                : deltas[winnerIndexes[0]]
            return .init(
                state: next,
                events: [.roundConfirmed(
                    winners: winnerIndexes,
                    losers: loserIndexes,
                    landlord: landlord,
                    farmers: farmers,
                    scoreChange: scoreChange,
                    scores: next.scores
                )]
            )

        case .resetScores:
            return .init(state: .init(), events: [.scoresReset])
        }
    }
}
