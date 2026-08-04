import RecordCore
import Foundation

enum UITestRecordFixtures {
    @MainActor
    static func installIfRequested() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let manager = ScoreboardRecordManager.shared
        if arguments.contains("-UITestClearRecordFixtures") {
            removeFixtures(from: manager)
            ScoreboardRecordsViewModel.shared.refreshRecordsImmediately()
            return
        }
        guard arguments.contains("-UITestRecordFixtures") else { return }
        removeFixtures(from: manager)
        let gameTypes: [GameType] = [
            .pingpong, .badminton, .tennis, .pickleball, .football, .basketball,
            .threeBasketball, .volleyball, .beachVolleyball, .airVolleyball, .archery,
            .boxing, .billiards, .eightBall, .nineBall, .snooker, .doudizhu,
            .guandan, .shengji, .uno, .foosball, .simpleScore, .multiScoreboard
        ]

        for (index, gameType) in gameTypes.enumerated() {
            let start = Date().addingTimeInterval(TimeInterval(-index * 60))
            var actions: [DetailedScoreAction] = [
                .init(type: .matchStarted, epochMilliseconds: Int64(start.timeIntervalSince1970 * 1_000), scores: [0, 0]),
                .init(type: .scoreChanged, epochMilliseconds: Int64(start.addingTimeInterval(5).timeIntervalSince1970 * 1_000), team: .team1, scores: [1, 0], setNumber: 1, roundNumber: 1, periodNumber: 1, scoreChange: 1, operationCode: "fixture_score"),
                .init(type: .scoreChanged, epochMilliseconds: Int64(start.addingTimeInterval(10).timeIntervalSince1970 * 1_000), team: .team2, scores: [1, 1], setNumber: 1, roundNumber: 1, periodNumber: 1, scoreChange: 1, operationCode: "fixture_score"),
                .init(type: gameType == .basketball ? .periodFinished : .setFinished, epochMilliseconds: Int64(start.addingTimeInterval(15).timeIntervalSince1970 * 1_000), scores: [11, 8], setScores: [1, 0], setNumber: 1, roundNumber: 1, periodNumber: 1, winner: .team1, operationCode: "fixture_section"),
                .init(type: .matchFinished, epochMilliseconds: Int64(start.addingTimeInterval(20).timeIntervalSince1970 * 1_000), scores: [11, 8], setScores: [1, 0], winner: .team1)
            ]
            if gameType == .pingpong {
                actions = [
                    .init(type: .matchStarted, epochMilliseconds: Int64(start.timeIntervalSince1970 * 1_000), scores: [0, 0]),
                    .init(type: .scoreChanged, epochMilliseconds: Int64(start.addingTimeInterval(5).timeIntervalSince1970 * 1_000), team: .team1, scores: [1, 0], setNumber: 1, scoreChange: 1, operationCode: "fixture_score"),
                    .init(type: .scoreChanged, epochMilliseconds: Int64(start.addingTimeInterval(8).timeIntervalSince1970 * 1_000), team: .team2, scores: [1, 1], setNumber: 1, scoreChange: 1, operationCode: "fixture_score"),
                    .init(type: .scoreChanged, epochMilliseconds: Int64(start.addingTimeInterval(11).timeIntervalSince1970 * 1_000), team: .team1, scores: [2, 1], setNumber: 1, scoreChange: 1, operationCode: "fixture_score"),
                    .init(type: .setFinished, epochMilliseconds: Int64(start.addingTimeInterval(15).timeIntervalSince1970 * 1_000), scores: [2, 1], setScores: [1, 0], setNumber: 1, winner: .team1, operationCode: "fixture_section"),
                    .init(type: .scoreChanged, epochMilliseconds: Int64(start.addingTimeInterval(20).timeIntervalSince1970 * 1_000), team: .team2, scores: [0, 1], setNumber: 2, scoreChange: 1, operationCode: "fixture_score"),
                    .init(type: .scoreChanged, epochMilliseconds: Int64(start.addingTimeInterval(23).timeIntervalSince1970 * 1_000), team: .team1, scores: [1, 1], setNumber: 2, scoreChange: 1, operationCode: "fixture_score"),
                    .init(type: .scoreChanged, epochMilliseconds: Int64(start.addingTimeInterval(26).timeIntervalSince1970 * 1_000), team: .team1, scores: [2, 1], setNumber: 2, scoreChange: 1, operationCode: "fixture_score"),
                    .init(type: .setFinished, epochMilliseconds: Int64(start.addingTimeInterval(30).timeIntervalSince1970 * 1_000), scores: [2, 1], setScores: [2, 0], setNumber: 2, winner: .team1, operationCode: "fixture_section"),
                    .init(type: .matchFinished, epochMilliseconds: Int64(start.addingTimeInterval(35).timeIntervalSince1970 * 1_000), scores: [2, 1], setScores: [2, 0], winner: .team1)
                ]
            }
            var extra: [String: AnyCodable]? = nil
            if [.nineBall, .doudizhu, .uno, .multiScoreboard].contains(gameType) {
                let count = gameType == .nineBall ? 2 : (gameType == .uno ? 4 : 3)
                let playerFormat = NSLocalizedString("multi_score_player_default_format", value: "玩家 %d", comment: "")
                extra = ["players": AnyCodable((1...count).map { ["name": String(format: playerFormat, $0), "score": 20 - $0] })]
            }
            let legacyActions: [String] = gameType == .multiScoreboard
                ? [
                    "\(Int64(start.addingTimeInterval(5).timeIntervalSince1970 * 1_000))|adjust:0:+3",
                    "\(Int64(start.addingTimeInterval(10).timeIntervalSince1970 * 1_000))|adjust:1:-1"
                ]
                : []
            let record = ScoreboardRecord(
                id: "ui-fixture-\(gameType.canonicalScoreboardIdentifier)",
                gameType: gameType,
                startTime: start,
                endTime: start.addingTimeInterval(gameType == .pingpong ? 35 : 20),
                duration: gameType == .pingpong ? 35 : 20,
                team1Name: NSLocalizedString("red_team", comment: ""),
                team2Name: NSLocalizedString("blue_team", comment: ""),
                team1FinalScore: 11,
                team2FinalScore: 8,
                team1SetScore: gameType == .pingpong ? 2 : 1,
                team2SetScore: 0,
                winner: "left",
                actions: legacyActions,
                detailedActions: actions,
                setResults: ScoreboardRecordActionAdapter.setResults(from: actions),
                totalScoreChanges: actions.count,
                extraData: extra,
                status: .finished
            )
            try? manager.saveScoreboardRecord(record)
        }
        ScoreboardRecordsViewModel.shared.refreshRecordsImmediately()
        #endif
    }

    private static func removeFixtures(from manager: ScoreboardRecordManager) {
        manager.loadAllRecords()
            .filter { $0.id.hasPrefix("ui-fixture-") }
            .forEach { _ = manager.deleteRecord($0.id) }
    }
}
