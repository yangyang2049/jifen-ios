import LinkCore
import RecordCore
import ScoreCore

/// 8 块手表计分板的统一口径表。
///
/// 每块板只提供：联动/本地快照如何由 Reducer State 得到、动作如何投影、
/// 撤销摘要与续赛浮条文案；撤销栈、时间线、续玩 bundle 一律交给
/// `WatchReducerSessionStore`。
enum WatchBoardBindings {
    static func rally(gameType: GameType) -> WatchReducerBinding<RallyMatchReducer> {
        WatchReducerBinding(
            emoji: rallyEmoji(gameType),
            snapshot: { .rally($0) },
            project: { intent, events, state, timestamp in
                ScoreActionProjector.rally(intent: intent, events: events, state: state, timestamp: timestamp)
            },
            undoSummary: {
                WatchReducerUndoSummary(
                    team1Score: $0.leftPoints, team2Score: $0.rightPoints,
                    team1SetScore: $0.leftSets, team2SetScore: $0.rightSets
                )
            },
            scoreLine: {
                $0.leftSets + $0.rightSets > 0
                    ? "\($0.leftSets) - \($0.rightSets)"
                    : "\($0.leftPoints) : \($0.rightPoints)"
            },
            resetsActionLog: { intent in
                if case .reset = intent { return true }
                return false
            },
            payload: { bundle in .rally(gameType: gameType, bundle: bundle, restState: nil) }
        )
    }

    static func tennis(gameType: GameType, isDoubles: Bool) -> WatchReducerBinding<TennisMatchReducer> {
        WatchReducerBinding(
            emoji: "🎾",
            snapshot: { .tennis($0) },
            project: { intent, events, state, timestamp in
                ScoreActionProjector.tennis(intent: intent, events: events, state: state, timestamp: timestamp)
            },
            undoSummary: {
                WatchReducerUndoSummary(
                    team1Score: $0.leftPoints, team2Score: $0.rightPoints,
                    team1SetScore: $0.rules.setScoringMode == .tiebreakOnly ? nil : $0.leftSets,
                    team2SetScore: $0.rules.setScoringMode == .tiebreakOnly ? nil : $0.rightSets
                )
            },
            scoreLine: {
                $0.rules.setScoringMode == .tiebreakOnly
                    ? "\($0.leftPoints) : \($0.rightPoints)"
                    : "\($0.leftSets) - \($0.rightSets)"
            },
            resetsActionLog: { intent in
                if case .reset = intent { return true }
                return false
            },
            payload: { bundle in
                .tennis(isDoubles: isDoubles, bundle: bundle, restState: nil)
            }
        )
    }

    static func archery() -> WatchReducerBinding<ArcheryMatchReducer> {
        WatchReducerBinding(
            emoji: "🏹",
            snapshot: { .archery($0) },
            project: { _, events, state, timestamp in
                ScoreActionProjector.archery(events: events, state: state, timestamp: timestamp)
            },
            undoSummary: {
                WatchReducerUndoSummary(
                    team1Score: $0.leftArrowSum, team2Score: $0.rightArrowSum,
                    team1SetScore: $0.leftSetPoints, team2SetScore: $0.rightSetPoints
                )
            },
            scoreLine: {
                $0.leftSetPoints + $0.rightSetPoints > 0
                    ? "\($0.leftSetPoints) : \($0.rightSetPoints)"
                    : "\($0.leftArrowSum) : \($0.rightArrowSum)"
            },
            resetsActionLog: { intent in
                if case .reset = intent { return true }
                return false
            },
            payload: { bundle in .archery(bundle: bundle, restState: nil) }
        )
    }

    static func eightBall() -> WatchReducerBinding<EightBallReducer> {
        WatchReducerBinding(
            emoji: "🎱",
            snapshot: { .eightBall($0) },
            project: { _, events, state, timestamp in
                ScoreActionProjector.eightBall(events: events, state: state, timestamp: timestamp)
            },
            undoSummary: {
                WatchReducerUndoSummary(team1Score: $0.leftPoints, team2Score: $0.rightPoints)
            },
            scoreLine: { "\($0.leftPoints) : \($0.rightPoints)" },
            resetsActionLog: { intent in
                if case .reset = intent { return true }
                return false
            },
            payload: { bundle in .eightBall(bundle: bundle, leftName: "", rightName: "") }
        )
    }

