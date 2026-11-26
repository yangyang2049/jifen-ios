import Foundation
import ScoreCore
import SessionCore

public enum RecordSource: String, Codable, Sendable {
    case phoneLocal
    case watchLocal
    case linkedWatch
    case linkedPhone
}

public enum ScoreActionKind: String, Codable, Sendable {
    case matchStarted
    case scoreChanged
    case stateChanged
    case undo
    case matchFinished
}

public struct ScoreAction: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: ScoreActionKind
    public let epochMilliseconds: Int64
    public let summary: String

    public init(id: UUID = UUID(), kind: ScoreActionKind, epochMilliseconds: Int64, summary: String) {
        self.id = id
        self.kind = kind
        self.epochMilliseconds = epochMilliseconds
        self.summary = summary
    }
}

/// Cross-project action vocabulary used by record schema v4.  The legacy
/// `ScoreAction` remains intentionally small for transport compatibility;
/// this model carries the information needed to rebuild a trustworthy recap.
public enum DetailedScoreActionType: String, Codable, Sendable {
    case matchStarted
    case scoreChanged
    case setFinished
    case roundFinished
    case periodFinished
    case matchFinished
    case undo
    case reset
    case sideChanged
    case serveChanged
    case foul
    case timeout
    case stateChanged
}

public enum RecordTeam: String, Codable, CaseIterable, Sendable {
    case team1
    case team2
    case team3
    case team4
}

public struct ParticipantScoreSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let score: Int
    public let rank: Int?
    public let role: String?

    public init(id: String, name: String, score: Int, rank: Int? = nil, role: String? = nil) {
        self.id = id
        self.name = name
        self.score = score
        self.rank = rank
        self.role = role
    }
}

public struct DetailedScoreAction: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let type: DetailedScoreActionType
    /// Nil for imported actions whose original record did not contain time.
    public let epochMilliseconds: Int64?
    public let team: RecordTeam?
    /// Up to four side scores after the accepted operation.
    public let scores: [Int]
    /// Up to four set/game scores after the accepted operation.
    public let setScores: [Int]
    public let setNumber: Int?
    public let gameNumber: Int?
    public let roundNumber: Int?
    public let periodNumber: Int?
    /// Seconds elapsed on the in-period game clock at the time of the action
    /// (basketball-style sports only). Optional keeps older records
    /// source-compatible.
    public let gameTimeSeconds: Int?
    public let scoreChange: Int?
    public let winner: RecordTeam?
    public let loser: RecordTeam?
    public let landlord: RecordTeam?
    /// Multi-party round outcome metadata. Optional keeps older v4/v5 records
    /// source-compatible while preserving Android's typed Doudizhu projection.
    public let winners: [RecordTeam]?
    public let losers: [RecordTeam]?
    public let farmers: [RecordTeam]?
    public let participants: [ParticipantScoreSnapshot]
    /// Stable project-specific operation code such as `snooker_foul_4`.
    public let operationCode: String?
    /// Typed project-specific value associated with `operationCode`, such as
    /// the configured Guandan rank restored after a triple-A fallback.
    public let operationPayload: String?
    public let summary: String?
    /// Cross-end match-clock position of a football goal: period 1/2 for the
    /// regulation halves, 3/4 for extra time. Mirrors Android's
    /// `ScoreAction.footballPeriod`, so imported records survive re-encoding.
    public let footballPeriod: Int?
    /// Seconds elapsed on the football match clock inside `footballPeriod`.
    /// Mirrors Android's `ScoreAction.footballElapsedSeconds`.
    public let footballElapsedSeconds: Int?

    public init(
        id: UUID = UUID(),
        type: DetailedScoreActionType,
        epochMilliseconds: Int64? = nil,
        team: RecordTeam? = nil,
        scores: [Int] = [],
        setScores: [Int] = [],
        setNumber: Int? = nil,
        gameNumber: Int? = nil,
        roundNumber: Int? = nil,
        periodNumber: Int? = nil,
        gameTimeSeconds: Int? = nil,
        scoreChange: Int? = nil,
        winner: RecordTeam? = nil,
        loser: RecordTeam? = nil,
        landlord: RecordTeam? = nil,
        winners: [RecordTeam]? = nil,
        losers: [RecordTeam]? = nil,
        farmers: [RecordTeam]? = nil,
        participants: [ParticipantScoreSnapshot] = [],
        operationCode: String? = nil,
        operationPayload: String? = nil,
        summary: String? = nil,
        footballPeriod: Int? = nil,
        footballElapsedSeconds: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.epochMilliseconds = epochMilliseconds
        self.team = team
        self.scores = Array(scores.prefix(4))
        self.setScores = Array(setScores.prefix(4))
        self.setNumber = setNumber
        self.gameNumber = gameNumber
        self.roundNumber = roundNumber
        self.periodNumber = periodNumber
        self.gameTimeSeconds = gameTimeSeconds
        self.scoreChange = scoreChange
        self.winner = winner
        self.loser = loser
        self.landlord = landlord
        self.winners = winners
        self.losers = losers
        self.farmers = farmers
        self.participants = participants
        self.operationCode = operationCode
        self.operationPayload = operationPayload
        self.summary = summary
        self.footballPeriod = footballPeriod
        self.footballElapsedSeconds = footballElapsedSeconds
    }
}

