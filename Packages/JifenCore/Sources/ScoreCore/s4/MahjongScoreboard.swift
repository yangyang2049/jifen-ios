import Foundation

// MARK: - 麻将记分引擎（Mahjong scoreboard engine）
//
// 本文件是跨端麻将契约 v2 的 iOS 翻译，逐函数对应：
//   - HarmonyOS `entry/src/main/ets/model/MahjongModels.ts`
//   - HarmonyOS `entry/src/main/ets/scoreboard/mahjong/MahjongReducer.ts`
//   - HarmonyOS `entry/src/main/ets/scoreboard/mahjong/MahjongFormState.ts`
//   - Android `shared-model/.../MahjongModels.kt`、`score-engine/.../mahjong/MahjongReducer.kt`
// 语义不做再设计：只记分不推动牌局状态机（除和牌推进手数/轮庄），台账是唯一真源，
// 任何状态都能由 `restore(setup:ledger:)` 逐条重放重建。
//
// JSON 字段名与 hos/Android 完全一致（schemaVersion / playerNames / winnerIndexes /
// scoresAfter / completesHand …），因此记录、草稿、投屏 JSON 可跨端读写。
//
// 唯一与 JS 实现不同的地方是整数安全：JS 用 `Number.isSafeInteger` + `Math.pow`，
// Swift 用 Int64 移位并在超出 Int32 范围时拒绝（对应 Android 的 `toSafeIntOrNull`），
// 接受/拒绝的判定结果与两端一致。
//
// Golden fixtures 复用 Android 的跨端契约数据：
//   `Tests/JifenCoreTests/mahjong/mahjong-reducer-v2.json`（当前契约 v2）
//   `Tests/JifenCoreTests/mahjong/mahjong-reducer-v1.json`（legacy v1 流水）
// 注意 v1 文件在本仓库只用于「legacy 流水按原值重放」这条规则的测试：iOS 从未发布过
// 麻将，v1 不是 iOS 可写入的协议版本（hos `MAHJONG_CONTRACT_VERSION = 2`）。

// MARK: - 常量与枚举

/// 跨端契约版本（hos `MAHJONG_CONTRACT_VERSION`、Android `MAHJONG_CONTRACT_VERSION`）。
public let MAHJONG_CONTRACT_VERSION: Int = 2
/// 麻将固定 4 人（hos `MAHJONG_PLAYER_COUNT`）。
public let MAHJONG_PLAYER_COUNT: Int = 4
/// 座位风顺序（hos `seatWinds` 默认值、Android `mahjongSeatWindsForDealer`）。
public let mahjongWindOrder: [String] = ["east", "south", "west", "north"]

/// 按庄家轮转后的逐座位风（Android `mahjongSeatWindsForDealer`）。
public func mahjongSeatWindsForDealer(dealerIndex: Int) -> [String] {
    let dealer = max(0, min(MAHJONG_PLAYER_COUNT - 1, dealerIndex))
    return (0 ..< MAHJONG_PLAYER_COUNT).map { index in
        mahjongWindOrder[(index - dealer + MAHJONG_PLAYER_COUNT) % MAHJONG_PLAYER_COUNT]
    }
}

/// 按庄家轮转后的默认座位名（Android `mahjongDefaultPlayerNamesForDealer`）。
public func mahjongDefaultPlayerNamesForDealer(dealerIndex: Int) -> [String] {
    let names = ["东家", "南家", "西家", "北家"]
    let dealer = max(0, min(MAHJONG_PLAYER_COUNT - 1, dealerIndex))
    return (0 ..< MAHJONG_PLAYER_COUNT).map { index in
        names[(index - dealer + MAHJONG_PLAYER_COUNT) % MAHJONG_PLAYER_COUNT]
    }
}

public enum MahjongRuleset: String, Codable, Equatable, Sendable, CaseIterable {
    case generic
    case sichuanBloodBattle = "sichuan_blood_battle"
}

public enum MahjongMatchLength: String, Codable, Equatable, Sendable, CaseIterable {
    case free
    case eastOnly = "east_only"
    case hanchan
}

public enum MahjongDealerRule: String, Codable, Equatable, Sendable, CaseIterable {
    case rotateEachHand = "rotate_each_hand"
    case dealerWinOrDrawStays = "dealer_win_or_draw_stays"
}

public enum MahjongActionType: String, Codable, Equatable, Sendable, CaseIterable {
    case selfDraw = "self_draw"
    case discardWin = "discard_win"
    case kong
    case draw
    case notenPenalty = "noten_penalty"
    case flowerPigPenalty = "flower_pig_penalty"
    case kongRefund = "kong_refund"
    case transfer
    case adjustment
}

public enum MahjongKongKind: String, Codable, Equatable, Sendable, CaseIterable {
    case exposed
    case added
    case concealed
}

public enum MahjongPaymentMode: String, Codable, Equatable, Sendable, CaseIterable {
    case onePayer = "one_payer"
    case allOpponents = "all_opponents"
}

extension MahjongActionType {
    /// hos `isWin`：只有自摸与点炮算和牌。
    public var isWin: Bool { self == .selfDraw || self == .discardWin }

    /// hos `isMahjongManual`：手工四家增减。
    public var isManual: Bool {
        self == .adjustment || self == .notenPenalty || self == .flowerPigPenalty
    }
}

// MARK: - Setup

