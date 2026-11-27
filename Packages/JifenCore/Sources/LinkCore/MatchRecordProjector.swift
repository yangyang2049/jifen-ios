import Foundation
import RecordCore
import ScoreCore

/// M2 统一记录投影器：从 LinkCore.LinkedScoreboardSnapshot 权威快照原子构建
/// CanonicalMatchRecord（手表联动完赛、手机摄取共用一个口径）。
public enum MatchRecordProjector {
    /// 单条投影结果（比分/局分/胜者/参与者/项目配置已按运动类型填充）。
    public struct SnapshotProjection {
        public let team1Name: String
        public let team2Name: String
        public let team1FinalScore: Int
        public let team2FinalScore: Int
        public let team1SetScore: Int?
        public let team2SetScore: Int?
        public let winnerIdentity: ScoreboardWinnerIdentity?
        public let participants: [RecordParticipantScore]?
        public let projectConfiguration: [String: String]

        init(
            team1Name: String,
            team2Name: String,
            team1FinalScore: Int,
            team2FinalScore: Int,
            team1SetScore: Int?,
            team2SetScore: Int?,
            winnerIdentity: ScoreboardWinnerIdentity?,
            participants: [RecordParticipantScore]?,
            projectConfiguration: [String: String]
        ) {
            self.team1Name = team1Name
            self.team2Name = team2Name
            self.team1FinalScore = team1FinalScore
            self.team2FinalScore = team2FinalScore
            self.team1SetScore = team1SetScore
            self.team2SetScore = team2SetScore
            self.winnerIdentity = winnerIdentity
            self.participants = participants
            self.projectConfiguration = projectConfiguration
        }
    }

