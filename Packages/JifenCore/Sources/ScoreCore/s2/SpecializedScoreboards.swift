import Foundation

// MARK: - Eight ball (race-to racks)

public struct EightBallState: Codable, Equatable, Sendable {
    public var leftPoints: Int
    public var rightPoints: Int
    public var leftCounts: [Int]
    public var rightCounts: [Int]
    public var targetPoints: Int
    public var finished: Bool
    public var handicapRacks: Int
    public var handicapBeneficiary: MatchSide?
    public var sidesSwapped: Bool

    public static func initial(targetPoints: Int = 9, handicapRacks: Int = 0, handicapBeneficiary: MatchSide? = nil) -> Self {
        let target = min(99, max(1, targetPoints))
        let handicap = min(max(0, handicapRacks), max(0, target - 1))
        return .init(
            leftPoints: handicapBeneficiary == .left ? handicap : 0,
            rightPoints: handicapBeneficiary == .right ? handicap : 0,
            leftCounts: Array(repeating: 0, count: 15),
            rightCounts: Array(repeating: 0, count: 15),
            targetPoints: target,
            finished: false,
            handicapRacks: handicap,
            handicapBeneficiary: handicapBeneficiary,
            sidesSwapped: false
        )
    }
}

public enum EightBallIntent: Codable, Sendable {
    case addRack(MatchSide)
    case applyPot(side: MatchSide, ball: Int)
    case adminAdjust(left: Int, right: Int)
    case exchangeSides
    case reset
}

public enum EightBallEvent: Codable, Equatable, Sendable {
    case rackWon(MatchSide)
    case ballPotted(side: MatchSide, ball: Int)
    case adminAdjusted
    case sidesExchanged
    case reset
}

public struct EightBallReducer: DomainReducer {
    public init() {}

    public func reduce(state: EightBallState, intent: EightBallIntent, at epochMilliseconds: Int64) -> ReduceResult<EightBallState, EightBallEvent> {
        if state.finished {
            switch intent {
            case .adminAdjust, .reset: break
            default: return .rejected(state: state, reason: "Already finished")
            }
        }
        var next = state
        switch intent {
        case .addRack(let side):
            if side == .left { next.leftPoints += 1 } else { next.rightPoints += 1 }
            next.finished = next.leftPoints >= next.targetPoints || next.rightPoints >= next.targetPoints
            return .init(state: next, events: [.rackWon(side)])
        case .applyPot(let side, let ball):
            guard (1 ... 15).contains(ball) else { return .rejected(state: state, reason: "Invalid ball number") }
            if side == .left {
                next.leftCounts[ball - 1] += 1
                next.leftPoints += 1
            } else {
                next.rightCounts[ball - 1] += 1
                next.rightPoints += 1
            }
            next.finished = next.leftPoints >= next.targetPoints || next.rightPoints >= next.targetPoints
            return .init(state: next, events: [.ballPotted(side: side, ball: ball)])
        case .adminAdjust(let left, let right):
            let maximum = max(0, state.targetPoints - 1)
            let leftMinimum = state.handicapBeneficiary == .left ? state.handicapRacks : 0
            let rightMinimum = state.handicapBeneficiary == .right ? state.handicapRacks : 0
            next.leftPoints = min(maximum, max(leftMinimum, left))
            next.rightPoints = min(maximum, max(rightMinimum, right))
            next.finished = false
            return .init(state: next, events: [.adminAdjusted])
        case .exchangeSides:
            next.sidesSwapped.toggle()
            return .init(state: next, events: [.sidesExchanged])
        case .reset:
            return .init(state: .initial(targetPoints: state.targetPoints, handicapRacks: state.handicapRacks, handicapBeneficiary: state.handicapBeneficiary), events: [.reset])
        }
    }
}

// MARK: - Nine-ball chase points (2-4 players)

public struct NineBallChaseConfig: Codable, Equatable, Sendable {
    public var bigGold = 10
    public var smallGold = 7
    public var goldenNine = 8
    public var normalWin = 4
    public var ballInHand = 1
    public var foul = 1

    public init(bigGold: Int = 10, smallGold: Int = 7, goldenNine: Int = 8, normalWin: Int = 4, ballInHand: Int = 1, foul: Int = 1) {
        self.bigGold = bigGold
        self.smallGold = smallGold
        self.goldenNine = goldenNine
        self.normalWin = normalWin
        self.ballInHand = ballInHand
        self.foul = foul
    }
}

public enum NineBallChaseKind: String, Codable, CaseIterable, Equatable, Sendable {
    case bigGold = "big_gold"
    case smallGold = "small_gold"
    case goldenNine = "golden_nine"
    case normalWin = "normal_win"
    case ballInHand = "ball_in_hand"
    case foul
}

