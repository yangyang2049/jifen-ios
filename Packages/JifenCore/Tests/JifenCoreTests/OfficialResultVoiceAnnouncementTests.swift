import Foundation
import ScoreCore
import Testing

@Suite("Official result calls through the production entry")
struct OfficialResultVoiceAnnouncementTests {
    private func call(_ payload: VoiceAnnouncementPayload, _ locale: String = "zh-Hans") throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let data = try Data(contentsOf: root.appendingPathComponent("jifen/Resources/\(locale).lproj/ScoreVoice.strings"))
        let templates = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        return try #require(LocalizedVoiceAnnouncementBuilder.buildReviewed(payload, localization: locale)
            .render(locale: Locale(identifier: locale), template: { templates[$0] }))
    }

    @Test func tableTennisNamesWinnerAndUsesPointsThenGames() throws {
        for sport in [GameType.pingpong, .pingpongDoubles] {
            for winner in [MatchSide.left, .right] {
                let leftWins = winner == .left
                var payload = VoiceAnnouncementPayload(gameType: sport, phase: .setEnd,
                    leftTeamName: "Alice %2$@", rightTeamName: "Bob",
                    leftScore: leftWins ? 12 : 10, rightScore: leftWins ? 10 : 12,
                    leftSets: leftWins ? 2 : 1, rightSets: leftWins ? 1 : 2,
                    currentSet: 3, serverSide: winner.opposite, winnerSide: winner)
                let name = leftWins ? "Alice %2$@" : "Bob"
                #expect(try call(payload) == "12比10，\(name)胜第3局")
                #expect(try call(payload, "zh-Hant") == "12比10，\(name)勝第3局")
                #expect(try call(payload, "en") == "12, 10. Game to \(name)")
                payload.phase = .matchEnd
                payload.currentSet = 4
                payload.leftSets = leftWins ? 3 : 1
                payload.rightSets = leftWins ? 1 : 3
                #expect(try call(payload) == "12比10，\(name)胜第4局。比赛结果\(name)胜3比1")
                #expect(try call(payload, "en") == "12, 10. Game and match to \(name). \(name) wins 3 games to 1")
                payload.isManualEnd = true
                #expect(try call(payload) == "比赛结果\(name)胜3比1")
                payload.winnerSide = nil
                #expect(try call(payload) == "比赛结束")
            }
        }
    }

    @Test func tableTennisFinalPointProducesOneMatchResultAfterPointReset() throws {
        var before = RallyMatchEngine.initial(leftName: "Alice", rightName: "Bob", rules: .pingPong(maxSets: 5))
        before.leftSets = 1
        before.rightSets = 2
        before.leftPoints = 10
        before.rightPoints = 11
        let result = RallyMatchReducer().reduce(state: before, intent: .pointWon(.right), at: 1)
        let payloads = RallyVoiceAnnouncementMapper.payloads(gameType: .pingpong, before: before,
            after: result.state, events: result.events, completedSetScores: [])
        #expect(payloads.map(\.phase) == [.matchEnd])
        #expect(try call(try #require(payloads.first)) == "12比10，Bob胜第4局。比赛结果Bob胜3比1")
    }

    @Test func badmintonAnnouncesEveryCompletedGameFromTheMatchWinnersSide() throws {
        for sport in [GameType.badminton, .badmintonDoubles] {
            var payload = VoiceAnnouncementPayload(gameType: sport, phase: .setEnd,
                leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 21, rightScore: 17,
                leftSets: 1, rightSets: 1, currentSet: 2, winnerSide: .left)
            #expect(try call(payload) == "本局结束，第2局由Alice获胜，21比17，一局平")
            #expect(try call(payload, "zh-Hant") == "本局結束，第2局由Alice獲勝，21比17，一局平")
            payload.phase = .matchEnd
            payload.winnerSide = .right
            payload.leftScore = 18
            payload.rightScore = 21
            payload.leftSets = 1
            payload.rightSets = 2
            payload.setScores = [.init(leftGames: 21, rightGames: 15), .init(leftGames: 17, rightGames: 21), .init(leftGames: 18, rightGames: 21)]
            #expect(try call(payload) == "本局结束，比赛由Bob获胜，15比21、21比17、21比18")
            #expect(try call(payload, "en") == "Game. Match won by Bob, 15, 21, 21, 17, 21, 18")
            payload.isManualEnd = true
            #expect(try call(payload) == "比赛结束，Bob获胜")
            payload.winnerSide = nil
            #expect(try call(payload) == "比赛结束")
        }
    }

    @Test func tennisSeparatesGameWinnerSetLeaderAndMatchResult() throws {
        for sport in [GameType.tennis, .tennisDoubles] {
            var p = VoiceAnnouncementPayload(gameType: sport, phase: .gameEnd,
                leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 4, rightScore: 2,
                currentSet: 1, winnerSide: .right)
            #expect(try call(p) == "Bob胜本局，第1盘局数4比2，Alice领先")
            p.leftScore = 6; p.rightScore = 6; p.isTieBreak = true
            #expect(try call(p) == "Bob胜本局，第1盘局数6平，抢七")
            p.phase = .setEnd; p.currentSet = 2; p.leftScore = 4; p.rightScore = 6
            p.leftSets = 1; p.rightSets = 1; p.isTieBreak = false
            #expect(try call(p) == "第2盘结束，Bob获胜，局数6比4。盘数1平")
            p.phase = .matchEnd; p.currentSet = 3; p.rightSets = 2
            p.setScores = [.init(leftGames: 6, rightGames: 4), .init(leftGames: 3, rightGames: 6), .init(leftGames: 4, rightGames: 6)]
            #expect(try call(p) == "全场比赛结束，Bob获胜，盘数2比1，各盘局数4比6、6比3、6比4")
            #expect(try call(p, "zh-Hant") == "全場比賽結束，Bob獲勝，盤數2比1，各盤局數4比6、6比3、6比4")
            p.leftSets = 0; p.rightSets = 0; p.leftScore = 8; p.rightScore = 10; p.isTieBreak = true
            #expect(try call(p) == "比赛结束，Bob获胜，10比8")
            p.isManualEnd = true
            #expect(try call(p) == "比赛结束，Bob获胜")
            p.winnerSide = nil
            #expect(try call(p) == "比赛结束")
        }
    }

    @Test func squashUsesItsOwnGameAndMatchResultStructure() throws {
        var p = VoiceAnnouncementPayload(gameType: .squash, phase: .setEnd,
            leftTeamName: "Alice", rightTeamName: "Bob", leftScore: 7, rightScore: 11,
            leftSets: 2, rightSets: 1, winnerSide: .right)
        #expect(try call(p) == "11比7，Bob本局获胜。Alice大比分2比1领先")
        p.leftSets = 1
        #expect(try call(p) == "11比7，Bob本局获胜。大比分1平")
        p.phase = .matchEnd; p.leftScore = 8; p.leftSets = 2; p.rightSets = 3
        p.setScores = [.init(leftGames: 11, rightGames: 3), .init(leftGames: 7, rightGames: 11),
            .init(leftGames: 11, rightGames: 6), .init(leftGames: 9, rightGames: 11), .init(leftGames: 8, rightGames: 11)]
        #expect(try call(p) == "11比8，Bob比赛获胜，大比分3比2，小比分：3比11、11比7、6比11、11比9、11比8")
        #expect(try call(p, "en") == "11, 8, match to Bob, 3 games to 2, 3, 11, 11, 7, 6, 11, 11, 9, 11, 8")
        p.isManualEnd = true
        #expect(try call(p) == "比赛结束，Bob获胜")
        p.winnerSide = nil
        #expect(try call(p) == "比赛结束")
    }

    @Test func standaloneTiebreakFinalPointNeverBecomesZeroSetsOrTenGames() throws {
        var before = TennisMatchState(leftName: "Alice", rightName: "Bob",
            rules: TennisRuleSet(tieBreakPoints: 10, setScoringMode: .tiebreakOnly))
        before.leftPoints = 8
        before.rightPoints = 9
        let result = TennisMatchReducer().reduce(state: before, intent: .pointWon(.right), at: 1)
        let payloads = TennisVoiceAnnouncementMapper.payloads(gameType: .tennis, before: before,
            after: result.state, intent: .pointWon(.right), events: result.events, completedSetScores: [])
        #expect(payloads.map(\.phase) == [.matchEnd])
        let payload = try #require(payloads.first)
        #expect(payload.isTieBreak)
        #expect(payload.winnerSide == .right)
        #expect(try call(payload) == "比赛结束，Bob获胜，10比8")
        #expect(try call(payload, "en") == "Match Bob, 10, 8")
    }
}
