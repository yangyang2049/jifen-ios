import Foundation
import SwiftUI // Required for Color, though not directly used in this file for styling. Keep for consistency if needed elsewhere.

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
    if hours > 0 {
        return String(format: "%d时%d分%d秒", hours, minutes, seconds)
    }
    if minutes > 0 {
        return String(format: "%d分%d秒", minutes, seconds)
    }
    return String(format: "%d秒", seconds)
}

func watchFormatDisplayDate(_ dateStr: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    guard let date = formatter.date(from: dateStr) else {
        return dateStr
    }
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
        return "今天"
    }
    if calendar.isDateInYesterday(date) {
        return "昨天"
    }
    let month = calendar.component(.month, from: date)
    let day = calendar.component(.day, from: date)
    return "\(month)月\(day)日"
}