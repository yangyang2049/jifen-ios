import ScoreCore
import Testing

@Suite struct PickleballVoiceAnnouncementTests {
    /// 生产播报：`buildReviewed` 加真实 `ScoreVoice.strings`。
    private func call(
        _ gameType: GameType = .pickleball,
        _ code: String = "zh-Hans",
        _ overrides: (inout VoiceAnnouncementPayload) -> Void = { _ in }
    ) throws -> String {
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
        return try VoiceProductionCalls.text(p, code)
    }

    @Test func singlesScoreCall() throws {
        #expect(
            try call {
                $0.leftScore = 4
                $0.rightScore = 3
                $0.serverSide = .left
            } == "4比3"
        )
        #expect(
            try call(.pickleball, "en") {
                $0.leftScore = 4
                $0.rightScore = 3
                $0.serverSide = .left
            } == "four, three"
        )
    }

    @Test func doublesOpeningZeroZeroTwo() throws {
        #expect(
            try call(.pickleballDoubles) {
                $0.serverNumber = 2
            } == "0比0、2"
        )
        #expect(
            try call(.pickleballDoubles, "en") {
                $0.serverNumber = 2
            } == "zero, zero, 2"
        )
    }

    @Test func doublesThreeNumberCall() throws {
        #expect(
            try call(.pickleballDoubles) {
                $0.leftScore = 5
                $0.rightScore = 3
                $0.serverSide = .left
                $0.serverNumber = 2
            } == "5比3、2"
        )
        #expect(
            try call(.pickleballDoubles, "en") {
                $0.leftScore = 5
                $0.rightScore = 3
                $0.serverSide = .left
                $0.serverNumber = 1
            } == "five, three, 1"
        )
    }

    @Test func sideOutPrefix() throws {
        #expect(
            try call(.pickleballDoubles) {
                $0.leftScore = 5
                $0.rightScore = 3
                $0.serverSide = .right
                $0.serverNumber = 1
                $0.serviceOver = true
            } == "3比5、1"
        )
        #expect(
            try call(.pickleballDoubles, "en") {
                $0.leftScore = 5
                $0.rightScore = 3
                $0.serverSide = .right
                $0.serverNumber = 1
                $0.serviceOver = true
            } == "Side out, three, five, 1"
        )
    }

    @Test func mapperEmitsSideOutAndOpening() throws {
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
        #expect(try VoiceProductionCalls.text(try #require(opening), "zh-Hans") == "0比0、2")

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
        // 中文生产播报不发换发球前缀，只念换发后的比分与发球序号。
        #expect(try VoiceProductionCalls.text(payloads[0], "zh-Hans") == "0比0、1")
    }

    @Test func singlesSideOutAnnouncesNewServerScore() throws {
        var rules = RallyRuleSet.pickleball()
        rules.useRallyScoring = false
        let state = RallyMatchEngine.initial(
            leftName: "Alice",
            rightName: "Bob",
            rules: rules,
            openingServer: .left
        )
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
        #expect(try VoiceProductionCalls.text(payloads[0], "zh-Hans") == "0比2")
    }

    @Test func rallyScoringOmitsSideOutPrefix() throws {
        var rules = RallyRuleSet.pickleball()
        rules.useRallyScoring = true
        let state = RallyMatchEngine.initial(
            leftName: "Alice",
            rightName: "Bob",
            rules: rules,
            openingServer: .left,
            doubles: .pickleball(playerNames: ["A", "B", "C", "D"], servingTeam0: true)
        )
        let opening = RallyVoiceAnnouncementMapper.openingPayload(
            gameType: .pickleballDoubles,
            state: state
        )
        #expect(opening?.serverNumber == nil)
        #expect(try VoiceProductionCalls.text(try #require(opening), "zh-Hans") == "0比0")

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
        #expect(payloads[0].serverNumber == nil)
        let zh = try VoiceProductionCalls.text(payloads[0], "zh-Hans")
        #expect(zh.contains("比"))
        #expect(!zh.contains("换发球"))
    }

    /// 匹克球局末/赛末在中文与英文生产播报里只念比分（结果由官方结果播报负责）。
    @Test func gameAndMatchEndSpeakProductionScores() throws {
        #expect(
            try call(.pickleball) {
                $0.phase = .setEnd
                $0.leftScore = 11
                $0.rightScore = 7
                $0.leftSets = 1
                $0.rightSets = 0
                $0.currentSet = 1
                $0.winnerSide = .left
                $0.winnerName = "Alice"
            } == "11比7"
        )
        #expect(
            try call(.pickleball, "en") {
                $0.phase = .setEnd
                $0.leftScore = 11
                $0.rightScore = 7
                $0.leftSets = 1
                $0.rightSets = 0
                $0.currentSet = 1
                $0.winnerSide = .left
                $0.winnerName = "Alice"
            } == "11, 7"
        )
        #expect(
            try call(.pickleball, "en") {
                $0.phase = .matchEnd
                $0.leftScore = 11
                $0.rightScore = 7
                $0.leftSets = 2
                $0.rightSets = 0
                $0.winnerSide = .left
                $0.winnerName = "Alice"
            } == "11, 7"
        )
    }
}
