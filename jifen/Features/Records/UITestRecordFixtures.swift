import RecordCore
import Foundation

enum UITestRecordFixtures {
    @MainActor
    static func installIfRequested() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let shouldClear = arguments.contains("-UITestClearRecordFixtures")
        let shouldInstall = arguments.contains("-UITestRecordFixtures")
        guard shouldClear || shouldInstall else { return }

        let manager = ScoreboardRecordManager.shared
        if shouldClear {
            removeFixtures(from: manager)
            ScoreboardRecordsViewModel.shared.refreshRecordsImmediately()
            return
        }
        removeFixtures(from: manager)
        let gameTypes = GameCatalog.scoreboardItems.map(\.gameType)

        for (index, gameType) in gameTypes.enumerated() {
            let reference = arguments.contains("-MarketingScreenshotFixture")
                ? Date(timeIntervalSince1970: 1_788_321_600)
                : Date()
            let start = reference.addingTimeInterval(TimeInterval(-index * 60))
            var actions: [DetailedScoreAction] = [
                .init(type: .matchStarted, epochMilliseconds: Int64(start.timeIntervalSince1970 * 1_000), scores: [0, 0]),
                .init(type: .scoreChanged, epochMilliseconds: Int64(start.addingTimeInterval(5).timeIntervalSince1970 * 1_000), team: .team1, scores: [1, 0], setNumber: 1, roundNumber: 1, periodNumber: 1, scoreChange: 1, operationCode: "fixture_score"),
                .init(type: .scoreChanged, epochMilliseconds: Int64(start.addingTimeInterval(10).timeIntervalSince1970 * 1_000), team: .team2, scores: [1, 1], setNumber: 1, roundNumber: 1, periodNumber: 1, scoreChange: 1, operationCode: "fixture_score"),
                .init(type: gameType == .basketball ? .periodFinished : .setFinished, epochMilliseconds: Int64(start.addingTimeInterval(15).timeIntervalSince1970 * 1_000), scores: [11, 8], setScores: [1, 0], setNumber: 1, roundNumber: 1, periodNumber: 1, winner: .team1, operationCode: "fixture_section"),
                .init(type: .matchFinished, epochMilliseconds: Int64(start.addingTimeInterval(20).timeIntervalSince1970 * 1_000), scores: [11, 8], setScores: [1, 0], winner: .team1)
            ]
            var duration: TimeInterval = 20
            var final1 = 11, final2 = 8, setScore1 = 1, setScore2 = 0
            if gameType == .pingpong {
                // 真实 3 局完赛:11:8 / 8:11 / 11:9,总时长约 21 分钟,逐分时间线
                let sets: [(Int, Int)] = [(11, 8), (8, 11), (11, 9)]
                actions = [.init(type: .matchStarted, epochMilliseconds: Int64(start.timeIntervalSince1970 * 1_000), scores: [0, 0])]
                var clock: TimeInterval = 0
                var setScores = [0, 0, 0]
                for (setIndex, target) in sets.enumerated() {
                    let seq = pointScorers(target.0, target.1)
                    var points = [0, 0]
                    for (rally, scorer) in seq.enumerated() {
                        clock += TimeInterval(14 + (rally * 7 + setIndex * 5) % 13)
                        points[scorer - 1] += 1
                        actions.append(.init(
                            type: .scoreChanged,
                            epochMilliseconds: Int64(start.addingTimeInterval(clock).timeIntervalSince1970 * 1_000),
                            team: scorer == 1 ? .team1 : .team2,
                            scores: [points[0], points[1]],
                            setNumber: setIndex + 1,
                            scoreChange: 1,
                            operationCode: "fixture_score"
                        ))
                    }
                    clock += 45
                    setScores[target.0 > target.1 ? 0 : 1] += 1
                    actions.append(.init(
                        type: .setFinished,
                        epochMilliseconds: Int64(start.addingTimeInterval(clock).timeIntervalSince1970 * 1_000),
                        scores: [target.0, target.1],
                        setScores: [setScores[0], setScores[1]],
                        setNumber: setIndex + 1,
                        winner: target.0 > target.1 ? .team1 : .team2,
                        operationCode: "fixture_section"
                    ))
                }
                duration = clock
                setScore1 = setScores[0]
                setScore2 = setScores[1]
                final1 = sets.last!.0
                final2 = sets.last!.1
                actions.append(.init(
                    type: .matchFinished,
                    epochMilliseconds: Int64(start.addingTimeInterval(clock).timeIntervalSince1970 * 1_000),
                    scores: [final1, final2],
                    setScores: [setScore1, setScore2],
                    winner: .team1
                ))
            }
            var extra: [String: AnyCodable]? = nil
            if [.nineBall, .doudizhu, .uno, .multiScoreboard].contains(gameType) {
                let count = gameType == .nineBall ? 2 : (gameType == .uno ? 4 : 3)
                let playerFormat = NSLocalizedString("multi_score_player_default_format", value: "玩家 %d", comment: "")
                // UNO 用累计罚分:数值拉开、无 0 分,更像打到中后段
                let unoScores = [35, 18, 52, 27]
                extra = ["players": AnyCodable((1...count).map {
                    ["name": String(format: playerFormat, $0),
                     "score": gameType == .uno ? unoScores[$0 - 1] : 20 - $0]
                })]
            }
            let legacyActions: [String] = gameType == .multiScoreboard
                ? [
                    "\(Int64(start.addingTimeInterval(5).timeIntervalSince1970 * 1_000))|adjust:0:+3",
                    "\(Int64(start.addingTimeInterval(10).timeIntervalSince1970 * 1_000))|adjust:1:-1"
                ]
                : []
            // 商店截图要像真实对局:队名可由启动参数覆盖,缺省仍是本地化的红方/蓝方
            let team1Name = UserDefaults.standard.string(forKey: "UITestRecordTeamName1")
                ?? NSLocalizedString("red_team", comment: "")
            let team2Name = UserDefaults.standard.string(forKey: "UITestRecordTeamName2")
                ?? NSLocalizedString("blue_team", comment: "")
            let record = ScoreboardRecord(
                id: "ui-fixture-\(gameType.canonicalScoreboardIdentifier)",
                gameType: gameType,
                startTime: start,
                endTime: start.addingTimeInterval(duration),
                duration: duration,
                team1Name: team1Name,
                team2Name: team2Name,
                team1FinalScore: final1,
                team2FinalScore: final2,
                team1SetScore: setScore1,
                team2SetScore: setScore2,
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

    /// 按双方目标分比例交错生成得分方序列,结尾恰好为 a:b,走势有交替与小幅连得
    private static func pointScorers(_ a: Int, _ b: Int) -> [Int] {
        var seq: [Int] = []
        var ia = 0, ib = 0
        let total = a + b
        for _ in 0..<total {
            if ia >= a {
                ib += 1; seq.append(2)
            } else if ib >= b {
                ia += 1; seq.append(1)
            } else if Double(ia + 1) / Double(a) <= Double(ib + 1) / Double(b) {
                ia += 1; seq.append(1)
            } else {
                ib += 1; seq.append(2)
            }
        }
        return seq
    }

    private static func removeFixtures(from manager: ScoreboardRecordManager) {
        manager.loadAllRecords()
            .filter { $0.id.hasPrefix("ui-fixture-") }
            .forEach { manager.deleteRecord($0.id) }
    }
}
