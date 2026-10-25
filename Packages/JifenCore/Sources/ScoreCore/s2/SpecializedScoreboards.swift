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

    private enum CodingKeys: String, CodingKey {
        case leftPoints, rightPoints, leftCounts, rightCounts, targetPoints, finished
        case handicapRacks, handicapBeneficiary, sidesSwapped
    }

    public init(
        leftPoints: Int,
        rightPoints: Int,
        leftCounts: [Int],
        rightCounts: [Int],
        targetPoints: Int,
        finished: Bool,
        handicapRacks: Int,
        handicapBeneficiary: MatchSide?,
        sidesSwapped: Bool = false
    ) {
        self.leftPoints = leftPoints
        self.rightPoints = rightPoints
        self.leftCounts = leftCounts
        self.rightCounts = rightCounts
        self.targetPoints = targetPoints
        self.finished = finished
        self.handicapRacks = handicapRacks
        self.handicapBeneficiary = handicapBeneficiary
        self.sidesSwapped = sidesSwapped
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            leftPoints: try container.decode(Int.self, forKey: .leftPoints),
            rightPoints: try container.decode(Int.self, forKey: .rightPoints),
            leftCounts: try container.decode([Int].self, forKey: .leftCounts),
            rightCounts: try container.decode([Int].self, forKey: .rightCounts),
            targetPoints: try container.decode(Int.self, forKey: .targetPoints),
            finished: try container.decode(Bool.self, forKey: .finished),
            handicapRacks: try container.decodeIfPresent(Int.self, forKey: .handicapRacks) ?? 0,
            handicapBeneficiary: try container.decodeIfPresent(MatchSide.self, forKey: .handicapBeneficiary),
            sidesSwapped: try container.decodeIfPresent(Bool.self, forKey: .sidesSwapped) ?? false
        )
    }

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

    public func canAdjustRacks(side: MatchSide, delta: Int) -> Bool {
        guard delta != 0 else { return false }
        let current = side == .left ? leftPoints : rightPoints
        let minimum = handicapBeneficiary == side ? handicapRacks : 0
        let next = current + delta
        return next >= minimum && next <= max(0, targetPoints - 1)
    }
}

public enum EightBallIntent: Codable, Sendable {
    case addRack(MatchSide)
    case applyPot(side: MatchSide, ball: Int)
    case adminAdjust(left: Int, right: Int)
    case exchangeSides
    case reset
    case finishMatch
}

public enum EightBallEvent: Codable, Equatable, Sendable {
    case rackWon(MatchSide)
    case ballPotted(side: MatchSide, ball: Int)
    case adminAdjusted
    case sidesExchanged
    case reset
    case matchFinished
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
            guard left >= leftMinimum, left <= maximum,
                  right >= rightMinimum, right <= maximum else {
                return .rejected(state: state, reason: "Rack score overflow")
            }
            next.leftPoints = left
            next.rightPoints = right
            next.finished = false
            return .init(state: next, events: [.adminAdjusted])
        case .exchangeSides:
            next.sidesSwapped.toggle()
            return .init(state: next, events: [.sidesExchanged])
        case .reset:
            return .init(state: .initial(targetPoints: state.targetPoints, handicapRacks: state.handicapRacks, handicapBeneficiary: state.handicapBeneficiary), events: [.reset])
        case .finishMatch:
            next.finished = true
            return .init(state: next, events: [.matchFinished])
        }
    }
}

// MARK: - Nine-ball chase points (2-4 players)

public enum NineBallRuleFamily: String, Codable, CaseIterable, Sendable { case folk, tournament }
public enum NineBallPointScheme: String, Codable, CaseIterable, Sendable { case standard = "14710", classic = "1357" }
public enum NineBallBreakRule: String, Codable, CaseIterable, Sendable { case winner, alternate }