    /// 从快照提取展示/胜者/配置投影。winnerSide 缺省时按比分定胜者（平局 nil）。
    public static func project(
        snapshot: LinkedScoreboardSnapshot,
        gameType: ScoreCore.GameType,
        winnerSide: MatchSide?,
        participantNames: [String],
        source: RecordSource = .linkedWatch
    ) -> SnapshotProjection {
        let isStandalone = source == .watchLocal
        func resolvedWinner(fallbackLeft: Int, fallbackRight: Int) -> ScoreboardWinnerIdentity? {
            switch winnerSide {
            case .left:
                return .team(.team0)
            case .right:
                return .team(.team1)
            case nil:
                if fallbackLeft == fallbackRight { return nil }
                return fallbackLeft > fallbackRight ? .team(.team0) : .team(.team1)
            }
        }

        switch snapshot {
        case .rally(let state):
            return SnapshotProjection(
                team1Name: state.leftName,
                team2Name: state.rightName,
                team1FinalScore: state.leftPoints,
                team2FinalScore: state.rightPoints,
                team1SetScore: state.leftSets,
                team2SetScore: state.rightSets,
                winnerIdentity: resolvedWinner(
                    fallbackLeft: state.leftSets, fallbackRight: state.rightSets
                ),
                participants: state.doubles?.playerNames.map {
                    RecordParticipantScore(name: $0, score: 0)
                },
                projectConfiguration: [
                    "scoreCoreGameType": gameType.rawValue,
                    "isSingles": String(state.doubles == nil),
                    "isDoubles": String(state.doubles != nil),
                    "maxSets": String(state.rules.maxSets),
                    "pointsPerSet": String(state.rules.pointsToWinSet),
                    "useRallyScoring": String(state.rules.useRallyScoring),
                    "rallyScoring": String(state.rules.useRallyScoring)
                ]
            )
        case .tennis(let state):
            let isTiebreakOnly = state.rules.setScoringMode == .tiebreakOnly
            let fallbackLeft = isTiebreakOnly ? state.leftPoints : state.leftSets
            let fallbackRight = isTiebreakOnly ? state.rightPoints : state.rightSets
            return SnapshotProjection(
                team1Name: state.leftName,
                team2Name: state.rightName,
                team1FinalScore: isTiebreakOnly || isStandalone ? state.leftPoints : state.leftGames,
                team2FinalScore: isTiebreakOnly || isStandalone ? state.rightPoints : state.rightGames,
                // iPhone v5 原样：抢七局模式下局分为 nil。
                team1SetScore: isTiebreakOnly ? nil : state.leftSets,
                team2SetScore: isTiebreakOnly ? nil : state.rightSets,
                winnerIdentity: resolvedWinner(
                    fallbackLeft: fallbackLeft, fallbackRight: fallbackRight
                ),
                participants: state.doublesPlayerNames?.map {
                    RecordParticipantScore(name: $0, score: 0)
                },
                projectConfiguration: [
                    "scoreCoreGameType": gameType.rawValue,
                    "isSingles": String(state.doublesPlayerNames == nil),
                    "isDoubles": String(state.doublesPlayerNames != nil),
                    "maxSets": String(state.rules.maxSets),
                    "tieBreakPoints": String(state.rules.tieBreakPoints),
                    "setScoringMode": state.rules.setScoringMode.rawValue,
                    "usesNoAdScoring": String(state.rules.usesNoAdScoring)
                ]
            )
        case .archery(let state):
            return SnapshotProjection(
                team1Name: state.leftName,
                team2Name: state.rightName,
                team1FinalScore: isStandalone ? state.leftSetPoints : state.leftArrowSum,
                team2FinalScore: isStandalone ? state.rightSetPoints : state.rightArrowSum,
                team1SetScore: state.leftSetPoints,
                team2SetScore: state.rightSetPoints,
                winnerIdentity: resolvedWinner(
                    fallbackLeft: state.leftSetPoints, fallbackRight: state.rightSetPoints
                ),
                participants: [
                    RecordParticipantScore(name: state.leftName, score: state.leftSetPoints),
                    RecordParticipantScore(name: state.rightName, score: state.rightSetPoints)
                ],
                projectConfiguration: [
                    "scoreCoreGameType": gameType.rawValue
                ]
            )
        case .eightBall(let state):
            return SnapshotProjection(
                team1Name: resolvedName(participantNames, 0, fallback: "八球选手 1"),
                team2Name: resolvedName(participantNames, 1, fallback: "八球选手 2"),
                team1FinalScore: state.leftPoints,
                team2FinalScore: state.rightPoints,
                team1SetScore: isStandalone ? state.leftPoints : nil,
                team2SetScore: isStandalone ? state.rightPoints : nil,
                winnerIdentity: resolvedWinner(
                    fallbackLeft: state.leftPoints, fallbackRight: state.rightPoints
                ),
                participants: nil,
                projectConfiguration: [
                    "scoreCoreGameType": gameType.rawValue,
                    "targetRacks": String(state.targetPoints),
                    "handicapRacks": String(state.handicapRacks),
                    "handicapBeneficiary": state.handicapBeneficiary?.rawValue ?? "none"
                ]
            )
        case .nineBall(let state):
            let count = max(2, state.playerCount)
            let points: [Int] = (0..<count).map { index in
                state.playerPoints.indices.contains(index) ? state.playerPoints[index] : 0
            }
            let names = (0..<count).map { index in
                state.resolvedName(
                    at: index,
                    fallback: resolvedName(participantNames, index, fallback: "选手 \(index + 1)")
                )
            }
            let winner: ScoreboardWinnerIdentity? = {
                if count == 2, let winnerSide {
                    return .participant(index: winnerSide == .left ? 0 : 1)
                }
                guard let best = points.max() else { return nil }
                let leaders = points.indices.filter { points[$0] == best }
                return leaders.count == 1 ? .participant(index: leaders[0]) : nil
            }()
            return SnapshotProjection(
                team1Name: names[0],
                team2Name: names[1],
                team1FinalScore: points[0],
                team2FinalScore: points[1],
                team1SetScore: isStandalone ? points[0] : nil,
                team2SetScore: isStandalone ? points[1] : nil,
                winnerIdentity: winner,
                participants: (0..<count).map { index in
                    RecordParticipantScore(name: names[index], score: points[index])
                },
                projectConfiguration: [
                    "scoreCoreGameType": gameType.rawValue,
                    "playerCount": String(count)
                ]
            )
        case .snooker(let state):
            let fallbackLeft = state.leftFrames != state.rightFrames ? state.leftFrames : state.leftScore
            let fallbackRight = state.leftFrames != state.rightFrames ? state.rightFrames : state.rightScore
            return SnapshotProjection(
                team1Name: resolvedName(participantNames, 0, fallback: "斯诺克选手 1"),
                team2Name: resolvedName(participantNames, 1, fallback: "斯诺克选手 2"),
                team1FinalScore: state.leftScore,
                team2FinalScore: state.rightScore,
                team1SetScore: state.leftFrames,
                team2SetScore: state.rightFrames,
                winnerIdentity: resolvedWinner(
                    fallbackLeft: fallbackLeft, fallbackRight: fallbackRight
                ),
                participants: nil,
                projectConfiguration: [
                    "scoreCoreGameType": gameType.rawValue,
                    "maxFrames": String(state.maxFrames)
                ]
            )
        case .football(let state):
            return SnapshotProjection(
                team1Name: state.leftName,
                team2Name: state.rightName,
                team1FinalScore: state.leftScore,
                team2FinalScore: state.rightScore,
                team1SetScore: nil,
                team2SetScore: nil,
                winnerIdentity: resolvedWinner(
                    fallbackLeft: state.leftScore, fallbackRight: state.rightScore
                ),
                participants: nil,
                projectConfiguration: [
                    "scoreCoreGameType": gameType.rawValue,
                    "footballHalfLengthSeconds": String(state.timer.halfLengthSeconds),
                    "showMatchTime": "true"
                ]
            )
        case .basketballTraining(let state):
            let counts = state.counts
            return SnapshotProjection(
                team1Name: resolvedName(
                    participantNames, 0, fallback: NSLocalizedString("shot_training_miss", value: "未中", comment: "")
                ),
                team2Name: resolvedName(
                    participantNames, 1, fallback: NSLocalizedString("shot_training_made", value: "命中", comment: "")
                ),
                team1FinalScore: counts.missed,
                team2FinalScore: counts.made,
                team1SetScore: nil,
                team2SetScore: nil,
                winnerIdentity: nil,
                participants: nil,
                projectConfiguration: [
                    "scoreCoreGameType": gameType.rawValue,
                    "type": "basketball_training",
                    "basketballTrainingScoringMode": state.mode.rawValue
                ]
            )
        }
    }

