import CryptoKit
import Foundation
import ScoreCore
import SessionCore
import Testing

/// 麻将跨端契约 golden 测试。
///
/// 数据来源（已拷进本仓库 `Tests/JifenCoreTests/mahjong/`，测试期不引用兄弟仓库路径）：
/// - `mahjong-reducer-v2.json`：Android `app/src/test/resources/mahjong/` 同名夹具，
///   断言当前意图引擎逐字段复现 `expected`。
/// - `mahjong-reducer-v1.json`：legacy 夹具。v1 不是可写协议（血战下 endHand 会被
///   `premature_end` 拦住），只能作为台账原值重放，因此这里按 v1 语义手抄台账并断言
///   `restore` 复现 `expected`。
/// - `mahjong-display-state-v1.json`：Android `docs/fixtures/` 投屏夹具，
///   断言 `mahjong*` 键集合与本端 `mahjongDisplaySportStateKeys` 完全一致。
///
/// 其余行为断言逐条对齐 hos `scripts/test_mahjong_reducer_contract.mjs` 与
/// `entry/src/test/scoreboard/MahjongReducer.test.ets`。

private struct Fixture: Decodable {
    struct Setup: Decodable {
        var ruleset: String
        var startScore: Int
        var baseScore: Int
        var initialDealerIndex: Int
        var matchLength: String
        var dealerRule: String
        var maxFan: Int
    }

    struct Intent: Decodable {
        var at: Int
        var actionType: String
        var winnerIndexes: [Int]
        var payerIndexes: [Int]
        var factor: Int
        var kongKind: String?
        var paymentMode: String?
        var endHand: Bool
    }

    struct Expected: Decodable {
        var scores: [Int]
        var handNumber: Int
        var roundOrdinal: Int
        var dealerIndex: Int
        var dealerStreak: Int
        var currentHandWinnerIndexes: [Int]
        var ledgerSize: Int
    }

    var schemaVersion: Int
    var setup: Setup
    var intents: [Intent]
    var expected: Expected
}

private struct DisplayFixture: Decodable {
    var gameType: String
    var layoutKind: String
    var sportState: [String: JsonValue]
}

/// sportState 的宽松 JSON 值（夹具里混合了 Int / String / [String] / [Int] / Bool）。
private enum JsonValue: Decodable, Equatable {
    case integer(Int)
    case string(String)
    case strings([String])
    case integers([Int])
    case bool(Bool)
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .other; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Int.self) { self = .integer(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([String].self) { self = .strings(value); return }
        if let value = try? container.decode([Int].self) { self = .integers(value); return }
        self = .other
    }
}

private func loadFixture(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "mahjong") else {
        throw CocoaError(.fileNoSuchFile)
    }
    return try Data(contentsOf: url)
}

private func loadReducerFixture(_ name: String) throws -> Fixture {
    try JSONDecoder().decode(Fixture.self, from: try loadFixture(name))
}

private func setup(from fixture: Fixture) -> MahjongSetupResult {
    MahjongSetupResult(
        schemaVersion: fixture.schemaVersion,
        ruleset: MahjongRuleset(rawValue: fixture.setup.ruleset) ?? .generic,
        startScore: fixture.setup.startScore,
        baseScore: fixture.setup.baseScore,
        initialDealerIndex: fixture.setup.initialDealerIndex,
        matchLength: MahjongMatchLength(rawValue: fixture.setup.matchLength) ?? .free,
        dealerRule: MahjongDealerRule(rawValue: fixture.setup.dealerRule) ?? .rotateEachHand,
        maxFan: fixture.setup.maxFan
    )
}

private func intent(from raw: Fixture.Intent) -> MahjongSettlementIntent {
    MahjongSettlementIntent(
        actionType: MahjongActionType(rawValue: raw.actionType) ?? .adjustment,
        winnerIndexes: raw.winnerIndexes,
        payerIndexes: raw.payerIndexes,
        factor: raw.factor,
        kongKind: raw.kongKind.flatMap { MahjongKongKind(rawValue: $0) },
        paymentMode: raw.paymentMode.flatMap { MahjongPaymentMode(rawValue: $0) },
        endHand: raw.endHand
    )
}

private func assertExpected(_ state: MahjongSessionState, _ expected: Fixture.Expected) {
    #expect(state.scores == expected.scores)
    #expect(state.handNumber == expected.handNumber)
    #expect(state.roundOrdinal == expected.roundOrdinal)
    #expect(state.dealerIndex == expected.dealerIndex)
    #expect(state.dealerStreak == expected.dealerStreak)
    #expect(state.currentHandWinnerIndexes == expected.currentHandWinnerIndexes)
    #expect(state.ledger.count == expected.ledgerSize)
}

// MARK: - 夹具同源性

/// 这三份 JSON 是跨端 golden 数据，必须与 Android 仓库里的原件逐字节一致；
/// 一旦有人在 iOS 侧单独改动夹具，本断言立刻变红（sha256 取原件实算值）。
@Test func mahjongFixturesAreTheAndroidGoldenCopies() throws {
    let expectedSHA256: [String: String] = [
        "mahjong-reducer-v1": "8654e84b6c0edae3d45e4f706a4a6de8ad8023cd76c0751123135319a7cca24e",
        "mahjong-reducer-v2": "f6bad19dd9d809a1466888ed61f5cfdf039eaf767d5180b9ea04211ada1e3c79",
        "mahjong-display-state-v1": "39426a6b75143a2acd4c68b75f08c880cd056bc2e8af87e9a032176215fbe10d",
    ]
    for (name, digest) in expectedSHA256 {
        let data = try loadFixture(name)
        #expect(mahjongSHA256(data) == digest, "\(name).json 与 Android 原件不一致")
    }
}

private func mahjongSHA256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

// MARK: - v2：意图引擎逐字段复现

@Test func mahjongV2FixtureReplayedThroughIntentsMatchesExpectedExactly() throws {
    let fixture = try loadReducerFixture("mahjong-reducer-v2")
    #expect(fixture.schemaVersion == MAHJONG_CONTRACT_VERSION)
    var state = MahjongSessionState.initial(setup: setup(from: fixture))
    let reducer = MahjongReducer()

    for raw in fixture.intents {
        let result = reducer.reduce(state: state, intent: .recordSettlement(intent(from: raw)), at: Int64(raw.at))
        // 夹具里的每一步都必须是可接受的，否则 golden 失效。
        #expect(result.accepted, "intent \(raw.actionType) 被拒绝：\(result.reason ?? "?")")
        state = result.state
    }
    assertExpected(state, fixture.expected)
    // 血战下只有 2 名和牌者，本手未结束；杠分不计入和牌者。
    #expect(state.ledger.allSatisfy { !$0.completesHand })
}

@Test func mahjongV2FixtureMatchesHandsetGoldenValues() throws {
    let fixture = try loadReducerFixture("mahjong-reducer-v2")
    #expect(fixture.expected.scores == [-20, 4, 60, -44])
    #expect(fixture.expected.currentHandWinnerIndexes == [1, 2])
    #expect(fixture.expected.ledgerSize == 3)
    #expect(fixture.setup.ruleset == MahjongRuleset.sichuanBloodBattle.rawValue)
}