public struct NineBallChaseConfig: Codable, Equatable, Sendable {
    public var bigGold: Int
    public var smallGold: Int
    public var goldenNine: Int
    public var normalWin: Int
    public var ballInHand: Int
    public var foul: Int
    public var smallGoldAllPay: Bool
    public var goldRetainsBreak: Bool
    public var ruleFamily: NineBallRuleFamily
    public var pointScheme: NineBallPointScheme
    public var handoffEnabled: Bool
    public var thirdFoul: Int
    public var breakRule: NineBallBreakRule
    public var totalRacks: Int

    public init(bigGold: Int = 10, smallGold: Int = 7, goldenNine: Int = 4, normalWin: Int = 4, ballInHand: Int = 1, foul: Int = 1, smallGoldAllPay: Bool = false, goldRetainsBreak: Bool = true, ruleFamily: NineBallRuleFamily = .folk, pointScheme: NineBallPointScheme = .standard, handoffEnabled: Bool = true, thirdFoul: Int = 2, breakRule: NineBallBreakRule = .winner, totalRacks: Int = 10) {
        self.bigGold = Self.point(bigGold); self.smallGold = Self.point(smallGold)
        self.goldenNine = Self.point(goldenNine); self.normalWin = Self.point(normalWin)
        self.ballInHand = Self.point(ballInHand); self.foul = Self.point(foul)
        self.smallGoldAllPay = smallGoldAllPay; self.goldRetainsBreak = goldRetainsBreak
        self.ruleFamily = ruleFamily; self.pointScheme = pointScheme; self.handoffEnabled = handoffEnabled
        self.thirdFoul = Self.point(thirdFoul); self.breakRule = breakRule; self.totalRacks = Self.point(totalRacks)
    }
    public static func preset(_ scheme: NineBallPointScheme = .standard, family: NineBallRuleFamily = .folk) -> Self {
        scheme == .classic && family == .folk
            ? .init(bigGold: 7, smallGold: 5, goldenNine: 3, normalWin: 3, pointScheme: scheme)
            : .init(ruleFamily: family)
    }
    public var normalized: Self {
        .init(bigGold: bigGold, smallGold: smallGold, goldenNine: goldenNine, normalWin: normalWin,
              ballInHand: ballInHand, foul: foul, smallGoldAllPay: smallGoldAllPay,
              goldRetainsBreak: goldRetainsBreak, ruleFamily: ruleFamily, pointScheme: pointScheme,
              handoffEnabled: handoffEnabled, thirdFoul: thirdFoul, breakRule: breakRule, totalRacks: totalRacks)
    }
    public var maximumRackSwing: Int { 2 * foul + max(bigGold, smallGold, normalWin, thirdFoul) }
    private static func point(_ value: Int) -> Int { min(99, max(1, value)) }
    private enum CodingKeys: String, CodingKey {
        case bigGold, smallGold, goldenNine, normalWin, ballInHand, foul, smallGoldAllPay, goldRetainsBreak
        case ruleFamily, pointScheme, handoffEnabled, thirdFoul, breakRule, totalRacks
    }
    public init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        self.init(bigGold: try v.decode(Int.self, forKey: .bigGold), smallGold: try v.decode(Int.self, forKey: .smallGold),
                  goldenNine: try v.decode(Int.self, forKey: .goldenNine), normalWin: try v.decode(Int.self, forKey: .normalWin),
                  ballInHand: try v.decode(Int.self, forKey: .ballInHand), foul: try v.decode(Int.self, forKey: .foul),
                  smallGoldAllPay: try v.decodeIfPresent(Bool.self, forKey: .smallGoldAllPay) ?? false,
                  goldRetainsBreak: try v.decodeIfPresent(Bool.self, forKey: .goldRetainsBreak) ?? true,
                  ruleFamily: try v.decodeIfPresent(NineBallRuleFamily.self, forKey: .ruleFamily) ?? .folk,
                  pointScheme: try v.decodeIfPresent(NineBallPointScheme.self, forKey: .pointScheme) ?? .standard,
                  handoffEnabled: try v.decodeIfPresent(Bool.self, forKey: .handoffEnabled) ?? true,
                  thirdFoul: try v.decodeIfPresent(Int.self, forKey: .thirdFoul) ?? 2,
                  breakRule: try v.decodeIfPresent(NineBallBreakRule.self, forKey: .breakRule) ?? .winner,
                  totalRacks: try v.decodeIfPresent(Int.self, forKey: .totalRacks) ?? 10)
    }
}

