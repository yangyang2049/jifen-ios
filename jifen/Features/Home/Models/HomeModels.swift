import Foundation
import SwiftUI // For Color (though not directly used here, good practice if views are nearby)
// Assuming GameType is part of the main 'jifen' module
// and formatScoreboardDuration is globally available or imported from the same module



// MARK: - ActivityType Enum
enum ActivityType: Int, Codable, Identifiable {
    var id: Self { self } // Conforming to Identifiable for ForEach loops
    case scoreboard = 0
    case timer = 1
}

// MARK: - GameRecordSummary Struct (for timer records)
// This struct is inferred from HarmonyOS HomeTab.ets logic for timer activities.
// It will be used to represent a summary of a timer record.
struct GameRecordSummary: Identifiable, Codable, Equatable {
    let id: String
    let gameType: GameType
    let timestamp: TimeInterval
    var duration: TimeInterval?
    var winner: String?
    
    var title: String {
        gameType.displayName
    }
    var description: String {
        if let duration = duration {
            return "Duration: \(formatDuration(duration))"
        }
        return ""
    }
    var date: String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    var time: String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // Equatable conformance
    static func == (lhs: GameRecordSummary, rhs: GameRecordSummary) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - RecentActivity Struct
// This struct combines common fields from both timer and scoreboard records
// to be displayed in the recent activities list.
struct RecentActivity: Identifiable, Codable {
    let id: String
    let activityType: ActivityType
    let gameType: GameType
    let timestamp: TimeInterval // Unix timestamp
    let title: String
    let description: String
}

// MARK: - SourcePage Enum
enum SourcePage: String, Codable {
    case home = "HOME"
    case newGameDialog = "NEW_GAME_DIALOG" // Added based on typical usage
    // Add other cases as needed from HarmonyOS project
}

// MARK: - GameItem Struct
struct GameItem: Identifiable {
    let id = UUID() // Using UUID for Identifiable conformance
    let type: GameType
    let nameKey: String // Using key for localization $r('app.string.tab_volleyball') etc.
    let emoji: String // Icon
    let route: String // String for route, to be translated to NavigationLink later
}

// MARK: - QuickStartConfig Struct
struct QuickStartConfig: Codable, Equatable {
    var primarySport: GameType
    var secondarySport: GameType

    // A default configuration for phone, similar to DEFAULT_QUICK_START_CONFIG_PHONE
    static let defaultPhoneConfig = QuickStartConfig(primarySport: .basketball, secondarySport: .badminton)
}

// MARK: - SportsSetupResult Struct (refined for 6 supported sports)
// Based on HarmonyOS SportsSetupDialog.ets, excluding pickleball-specific fields
struct SportsSetupResult: Codable {
    var team1Name: String
    var team2Name: String
    var maxSets: Int? = nil
    var pointsPerSet: Int? = nil
    var tieBreakPoints: Int? = nil
    var autoChangeSides: Bool? = nil // autoChangeSides (Pingpong, Tennis, Badminton, Volleyball)
}

// MARK: - RecentGameDisplay Struct (for SportsSetupDialog)
// Based on HarmonyOS SportsSetupDialog.ets
struct RecentGameDisplay: Identifiable, Codable {
    let id: String // recordId
    let team1Name: String
    let team2Name: String
    let score: String
    let time: String
    let recordId: String
    var setsInfo: String?
}