@Test func mahjongV2FixtureLedgerDeltasAndScoresAfterAreInternallyConsistent() throws {
    let fixture = try loadReducerFixture("mahjong-reducer-v2")
    var state = MahjongSessionState.initial(setup: setup(from: fixture))
    let reducer = MahjongReducer()
    for raw in fixture.intents {
        state = reducer.reduce(state: state, intent: .recordSettlement(intent(from: raw)), at: Int64(raw.at)).state
    }
    var running = [Int](repeating: state.setup.startScore, count: MAHJONG_PLAYER_COUNT)
    for entry in state.ledger {
        #expect(entry.deltas.count == MAHJONG_PLAYER_COUNT)
        #expect(entry.scoresAfter.count == MAHJONG_PLAYER_COUNT)
        for index in 0 ..< MAHJONG_PLAYER_COUNT {
            running[index] += entry.deltas[index]
            #expect(running[index] == entry.scoresAfter[index], "\(entry.id) 第 \(index) 位增减与总分不符")
        }
        // 台账自证零和性（调分是唯一非零和出口，夹具里没有调分）。
        #expect(entry.zeroSum == (entry.deltas.reduce(0, +) == 0))
    }
    #expect(running == fixture.expected.scores)
}

// MARK: - v1：legacy 台账原值重放

/// 按 v1 语义手抄的 legacy 台账（金额来自 v1 当年规则，与今天的意图引擎不同口径）：
/// 1. 暗杠 factor 1：每家付 底分×2^1 = 4 → [12,-4,-4,-4]，本手未结束；
/// 2. 点炮 factor 2：2×2^2 = 8 → [0,8,0,-8]，本手未结束；
/// 3. 自摸 factor 4：2×2^4 = 32，三家各付 → [-32,-32,96,-32]，v1 直接 endHand → 结束本手。
/// 三笔累计 [-20,-28,92,-44]，与夹具 `expected.scores` 一致。
private func legacyV1Ledger() -> [MahjongLedgerEntry] {
    [
        MahjongLedgerEntry(
            schemaVersion: 1, id: "v1-1", timestamp: 1, handNumber: 1, roundOrdinal: 0,
            dealerIndex: 0, dealerStreak: 1, actionType: .kong,
            winnerIndexes: [0], payerIndexes: [1, 2, 3],
            kongKind: .concealed, paymentMode: .allOpponents,
            baseScore: 2, factor: 1, resolvedAmount: 4,
            deltas: [12, -4, -4, -4], scoresAfter: [12, -4, -4, -4],
            completesHand: false, zeroSum: true
        ),
        MahjongLedgerEntry(
            schemaVersion: 1, id: "v1-2", timestamp: 2, handNumber: 1, roundOrdinal: 0,
            dealerIndex: 0, dealerStreak: 1, actionType: .discardWin,
            winnerIndexes: [1], payerIndexes: [3],
            baseScore: 2, factor: 2, resolvedAmount: 8,
            deltas: [0, 8, 0, -8], scoresAfter: [12, 4, -4, -12],
            completesHand: false, zeroSum: true
        ),
        MahjongLedgerEntry(
            schemaVersion: 1, id: "v1-3", timestamp: 3, handNumber: 1, roundOrdinal: 0,
            dealerIndex: 0, dealerStreak: 1, actionType: .selfDraw,
            winnerIndexes: [2], payerIndexes: [0, 1, 3],
            baseScore: 2, factor: 4, resolvedAmount: 32,
            deltas: [-32, -32, 96, -32], scoresAfter: [-20, -28, 92, -44],
            completesHand: true, zeroSum: true
        ),
    ]
}

@Test func mahjongV1LegacyLedgerRestoresVerbatimWithoutRecomputingAmounts() throws {
    let fixture = try loadReducerFixture("mahjong-reducer-v1")
    #expect(fixture.schemaVersion == 1)
    // v1 与 v2 夹具总分不同：证明 v1 只能按 legacy 台账原值恢复，不能用今天的意图重算。
    #expect(fixture.expected.scores == [-20, -28, 92, -44])
    let v2Scores = try loadReducerFixture("mahjong-reducer-v2").expected.scores
    #expect(fixture.expected.scores != v2Scores)

    let reducer = MahjongReducer()
    let restored = reducer.restore(setup: setup(from: fixture), ledger: legacyV1Ledger())
    #expect(restored.accepted, "legacy 台账重放失败：\(restored.reason ?? "?")")
    assertExpected(restored.state, fixture.expected)
    // 重放必须逐笔沿用台账里的 scoresAfter，绝不重算金额。
    var running = [Int](repeating: fixture.setup.startScore, count: MAHJONG_PLAYER_COUNT)
    for entry in restored.state.ledger {
        for index in 0 ..< MAHJONG_PLAYER_COUNT { running[index] += entry.deltas[index] }
        #expect(running == entry.scoresAfter)
    }
    #expect(restored.state.schemaVersion == MAHJONG_CONTRACT_VERSION)
}

@Test func mahjongV1IntentsCannotBeRewrittenByTodayEngine() throws {
    let fixture = try loadReducerFixture("mahjong-reducer-v1")
    let reducer = MahjongReducer()
    var state = MahjongSessionState.initial(setup: setup(from: fixture))
    var acceptedCount = 0
    var lastReason: String?
    for raw in fixture.intents {
        let result = reducer.reduce(state: state, intent: .recordSettlement(intent(from: raw)), at: Int64(raw.at))
        if result.accepted {
            acceptedCount += 1
            state = result.state
        } else {
            lastReason = result.reason
        }
    }
    // 最后一笔带 endHand，血战下不足 3 家 → 今天的引擎必须拒绝，而不是静默改成 v2 结果。
    #expect(acceptedCount == 2)
    #expect(lastReason == MahjongRejectReason.prematureEnd.rawValue)
    #expect(state.scores != fixture.expected.scores)
}

// MARK: - hos 契约行为清单

@Test func mahjongReducerRejectsDuplicateOperationId() {
    let reducer = MahjongReducer()
    var state = MahjongSessionState.initial(setup: .sichuanBloodBattle())
    let settlement = MahjongSettlementIntent(
        actionType: .discardWin,
        operationId: "op-1",
        winnerIndexes: [1],
        payerIndexes: [3],
        factor: 2
    )
    let first = reducer.reduce(state: state, intent: .recordSettlement(settlement), at: 1)
    #expect(first.accepted)
    state = first.state
    let second = reducer.reduce(state: state, intent: .recordSettlement(settlement), at: 2)
    #expect(!second.accepted)
    #expect(second.reason == MahjongRejectReason.duplicateOperation.rawValue)
    #expect(second.state.ledger.count == 1)
    // 新 operationId 仍可入账。
    let third = reducer.reduce(state: state, intent: .recordSettlement(MahjongSettlementIntent(
        actionType: .discardWin, operationId: "op-2", winnerIndexes: [2], payerIndexes: [0], factor: 1
    )), at: 3)
    #expect(third.accepted)
    #expect(third.state.ledger.map(\.id) == ["op-1", "op-2"])
}

