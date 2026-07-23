import Testing
import ScoreCore

@Suite struct VoiceAnnouncementMessageBuilderTests {
    private func tennis(
        language: VoiceAnnouncementLanguage = .zhCN,
        _ overrides: (inout VoiceAnnouncementPayload) -> Void = { _ in }
    ) -> String {
        var payload = VoiceAnnouncementPayload(
            gameType: .tennis,
            phase: .scoreChange,
            leftTeamName: "Alice",
            rightTeamName: "Bob",
            leftScore: 0,
            rightScore: 0,
            leftSets: 0,
            rightSets: 0,
            currentSet: 1,
            serverSide: .left,
            winnerSide: .left,
            winnerName: "Alice",
            tennisDeuceMode: "advantage"
        )
        overrides(&payload)
        return VoiceAnnouncementMessageBuilder.build(payload, language: language)
    }

    private func racket(
        _ gameType: GameType,
        language: VoiceAnnouncementLanguage = .zhCN,
        _ overrides: (inout VoiceAnnouncementPayload) -> Void = { _ in }
    ) -> String {
        var payload = VoiceAnnouncementPayload(
            gameType: gameType,
            phase: .scoreChange,
            leftTeamName: "Alice",
            rightTeamName: "Bob",
            leftScore: 5,
            rightScore: 3,
            leftSets: 0,
            rightSets: 0,
            currentSet: 1,
            serverSide: .left,
            winnerSide: .left,
            winnerName: "Alice"
        )
        overrides(&payload)
        return VoiceAnnouncementMessageBuilder.build(payload, language: language)
    }

    // —— Badminton BWF ——

