import ScoreCore
import Testing

@Suite("Rally voice event mapper")
struct RallyVoiceAnnouncementMapperTests {
    @Test func badmintonCriticalPointIntervalAndOrderedSideChange() throws {
        var before = RallyMatchEngine.initial(
            leftName: "Alice",
            rightName: "Bob",
            rules: .badminton(maxSets: 3),
            openingServer: .left
        )
        before.leftSets = 1
        before.rightSets = 1
        before.leftPoints = 10
        before.rightPoints = 8

        var after = before
        after.leftPoints = 11
        after.sidesSwapped = true
        let interval = RallyVoiceAnnouncementMapper.payloads(
            gameType: .badminton,
            before: before,
            after: after,
            events: [
                .pointScored(side: .left, leftPoints: 11, rightPoints: 8),
                .sidesExchanged
            ],
            completedSetScores: []
        )
        #expect(interval.map(\.phase) == [.scoreChange, .sideChange])
        #expect(interval[0].isInterval)
        // 英文抢分板：分数 + 间歇与换边都是生产播报。
        #expect(try VoiceProductionCalls.text(interval[0], "en") == "11, 8, interval")
        #expect(try VoiceProductionCalls.text(interval[1], "en") == "Change ends")

        before.leftPoints = 19
        before.rightPoints = 18
        after = before
        after.leftPoints = 20
        let matchPoint = RallyVoiceAnnouncementMapper.payloads(
            gameType: .badminton,
            before: before,
            after: after,
            events: [.pointScored(side: .left, leftPoints: 20, rightPoints: 18)],
            completedSetScores: []
        )
        #expect(matchPoint[0].criticalPoint == .matchPoint)
        // 中文生产播报只念比分，赛点关键词不单独播报（英文仍然念 match point）。
        #expect(try VoiceProductionCalls.text(matchPoint[0], "zh-Hans") == "20比18")

        before.leftPoints = 28
        before.rightPoints = 28
        after = before
        after.leftPoints = 29
        let capPoint = RallyVoiceAnnouncementMapper.payloads(
            gameType: .badminton,
            before: before,
            after: after,
            events: [.pointScored(side: .left, leftPoints: 29, rightPoints: 28)],
            completedSetScores: []
        )
        #expect(capPoint[0].criticalPoint == .matchPoint)
        #expect(try VoiceProductionCalls.text(capPoint[0], "en") == "29, match point, 28")
    }

    @Test func volleyballSupportsVoiceAnnouncementAndReportsServiceOver() throws {
        // 支持集合应包含排球三类（对齐安卓 isVolleyballVoiceType，2026-08-31 补）
        #expect(VoiceAnnouncementSupport.isSupported(.volleyball))
        #expect(VoiceAnnouncementSupport.isSupported(.beachVolleyball))
        #expect(VoiceAnnouncementSupport.isSupported(.airVolleyball))

        var before = RallyMatchEngine.initial(
            leftName: "红队",
            rightName: "蓝队",
            rules: .volleyball(maxSets: 5),
            openingServer: .left
        )
        before.leftPoints = 5
        before.rightPoints = 4
        before.servingSide = .left

        var after = before
        after.leftPoints = 5
        after.rightPoints = 6
        after.servingSide = .right

        let payloads = RallyVoiceAnnouncementMapper.payloads(
            gameType: .volleyball,
            before: before,
            after: after,
            events: [.pointScored(side: .right, leftPoints: 5, rightPoints: 6)],
            completedSetScores: []
        )
        #expect(payloads.map(\.phase) == [.scoreChange])
        #expect(payloads[0].serviceOver == true, "排球得分应播报换发球")
        #expect(payloads[0].criticalPoint == nil, "排球不播局点/赛点，对齐安卓 rallyKeyPoints")
        // 中文生产播报不发换发球前缀，只念换发后的比分。
        #expect(try VoiceProductionCalls.text(payloads[0], "zh-Hans") == "5比6")
    }