public enum NineBallChaseKind: String, Codable, CaseIterable, Equatable, Sendable {
    case bigGold = "big_gold"
    case smallGold = "small_gold"
    case goldenNine = "golden_nine"
    case normalWin = "normal_win"
    case ballInHand = "ball_in_hand"
    case foul
    /// A non-scoring choice of who continues. The legacy ball_in_hand slot is never reused.
    case handoff

    public static let legacyKinds: [Self] = [.bigGold, .smallGold, .goldenNine, .normalWin, .ballInHand, .foul]
    public static let transferKinds: [Self] = [.bigGold, .smallGold, .goldenNine, .normalWin, .handoff, .foul]

    public var endsRack: Bool {
        self == .bigGold || self == .smallGold || self == .goldenNine || self == .normalWin
    }
}

public struct NineBallChaseState: Codable, Equatable, Sendable {
    public var playerCount: Int
    public var playerPoints: [Int]
    public var playerCounts: [[Int]]
    public var config: NineBallChaseConfig
    public var finished: Bool
    /// Display names for up to 4 players. Empty slots use UI defaults.
    public var playerNames: [String]
    /// Presentation-only side placement for two-player chase. Player identity,
    /// scores and event counts always remain in logical player order.
    public var sidesSwapped: Bool
    /// Missing on persisted sessions means legacy cumulative scoring, never an implicit upgrade.
    public var ruleVersion: Int
    public var roundNumber: Int
    public var breakerPlayer: Int
    /// The configured opening breaker, kept separately from the current rack.
    public var initialBreakerPlayer: Int
    public var currentShooter: Int?

    public var rackFouls: [Int]
    public var isTournament: Bool { ruleVersion == 3 && config.ruleFamily == .tournament }
    public var usesRackRules: Bool { ruleVersion == 2 || ruleVersion == 3 }
    public var scoringKinds: [NineBallChaseKind] {
        if ruleVersion == 1 { return NineBallChaseKind.legacyKinds }
        if isTournament { return [.bigGold, .smallGold, .normalWin, .foul] }
        return NineBallChaseKind.transferKinds.filter { ruleVersion == 2 || config.handoffEnabled || $0 != .handoff }
    }

    public init(
        playerCount: Int,
        playerPoints: [Int],
        playerCounts: [[Int]],
        config: NineBallChaseConfig,
        finished: Bool,
        playerNames: [String] = [],
        sidesSwapped: Bool = false,
        ruleVersion: Int = 2,
        roundNumber: Int = 1,
        breakerPlayer: Int = 0,
        initialBreakerPlayer: Int? = nil,
        currentShooter: Int? = nil,
        rackFouls: [Int] = []
    ) {
        let normalizedPlayerCount = ruleVersion == 3 && config.ruleFamily == .tournament ? 2 : min(4, max(2, playerCount))
        self.playerCount = normalizedPlayerCount
        self.ruleVersion = max(1, ruleVersion)
        self.roundNumber = max(1, roundNumber)
        self.breakerPlayer = (0..<self.playerCount).contains(breakerPlayer) ? breakerPlayer : 0
        self.initialBreakerPlayer = (0..<self.playerCount).contains(initialBreakerPlayer ?? breakerPlayer) ? (initialBreakerPlayer ?? breakerPlayer) : 0
        self.currentShooter = currentShooter.flatMap { (0..<normalizedPlayerCount).contains($0) ? $0 : nil }
        self.playerPoints = Array((playerPoints + Array(repeating: 0, count: 4)).prefix(4))
        let count = self.ruleVersion == 1 ? 6 : 7
        self.playerCounts = (0..<4).map { index in
            let source = playerCounts[safe: index] ?? []
            return Array((source + Array(repeating: 0, count: count)).prefix(count))
        }
        self.rackFouls = (0..<4).map { min(2, max(0, rackFouls[safe: $0] ?? 0)) }
        self.config = config.normalized
        self.finished = finished
        self.playerNames = Self.normalizedNames(playerNames)
        self.sidesSwapped = sidesSwapped
    }

