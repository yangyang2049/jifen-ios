import SwiftUI



// MARK: - GameType Utilities (based on HomeUtils.ts)

import Foundation // For String localization potentially, or just general utilities
// Assuming GameType is part of the main 'jifen' module and thus accessible


let GAME_GRADIENTS: [GameType: [Color]] = [
    .basketball: [Color(hex: "#EA580C"), Color(hex: "#C2410C")], // Orange
    .football: [Color(hex: "#10B981"), Color(hex: "#047857")],   // Emerald
    .badminton: [Color(hex: "#3B82F6"), Color(hex: "#1E40AF")],  // Blue
    .pingpong: [Color(hex: "#EF4444"), Color(hex: "#B91C1C")],   // Red
    .tennis: [Color(hex: "#84CC16"), Color(hex: "#4D7C0F")],     // Lime
    .volleyball: [Color(hex: "#EAB308"), Color(hex: "#A16207")], // Yellow
    .go: [Color(hex: "#57534E"), Color(hex: "#292524")],         // Stone
    .xiangqi: [Color(hex: "#B45309"), Color(hex: "#78350F")],    // Amber
    .chess: [Color(hex: "#525252"), Color(hex: "#262626")],      // Neutral
    .checkers: [Color(hex: "#A3A3A3"), Color(hex: "#525252")],   // Neutral Light
    .boxing: [Color(hex: "#DC2626"), Color(hex: "#991B1B")],     // Red
    .billiards: [Color(hex: "#0F766E"), Color(hex: "#115E59")],  // Teal
    .pickleball: [Color(hex: "#14B8A6"), Color(hex: "#0F766E")], // Teal
    .guandan: [Color(hex: "#8B5CF6"), Color(hex: "#6D28D9")],    // Violet
    .doudizhu: [Color(hex: "#F97316"), Color(hex: "#C2410C")],   // Orange
    .simpleScore: [Color(hex: "#6B7280"), Color(hex: "#374151")], // Gray
    .multiScoreboard: [Color(hex: "#6366F1"), Color(hex: "#4338CA")], // Indigo
    .counter: [Color(hex: "#EC4899"), Color(hex: "#BE185D")],    // Pink
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
    return "开始比赛" // Equivalent to '开始比赛' from HarmonyOS
}

// Available sports to choose from for QuickStartEditSheetComponent
let availableSports: [GameType] = [
    .basketball, .football, .badminton,
    .pingpong, .tennis, .volleyball,
    .billiards, .boxing,
    .go, .xiangqi, .chess,
    .guandan, .doudizhu
]