    @Test func doublesOpeningUsesActualServerAndReceiverSlots() throws {
        let names = ["Alice", "Bob", "Carol", "David"]
        let pingpong = RallyMatchEngine.initial(
            leftName: "Red",
            rightName: "Blue",
            rules: .pingPong(),
            openingServer: .left,
            doubles: .pingPong(
                playerNames: names,
                openingServerSlotIndex: 2,
                openingReceiverSlotIndex: 3
            )
        )
        let pingpongOpening = RallyVoiceAnnouncementMapper.openingPayload(
            gameType: .pingpongDoubles,
            state: pingpong
        )!
        #expect(pingpongOpening.serverName == "Carol")
        #expect(pingpongOpening.receiverName == "David")
        #expect(try VoiceProductionCalls.text(pingpongOpening, "en") == "Carol to serve, love all")

        let badminton = RallyMatchEngine.initial(
            leftName: "Red",
            rightName: "Blue",
            rules: .badminton(),
            openingServer: .left,
            doubles: .badminton(playerNames: names, servingTeam0: true)
        )
        let badmintonOpening = RallyVoiceAnnouncementMapper.openingPayload(
            gameType: .badmintonDoubles,
            state: badminton
        )!
        #expect(badmintonOpening.serverName == badminton.doubles?.serverName)
        #expect(badmintonOpening.receiverName == badminton.doubles?.receiverName)
        #expect(
            try VoiceProductionCalls.text(badmintonOpening, "en")
                .contains("to serve to")
        )
    }

    @Test func manualFinishWithoutWinnerIsNeutral() throws {
        var state = RallyMatchEngine.initial(
            leftName: "Alice",
            rightName: "Bob",
            rules: .pingPong()
        )
        state.finished = true
        let payloads = RallyVoiceAnnouncementMapper.payloads(
            gameType: .pingpong,
            before: state,
            after: state,
            events: [.matchFinished(winner: nil)],
            completedSetScores: []
        )
        #expect(payloads.count == 1)
        #expect(payloads[0].winnerSide == nil)
        #expect(try VoiceProductionCalls.text(payloads[0], "zh-Hans") == "比赛结束")
        #expect(try VoiceProductionCalls.text(payloads[0], "en") == "Match over")

        state.leftSets = 2
        state.rightSets = 1
        let winnerPayload = RallyVoiceAnnouncementMapper.payloads(
            gameType: .pingpong,
            before: state,
            after: state,
            events: [.matchFinished(winner: .left)],
            completedSetScores: []
        )[0]
        #expect(winnerPayload.isManualEnd)
        #expect(try VoiceProductionCalls.text(winnerPayload, "zh-Hans") == "比赛结果Alice胜2比1")
        #expect(try VoiceProductionCalls.text(winnerPayload, "en") == "Match to Alice. Alice wins 2 games to 1")
    }

    @Test func doublesPayloadTracksRotationForAllRallySports() {
        let names = ["Alice", "Bob", "Carol", "David"]
        let reducer = RallyMatchReducer()

        var pingpong = RallyMatchEngine.initial(
            leftName: "Red",
            rightName: "Blue",
            rules: .pingPong(),
            doubles: .pingPong(playerNames: names)
        )
        let openingServer = pingpong.doubles?.serverName
        pingpong = reducer.reduce(state: pingpong, intent: .pointWon(.left), at: 1).state
        let pingpongTurn = reducer.reduce(state: pingpong, intent: .pointWon(.right), at: 2)
        let pingpongPayload = RallyVoiceAnnouncementMapper.payloads(
            gameType: .pingpongDoubles,
            before: pingpong,
            after: pingpongTurn.state,
            events: pingpongTurn.events,
            completedSetScores: []
        )[0]
        #expect(pingpongTurn.state.doubles?.serverName != openingServer)
        #expect(pingpongPayload.serverName == pingpongTurn.state.doubles?.serverName)
        #expect(pingpongPayload.receiverName == pingpongTurn.state.doubles?.receiverName)

        let badminton = RallyMatchEngine.initial(
            leftName: "Red",
            rightName: "Blue",
            rules: .badminton(),
            doubles: .badminton(playerNames: names)
        )
        let badmintonTurn = reducer.reduce(state: badminton, intent: .pointWon(.right), at: 3)
        let badmintonPayload = RallyVoiceAnnouncementMapper.payloads(
            gameType: .badmintonDoubles,
            before: badminton,
            after: badmintonTurn.state,
            events: badmintonTurn.events,
            completedSetScores: []
        )[0]
        #expect(badmintonPayload.serviceOver)
        #expect(badmintonPayload.serverName == badmintonTurn.state.doubles?.serverName)
        #expect(badmintonPayload.receiverName == badmintonTurn.state.doubles?.receiverName)

        var pickleballRules = RallyRuleSet.pickleball()
        pickleballRules.useRallyScoring = false
        let pickleball = RallyMatchEngine.initial(
            leftName: "Red",
            rightName: "Blue",
            rules: pickleballRules,
            doubles: .pickleball(playerNames: names)
        )
        let sideOut = reducer.reduce(state: pickleball, intent: .pointWon(.right), at: 4)
        let pickleballPayload = RallyVoiceAnnouncementMapper.payloads(
            gameType: .pickleballDoubles,
            before: pickleball,
            after: sideOut.state,
            events: sideOut.events,
            completedSetScores: []
        )[0]
        #expect(pickleballPayload.serverName == sideOut.state.doubles?.serverName)
        #expect(pickleballPayload.receiverName == sideOut.state.doubles?.receiverName)
        #expect(pickleballPayload.serverNumber == sideOut.state.doubles?.pickleballServerNumber)
    }

    @Test func pickleballDoublesFirstServerLossAnnouncesSecondServerNotSideOut() throws {
        var rules = RallyRuleSet.pickleball()
        rules.useRallyScoring = false
        let reducer = RallyMatchReducer()
        let opening = RallyMatchEngine.initial(
            leftName: "Red",
            rightName: "Blue",
            rules: rules,
            doubles: .pickleball(playerNames: ["A", "B", "C", "D"])
        )
        let firstSideOut = reducer.reduce(state: opening, intent: .pointWon(.right), at: 1)
        #expect(firstSideOut.state.servingSide == .right)
        #expect(firstSideOut.state.doubles?.pickleballServerNumber == 1)

        let secondServer = reducer.reduce(state: firstSideOut.state, intent: .pointWon(.left), at: 2)
        let payload = RallyVoiceAnnouncementMapper.payloads(
            gameType: .pickleballDoubles,
            before: firstSideOut.state,
            after: secondServer.state,
            events: secondServer.events,
            completedSetScores: []
        )[0]
        #expect(payload.secondServer)
        #expect(!payload.serviceOver)
        // 中文生产播报只念比分与发球序号（二号）；英文念 "Second server"。
        #expect(try VoiceProductionCalls.text(payload, "zh-Hans") == "0比0、2")
        #expect(try VoiceProductionCalls.text(payload, "en").hasPrefix("Second server"))
    }

    @Test func squashAndShuttlecockAreNoLongerFilteredFromVoiceMapping() throws {
        for (gameType, rules) in [
            (GameType.squash, RallyRuleSet.squash()),
            (.shuttlecock, .shuttlecock())
        ] {
            let before = RallyMatchEngine.initial(leftName: "Alice", rightName: "Bob", rules: rules)
            let result = RallyMatchReducer().reduce(state: before, intent: .pointWon(.left), at: 1)
            let payloads = RallyVoiceAnnouncementMapper.payloads(
                gameType: gameType,
                before: before,
                after: result.state,
                events: result.events,
                completedSetScores: []
            )
            #expect(payloads.count == 1)
            #expect(try !VoiceProductionCalls.text(payloads[0], "zh-Hans").isEmpty)
        }
    }
}
