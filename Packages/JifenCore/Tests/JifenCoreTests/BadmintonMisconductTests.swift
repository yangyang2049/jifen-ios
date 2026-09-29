import Foundation
import Testing
import ScoreCore

/// 羽毛球判罚（红黄牌/取消资格）+ 医疗中断引擎语义测试。
/// opCode 字符串逐字对齐安卓 bd_yellow / bd_red / bd_disqualify，保证跨端记录互通。
@Suite struct BadmintonMisconductTests {

    private func makeBadmintonState() -> RallyMatchState {
        RallyMatchEngine.initial(leftName: "红队", rightName: "蓝队", rules: .badminton())
    }

    private func reduce(
        _ state: RallyMatchState,
        _ intent: RallyMatchIntent,
        at milliseconds: Int64 = 1
    ) -> ReduceResult<RallyMatchState, RallyMatchEvent> {
        RallyMatchReducer().reduce(state: state, intent: intent, at: milliseconds)
    }

    @Test func badmintonRulesUseBadmintonSportProfile() {
        #expect(RallyRuleSet.badminton().sportProfile == .badminton)
    }

    @Test func misconductKindRawValuesMatchAndroidOpCodes() {
        #expect(BadmintonMisconductKind.yellow.rawValue == "bd_yellow")
        #expect(BadmintonMisconductKind.red.rawValue == "bd_red")
        #expect(BadmintonMisconductKind.disqualify.rawValue == "bd_disqualify")
    }