@Test func mahjongReducerUndoIsAtomicAndRestoresPreviousHandState() {
    let reducer = MahjongReducer()
    var state = MahjongSessionState.initial(setup: .sichuanBloodBattle())
    let steps: [MahjongSettlementIntent] = [
        MahjongSettlementIntent(actionType: .kong, winnerIndexes: [0], factor: 1,
                                kongKind: .concealed, paymentMode: .allOpponents),
        MahjongSettlementIntent(actionType: .discardWin, winnerIndexes: [1], payerIndexes: [3], factor: 2),
        MahjongSettlementIntent(actionType: .discardWin, winnerIndexes: [2], payerIndexes: [0], factor: 3),
    ]
    for (index, step) in steps.enumerated() {
        let result = reducer.reduce(state: state, intent: .recordSettlement(step), at: Int64(index + 1))
        #expect(result.accepted, "第 \(index + 1) 笔被拒绝：\(result.reason ?? "?")")
        state = result.state
    }
    let beforeUndo = state
    #expect(beforeUndo.ledger.count == 3)

    let undone = reducer.reduce(state: state, intent: .undoLast, at: 99)
    #expect(undone.accepted)
    state = undone.state
    #expect(state.ledger.count == 2)
    #expect(state.ledger.map(\.id) == beforeUndo.ledger.dropLast().map(\.id))
    // 重放得到的状态必须与「只跑前两笔」完全一致。
    var replayed = MahjongSessionState.initial(setup: beforeUndo.setup)
    for (index, step) in steps.prefix(2).enumerated() {
        replayed = reducer.reduce(state: replayed, intent: .recordSettlement(step), at: Int64(index + 1)).state
    }
    #expect(state == replayed)

    // 逐笔撤销回开局。
    for _ in 0 ..< 4 {
        guard !state.ledger.isEmpty else { break }
        let step = reducer.reduce(state: state, intent: .undoLast, at: 100)
        #expect(step.accepted, "撤销失败：\(step.reason ?? "?")")
        state = step.state
    }
    #expect(state.scores == [0, 0, 0, 0])
    #expect(state.handNumber == 1)
    #expect(state.roundOrdinal == 0)
    #expect(state.dealerStreak == 1)
    #expect(state.currentHandWinnerIndexes == [])
    #expect(state.lastDeltas == [0, 0, 0, 0])
    let empty = reducer.reduce(state: state, intent: .undoLast, at: 101)
    #expect(!empty.accepted)
    #expect(empty.reason == MahjongRejectReason.nothingToUndo.rawValue)
}

@Test func mahjongRestoreFailsExplicitlyOnUnknownVersionAndCorruptLedger() {
    let reducer = MahjongReducer()
    let setup = MahjongSetupResult.sichuanBloodBattle()
    let entry = MahjongLedgerEntry(
        id: "e1", timestamp: 1, handNumber: 1, roundOrdinal: 0, dealerIndex: 0, dealerStreak: 1,
        actionType: .discardWin, winnerIndexes: [1], payerIndexes: [3], baseScore: 2, factor: 2,
        resolvedAmount: 8, deltas: [-8, 8, 0, 0], scoresAfter: [-8, 8, 0, 0],
        completesHand: false, zeroSum: true
    )
    // 未知 schemaVersion：整本失败，绝不静默产出错误总分。
    var unknownVersion = entry
    unknownVersion.schemaVersion = 99
    let badVersion = reducer.restore(setup: setup, ledger: [unknownVersion])
    #expect(!badVersion.accepted)
    #expect(badVersion.reason == MahjongRejectReason.unsupportedVersion.rawValue)

    // 增减与总分不符。
    var mismatched = entry
    mismatched.scoresAfter = [-8, 9, 0, 0]
    let badMath = reducer.restore(setup: setup, ledger: [mismatched])
    #expect(!badMath.accepted)
    #expect(badMath.reason == MahjongRejectReason.invalidLedger.rawValue)

    // 流水 id 重复。
    let duplicated = reducer.restore(setup: setup, ledger: [entry, entry])
    #expect(!duplicated.accepted)
    #expect(duplicated.reason == MahjongRejectReason.invalidLedger.rawValue)

    // 越界庄家 / 连庄数 < 1 / 手数 < 1 / 座位越界。
    var badDealer = entry
    badDealer.dealerIndex = 7
    #expect(reducer.restore(setup: setup, ledger: [badDealer]).reason == MahjongRejectReason.invalidLedger.rawValue)
    var badStreak = entry
    badStreak.dealerStreak = 0
    #expect(reducer.restore(setup: setup, ledger: [badStreak]).reason == MahjongRejectReason.invalidLedger.rawValue)
    var badHand = entry
    badHand.handNumber = 0
    #expect(reducer.restore(setup: setup, ledger: [badHand]).reason == MahjongRejectReason.invalidLedger.rawValue)
    var badSeat = entry
    badSeat.payerIndexes = [9]
    #expect(reducer.restore(setup: setup, ledger: [badSeat]).reason == MahjongRejectReason.invalidLedger.rawValue)

    // 正常 legacy 台账（v1）与当前版本（v2）都可重放。
    #expect(reducer.restore(setup: setup, ledger: [entry]).accepted)
    var v1 = entry
    v1.schemaVersion = 1
    #expect(reducer.restore(setup: setup, ledger: [v1]).accepted)
    // 撤销遇到损坏台账时不落地，避免半撤销状态。
    let second = MahjongLedgerEntry(
        id: "e2", timestamp: 2, handNumber: 1, roundOrdinal: 0, dealerIndex: 0, dealerStreak: 1,
        actionType: .draw, baseScore: 2, factor: 0, resolvedAmount: 0,
        deltas: [0, 0, 0, 0], scoresAfter: [-8, 8, 0, 0], completesHand: true, zeroSum: true
    )
    let live = reducer.restore(setup: setup, ledger: [entry, second]).state
    #expect(live.ledger.count == 2)
    var corrupted = live
    corrupted.ledger[0].scoresAfter = [999, 999, 999, 999]
    let undoOverCorrupt = reducer.reduce(state: corrupted, intent: .undoLast, at: 3)
    #expect(!undoOverCorrupt.accepted)
    #expect(undoOverCorrupt.reason == MahjongRejectReason.invalidLedger.rawValue)
    #expect(undoOverCorrupt.events.isEmpty)
    // 拒绝的结果不会被会话落库（见 ScoreSessionCore 的 accepted 分支）。
}

