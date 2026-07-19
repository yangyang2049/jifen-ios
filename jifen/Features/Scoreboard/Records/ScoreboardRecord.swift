//
//  ScoreboardRecord.swift
//  jifen
//
//  Scoreboard record data models
//

import Foundation

enum ScoreboardRecordStatus: String, Codable {
    case draft
    case finished
}

// MARK: - Scoreboard Record

struct ScoreboardRecord: Codable, Identifiable {
    var schemaVersion: Int = 3
    let id: String
    let gameType: GameType
    let startTime: Date
    var endTime: Date?
    var duration: TimeInterval?
    let team1Name: String
    let team2Name: String
    var team1FinalScore: Int
    var team2FinalScore: Int
    var team1SetScore: Int?
    var team2SetScore: Int?
    var winner: String? // "left", "right", or nil
    var actions: [String] // Simplified action strings
    var totalScoreChanges: Int
    var extraData: [String: AnyCodable]?
    var projectConfiguration: [String: AnyCodable]?
    var stateSnapshot: Data?
    var syncMetadata: [String: String]?
    var status: ScoreboardRecordStatus = .finished
    
    enum CodingKeys: String, CodingKey {
        case id
        case schemaVersion
        case gameType
        case startTime
        case endTime
        case duration
        case team1Name
        case team2Name
        case team1FinalScore
        case team2FinalScore
        case team1SetScore
        case team2SetScore
        case winner
        case actions
        case totalScoreChanges
        case extraData
        case projectConfiguration
        case stateSnapshot
        case syncMetadata
        case status
    }

    init(
        id: String,
        gameType: GameType,
        startTime: Date,
        endTime: Date? = nil,
        duration: TimeInterval? = nil,
        team1Name: String,
        team2Name: String,
        team1FinalScore: Int,
        team2FinalScore: Int,
        team1SetScore: Int? = nil,
        team2SetScore: Int? = nil,
        winner: String? = nil,
        actions: [String] = [],
        totalScoreChanges: Int,
        extraData: [String: AnyCodable]? = nil,
        projectConfiguration: [String: AnyCodable]? = nil,
        stateSnapshot: Data? = nil,
        syncMetadata: [String: String]? = nil,
        status: ScoreboardRecordStatus = .finished
    ) {
        self.schemaVersion = 3
        self.id = id
        self.gameType = gameType
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.team1Name = team1Name
        self.team2Name = team2Name
        self.team1FinalScore = team1FinalScore
        self.team2FinalScore = team2FinalScore
        self.team1SetScore = team1SetScore
        self.team2SetScore = team2SetScore
        self.winner = winner
        self.actions = actions
        self.totalScoreChanges = totalScoreChanges
        self.extraData = extraData
        self.projectConfiguration = projectConfiguration
        self.stateSnapshot = stateSnapshot
        self.syncMetadata = syncMetadata
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        id = try container.decode(String.self, forKey: .id)
        gameType = try container.decode(GameType.self, forKey: .gameType)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        team1Name = try container.decode(String.self, forKey: .team1Name)
        team2Name = try container.decode(String.self, forKey: .team2Name)
        team1FinalScore = try container.decode(Int.self, forKey: .team1FinalScore)
        team2FinalScore = try container.decode(Int.self, forKey: .team2FinalScore)
        team1SetScore = try container.decodeIfPresent(Int.self, forKey: .team1SetScore)
        team2SetScore = try container.decodeIfPresent(Int.self, forKey: .team2SetScore)
        winner = try container.decodeIfPresent(String.self, forKey: .winner)
        actions = try container.decodeIfPresent([String].self, forKey: .actions) ?? []
        totalScoreChanges = try container.decode(Int.self, forKey: .totalScoreChanges)
        extraData = try container.decodeIfPresent([String: AnyCodable].self, forKey: .extraData)
        projectConfiguration = try container.decodeIfPresent([String: AnyCodable].self, forKey: .projectConfiguration)
        stateSnapshot = try container.decodeIfPresent(Data.self, forKey: .stateSnapshot)
        syncMetadata = try container.decodeIfPresent([String: String].self, forKey: .syncMetadata)
        status = try container.decodeIfPresent(ScoreboardRecordStatus.self, forKey: .status) ?? .finished
    }
}

// MARK: - Scoreboard Record Summary

struct ScoreboardRecordSummary: Codable, Identifiable, Equatable {
    let id: String
    let gameType: GameType
    let date: String // YYYY-MM-DD
    let time: String // HH:mm
    let timestamp: TimeInterval
    var duration: TimeInterval?
    let team1Name: String
    let team2Name: String
    let team1FinalScore: Int
    let team2FinalScore: Int
    var team1SetScore: Int?
    var team2SetScore: Int?
    var winner: String?
    var extraData: [String: AnyCodable]?
    
