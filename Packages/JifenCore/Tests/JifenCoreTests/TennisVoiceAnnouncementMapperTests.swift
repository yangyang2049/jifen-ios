import Testing
import ScoreCore

@Suite("Tennis voice event mapper")
struct TennisVoiceAnnouncementMapperTests {
    @Test func manualSideChangeFollowsProductionSilence() throws {
        let state = TennisMatchState(leftName: "Alice", rightName: "Bob")
        var after = state
        after.sidesSwapped = true
        let payloads = TennisVoiceAnnouncementMapper.payloads(
            gameType: .tennis,
            before: state,
            after: after,
            intent: .exchangeSides,
            events: [.sidesExchanged],
            completedSetScores: []
        )
        #expect(payloads.map(\.phase) == [.sideChange])
        // 生产播报里网球换边是静音：事件仍要映射成 .sideChange，但不读文案。
        #expect(try VoiceProductionCalls.text(payloads[0], "en").isEmpty)
    }

    @Test func gameEndEnteringShortSetTieBreakUsesIsTieBreakFlag() throws {
        var before = TennisMatchState(
            leftName: "Alice",
            rightName: "Bob",
            rules: TennisRuleSet(gamesPerSet: 4)
        )
        before.leftGames = 3
        before.rightGames = 4
        before.leftPoints = 3
        before.rightPoints = 2

        var after = before
        after.leftGames = 4
        after.rightGames = 4
        after.leftPoints = 0
        after.rightPoints = 0
        after.isTieBreak = true

        let payloads = TennisVoiceAnnouncementMapper.payloads(
            gameType: .tennis,
            before: before,
            after: after,
            intent: .pointWon(.left),
            events: [
                .pointScored(side: .left, left: 4, right: 2),
                .gameCompleted(winner: .left, leftGames: 4, rightGames: 4, tieBreak: false)
            ],
            completedSetScores: []
        )

        #expect(payloads.count == 1)
        #expect(payloads[0].phase == .gameEnd)
        #expect(payloads[0].leftScore == 4)
        #expect(payloads[0].rightScore == 4)
        #expect(payloads[0].isTieBreak == true)
        #expect(
            try VoiceProductionCalls.text(payloads[0], "zh-Hans")
                == "Alice胜本局，第1盘局数4平，抢七"
        )
        #expect(
            try VoiceProductionCalls.text(payloads[0], "en")
                == "Game Alice. 4 games all. Tie-break"
        )
    }

    @Test func matchEndPrefersSetHistoryAndSkipsPointScore() throws {
        var before = TennisMatchState(leftName: "Alice", rightName: "Bob")
        before.leftSets = 1
        before.rightSets = 1
        before.leftGames = 6
        before.rightGames = 5
        before.leftPoints = 3
        before.rightPoints = 2

        var after = before
        after.leftSets = 2
        after.rightSets = 1
        after.finished = true

        let history: [VoiceSetScore] = [
            .init(leftGames: 6, rightGames: 4),
            .init(leftGames: 3, rightGames: 6),
            .init(leftGames: 7, rightGames: 5)
        ]
        let payloads = TennisVoiceAnnouncementMapper.payloads(
            gameType: .tennis,
            before: before,
            after: after,
            intent: .pointWon(.left),
            events: [
                .pointScored(side: .left, left: 4, right: 2),
                .gameCompleted(winner: .left, leftGames: 7, rightGames: 5, tieBreak: false),
                .setCompleted(winner: .left, setNumber: 3, leftGames: 7, rightGames: 5, leftSets: 2, rightSets: 1),
                .matchFinished(winner: .left)
            ],
            completedSetScores: history
        )

        #expect(payloads.count == 1)
        #expect(payloads[0].phase == .matchEnd)
        #expect(
            try VoiceProductionCalls.text(payloads[0], "zh-Hans")
                == "全场比赛结束，Alice获胜，盘数2比1，各盘局数6比4、3比6、7比5"
        )
    }

    @Test func manualTiedFinishDoesNotInventWinner() throws {
        var after = TennisMatchState(leftName: "Alice", rightName: "Bob")
        after.finished = true
        let payloads = TennisVoiceAnnouncementMapper.payloads(
            gameType: .tennis,
            before: after,
            after: after,
            intent: .finish,
            events: [.matchFinished(winner: nil)],
            completedSetScores: []
        )
        #expect(payloads.count == 1)
        #expect(payloads[0].winnerSide == nil)
        #expect(try VoiceProductionCalls.text(payloads[0], "zh-Hans") == "比赛结束")
        #expect(try VoiceProductionCalls.text(payloads[0], "en") == "Match over")

        after.leftSets = 1
        let winnerPayload = TennisVoiceAnnouncementMapper.payloads(
            gameType: .tennis,
            before: after,
            after: after,
            intent: .finish,
            events: [.matchFinished(winner: .left)],
            completedSetScores: []
        )[0]
        #expect(winnerPayload.isManualEnd)
        #expect(try VoiceProductionCalls.text(winnerPayload, "zh-Hans") == "比赛结束，Alice获胜")
        #expect(try VoiceProductionCalls.text(winnerPayload, "en") == "Match Alice, 1 set to 0")
    }

    @Test func tiebreakOnlyOpeningAndDoublesIdentity() throws {
        let rules = TennisRuleSet(tieBreakPoints: 10, setScoringMode: .tiebreakOnly)
        let state = TennisMatchState(
            leftName: "Red",
            rightName: "Blue",
            rules: rules,
            openingServer: .left,
            doublesPlayerNames: ["Alice", "Bob", "Carol", "David"]
        )
        let payload = TennisVoiceAnnouncementMapper.openingPayload(gameType: .tennisDoubles, state: state)
        #expect(payload?.serverName == "Alice")
        #expect(payload?.leftPlayerNames == ["Alice", "Carol"])
        // 生产播报的抢十开局只念比分（0比0）与英文 "to serve, play"。
        #expect(try VoiceProductionCalls.text(payload!, "zh-Hans") == "0比0")
        #expect(try VoiceProductionCalls.text(payload!, "en") == "Alice to serve, play")

        let regular = TennisMatchState(leftName: "Alice", rightName: "Bob")
        let regularOpening = TennisVoiceAnnouncementMapper.openingPayload(gameType: .tennis, state: regular)!
        #expect(try VoiceProductionCalls.text(regularOpening, "zh-Hans") == "0比0")
        #expect(try VoiceProductionCalls.text(regularOpening, "en") == "Alice to serve, play")
    }

    @Test func doublesServerNameFollowsGameRotation() {
        var state = TennisMatchState(
            leftName: "Red",
            rightName: "Blue",
            doublesPlayerNames: ["Alice", "Bob", "Carol", "David"]
        )
        let reducer = TennisMatchReducer()
        for index in 0..<4 {
            state = reducer.reduce(state: state, intent: .pointWon(.left), at: Int64(index)).state
        }
        #expect(TennisDoublesServing.currentServerSlot(in: state) == 1)

        let nextPoint = reducer.reduce(state: state, intent: .pointWon(.right), at: 5)
        let payload = TennisVoiceAnnouncementMapper.payloads(
            gameType: .tennisDoubles,
            before: state,
            after: nextPoint.state,
            intent: .pointWon(.right),
            events: nextPoint.events,
            completedSetScores: []
        )[0]
        #expect(payload.serverName == "Bob")
        #expect(payload.leftPlayerNames == ["Alice", "Carol"])
        #expect(payload.rightPlayerNames == ["Bob", "David"])
    }

    @Test func softTennisAndPadelCarryAndroid31VoiceProfiles() throws {
        let soft = TennisMatchState(
            leftName: "Red",
            rightName: "Blue",
            rules: .softTennis(gamesPerSet: 9)
        )
        let softOpening = TennisVoiceAnnouncementMapper.openingPayload(gameType: .softTennis, state: soft)
        #expect(softOpening?.maxSets == 9)
        #expect(try VoiceProductionCalls.text(softOpening!, "zh-Hans") == "0比0")

        var padel = TennisMatchState(
            leftName: "Red",
            rightName: "Blue",
            rules: .padel(deuceMode: .starPoint)
        )
        padel.leftPoints = 3
        padel.rightPoints = 2
        padel.starPointReturnedAdvantages = 1
        let result = TennisMatchReducer().reduce(state: padel, intent: .pointWon(.right), at: 1)
        let payload = TennisVoiceAnnouncementMapper.payloads(
            gameType: .padel,
            before: padel,
            after: result.state,
            intent: .pointWon(.right),
            events: result.events,
            completedSetScores: []
        )[0]
        #expect(payload.tennisDeuceMode == PadelDeuceMode.starPoint.rawValue)
        #expect(payload.starPointReturnedAdvantages == 1)
        // 中文生产播报的平分只念比分。
        #expect(try VoiceProductionCalls.text(payload, "zh-Hans") == "40比40")
    }
}
