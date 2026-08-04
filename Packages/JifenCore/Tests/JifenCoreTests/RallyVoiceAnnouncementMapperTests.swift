import ScoreCore
import Testing

@Suite("Rally voice event mapper")
struct RallyVoiceAnnouncementMapperTests {
    @Test func badmintonCriticalPointIntervalAndOrderedSideChange() {
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
        #expect(VoiceAnnouncementMessageBuilder.build(interval[0], language: .enUS) == "11-8, interval")
        #expect(VoiceAnnouncementMessageBuilder.build(interval[1], language: .enUS) == "Change ends")

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
        #expect(VoiceAnnouncementMessageBuilder.build(matchPoint[0], language: .zhCN) == "20，赛点，18")

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
        #expect(VoiceAnnouncementMessageBuilder.build(capPoint[0], language: .enUS) == "29, match point, 28")
    }

    @Test func doublesOpeningUsesActualServerAndReceiverSlots() {
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
        #expect(VoiceAnnouncementMessageBuilder.build(pingpongOpening, language: .enUS) == "Carol to serve, love all")

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
            VoiceAnnouncementMessageBuilder.build(badmintonOpening, language: .enUS)
                .contains("to serve to")
        )
    }

    @Test func manualFinishWithoutWinnerIsNeutral() {
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
        #expect(VoiceAnnouncementMessageBuilder.build(payloads[0], language: .zhCN) == "比赛结束")
        #expect(VoiceAnnouncementMessageBuilder.build(payloads[0], language: .enUS) == "Match over")

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
        #expect(VoiceAnnouncementMessageBuilder.build(winnerPayload, language: .zhCN) == "比赛结束，Alice以2比1获胜")
        #expect(VoiceAnnouncementMessageBuilder.build(winnerPayload, language: .enUS) == "Match to Alice. Alice wins 2 games to 1")
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
}