/// 开局设置（hos `MahjongSetupResult`）。
public struct MahjongSetupResult: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var playerNames: [String]
    public var seatWinds: [String]
    public var ruleset: MahjongRuleset
    public var startScore: Int
    public var baseScore: Int
    public var initialDealerIndex: Int
    public var matchLength: MahjongMatchLength
    public var dealerRule: MahjongDealerRule
    public var maxFan: Int

    public init(
        schemaVersion: Int = MAHJONG_CONTRACT_VERSION,
        playerNames: [String] = ["东家", "南家", "西家", "北家"],
        seatWinds: [String] = mahjongWindOrder,
        ruleset: MahjongRuleset = .generic,
        startScore: Int = 0,
        baseScore: Int = 1,
        initialDealerIndex: Int = 0,
        matchLength: MahjongMatchLength = .free,
        dealerRule: MahjongDealerRule = .rotateEachHand,
        maxFan: Int = 4
    ) {
        self.schemaVersion = schemaVersion
        self.playerNames = playerNames
        self.seatWinds = seatWinds
        self.ruleset = ruleset
        self.startScore = startScore
        self.baseScore = baseScore
        self.initialDealerIndex = initialDealerIndex
        self.matchLength = matchLength
        self.dealerRule = dealerRule
        self.maxFan = maxFan
    }

    /// hos `createDefaultMahjongSetup`。
    public static func generic(playerNames: [String]? = nil) -> MahjongSetupResult {
        MahjongSetupResult(playerNames: playerNames?.prefix(MAHJONG_PLAYER_COUNT).map { $0 } ?? ["东家", "南家", "西家", "北家"])
    }

    /// hos `createSichuanMahjongSetup` / Android `sichuanPreset`：底分 2、封顶 4。
    public static func sichuanBloodBattle(playerNames: [String]? = nil) -> MahjongSetupResult {
        var setup = MahjongSetupResult.generic(playerNames: playerNames)
        setup.ruleset = .sichuanBloodBattle
        setup.baseScore = 2
        setup.maxFan = 4
        return setup
    }

    /// Android `isScoreRangeSafe`：底分×2^封顶番数必须落在 Int32 内。
    public var isScoreRangeSafe: Bool {
        guard baseScore > 0, (0 ... 30).contains(maxFan) else { return false }
        if ruleset == .generic { return true }
        return Int64(baseScore) * (Int64(1) << Int64(maxFan)) <= Int64(Int32.max)
    }

    /// hos `resolveMahjongCapScore` / Android `capScoreOrNull`：
    /// 仅四川血战有封顶分，其它模板为 nil。
    public var capScore: Int? {
        guard ruleset == .sichuanBloodBattle, baseScore > 0, (0 ... 30).contains(maxFan),
              isScoreRangeSafe else { return nil }
        return Int(Int64(baseScore) * (Int64(1) << Int64(maxFan)))
    }

    /// Android `MahjongSetupResult.init` 的 `require` 校验：返回首个不满足项。
    public func validationError() -> String? {
        if schemaVersion < 1 { return "schemaVersion must be positive" }
        if playerNames.count != MAHJONG_PLAYER_COUNT { return "Mahjong requires four player names" }
        if seatWinds.count != MAHJONG_PLAYER_COUNT { return "Mahjong requires four seat winds" }
        if !(0 ..< MAHJONG_PLAYER_COUNT).contains(initialDealerIndex) { return "Invalid dealer index" }
        if baseScore <= 0 { return "Base score must be positive" }
        if !(0 ... 30).contains(maxFan) { return "maxFan must be between 0 and 30" }
        if !isScoreRangeSafe { return "Maximum settlement exceeds the score range" }
        return nil
    }
}

// MARK: - Ledger

/// 一笔流水（hos `MahjongLedgerEntry`）。分数变化与结算后总分都写死在流水里，
/// 因此重放时不需要重新推算金额（v1 legacy 流水正是靠这一点按原值恢复）。
public struct MahjongLedgerEntry: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var timestamp: Int64
    public var handNumber: Int
    public var roundOrdinal: Int
    public var dealerIndex: Int
    public var dealerStreak: Int
    public var actionType: MahjongActionType
    public var winnerIndexes: [Int]
    public var payerIndexes: [Int]
    public var kongKind: MahjongKongKind?
    public var paymentMode: MahjongPaymentMode?
    public var baseScore: Int
    /// 两端语义均为「番数」；v1 流水的已结算分数按 `resolvedAmount`/`scoresAfter` 原值恢复。
    public var factor: Int
    public var resolvedAmount: Int
    /// 点炮一炮多响时的逐位番数（hos 独有；长度固定 4）。
    public var winnerFactors: [Int]?
    /// 点炮一炮多响时的逐位金额（hos 独有；长度固定 4）。
    public var winnerAmounts: [Int]?
    /// 退杠分指向的原杠分流水 id（hos 独有）。
    public var refundEntryIds: [String]?
    public var deltas: [Int]
    public var scoresAfter: [Int]
    public var completesHand: Bool
    public var zeroSum: Bool
    public var note: String?

    public init(
        schemaVersion: Int = MAHJONG_CONTRACT_VERSION,
        id: String,
        timestamp: Int64,
        handNumber: Int,
        roundOrdinal: Int,
        dealerIndex: Int,
        dealerStreak: Int,
        actionType: MahjongActionType,
        winnerIndexes: [Int] = [],
        payerIndexes: [Int] = [],
        kongKind: MahjongKongKind? = nil,
        paymentMode: MahjongPaymentMode? = nil,
        baseScore: Int,
        factor: Int,
        resolvedAmount: Int,
        winnerFactors: [Int]? = nil,
        winnerAmounts: [Int]? = nil,
        refundEntryIds: [String]? = nil,
        deltas: [Int],
        scoresAfter: [Int],
        completesHand: Bool,
        zeroSum: Bool,
        note: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.timestamp = timestamp
        self.handNumber = handNumber
        self.roundOrdinal = roundOrdinal
        self.dealerIndex = dealerIndex
        self.dealerStreak = dealerStreak
        self.actionType = actionType
        self.winnerIndexes = winnerIndexes
        self.payerIndexes = payerIndexes
        self.kongKind = kongKind
        self.paymentMode = paymentMode
        self.baseScore = baseScore
        self.factor = factor
        self.resolvedAmount = resolvedAmount
        self.winnerFactors = winnerFactors
        self.winnerAmounts = winnerAmounts
        self.refundEntryIds = refundEntryIds
        self.deltas = deltas
        self.scoresAfter = scoresAfter
        self.completesHand = completesHand
        self.zeroSum = zeroSum
        self.note = note
    }
}

