//
//  MahjongScoreboardStore.swift
//  jifen
//
//  麻将会话状态容器：唯一的构造入口是 core 的 `ScoreboardSessionFactory.mahjong`，
//  记分语义全部由 `MahjongReducer` 决定（台账是唯一真源，撤销走 `.undoLast` 意图，
//  与安卓 `MahjongSessionViewModel` 的 submit/undoLast/endGame/restartCurrentGame 一一对应）。
//

import Foundation
import Observation
import ScoreCore
import SessionCore

/// 落盘用的会话快照。`session` 自身可完整重放（setup + ledger），因此不需要
/// 像掼蛋/斗地主那样另存 undoHistory。
struct MahjongResumeState: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = currentSchemaVersion
    var session: MahjongSessionState
    var intentTimeline: [String]
    var actionCount: Int

    init(
        schemaVersion: Int = currentSchemaVersion,
        session: MahjongSessionState,
        intentTimeline: [String] = [],
        actionCount: Int = 0
    ) {
        self.schemaVersion = schemaVersion
        self.session = session
        self.intentTimeline = intentTimeline
        self.actionCount = actionCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        session = try container.decode(MahjongSessionState.self, forKey: .session)
        intentTimeline = try container.decodeIfPresent([String].self, forKey: .intentTimeline) ?? []
        actionCount = try container.decodeIfPresent(Int.self, forKey: .actionCount) ?? 0
    }

    var encoded: Data? {
        try? JSONEncoder().encode(self)
    }
}

@MainActor
@Observable
final class MahjongScoreboardStore {
    private(set) var state: MahjongSessionState
    private(set) var lastRejectionReason: String?
    private(set) var actions: [String] = []
    private(set) var actionCount: Int = 0
    let recordID: String
    let setup: MahjongSetupResult

    private let reducer = MahjongReducer()
    private let core: ScoreSessionCore<MahjongReducer>?
    private var operationTask: Task<Void, Never>?

    init(
        setup: MahjongSetupResult,
        restoredState: MahjongSessionState? = nil,
        recordID: String,
        restoredActions: [String] = [],
        restoredActionCount: Int = 0
    ) {
        // 会话核只由工厂创建：app 侧不再自己拼 ScoreSession。
        let core = ScoreboardSessionFactory.mahjong(setup: setup)
        self.core = core
        self.setup = setup
        self.recordID = recordID
        self.state = restoredState ?? MahjongSessionState.initial(setup: setup)
        self.actions = restoredActions
        self.actionCount = max(restoredActionCount, restoredState?.ledger.count ?? 0)
        if let restoredState, let core {
            // 恢复的会话要把 actor 对齐到台账状态；后续所有意图都排在这次 rebase 之后。
            operationTask = Task {
                _ = await core.rebase(
                    to: restoredState,
                    status: restoredState.finished ? .finished : .live
                )
            }
        }
    }

    /// 台账驱动的分数变化描述（记录详情/投屏标题用）。
    var currentHandDeltaByPlayer: [Int] {
        var deltas = [Int](repeating: 0, count: MAHJONG_PLAYER_COUNT)
        for entry in state.ledger where entry.handNumber == state.handNumber {
            for (index, delta) in entry.deltas.enumerated() where deltas.indices.contains(index) {
                deltas[index] += delta
            }
        }
        return deltas
    }

    /// 结算面板的实时预览：与安卓一样直接跑一次 reducer（时间戳只影响流水 id，
    /// 预览结果不落盘）。
    func preview(_ settlement: MahjongSettlementIntent) -> ReduceResult<MahjongSessionState, MahjongSessionEvent> {
        reducer.reduce(state: state, intent: .recordSettlement(settlement), at: 0)
    }

    func clearRejection() {
        lastRejectionReason = nil
    }

    func submit(_ settlement: MahjongSettlementIntent, completion: ((Bool) -> Void)? = nil) {
        send(.recordSettlement(settlement), recordAs: mahjongActionDescription(for: settlement), completion: completion)
    }

    func undoLast(completion: ((Bool) -> Void)? = nil) {
        send(.undoLast, recordAs: "mahjong_undo", completion: completion)
    }

    func finishMatch(completion: ((Bool) -> Void)? = nil) {
        send(.finishMatch, recordAs: "mahjong_finish", completion: completion)
    }

    /// 安卓 `restartCurrentGame`：沿用本场设置清空台账，复用同一记录 id。
    func restartWithCurrentSetup() {
        let initial = MahjongSessionState(setup: setup)
        state = initial
        actions = []
        actionCount = 0
        lastRejectionReason = nil
        let previous = operationTask
        operationTask = Task { [core] in
            _ = await previous?.value
            _ = await core?.rebase(to: initial, status: .live)
        }
    }

    private func send(
        _ intent: MahjongSessionIntent,
        recordAs code: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard let core else {
            lastRejectionReason = MahjongRejectReason.invalidState.rawValue
            completion?(false)
            return
        }
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        let previous = operationTask
        operationTask = Task { [weak self, reducer] in
            _ = await previous?.value
            guard let self else { return }
            // 意图时间戳统一由本函数产生，保证 actor 与同步预览的判定一致。
            let local = reducer.reduce(state: self.state, intent: intent, at: now)
            switch await core.dispatch(actorId: "phone", intent: intent, at: now) {
            case .accepted(let session, _):
                self.state = session.state
                self.actionCount += 1
                self.actions.append("\(now)|\(code)|\(session.state.scores.map(String.init).joined(separator: ","))")
                self.lastRejectionReason = local.accepted ? nil : local.reason
                completion?(true)
            case .rejected(_, let reason):
                self.lastRejectionReason = reason
                completion?(false)
            }
        }
    }

    /// 等待排队的意图全部落地（退出/保存前调用）。
    func flush(completion: @escaping () -> Void) {
        let pending = operationTask
        Task {
            _ = await pending?.value
            completion()
        }
    }
}

/// 台账流水 → 记录时间线描述（安卓 `record_mahjong_action` 的 iOS 对应物）。
func mahjongActionDescription(for settlement: MahjongSettlementIntent) -> String {
    "mahjong_\(settlement.actionType.rawValue)"
}
