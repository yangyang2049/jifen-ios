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