    public static func initial(
        config: NineBallChaseConfig = .init(),
        playerCount: Int = 2,
        playerNames: [String] = [],
        ruleVersion: Int = 2,
        breakerPlayer: Int = 0
    ) -> Self {
        .init(
            playerCount: playerCount,
            playerPoints: Array(repeating: 0, count: 4),
            playerCounts: Array(repeating: Array(repeating: 0, count: ruleVersion == 1 ? 6 : 7), count: 4),
            config: config,
            finished: false,
            playerNames: playerNames,
            ruleVersion: ruleVersion,
            breakerPlayer: breakerPlayer
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
        case playerCount, playerPoints, playerCounts, config, finished, playerNames, sidesSwapped
        case ruleVersion, roundNumber, breakerPlayer, initialBreakerPlayer, currentShooter, rackFouls
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            playerCount: try container.decode(Int.self, forKey: .playerCount),
            playerPoints: try container.decode([Int].self, forKey: .playerPoints),
            playerCounts: try container.decode([[Int]].self, forKey: .playerCounts),
            config: try container.decode(NineBallChaseConfig.self, forKey: .config),
            finished: try container.decode(Bool.self, forKey: .finished),
            playerNames: try container.decodeIfPresent([String].self, forKey: .playerNames) ?? [],
            sidesSwapped: try container.decodeIfPresent(Bool.self, forKey: .sidesSwapped) ?? false,
            ruleVersion: try container.decodeIfPresent(Int.self, forKey: .ruleVersion) ?? 1,
            roundNumber: try container.decodeIfPresent(Int.self, forKey: .roundNumber) ?? 1,
            breakerPlayer: try container.decodeIfPresent(Int.self, forKey: .breakerPlayer) ?? 0,
            initialBreakerPlayer: try container.decodeIfPresent(Int.self, forKey: .initialBreakerPlayer) ?? 0,
            currentShooter: try container.decodeIfPresent(Int.self, forKey: .currentShooter),
            rackFouls: try container.decodeIfPresent([Int].self, forKey: .rackFouls) ?? []
        )
    }
}

public enum NineBallChaseIntent: Codable, Sendable {
    /// Only valid for legacy sessions. New sessions require the transfer intent.
    case chaseEvent(player: Int, kind: NineBallChaseKind)
    case chaseTransfer(player: Int, kind: NineBallChaseKind, payer: Int?, continuePlayer: Int?)
    case tournamentEvent(player: Int, kind: NineBallChaseKind)
    case setBreaker(player: Int)
    case deltaTotal(player: Int, delta: Int)
    case adminSetTotals(left: Int, right: Int)
    case adminCorrect(playerNames: [String], playerPoints: [Int])
    case exchangeSides
    case resetScores
    case finishMatch
}

public enum NineBallChaseEvent: Codable, Equatable, Sendable {
    case chaseApplied(player: Int, scorePlayer: Int, kind: NineBallChaseKind, delta: Int)
    case totalsAdjusted
    case sidesExchanged
    case matchFinished
    case chaseTransferred(player: Int, kind: NineBallChaseKind, deltas: [Int], payer: Int?, continuePlayer: Int?, roundBefore: Int, breakerBefore: Int, nextBreaker: Int)
    case breakerChanged(player: Int)
}

public struct NineBallChaseReducer: DomainReducer {
    public init() {}