@Test func mahjongIntegerParserAcceptsAndRejectsExactSet() {
    // 拒绝：hos/Android 侧会算出 NaN 或非法数字的输入。
    for rejected in ["", "   ", "1.5", "2x", "--1", "1e2", "0x10", "１２", "+-4", "4-", "abc"] {
        #expect(mahjongInteger(rejected) == nil, "\(rejected) 不该被解析")
        #expect(mahjongInteger(rejected, signed: true) == nil, "signed \(rejected) 不该被解析")
    }
    // 接受：含带符号输入（手工增减用 signed）。
    #expect(mahjongInteger("0") == 0)
    #expect(mahjongInteger("12") == 12)
    #expect(mahjongInteger(" 7 ") == 7)
    #expect(mahjongInteger("007") == 7)
    #expect(mahjongInteger("+4", signed: true) == 4)
    #expect(mahjongInteger("-4", signed: true) == -4)
    #expect(mahjongInteger("-4") == nil)
    #expect(mahjongInteger("+4") == nil)
    #expect(mahjongInteger(nil) == nil)
    // 表单层：脏输入不出意图（对应 hos 的 NaN 拒绝）。
    var state = MahjongSessionState.initial(setup: .sichuanBloodBattle())
    state.scores = [0, 0, 0, 0]
    let form = createMahjongForm(action: .discardWin, state: state)
    let parsed = mahjongFormIntent(form)
    #expect(parsed != nil)
    #expect(parsed?.actionType == .discardWin)
    #expect(parsed?.winnerIndexes == [0])
    #expect(parsed?.payerIndexes == [1])
    #expect(parsed?.winnerFactors == [0, 0, 0, 0])
    var brokenFan = copyMahjongForm(form)
    brokenFan.fan = "4.2"
    #expect(mahjongFormIntent(brokenFan) == nil)
    #expect(brokenFan.dirty)
    var brokenWinnerFan = copyMahjongForm(form)
    brokenWinnerFan.winnerFans = ["0", "x", "0", "0"]
    #expect(mahjongFormIntent(brokenWinnerFan) == nil)
}

@Test func mahjongSelfDrawAndBloodThreeWinnerHandClosure() {
    let reducer = MahjongReducer()
    // 通用模板：底分 1、2 番自摸 → 三家各付 4，和牌者 +12，和牌即结束本手并轮庄。
    let generic = MahjongSetupResult.generic()
    let drawn = reducer.record(
        MahjongSessionState.initial(setup: generic),
        MahjongSettlementIntent(actionType: .selfDraw, winnerIndexes: [0], factor: 2),
        now: 1
    )
    #expect(drawn.accepted)
    let entry = drawn.state.ledger[0]
    #expect(entry.deltas == [12, -4, -4, -4])
    #expect(entry.scoresAfter == [12, -4, -4, -4])
    #expect(entry.completesHand)
    #expect(drawn.state.handNumber == 2)
    #expect(drawn.state.roundOrdinal == 1)
    #expect(drawn.state.dealerIndex == 1)
    #expect(drawn.state.dealerStreak == 1)
    #expect(drawn.state.currentHandWinnerIndexes == [])
    #expect(drawn.state.lastDeltas == [12, -4, -4, -4])

    // 血战：第 3 名不同和牌者才结束本手；杠分不计入和牌者。
    var blood = MahjongSessionState.initial(setup: .sichuanBloodBattle())
    blood = reducer.record(blood, MahjongSettlementIntent(
        actionType: .kong, winnerIndexes: [0], factor: 1, kongKind: .concealed, paymentMode: .allOpponents
    ), now: 1).state
    #expect(blood.currentHandWinnerIndexes == [])
    #expect(blood.ledger[0].deltas == [12, -4, -4, -4])
    #expect(blood.ledger[0].resolvedAmount == 4)
    blood = reducer.record(blood, MahjongSettlementIntent(
        actionType: .discardWin, winnerIndexes: [1], payerIndexes: [3], factor: 2
    ), now: 2).state
    #expect(blood.currentHandWinnerIndexes == [1])
    #expect(!blood.ledger[1].completesHand)
    blood = reducer.record(blood, MahjongSettlementIntent(
        actionType: .selfDraw, winnerIndexes: [2], factor: 4
    ), now: 3).state
    #expect(blood.currentHandWinnerIndexes == [1, 2])
    #expect(blood.scores == [-20, 4, 60, -44])
    #expect(blood.handNumber == 1)
    // 已和牌的玩家在本手内是「非活跃」座位，不能再参与。
    let alreadyWon = reducer.record(blood, MahjongSettlementIntent(
        actionType: .discardWin, winnerIndexes: [1], payerIndexes: [0], factor: 1
    ), now: 4)
    #expect(!alreadyWon.accepted)
    #expect(alreadyWon.reason == MahjongRejectReason.inactivePlayer.rawValue)
    // 第 3 家点和 → 结束本手。
    let thirdWinner = reducer.record(blood, MahjongSettlementIntent(
        actionType: .discardWin, winnerIndexes: [3], payerIndexes: [0], factor: 0
    ), now: 5)
    #expect(thirdWinner.accepted)
    #expect(thirdWinner.state.ledger.last?.completesHand == true)
    #expect(thirdWinner.state.currentHandWinnerIndexes == [])
    #expect(thirdWinner.state.handNumber == 2)
    #expect(thirdWinner.state.dealerIndex == 1)

    // 不足 3 家就 endHand → premature_end。
    let premature = reducer.record(MahjongSessionState.initial(setup: .sichuanBloodBattle()),
                                   MahjongSettlementIntent(
                                       actionType: .discardWin, winnerIndexes: [1], payerIndexes: [3],
                                       factor: 1, endHand: true
                                   ), now: 6)
    #expect(!premature.accepted)
    #expect(premature.reason == MahjongRejectReason.prematureEnd.rawValue)
    // 流局无论血战都结束本手。
    let drew = reducer.record(blood, MahjongSettlementIntent(actionType: .draw), now: 7)
    #expect(drew.accepted)
    #expect(drew.state.ledger.last?.completesHand == true)
    #expect(drew.state.handNumber == 2)
}