    static func nineBall() -> WatchReducerBinding<NineBallChaseReducer> {
        WatchReducerBinding(
            emoji: "🎱",
            snapshot: { .nineBall($0) },
            project: { _, events, state, timestamp in
                ScoreActionProjector.nineBall(events: events, state: state, timestamp: timestamp)
            },
            undoSummary: {
                WatchReducerUndoSummary(
                    team1Score: $0.playerPoints.indices.contains(0) ? $0.playerPoints[0] : 0,
                    team2Score: $0.playerPoints.indices.contains(1) ? $0.playerPoints[1] : 0
                )
            },
            scoreLine: {
                $0.playerPoints.prefix(max(0, $0.playerCount)).map(String.init).joined(separator: " · ")
            },
            resetsActionLog: { intent in
                if case .resetScores = intent { return true }
                return false
            },
            payload: { bundle in .nineBall(bundle: bundle) }
        )
    }

    static func snooker() -> WatchReducerBinding<SnookerReducer> {
        WatchReducerBinding(
            emoji: "🎱",
            snapshot: { .snooker($0) },
            project: { intent, events, state, timestamp in
                ScoreActionProjector.snooker(intent: intent, events: events, state: state, timestamp: timestamp)
            },
            undoSummary: {
                WatchReducerUndoSummary(
                    team1Score: $0.leftScore, team2Score: $0.rightScore,
                    team1SetScore: $0.leftFrames, team2SetScore: $0.rightFrames
                )
            },
            scoreLine: { "\($0.leftFrames)-\($0.rightFrames) / \($0.leftScore):\($0.rightScore)" },
            resetsActionLog: { intent in
                if case .reset = intent { return true }
                return false
            },
            payload: { bundle in .snooker(bundle: bundle, leftName: "", rightName: "") }
        )
    }

    static func football(isFiveAside: Bool) -> WatchReducerBinding<FootballMatchReducer> {
        WatchReducerBinding(
            emoji: "⚽",
            snapshot: { .football($0) },
            project: { intent, events, state, timestamp in
                ScoreActionProjector.football(intent: intent, events: events, state: state, timestamp: timestamp)
            },
            undoSummary: {
                WatchReducerUndoSummary(team1Score: $0.leftScore, team2Score: $0.rightScore)
            },
            scoreLine: { "\($0.leftScore) - \($0.rightScore)" },
            resetsActionLog: { intent in
                if case .reset = intent { return true }
                return false
            },
            payload: { bundle in .football(isFiveAside: isFiveAside, bundle: bundle) }
        )
    }

    static func shotTraining(mode: ShotTrainingMode) -> WatchReducerBinding<ShotTrainingReducer> {
        WatchReducerBinding(
            emoji: "🏀",
            snapshot: { .basketballTraining($0) },
            project: { intent, events, state, timestamp in
                ScoreActionProjector.shotTraining(intent: intent, events: events, state: state, timestamp: timestamp)
            },
            undoSummary: {
                WatchReducerUndoSummary(team1Score: $0.counts.missed, team2Score: $0.counts.made)
            },
            scoreLine: {
                let counts = $0.counts
                let attempts = max(1, counts.attempts)
                let percentage = Int((Double(counts.made) / Double(attempts) * 100).rounded())
                return "\(counts.made)/\(counts.attempts) = \(percentage)%"
            },
            resetsActionLog: { intent in
                if case .reset = intent { return true }
                return false
            },
            payload: { bundle in .basketballTraining(bundle: bundle) }
        )
    }

    private static func rallyEmoji(_ gameType: GameType) -> String {
        switch gameType {
        case .badminton, .badmintonDoubles, .shuttlecock: return "🏸"
        case .pingpong, .pingpongDoubles: return "🏓"
        case .pickleball, .pickleballDoubles: return "🏓"
        case .squash: return "🎾"
        case .foosball, .foosballDoubles: return "⚽"
        default: return "🏆"
        }
    }
}
