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
    case go = "go"
    case xiangqi = "xiangqi"
    case chess = "chess"
    case checkers = "checkers"
    case boxing = "boxing"
    case billiards = "billiards"
    case pickleball = "pickleball"
    case guandan = "guandan"
    case doudizhu = "doudizhu"
    case simpleScore = "simpleScore"
    case multiScoreboard = "multiScoreboard"
    case counter = "counter"

    var displayName: String {
        switch self {
        case .pingpong: return NSLocalizedString("game_pingpong", comment: "Ping Pong")
        case .badminton: return NSLocalizedString("game_badminton", comment: "Badminton")
        case .tennis: return NSLocalizedString("game_tennis", comment: "Tennis")
        case .basketball: return NSLocalizedString("game_basketball", comment: "Basketball")
        case .football: return NSLocalizedString("game_football", comment: "Football")
        case .volleyball: return NSLocalizedString("game_volleyball", comment: "Volleyball")
        case .go: return NSLocalizedString("game_go", comment: "Go")
        case .xiangqi: return NSLocalizedString("game_xiangqi", comment: "Chinese Chess")
        case .chess: return NSLocalizedString("game_chess", comment: "Chess")
        case .checkers: return NSLocalizedString("game_checkers", comment: "Checkers")
        case .boxing: return NSLocalizedString("game_boxing", comment: "Boxing")
        case .billiards: return NSLocalizedString("game_billiards", comment: "Billiards")
        case .pickleball: return NSLocalizedString("game_pickleball", comment: "Pickleball")
        case .guandan: return NSLocalizedString("game_guandan", comment: "Guandan")
        case .doudizhu: return NSLocalizedString("game_doudizhu", comment: "Doudizhu")
        case .simpleScore: return NSLocalizedString("game_simple_score", comment: "Simple Score")
        case .multiScoreboard: return NSLocalizedString("game_multi_scoreboard", comment: "Multi Scoreboard")
        case .counter: return NSLocalizedString("game_counter", comment: "Counter")
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
        case .go: return "⚪⚫"
        case .xiangqi: return "象棋"
        case .chess: return "♔♕"
        case .checkers: return "🏁"
        case .boxing: return "🥊"
        case .billiards: return "🎱"
        case .pickleball: return "🏓"
        case .guandan: return "🃏"
        case .doudizhu: return "🃏"
        case .simpleScore: return "📝"
        case .multiScoreboard: return "📊"
        case .counter: return "➕"
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

enum NameType: String, Codable {
    case team = "TEAM"
    case player = "PLAYER"
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
