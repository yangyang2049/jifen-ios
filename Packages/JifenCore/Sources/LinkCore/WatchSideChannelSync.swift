import Foundation

/// Phone→watch common-names snapshot pushed via `WCSession.updateApplicationContext`.
public struct CommonNamesSyncSnapshot: Codable, Equatable, Sendable {
    public var teams: [String]
    public var players: [String]
    public var updatedAtEpochMilliseconds: Int64

    public init(
        teams: [String],
        players: [String],
        updatedAtEpochMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.teams = teams
        self.players = players
        self.updatedAtEpochMilliseconds = updatedAtEpochMilliseconds
    }

    public func applicationContextValue() -> [String: Any] {
        [
            "teams": teams,
            "players": players,
            "updatedAt": updatedAtEpochMilliseconds
        ]
    }

    public static func fromApplicationContextValue(_ value: Any?) -> CommonNamesSyncSnapshot? {
        guard let dict = value as? [String: Any] else { return nil }
        let teams = dict["teams"] as? [String] ?? []
        let players = dict["players"] as? [String] ?? []
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
        return CommonNamesSyncSnapshot(
            teams: teams,
            players: players,
            updatedAtEpochMilliseconds: updatedAt
        )
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
        self.totalScoreChanges = totalScoreChanges
        self.participants = participants
        self.projectConfiguration = projectConfiguration
    }
}
