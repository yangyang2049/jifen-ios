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
        ScoreboardCatalogItem(gameType: .badminton, emoji: "🏸", section: .sports),
        ScoreboardCatalogItem(gameType: .tennis, emoji: "🎾", section: .sports),
        ScoreboardCatalogItem(gameType: .pingpong, emoji: "🏓", section: .sports),
        ScoreboardCatalogItem(gameType: .pickleball, emoji: "🏓", section: .sports),
        ScoreboardCatalogItem(gameType: .shuttlecock, emoji: "🏸", section: .sports),
        ScoreboardCatalogItem(gameType: .squash, emoji: "🎾", section: .sports),
        ScoreboardCatalogItem(gameType: .softTennis, emoji: "🎾", section: .sports),
        ScoreboardCatalogItem(gameType: .padel, emoji: "🎾", section: .sports),
        ScoreboardCatalogItem(gameType: .football, emoji: "⚽", section: .sports),
        ScoreboardCatalogItem(gameType: .football5v5, emoji: "⚽", section: .sports),
        ScoreboardCatalogItem(gameType: .basketball, emoji: "🏀", section: .sports),
        ScoreboardCatalogItem(gameType: .threeBasketball, emoji: "🏀", section: .sports),
        ScoreboardCatalogItem(gameType: .basketballTraining, emoji: "🏀", section: .sports),
        ScoreboardCatalogItem(gameType: .volleyball, emoji: "🏐", section: .sports),
        ScoreboardCatalogItem(gameType: .beachVolleyball, emoji: "🏐", section: .sports),
        ScoreboardCatalogItem(gameType: .airVolleyball, emoji: "🏐", section: .sports),
        ScoreboardCatalogItem(gameType: .archery, emoji: "🏹", section: .sports),
        ScoreboardCatalogItem(gameType: .boxing, emoji: "🥊", section: .sports),

        ScoreboardCatalogItem(gameType: .billiards, emoji: "🎱", section: .billiards),
        ScoreboardCatalogItem(gameType: .snooker, emoji: "🎱", section: .billiards),
        ScoreboardCatalogItem(gameType: .eightBall, emoji: "🎱", section: .billiards),
        ScoreboardCatalogItem(gameType: .nineBall, emoji: "🎱", section: .billiards),

        ScoreboardCatalogItem(gameType: .doudizhu, emoji: "🃏", section: .cardGames),
        ScoreboardCatalogItem(gameType: .guandan, emoji: "🃏", section: .cardGames),
        ScoreboardCatalogItem(gameType: .shengji, emoji: "🃏", section: .cardGames),
        ScoreboardCatalogItem(gameType: .uno, emoji: "🎴", section: .cardGames),

        ScoreboardCatalogItem(gameType: .foosball, emoji: "⚽", section: .other),
        ScoreboardCatalogItem(gameType: .simpleScore, emoji: "🔢", section: .other),
        ScoreboardCatalogItem(gameType: .multiScoreboard, emoji: "👥", section: .other)
    ]

    private static var uiLocalization: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    /// 与快速开始默认项目一致，按 App 显示语言选择偏好，避免设备地区造成入口顺序不一致。
    static func prefersBadminton(for localization: String) -> Bool {
        let language = Locale(identifier: localization).language.languageCode?.identifier
        let badmintonLanguages: Set<String> = [
            "zh", "ja", "ko", "id", "ms", "th", "vi",
            "hi", "bn", "gu", "kn", "ml", "mr", "or", "pa", "ta", "te", "ur"
        ]
        return language.map { badmintonLanguages.contains($0) } == true
    }

    static func scoreboardItems(in section: ScoreboardCatalogSection) -> [ScoreboardCatalogItem] {
        let items = scoreboardItems.filter { $0.section == section && isSelectable($0.gameType) }
        let leadingTypes: [GameType]
        switch section {
        case .sports:
            leadingTypes = prefersBadminton(for: uiLocalization)
                ? [.badminton, .tennis, .pingpong, .pickleball]
                : [.tennis, .pickleball, .badminton, .pingpong]
        case .cardGames:
            leadingTypes = [.uno]
        default:
            return items
        }
        let leading = leadingTypes.compactMap { type in items.first { $0.gameType == type } }
        let rest = items.filter { !leadingTypes.contains($0.gameType) }
        return leading + rest
    }

    /// 所有选择入口与计分页复用显示顺序；原始目录仍保留完整记录项目。
    static var selectableScoreboardGameTypes: [GameType] {
        ScoreboardCatalogSection.allCases.flatMap { scoreboardItems(in: $0).map(\.gameType) }
    }

    /// 英文界面隐藏的项目：毽球/气排球只在中文等其余语言展示，英文版不再提供入口。
    /// 记录目录不受影响（`scoreboardItems` 保持完整），已有对局与筛选不受影响。
    private static let hiddenInEnglishGameTypes: Set<GameType> = [.shuttlecock, .airVolleyball]

    /// 跟随 App 显示语言（与 timerBoardGameItems 同口径），英文界面为 true。
    static let isEnglishUI: Bool = {
        let localization = Bundle.main.preferredLocalizations.first ?? "en"
        let language = Locale(identifier: localization).language.languageCode?.identifier
        return language == "en"
    }()

    static func isSelectable(_ gameType: GameType) -> Bool {
        isSelectable(gameType, isEnglish: isEnglishUI)
    }

    static func isSelectable(_ gameType: GameType, isEnglish: Bool) -> Bool {
        !(isEnglish && hiddenInEnglishGameTypes.contains(gameType))
    }

    /// 项目所属的计分板分区；目录只收计分板项目，其余（计时类棋类等）返回 nil。
    static func section(for gameType: GameType) -> ScoreboardCatalogSection? {
        scoreboardItems.first { $0.gameType == gameType }?.section
    }

    /// Follow the app's displayed language, including regional Chinese variants.
    static let timerBoardGameItems: [TimerDestination] = {
        let localization = Bundle.main.preferredLocalizations.first ?? "en"
        let language = Locale(identifier: localization).language.languageCode?.identifier
        if language == "zh" || language == "ja" || language == "ko" {
            return [.go, .xiangqi, .chess, .checkers]
        }
        return [.chess, .go, .checkers, .xiangqi]
    }()
    static let timerOtherItems: [TimerDestination] = [.cube, .stopwatch, .timeout]
    static let timerAllItems: [TimerDestination] = timerBoardGameItems + timerOtherItems

    static let scoreboardGameTypes: [GameType] = scoreboardItems.map(\.gameType)
    static let timerSelectableGameTypes: [GameType] = timerAllItems.compactMap(\.mappedGameType)
    static var quickStartSelectableGameTypes: [GameType] {
        unique(selectableScoreboardGameTypes + timerSelectableGameTypes)
    }
    /// 新比赛弹窗展示的项目（不含秒表，秒表仅在计时 Tab 中使用）
    static var newGameDialogGameTypes: [GameType] {
        quickStartSelectableGameTypes.filter { $0 != .stopwatch }
    }

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