    // Convert from full record
    init(from record: ScoreboardRecord) {
        self.id = record.id
        self.gameType = record.gameType
        self.timestamp = record.startTime.timeIntervalSince1970
        
        // Format date（同年不显示年份，与 Watch、鸿蒙一致）
        let dateFormatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDate(record.startTime, equalTo: Date(), toGranularity: .year) {
            dateFormatter.dateFormat = "MM-dd"
        } else {
            dateFormatter.dateFormat = "yyyy-MM-dd"
        }
        self.date = dateFormatter.string(from: record.startTime)
        
        // Format time
        dateFormatter.dateFormat = "HH:mm"
        self.time = dateFormatter.string(from: record.startTime)
        
        self.duration = record.duration
        self.team1Name = record.team1Name
        self.team2Name = record.team2Name
        self.team1FinalScore = record.team1FinalScore
        self.team2FinalScore = record.team2FinalScore
        self.team1SetScore = record.team1SetScore
        self.team2SetScore = record.team2SetScore
        self.winner = record.winner
        self.extraData = record.extraData
    }
    
    // Equatable conformance
    static func == (lhs: ScoreboardRecordSummary, rhs: ScoreboardRecordSummary) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Scoreboard Record Group

struct ScoreboardRecordGroup: Identifiable {
    let id: String
    let date: String
    let displayDate: String
    var records: [ScoreboardRecordSummary]
}

// MARK: - Multi-participant record display

struct ScoreboardRecordParticipant: Equatable {
    let name: String
    let score: Int
}

extension ScoreboardRecord {
    var displayParticipants: [ScoreboardRecordParticipant] {
        scoreboardRecordParticipants(gameType: gameType, from: extraData)
    }

    var displayMatchTitle: String {
        let names = displayParticipants.map(\.name)
        return names.isEmpty ? "\(team1Name) vs \(team2Name)" : names.joined(separator: " vs ")
    }

    func displayScore(separator: String = " : ") -> String {
        let scores = displayParticipants.map { String($0.score) }
        return scores.isEmpty ? "\(team1FinalScore)\(separator)\(team2FinalScore)" : scores.joined(separator: separator)
    }
}

extension ScoreboardRecordSummary {
    var displayParticipants: [ScoreboardRecordParticipant] {
        scoreboardRecordParticipants(gameType: gameType, from: extraData)
    }

    var displayMatchTitle: String {
        let names = displayParticipants.map(\.name)
        return names.isEmpty ? "\(team1Name) vs \(team2Name)" : names.joined(separator: " vs ")
    }

    func displayScore(separator: String = " : ") -> String {
        let scores = displayParticipants.map { String($0.score) }
        return scores.isEmpty ? "\(team1FinalScore)\(separator)\(team2FinalScore)" : scores.joined(separator: separator)
    }
}

private func scoreboardRecordParticipants(gameType: GameType, from extraData: [String: AnyCodable]?) -> [ScoreboardRecordParticipant] {
    guard gameType == .multiScoreboard || gameType == .uno || gameType == .doudizhu || gameType == .nineBall else {
        return []
    }
    guard let rawPlayers = extraData?["players"]?.value else { return [] }
    let values: [Any]
    if let array = rawPlayers as? [Any] {
        values = array
    } else if let array = rawPlayers as? [AnyCodable] {
        values = array.map(\.value)
    } else {
        return []
    }

    return values.compactMap { raw in
        let value = (raw as? AnyCodable)?.value ?? raw
        let dictionary: [String: Any]
        if let decoded = value as? [String: Any] {
            dictionary = decoded
        } else if let wrapped = value as? [String: AnyCodable] {
            dictionary = wrapped.mapValues(\.value)
        } else {
            return nil
        }
        guard let name = dictionary["name"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let rawScore = dictionary["finalScore"] ?? dictionary["score"] ?? 0
        let score: Int
        if let int = rawScore as? Int { score = int }
        else if let double = rawScore as? Double { score = Int(double) }
        else if let string = rawScore as? String { score = Int(string) ?? 0 }
        else if let wrapped = rawScore as? AnyCodable, let int = wrapped.value as? Int { score = int }
        else { score = 0 }
        return ScoreboardRecordParticipant(name: name, score: score)
    }
}

// MARK: - AnyCodable Helper

struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable value cannot be encoded"))
        }
    }
}
