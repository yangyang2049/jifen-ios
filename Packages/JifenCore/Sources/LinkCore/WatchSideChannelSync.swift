import Foundation
import RecordCore

/// Phone→watch common-names snapshot pushed via `WCSession.updateApplicationContext`.
public struct CommonNamesSyncSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var teams: [String]
    public var players: [String]
    public var updatedAtEpochMilliseconds: Int64
    public var revision: UInt64

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case teams
        case players
        case updatedAtEpochMilliseconds
        case revision
    }

    public init(
        teams: [String],
        players: [String],
        updatedAtEpochMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        schemaVersion: Int = Self.currentSchemaVersion,
        revision: UInt64 = 0
    ) {
        self.schemaVersion = schemaVersion
        self.teams = teams
        self.players = players
        self.updatedAtEpochMilliseconds = updatedAtEpochMilliseconds
        self.revision = revision
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard (1...Self.currentSchemaVersion).contains(schemaVersion) else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported common-name snapshot schema"
            )
        }
        teams = try container.decode([String].self, forKey: .teams)
        players = try container.decode([String].self, forKey: .players)
        updatedAtEpochMilliseconds = try container.decode(Int64.self, forKey: .updatedAtEpochMilliseconds)
        revision = try container.decodeIfPresent(UInt64.self, forKey: .revision) ?? 0
    }

    public func applicationContextValue() -> [String: Any] {
        [
            "schemaVersion": schemaVersion,
            "teams": teams,
            "players": players,
            "updatedAt": updatedAtEpochMilliseconds,
            "revision": NSNumber(value: revision)
        ]
    }

    public static func fromApplicationContextValue(_ value: Any?) -> CommonNamesSyncSnapshot? {
        guard let dict = value as? [String: Any] else { return nil }
        guard let teams = dict["teams"] as? [String],
              let players = dict["players"] as? [String] else { return nil }
        let schemaVersion = (dict["schemaVersion"] as? NSNumber)?.intValue
            ?? (dict["schemaVersion"] as? Int)
            ?? 1
        guard (1...Self.currentSchemaVersion).contains(schemaVersion) else { return nil }
        let updatedAt: Int64
        if let number = dict["updatedAt"] as? NSNumber {
            updatedAt = number.int64Value
        } else if let intValue = dict["updatedAt"] as? Int64 {
            updatedAt = intValue
        } else if let intValue = dict["updatedAt"] as? Int {
            updatedAt = Int64(intValue)
        } else {
            updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        }
        let revision: UInt64
        if let number = dict["revision"] as? NSNumber {
            guard number.int64Value >= 0 else { return nil }
            revision = UInt64(number.int64Value)
        } else if let value = dict["revision"] as? UInt64 {
            revision = value
        } else if let value = dict["revision"] as? Int, value >= 0 {
            revision = UInt64(value)
        } else {
            revision = 0
        }
        return CommonNamesSyncSnapshot(
            teams: teams,
            players: players,
            updatedAtEpochMilliseconds: updatedAt,
            schemaVersion: schemaVersion,
            revision: revision
        )
    }
}

public enum CommonNameSyncType: String, Codable, Equatable, Sendable {
    case team
    case player
}

public enum CommonNameMutationKind: String, Codable, Equatable, Sendable {
    case add
    case rename
    case delete
}

public struct CommonNameMutation: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: CommonNameMutationKind
    public var nameType: CommonNameSyncType
    public var originalName: String?
    public var newName: String?
    public var createdAtEpochMilliseconds: Int64

    public init(
        id: UUID = UUID(),
        kind: CommonNameMutationKind,
        nameType: CommonNameSyncType,
        originalName: String? = nil,
        newName: String? = nil,
        createdAtEpochMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.kind = kind
        self.nameType = nameType
        self.originalName = originalName
        self.newName = newName
        self.createdAtEpochMilliseconds = createdAtEpochMilliseconds
    }
}

public struct CommonNameMutationBatch: Codable, Equatable, Sendable {
    public var mutations: [CommonNameMutation]

