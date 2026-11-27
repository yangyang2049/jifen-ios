import Foundation
import ScoreCore
import Testing

/// 比分、赛果和官方暂停的生产播报回归。
@Suite struct VoiceAnnouncementCallTests {
    private func tennis(
        _ code: String = "zh-Hans",
        _ overrides: (inout VoiceAnnouncementPayload) -> Void = { _ in }
    ) throws -> String {
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
        return try VoiceProductionCalls.text(payload, code)
    }

    private func racket(
        _ gameType: GameType,
        _ code: String = "zh-Hans",
        _ overrides: (inout VoiceAnnouncementPayload) -> Void = { _ in }
    ) throws -> String {
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
        return try VoiceProductionCalls.text(payload, code)
    }

    // —— Badminton BWF ——

    @Test func badmintonScoreAndServiceOver() throws {
        #expect(try racket(.badminton) == "5比3")
        #expect(try racket(.badminton, "en") == "5, 3")
        #expect(
            try racket(.badminton) {
                $0.serviceOver = true
                $0.serverSide = .right
                $0.leftScore = 5
                $0.rightScore = 3
            } == "3比5"
        )
        #expect(
            try racket(.badminton, "en") {
                $0.serviceOver = true
                $0.serverSide = .right
                $0.leftScore = 5
                $0.rightScore = 3
            } == "Service over, 3, 5"
        )
    }

    @Test func badmintonCriticalPointsAndInterval() throws {
        #expect(
            try racket(.badminton) {
                $0.leftScore = 20
                $0.rightScore = 18
                $0.criticalPoint = .gamePoint
            } == "20比18"
        )
        #expect(
            try racket(.badminton, "en") {
                $0.leftScore = 29
                $0.rightScore = 28
                $0.criticalPoint = .matchPoint
            } == "29, match point, 28"
        )
        #expect(
            try racket(.badminton) {
                $0.leftScore = 11
                $0.rightScore = 8
                $0.isInterval = true
            } == "11比8"
        )
        #expect(
            try racket(.badminton, "en") {
                $0.leftScore = 11
                $0.rightScore = 8
                $0.isInterval = true
            } == "11, 8, interval"
        )
    }

    @Test func badmintonSetAndMatchEnd() throws {
        #expect(
            try racket(.badminton) {
                $0.phase = .setEnd
                $0.leftScore = 21
                $0.rightScore = 18
                $0.leftSets = 1
                $0.rightSets = 0
                $0.currentSet = 1
            } == "本局结束，第1局由Alice获胜，21比18"
        )
        #expect(
            try racket(.badminton, "en") {
                $0.phase = .setEnd
                $0.leftScore = 21
                $0.rightScore = 18
                $0.leftSets = 1
                $0.rightSets = 0
                $0.currentSet = 1
            } == "Game. First game won by Alice, 21, 18"
        )
        #expect(
            try racket(.badminton) {
                $0.phase = .setEnd
                $0.leftScore = 19
                $0.rightScore = 21
                $0.leftSets = 1
                $0.rightSets = 1
                $0.currentSet = 2
                $0.winnerSide = .right
                $0.winnerName = "Bob"
            } == "本局结束，第2局由Bob获胜，21比19，一局平"
        )
        #expect(
            try racket(.badminton) {
                $0.phase = .matchEnd
                $0.leftScore = 21
                $0.rightScore = 15
                $0.setScores = [
                    .init(leftGames: 21, rightGames: 18),
                    .init(leftGames: 19, rightGames: 21),
                    .init(leftGames: 21, rightGames: 15),
                ]
            } == "本局结束，比赛由Alice获胜，21比18、19比21、21比15"
        )
        #expect(
            try racket(.badminton, "en") {
                $0.phase = .matchEnd
                $0.leftScore = 21
                $0.rightScore = 15
                $0.setScores = [
                    .init(leftGames: 21, rightGames: 18),
                    .init(leftGames: 19, rightGames: 21),
                    .init(leftGames: 21, rightGames: 15),
                ]
            } == "Game. Match won by Alice, 21, 18, 19, 21, 21, 15"
        )
        // 中文生产播报不念换边（numericFallback 对 sideChange 返回空串），
        // 英文仍然念 "Change ends"。
        #expect(try racket(.badminton) { $0.phase = .sideChange }.isEmpty)
        #expect(try racket(.badminton, "en") { $0.phase = .sideChange } == "Change ends")
    }

    // —— Table tennis ITTF ——

    @Test func pingpongOpeningScoreAndEnds() throws {
        #expect(try racket(.pingpong) { $0.leftScore = 0; $0.rightScore = 0 } == "0平")
        #expect(
            try racket(.pingpong, "en") { $0.leftScore = 0; $0.rightScore = 0 }
                == "Alice to serve, love all"
        )
        #expect(try racket(.pingpong) { $0.leftScore = 8; $0.rightScore = 7 } == "8比7")
        #expect(try racket(.pingpong, "en") { $0.leftScore = 8; $0.rightScore = 7 } == "8, 7")
        #expect(try racket(.pingpong) { $0.leftScore = 8; $0.rightScore = 8 } == "8平")
        #expect(try racket(.pingpong, "en") { $0.leftScore = 8; $0.rightScore = 8 } == "8 all")
        #expect(
            try racket(.pingpong) {
                $0.phase = .setEnd
                $0.leftScore = 11
                $0.rightScore = 5
                $0.leftSets = 1
                $0.rightSets = 0
                $0.currentSet = 1
            } == "11比5，Alice胜第1局"
        )
        #expect(
            try racket(.pingpong, "en") {
                $0.phase = .setEnd
                $0.leftScore = 11
                $0.rightScore = 5
                $0.leftSets = 1
                $0.rightSets = 0
                $0.currentSet = 1
            } == "11, 5. Game to Alice"
        )
        #expect(
            try racket(.pingpong) {
                $0.phase = .matchEnd
                $0.leftScore = 11
                $0.rightScore = 7
                $0.leftSets = 3
                $0.rightSets = 1
                $0.setScores = [
                    .init(leftGames: 11, rightGames: 5),
                    .init(leftGames: 9, rightGames: 11),
                    .init(leftGames: 11, rightGames: 7),
                ]
            } == "11比7，Alice胜第1局。比赛结果Alice胜3比1"
        )
    }

    // —— Tennis ITF ——

    @Test func tennisPointsGamesSetsAndMatch() throws {
        #expect(try tennis { $0.leftScore = 1; $0.rightScore = 0 } == "15比0")
        #expect(try tennis("en") { $0.leftScore = 1; $0.rightScore = 0 } == "Fifteen, love")
        #expect(try tennis { $0.leftScore = 1; $0.rightScore = 1; $0.serverSide = .right } == "15比15")
        #expect(
            try tennis("en") { $0.leftScore = 1; $0.rightScore = 1; $0.serverSide = .right }
                == "Fifteen all"
        )
        #expect(try tennis { $0.leftScore = 2; $0.rightScore = 1 } == "30比15")
        #expect(try tennis("en") { $0.leftScore = 2; $0.rightScore = 1 } == "Thirty, fifteen")
        #expect(try tennis { $0.leftScore = 3; $0.rightScore = 3 } == "平分")
        #expect(try tennis("en") { $0.leftScore = 3; $0.rightScore = 3 } == "Deuce")
        #expect(try tennis { $0.leftScore = 4; $0.rightScore = 3 } == "Alice占先")
        #expect(try tennis("en") { $0.leftScore = 4; $0.rightScore = 3 } == "Advantage Alice")
        #expect(
            try tennis {
                $0.leftScore = 3
                $0.rightScore = 3
                $0.tennisDeuceMode = "no_ad"
            } == "40比40"
        )
        #expect(
            try tennis("en") {
                $0.leftScore = 3
                $0.rightScore = 3
                $0.tennisDeuceMode = "no_ad"
            } == "Deciding point, receiver's choice"
        )
        #expect(try tennis { $0.leftScore = 3; $0.rightScore = 2; $0.isTieBreak = true } == "3比2")
        #expect(
            try tennis("en") { $0.leftScore = 3; $0.rightScore = 2; $0.isTieBreak = true }
                == "3, 2, Alice"
        )
        #expect(
            try tennis {
                $0.phase = .gameEnd
                $0.leftScore = 3
                $0.rightScore = 2
            } == "Alice胜本局，第1盘局数3比2，Alice领先"
        )
        #expect(
            try tennis("en") {
                $0.phase = .gameEnd
                $0.leftScore = 3
                $0.rightScore = 2
            } == "Game Alice. Alice leads 3 games to 2, first set"
        )
        #expect(
            try tennis {
                $0.phase = .gameEnd
                $0.leftScore = 6
                $0.rightScore = 6
                $0.isTieBreak = true
            } == "Alice胜本局，第1盘局数6平，抢七"
        )
        #expect(
            try tennis("en") {
                $0.phase = .gameEnd
                $0.leftScore = 6
                $0.rightScore = 6
                $0.isTieBreak = true
            } == "Game Alice. 6 games all. Tie-break"
        )
        #expect(
            try tennis {
                $0.phase = .gameEnd
                $0.leftScore = 4
                $0.rightScore = 4
                $0.isTieBreak = true
            } == "Alice胜本局，第1盘局数4平，抢七"
        )
        #expect(
            try tennis("en") {
                $0.phase = .gameEnd
                $0.leftScore = 4
                $0.rightScore = 4
                $0.isTieBreak = true
            } == "Game Alice. 4 games all. Tie-break"
        )
        #expect(
            try tennis {
                $0.phase = .setEnd
                $0.leftScore = 6
                $0.rightScore = 4
                $0.leftSets = 1
                $0.rightSets = 0
                $0.currentSet = 1
            } == "第1盘结束，Alice获胜，局数6比4。盘数1比0，Alice领先"
        )
        #expect(
            try tennis("en") {
                $0.phase = .setEnd
                $0.leftScore = 6
                $0.rightScore = 4
                $0.leftSets = 1
                $0.rightSets = 0
                $0.currentSet = 1
            } == "Game and first set Alice, 6 games to 4"
        )
        #expect(
            try tennis {
                $0.phase = .matchEnd
                $0.leftScore = 7
                $0.rightScore = 6
                $0.leftSets = 2
                $0.rightSets = 1
                $0.currentSet = 3
                $0.setScores = [
                    .init(leftGames: 6, rightGames: 4),
                    .init(leftGames: 3, rightGames: 6),
                    .init(leftGames: 7, rightGames: 6),
                ]
            } == "全场比赛结束，Alice获胜，盘数2比1，各盘局数6比4、3比6、7比6"
        )
        #expect(
            try tennis("en") {
                $0.phase = .matchEnd
                $0.leftScore = 7
                $0.rightScore = 6
                $0.leftSets = 2
                $0.rightSets = 1
                $0.currentSet = 3
                $0.setScores = [
                    .init(leftGames: 6, rightGames: 4),
                    .init(leftGames: 3, rightGames: 6),
                    .init(leftGames: 7, rightGames: 6),
                ]
            } == "Game, set and match Alice, 2 sets to 1, 6, 4, 3, 6, 7, 6"
        )
    }

    @Test func doublesWinnerUsesLocalizedPairNameAndTiedManualFinishHasNoWinner() throws {
        var doubles = VoiceAnnouncementPayload(
            gameType: .pingpongDoubles,
            phase: .matchEnd,
            leftTeamName: "Red",
            rightTeamName: "Blue",
            leftScore: 11,
            rightScore: 7,
            leftSets: 3,
            rightSets: 1,
            winnerSide: .left,
            leftPlayerNames: ["Alice", "Carol"],
            rightPlayerNames: ["Bob", "David"]
        )
        #expect(try VoiceProductionCalls.text(doubles, "zh-Hans").contains("Alice和Carol"))
        #expect(try VoiceProductionCalls.text(doubles, "en").contains("Alice and Carol"))
        // 中文结果口径列出局分与盘分，英文列出局数与比分。
        #expect(try VoiceProductionCalls.text(doubles, "zh-Hans").hasSuffix("比赛结果Alice和Carol胜3比1"))
        #expect(try VoiceProductionCalls.text(doubles, "en").hasSuffix("Alice and Carol wins 3 games to 1"))

        doubles.phase = .matchEnd
        doubles.winnerSide = nil
        doubles.winnerName = nil
        doubles.leftSets = 1
        doubles.rightSets = 1
        #expect(try VoiceProductionCalls.text(doubles, "zh-Hans") == "比赛结束")
        #expect(try VoiceProductionCalls.text(doubles, "en") == "Match over")
    }

    // —— zh-Hant 走同一套生产模板 ——

    @Test func traditionalBadmintonCriticalPointsReadScoreOnly() throws {
        #expect(try racket(.badminton, "zh-Hant") == "5比3")
        var gamePoint = VoiceAnnouncementPayload(
            gameType: .badminton,
            phase: .scoreChange,
            leftTeamName: "Alice",
            rightTeamName: "Bob",
            leftScore: 20,
            rightScore: 18,
            serverSide: .left,
            winnerSide: .left,
            winnerName: "Alice",
            criticalPoint: .gamePoint
        )
        // 局点/赛点在中文生产播报里只念比分，不念关键词；繁简输出保持一致。
        #expect(try VoiceProductionCalls.text(gamePoint, "zh-Hant") == "20比18")
        gamePoint.criticalPoint = .matchPoint
        #expect(try VoiceProductionCalls.text(gamePoint, "zh-Hant") == "20比18")
        gamePoint.criticalPoint = nil
        #expect(try VoiceProductionCalls.text(gamePoint, "zh-Hans") == "20比18")
    }

    @Test func chineseBadmintonIntervalReadsScoreAndSideChangeIsSilent() throws {
        var payload = VoiceAnnouncementPayload(
            gameType: .badminton,
            phase: .scoreChange,
            leftTeamName: "Alice",
            rightTeamName: "Bob",
            leftScore: 11,
            rightScore: 9,
            serverSide: .left,
            winnerSide: .left,
            winnerName: "Alice",
            isInterval: true
        )
        // 中文生产播报对局中间歇只念比分；繁简输出一致，换边静音。
        #expect(try VoiceProductionCalls.text(payload, "zh-Hans") == "11比9")
        #expect(try VoiceProductionCalls.text(payload, "zh-Hant") == "11比9")
        payload.phase = .sideChange
        #expect(try VoiceProductionCalls.text(payload, "zh-Hant").isEmpty)
    }

    @Test func traditionalKeepsTennisAdvantageTermAndUserNames() throws {
        // 佔先 matches the UI term 無佔先; Traditional names pass through.
        let advantage = try tennis("zh-Hant") { payload in
            payload.leftScore = 4
            payload.rightScore = 3
        }
        #expect(advantage == "Alice佔先")
        let deuceNoAd = try tennis("zh-Hant") { payload in
            payload.leftScore = 3
            payload.rightScore = 3
            payload.tennisDeuceMode = "no_ad"
        }
        #expect(deuceNoAd == "40比40")
        let traditionalNames = try tennis("zh-Hant") { payload in
            payload.leftTeamName = "陳小明"
            payload.rightTeamName = "林大華"
            payload.leftScore = 4
            payload.rightScore = 3
        }
        #expect(traditionalNames == "陳小明佔先")
    }

    @Test func onlyOrdinarySingleScoresAreDebounced() throws {
        let ordinary = VoiceAnnouncementPayload(
            gameType: .badminton,
            phase: .scoreChange,
            leftTeamName: "Alice",
            rightTeamName: "Bob",
            leftScore: 5,
            rightScore: 3
        )
        #expect(VoiceAnnouncementBatchPolicy.shouldDebounce([ordinary]))

        var keyPoint = ordinary
        keyPoint.criticalPoint = .gamePoint
        #expect(!VoiceAnnouncementBatchPolicy.shouldDebounce([keyPoint]))

        var interval = ordinary
        interval.isInterval = true
        interval.leftScore = 11
        interval.rightScore = 8
        let changeEnds = VoiceAnnouncementPayload(
            gameType: .badminton,
            phase: .sideChange,
            leftTeamName: "Alice",
            rightTeamName: "Bob",
            leftScore: 11,
            rightScore: 8
        )
        #expect(!VoiceAnnouncementBatchPolicy.shouldDebounce([interval, changeEnds]))
        #expect(
            try [interval, changeEnds].map { try VoiceProductionCalls.text($0, "en") }
                == ["11, 8, interval", "Change ends"]
        )
        #expect(VoiceAnnouncementBatchPolicy.queuePolicy([ordinary]) == .latestScore)
        #expect(VoiceAnnouncementBatchPolicy.queuePolicy([changeEnds]) == .append)
        #expect(VoiceAnnouncementBatchPolicy.queuePolicy([interval, changeEnds]) == .flush)

        var warning = ordinary
        warning.phase = .breakWarning
        warning.breakCue = .twentySeconds
        #expect(VoiceAnnouncementBatchPolicy.queuePolicy([warning]) == .append)

        var resume = ordinary
        resume.phase = .breakResume
        #expect(VoiceAnnouncementBatchPolicy.queuePolicy([resume]) == .flush)
    }

    @Test func officialBreak31CuePolicyMatchesAndroid() {
        #expect(OfficialBreakVoicePolicy.shouldSpeak(gameType: .pickleball, cue: .start))
        #expect(!OfficialBreakVoicePolicy.shouldSpeak(gameType: .badminton, cue: .start))
        #expect(!OfficialBreakVoicePolicy.shouldSpeak(gameType: .tennis, cue: .complete))
        #expect(!OfficialBreakVoicePolicy.shouldSpeak(gameType: .padel, cue: .complete))
        #expect(OfficialBreakVoicePolicy.shouldSpeak(gameType: .softTennis, cue: .complete))
        #expect(OfficialBreakVoicePolicy.shouldSpeak(gameType: .tennis, cue: .earlyResume))
    }

    @Test func pingPongAdministrativeBreaksStaySilentWithPreferenceOnOrOff() {
        for kind in [OfficialBreakKind.timeout, .medical] {
            let state = OfficialBreakState(
                sport: .pingpong,
                kind: kind,
                durationSeconds: 60,
                source: .administrative
            )
            for preferenceEnabled in [false, true] {
                for cue in [
                    OfficialBreakCue.start, .twentySeconds, .halfTime,
                    .fifteenSeconds, .time, .complete, .earlyResume
                ] {
                    #expect(!OfficialBreakVoicePolicy.shouldSpeak(
                        gameType: .pingpong,
                        cue: cue,
                        state: state,
                        officialBreaksEnabled: preferenceEnabled
                    ))
                    #expect(OfficialBreakVoiceMapper.payload(
                        gameType: .pingpong,
                        cue: cue,
                        state: state,
                        leftName: "Alice",
                        rightName: "Bob",
                        leftScore: 5,
                        rightScore: 4,
                        servingSide: .left
                    ) == nil)
                }
            }
        }
    }

    @Test func ordinaryOfficialBreakKeepsExistingVoicePolicy() {
        let state = OfficialBreakState(
            sport: .pickleball,
            kind: .midGame,
            durationSeconds: 60
        )
        #expect(!OfficialBreakVoicePolicy.shouldSpeak(
            gameType: .pickleball,
            cue: .start,
            state: state,
            officialBreaksEnabled: false
        ))
        #expect(OfficialBreakVoicePolicy.shouldSpeak(
            gameType: .pickleball,
            cue: .start,
            state: state,
            officialBreaksEnabled: true
        ))
        #expect(OfficialBreakVoiceMapper.payload(
            gameType: .pickleball,
            cue: .start,
            state: state,
            leftName: "Alice",
            rightName: "Bob",
            leftScore: 6,
            rightScore: 4,
            servingSide: .left
        ) != nil)
    }

    @Test func android31AddsProjectSpecificRacketCalls() throws {
        #expect(
            try racket(.squash) {
                $0.phase = .opening
                $0.leftScore = 0
                $0.rightScore = 0
                $0.receiverName = "Bob"
                $0.maxSets = 5
            } == "0比0"
        )
        #expect(
            try racket(.squash, "en") {
                $0.phase = .scoreChange
                $0.leftScore = 10
                $0.rightScore = 10
            } == "10 all, a player must win by 2 points"
        )
        #expect(try racket(.shuttlecock) { $0.phase = .opening; $0.leftScore = 0; $0.rightScore = 0 } == "0比0")

        #expect(
            try racket(.softTennis) {
                $0.phase = .opening
                $0.maxSets = 9
            } == "5比3"
        )
        #expect(
            try racket(.softTennis) {
                $0.leftScore = 4
                $0.rightScore = 3
            } == "4比3"
        )
        #expect(
            try racket(.padel) {
                $0.leftScore = 3
                $0.rightScore = 3
                $0.tennisDeuceMode = PadelDeuceMode.goldenPoint.rawValue
            } == "40比40"
        )
        #expect(
            try racket(.padel, "en") {
                $0.leftScore = 3
                $0.rightScore = 3
                $0.tennisDeuceMode = PadelDeuceMode.starPoint.rawValue
                $0.starPointReturnedAdvantages = 2
            } == "Deuce 3, Star point"
        )
    }

    @Test func officialBreak31WarningsStartAndResumeUseProjectSpecificCalls() throws {
        let state = OfficialBreakState(
            sport: .pickleball,
            kind: .midGame,
            durationSeconds: 60,
            afterAction: .exchangeSides
        )
        let start = OfficialBreakVoiceMapper.payload(
            gameType: .pickleballDoubles,
            cue: .start,
            state: state,
            leftName: "Alice",
            rightName: "Bob",
            leftScore: 6,
            rightScore: 4,
            servingSide: .left,
            serverNumber: 2,
            currentSet: 3
        )
        let startPayload = try #require(start)
        // breakStart 在中文/英文生产播报里静音（策略层已先行过滤）。
        #expect(try VoiceProductionCalls.text(startPayload, "zh-Hans").isEmpty)
        #expect(try VoiceProductionCalls.text(startPayload, "en").isEmpty)

        let resumed = OfficialBreakVoiceMapper.payload(
            gameType: .pingpong,
            cue: .complete,
            state: OfficialBreakState(sport: .pingpong, kind: .gameBreak, durationSeconds: 60),
            leftName: "Alice",
            rightName: "Bob",
            leftScore: 0,
            rightScore: 0,
            servingSide: .right,
            serverName: "Bob",
            currentSet: 2
        )
        let resumedPayload = try #require(resumed)
        #expect(try VoiceProductionCalls.text(resumedPayload, "zh-Hans") == "0比0")
        #expect(try VoiceProductionCalls.text(resumedPayload, "en") == "Time. Bob to serve, love all")

        for (cue, zh, en) in [
            (OfficialBreakCue.twentySeconds, "20秒", "20 seconds"),
            (.halfTime, "休息过半", "Half-time"),
            (.fifteenSeconds, "15秒", "15 seconds"),
            (.time, "时间到", "Time")
        ] {
            let warning = OfficialBreakVoiceMapper.payload(
                gameType: .squash,
                cue: cue,
                state: OfficialBreakState(sport: .squash, kind: .gameBreak, durationSeconds: 90),
                leftName: "Alice",
                rightName: "Bob",
                leftScore: 0,
                rightScore: 0,
                servingSide: .left
            )
            let warningPayload = try #require(warning)
            // 中文全部静音；英文只保留休息过半、15 秒与时间到，
            // 20 秒提示由 breakWarning 的独立策略处理。
            #expect(try VoiceProductionCalls.text(warningPayload, "zh-Hans").isEmpty)
            #expect(try VoiceProductionCalls.text(warningPayload, "en") == (cue == .twentySeconds ? "" : en))
        }
    }
}
