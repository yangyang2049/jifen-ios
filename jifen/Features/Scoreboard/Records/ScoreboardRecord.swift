//
//  ScoreboardRecord.swift
//  jifen
//
//  Scoreboard record data models
//

import Foundation

// MARK: - Scoreboard Record

struct ScoreboardRecord: Codable, Identifiable {
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
    
    enum CodingKeys: String, CodingKey {
        case id
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


