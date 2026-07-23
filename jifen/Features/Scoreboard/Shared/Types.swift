//
//  Types.swift
//  jifen
//
//  Scoreboard shared types
//

import Foundation
import ScoreCore
import SwiftUI

// MARK: - Game Type

func resolvedScoreboardSetupName(_ name: String?, fallback: String) -> String {
    guard let name else { return fallback }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
}

enum GameType: String, Codable, CaseIterable {
    case pingpong = "pingpong"
    case badminton = "badminton"
    case tennis = "tennis"
    case basketball = "basketball"
    case threeBasketball = "three_basketball"
    case football = "football"
    case volleyball = "volleyball"
    case beachVolleyball = "beach_volleyball"
    case airVolleyball = "air_volleyball"
    case checkers = "checkers"
    case boxing = "boxing"
    case billiards = "billiards"
    case eightBall = "eight_ball"
    case nineBall = "nine_ball"
    case snooker = "snooker"
    case pickleball = "pickleball"
    case archery = "archery"
    case guandan = "guandan"
    case doudizhu = "doudizhu"
    case shengji = "shengji"
    case uno = "uno"
    case foosball = "foosball"
    case simpleScore = "simpleScore"
    case multiScoreboard = "multiScoreboard"
    case counter = "counter"
    case stopwatch = "stopwatch"
    case go = "go"
    case xiangqi = "xiangqi"
    case chess = "chess"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "archery_dual": self = .archery
        case "simple_score": self = .simpleScore
        case "multi_scoreboard": self = .multiScoreboard
        default:
            guard let gameType = Self(rawValue: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown game type: \(value)")
            }
            self = gameType
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(canonicalScoreboardIdentifier)
    }

    var displayName: String {
        switch self {
        case .pingpong: return NSLocalizedString("game_pingpong", comment: "Ping Pong")
        case .badminton: return NSLocalizedString("game_badminton", comment: "Badminton")
        case .tennis: return NSLocalizedString("game_tennis", comment: "Tennis")
        case .basketball: return NSLocalizedString("game_basketball", comment: "Basketball")
        case .threeBasketball: return NSLocalizedString("game_three_basketball", value: "三人篮球", comment: "3x3 Basketball")
        case .football: return NSLocalizedString("game_football", comment: "Football")
        case .volleyball: return NSLocalizedString("game_volleyball", comment: "Volleyball")
        case .beachVolleyball: return NSLocalizedString("game_beach_volleyball", value: "沙滩排球", comment: "Beach Volleyball")
        case .airVolleyball: return NSLocalizedString("game_air_volleyball", value: "气排球", comment: "Air Volleyball")
        case .checkers: return NSLocalizedString("game_checkers", comment: "Checkers")
        case .boxing: return NSLocalizedString("game_boxing", comment: "Boxing")
        case .billiards: return NSLocalizedString("game_billiards", comment: "Billiards")
        case .eightBall: return NSLocalizedString("game_eight_ball", value: "黑八", comment: "Eight Ball")
        case .nineBall: return NSLocalizedString("game_nine_ball", value: "追分", comment: "Chase Points")
        case .snooker: return NSLocalizedString("game_snooker", value: "斯诺克", comment: "Snooker")
        case .pickleball: return NSLocalizedString("game_pickleball", comment: "Pickleball")
        case .archery: return NSLocalizedString("project_archery", value: "Archery", comment: "Archery")
        case .guandan: return NSLocalizedString("game_guandan", comment: "Guandan")
        case .doudizhu: return NSLocalizedString("game_doudizhu", comment: "Doudizhu")
        case .shengji: return NSLocalizedString("game_shengji", value: "升级", comment: "Shengji")
        case .uno: return NSLocalizedString("game_uno", value: "UNO", comment: "UNO")
        case .foosball: return NSLocalizedString("game_foosball", value: "桌上足球", comment: "Foosball")
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
        case .threeBasketball: return "🏀"
        case .football: return "⚽"
        case .volleyball: return "🏐"
        case .beachVolleyball, .airVolleyball: return "🏐"
        case .checkers: return "🏁"
        case .boxing: return "🥊"
        case .billiards: return "🎱"
        case .eightBall, .nineBall, .snooker: return "🎱"
        case .pickleball: return "🏓"
        case .archery: return "🏹"
        case .guandan: return "🃏"
        case .doudizhu: return "🃏"
        case .shengji: return "🃏"
        case .uno: return "🎴"
        case .foosball: return "⚽"
        case .simpleScore: return "🔢"
        case .multiScoreboard: return "👥"
        case .counter: return "➕"
        case .stopwatch: return "⏱️"
        case .go: return "⚫"
        case .xiangqi: return "🐘"
        case .chess: return "♟️"
        }
    }

    /// Scoreboard/timer types shown in Records filter (excludes counter).
    static var scoreboardFilterTypes: [GameType] {
        [
            .pingpong, .badminton, .tennis, .pickleball, .football, .basketball, .threeBasketball,
            .volleyball, .beachVolleyball, .airVolleyball, .archery, .boxing,
            .billiards, .eightBall, .nineBall, .snooker,
            .doudizhu, .guandan, .shengji, .uno, .foosball, .simpleScore, .multiScoreboard,
            .xiangqi, .go, .chess, .checkers, .stopwatch
        ]
    }

    var canonicalScoreboardIdentifier: String {
        switch self {
        case .archery: return "archery_dual"
        case .simpleScore: return "simple_score"
        case .multiScoreboard: return "multi_scoreboard"
        default: return rawValue
        }
    }

    init?(scoreCoreGameType: ScoreCore.GameType) {
        switch scoreCoreGameType {
        case .pingpong, .pingpongDoubles: self = .pingpong
        case .badminton, .badmintonDoubles: self = .badminton
        case .tennis, .tennisDoubles: self = .tennis
        case .basketball: self = .basketball
        case .threeBasketball: self = .threeBasketball
        case .football: self = .football
        case .volleyball: self = .volleyball
        case .beachVolleyball: self = .beachVolleyball
        case .airVolleyball: self = .airVolleyball
        case .boxing: self = .boxing
        case .billiards: self = .billiards
        case .eightBall: self = .eightBall
        case .nineBall: self = .nineBall
        case .snooker: self = .snooker
        case .pickleball, .pickleballDoubles: self = .pickleball
        case .archeryDual: self = .archery
        case .guandan: self = .guandan
        case .doudizhu: self = .doudizhu
        case .shengji: self = .shengji
        case .uno: self = .uno
        case .foosball, .foosballDoubles: self = .foosball
        case .simpleScore: self = .simpleScore
        case .multiScoreboard: self = .multiScoreboard
        }
    }

    var scoreCoreGameType: ScoreCore.GameType? {
        ScoreCore.GameType(rawValue: canonicalScoreboardIdentifier)
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
    func recordScoreAction(action: String)
    func getScoringOptions() -> [Int]
    func handleExitClick() -> Bool
    /// Seconds remaining in the double-tap exit confirm window, if armed.
    var exitConfirmRemainingSeconds: TimeInterval? { get }
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
    let showEndGame: Bool
    let showSettleMatch: Bool
    let onEndGame: (() -> Void)?
    let extraMenuItemsProvider: (() -> [ScoreboardMenuItem])?
    let onMenuAction: ((String) -> Void)?
    /// Optional semantic key-point state for local display snapshots.
    let syncKeyPointProvider: (() -> LocalScoreboardKeyPoint?)?
    /// When set, replaces default tap-to-+1 / double-tap scoring for that panel side.
    let onScorePanelTap: ((Bool) -> Void)?

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
        onEditModeChange: ((Bool) -> Void)? = nil,
        showEndGame: Bool = false,
        showSettleMatch: Bool = false,
        onEndGame: (() -> Void)? = nil,
        extraMenuItemsProvider: (() -> [ScoreboardMenuItem])? = nil,
        onMenuAction: ((String) -> Void)? = nil,
        syncKeyPointProvider: (() -> LocalScoreboardKeyPoint?)? = nil,
        onScorePanelTap: ((Bool) -> Void)? = nil
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
        self.showEndGame = showEndGame
        self.showSettleMatch = showSettleMatch
        self.onEndGame = onEndGame
        self.extraMenuItemsProvider = extraMenuItemsProvider
        self.onMenuAction = onMenuAction
        self.syncKeyPointProvider = syncKeyPointProvider
        self.onScorePanelTap = onScorePanelTap
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