    @Test func badmintonScoreAndServiceOver() {
        #expect(racket(.badminton) == "5比3")
        #expect(racket(.badminton, language: .enUS) == "5-3")
        #expect(
            racket(.badminton) {
                $0.serviceOver = true
                $0.serverSide = .right
                $0.leftScore = 5
                $0.rightScore = 3
            } == "换发球，3比5"
        )
        #expect(
            racket(.badminton, language: .enUS) {
                $0.serviceOver = true
                $0.serverSide = .right
                $0.leftScore = 5
                $0.rightScore = 3
            } == "Service over, 3-5"
        )
    }

    @Test func badmintonSetAndMatchEnd() {
        #expect(
            racket(.badminton) {
                $0.phase = .setEnd
                $0.leftScore = 21
                $0.rightScore = 18
                $0.leftSets = 1
                $0.rightSets = 0
                $0.currentSet = 1
            } == "第一局，Alice胜，21比18"
        )
        #expect(
            racket(.badminton, language: .enUS) {
                $0.phase = .setEnd
                $0.leftScore = 21
                $0.rightScore = 18
                $0.leftSets = 1
                $0.rightSets = 0
                $0.currentSet = 1
            } == "First game won by Alice, 21-18"
        )
        #expect(
            racket(.badminton) {
                $0.phase = .setEnd
                $0.leftScore = 19
                $0.rightScore = 21
                $0.leftSets = 1
                $0.rightSets = 1
                $0.currentSet = 2
                $0.winnerSide = .right
                $0.winnerName = "Bob"
            } == "第二局，Bob胜，21比19，局分1平"
        )
        #expect(
            racket(.badminton) {
                $0.phase = .matchEnd
                $0.leftScore = 21
                $0.rightScore = 15
                $0.setScores = [
                    .init(leftGames: 21, rightGames: 18),
                    .init(leftGames: 19, rightGames: 21),
                    .init(leftGames: 21, rightGames: 15),
                ]
            } == "比赛结束，Alice胜，21比18、19比21、21比15"
        )
        #expect(
            racket(.badminton, language: .enUS) {
                $0.phase = .matchEnd
                $0.leftScore = 21
                $0.rightScore = 15
                $0.setScores = [
                    .init(leftGames: 21, rightGames: 18),
                    .init(leftGames: 19, rightGames: 21),
                    .init(leftGames: 21, rightGames: 15),
                ]
            } == "Match won by Alice, 21-18, 19-21, 21-15"
        )
        #expect(racket(.badminton) { $0.phase = .sideChange } == "交换场地")
        #expect(racket(.badminton, language: .enUS) { $0.phase = .sideChange } == "Change ends")
    }

    // —— Table tennis ITTF ——

    @Test func pingpongOpeningScoreAndEnds() {
        #expect(racket(.pingpong) { $0.leftScore = 0; $0.rightScore = 0 } == "Alice发球，0比0")
        #expect(
            racket(.pingpong, language: .enUS) { $0.leftScore = 0; $0.rightScore = 0 }
                == "Alice to serve, love all"
        )
        #expect(racket(.pingpong) { $0.leftScore = 8; $0.rightScore = 7 } == "8比7")
        #expect(racket(.pingpong, language: .enUS) { $0.leftScore = 8; $0.rightScore = 7 } == "8-7")
        #expect(racket(.pingpong) { $0.leftScore = 8; $0.rightScore = 8 } == "8平")
        #expect(racket(.pingpong, language: .enUS) { $0.leftScore = 8; $0.rightScore = 8 } == "8-all")
        #expect(
            racket(.pingpong) {
                $0.phase = .setEnd
                $0.leftScore = 11
                $0.rightScore = 5
                $0.leftSets = 1
                $0.rightSets = 0
                $0.currentSet = 1
            } == "第一局，Alice胜，11比5"
        )
        #expect(
            racket(.pingpong, language: .enUS) {
                $0.phase = .setEnd
                $0.leftScore = 11
                $0.rightScore = 5
                $0.leftSets = 1
                $0.rightSets = 0
                $0.currentSet = 1
            } == "Game 1 won by Alice, 11-5"
        )
        #expect(
            racket(.pingpong) {
                $0.phase = .matchEnd
                $0.setScores = [
                    .init(leftGames: 11, rightGames: 5),
                    .init(leftGames: 9, rightGames: 11),
                    .init(leftGames: 11, rightGames: 7),
                ]
            } == "比赛结束，Alice胜，11比5、9比11、11比7"
        )
    }

    // —— Tennis ITF ——

    @Test func tennisPointsGamesSetsAndMatch() {
        #expect(tennis { $0.leftScore = 1; $0.rightScore = 0 } == "15比0")
        #expect(tennis(language: .enUS) { $0.leftScore = 1; $0.rightScore = 0 } == "Fifteen-love")
        #expect(tennis { $0.leftScore = 1; $0.rightScore = 1; $0.serverSide = .right } == "15平")
        #expect(
            tennis(language: .enUS) { $0.leftScore = 1; $0.rightScore = 1; $0.serverSide = .right }
                == "Fifteen-all"
        )
        #expect(tennis { $0.leftScore = 2; $0.rightScore = 1 } == "30比15")
        #expect(tennis(language: .enUS) { $0.leftScore = 2; $0.rightScore = 1 } == "Thirty-fifteen")
        #expect(tennis { $0.leftScore = 3; $0.rightScore = 3 } == "平分")
        #expect(tennis(language: .enUS) { $0.leftScore = 3; $0.rightScore = 3 } == "Deuce")
        #expect(tennis { $0.leftScore = 4; $0.rightScore = 3 } == "Alice占先")
        #expect(tennis(language: .enUS) { $0.leftScore = 4; $0.rightScore = 3 } == "Advantage Alice")
        #expect(
            tennis {
                $0.leftScore = 3
                $0.rightScore = 3
                $0.tennisDeuceMode = "no_ad"
            } == "决胜分，接发方选择"
        )
        #expect(
            tennis(language: .enUS) {
                $0.leftScore = 3
                $0.rightScore = 3
                $0.tennisDeuceMode = "no_ad"
            } == "Deciding point, receiver's choice"
        )
        #expect(tennis { $0.leftScore = 3; $0.rightScore = 2; $0.isTieBreak = true } == "3比2，Alice")
        #expect(
            tennis(language: .enUS) { $0.leftScore = 3; $0.rightScore = 2; $0.isTieBreak = true }
                == "3-2 Alice"
        )
        #expect(
            tennis {
                $0.phase = .gameEnd
                $0.leftScore = 3
                $0.rightScore = 2
            } == "Alice胜本局，Alice 3比2领先"
        )
        #expect(
            tennis(language: .enUS) {
                $0.phase = .gameEnd
                $0.leftScore = 3
                $0.rightScore = 2
            } == "Game Alice. Alice leads 3 games to 2"
        )
        #expect(
            tennis {
                $0.phase = .gameEnd
                $0.leftScore = 6
                $0.rightScore = 6
                $0.isTieBreak = true
            } == "Alice胜本局，局分6平，抢七"
        )
        #expect(
            tennis(language: .enUS) {
                $0.phase = .gameEnd
                $0.leftScore = 6
                $0.rightScore = 6
                $0.isTieBreak = true
            } == "Game Alice. 6 games all. Tie-break"
        )
        #expect(
            tennis {
                $0.phase = .gameEnd
                $0.leftScore = 4
                $0.rightScore = 4
                $0.isTieBreak = true
            } == "Alice胜本局，局分4平，抢七"
        )
        #expect(
            tennis(language: .enUS) {
                $0.phase = .gameEnd
                $0.leftScore = 4
                $0.rightScore = 4
                $0.isTieBreak = true
            } == "Game Alice. 4 games all. Tie-break"
        )
        #expect(
            tennis {
                $0.phase = .setEnd
                $0.leftScore = 6
                $0.rightScore = 4
                $0.leftSets = 1
                $0.rightSets = 0
                $0.currentSet = 1
            } == "Alice胜第一盘，6比4"
        )
        #expect(
            tennis(language: .enUS) {
                $0.phase = .setEnd
                $0.leftScore = 6
                $0.rightScore = 4
                $0.leftSets = 1
                $0.rightSets = 0
                $0.currentSet = 1
            } == "Game and first set Alice, 6-4"
        )
        #expect(
            tennis {
                $0.phase = .matchEnd
                $0.leftScore = 7
                $0.rightScore = 6
                $0.leftSets = 2
                $0.rightSets = 1
                $0.setScores = [
                    .init(leftGames: 6, rightGames: 4),
                    .init(leftGames: 3, rightGames: 6),
                    .init(leftGames: 7, rightGames: 6),
                ]
            } == "比赛结束，Alice胜，6比4、3比6、7比6"
        )
        #expect(
            tennis(language: .enUS) {
                $0.phase = .matchEnd
                $0.leftScore = 7
                $0.rightScore = 6
                $0.leftSets = 2
                $0.rightSets = 1
                $0.setScores = [
                    .init(leftGames: 6, rightGames: 4),
                    .init(leftGames: 3, rightGames: 6),
                    .init(leftGames: 7, rightGames: 6),
                ]
            } == "Game, set and match Alice, 6-4, 3-6, 7-6"
        )
    }
}
