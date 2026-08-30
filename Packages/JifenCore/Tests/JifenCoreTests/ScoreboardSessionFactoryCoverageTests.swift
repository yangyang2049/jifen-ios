import ScoreCore
import SessionCore
import Testing

@Test func scoreboardSessionFactoryConstructsEveryGameType() async {
    let rallyTypes: [GameType] = [
        .volleyball, .airVolleyball, .beachVolleyball,
        .pingpong, .pingpongDoubles,
        .badminton, .badmintonDoubles,
        .shuttlecock, .squash,
        .pickleball, .pickleballDoubles,
        .foosball, .foosballDoubles
    ]
    let tennisTypes: [GameType] = [.tennis, .tennisDoubles, .softTennis, .padel]
    let lineTypes: [GameType] = [.football, .football5v5, .billiards, .simpleScore]
    var constructedTypes = Set<GameType>()

    for gameType in rallyTypes {
        guard let core = ScoreboardSessionFactory.rally(
            gameType: gameType,
            leftName: "A",
            rightName: "B"
        ) else {
            Issue.record("Missing rally factory route for \(gameType.rawValue)")
            continue
        }
        let session = await core.snapshot()
        #expect(session.gameType == gameType)
        #expect(session.reducerType == ScoreboardKernelRegistry.descriptor(for: gameType).reducerType)
        constructedTypes.insert(session.gameType)
    }

    for gameType in tennisTypes {
        guard let core = ScoreboardSessionFactory.tennis(
            gameType: gameType,
            leftName: "A",
            rightName: "B"
        ) else {
            Issue.record("Missing tennis factory route for \(gameType.rawValue)")
            continue
        }
        let session = await core.snapshot()
        #expect(session.gameType == gameType)
        #expect(session.reducerType == ScoreboardKernelRegistry.descriptor(for: gameType).reducerType)
        constructedTypes.insert(session.gameType)
    }

    for gameType in lineTypes {
        guard let core = ScoreboardSessionFactory.line(
            gameType: gameType,
            leftName: "A",
            rightName: "B"
        ) else {
            Issue.record("Missing line factory route for \(gameType.rawValue)")
            continue
        }
        let session = await core.snapshot()
        #expect(session.gameType == gameType)
        #expect(session.reducerType == ScoreboardKernelRegistry.descriptor(for: gameType).reducerType)
        constructedTypes.insert(session.gameType)
    }

    for gameType in [GameType.basketball, .threeBasketball] {
        guard let core = ScoreboardSessionFactory.basketball(
            gameType: gameType,
            leftName: "A",
            rightName: "B"
        ) else {
            Issue.record("Missing basketball factory route for \(gameType.rawValue)")
            continue
        }
        let session = await core.snapshot()
        #expect(session.gameType == gameType)
        #expect(session.state.gameMode == (gameType == .basketball ? .fiveVFive : .threeXThree))
        #expect(session.reducerType == ScoreboardKernelRegistry.descriptor(for: gameType).reducerType)
        constructedTypes.insert(session.gameType)
    }

    let boxing = await ScoreboardSessionFactory.boxing(leftName: "A", rightName: "B").snapshot()
    let archery = await ScoreboardSessionFactory.archery(leftName: "A", rightName: "B").snapshot()
    let eightBall = await ScoreboardSessionFactory.eightBall(leftName: "A", rightName: "B").snapshot()
    let snooker = await ScoreboardSessionFactory.snooker(leftName: "A", rightName: "B").snapshot()
    let guandan = await ScoreboardSessionFactory.guandan(redName: "A", blueName: "B").snapshot()
    let shengji = await ScoreboardSessionFactory.shengji(leftName: "A", rightName: "B").snapshot()

    guard let nineBallCore = ScoreboardSessionFactory.nineBall(playerNames: ["A", "B"]),
          let doudizhuCore = ScoreboardSessionFactory.doudizhu(playerNames: ["A", "B", "C"]),
          let multiCore = ScoreboardSessionFactory.multiScoreboard(playerNames: ["A", "B", "C"]),
          let unoCore = ScoreboardSessionFactory.uno(playerNames: ["A", "B"]) else {
        Issue.record("Missing multi-player factory routes")
        return
    }
    let nineBall = await nineBallCore.snapshot()
    let doudizhu = await doudizhuCore.snapshot()
    let multi = await multiCore.snapshot()
    let uno = await unoCore.snapshot()

    let fixedSessions: [(GameType, String)] = [
        (boxing.gameType, boxing.reducerType),
        (archery.gameType, archery.reducerType),
        (eightBall.gameType, eightBall.reducerType),
        (nineBall.gameType, nineBall.reducerType),
        (snooker.gameType, snooker.reducerType),
        (guandan.gameType, guandan.reducerType),
        (shengji.gameType, shengji.reducerType),
        (doudizhu.gameType, doudizhu.reducerType),
        (multi.gameType, multi.reducerType),
        (uno.gameType, uno.reducerType)
    ]
    for (gameType, reducerType) in fixedSessions {
        #expect(reducerType == ScoreboardKernelRegistry.descriptor(for: gameType).reducerType)
        constructedTypes.insert(gameType)
    }

    #expect(constructedTypes == Set(GameType.allCases))
}