/// 会话状态（hos `MahjongSessionState`）。
public struct MahjongSessionState: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var setup: MahjongSetupResult
    public var scores: [Int]
    public var handNumber: Int
    /// 0=东一，1=东二…4=南一；连庄不推进（Android 注释同）。
    public var roundOrdinal: Int
    public var dealerIndex: Int
    public var dealerStreak: Int
    /// 血战当前手已和牌者；非血战恒为空。
    public var currentHandWinnerIndexes: [Int]
    public var ledger: [MahjongLedgerEntry]
    public var lastDeltas: [Int]
    public var roundLimitReached: Bool
    public var roundLimitAcknowledged: Bool?
    public var finished: Bool

    public init(
        schemaVersion: Int = MAHJONG_CONTRACT_VERSION,
        setup: MahjongSetupResult,
        scores: [Int]? = nil,
        handNumber: Int = 1,
        roundOrdinal: Int = 0,
        dealerIndex: Int? = nil,
        dealerStreak: Int = 1,
        currentHandWinnerIndexes: [Int] = [],
        ledger: [MahjongLedgerEntry] = [],
        lastDeltas: [Int]? = nil,
        roundLimitReached: Bool = false,
        roundLimitAcknowledged: Bool? = nil,
        finished: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.setup = setup
        self.scores = scores ?? [Int](repeating: setup.startScore, count: MAHJONG_PLAYER_COUNT)
        self.handNumber = handNumber
        self.roundOrdinal = roundOrdinal
        self.dealerIndex = dealerIndex ?? setup.initialDealerIndex
        self.dealerStreak = dealerStreak
        self.currentHandWinnerIndexes = currentHandWinnerIndexes
        self.ledger = ledger
        self.lastDeltas = lastDeltas ?? [Int](repeating: 0, count: MAHJONG_PLAYER_COUNT)
        self.roundLimitReached = roundLimitReached
        self.roundLimitAcknowledged = roundLimitAcknowledged
        self.finished = finished
    }

    /// hos `createMahjongSession`。
    public static func initial(setup: MahjongSetupResult) -> MahjongSessionState {
        MahjongSessionState(setup: setup)
    }

    /// Android `MahjongDraftState` 对应物：草稿落盘时带的更新时间戳。
    public struct Draft: Codable, Equatable, Sendable {
        public var schemaVersion: Int
        public var setup: MahjongSetupResult
        public var session: MahjongSessionState
        public var updatedAtEpochMs: Int64

        public init(
            schemaVersion: Int = MAHJONG_CONTRACT_VERSION,
            setup: MahjongSetupResult,
            session: MahjongSessionState,
            updatedAtEpochMs: Int64
        ) {
            self.schemaVersion = schemaVersion
            self.setup = setup
            self.session = session
            self.updatedAtEpochMs = updatedAtEpochMs
        }
    }
}

/// 结算统计（hos/Android `MahjongPlayerStats`）。
public struct MahjongPlayerStats: Codable, Equatable, Sendable {
    public var playerIndex: Int
    public var name: String
    public var finalScore: Int
    public var netChange: Int
    public var rank: Int
    public var winCount: Int
    public var selfDrawCount: Int
    public var discardCount: Int

    public init(
        playerIndex: Int,
        name: String,
        finalScore: Int,
        netChange: Int,
        rank: Int,
        winCount: Int,
        selfDrawCount: Int,
        discardCount: Int
    ) {
        self.playerIndex = playerIndex
        self.name = name
        self.finalScore = finalScore
        self.netChange = netChange
        self.rank = rank
        self.winCount = winCount
        self.selfDrawCount = selfDrawCount
        self.discardCount = discardCount
    }
}

/// 逐人和牌统计（hos/Android 记录详情页用同一份口径）。
public func mahjongPlayerStats(state: MahjongSessionState) -> [MahjongPlayerStats] {
    var winCount = [Int](repeating: 0, count: MAHJONG_PLAYER_COUNT)
    var selfDrawCount = [Int](repeating: 0, count: MAHJONG_PLAYER_COUNT)
    var discardCount = [Int](repeating: 0, count: MAHJONG_PLAYER_COUNT)
    for entry in state.ledger {
        switch entry.actionType {
        case .selfDraw:
            for index in entry.winnerIndexes where (0 ..< MAHJONG_PLAYER_COUNT).contains(index) {
                winCount[index] += 1
                selfDrawCount[index] += 1
            }
        case .discardWin:
            for index in entry.winnerIndexes where (0 ..< MAHJONG_PLAYER_COUNT).contains(index) {
                winCount[index] += 1
            }
            for index in entry.payerIndexes where (0 ..< MAHJONG_PLAYER_COUNT).contains(index) {
                discardCount[index] += 1
            }
        default:
            break
        }
    }
    let ranked = (0 ..< MAHJONG_PLAYER_COUNT)
        .map { index in (index, state.scores.indices.contains(index) ? state.scores[index] : 0) }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
    return ranked.enumerated().map { rank, item in
        MahjongPlayerStats(
            playerIndex: item.0,
            name: state.setup.playerNames.indices.contains(item.0) ? state.setup.playerNames[item.0] : "",
            finalScore: item.1,
            netChange: item.1 - state.setup.startScore,
            rank: rank + 1,
            winCount: winCount[item.0],
            selfDrawCount: selfDrawCount[item.0],
            discardCount: discardCount[item.0]
        )
    }
}

// MARK: - 工具函数（hos `MahjongFormState` / reducer 内部）

/// hos `distinct`：保序去重。
func mahjongDistinct(_ values: [Int]) -> [Int] {
    var out: [Int] = []
    for value in values where !out.contains(value) { out.append(value) }
    return out
}

/// hos `mahjongInteger(text, signed)`：只接受纯数字（signed 时允许一个前导 ±），
/// 拒绝 ""、"1.5"、"2x"、"--1"、"1e2"、"0x10"，接受 "+4"/"-4"。
public func mahjongInteger(_ text: String?, signed: Bool = false) -> Int? {
    guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    var characters = Array(trimmed)
    if signed, characters.first == "+" || characters.first == "-" {
        characters.removeFirst()
    }
    guard !characters.isEmpty else { return nil }
    for character in characters where !("0" ... "9").contains(String(character)) {
        return nil
    }
    return Int(trimmed)
}

/// hos `activeMahjongPlayers`：血战剔除本手已和牌者。
public func activeMahjongPlayers(_ state: MahjongSessionState) -> [Int] {
    (0 ..< MAHJONG_PLAYER_COUNT).filter { index in
        state.setup.ruleset != .sichuanBloodBattle || !state.currentHandWinnerIndexes.contains(index)
    }
}