@Test func mahjongBloodBattleCapAndAmountFormulas() {
    let reducer = MahjongReducer()
    let blood = MahjongSetupResult.sichuanBloodBattle()
    #expect(blood.capScore == 32)
    #expect(MahjongSetupResult.generic().capScore == nil)
    #expect(MahjongSetupResult(baseScore: 2, maxFan: 30).capScore == nil)
    // 血战按封顶取小：8 番仍是 2×2^4=32。
    let capped = reducer.record(
        MahjongSessionState.initial(setup: blood),
        MahjongSettlementIntent(actionType: .discardWin, winnerIndexes: [1], payerIndexes: [3], factor: 8),
        now: 1
    )
    #expect(capped.accepted)
    #expect(capped.state.ledger[0].deltas == [0, 32, 0, -32])
    #expect(capped.state.ledger[0].resolvedAmount == 32)
    // 通用模板不封顶：超出可表示范围时按溢出拒绝。
    let huge = reducer.record(
        MahjongSessionState.initial(setup: MahjongSetupResult(baseScore: 1, maxFan: 30)),
        MahjongSettlementIntent(actionType: .discardWin, winnerIndexes: [1], payerIndexes: [3], factor: 40),
        now: 1
    )
    #expect(!huge.accepted)
    #expect(huge.reason == MahjongRejectReason.scoreOverflow.rawValue)
    // 一炮多响：逐位番数独立结算。
    let multi = reducer.record(
        MahjongSessionState.initial(setup: blood),
        MahjongSettlementIntent(actionType: .discardWin, winnerIndexes: [1, 2, 3], payerIndexes: [0],
                                factor: 0, winnerFactors: [0, 1, 2, 4]),
        now: 1
    )
    #expect(multi.accepted)
    // 1 番 4 + 2 番 8 + 4 番 32 = 44 由点炮者独付。
    #expect(multi.state.ledger[0].deltas == [-44, 4, 8, 32])
    #expect(multi.state.ledger[0].winnerFactors == [0, 1, 2, 4])
    #expect(multi.state.ledger[0].winnerAmounts == [0, 4, 8, 32])
    #expect(multi.state.ledger[0].completesHand)
    let badWinnerFactors = reducer.record(
        MahjongSessionState.initial(setup: blood),
        MahjongSettlementIntent(actionType: .discardWin, winnerIndexes: [1], payerIndexes: [0],
                                factor: 0, winnerFactors: [1, 2]),
        now: 2
    )
    #expect(badWinnerFactors.reason == MahjongRejectReason.invalidFactor.rawValue)
    // 补杠（added）只在血战存在，固定分为底分×1；暗杠/明杠为底分×2。
    let addedGeneric = reducer.record(
        MahjongSessionState.initial(setup: MahjongSetupResult.generic()),
        MahjongSettlementIntent(actionType: .kong, winnerIndexes: [0], factor: 0,
                               kongKind: .added, paymentMode: .allOpponents),
        now: 3
    )
    #expect(!addedGeneric.accepted)
    #expect(addedGeneric.reason == MahjongRejectReason.invalidKong.rawValue)
    let addedBlood = reducer.record(
        MahjongSessionState.initial(setup: blood),
        MahjongSettlementIntent(actionType: .kong, winnerIndexes: [0], factor: 0,
                               kongKind: .added, paymentMode: .allOpponents),
        now: 4
    )
    #expect(addedBlood.accepted)
    #expect(addedBlood.state.ledger[0].deltas == [6, -2, -2, -2])
    // 血战直杠必须一家付；缺 paymentMode / 缺杠种同样拒绝。
    let exposedAll = reducer.record(
        MahjongSessionState.initial(setup: blood),
        MahjongSettlementIntent(actionType: .kong, winnerIndexes: [0], factor: 0,
                               kongKind: .exposed, paymentMode: .allOpponents),
        now: 5
    )
    #expect(exposedAll.reason == MahjongRejectReason.invalidKong.rawValue)
    let noKind = reducer.record(
        MahjongSessionState.initial(setup: blood),
        MahjongSettlementIntent(actionType: .kong, winnerIndexes: [0], payerIndexes: [1], factor: 0,
                                paymentMode: .onePayer),
        now: 6
    )
    #expect(noKind.reason == MahjongRejectReason.invalidKong.rawValue)
    // 一家付/自摸/点炮的 4 家总额都必须零和；调分是唯一例外。
    let adjustment = reducer.record(
        MahjongSessionState.initial(setup: blood),
        MahjongSettlementIntent(actionType: .adjustment, manualDeltas: [10, 0, 0, 0]),
        now: 7
    )
    #expect(adjustment.accepted)
    #expect(adjustment.state.ledger[0].zeroSum == false)
    let allZeroManual = reducer.record(
        MahjongSessionState.initial(setup: blood),
        MahjongSettlementIntent(actionType: .adjustment, manualDeltas: [0, 0, 0, 0]),
        now: 8
    )
    #expect(allZeroManual.reason == MahjongRejectReason.invalidAdjustment.rawValue)
    let penalty = reducer.record(
        MahjongSessionState.initial(setup: blood),
        MahjongSettlementIntent(actionType: .notenPenalty, manualDeltas: [10, 0, 0, 0]),
        now: 9
    )
    #expect(!penalty.accepted)
    #expect(penalty.reason == MahjongRejectReason.penaltyNotZeroSum.rawValue)
    // 查叫/查花猪/退杠分只在血战模板下存在。
    let notInGeneric = reducer.record(
        MahjongSessionState.initial(setup: MahjongSetupResult.generic()),
        MahjongSettlementIntent(actionType: .notenPenalty, manualDeltas: [5, -5, 0, 0]),
        now: 10
    )
    #expect(!notInGeneric.accepted)
    #expect(notInGeneric.reason == MahjongRejectReason.invalidAction.rawValue)
    // 手工增减脏输入在表单层就拦住。
    var manualForm = createMahjongForm(action: .adjustment, state: MahjongSessionState.initial(setup: blood))
    manualForm.deltas = ["10", "-5", "-5", "0"]
    #expect(mahjongFormIntent(manualForm)?.manualDeltas == [10, -5, -5, 0])
    #expect(mahjongFormIntent(manualForm)?.winnerIndexes == [])
    var badManual = copyMahjongForm(manualForm)
    badManual.deltas = ["10", "x", "-5", "-5"]
    #expect(mahjongFormIntent(badManual) == nil)
}