public struct NineBallChaseState: Codable, Equatable, Sendable {
    public var playerCount: Int
    public var playerPoints: [Int]
    public var playerCounts: [[Int]]
    public var config: NineBallChaseConfig
    public var finished: Bool
    /// Display names for up to 4 players. Empty slots use UI defaults.
    public var playerNames: [String]

    public init(
        playerCount: Int,
        playerPoints: [Int],
        playerCounts: [[Int]],
        config: NineBallChaseConfig,
        finished: Bool,
        playerNames: [String] = []
    ) {
        self.playerCount = min(4, max(2, playerCount))
        self.playerPoints = Array((playerPoints + Array(repeating: 0, count: 4)).prefix(4))
        self.playerCounts = (0..<4).map { index in
            let source = playerCounts[safe: index] ?? []
            return Array((source + Array(repeating: 0, count: NineBallChaseKind.allCases.count)).prefix(NineBallChaseKind.allCases.count))
        }
        self.config = config
        self.finished = finished
        self.playerNames = Self.normalizedNames(playerNames)
    }

    public static func initial(
        config: NineBallChaseConfig = .init(),
        playerCount: Int = 2,
        playerNames: [String] = []
    ) -> Self {
        .init(
            playerCount: playerCount,
            playerPoints: Array(repeating: 0, count: 4),
            playerCounts: Array(repeating: Array(repeating: 0, count: NineBallChaseKind.allCases.count), count: 4),
            config: config,
            finished: false,
            playerNames: playerNames
        )
    }

    public var leftPoints: Int { playerPoints[safe: 0] ?? 0 }
    public var rightPoints: Int { playerPoints[safe: 1] ?? 0 }

    public func resolvedName(at index: Int, fallback: String? = nil) -> String {
        let trimmed = playerNames[safe: index]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        if let fallback, !fallback.isEmpty { return fallback }
        return "P\(index + 1)"
    }

    private static func normalizedNames(_ names: [String]) -> [String] {
        (0..<4).map { index in
            guard names.indices.contains(index) else { return "" }
            return names[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case playerCount, playerPoints, playerCounts, config, finished, playerNames
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            playerCount: try container.decode(Int.self, forKey: .playerCount),
            playerPoints: try container.decode([Int].self, forKey: .playerPoints),
            playerCounts: try container.decode([[Int]].self, forKey: .playerCounts),
            config: try container.decode(NineBallChaseConfig.self, forKey: .config),
            finished: try container.decode(Bool.self, forKey: .finished),
            playerNames: try container.decodeIfPresent([String].self, forKey: .playerNames) ?? []
        )
    }
}

public enum NineBallChaseIntent: Codable, Sendable {
    case chaseEvent(player: Int, kind: NineBallChaseKind)
    case deltaTotal(player: Int, delta: Int)
    case adminSetTotals(left: Int, right: Int)
    case resetScores
}

public enum NineBallChaseEvent: Codable, Equatable, Sendable {
    case chaseApplied(player: Int, scorePlayer: Int, kind: NineBallChaseKind, delta: Int)
    case totalsAdjusted
}

public struct NineBallChaseReducer: DomainReducer {
    public init() {}

    public func reduce(state: NineBallChaseState, intent: NineBallChaseIntent, at epochMilliseconds: Int64) -> ReduceResult<NineBallChaseState, NineBallChaseEvent> {
        if state.finished {
            switch intent {
            case .adminSetTotals, .resetScores: break
            default: return .rejected(state: state, reason: "Already finished")
            }
        }
        var next = normalized(state)
        switch intent {
        case .resetScores:
            next.playerPoints = Array(repeating: 0, count: 4)
            next.playerCounts = Array(repeating: Array(repeating: 0, count: 6), count: 4)
            next.finished = false
            return .init(state: next, events: [.totalsAdjusted])
        case .chaseEvent(let player, let kind):
            guard (0 ..< next.playerCount).contains(player) else { return .rejected(state: state, reason: "Invalid player") }
            let configured = delta(for: kind, config: next.config)
            guard configured != 0 else { return .rejected(state: state, reason: "Invalid point value") }
            let scorePlayer = kind == .foul && next.playerCount == 2 ? (player == 0 ? 1 : 0) : player
            let scoreDelta = kind == .foul && next.playerCount > 2 ? -configured : configured
            next.playerPoints[scorePlayer] += scoreDelta
            next.playerCounts[player][NineBallChaseKind.allCases.firstIndex(of: kind)!] += 1
            return .init(state: next, events: [.chaseApplied(player: player, scorePlayer: scorePlayer, kind: kind, delta: scoreDelta)])
        case .deltaTotal(let player, let delta):
            guard (0 ..< next.playerCount).contains(player) else { return .rejected(state: state, reason: "Invalid player") }
            next.playerPoints[player] += delta
            return .init(state: next, events: [.totalsAdjusted])
        case .adminSetTotals(let left, let right):
            next.playerPoints[0] = max(0, left)
            next.playerPoints[1] = max(0, right)
            return .init(state: next, events: [.totalsAdjusted])
        }
    }