/// hos `reachedLimit`：东风圈 4 局、半庄 8 局。
func mahjongReachedRoundLimit(_ length: MahjongMatchLength, roundOrdinal: Int) -> Bool {
    switch length {
    case .free: return false
    case .eastOnly: return roundOrdinal >= 4
    case .hanchan: return roundOrdinal >= 8
    }
}

/// 合法座位下标集合（hos 的 `index >= 0 && index < MAHJONG_PLAYER_COUNT`）。
let mahjongSeatRange: Set<Int> = Set(0 ..< MAHJONG_PLAYER_COUNT)

/// `底分 × 2^番`，番数超出可表示范围或结果超出 Int32 时返回 nil
/// （对应 JS 的 `!Number.isSafeInteger(amount) || amount > 2147483647`）。
func mahjongScaledAmount(baseScore: Int, exponent: Int) -> Int? {
    guard baseScore != 0, exponent >= 0, exponent <= 30 else { return nil }
    return safeInt32(Int64(baseScore) * (Int64(1) << Int64(exponent)))
}

/// Int32 收口（Android `toSafeIntOrNull`）。
private func safeInt32(_ value: Int64) -> Int? {
    guard value >= Int64(Int32.min), value <= Int64(Int32.max) else { return nil }
    return Int(value)
}

// MARK: - Intent / Event

/// 结算意图（hos `MahjongSettlementIntent`）。
public struct MahjongSettlementIntent: Codable, Equatable, Sendable {
    public var actionType: MahjongActionType
    /// 幂等键：同 id 已入台账则整笔拒绝（hos `duplicate_operation`）。
    public var operationId: String?
    public var winnerIndexes: [Int]
    public var payerIndexes: [Int]
    public var factor: Int
    /// 一炮多响的逐位番数；提供时长度必须为 4。
    public var winnerFactors: [Int]?
    public var refundEntryIds: [String]
    public var kongKind: MahjongKongKind?
    public var paymentMode: MahjongPaymentMode?
    public var manualDeltas: [Int]?
    /// 血战「记入并结束」；通用和牌与流局由规则自动结束。
    public var endHand: Bool
    public var note: String?

    public init(
        actionType: MahjongActionType,
        operationId: String? = nil,
        winnerIndexes: [Int] = [],
        payerIndexes: [Int] = [],
        factor: Int = 0,
        winnerFactors: [Int]? = nil,
        refundEntryIds: [String] = [],
        kongKind: MahjongKongKind? = nil,
        paymentMode: MahjongPaymentMode? = nil,
        manualDeltas: [Int]? = nil,
        endHand: Bool = false,
        note: String? = nil
    ) {
        self.actionType = actionType
        self.operationId = operationId
        self.winnerIndexes = winnerIndexes
        self.payerIndexes = payerIndexes
        self.factor = factor
        self.winnerFactors = winnerFactors
        self.refundEntryIds = refundEntryIds
        self.kongKind = kongKind
        self.paymentMode = paymentMode
        self.manualDeltas = manualDeltas
        self.endHand = endHand
        self.note = note
    }
}

public enum MahjongSessionIntent: Codable, Equatable, Sendable {
    case recordSettlement(MahjongSettlementIntent)
    case undoLast
    case finishMatch
}

public enum MahjongSessionEvent: Codable, Equatable, Sendable {
    case settlementRecorded(MahjongLedgerEntry)
    case lastEntryUndone(MahjongLedgerEntry)
    case matchFinished(at: Int64)
}

/// hos `MahjongReduceResult.reason` 的机器可读 token，跨端逐字相同。
public enum MahjongRejectReason: String, Codable, Equatable, Sendable {
    case duplicateOperation = "duplicate_operation"
    case unsupportedVersion = "unsupported_version"
    case matchFinished = "match_finished"
    case invalidState = "invalid_state"
    case invalidAction = "invalid_action"
    case invalidPlayers = "invalid_players"
    case inactivePlayer = "inactive_player"
    case invalidFactor = "invalid_factor"
    case scoreOverflow = "score_overflow"
    case invalidSelfDraw = "invalid_self_draw"
    case invalidDiscardWin = "invalid_discard_win"
    case invalidKong = "invalid_kong"
    case invalidTransfer = "invalid_transfer"
    case invalidRefund = "invalid_refund"
    case invalidDraw = "invalid_draw"
    case invalidAdjustment = "invalid_adjustment"
    case penaltyNotZeroSum = "penalty_not_zero_sum"
    case notZeroSum = "not_zero_sum"
    case prematureEnd = "premature_end"
    case nothingToUndo = "nothing_to_undo"
    case invalidLedger = "invalid_ledger"
}

// MARK: - Reducer

public struct MahjongReducer: DomainReducer {
    public init() {}

    public func reduce(
        state: MahjongSessionState,
        intent: MahjongSessionIntent,
        at epochMilliseconds: Int64
    ) -> ReduceResult<MahjongSessionState, MahjongSessionEvent> {
        switch intent {
        case .recordSettlement(let settlement):
            return record(state, settlement, now: epochMilliseconds)
        case .undoLast:
            return undo(state)
        case .finishMatch:
            guard !state.finished else {
                return .rejected(state: state, reason: MahjongRejectReason.matchFinished.rawValue)
            }
            var next = state
            next.finished = true
            return ReduceResult(state: next, events: [.matchFinished(at: epochMilliseconds)])
        }
    }

