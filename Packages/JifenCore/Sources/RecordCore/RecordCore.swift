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
    public let scoreChange: Int?
    public let winner: RecordTeam?
    public let loser: RecordTeam?
    public let landlord: RecordTeam?
    public let participants: [ParticipantScoreSnapshot]
    /// Stable project-specific operation code such as `snooker_foul_4`.
    public let operationCode: String?
    public let summary: String?

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
        scoreChange: Int? = nil,
        winner: RecordTeam? = nil,
        loser: RecordTeam? = nil,
        landlord: RecordTeam? = nil,
        participants: [ParticipantScoreSnapshot] = [],
        operationCode: String? = nil,
        summary: String? = nil
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
        self.scoreChange = scoreChange
        self.winner = winner
        self.loser = loser
        self.landlord = landlord
        self.participants = participants
        self.operationCode = operationCode
        self.summary = summary
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

public struct ScoreRecordV2: Codable, Equatable, Identifiable, Sendable {
    public let schemaVersion: Int?
    public let id: UUID
    public let sessionId: UUID
    public let gameType: GameType
    public let source: RecordSource
    public let startedAtEpochMilliseconds: Int64
    public let finishedAtEpochMilliseconds: Int64?
    public let payload: RecordPayload
    public let actions: [ScoreAction]
    /// JSON-encoded project setup. Kept opaque so new project rules do not require a record migration.
    public let configuration: Data?
    /// Full versioned reducer/session snapshot used for exact resume and replay.
    public let stateSnapshot: Data?
    public let syncMetadata: RecordSyncMetadata?
    /// A non-nil value is a deletion tombstone and must win over an older upsert.
    public let deletedAtEpochMilliseconds: Int64?

    public init(
        id: UUID = UUID(),
        sessionId: UUID,
        gameType: GameType,
        source: RecordSource,
        startedAtEpochMilliseconds: Int64,
        finishedAtEpochMilliseconds: Int? = nil,
        payload: RecordPayload,
        actions: [ScoreAction],
        schemaVersion: Int? = 3,
        configuration: Data? = nil,
        stateSnapshot: Data? = nil,
        syncMetadata: RecordSyncMetadata? = nil,
        deletedAtEpochMilliseconds: Int64? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.sessionId = sessionId
        self.gameType = gameType
        self.source = source
        self.startedAtEpochMilliseconds = startedAtEpochMilliseconds
        self.finishedAtEpochMilliseconds = finishedAtEpochMilliseconds.map(Int64.init)
        self.payload = payload
        self.actions = actions
        self.configuration = configuration
        self.stateSnapshot = stateSnapshot
        self.syncMetadata = syncMetadata
        self.deletedAtEpochMilliseconds = deletedAtEpochMilliseconds
    }
}