    private static func resolvedName(_ names: [String], _ index: Int, fallback: String) -> String {
        guard names.indices.contains(index) else { return fallback }
        let trimmed = names[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// 原子构建 CanonicalMatchRecord（完赛载荷/回传记录的唯一入口）。
    public static func canonicalRecord(
        id: String,
        kind: RecordGameKind,
        source: RecordSource,
        snapshot: LinkedScoreboardSnapshot,
        gameType: ScoreCore.GameType,
        winnerSide: MatchSide?,
        startEpochMilliseconds: Int64,
        endEpochMilliseconds: Int64,
        durationSeconds: Double,
        participantNames: [String],
        detailedActions: [DetailedScoreAction],
        totalScoreChanges: Int,
        additionalConfiguration: [String: String] = [:]
    ) -> CanonicalMatchRecord {
        let projection = project(
            snapshot: snapshot,
            gameType: gameType,
            winnerSide: winnerSide,
            participantNames: participantNames,
            source: source
        )
        let training: ScoreCore.ShotTrainingState?
        var effectiveActions = detailedActions
        var effectiveTotalChanges = totalScoreChanges
        if case .basketballTraining(let state) = snapshot {
            training = state
            // 投篮训练：即使调用方传空明细/0 总数，也必须从状态本身得到动作
            // 和完整尝试数（含 earlierCounts 折叠部分）。
            if effectiveActions.isEmpty {
                effectiveActions = state.detailedActions(endingAt: Date(
                    timeIntervalSince1970: Double(endEpochMilliseconds) / 1_000
                ))
            }
            if effectiveTotalChanges == 0 {
                effectiveTotalChanges = state.counts.attempts
            }
        } else {
            training = nil
        }
        return CanonicalMatchRecord(
            id: id,
            kind: kind,
            source: source,
            startEpochMilliseconds: startEpochMilliseconds,
            endEpochMilliseconds: endEpochMilliseconds,
            durationSeconds: durationSeconds,
            team1Name: projection.team1Name,
            team2Name: projection.team2Name,
            team1FinalScore: projection.team1FinalScore,
            team2FinalScore: projection.team2FinalScore,
            team1SetScore: projection.team1SetScore,
            team2SetScore: projection.team2SetScore,
            winnerIdentity: projection.winnerIdentity,
            detailedActions: effectiveActions,
            totalScoreChanges: effectiveTotalChanges,
            participants: projection.participants,
            projectConfiguration: projection.projectConfiguration.merging(additionalConfiguration) { _, additional in additional },
            basketballTraining: training
        )
    }
}