@Test func scoreboardSessionFactoryRejectsWrongKernelAndInvalidPlayerArity() {
    #expect(
        ScoreboardSessionFactory.basketball(
            gameType: .football,
            leftName: "A",
            rightName: "B"
        ) == nil
    )
    #expect(ScoreboardSessionFactory.nineBall(playerNames: ["A"]) == nil)
    #expect(ScoreboardSessionFactory.nineBall(playerNames: ["A", "B", "C", "D", "E"]) == nil)
    #expect(ScoreboardSessionFactory.doudizhu(playerNames: ["A", "B"]) == nil)
    #expect(ScoreboardSessionFactory.doudizhu(playerNames: ["A", "B", "C", "D"]) == nil)

    #expect(
        ScoreboardSessionFactory.multiParticipant(
            gameType: .football,
            playerNames: ["A", "B", "C"]
        ) == nil
    )

    #expect(ScoreboardSessionFactory.multiScoreboard(playerNames: ["A", "B"]) == nil)
    #expect(ScoreboardSessionFactory.multiScoreboard(playerNames: ["A", "B", "C"]) != nil)
    #expect(
        ScoreboardSessionFactory.multiScoreboard(
            playerNames: (1 ... 9).map { "P\($0)" }
        ) != nil
    )
    #expect(
        ScoreboardSessionFactory.multiScoreboard(
            playerNames: (1 ... 10).map { "P\($0)" }
        ) == nil
    )

    #expect(ScoreboardSessionFactory.uno(playerNames: ["A"]) == nil)
    #expect(ScoreboardSessionFactory.uno(playerNames: ["A", "B"], targetScore: 1) != nil)
    #expect(
        ScoreboardSessionFactory.uno(
            playerNames: (1 ... 10).map { "P\($0)" },
            targetScore: 99_999
        ) != nil
    )
    #expect(
        ScoreboardSessionFactory.uno(
            playerNames: (1 ... 11).map { "P\($0)" }
        ) == nil
    )
    #expect(ScoreboardSessionFactory.uno(playerNames: ["A", "B"], targetScore: 0) == nil)
    #expect(ScoreboardSessionFactory.uno(playerNames: ["A", "B"], targetScore: 100_000) == nil)
    #expect(
        ScoreboardSessionFactory.multiParticipant(
            gameType: .uno,
            playerNames: ["A", "B"],
            customAdjustEnabled: true
        ) == nil
    )
    #expect(
        ScoreboardSessionFactory.multiParticipant(
            gameType: .multiScoreboard,
            playerNames: ["A", "B", "C"],
            targetScore: 500
        ) == nil
    )
}

@Test func scoreboardSessionFactoryProjectsSetupIntoTypedStateAndParticipants() async {
    let basketballCore = ScoreboardSessionFactory.basketball(
        gameType: .threeBasketball,
        leftName: "主队",
        rightName: "客队",
        ruleSet: .nba
    )
    let basketball = await basketballCore?.snapshot()
    #expect(basketball?.state.gameMode == .threeXThree)
    #expect(basketball?.state.ruleSet == .nba)
    #expect(basketball?.participants.map(\.name) == ["主队", "客队"])

    let eightBall = await ScoreboardSessionFactory.eightBall(
        leftName: "A",
        rightName: "B",
        targetPoints: 7,
        handicapRacks: 2,
        handicapBeneficiary: .right
    ).snapshot()
    #expect(eightBall.state.targetPoints == 7)
    #expect(eightBall.state.rightPoints == 2)

    let nineBallCore = ScoreboardSessionFactory.nineBall(playerNames: ["甲", "", "丙"])
    let nineBall = await nineBallCore?.snapshot()
    #expect(nineBall?.state.playerCount == 3)
    #expect(nineBall?.participants.map(\.name) == ["甲", "P2", "丙"])

    let doudizhuCore = ScoreboardSessionFactory.doudizhu(playerNames: ["地主", "农民甲", "农民乙"])
    let doudizhu = await doudizhuCore?.snapshot()
    #expect(doudizhu?.participants.map(\.id) == ["player-0", "player-1", "player-2"])

    let multiCore = ScoreboardSessionFactory.multiScoreboard(
        playerNames: ["甲", "  ", "丙"],
        customAdjustEnabled: true,
        allowRemoveWhileHasScore: true
    )
    let multi = await multiCore?.snapshot()
    #expect(multi?.gameType == .multiScoreboard)
    #expect(multi?.participants.map(\.id) == ["p0", "p1", "p2"])
    #expect(multi?.participants.map(\.name) == ["甲", "P2", "丙"])
    #expect(multi?.state.participants.map(\.name) == ["甲", "P2", "丙"])
    #expect(multi?.state.allowRemoveWhileHasScore == true)
    #expect(multi?.metadata.extras["customAdjustEnabled"] == "true")

    let unoCore = ScoreboardSessionFactory.uno(
        playerNames: ["甲", "乙"],
        targetScore: 750
    )
    let uno = await unoCore?.snapshot()
    #expect(uno?.gameType == .uno)
    #expect(uno?.metadata.extras["targetScore"] == "750")
    #expect(uno?.state.minScore == MultiParticipantState.minimumScore)
    #expect(uno?.state.maxScore == MultiParticipantState.maximumScore)
}
