import SwiftUI



// MARK: - GameType Utilities (based on HomeUtils.ts)

import Foundation // For String localization potentially, or just general utilities
// Assuming GameType is part of the main 'jifen' module and thus accessible


// Timer types for quick start (navigate to Timer tab)
let quickStartTimerTypes: Set<GameType> = Set(GameCatalog.timerSelectableGameTypes)

// Universal blue gradient for all small cards (sports + times)
let GAME_GRADIENTS: [GameType: [Color]] = [
    .basketball: [Color(hex: "#EA580C"), Color(hex: "#C2410C")],
    .football: [Color(hex: "#10B981"), Color(hex: "#047857")],
    .badminton: [Color(hex: "#3B82F6"), Color(hex: "#1E40AF")],
    .pingpong: [Color(hex: "#EF4444"), Color(hex: "#B91C1C")],
    .tennis: [Color(hex: "#84CC16"), Color(hex: "#4D7C0F")],
    .volleyball: [Color(hex: "#EAB308"), Color(hex: "#A16207")],
    .checkers: [Color(hex: "#A3A3A3"), Color(hex: "#525252")],
    .boxing: [Color(hex: "#DC2626"), Color(hex: "#991B1B")],
    .billiards: [Color(hex: "#0F766E"), Color(hex: "#115E59")],
    .pickleball: [Color(hex: "#14B8A6"), Color(hex: "#0F766E")],
    .archery: [Color(hex: "#E53935"), Color(hex: "#B71C1C")],
    .guandan: [Color(hex: "#8B5CF6"), Color(hex: "#6D28D9")],
    .doudizhu: [Color(hex: "#F97316"), Color(hex: "#C2410C")],
    .simpleScore: [Color(hex: "#6B7280"), Color(hex: "#374151")],
    .multiScoreboard: [Color(hex: "#6366F1"), Color(hex: "#4338CA")],
    .counter: [Color(hex: "#EC4899"), Color(hex: "#BE185D")],
    .stopwatch: [Color(hex: "#6B7280"), Color(hex: "#374151")],
    .go: [Color(hex: "#57534E"), Color(hex: "#292524")],
    .xiangqi: [Color(hex: "#B45309"), Color(hex: "#78350F")],
    .chess: [Color(hex: "#525252"), Color(hex: "#262626")],
]

func getGameName(type: GameType) -> String {
    return type.displayName
}

func getGameIcon(type: GameType) -> String {
    return type.icon
}

func getGameGradient(type: GameType) -> [Color] {
    return GAME_GRADIENTS[type] ?? [Color(hex: "#71717A"), Color(hex: "#3F3F46")] // Default gray if not found
}

func getGameStats(type: GameType) -> String {
    // Placeholder for now, can be connected to real stats later
    return NSLocalizedString("home_start_game", comment: "Start Game")
}

func getPlusIcon() -> String {
    // Use emoji for reliable + icon display
    return "➕"
}

// Game types excluded from Quick Start config (计时器、计数器、跳棋)
// Quick Start options should stay fully aligned with Scoreboard/Timer tabs.
let availableSports: [GameType] = GameCatalog.quickStartSelectableGameTypes

let quickStartTextTimerTypes: Set<GameType> = quickStartTimerTypes

func isQuickStartTimerType(_ type: GameType) -> Bool {
    quickStartTextTimerTypes.contains(type)
}