    /// hos `MahjongReducer.record`。逐行对应，包括校验顺序与拒绝 token。
    public func record(
        _ state: MahjongSessionState,
        _ intent: MahjongSettlementIntent,
        now: Int64
    ) -> ReduceResult<MahjongSessionState, MahjongSessionEvent> {
        // 幂等：同 operationId 已入台账则整笔拒绝。
        if let operationId = intent.operationId,
           state.ledger.contains(where: { $0.id == operationId }) {
            return rejected(state, .duplicateOperation)
        }
        if state.schemaVersion > MAHJONG_CONTRACT_VERSION {
            return rejected(state, .unsupportedVersion)
        }
        if state.finished { return rejected(state, .matchFinished) }
        if state.scores.count != MAHJONG_PLAYER_COUNT { return rejected(state, .invalidState) }

        let blood = state.setup.ruleset == .sichuanBloodBattle
        // 查叫/查花猪/退杠分只在血战模板下存在（hos `invalid_action`）。
        if !blood,
           [MahjongActionType.notenPenalty, .flowerPigPenalty, .kongRefund].contains(intent.actionType) {
            return rejected(state, .invalidAction)
        }

        let active = activeMahjongPlayers(state)
        let rawWinners = intent.winnerIndexes
        let rawPayers = intent.payerIndexes
        let winners = mahjongDistinct(rawWinners)
        var payers = mahjongDistinct(rawPayers)
        // 座位重复或越界（hos 用长度对比识别重复）。
        if winners.count != rawWinners.count || payers.count != rawPayers.count {
            return rejected(state, .invalidPlayers)
        }
        if winners.contains(where: { !mahjongSeatRange.contains($0) })
            || payers.contains(where: { !mahjongSeatRange.contains($0) })
            || winners.contains(where: { payers.contains($0) }) {
            return rejected(state, .invalidPlayers)
        }
        if (intent.actionType.isWin || intent.actionType == .kong),
           (winners + payers).contains(where: { !active.contains($0) }) {
            return rejected(state, .inactivePlayer)
        }
        if payers.isEmpty, intent.actionType == .selfDraw {
            payers = active.filter { !winners.contains($0) }
        }
        if payers.isEmpty, intent.actionType == .kong, intent.paymentMode == .allOpponents {
            payers = active.filter { !winners.contains($0) }
        }

        let factor = intent.factor
        if factor < 0 { return rejected(state, .invalidFactor) }

        // 流局/调分/查叫/查花猪/退杠分不产生金额；杠分在血战按杠种计固定分。
        var amount = 0
        if intent.actionType != .draw, intent.actionType != .adjustment,
           intent.actionType != .notenPenalty, intent.actionType != .flowerPigPenalty,
           intent.actionType != .kongRefund {
            if blood, intent.actionType == .kong {
                let multiplier: Int64 = intent.kongKind == .added ? 1 : 2
                guard let value = safeInt32(Int64(state.setup.baseScore) * multiplier) else {
                    return rejected(state, .scoreOverflow)
                }
                amount = value
            } else {
                guard let value = calculateAmount(state: state, factor: factor) else {
                    return rejected(state, .scoreOverflow)
                }
                amount = value
            }
        }

        var deltas = [Int64](repeating: 0, count: MAHJONG_PLAYER_COUNT)
        var winnerAmounts = [Int](repeating: 0, count: MAHJONG_PLAYER_COUNT)
        switch intent.actionType {
        case .selfDraw:
            // 自摸：除和牌者外的全部活跃玩家各付一份。
            if winners.count != 1 || payers.count != active.count - 1
                || active.contains(where: { !winners.contains($0) && !payers.contains($0) }) {
                return rejected(state, .invalidSelfDraw)
            }
            for payer in payers {
                deltas[payer] -= Int64(amount)
                deltas[winners[0]] += Int64(amount)
            }
        case .discardWin:
            // 点炮：1 名点炮者，1~3 名和牌者，可逐位不同番数（一炮多响）。
            if winners.isEmpty || winners.count > 3 || payers.count != 1 {
                return rejected(state, .invalidDiscardWin)
            }
            if let winnerFactors = intent.winnerFactors, winnerFactors.count != MAHJONG_PLAYER_COUNT {
                return rejected(state, .invalidFactor)
            }
            for winner in winners {
                let fan = intent.winnerFactors?[winner] ?? factor
                if fan < 0 { return rejected(state, .invalidFactor) }
                let exponent = blood ? Swift.min(fan, state.setup.maxFan) : fan
                guard let ownAmount = mahjongScaledAmount(baseScore: state.setup.baseScore, exponent: exponent) else {
                    return rejected(state, .scoreOverflow)
                }
                winnerAmounts[winner] = ownAmount
                deltas[winner] += Int64(ownAmount)
                deltas[payers[0]] -= Int64(ownAmount)
            }
        case .kong:
            let opponents = active.filter { !winners.contains($0) }
            let validPayers: Bool
            switch intent.paymentMode {
            case .onePayer: validPayers = payers.count == 1
            case .allOpponents: validPayers = Set(payers) == Set(opponents)
            case nil: validPayers = false
            }
            // 未提供杠种（hos 的「不在已知杠种内」）或通用模板下补杠均非法。
            let validKind = intent.kongKind != nil && (blood || intent.kongKind != .added)
            let validBloodPayment = !blood
                || intent.paymentMode == (intent.kongKind == .exposed ? .onePayer : .allOpponents)
            if winners.count != 1 || !validKind || !validPayers || !validBloodPayment {
                return rejected(state, .invalidKong)
            }
            for payer in payers {
                deltas[payer] -= Int64(amount)
                deltas[winners[0]] += Int64(amount)
            }
        case .transfer:
            if winners.count != 1 || payers.count != 1 { return rejected(state, .invalidTransfer) }
            deltas[winners[0]] += Int64(amount)
            deltas[payers[0]] -= Int64(amount)
        case .kongRefund:
            let ids = intent.refundEntryIds
            let refunded = state.ledger.flatMap { $0.refundEntryIds ?? [] }
            if winners.count != 0 || payers.count != 0 || ids.isEmpty || Set(ids).count != ids.count {
                return rejected(state, .invalidRefund)
            }
            for id in ids {
                guard let original = state.ledger.first(where: { $0.id == id }),
                      original.actionType == .kong,
                      original.handNumber == state.handNumber,
                      !refunded.contains(id),
                      !original.winnerIndexes.contains(where: { state.currentHandWinnerIndexes.contains($0) }) else {
                    return rejected(state, .invalidRefund)
                }
                for (index, value) in original.deltas.enumerated() where index < MAHJONG_PLAYER_COUNT {
                    deltas[index] -= Int64(value)
                }
            }
        case .draw:
            if !winners.isEmpty || !payers.isEmpty { return rejected(state, .invalidDraw) }
        case .adjustment, .notenPenalty, .flowerPigPenalty:
            if !winners.isEmpty || !payers.isEmpty { return rejected(state, .invalidPlayers) }
            guard let manual = intent.manualDeltas,
                  manual.count == MAHJONG_PLAYER_COUNT,
                  manual.contains(where: { $0 != 0 }) else {
                return rejected(state, .invalidAdjustment)
            }
            for (index, value) in manual.enumerated() { deltas[index] = Int64(value) }
            if intent.actionType != .adjustment, deltas.reduce(0, +) != 0 {
                return rejected(state, .penaltyNotZeroSum)
            }
        }

        let zeroSum = deltas.reduce(0, +) == 0
        if intent.actionType != .adjustment, !zeroSum { return rejected(state, .notZeroSum) }
        // 逐位落账必须全部在 Int32 内（hos `addSafely`）。
        var scoresAfter: [Int] = []
        var safeDeltas: [Int] = []
        for index in 0 ..< MAHJONG_PLAYER_COUNT {
            guard let delta = safeInt32(deltas[index]) else { return rejected(state, .scoreOverflow) }
            guard let value = safeInt32(Int64(state.scores[index]) + deltas[index]) else {
                return rejected(state, .scoreOverflow)
            }
            safeDeltas.append(delta)
            scoresAfter.append(value)
        }

        let winnersThisHand = mahjongDistinct(state.currentHandWinnerIndexes + (intent.actionType.isWin ? winners : []))
        if intent.endHand, intent.actionType != .draw,
           !(intent.actionType.isWin && (!blood || winnersThisHand.count >= 3)) {
            return rejected(state, .prematureEnd)
        }
        let completesHand = intent.actionType == .draw
            || (intent.actionType.isWin && (!blood || winnersThisHand.count >= 3))

        let entry = MahjongLedgerEntry(
            id: intent.operationId ?? "\(now)-\(state.ledger.count + 1)",
            timestamp: now,
            handNumber: state.handNumber,
            roundOrdinal: state.roundOrdinal,
            dealerIndex: state.dealerIndex,
            dealerStreak: state.dealerStreak,
            actionType: intent.actionType,
            winnerIndexes: winners,
            payerIndexes: payers,
            kongKind: intent.kongKind,
            paymentMode: intent.paymentMode,
            baseScore: state.setup.baseScore,
            factor: factor,
            resolvedAmount: amount,
            winnerFactors: intent.actionType == .discardWin
                ? (0 ..< MAHJONG_PLAYER_COUNT).map { index in
                    winners.contains(index) ? (intent.winnerFactors?[index] ?? factor) : 0
                }
                : nil,
            winnerAmounts: intent.actionType == .discardWin ? winnerAmounts : nil,
            refundEntryIds: intent.actionType == .kongRefund ? intent.refundEntryIds : nil,
            deltas: safeDeltas,
            scoresAfter: scoresAfter,
            completesHand: completesHand,
            zeroSum: zeroSum,
            note: intent.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return ReduceResult(state: applyEntry(state, entry), events: [.settlementRecorded(entry)], accepted: true)
    }

    /// hos `applyEntry`：流水入账并推进手数/轮庄。
    func applyEntry(_ state: MahjongSessionState, _ entry: MahjongLedgerEntry) -> MahjongSessionState {
        // v1 legacy 流水的 winnerIndexes 无条件并入本手和牌者（当年杠分也写在这里）；
        // v2 只有和牌类动作才写。
        let winners = mahjongDistinct(
            state.currentHandWinnerIndexes + ((entry.schemaVersion == 1 || entry.actionType.isWin) ? entry.winnerIndexes : [])
        )
        var next = state
        next.schemaVersion = MAHJONG_CONTRACT_VERSION
        next.scores = entry.scoresAfter
        next.currentHandWinnerIndexes = winners
        next.ledger = state.ledger + [entry]
        next.lastDeltas = entry.deltas
        guard entry.completesHand else { return next }

        let dealerStays = state.setup.dealerRule == .dealerWinOrDrawStays
            && (entry.actionType == .draw || winners.contains(state.dealerIndex))
        let nextRoundOrdinal = dealerStays ? state.roundOrdinal : state.roundOrdinal + 1
        next.handNumber = state.handNumber + 1
        next.roundOrdinal = nextRoundOrdinal
        next.dealerIndex = dealerStays ? state.dealerIndex : (state.dealerIndex + 1) % MAHJONG_PLAYER_COUNT
        next.dealerStreak = dealerStays ? state.dealerStreak + 1 : 1
        next.currentHandWinnerIndexes = []
        next.roundLimitReached = mahjongReachedRoundLimit(
            state.setup.matchLength,
            roundOrdinal: nextRoundOrdinal
        )
        return next
    }

    /// hos `MahjongReducer.undo`：丢掉最后一笔后整本台账重放，撤销是原子的。
    public func undo(_ state: MahjongSessionState) -> ReduceResult<MahjongSessionState, MahjongSessionEvent> {
        guard let removed = state.ledger.last else { return rejected(state, .nothingToUndo) }
        let replayed = restore(setup: state.setup, ledger: Array(state.ledger.dropLast()))
        // 台账重放失败（损坏/未知版本）时撤销不落地，避免半撤销状态。
        guard replayed.accepted else { return replayed }
        var next = replayed.state
        next.finished = false
        return ReduceResult(state: next, events: [.lastEntryUndone(removed)])
    }

    /// hos `MahjongReducer.restore`：台账是唯一真源。任何一条不合法（含未知 schemaVersion、
    /// 分数与增减不一致、id 重复）都整本失败，绝不静默产出错误总分。
    public func restore(setup: MahjongSetupResult, ledger: [MahjongLedgerEntry]) -> ReduceResult<MahjongSessionState, MahjongSessionEvent> {
        var restored = MahjongSessionState.initial(setup: setup)
        var ids: [String] = []
        for entry in ledger {
            if entry.schemaVersion != 1, entry.schemaVersion != MAHJONG_CONTRACT_VERSION {
                return ReduceResult(state: restored, accepted: false, reason: MahjongRejectReason.unsupportedVersion.rawValue)
            }
            let deltasMatchScores = entry.deltas.indices.contains(0)
                && entry.deltas.count == MAHJONG_PLAYER_COUNT
                && entry.scoresAfter.count == MAHJONG_PLAYER_COUNT
                && entry.deltas.enumerated().allSatisfy { index, delta in
                    restored.scores.indices.contains(index)
                        && restored.scores[index] + delta == entry.scoresAfter[index]
                }
            let badIndex = (entry.winnerIndexes + entry.payerIndexes)
                .contains(where: { !mahjongSeatRange.contains($0) })
            if entry.handNumber < 1 || entry.roundOrdinal < 0
                || !mahjongSeatRange.contains(entry.dealerIndex) || entry.dealerStreak < 1
                || ids.contains(entry.id) || !deltasMatchScores || badIndex {
                return ReduceResult(state: restored, accepted: false, reason: MahjongRejectReason.invalidLedger.rawValue)
            }
            ids.append(entry.id)
            restored.handNumber = entry.handNumber
            restored.roundOrdinal = entry.roundOrdinal
            restored.dealerIndex = entry.dealerIndex
            restored.dealerStreak = entry.dealerStreak
            restored = applyEntry(restored, entry)
        }
        return ReduceResult(state: restored, accepted: true)
    }

    /// hos 金额公式：通用 `底分 × 2^番`；血战按封顶番数取小。
    private func calculateAmount(state: MahjongSessionState, factor: Int) -> Int? {
        guard factor >= 0 else { return nil }
        let exponent = state.setup.ruleset == .generic
            ? factor
            : Swift.min(factor, state.setup.maxFan)
        return mahjongScaledAmount(baseScore: state.setup.baseScore, exponent: exponent)
    }

    private func rejected(
        _ state: MahjongSessionState,
        _ reason: MahjongRejectReason
    ) -> ReduceResult<MahjongSessionState, MahjongSessionEvent> {
        ReduceResult(state: state, accepted: false, reason: reason.rawValue)
    }

}

// MARK: - 表单（hos `MahjongFormState.ts`）

/// 结算表单草稿（hos `MahjongFormDraft`）。字符串字段保持 hos 的原始输入语义，
/// 由 `mahjongInteger` 在提交时统一解析，解析不过就不出意图。
public struct MahjongFormDraft: Equatable, Sendable {
    public var action: MahjongActionType
    public var winners: [Int]
    public var payer: Int
    public var fan: String
    public var winnerFans: [String]
    public var kongKind: MahjongKongKind
    public var payment: MahjongPaymentMode
    public var deltas: [String]
    public var refunds: [String]
    public var note: String
    public var otherFan: Bool
    public var dirty: Bool

