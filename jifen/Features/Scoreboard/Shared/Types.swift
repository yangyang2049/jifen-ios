//
//  Types.swift
//  jifen
//
//  Scoreboard shared types
//

import Foundation
import SwiftUI

// MARK: - Game Type

enum GameType: String, Codable, CaseIterable {
    case pingpong = "pingpong"
    case badminton = "badminton"
    case tennis = "tennis"
    case basketball = "basketball"
    case football = "football"
    case volleyball = "volleyball"
    
    var displayName: String {
        switch self {
        case .pingpong: return "乒乓球"
        case .badminton: return "羽毛球"
        case .tennis: return "网球"
        case .basketball: return "篮球"
        case .football: return "足球"
        case .volleyball: return "排球"
        }
    }
    
    var icon: String {
        switch self {
        case .pingpong: return "🏓"
        case .badminton: return "🏸"
        case .tennis: return "🎾"
        case .basketball: return "🏀"
        case .football: return "⚽"
        case .volleyball: return "🏐"
        }
    }
}

// MARK: - Team Data

@Observable
class TeamData {
    var name: String = ""
    var score: Int = 0
    var sets: Int? = nil  // 局数（用于乒乓球、排球、羽毛球等）；盘数/Set（用于网球等）
    var games: Int? = nil  // 局数/Game（用于网球等）
    
    init(name: String = "", score: Int = 0, sets: Int? = nil, games: Int? = nil) {
        self.name = name
        self.score = score
        self.sets = sets
        self.games = games
    }
}

// MARK: - History Item

struct HistoryItem {
    let left: Int
    let right: Int
    let leftSets: Int?
    let rightSets: Int?
    let leftGames: Int?
    let rightGames: Int?
    let timestamp: Date
    
    init(left: Int, right: Int, leftSets: Int? = nil, rightSets: Int? = nil, leftGames: Int? = nil, rightGames: Int? = nil) {
        self.left = left
        self.right = right
        self.leftSets = leftSets
        self.rightSets = rightSets
        self.leftGames = leftGames
        self.rightGames = rightGames
        self.timestamp = Date()
    }
}

// MARK: - Vibration Type

enum VibrationType {
    case light
    case medium
    case heavy
}

// MARK: - Scoreboard Controller Config

struct ScoreboardControllerConfig {
    let gameType: GameType
    let enableRecording: Bool
    let enableScreenshot: Bool
    let enableUndo: Bool
    let maxHistorySize: Int
    
    init(
        gameType: GameType,
        enableRecording: Bool = true,
        enableScreenshot: Bool = true,
        enableUndo: Bool = true,
        maxHistorySize: Int = 50
    ) {
        self.gameType = gameType
        self.enableRecording = enableRecording
        self.enableScreenshot = enableScreenshot
        self.enableUndo = enableUndo
        self.maxHistorySize = maxHistorySize
    }
}

// MARK: - Base Controller Protocol

protocol BaseScoreboardControllerProtocol {
    var isTablet: Bool { get }
    var hideButtons: Bool { get set }
    var undoEnabled: Bool { get }
    var swipeScreenshotEnabled: Bool { get }
    var currentFont: String { get set }
    
    func performVibration(type: VibrationType)
    func pushHistory(left: Int, right: Int, leftSets: Int?, rightSets: Int?, leftGames: Int?, rightGames: Int?)
    func popHistory() -> HistoryItem?
    func clearHistory()
    func getScoringOptions() -> [Int]
    func handleExitClick() -> Bool
    func captureScreenshot(of view: UIView) -> UIImage?
    func saveScreenshotToPhotoLibrary(_ image: UIImage, completion: @escaping (Bool, Error?) -> Void)
    func generateScreenshotFileName() -> String
    func getFontFamily() -> String
}

// MARK: - Score ViewModel Protocol

protocol ScoreViewModelProtocol: AnyObject {
    var leftTeam: TeamData { get }
    var rightTeam: TeamData { get }
    var gameFinished: Bool { get }
    
    func addScore(isLeft: Bool, points: Int)
    func subtractScore(isLeft: Bool, points: Int)
    func reset()
    func undo() -> Bool
    func exchangeSides()
}

// MARK: - Template Config

struct TemplateConfig {
    let gameType: GameType
    var controller: BaseScoreboardControllerProtocol
    let viewModel: ScoreViewModelProtocol
    let scoreFontSize: CGFloat
    let nameType: NameType
    let scoreTextProvider: ((Bool, TeamData) -> String)?
    
    init(
        gameType: GameType,
        controller: BaseScoreboardControllerProtocol,
        viewModel: ScoreViewModelProtocol,
        scoreFontSize: CGFloat = 96,
        nameType: NameType = .team,
        scoreTextProvider: ((Bool, TeamData) -> String)? = nil
    ) {
        self.gameType = gameType
        self.controller = controller
        self.viewModel = viewModel
        self.scoreFontSize = scoreFontSize
        self.nameType = nameType
        self.scoreTextProvider = scoreTextProvider
    }
}

// MARK: - Name Type

enum NameType {
    case team
    case player
}

// MARK: - Set End Callback Data

struct SetEndCallbackData {
    let finalLeftScore: Int
    let finalRightScore: Int
    let winnerName: String
    let setNumber: Int
    let leftSets: Int
    let rightSets: Int
    let leftGames: Int?
    let rightGames: Int?
    let shouldChangeSides: Bool
    let isGameFinished: Bool
    let continueUpdate: () -> Void
}