    public init(mutations: [CommonNameMutation]) {
        self.mutations = mutations
    }
}

public enum CommonNameMutationResultStatus: String, Codable, Equatable, Sendable {
    case applied
    case noChange
    case conflict
    case invalid
}

public struct CommonNameMutationResult: Codable, Equatable, Sendable {
    public var mutationId: UUID
    public var status: CommonNameMutationResultStatus

    public init(mutationId: UUID, status: CommonNameMutationResultStatus) {
        self.mutationId = mutationId
        self.status = status
    }
}

public struct CommonNameMutationAcknowledgement: Codable, Equatable, Sendable {
    public var snapshot: CommonNamesSyncSnapshot
    public var results: [CommonNameMutationResult]

    public init(snapshot: CommonNamesSyncSnapshot, results: [CommonNameMutationResult]) {
        self.snapshot = snapshot
        self.results = results
    }
}

public struct CommonNamesSyncRequestPayload: Codable, Equatable, Sendable {
    public var requestId: UUID

    public init(requestId: UUID = UUID()) {
        self.requestId = requestId
    }
}

public struct ConnectivityProbePayload: Codable, Equatable, Sendable {
    public var probeId: UUID

    public init(probeId: UUID = UUID()) {
        self.probeId = probeId
    }
}

/// Watch→phone usage events are queued so picking/typing a player name works offline.
public struct CommonNameUsagePayload: Codable, Equatable, Sendable {
    public var names: [String]
    public var nameType: String

    public init(names: [String], nameType: String = "player") {
        self.names = names
        self.nameType = nameType
    }
}

public struct WatchRecordParticipantPayload: Codable, Equatable, Sendable {
    public var name: String
    public var score: Int

    public init(name: String, score: Int) {
        self.name = name
        self.score = score
    }
}

/// Watch→phone finished-record payload queued via `transferUserInfo`.
public struct WatchRecordTransferPayload: Codable, Equatable, Sendable {
    public var id: String
    public var gameType: String
    public var startTimeEpochMilliseconds: Int64
    public var endTimeEpochMilliseconds: Int64
    public var durationSeconds: Double
    public var team1Name: String
    public var team2Name: String
    public var team1FinalScore: Int
    public var team2FinalScore: Int
    public var team1SetScore: Int
    public var team2SetScore: Int
    public var winner: String?
    public var actions: [String]
    /// Schema-v4 compatible actions; nil for older watch payloads.
    public var detailedActions: [DetailedScoreAction]?
    public var totalScoreChanges: Int
    public var participants: [WatchRecordParticipantPayload]?
    public var projectConfiguration: [String: String]?

    public init(
        id: String,
        gameType: String,
        startTimeEpochMilliseconds: Int64,
        endTimeEpochMilliseconds: Int64,
        durationSeconds: Double,
        team1Name: String,
        team2Name: String,
        team1FinalScore: Int,
        team2FinalScore: Int,
        team1SetScore: Int,
        team2SetScore: Int,
        winner: String?,
        actions: [String],
        detailedActions: [DetailedScoreAction]? = nil,
        totalScoreChanges: Int,
        participants: [WatchRecordParticipantPayload]? = nil,
        projectConfiguration: [String: String]? = nil
    ) {
        self.id = id
        self.gameType = gameType
        self.startTimeEpochMilliseconds = startTimeEpochMilliseconds
        self.endTimeEpochMilliseconds = endTimeEpochMilliseconds
        self.durationSeconds = durationSeconds
        self.team1Name = team1Name
        self.team2Name = team2Name
        self.team1FinalScore = team1FinalScore
        self.team2FinalScore = team2FinalScore
        self.team1SetScore = team1SetScore
        self.team2SetScore = team2SetScore
        self.winner = winner
        self.actions = actions
        self.detailedActions = detailedActions
        self.totalScoreChanges = totalScoreChanges
        self.participants = participants
        self.projectConfiguration = projectConfiguration
    }
}
