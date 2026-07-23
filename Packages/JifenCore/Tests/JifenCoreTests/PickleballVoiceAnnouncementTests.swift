import Testing
import ScoreCore

@Suite struct PickleballVoiceAnnouncementTests {
    private func payload(
        _ gameType: GameType = .pickleball,
        language: VoiceAnnouncementLanguage = .zhCN,
        _ overrides: (inout VoiceAnnouncementPayload) -> Void = { _ in }
    ) -> String {
        var p = VoiceAnnouncementPayload(
            gameType: gameType,
            phase: .scoreChange,
            leftTeamName: "Alice",
            rightTeamName: "Bob",
            leftScore: 0,
            rightScore: 0,
            serverSide: .left
        )
        overrides(&p)
        return VoiceAnnouncementMessageBuilder.build(p, language: language)
    }

    @Test func singlesScoreCall() {
        #expect(
            payload {
                $0.leftScore = 4
                $0.rightScore = 3
                $0.serverSide = .left
            } == "4比3"
        )
        #expect(
            payload(language: .enUS) {
                $0.leftScore = 4
                $0.rightScore = 3
                $0.serverSide = .left
            } == "four, three"
        )
    }

    @Test func doublesOpeningZeroZeroTwo() {
        #expect(
            payload(.pickleballDoubles) {
                $0.serverNumber = 2
            } == "0比0，二号"
        )
        #expect(
            payload(.pickleballDoubles, language: .enUS) {
                $0.serverNumber = 2
            } == "zero, zero, 2"
        )
    }

    @Test func doublesThreeNumberCall() {
        #expect(
            payload(.pickleballDoubles) {
                $0.leftScore = 5
                $0.rightScore = 3
                $0.serverSide = .left
                $0.serverNumber = 2
            } == "5比3，二号"
        )
        #expect(
            payload(.pickleballDoubles, language: .enUS) {
                $0.leftScore = 5
                $0.rightScore = 3
                $0.serverSide = .left
                $0.serverNumber = 1
            } == "five, three, 1"
        )
    }

    @Test func sideOutPrefix() {
        #expect(
            payload(.pickleballDoubles) {
                $0.leftScore = 5
                $0.rightScore = 3
                $0.serverSide = .right
                $0.serverNumber = 1
                $0.serviceOver = true
            } == "换发球，3比5，一号"
        )
        #expect(
            payload(.pickleballDoubles, language: .enUS) {
                $0.leftScore = 5
                $0.rightScore = 3
                $0.serverSide = .right
                $0.serverNumber = 1
                $0.serviceOver = true
            } == "Side out, three, five, 1"
        )
    }

    @Test func mapperEmitsSideOutAndOpening() {
        var rules = RallyRuleSet.pickleball()
        rules.useRallyScoring = false
        let doubles = RallyDoublesState.pickleball(
            playerNames: ["A", "B", "C", "D"],
            servingTeam0: true
        )
        let state = RallyMatchEngine.initial(
            leftName: "Alice",
            rightName: "Bob",
            rules: rules,
            openingServer: .left,
            doubles: doubles
        )
        let opening = RallyVoiceAnnouncementMapper.openingPayload(gameType: .pickleballDoubles, state: state)
        #expect(opening != nil)
        #expect(VoiceAnnouncementMessageBuilder.build(opening!, language: .zhCN) == "0比0，二号")

        let reducer = RallyMatchReducer()
        let sideOutResult = reducer.reduce(state: state, intent: .pointWon(.right), at: 0)
        #expect(sideOutResult.events.contains { if case .sideOut = $0 { return true }; return false })
        let payloads = RallyVoiceAnnouncementMapper.payloads(
            gameType: .pickleballDoubles,
            before: state,
            after: sideOutResult.state,
            events: sideOutResult.events,
            completedSetScores: []
        )
        #expect(payloads.count == 1)
        #expect(payloads[0].serviceOver == true)
        #expect(payloads[0].serverNumber == 1)
        #expect(VoiceAnnouncementMessageBuilder.build(payloads[0], language: .zhCN).contains("换发球"))
    }

    @Test func singlesSideOutAnnouncesNewServerScore() {
        var rules = RallyRuleSet.pickleball()
        rules.useRallyScoring = false
        let state = RallyMatchEngine.initial(
            leftName: "Alice",
            rightName: "Bob",
            rules: rules,
            openingServer: .left
        )
        var afterPoint = state
        afterPoint.leftPoints = 2
        // Simulate scored to 2-0 then side-out
        let mid = RallyMatchReducer().reduce(state: state, intent: .pointWon(.left), at: 0).state
        let mid2 = RallyMatchReducer().reduce(state: mid, intent: .pointWon(.left), at: 1).state
        let sideOut = RallyMatchReducer().reduce(state: mid2, intent: .pointWon(.right), at: 2)
        let payloads = RallyVoiceAnnouncementMapper.payloads(
            gameType: .pickleball,
            before: mid2,
            after: sideOut.state,
            events: sideOut.events,
            completedSetScores: []
        )
        #expect(payloads.count == 1)
        #expect(payloads[0].serverSide == .right)
        #expect(VoiceAnnouncementMessageBuilder.build(payloads[0], language: .zhCN) == "换发球，0比2")
        _ = afterPoint
    }

    @Test func rallyScoringOmitsSideOutPrefix() {
        var rules = RallyRuleSet.pickleball()
        rules.useRallyScoring = true
        let state = RallyMatchEngine.initial(
            leftName: "Alice",
            rightName: "Bob",
            rules: rules,
            openingServer: .left,
            doubles: .pickleball(playerNames: ["A", "B", "C", "D"], servingTeam0: true)
        )
        let scored = RallyMatchReducer().reduce(state: state, intent: .pointWon(.left), at: 0)
        let payloads = RallyVoiceAnnouncementMapper.payloads(
            gameType: .pickleballDoubles,
            before: state,
            after: scored.state,
            events: scored.events,
            completedSetScores: []
        )
        #expect(!payloads.isEmpty)
        #expect(payloads[0].serviceOver != true)
        let zh = VoiceAnnouncementMessageBuilder.build(payloads[0], language: .zhCN)
        #expect(zh.contains("比"))
        #expect(!zh.contains("换发球"))
    }

    @Test func setEndPhraseMatchesRallyTemplate() {
        #expect(
            payload(.pickleball) {
                $0.phase = .setEnd
                $0.leftScore = 11
                $0.rightScore = 7
                $0.leftSets = 1
                $0.rightSets = 0
                $0.currentSet = 1
                $0.winnerSide = .left
                $0.winnerName = "Alice"
            }.contains("Alice")
        )
        #expect(
            payload(.pickleball, language: .enUS) {
                $0.phase = .setEnd
                $0.leftScore = 11
                $0.rightScore = 7
                $0.leftSets = 1
                $0.rightSets = 0
                $0.currentSet = 1
                $0.winnerSide = .left
                $0.winnerName = "Alice"
            }.localizedCaseInsensitiveContains("Alice")
        )
    }
}