    public func reduce(state: NineBallChaseState, intent: NineBallChaseIntent, at epochMilliseconds: Int64) -> ReduceResult<NineBallChaseState, NineBallChaseEvent> {
        guard (1...3).contains(state.ruleVersion) else {
            return .rejected(state: state, reason: "Unsupported nine-ball rule version")
        }
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
            next.playerCounts = Array(repeating: Array(repeating: 0, count: next.ruleVersion == 1 ? 6 : 7), count: 4)
            next.finished = false
            next.sidesSwapped = false
            next.roundNumber = 1
            next.breakerPlayer = next.initialBreakerPlayer
            next.currentShooter = nil
            next.rackFouls = Array(repeating: 0, count: 4)
            return .init(state: next, events: [.totalsAdjusted])
        case .chaseEvent(let player, let kind):
            guard next.ruleVersion == 1 else { return .rejected(state: state, reason: "Rule v2 requires a transfer event") }
            guard (0 ..< next.playerCount).contains(player) else { return .rejected(state: state, reason: "Invalid player") }
            let configured = delta(for: kind, config: next.config)
            guard configured != 0 else { return .rejected(state: state, reason: "Invalid point value") }
            let scorePlayer = kind == .foul && next.playerCount == 2 ? (player == 0 ? 1 : 0) : player
            let scoreDelta = kind == .foul && next.playerCount > 2 ? -configured : configured
            guard let kindIndex = NineBallChaseKind.allCases.firstIndex(of: kind) else {
                return .rejected(state: state, reason: "Invalid event kind")
            }
            next.playerPoints[scorePlayer] += scoreDelta
            next.playerCounts[player][kindIndex] += 1
            return .init(state: next, events: [.chaseApplied(player: player, scorePlayer: scorePlayer, kind: kind, delta: scoreDelta)])
        case .chaseTransfer(let player, let kind, let payer, let continuePlayer):
            guard next.usesRackRules, !next.isTournament else { return .rejected(state: state, reason: "Session requires its own scoring intent") }
            return transfer(state: next, player: player, kind: kind, payer: payer, continuePlayer: continuePlayer)
        case .tournamentEvent(let player, let kind):
            return tournament(state: next, player: player, kind: kind)
        case .setBreaker(let player):
            guard next.usesRackRules, (0..<next.playerCount).contains(player) else {
                return .rejected(state: state, reason: "Invalid breaker")
            }
            next.breakerPlayer = player
            return .init(state: next, events: [.breakerChanged(player: player)])
        case .deltaTotal(let player, let delta):
            guard (0 ..< next.playerCount).contains(player) else { return .rejected(state: state, reason: "Invalid player") }
            guard !next.isTournament || next.playerPoints[player] + delta >= 0 else { return .rejected(state: state, reason: "Negative tournament score") }
            next.playerPoints[player] += delta
            return .init(state: next, events: [.totalsAdjusted])
        case .adminSetTotals(let left, let right):
            guard !next.isTournament || (left >= 0 && right >= 0) else { return .rejected(state: state, reason: "Negative tournament score") }
            next.playerPoints[0] = next.ruleVersion == 1 ? max(0, left) : left
            next.playerPoints[1] = next.ruleVersion == 1 ? max(0, right) : right
            return .init(state: next, events: [.totalsAdjusted])
        case .adminCorrect(let playerNames, let playerPoints):
            guard !next.isTournament || playerPoints.prefix(next.playerCount).allSatisfy({ $0 >= 0 }) else { return .rejected(state: state, reason: "Negative tournament score") }
            for index in 0 ..< next.playerCount {
                let trimmed = playerNames[safe: index]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !trimmed.isEmpty {
                    next.playerNames[index] = trimmed
                }
                if let points = playerPoints[safe: index] {
                    next.playerPoints[index] = min(9_999, max(-9_999, points))
                }
            }
            next.finished = false
            return .init(state: next, events: [.totalsAdjusted])
        case .exchangeSides:
            guard next.playerCount == 2 else {
                return .rejected(state: state, reason: "Exchange sides is only available for two players")
            }
            next.sidesSwapped.toggle()
            return .init(state: next, events: [.sidesExchanged])
        case .finishMatch:
            next.finished = true
            return .init(state: next, events: [.matchFinished])
        }
    }

    private func normalized(_ state: NineBallChaseState) -> NineBallChaseState {
        .init(playerCount: state.playerCount, playerPoints: state.playerPoints, playerCounts: state.playerCounts,
              config: state.config, finished: state.finished, playerNames: state.playerNames,
              sidesSwapped: state.sidesSwapped, ruleVersion: state.ruleVersion, roundNumber: state.roundNumber,
              breakerPlayer: state.breakerPlayer, initialBreakerPlayer: state.initialBreakerPlayer, currentShooter: state.currentShooter, rackFouls: state.rackFouls)
    }

    private func delta(for kind: NineBallChaseKind, config: NineBallChaseConfig) -> Int {
        switch kind {
        case .bigGold: config.bigGold
        case .smallGold: config.smallGold
        case .goldenNine: config.goldenNine
        case .normalWin: config.normalWin
        case .ballInHand: config.ballInHand
        case .foul: config.foul
        case .handoff: 0
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
    public var sidesSwapped: Bool

    private enum CodingKeys: String, CodingKey {
        case leftIndex, rightIndex, maxTierIndex, finished, dealer, sidesSwapped
    }

    public init(leftIndex: Int = 0, rightIndex: Int = 0, maxTierIndex: Int = 12, finished: Bool = false, dealer: MatchSide? = nil, sidesSwapped: Bool = false) {
        self.leftIndex = leftIndex
        self.rightIndex = rightIndex
        self.maxTierIndex = maxTierIndex
        self.finished = finished
        self.dealer = dealer
        self.sidesSwapped = sidesSwapped
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            leftIndex: try container.decode(Int.self, forKey: .leftIndex),
            rightIndex: try container.decode(Int.self, forKey: .rightIndex),
            maxTierIndex: try container.decode(Int.self, forKey: .maxTierIndex),
            finished: try container.decode(Bool.self, forKey: .finished),
            dealer: try container.decodeIfPresent(MatchSide.self, forKey: .dealer),
            sidesSwapped: try container.decodeIfPresent(Bool.self, forKey: .sidesSwapped) ?? false
        )
    }

    public var winnerSide: MatchSide? {
        guard finished, leftIndex != rightIndex else { return nil }
        return leftIndex > rightIndex ? .left : .right
    }
}