public struct RecordSetResult: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let number: Int
    public let titleCode: String?
    public let scores: [Int]
    public let winner: RecordTeam?
    public let startedAtEpochMilliseconds: Int64?
    public let finishedAtEpochMilliseconds: Int64?

    public init(
        id: UUID = UUID(),
        number: Int,
        titleCode: String? = nil,
        scores: [Int],
        winner: RecordTeam? = nil,
        startedAtEpochMilliseconds: Int64? = nil,
        finishedAtEpochMilliseconds: Int64? = nil
    ) {
        self.id = id
        self.number = number
        self.titleCode = titleCode
        self.scores = Array(scores.prefix(4))
        self.winner = winner
        self.startedAtEpochMilliseconds = startedAtEpochMilliseconds
        self.finishedAtEpochMilliseconds = finishedAtEpochMilliseconds
    }
}

public struct TwoSideRecordPayload: Codable, Equatable, Sendable {
    public let leftName: String
    public let rightName: String
    public let leftScore: Int
    public let rightScore: Int
    public let leftSets: Int?
    public let rightSets: Int?

    public init(leftName: String, rightName: String, leftScore: Int, rightScore: Int, leftSets: Int? = nil, rightSets: Int? = nil) {
        self.leftName = leftName
        self.rightName = rightName
        self.leftScore = leftScore
        self.rightScore = rightScore
        self.leftSets = leftSets
        self.rightSets = rightSets
    }
}

public enum RecordPayload: Codable, Equatable, Sendable {
    case twoSide(TwoSideRecordPayload)
    case multiParticipant(participants: [SessionParticipant])
    case cardGame(teamNames: [String], summary: String)
}

public struct RecordSyncMetadata: Codable, Equatable, Sendable {
    public let actorID: UUID
    public let revision: UInt64
    public let updatedAtEpochMilliseconds: Int64
    public let serverCursor: String?

    public init(actorID: UUID, revision: UInt64, updatedAtEpochMilliseconds: Int64, serverCursor: String? = nil) {
        self.actorID = actorID
        self.revision = revision
        self.updatedAtEpochMilliseconds = updatedAtEpochMilliseconds
        self.serverCursor = serverCursor
    }
}

/// 双端统一的胜者身份（M2 从手机 ScoreboardRecord.swift 上移）。
/// JSON 编码键名与格式与手机 schema v5 完全一致（kind/teamID/participantIndex）。
public enum ScoreboardWinnerIdentity: Codable, Equatable, Sendable {
    case team(TeamID)
    case participant(index: Int)

    private enum Kind: String, Codable {
        case team
        case participant
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case teamID
        case participantIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .team:
            self = .team(try container.decode(TeamID.self, forKey: .teamID))
        case .participant:
            let index = try container.decode(Int.self, forKey: .participantIndex)
            guard index >= 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .participantIndex,
                    in: container,
                    debugDescription: "Winner participant index must be non-negative"
                )
            }
            self = .participant(index: index)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .team(let teamID):
            try container.encode(Kind.team, forKey: .kind)
            try container.encode(teamID, forKey: .teamID)
        case .participant(let index):
            try container.encode(Kind.participant, forKey: .kind)
            try container.encode(index, forKey: .participantIndex)
        }
    }

    public var teamID: TeamID? {
        guard case .team(let teamID) = self else { return nil }
        return teamID
    }

    /// Canonical compatibility token written beside the typed schema-v5 value.
    /// Older clients can keep reading the winner token without depending on a
    /// localized participant name or the current screen placement.
    public var legacyToken: String {
        switch self {
        case .team(let teamID): return teamID.rawValue
        case .participant(let index): return "player_\(index)"
        }
    }

    public static func fromStableLegacyToken(_ token: String?) -> ScoreboardWinnerIdentity? {
        guard let raw = token?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else {
            return nil
        }
        if let teamID = TeamID.fromLegacyWinnerToken(raw) {
            return .team(teamID)
        }
        guard raw.hasPrefix("player_"),
              let index = Int(raw.dropFirst("player_".count)),
              index >= 0 else {
            return nil
        }
        return .participant(index: index)
    }

    public var recordTeam: RecordTeam? {
        switch self {
        case .team(.team0), .participant(index: 0): return .team1
        case .team(.team1), .participant(index: 1): return .team2
        case .participant(index: 2): return .team3
        case .participant(index: 3): return .team4
        case .participant: return nil
        }
    }
}

/// 投篮训练动作投影（RecordCore 侧）：DetailedScoreAction 在 RecordCore 定义，
/// ScoreCore 状态无法反向引用，这里以 extension 承载既有行为。
public extension ScoreCore.ShotTrainingState {
    func detailedActions(endingAt endTime: Date) -> [DetailedScoreAction] {
        var running = earlierCounts
        var actions = shots.map { shot in
            running.add(shot)
            return DetailedScoreAction(
                type: .scoreChanged,
                epochMilliseconds: Int64((shot.timestamp.timeIntervalSince1970 * 1_000).rounded()),
                team: shot.made ? .team2 : .team1,
                scores: [running.missed, running.made],
                scoreChange: 1,
                operationCode: "training_\(shot.points)pt_\(shot.made ? "made" : "miss")"
            )
        }
        actions.append(DetailedScoreAction(
            type: .matchFinished,
            epochMilliseconds: Int64((endTime.timeIntervalSince1970 * 1_000).rounded()),
            scores: [running.missed, running.made],
            operationCode: "training_rate_\(running.rate)"
        ))
        return actions
    }
}