@Test func mahjongKongRefundReversesOriginalKongDeltas() {
    let reducer = MahjongReducer()
    let setup = MahjongSetupResult.sichuanBloodBattle(playerNames: ["阿哲", "小雨", "老周", "安安"])
    var state = MahjongSessionState.initial(setup: setup)
    let kong = reducer.record(state, MahjongSettlementIntent(
        actionType: .kong, operationId: "kong-1", winnerIndexes: [0], factor: 0,
        kongKind: .concealed, paymentMode: .allOpponents
    ), now: 1)
    #expect(kong.accepted)
    state = kong.state
    #expect(state.ledger[0].deltas == [12, -4, -4, -4])
    #expect(refundableMahjongEntries(state).map(\.id) == ["kong-1"])

    let refund = reducer.record(state, MahjongSettlementIntent(
        actionType: .kongRefund, refundEntryIds: ["kong-1"]
    ), now: 2)
    #expect(refund.accepted)
    #expect(refund.state.ledger.last?.deltas == [-12, 4, 4, 4])
    #expect(refund.state.ledger.last?.refundEntryIds == ["kong-1"])
    #expect(refund.state.scores == [0, 0, 0, 0])
    #expect(refundableMahjongEntries(refund.state).isEmpty)
    // 重复退还与未知 id 都要拒绝。
    let twice = reducer.record(refund.state, MahjongSettlementIntent(
        actionType: .kongRefund, refundEntryIds: ["kong-1"]
    ), now: 3)
    #expect(!twice.accepted)
    #expect(twice.reason == MahjongRejectReason.invalidRefund.rawValue)
    let unknown = reducer.record(refund.state, MahjongSettlementIntent(
        actionType: .kongRefund, refundEntryIds: ["nope"]
    ), now: 4)
    #expect(!unknown.accepted)
    #expect(unknown.reason == MahjongRejectReason.invalidRefund.rawValue)
    // 退款动作不接受座位选择。
    let withSeats = reducer.record(state, MahjongSettlementIntent(
        actionType: .kongRefund, winnerIndexes: [0], refundEntryIds: ["kong-1"]
    ), now: 5)
    #expect(withSeats.reason == MahjongRejectReason.invalidRefund.rawValue)
    // 和牌者的杠分不可退（该玩家已进入本手和牌集合）。
    var afterWin = reducer.record(state, MahjongSettlementIntent(
        actionType: .discardWin, winnerIndexes: [1], payerIndexes: [3], factor: 1
    ), now: 6).state
    afterWin = reducer.record(afterWin, MahjongSettlementIntent(
        actionType: .discardWin, winnerIndexes: [2], payerIndexes: [3], factor: 1
    ), now: 7).state
    // 此时和牌集合 [1,2]，kong-1 的赢家 0 未和牌 → 仍可退。
    #expect(refundableMahjongEntries(afterWin).map(\.id) == ["kong-1"])
    let dealerWon = reducer.record(afterWin, MahjongSettlementIntent(
        actionType: .selfDraw, winnerIndexes: [0], factor: 1
    ), now: 8).state
    // 第 3 家和牌 → 本手结束并清空和牌集合，杠分也因跨手不可退。
    #expect(dealerWon.currentHandWinnerIndexes == [])
    #expect(dealerWon.handNumber == 2)
    #expect(refundableMahjongEntries(dealerWon).isEmpty)
    // 同一手内杠分得主自己点和：本手未结束，但该杠分已不可退。
    var sameHand = MahjongSessionState.initial(setup: setup)
    sameHand = reducer.record(sameHand, MahjongSettlementIntent(
        actionType: .kong, operationId: "kong-2", winnerIndexes: [0], factor: 0,
        kongKind: .concealed, paymentMode: .allOpponents
    ), now: 9).state
    #expect(refundableMahjongEntries(sameHand).map(\.id) == ["kong-2"])
    sameHand = reducer.record(sameHand, MahjongSettlementIntent(
        actionType: .selfDraw, winnerIndexes: [0], factor: 0
    ), now: 10).state
    #expect(sameHand.currentHandWinnerIndexes == [0])
    #expect(refundableMahjongEntries(sameHand).isEmpty)
}

@Test func mahjongRoundAndLedgerLabelsMatchAndroidAndHos() {
    #expect(mahjongRoundLabel(roundOrdinal: 0) == "东1局")
    #expect(mahjongRoundLabel(roundOrdinal: 3) == "东4局")
    #expect(mahjongRoundLabel(roundOrdinal: 4) == "南1局")
    #expect(mahjongRoundLabel(roundOrdinal: 15) == "北4局")
    #expect(mahjongRoundLabel(roundOrdinal: 16) == "第17局")
    #expect(mahjongActionLabel(.selfDraw) == "自摸")
    #expect(mahjongActionLabel(.discardWin) == "点炮")
    #expect(mahjongActionLabel(.kong) == "杠分")
    #expect(mahjongActionLabel(.draw) == "流局")
    #expect(mahjongActionLabel(.notenPenalty) == "查叫")
    #expect(mahjongActionLabel(.flowerPigPenalty) == "查花猪")
    #expect(mahjongActionLabel(.kongRefund) == "退杠分")
    #expect(mahjongActionLabel(.transfer) == "转分")
    #expect(mahjongActionLabel(.adjustment) == "调分")
    let discard = MahjongLedgerEntry(
        id: "e1", timestamp: 1, handNumber: 1, roundOrdinal: 0, dealerIndex: 0, dealerStreak: 1,
        actionType: .discardWin, winnerIndexes: [1], payerIndexes: [3], baseScore: 2, factor: 2,
        resolvedAmount: 8, winnerFactors: [0, 2, 0, 0],
        deltas: [-8, 8, 0, 0], scoresAfter: [-8, 8, 0, 0], completesHand: false, zeroSum: true,
        note: "杠上开花"
    )
    let names = ["阿哲", "小雨", "老周", "安安"]
    #expect(mahjongLedgerDescription(discard, names: names) == "点炮 · 小雨 2番 · 杠上开花")
    var zeroFan = discard
    zeroFan.winnerFactors = [0, 0, 0, 0]
    zeroFan.note = nil
    #expect(mahjongLedgerDescription(zeroFan, names: names) == "点炮 · 小雨 无番")
    var kongEntry = discard
    kongEntry.actionType = .kong
    kongEntry.kongKind = .added
    kongEntry.winnerFactors = nil
    kongEntry.note = nil
    #expect(mahjongLedgerDescription(kongEntry, names: names) == "补杠 · 小雨")
    kongEntry.kongKind = .concealed
    #expect(mahjongLedgerDescription(kongEntry, names: names) == "暗杠 · 小雨")
    var nonZero = discard
    nonZero.actionType = .adjustment
    nonZero.winnerIndexes = []
    nonZero.winnerFactors = nil
    nonZero.note = nil
    nonZero.zeroSum = false
    #expect(mahjongLedgerDescription(nonZero, names: names) == "调分 · 非零和")
    #expect(mahjongSeatWindsForDealer(dealerIndex: 0) == ["east", "south", "west", "north"])
    #expect(mahjongDefaultPlayerNamesForDealer(dealerIndex: 0).count == MAHJONG_PLAYER_COUNT)
}

@Test func mahjongTransferUsesAmountAndRequiresOneWinnerOnePayer() {
    let reducer = MahjongReducer()
    let state = MahjongSessionState.initial(setup: MahjongSetupResult(baseScore: 5, maxFan: 4))
    let transferred = reducer.record(state, MahjongSettlementIntent(
        actionType: .transfer, winnerIndexes: [2], payerIndexes: [0], factor: 1
    ), now: 1)
    #expect(transferred.accepted)
    #expect(transferred.state.ledger[0].deltas == [-10, 0, 10, 0])
    // 转分不结束本手。
    #expect(!transferred.state.ledger[0].completesHand)
    #expect(transferred.state.handNumber == 1)
    #expect(reducer.record(state, MahjongSettlementIntent(
        actionType: .transfer, winnerIndexes: [2], factor: 1
    ), now: 2).reason == MahjongRejectReason.invalidTransfer.rawValue)
    #expect(reducer.record(state, MahjongSettlementIntent(
        actionType: .transfer, winnerIndexes: [2, 3], payerIndexes: [0], factor: 1
    ), now: 3).reason == MahjongRejectReason.invalidTransfer.rawValue)
    // 流局不接受座位。
    #expect(reducer.record(state, MahjongSettlementIntent(
        actionType: .draw, winnerIndexes: [1]
    ), now: 4).reason == MahjongRejectReason.invalidDraw.rawValue)
}

