import Foundation
import ScoreCore

/// Minimal finished two-side record shared by phone and watch persistence paths.
public struct SharedTwoSideMatchRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let gameType: GameType
    public let source: RecordSource
    public let startEpochMilliseconds: Int64
    public let endEpochMilliseconds: Int64
    public let durationSeconds: TimeInterval
    public let team1Name: String
    public let team2Name: String
    public let team1FinalScore: Int
    public let team2FinalScore: Int
    public let team1SetScore: Int?
    public let team2SetScore: Int?
    /// Canonical winner: `team_0` / `team_1` / nil for draw or unfinished.
    public let winnerTeamID: String?

    public init(
        id: String,
        gameType: GameType,
        source: RecordSource,
        startEpochMilliseconds: Int64,
        endEpochMilliseconds: Int64,
        durationSeconds: TimeInterval,
        team1Name: String,
        team2Name: String,
        team1FinalScore: Int,
        team2FinalScore: Int,
        team1SetScore: Int? = nil,
        team2SetScore: Int? = nil,
        winnerTeamID: String? = nil
    ) {
        self.id = id
        self.gameType = gameType
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
        self.winnerTeamID = winnerTeamID
    }
}
