import Testing
import ScoreCore

@Suite("Tennis voice event mapper")
struct TennisVoiceAnnouncementMapperTests {
    @Test func manualSideChangeIsAnnounced() {
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
        #expect(VoiceAnnouncementMessageBuilder.build(payloads[0], language: .enUS) == "Change ends")
    }

    @Test func gameEndEnteringShortSetTieBreakUsesIsTieBreakFlag() {
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
            VoiceAnnouncementMessageBuilder.build(payloads[0], language: .zhCN)
                == "Alice胜本局，局分4平，抢七"
        )
        #expect(
            VoiceAnnouncementMessageBuilder.build(payloads[0], language: .enUS)
                == "Game Alice. 4 games all. Tie-break"
        )
    }

    @Test func matchEndPrefersSetHistoryAndSkipsPointScore() {
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
            VoiceAnnouncementMessageBuilder.build(payloads[0], language: .zhCN)
                == "本局、决胜盘及比赛由Alice获胜，Alice以2盘比1盘获胜，6比4、3比6、7比5"
        )
    }

    @Test func manualTiedFinishDoesNotInventWinner() {
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
        #expect(VoiceAnnouncementMessageBuilder.build(payloads[0], language: .zhCN) == "比赛结束")
        #expect(VoiceAnnouncementMessageBuilder.build(payloads[0], language: .enUS) == "Match over")

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
        #expect(VoiceAnnouncementMessageBuilder.build(winnerPayload, language: .zhCN) == "比赛结束，Alice以1盘比0盘获胜")
        #expect(VoiceAnnouncementMessageBuilder.build(winnerPayload, language: .enUS) == "Match Alice, 1 set to 0")
    }

    @Test func tiebreakOnlyOpeningAndDoublesIdentity() {
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
        #expect(VoiceAnnouncementMessageBuilder.build(payload!, language: .zhCN) == "抢十赛开始，Alice发球")
        #expect(VoiceAnnouncementMessageBuilder.build(payload!, language: .enUS) == "10-point match tie-break. Alice to serve")

        let regular = TennisMatchState(leftName: "Alice", rightName: "Bob")
        let regularOpening = TennisVoiceAnnouncementMapper.openingPayload(gameType: .tennis, state: regular)!
        #expect(VoiceAnnouncementMessageBuilder.build(regularOpening, language: .zhCN) == "Alice发球，比赛开始")
        #expect(VoiceAnnouncementMessageBuilder.build(regularOpening, language: .enUS) == "Alice to serve, play")
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
}