@Test func mahjongPlayerStatsRankWinAndPayerCounts() {
    let reducer = MahjongReducer()
    let setup = MahjongSetupResult.sichuanBloodBattle(playerNames: ["阿哲", "小雨", "老周", "安安"])
    var state = MahjongSessionState.initial(setup: setup)
    state = reducer.record(state, MahjongSettlementIntent(
        actionType: .selfDraw, winnerIndexes: [0], factor: 1
    ), now: 1).state
    state = reducer.record(state, MahjongSettlementIntent(
        actionType: .discardWin, winnerIndexes: [1], payerIndexes: [2], factor: 2
    ), now: 2).state
    state = reducer.record(state, MahjongSettlementIntent(
        actionType: .discardWin, winnerIndexes: [3], payerIndexes: [2], factor: 0
    ), now: 3).state
    #expect(state.scores == [12, 4, -14, -2])
    #expect(state.handNumber == 2)

    let stats = mahjongPlayerStats(state: state)
    #expect(stats.count == MAHJONG_PLAYER_COUNT)
    #expect(stats.map(\.rank) == [1, 2, 3, 4])
    #expect(stats.map(\.playerIndex) == [0, 1, 3, 2])
    #expect(stats[0].finalScore == 12)
    #expect(stats[0].netChange == 12 - setup.startScore)
    #expect(stats[0].name == "阿哲")
    #expect(stats[0].winCount == 1)
    #expect(stats[0].selfDrawCount == 1)
    // 点炮时的 payer 次数才计入 discardCount；杠分不计入。
    #expect(stats.first { $0.playerIndex == 2 }?.discardCount == 2)
    #expect(stats.first { $0.playerIndex == 2 }?.winCount == 0)
    #expect(stats.first { $0.playerIndex == 3 }?.winCount == 1)
    #expect(stats.first { $0.playerIndex == 3 }?.selfDrawCount == 0)
    #expect(stats.reduce(0) { $0 + $1.finalScore } == 0)
}

@Test func mahjongDealerRulesAndRoundLimits() {
    let reducer = MahjongReducer()
    let staying = MahjongSetupResult(
        ruleset: .sichuanBloodBattle, baseScore: 1, initialDealerIndex: 0,
        matchLength: .eastOnly, dealerRule: .dealerWinOrDrawStays, maxFan: 4
    )
    var state = MahjongSessionState.initial(setup: staying)
    // 庄家 0 与另外两家一起点和（3 家）→ 结束本手且连庄：roundOrdinal 不进、streak+1。
    let dealerWins = reducer.record(state, MahjongSettlementIntent(
        actionType: .discardWin, winnerIndexes: [0, 1, 2], payerIndexes: [3], factor: 0
    ), now: 1)
    #expect(dealerWins.accepted)
    state = dealerWins.state
    #expect(state.handNumber == 2)
    #expect(state.roundOrdinal == 0)
    #expect(state.dealerIndex == 0)
    #expect(state.dealerStreak == 2)
    #expect(!state.roundLimitReached)

    // 流局同样连庄。
    let drew = reducer.record(state, MahjongSettlementIntent(actionType: .draw), now: 2)
    #expect(drew.accepted)
    state = drew.state
    #expect(state.dealerIndex == 0)
    #expect(state.dealerStreak == 3)
    #expect(state.roundOrdinal == 0)

    // 庄家未参与的结算 → 换庄、streak 归 1、轮次 +1。
    state = reducer.record(state, MahjongSettlementIntent(
        actionType: .discardWin, winnerIndexes: [1, 2, 3], payerIndexes: [0], factor: 0
    ), now: 3).state
    #expect(state.dealerIndex == 1)
    #expect(state.dealerStreak == 1)
    #expect(state.roundOrdinal == 1)

    // 东风局打满 4 轮 → roundLimitReached，但比赛不自动结束。
    // 每次让庄家点炮、另外三家一起点和（庄家未和 → 必定换庄、轮次 +1）。
    for _ in 0 ..< 6 {
        if state.roundLimitReached { break }
        let dealer = state.dealerIndex
        let next = reducer.record(state, MahjongSettlementIntent(
            actionType: .discardWin,
            winnerIndexes: (0 ..< MAHJONG_PLAYER_COUNT).filter { $0 != dealer },
            payerIndexes: [dealer],
            factor: 0
        ), now: 10)
        #expect(next.accepted, "推进轮次失败：\(next.reason ?? "?")")
        state = next.state
    }
    #expect(state.roundOrdinal == 4)
    #expect(state.dealerIndex == 0)
    #expect(!state.finished)
    let finished = reducer.reduce(state: state, intent: .finishMatch, at: 300)
    #expect(finished.accepted)
    #expect(finished.state.finished)
    #expect(finished.events.first == .matchFinished(at: 300))
    let again = reducer.reduce(state: finished.state, intent: .finishMatch, at: 301)
    #expect(!again.accepted)
    #expect(again.reason == MahjongRejectReason.matchFinished.rawValue)
    let afterFinish = reducer.record(finished.state, MahjongSettlementIntent(actionType: .draw), now: 302)
    #expect(afterFinish.reason == MahjongRejectReason.matchFinished.rawValue)
    // 终局后仍可撤销（撤销把 finished 复位）。
    let undoneAfterFinish = reducer.reduce(state: finished.state, intent: .undoLast, at: 303)
    #expect(undoneAfterFinish.accepted)
    #expect(!undoneAfterFinish.state.finished)

    // 换庄模板：每手 +1 位，streak 恒 1；自由模式永不触顶。
    var rotating = MahjongSessionState.initial(setup: MahjongSetupResult(baseScore: 1))
    for _ in 0 ..< 9 {
        rotating = reducer.record(rotating, MahjongSettlementIntent(actionType: .draw), now: 400).state
    }
    #expect(rotating.dealerIndex == 1)
    #expect(rotating.dealerStreak == 1)
    #expect(rotating.handNumber == 10)
    #expect(rotating.roundOrdinal == 9)
    #expect(!rotating.roundLimitReached)
    // 半庄 8 轮触顶。
    var hanchan = MahjongSessionState.initial(setup: MahjongSetupResult(baseScore: 1, matchLength: .hanchan))
    for _ in 0 ..< 7 {
        hanchan = reducer.record(hanchan, MahjongSettlementIntent(actionType: .draw), now: 500).state
    }
    #expect(!hanchan.roundLimitReached)
    hanchan = reducer.record(hanchan, MahjongSettlementIntent(actionType: .draw), now: 501).state
    #expect(hanchan.roundOrdinal == 8)
    #expect(hanchan.roundLimitReached)
}