    private func normalized(_ state: NineBallChaseState) -> NineBallChaseState {
        var value = state
        value.playerCount = min(4, max(2, value.playerCount))
        value.playerPoints = Array((value.playerPoints + Array(repeating: 0, count: 4)).prefix(4))
        value.playerCounts = (0 ..< 4).map { player in
            let source = value.playerCounts[safe: player] ?? []
            return Array((source + Array(repeating: 0, count: 6)).prefix(6))
        }
        value.playerNames = Array((value.playerNames + Array(repeating: "", count: 4)).prefix(4)).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    private func delta(for kind: NineBallChaseKind, config: NineBallChaseConfig) -> Int {
        switch kind {
        case .bigGold: config.bigGold
        case .smallGold: config.smallGold
        case .goldenNine: config.goldenNine
        case .normalWin: config.normalWin
        case .ballInHand: config.ballInHand
        case .foul: config.foul
        }
    }
}

// MARK: - Shengji tier state machine

public struct ShengjiTierState: Codable, Equatable, Sendable {
    public var leftIndex: Int
    public var rightIndex: Int
    public var maxTierIndex: Int
    public var finished: Bool
    public var dealer: MatchSide?

    public init(leftIndex: Int = 0, rightIndex: Int = 0, maxTierIndex: Int = 12, finished: Bool = false, dealer: MatchSide? = nil) {
        self.leftIndex = leftIndex
        self.rightIndex = rightIndex
        self.maxTierIndex = maxTierIndex
        self.finished = finished
        self.dealer = dealer
    }
}

public enum ShengjiTierIntent: Codable, Sendable {
    case addLevels(side: MatchSide, delta: Int)
    case subtractLevels(side: MatchSide, delta: Int)
    case claimDealer(MatchSide)
    case resolveRound(winner: MatchSide, delta: Int)
}

public enum ShengjiTierEvent: Codable, Equatable, Sendable {
    case tierAdjusted(add: Bool, side: MatchSide, delta: Int, left: Int, right: Int)
    case dealerClaimed(side: MatchSide, initial: Bool)
}

public struct ShengjiTierReducer: DomainReducer {
    public init() {}

    public func reduce(state: ShengjiTierState, intent: ShengjiTierIntent, at epochMilliseconds: Int64) -> ReduceResult<ShengjiTierState, ShengjiTierEvent> {
        var current = state
        let cap = max(0, current.maxTierIndex)
        current.finished = current.finished || current.leftIndex >= cap || current.rightIndex >= cap
        if current.finished {
            if case .subtractLevels = intent {} else { return .rejected(state: current, reason: "Already finished") }
        }
        switch intent {
        case .claimDealer(let side):
            guard current.dealer == nil else { return .rejected(state: current, reason: "Dealer already selected") }
            current.dealer = side
            return .init(state: current, events: [.dealerClaimed(side: side, initial: true)])
        case .addLevels(let side, let delta):
            return adjust(state: current, side: side, delta: delta, add: true, cap: cap)
        case .subtractLevels(let side, let delta):
            return adjust(state: current, side: side, delta: delta, add: false, cap: cap)
        case .resolveRound(let winner, let delta):
            guard let dealer = current.dealer else { return .rejected(state: current, reason: "Dealer not selected") }
            guard (0 ... 3).contains(delta), !(delta == 0 && winner == dealer) else { return .rejected(state: current, reason: "Invalid delta") }
            let previousDealer = dealer
            if delta > 0 {
                let result = adjust(state: current, side: winner, delta: delta, add: true, cap: cap)
                current = result.state
            }
            current.dealer = winner == previousDealer ? previousDealer : winner
            var events: [ShengjiTierEvent] = []
            if delta > 0 { events.append(.tierAdjusted(add: true, side: winner, delta: delta, left: current.leftIndex, right: current.rightIndex)) }
            if current.dealer != previousDealer { events.append(.dealerClaimed(side: current.dealer!, initial: false)) }
            return .init(state: current, events: events)
        }
    }

    private func adjust(state: ShengjiTierState, side: MatchSide, delta: Int, add: Bool, cap: Int) -> ReduceResult<ShengjiTierState, ShengjiTierEvent> {
        guard delta > 0 else { return .rejected(state: state, reason: "Invalid delta") }
        var next = state
        if side == .left {
            next.leftIndex = add ? min(cap, next.leftIndex + delta) : max(0, next.leftIndex - delta)
        } else {
            next.rightIndex = add ? min(cap, next.rightIndex + delta) : max(0, next.rightIndex - delta)
        }
        next.finished = add && (next.leftIndex >= cap || next.rightIndex >= cap)
        return .init(state: next, events: [.tierAdjusted(add: add, side: side, delta: delta, left: next.leftIndex, right: next.rightIndex)])
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