public enum ShengjiTierIntent: Codable, Sendable {
    case addLevels(side: MatchSide, delta: Int)
    case subtractLevels(side: MatchSide, delta: Int)
    case claimDealer(MatchSide)
    case resolveRound(winner: MatchSide, delta: Int)
    case adminCorrect(left: Int, right: Int)
    case exchangeSides
    case reset
    case finish
}

public enum ShengjiTierEvent: Codable, Equatable, Sendable {
    case tierAdjusted(add: Bool, side: MatchSide, delta: Int, left: Int, right: Int)
    case dealerClaimed(side: MatchSide, initial: Bool)
    case administrativeCorrection(left: Int, right: Int)
    case sidesExchanged
    case matchReset
    case matchFinished
}

public struct ShengjiTierReducer: DomainReducer {
    public init() {}

    public func reduce(state: ShengjiTierState, intent: ShengjiTierIntent, at epochMilliseconds: Int64) -> ReduceResult<ShengjiTierState, ShengjiTierEvent> {
        var current = state
        let cap = max(0, current.maxTierIndex)
        current.finished = current.finished || current.leftIndex >= cap || current.rightIndex >= cap
        if current.finished {
            switch intent {
            case .subtractLevels, .adminCorrect, .reset:
                break
            default:
                return .rejected(state: current, reason: "Already finished")
            }
        }
        switch intent {
        case .adminCorrect(let left, let right):
            current.leftIndex = min(max(0, left), cap)
            current.rightIndex = min(max(0, right), cap)
            current.finished = current.leftIndex >= cap || current.rightIndex >= cap
            return .init(
                state: current,
                events: [.administrativeCorrection(left: current.leftIndex, right: current.rightIndex)]
            )
        case .reset:
            return .init(
                state: ShengjiTierState(maxTierIndex: current.maxTierIndex),
                events: [.matchReset]
            )
        case .exchangeSides:
            current.sidesSwapped.toggle()
            return .init(state: current, events: [.sidesExchanged])
        case .finish:
            guard !current.finished else { return .rejected(state: current, reason: "Already finished") }
            current.finished = true
            return .init(state: current, events: [.matchFinished])
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
            if current.dealer != previousDealer { events.append(.dealerClaimed(side: winner, initial: false)) }
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
