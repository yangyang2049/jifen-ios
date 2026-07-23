import Testing
import ScoreCore

@Suite("Tennis voice event mapper")
struct TennisVoiceAnnouncementMapperTests {
    @Test func ignoresNonPointIntents() {
        var state = TennisMatchState(leftName: "Alice", rightName: "Bob")
        let payloads = TennisVoiceAnnouncementMapper.payloads(
            gameType: .tennis,
            before: state,
            after: state,
            intent: .exchangeSides,
            events: [.sidesExchanged],
            completedSetScores: []
        )
        #expect(payloads.isEmpty)

        // Keep compiler happy if state mutated elsewhere.
        state.leftPoints = 0
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
                == "比赛结束，Alice胜，6比4、3比6、7比5"
        )
    }
}