    public init(
        action: MahjongActionType,
        winners: [Int],
        payer: Int,
        fan: String = "0",
        winnerFans: [String] = ["0", "0", "0", "0"],
        kongKind: MahjongKongKind = .exposed,
        payment: MahjongPaymentMode = .allOpponents,
        deltas: [String] = ["0", "0", "0", "0"],
        refunds: [String] = [],
        note: String = "",
        otherFan: Bool = false,
        dirty: Bool = false
    ) {
        self.action = action
        self.winners = winners
        self.payer = payer
        self.fan = fan
        self.winnerFans = winnerFans
        self.kongKind = kongKind
        self.payment = payment
        self.deltas = deltas
        self.refunds = refunds
        self.note = note
        self.otherFan = otherFan
        self.dirty = dirty
    }
}

/// hos `createMahjongForm`：默认选中首个活跃玩家为和牌者、次活跃为点炮者。
public func createMahjongForm(action: MahjongActionType, state: MahjongSessionState) -> MahjongFormDraft {
    let active = activeMahjongPlayers(state)
    return MahjongFormDraft(
        action: action,
        winners: Array(active.prefix(1)),
        payer: active.count > 1 ? active[1] : -1,
        payment: state.setup.ruleset == .sichuanBloodBattle ? .onePayer : .allOpponents
    )
}

/// hos `copyMahjongForm`：编辑必须先拷贝，标记 dirty（数组是值类型，天然不可变）。
public func copyMahjongForm(_ form: MahjongFormDraft) -> MahjongFormDraft {
    var next = form
    next.dirty = true
    return next
}

/// hos `mahjongFormIntent`。任一数字字段解析失败则返回 nil —— 对应 hos 里 NaN
/// 被 reducer 拒绝（例如 "4.2" 的手工增减），Swift 侧直接在表单层拦住。
public func mahjongFormIntent(_ form: MahjongFormDraft) -> MahjongSettlementIntent? {
    let manual = form.action.isManual
    let special = manual || form.action == .draw || form.action == .kongRefund
    let factor = special ? 0 : mahjongInteger(form.fan)
    let manualDeltas: [Int]?
    if manual {
        var parsed: [Int] = []
        for value in form.deltas {
            guard let delta = mahjongInteger(value, signed: true) else { return nil }
            parsed.append(delta)
        }
        manualDeltas = parsed
    } else {
        manualDeltas = nil
    }
    let winnerFactors: [Int]?
    if form.action == .discardWin {
        var factors: [Int] = []
        for value in form.winnerFans {
            guard let fan = mahjongInteger(value) else { return nil }
            factors.append(fan)
        }
        winnerFactors = factors
    } else {
        winnerFactors = nil
    }
    guard special ? true : factor != nil else { return nil }
    return MahjongSettlementIntent(
        actionType: form.action,
        winnerIndexes: special ? [] : form.winners,
        payerIndexes: form.action == .discardWin
            || (form.action == .kong && form.payment == .onePayer) ? [form.payer] : [],
        factor: factor ?? 0,
        winnerFactors: winnerFactors,
        refundEntryIds: form.action == .kongRefund ? form.refunds : [],
        kongKind: form.action == .kong ? form.kongKind : nil,
        paymentMode: form.action == .kong ? form.payment : nil,
        manualDeltas: manualDeltas,
        note: form.note
    )
}

/// hos `refundableMahjongEntries`：本手内未被退还、和牌者尚未和牌的杠分流水。
public func refundableMahjongEntries(
    _ state: MahjongSessionState
) -> [MahjongLedgerEntry] {
    var refunded: [String] = []
    for entry in state.ledger { refunded.append(contentsOf: entry.refundEntryIds ?? []) }
    return state.ledger.filter { entry in
        entry.actionType == .kong
            && entry.handNumber == state.handNumber
            && !refunded.contains(entry.id)
            && !entry.winnerIndexes.contains(where: { state.currentHandWinnerIndexes.contains($0) })
    }
}

/// hos `mahjongActionLabel`：结算表单与流水列表的动作名（zh 原文，与 hos 逐字相同）。
/// iOS 界面走本地化时用 `jifen` 侧的 `mahjongActionLocalizedLabel`。
public func mahjongActionLabel(_ action: MahjongActionType) -> String {
    switch action {
    case .selfDraw: return "自摸"
    case .discardWin: return "点炮"
    case .kong: return "杠分"
    case .draw: return "流局"
    case .notenPenalty: return "查叫"
    case .flowerPigPenalty: return "查花猪"
    case .kongRefund: return "退杠分"
    case .transfer: return "转分"
    case .adjustment: return "调分"
    }
}

/// hos `mahjongLedgerDescription`：一笔流水的一行描述。
public func mahjongLedgerDescription(_ entry: MahjongLedgerEntry, names: [String]) -> String {
    let label: String
    if entry.actionType == .kong {
        label = entry.kongKind == .added ? "补杠" : (entry.kongKind == .concealed ? "暗杠" : "明杠 / 直杠")
    } else {
        label = mahjongActionLabel(entry.actionType)
    }
    let winners = entry.winnerIndexes.map { index -> String in
        let name = names.indices.contains(index) ? names[index] : ""
        guard entry.actionType == .discardWin || entry.actionType == .selfDraw else { return name }
        let fan = entry.winnerFactors?[index] ?? entry.factor
        return "\(name) \(fan == 0 ? "无番" : "\(fan)番")"
    }.joined(separator: "、")
    let suffix = winners.isEmpty ? "" : " · \(winners)"
    let zeroSumSuffix = entry.zeroSum ? "" : " · 非零和"
    let noteSuffix = (entry.note?.isEmpty == false) ? " · \(entry.note!)" : ""
    return "\(label)\(suffix)\(zeroSumSuffix)\(noteSuffix)"
}

/// Android `mahjongRoundLabel`：投屏与标题用的局名（与 Android 逐字相同，保证 wire 一致）。
public func mahjongRoundLabel(roundOrdinal: Int) -> String {
    if roundOrdinal >= 4 * MAHJONG_PLAYER_COUNT { return "第\(roundOrdinal + 1)局" }
    let wind = ["东", "南", "西", "北"][max(0, roundOrdinal / 4)]
    return "\(wind)\(roundOrdinal % 4 + 1)局"
}

// MARK: - 投屏 sportState（Android `mahjongDisplaySportState`）

/// 麻将 sportState 的 wire 值形态。显示端只认这四种，app 侧一对一映射到
/// `ScoreboardDisplayValue`。
public enum MahjongSportValue: Equatable, Sendable {
    case integer(Int)
    case string(String)
    case strings([String])
    case integers([Int])
}

/// 麻将投屏键名表（顺序即写入顺序）。
/// `jifen/Core/CloudSync/DisplayStateWireCodec.swift` 的 sportState 白名单必须逐键包含这些键，
/// 否则投屏会静默丢字段；`Tests/JifenCoreTests/mahjong/mahjong-display-state-v1.json`
/// 是这份键集合的跨端 oracle。
public let mahjongDisplaySportStateKeys: [String] = [
    "mahjongProtocolVersion",
    "mahjongRuleset",
    "mahjongHandNumber",
    "mahjongRoundLabel",
    "mahjongDealerIndex",
    "mahjongDealerStreak",
    "mahjongSeatWinds",
    "mahjongLastDeltas",
    "mahjongHandWinnerIndexes",
    "mahjongBaseScore",
    "mahjongMaxFan",
    "mahjongCapScore",
]

/// 投屏/云同步显示端的麻将投影。键名与
/// `docs/fixtures/mahjong-display-state-v1.json` 的 `sportState` 逐一对应。
public struct MahjongDisplayProjection: Equatable, Sendable {
    public var protocolVersion: Int
    public var ruleset: String
    public var handNumber: Int
    public var roundLabel: String
    public var dealerIndex: Int
    public var dealerStreak: Int
    public var seatWinds: [String]
    public var lastDeltas: [Int]
    public var handWinnerIndexes: [Int]
    public var baseScore: Int
    public var maxFan: Int
    /// 仅血战模板有封顶分；通用模板为 nil（不写该键，对齐 Android `capScoreOrNull`）。
    public var capScore: Int?

