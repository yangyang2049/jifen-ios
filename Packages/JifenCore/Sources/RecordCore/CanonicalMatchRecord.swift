import Foundation
import ScoreCore

/// 规范记录的游戏类别：正式运动（带 ScoreCore 项目类型）或纯计数器工具。
public enum RecordGameKind: Codable, Equatable, Hashable, Sendable {
    case sport(ScoreCore.GameType)
    case counter
}

public struct RecordParticipantScore: Codable, Equatable, Sendable {
    public let name: String
    public let score: Int

    public init(name: String, score: Int) {
        self.name = name
        self.score = score
    }
}

/// M2 规范比赛记录：手表本地存储、手表→手机回传、联动完赛的统一载荷。
/// 手机端经 WatchCanonicalRecordAdapter 摄取为现有 schema v5 ScoreboardRecord。
public struct CanonicalMatchRecord: Codable, Equatable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let id: String
    public let kind: RecordGameKind
    public let source: RecordSource
    public let startEpochMilliseconds: Int64
    public let endEpochMilliseconds: Int64
    public let durationSeconds: Double
    public let team1Name: String
    public let team2Name: String
    public let team1FinalScore: Int
    public let team2FinalScore: Int
    public let team1SetScore: Int?
    public let team2SetScore: Int?
    public let winnerIdentity: ScoreboardWinnerIdentity?
    public let detailedActions: [DetailedScoreAction]
    public let totalScoreChanges: Int
    public let participants: [RecordParticipantScore]?
    public let projectConfiguration: [String: String]
    public let basketballTraining: ScoreCore.ShotTrainingState?

    public init(
        id: String,
        kind: RecordGameKind,
        source: RecordSource,
        startEpochMilliseconds: Int64,
        endEpochMilliseconds: Int64,
        durationSeconds: Double,
        team1Name: String,
        team2Name: String,
        team1FinalScore: Int,
        team2FinalScore: Int,
        team1SetScore: Int? = nil,
        team2SetScore: Int? = nil,
        winnerIdentity: ScoreboardWinnerIdentity? = nil,
        detailedActions: [DetailedScoreAction] = [],
        totalScoreChanges: Int = 0,
        participants: [RecordParticipantScore]? = nil,
        projectConfiguration: [String: String] = [:],
        basketballTraining: ScoreCore.ShotTrainingState? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.kind = kind
        self.source = source
        self.startEpochMilliseconds = startEpochMilliseconds
        self.endEpochMilliseconds = endEpochMilliseconds
        self.durationSeconds = durationSeconds
        self.team1Name = team1Name
        self.team2Name = team2Name
        self.team1FinalScore = team1FinalScore
        self.team2FinalScore = team2FinalScore
        self.team1SetScore = team1SetScore
        self.team2SetScore = team2SetScore
        self.winnerIdentity = winnerIdentity
        self.detailedActions = detailedActions
        self.totalScoreChanges = totalScoreChanges
        self.participants = participants
        self.projectConfiguration = projectConfiguration
        self.basketballTraining = basketballTraining
    }
}