@Test func mahjongSetupValidationMirrorsAndroidRequirements() {
    #expect(MahjongSetupResult.generic().validationError() == nil)
    #expect(MahjongSetupResult.sichuanBloodBattle().validationError() == nil)
    #expect(MahjongSetupResult(playerNames: ["甲", "乙", "丙"]).validationError() != nil)
    #expect(MahjongSetupResult(seatWinds: ["east"]).validationError() != nil)
    #expect(MahjongSetupResult(schemaVersion: 0).validationError() != nil)
    #expect(MahjongSetupResult(initialDealerIndex: 4).validationError() != nil)
    #expect(MahjongSetupResult(baseScore: 0).validationError() != nil)
    #expect(MahjongSetupResult(maxFan: 31).validationError() != nil)
    // 只有血战按封顶值检查溢出，通用模板不封顶（Android isScoreRangeSafe 同）。
    #expect(MahjongSetupResult(ruleset: .sichuanBloodBattle, baseScore: 1_000_000_000, maxFan: 4)
        .validationError() != nil)
    #expect(!MahjongSetupResult(ruleset: .sichuanBloodBattle, baseScore: 1_000_000_000, maxFan: 4)
        .isScoreRangeSafe)
    #expect(MahjongSetupResult(baseScore: 1_000_000_000, maxFan: 4).isScoreRangeSafe)
    #expect(MahjongSetupResult(baseScore: -1).validationError() != nil)
    #expect(MahjongSetupResult.generic().playerNames.count == MAHJONG_PLAYER_COUNT)
}

// MARK: - 投屏键集合

@Test func mahjongDisplayFixtureKeysMatchSportStateKeyList() throws {
    let data = try loadFixture("mahjong-display-state-v1")
    let fixture = try JSONDecoder().decode(DisplayFixture.self, from: data)
    #expect(fixture.gameType == "mahjong")
    #expect(fixture.layoutKind == "multi_grid")

    let wireKeys = fixture.sportState.keys.filter { $0.hasPrefix("mahjong") }.sorted()
    #expect(wireKeys == mahjongDisplaySportStateKeys.sorted())
    // 非麻将键（多宫格布局参数）由 app 侧统一注入，不在这份清单里。
    #expect(fixture.sportState.keys.filter { !$0.hasPrefix("mahjong") }
        .sorted() == ["multiGridLargeScore", "multiGridOuterPadding", "multiGridTileGap"])
    #expect(fixture.sportState["mahjongRuleset"] == .string("sichuan_blood_battle"))
    #expect(fixture.sportState["mahjongSeatWinds"] == .strings(["east", "south", "west", "north"]))
    #expect(fixture.sportState["mahjongLastDeltas"] == .integers([24, -8, -8, -8]))
}

@Test func mahjongDisplayProjectionProducesEveryWireKeyAndOmitsCapScoreForGeneric() throws {
    let blood = MahjongSessionState.initial(setup: .sichuanBloodBattle())
    let projection = MahjongDisplayProjection(state: blood)
    for key in mahjongDisplaySportStateKeys {
        #expect(projection.value(for: key) != nil, "\(key) 不该缺省")
    }
    #expect(projection.value(for: "mahjongProtocolVersion") == .integer(MAHJONG_CONTRACT_VERSION))
    #expect(projection.value(for: "mahjongRuleset") == .string(MahjongRuleset.sichuanBloodBattle.rawValue))
    #expect(projection.value(for: "mahjongHandNumber") == .integer(1))
    #expect(projection.value(for: "mahjongRoundLabel") == .string("东1局"))
    #expect(projection.value(for: "mahjongDealerStreak") == .integer(1))
    #expect(projection.value(for: "mahjongSeatWinds") == .strings(["east", "south", "west", "north"]))
    #expect(projection.value(for: "mahjongLastDeltas") == .integers([0, 0, 0, 0]))
    #expect(projection.value(for: "mahjongCapScore") == .integer(32))
    #expect(projection.value(for: "unknownKey") == nil)

    let generic = MahjongDisplayProjection(state: MahjongSessionState.initial(setup: .generic()))
    #expect(generic.capScore == nil)
    #expect(generic.value(for: "mahjongCapScore") == nil)
    // 其余键在无封顶模板下仍需写出。
    for key in mahjongDisplaySportStateKeys where key != "mahjongCapScore" {
        #expect(generic.value(for: key) != nil)
    }

    // 与 Android 夹具的具体取值逐键对齐。
    var seeded = MahjongSessionState.initial(setup: MahjongSetupResult(
        ruleset: .sichuanBloodBattle, baseScore: 2, initialDealerIndex: 3, maxFan: 4
    ))
    seeded.handNumber = 6
    seeded.roundOrdinal = 3
    seeded.dealerIndex = 3
    seeded.dealerStreak = 2
    seeded.lastDeltas = [24, -8, -8, -8]
    seeded.currentHandWinnerIndexes = [0]
    let seededProjection = MahjongDisplayProjection(state: seeded)
    let displayFixture = try JSONDecoder().decode(DisplayFixture.self, from: try loadFixture("mahjong-display-state-v1"))
    for key in mahjongDisplaySportStateKeys
        where key != "mahjongProtocolVersion" && key != "mahjongSeatWinds" {
        let expected = displayFixture.sportState[key]
        #expect(seededProjection.value(for: key).map(jsonValueOf) == expected, "\(key) 与夹具不一致")
    }
    // 夹具里的 mahjongSeatWinds 是静态样例（与同文件的 dealerIndex 3 不成对），
    // 引擎侧必须按庄家轮转输出（Android mahjongSeatWindsForDealer 同）。
    #expect(displayFixture.sportState["mahjongSeatWinds"] == .strings(["east", "south", "west", "north"]))
    #expect(seededProjection.value(for: "mahjongSeatWinds") == .strings(
        mahjongSeatWindsForDealer(dealerIndex: 3)
    ))
}

/// 把引擎的 wire 值转成夹具解码形态，便于逐键比对。
private func jsonValueOf(_ value: MahjongSportValue) -> JsonValue {
    switch value {
    case .integer(let number): return .integer(number)
    case .string(let text): return .string(text)
    case .strings(let list): return .strings(list)
    case .integers(let list): return .integers(list)
    }
}

// MARK: - 会话工厂接线（完备性清单的一部分）

@Test func mahjongSessionFactoryBuildsFourSeatSession() async throws {
    guard let core = ScoreboardSessionFactory.mahjong() else {
        Issue.record("缺少 mahjong 工厂路由")
        return
    }
    let session = await core.snapshot()
    #expect(session.gameType == .mahjong)
    #expect(session.ruleFamily == .s4)
    #expect(session.reducerType == ScoreboardKernelRegistry.descriptor(for: .mahjong).reducerType)
    #expect(session.participants.count == MAHJONG_PLAYER_COUNT)
    #expect(session.state.scores.count == MAHJONG_PLAYER_COUNT)
    #expect(session.state.setup.ruleset == MahjongRuleset.generic)
    #expect(session.state.handNumber == 1)

    let bloodCore = ScoreboardSessionFactory.mahjong(setup: .sichuanBloodBattle(playerNames: ["甲", "乙", "丙", "丁"]))
    let blood = await bloodCore?.snapshot()
    #expect(blood?.participants.map(\.name) == ["甲", "乙", "丙", "丁"])
    #expect(blood?.state.setup.capScore == 32)
    // 座位数不是 4 时工厂直接拒绝，UI 侧不需要二次兜底。
    #expect(ScoreboardSessionFactory.mahjong(setup: MahjongSetupResult(playerNames: ["甲", "乙", "丙"])) == nil)
}
