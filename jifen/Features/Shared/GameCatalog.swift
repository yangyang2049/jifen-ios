import Foundation

enum ScoreboardCatalogSection: String, CaseIterable, Identifiable {
    case sports
    case boardGames
    case scoring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sports:
            return NSLocalizedString("scoreboard_sports", value: "运动", comment: "Sports section")
        case .boardGames:
            return NSLocalizedString("scoreboard_board_games", value: "棋牌", comment: "Board/card games section")
        case .scoring:
            return NSLocalizedString("scoreboard_cards", value: "计分", comment: "Scoring tools section")
        }
    }
}

struct ScoreboardCatalogItem: Identifiable, Hashable {
    let gameType: GameType
    let emoji: String
    let section: ScoreboardCatalogSection

    var id: String { gameType.rawValue }
    var title: String { gameType.displayName }
}

enum TimerDestination: String, Hashable, CaseIterable, Identifiable {
    case stopwatch
    case go
    case xiangqi
    case chess
    case cube
    case timeout

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .stopwatch: return "⏱️"
        case .go: return "⚫"
        case .xiangqi: return "🐘"
        case .chess: return "♟️"
        case .cube: return "🧩"
        case .timeout: return "⏸️"
        }
    }

    var titleKey: String {
        switch self {
        case .stopwatch: return "timer_count_up"
        case .go: return "timer_go"
        case .xiangqi: return "timer_xiangqi"
        case .chess: return "timer_chess"
        case .cube: return "timer_cube"
        case .timeout: return "timer_timeout"
        }
    }

    var title: String {
        NSLocalizedString(titleKey, comment: "")
    }

    var mappedGameType: GameType? {
        switch self {
        case .stopwatch: return .stopwatch
        case .go: return .go
        case .xiangqi: return .xiangqi
        case .chess: return .chess
        default: return nil
        }
    }

    var requiresDualSetup: Bool {
        switch self {
        case .go, .xiangqi, .chess:
            return true
        default:
            return false
        }
    }
}

enum GameCatalog {
    static let scoreboardItems: [ScoreboardCatalogItem] = [
        ScoreboardCatalogItem(gameType: .football, emoji: "⚽", section: .sports),
        ScoreboardCatalogItem(gameType: .basketball, emoji: "🏀", section: .sports),
        ScoreboardCatalogItem(gameType: .volleyball, emoji: "🏐", section: .sports),
        ScoreboardCatalogItem(gameType: .pingpong, emoji: "🏓", section: .sports),
        ScoreboardCatalogItem(gameType: .badminton, emoji: "🏸", section: .sports),
        ScoreboardCatalogItem(gameType: .tennis, emoji: "🎾", section: .sports),
        ScoreboardCatalogItem(gameType: .pickleball, emoji: "🏓", section: .sports),
        ScoreboardCatalogItem(gameType: .boxing, emoji: "🥊", section: .sports),
        ScoreboardCatalogItem(gameType: .billiards, emoji: "🎱", section: .sports),
        ScoreboardCatalogItem(gameType: .archery, emoji: "🏹", section: .sports),

        ScoreboardCatalogItem(gameType: .doudizhu, emoji: "🃏", section: .boardGames),
        ScoreboardCatalogItem(gameType: .guandan, emoji: "🃏", section: .boardGames),

        ScoreboardCatalogItem(gameType: .simpleScore, emoji: "🔢", section: .scoring),
        ScoreboardCatalogItem(gameType: .multiScoreboard, emoji: "👥", section: .scoring)
    ]

    static func scoreboardItems(in section: ScoreboardCatalogSection) -> [ScoreboardCatalogItem] {
        scoreboardItems.filter { $0.section == section }
    }

    static let timerBoardGameItems: [TimerDestination] = [.go, .xiangqi, .chess]
    static let timerOtherItems: [TimerDestination] = [.cube, .stopwatch, .timeout]
    static let timerAllItems: [TimerDestination] = timerBoardGameItems + timerOtherItems

    static let scoreboardGameTypes: [GameType] = scoreboardItems.map(\.gameType)
    static let timerSelectableGameTypes: [GameType] = timerAllItems.compactMap(\.mappedGameType)
    static let quickStartSelectableGameTypes: [GameType] = unique(scoreboardGameTypes + timerSelectableGameTypes)
    /// 新比赛弹窗展示的项目（不含秒表，秒表仅在计时/工具中使用）
    static let newGameDialogGameTypes: [GameType] = quickStartSelectableGameTypes.filter { $0 != .stopwatch }

    static func timerDestination(for gameType: GameType) -> TimerDestination? {
        timerAllItems.first { $0.mappedGameType == gameType }
    }

    private static func unique(_ source: [GameType]) -> [GameType] {
        var seen: Set<GameType> = []
        var result: [GameType] = []
        for item in source where !seen.contains(item) {
            seen.insert(item)
            result.append(item)
        }
        return result
    }
}
