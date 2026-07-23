import Foundation
import RecordCore
import ScoreCore
import SwiftUI // Required for Color, though not directly used in this file for styling. Keep for consistency if needed elsewhere.

struct WatchRecordParticipant: Codable, Hashable {
    let name: String
    let score: Int
}

struct WatchBasketballTrainingShot: Codable, Hashable, Identifiable {
    let id: String
    let points: Int
    let made: Bool
    let timestamp: Date

    init(
        id: String = UUID().uuidString,
        points: Int,
        made: Bool,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.points = points
        self.made = made
        self.timestamp = timestamp
    }
}

struct WatchBasketballTrainingDetails: Codable, Hashable {
    let mode: WatchBasketballTrainingMode
    let shots: [WatchBasketballTrainingShot]
    /// Explicit Android-compatible six-category totals. Optional keeps records
    /// produced by the first Apple Watch implementation decodable.
    let onePointMade: Int?
    let onePointMiss: Int?
    let twoPointMade: Int?
    let twoPointMiss: Int?
    let threePointMade: Int?
    let threePointMiss: Int?

    init(mode: WatchBasketballTrainingMode, shots: [WatchBasketballTrainingShot]) {
        self.mode = mode
        self.shots = shots
        onePointMade = Self.count(shots, points: 1, made: true)
        onePointMiss = Self.count(shots, points: 1, made: false)
        twoPointMade = Self.count(shots, points: 2, made: true)
        twoPointMiss = Self.count(shots, points: 2, made: false)
        threePointMade = Self.count(shots, points: 3, made: true)
        threePointMiss = Self.count(shots, points: 3, made: false)
    }

    func count(points: Int, made: Bool) -> Int {
        switch (points, made) {
        case (1, true): return onePointMade ?? Self.count(shots, points: 1, made: true)
        case (1, false): return onePointMiss ?? Self.count(shots, points: 1, made: false)
        case (2, true): return twoPointMade ?? Self.count(shots, points: 2, made: true)
        case (2, false): return twoPointMiss ?? Self.count(shots, points: 2, made: false)
        case (3, true): return threePointMade ?? Self.count(shots, points: 3, made: true)
        default: return threePointMiss ?? Self.count(shots, points: 3, made: false)
        }
    }

    private static func count(
        _ shots: [WatchBasketballTrainingShot],
        points: Int,
        made: Bool
    ) -> Int {
        shots.lazy.filter { $0.points == points && $0.made == made }.count
    }
}

struct WatchScoreboardRecord: Codable, Identifiable {
    let id: String
    let gameType: WatchGameType
    let startTime: Date
    var endTime: Date
    var duration: TimeInterval
    let team1Name: String
    let team2Name: String
    var team1FinalScore: Int
    var team2FinalScore: Int
    var team1SetScore: Int
    var team2SetScore: Int
    var winner: String?
    var actions: [WatchScoreAction]
    var totalScoreChanges: Int
    /// Optional so records created by older watch versions remain decodable.
    var participants: [WatchRecordParticipant]? = nil
    var projectConfiguration: [String: String]? = nil
    var basketballTrainingDetails: WatchBasketballTrainingDetails? = nil

    /// Canonical shared DTO for phone ingest / future RecordCore alignment.
    func toSharedRecord() -> SharedTwoSideMatchRecord? {
        guard let coreType = gameType.scoreCoreGameType else { return nil }
        let winnerTeamID: String?
        if winner == team1Name || winner == "red" || winner == "left" {
            winnerTeamID = "team_0"
        } else if winner == team2Name || winner == "blue" || winner == "right" {
            winnerTeamID = "team_1"
        } else {
            winnerTeamID = nil
        }
        return SharedTwoSideMatchRecord(
            id: id,
            gameType: coreType,
            source: .watchLocal,
            startEpochMilliseconds: Int64(startTime.timeIntervalSince1970 * 1000),
            endEpochMilliseconds: Int64(endTime.timeIntervalSince1970 * 1000),
            durationSeconds: duration,
            team1Name: team1Name,
            team2Name: team2Name,
            team1FinalScore: team1FinalScore,
            team2FinalScore: team2FinalScore,
            team1SetScore: team1SetScore,
            team2SetScore: team2SetScore,
            winnerTeamID: winnerTeamID
        )
    }
}

struct WatchScoreboardRecordSummary: Identifiable, Codable, Equatable {
    let id: String
    let gameType: WatchGameType
    let timestamp: TimeInterval
    let dateText: String
    let timeText: String
    var duration: TimeInterval
    let team1Name: String
    let team2Name: String
    let team1FinalScore: Int
    let team2FinalScore: Int
    var team1SetScore: Int
    var team2SetScore: Int
    var winner: String?
    var participants: [WatchRecordParticipant]?

    init(from record: WatchScoreboardRecord) {
        self.id = record.id
        self.gameType = record.gameType
        self.timestamp = record.startTime.timeIntervalSince1970
        self.duration = record.duration
        self.team1Name = record.team1Name
        self.team2Name = record.team2Name
        self.team1FinalScore = record.team1FinalScore
        self.team2FinalScore = record.team2FinalScore
        self.team1SetScore = record.team1SetScore
        self.team2SetScore = record.team2SetScore
        self.winner = record.winner
        self.participants = record.participants

        let dateFormatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDate(record.startTime, equalTo: Date(), toGranularity: .year) {
            // Same year, format without year
            dateFormatter.dateFormat = "MM-dd"
        } else {
            // Different year, format with year
            dateFormatter.dateFormat = "yyyy-MM-dd"
        }
        self.dateText = dateFormatter.string(from: record.startTime)
        dateFormatter.dateFormat = "HH:mm"
        self.timeText = dateFormatter.string(from: record.startTime)
    }

    static func == (lhs: WatchScoreboardRecordSummary, rhs: WatchScoreboardRecordSummary) -> Bool {
        lhs.id == rhs.id
    }
}

func watchFormatDuration(_ duration: TimeInterval) -> String {

    let totalSeconds = Int(duration)

    let hours = totalSeconds / 3600

    let minutes = (totalSeconds % 3600) / 60

    let seconds = totalSeconds % 60

    

    let hourUnit = NSLocalizedString("unit_hour", value: "时", comment: "Hour unit")

    let minUnit = NSLocalizedString("unit_minute", value: "分", comment: "Minute unit")

    let secUnit = NSLocalizedString("unit_second", value: "秒", comment: "Second unit")

    

    if hours > 0 {

        return String(format: "%d%@%d%@%d%@", hours, hourUnit, minutes, minUnit, seconds, secUnit)

    }

    if minutes > 0 {

        return String(format: "%d%@%d%@", minutes, minUnit, seconds, secUnit)

    }

    return String(format: "%d%@", seconds, secUnit)

}



func watchFormatDisplayDate(_ dateStr: String) -> String {

    let formatter = DateFormatter()

    formatter.dateFormat = "yyyy-MM-dd"

    guard let date = formatter.date(from: dateStr) else {

        return dateStr

    }

    let calendar = Calendar.current

    if calendar.isDateInToday(date) {

        return NSLocalizedString("today", value: "今天", comment: "Today")

    }

    if calendar.isDateInYesterday(date) {

        return NSLocalizedString("yesterday", value: "昨天", comment: "Yesterday")

    }

    

    let monthFormat = NSLocalizedString("month_day_format", value: "%d月%d日", comment: "Month Day format")

    let month = calendar.component(.month, from: date)

    let day = calendar.component(.day, from: date)

    return String(format: monthFormat, month, day)

}