    public init(state: MahjongSessionState) {
        protocolVersion = MAHJONG_CONTRACT_VERSION
        ruleset = state.setup.ruleset.rawValue
        handNumber = state.handNumber
        roundLabel = mahjongRoundLabel(roundOrdinal: state.roundOrdinal)
        dealerIndex = state.dealerIndex
        dealerStreak = state.dealerStreak
        seatWinds = mahjongSeatWindsForDealer(dealerIndex: state.dealerIndex)
        lastDeltas = state.lastDeltas
        handWinnerIndexes = state.currentHandWinnerIndexes
        baseScore = state.setup.baseScore
        maxFan = state.setup.maxFan
        capScore = state.setup.capScore
    }

    /// 按 wire 键名取值；`mahjongCapScore` 在无封顶模板下为 nil（调用方跳过该键）。
    public func value(for key: String) -> MahjongSportValue? {
        switch key {
        case "mahjongProtocolVersion": return .integer(protocolVersion)
        case "mahjongRuleset": return .string(ruleset)
        case "mahjongHandNumber": return .integer(handNumber)
        case "mahjongRoundLabel": return .string(roundLabel)
        case "mahjongDealerIndex": return .integer(dealerIndex)
        case "mahjongDealerStreak": return .integer(dealerStreak)
        case "mahjongSeatWinds": return .strings(seatWinds)
        case "mahjongLastDeltas": return .integers(lastDeltas)
        case "mahjongHandWinnerIndexes": return .integers(handWinnerIndexes)
        case "mahjongBaseScore": return .integer(baseScore)
        case "mahjongMaxFan": return .integer(maxFan)
        case "mahjongCapScore": return capScore.map { .integer($0) }
        default: return nil
        }
    }
}
