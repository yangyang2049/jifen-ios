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
            let actions: [DetailedScoreAction] = [
                .init(type: .matchStarted, epochMilliseconds: Int64(start.timeIntervalSince1970 * 1_000), scores: [0, 0]),
                .init(type: .scoreChanged, epochMilliseconds: Int64(start.addingTimeInterval(5).timeIntervalSince1970 * 1_000), team: .team1, scores: [1, 0], setNumber: 1, roundNumber: 1, periodNumber: 1, scoreChange: 1, operationCode: "fixture_score"),
                .init(type: .scoreChanged, epochMilliseconds: Int64(start.addingTimeInterval(10).timeIntervalSince1970 * 1_000), team: .team2, scores: [1, 1], setNumber: 1, roundNumber: 1, periodNumber: 1, scoreChange: 1, operationCode: "fixture_score"),
                .init(type: gameType == .basketball ? .periodFinished : .setFinished, epochMilliseconds: Int64(start.addingTimeInterval(15).timeIntervalSince1970 * 1_000), scores: [11, 8], setScores: [1, 0], setNumber: 1, roundNumber: 1, periodNumber: 1, winner: .team1, operationCode: "fixture_section"),
                .init(type: .matchFinished, epochMilliseconds: Int64(start.addingTimeInterval(20).timeIntervalSince1970 * 1_000), scores: [11, 8], setScores: [1, 0], winner: .team1)
            ]
            var extra: [String: AnyCodable]? = nil
            if [.nineBall, .doudizhu, .uno, .multiScoreboard].contains(gameType) {
                let count = gameType == .nineBall ? 2 : (gameType == .uno ? 4 : 3)
                let playerFormat = NSLocalizedString("multi_score_player_default_format", value: "玩家 %d", comment: "")
                extra = ["players": AnyCodable((1...count).map { ["name": String(format: playerFormat, $0), "score": 20 - $0] })]
            }
            let record = ScoreboardRecord(
                id: "ui-fixture-\(gameType.canonicalScoreboardIdentifier)",
                gameType: gameType,
                startTime: start,
                endTime: start.addingTimeInterval(20),
                duration: 20,
                team1Name: NSLocalizedString("red_team", comment: ""),
                team2Name: NSLocalizedString("blue_team", comment: ""),
                team1FinalScore: 11,
                team2FinalScore: 8,
                team1SetScore: 1,
                team2SetScore: 0,
                winner: "left",
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