    @Test func yellowCardRecordsWithoutScoring() {
        let state = makeBadmintonState()
        let result = reduce(state, .badmintonMisconduct(side: .left, kind: .yellow))

        #expect(result.accepted)
        #expect(result.state.leftPoints == 0)
        #expect(result.state.rightPoints == 0)
        #expect(result.state.badmintonMisconductStatus(for: .left).yellowCount == 1)
        #expect(result.state.badmintonMisconductStatus(for: .left).redCount == 0)
        #expect(!result.state.badmintonMisconductStatus(for: .left).disqualified)
        #expect(result.events.first.map { event in
            if case .badmintonMisconduct(let action) = event {
                return action.kind.rawValue == "bd_yellow" && action.side == .left
            }
            return false
        } == true)
    }

    @Test func redCardAwardsOpponentOnePoint() {
        var state = makeBadmintonState()
        state.leftPoints = 5
        state.rightPoints = 3

        let result = reduce(state, .badmintonMisconduct(side: .right, kind: .red))

        #expect(result.accepted)
        #expect(result.state.leftPoints == 6)
        #expect(result.state.rightPoints == 3)
        #expect(result.state.badmintonMisconductStatus(for: .right).redCount == 1)
        #expect(result.events.contains { event in
            if case .pointScored(let side, _, _) = event { return side == .left }
            return false
        })
    }

    @Test func disqualificationFinishesMatchWithOpponentAsWinner() {
        let state = makeBadmintonState()

        let result = reduce(state, .badmintonMisconduct(side: .left, kind: .disqualify))

        #expect(result.accepted)
        #expect(result.state.finished)
        #expect(result.state.pingPongForfeitSide == .left)
        #expect(result.state.badmintonMisconductStatus(for: .left).disqualified)
        #expect(result.events.contains { event in
            if case .matchFinished(let winner) = event { return winner == .right }
            return false
        })
        // 终局胜方由判负事件推导；判负后重复 finish 被拒绝，判负侧保持不变。
        let repeatFinish = reduce(result.state, .finish)
        #expect(!repeatFinish.accepted)
        #expect(repeatFinish.state.pingPongForfeitSide == .left)
        #expect(repeatFinish.state.finished)
    }

    @Test func misconductRejectedAfterMatchFinishedAndForOtherProfiles() throws {
        // 判负完赛后不再受理判罚。
        let disqualified = reduce(makeBadmintonState(), .badmintonMisconduct(side: .left, kind: .disqualify)).state
        #expect(reduce(disqualified, .badmintonMisconduct(side: .right, kind: .yellow)).accepted == false)

        // 非 badminton profile（如乒乓球规则）不可用羽毛球判罚通道。
        let pingPong = RallyMatchEngine.initial(leftName: "A", rightName: "B", rules: .pingPong())
        #expect(reduce(pingPong, .badmintonMisconduct(side: .left, kind: .yellow)).accepted == false)
    }

    @Test func misconductStateAndEventsSurviveSerializationRoundTrip() throws {
        var state = makeBadmintonState()
        state = reduce(state, .badmintonMisconduct(side: .left, kind: .yellow), at: 10).state
        state = reduce(state, .badmintonMisconduct(side: .left, kind: .red), at: 20).state
        state = reduce(state, .badmintonMisconduct(side: .right, kind: .yellow), at: 30).state
        state = reduce(state, .badmintonMisconduct(side: .left, kind: .disqualify), at: 40).state

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        let decoded = try JSONDecoder().decode(RallyMatchState.self, from: data)

        #expect(decoded == state)
        #expect(decoded.badmintonMisconductActions?.count == 4)
        #expect(decoded.badmintonMisconductActions?.map(\.kind) == [.yellow, .red, .yellow, .disqualify])
        #expect(decoded.badmintonMisconductActions?.map(\.epochMilliseconds) == [10, 20, 30, 40])
        #expect(decoded.badmintonMisconductActions?.first?.side == .left)

        // 事件序列化往返（记录侧依赖 event Codable）。
        let events: [RallyMatchEvent] = [.badmintonMisconduct(BadmintonMisconductAction(
            kind: .disqualify,
            side: .right,
            epochMilliseconds: 1234
        ))]
        let decodedEvents = try JSONDecoder()
            .decode([RallyMatchEvent].self, from: try encoder.encode(events))
        #expect(decodedEvents == events)

        // 意图序列化往返（撤销时间线依赖 intent Codable）。
        let intents: [RallyMatchIntent] = [.badmintonMisconduct(side: .left, kind: .red)]
        let decodedIntents = try JSONDecoder()
            .decode([RallyMatchIntent].self, from: try encoder.encode(intents))
        #expect(decodedIntents.map { intent in
            if case .badmintonMisconduct(let side, let kind) = intent { return side == .left && kind == .red }
            return false
        } == [true])
    }

    @Test func stateWithoutMisconductFieldStillDecodes() throws {
        // 旧快照没有 badmintonMisconductActions 键：解码后应为空记录。
        let legacy = makeBadmintonState()
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(RallyMatchState.self, from: data)
        #expect(decoded.badmintonMisconductActions == nil)
        #expect(decoded.badmintonMisconductStatus(for: .left).yellowCount == 0)
    }

    // MARK: - 医疗中断（无时限正计时）

    @Test func medicalCountUpBreakNeverCompletesAutomatically() {
        var session = OfficialBreakSession()
        session.begin(
            sport: .badminton,
            kind: .medical,
            durationSeconds: 0,
            nowMilliseconds: 1_000,
            countUp: true
        )

        guard let started = session.state else {
            Issue.record("Medical break state missing")
            return
        }
        #expect(started.countUp)
        #expect(started.durationSeconds == 0)
        #expect(started.remainingSeconds == 0)
        #expect(started.elapsedSeconds == 0)
        #expect(started.isRunning)

        // 长时间推进：永不自动结束，只累计已用时长。
        var completed = session.tick(nowMilliseconds: 1_000 + 61 * 1_000)
        #expect(!completed)
        #expect(session.state?.isRunning == true)
        #expect(session.state?.elapsedSeconds == 61)
        #expect(session.state?.remainingSeconds == 0)

        completed = session.advance(seconds: 3_600)
        #expect(!completed)
        #expect(session.state?.isRunning == true)
        #expect(session.state?.elapsedSeconds == 61 + 3_600)
    }

    @Test func medicalCountUpBreakEndsOnlyByManualSkip() {
        var session = OfficialBreakSession()
        session.begin(
            sport: .badminton,
            kind: .medical,
            durationSeconds: 0,
            nowMilliseconds: 0,
            countUp: true
        )
        _ = session.advance(seconds: 125)

        // 「继续」= 手动收尾。
        session.skip()
        #expect(session.state?.isRunning == false)
        #expect(session.inputFrozen == false)
        #expect(session.state?.elapsedSeconds == 125)
    }

    @Test func medicalCountUpBreakStateSurvivesSerializationAndLegacyDecode() throws {
        let state = OfficialBreakState(
            sport: .badminton,
            kind: .medical,
            durationSeconds: 0,
            nowMilliseconds: 5_000,
            countUp: true
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(OfficialBreakState.self, from: data)
        #expect(decoded == state)

        // 旧快照缺 countUp/elapsedSeconds 键：按倒计时迁移。
        let legacyJSON = """
        {"sport":"badminton","kind":"medical","source":"official","phase":"countdown",
         "durationSeconds":60,"remainingSeconds":42,"isRunning":true,
         "startedWallClockMilliseconds":100,"updatedWallClockMilliseconds":100,
         "afterAction":"none"}
        """
        let legacy = try JSONDecoder().decode(OfficialBreakState.self, from: Data(legacyJSON.utf8))
        #expect(legacy.countUp == false)
        #expect(legacy.elapsedSeconds == 0)
        #expect(legacy.remainingSeconds == 42)
    }

    @Test func medicalCountUpFreezesScoringInReducer() {
        var state = makeBadmintonState()
        let breakState = OfficialBreakState(
            sport: .badminton,
            kind: .medical,
            durationSeconds: 0,
            nowMilliseconds: 0,
            countUp: true
        )
        state = reduce(state, .setOfficialBreakState(breakState)).state

        let rejected = reduce(state, .pointWon(.left))
        #expect(rejected.accepted == false)
        #expect(state.leftPoints == 0)
    }
}
