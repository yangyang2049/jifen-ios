import Foundation

enum ScoreboardCatalogSection: String, CaseIterable, Identifiable {
    case sports
    case billiards
    case cardGames
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sports:
            return NSLocalizedString("scoreboard_sports", value: "运动", comment: "Sports section")
        case .billiards:
            return NSLocalizedString("scoreboard_billiards", value: "台球", comment: "Billiards section")
        case .cardGames:
            return NSLocalizedString("scoreboard_board_games", value: "棋牌", comment: "Board/card games section")
        case .other:
            return NSLocalizedString("scoreboard_other", value: "其他计分", comment: "Other scoring section")
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
    case checkers
    case cube
    case timeout
    case basketball24
    case basketball12

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .stopwatch: return "⏱️"
        case .go: return "⚫"
        case .xiangqi: return "🐘"
        case .chess: return "♟️"
        case .checkers: return "⚪"
        case .cube: return "🧩"
        case .timeout: return "⏸️"
        case .basketball24, .basketball12: return "🏀"
        }
    }

    var titleKey: String {
        switch self {
        case .stopwatch: return "tool_stopwatch"
        case .go: return "timer_go"
        case .xiangqi: return "timer_xiangqi"
        case .chess: return "timer_chess"
        case .checkers: return "timer_checkers"
        case .cube: return "timer_cube"
        case .timeout: return "timer_timeout"
        case .basketball24: return "timer_basketball_24s"
        case .basketball12: return "timer_basketball_12s"
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
        case .checkers: return .checkers
        default: return nil
        }
    }

    var requiresDualSetup: Bool {
        switch self {
        case .go, .xiangqi, .chess, .checkers:
            return true
        default:
            return false
        }
    }
}

enum GameCatalog {
    static let scoreboardItems: [ScoreboardCatalogItem] = [
        ScoreboardCatalogItem(gameType: .pingpong, emoji: "🏓", section: .sports),
        ScoreboardCatalogItem(gameType: .badminton, emoji: "🏸", section: .sports),
        ScoreboardCatalogItem(gameType: .tennis, emoji: "🎾", section: .sports),
        ScoreboardCatalogItem(gameType: .pickleball, emoji: "🎾", section: .sports),
        ScoreboardCatalogItem(gameType: .football, emoji: "⚽", section: .sports),
        ScoreboardCatalogItem(gameType: .basketball, emoji: "🏀", section: .sports),
        ScoreboardCatalogItem(gameType: .threeBasketball, emoji: "🏀", section: .sports),
        ScoreboardCatalogItem(gameType: .volleyball, emoji: "🏐", section: .sports),
        ScoreboardCatalogItem(gameType: .beachVolleyball, emoji: "🏐", section: .sports),
        ScoreboardCatalogItem(gameType: .airVolleyball, emoji: "🏐", section: .sports),
        ScoreboardCatalogItem(gameType: .archery, emoji: "🏹", section: .sports),
        ScoreboardCatalogItem(gameType: .boxing, emoji: "🥊", section: .sports),

        ScoreboardCatalogItem(gameType: .billiards, emoji: "🎱", section: .billiards),
        ScoreboardCatalogItem(gameType: .eightBall, emoji: "🎱", section: .billiards),
        ScoreboardCatalogItem(gameType: .nineBall, emoji: "🎱", section: .billiards),
        ScoreboardCatalogItem(gameType: .snooker, emoji: "🎱", section: .billiards),

        ScoreboardCatalogItem(gameType: .doudizhu, emoji: "🃏", section: .cardGames),
        ScoreboardCatalogItem(gameType: .guandan, emoji: "🃏", section: .cardGames),
        ScoreboardCatalogItem(gameType: .shengji, emoji: "🃏", section: .cardGames),
        ScoreboardCatalogItem(gameType: .uno, emoji: "🎴", section: .cardGames),

        ScoreboardCatalogItem(gameType: .foosball, emoji: "⚽", section: .other),
        ScoreboardCatalogItem(gameType: .simpleScore, emoji: "🔢", section: .other),
        ScoreboardCatalogItem(gameType: .multiScoreboard, emoji: "👥", section: .other)
    ]

    static func scoreboardItems(in section: ScoreboardCatalogSection) -> [ScoreboardCatalogItem] {
        scoreboardItems.filter { $0.section == section }
    }

    static let timerBoardGameItems: [TimerDestination] = [.go, .xiangqi, .chess, .checkers]
    static let timerOtherItems: [TimerDestination] = [.cube, .stopwatch, .timeout, .basketball24, .basketball12]
    static let timerAllItems: [TimerDestination] = timerBoardGameItems + timerOtherItems

    static let scoreboardGameTypes: [GameType] = scoreboardItems.map(\.gameType)
    static let timerSelectableGameTypes: [GameType] = timerAllItems.compactMap(\.mappedGameType)
    static let quickStartSelectableGameTypes: [GameType] = unique(scoreboardGameTypes + timerSelectableGameTypes)
    /// 新比赛弹窗展示的项目（不含秒表，秒表仅在计时 Tab 中使用）
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
