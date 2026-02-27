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
    case checkers = "checkers"
    case boxing = "boxing"
    case billiards = "billiards"
    case pickleball = "pickleball"
    case archery = "archery"
    case guandan = "guandan"
    case doudizhu = "doudizhu"
    case simpleScore = "simpleScore"
    case multiScoreboard = "multiScoreboard"
    case counter = "counter"
    case stopwatch = "stopwatch"
    case go = "go"
    case xiangqi = "xiangqi"
    case chess = "chess"

    var displayName: String {
        switch self {
        case .pingpong: return NSLocalizedString("game_pingpong", comment: "Ping Pong")
        case .badminton: return NSLocalizedString("game_badminton", comment: "Badminton")
        case .tennis: return NSLocalizedString("game_tennis", comment: "Tennis")
        case .basketball: return NSLocalizedString("game_basketball", comment: "Basketball")
        case .football: return NSLocalizedString("game_football", comment: "Football")
        case .volleyball: return NSLocalizedString("game_volleyball", comment: "Volleyball")
        case .checkers: return NSLocalizedString("game_checkers", comment: "Checkers")
        case .boxing: return NSLocalizedString("game_boxing", comment: "Boxing")
        case .billiards: return NSLocalizedString("game_billiards", comment: "Billiards")
        case .pickleball: return NSLocalizedString("game_pickleball", comment: "Pickleball")
        case .archery: return NSLocalizedString("project_archery", value: "Archery", comment: "Archery")
        case .guandan: return NSLocalizedString("game_guandan", comment: "Guandan")
        case .doudizhu: return NSLocalizedString("game_doudizhu", comment: "Doudizhu")
        case .simpleScore: return NSLocalizedString("game_simple_score", value: "Simple Score", comment: "Simple Score")
        case .multiScoreboard: return NSLocalizedString("game_multi_scoreboard", value: "Multi-Score", comment: "Multi Scoreboard")
        case .counter: return NSLocalizedString("game_counter", comment: "Counter")
        case .stopwatch: return NSLocalizedString("game_stopwatch", comment: "Stopwatch")
        case .go: return NSLocalizedString("timer_go", comment: "Go")
        case .xiangqi: return NSLocalizedString("timer_xiangqi", comment: "Xiangqi")
        case .chess: return NSLocalizedString("timer_chess", comment: "Chess")
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
        case .checkers: return "🏁"
        case .boxing: return "🥊"
        case .billiards: return "🎱"
        case .pickleball: return "🏓"
        case .archery: return "🏹"
        case .guandan: return "🃏"
        case .doudizhu: return "🃏"
        case .simpleScore: return "🔢"
        case .multiScoreboard: return "👥"
        case .counter: return "➕"
        case .stopwatch: return "⏱️"
        case .go: return "⚫"
        case .xiangqi: return "🐘"
        case .chess: return "♟️"
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
    
    func performVibration(type: VibrationType)
    func pushHistory(left: Int, right: Int, leftSets: Int?, rightSets: Int?, leftGames: Int?, rightGames: Int?)
    func popHistory() -> HistoryItem?
    func clearHistory()
    func getScoringOptions() -> [Int]
    func handleExitClick() -> Bool
    func captureScreenshot(of view: UIView) -> UIImage?
    func saveScreenshotToPhotoLibrary(_ image: UIImage, completion: @escaping (Bool, Error?) -> Void)
    func generateScreenshotFileName() -> String
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
    /// 结束比赛（足球/篮球等无计时终场时，由菜单「结束比赛」调用）
    func endGame()
    /// 编辑模式下局分 ±（射箭/羽毛球等有局分的项目实现）
    func adjustSets(isLeft: Bool, delta: Int)
}

extension ScoreViewModelProtocol {
    func adjustSets(isLeft: Bool, delta: Int) {}
}

// MARK: - Template Config

struct TemplateConfig {
    let gameType: GameType
    var controller: BaseScoreboardControllerProtocol
    let viewModel: ScoreViewModelProtocol
    let scoreFontSize: CGFloat
    let nameType: NameType
    let isDoublesModeProvider: (() -> Bool)?
    let scoreTextProvider: ((Bool, TeamData) -> String)?
    let tapToAddEnabled: Bool
    /// 插在左右半区之上、编辑/底部按钮与菜单之下的中间层；参数为 isEditMode，编辑模式下可隐藏或禁用交互（如射箭不发球箭头、不响应半区点击）
    let contentOverlayProvider: ((Bool) -> AnyView)?
    /// 编辑模式变化时回调，供父视图隐藏发球指示器等（编辑模式下不显示）
    let onEditModeChange: ((Bool) -> Void)?

    init(
        gameType: GameType,
        controller: BaseScoreboardControllerProtocol,
        viewModel: ScoreViewModelProtocol,
        scoreFontSize: CGFloat = 96,
        nameType: NameType = .team,
        isDoublesModeProvider: (() -> Bool)? = nil,
        scoreTextProvider: ((Bool, TeamData) -> String)? = nil,
        tapToAddEnabled: Bool = true,
        contentOverlayProvider: ((Bool) -> AnyView)? = nil,
        onEditModeChange: ((Bool) -> Void)? = nil
    ) {
        self.gameType = gameType
        self.controller = controller
        self.viewModel = viewModel
        self.scoreFontSize = scoreFontSize
        self.nameType = nameType
        self.isDoublesModeProvider = isDoublesModeProvider
        self.scoreTextProvider = scoreTextProvider
        self.tapToAddEnabled = tapToAddEnabled
        self.contentOverlayProvider = contentOverlayProvider
        self.onEditModeChange = onEditModeChange
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
