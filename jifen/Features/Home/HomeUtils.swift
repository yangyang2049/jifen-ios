import SwiftUI



// MARK: - GameType Utilities (based on HomeUtils.ts)

import Foundation // For String localization potentially, or just general utilities
// Assuming GameType is part of the main 'jifen' module and thus accessible


// Universal blue gradient for all small cards
let GAME_GRADIENTS: [GameType: [Color]] = [
    .basketball: [Color(hex: "#3B82F6"), Color(hex: "#1E40AF")], // Blue
    .football: [Color(hex: "#3B82F6"), Color(hex: "#1E40AF")],   // Blue
    .badminton: [Color(hex: "#3B82F6"), Color(hex: "#1E40AF")],  // Blue
    .pingpong: [Color(hex: "#3B82F6"), Color(hex: "#1E40AF")],   // Blue
    .tennis: [Color(hex: "#3B82F6"), Color(hex: "#1E40AF")],    // Blue
    .volleyball: [Color(hex: "#3B82F6"), Color(hex: "#1E40AF")], // Blue
    .go: [Color(hex: "#3B82F6"), Color(hex: "#1E40AF")],         // Blue
    .xiangqi: [Color(hex: "#3B82F6"), Color(hex: "#1E40AF")],    // Blue
    .chess: [Color(hex: "#3B82F6"), Color(hex: "#1E40AF")],      // Blue
    .checkers: [Color(hex: "#3B82F6"), Color(hex: "#1E40AF")],   // Blue
    .boxing: [Color(hex: "#3B82F6"), Color(hex: "#1E40AF")],     // Blue
    .billiards: [Color(hex: "#3B82F6"), Color(hex: "#1E40AF")],  // Blue
    .pickleball: [Color(hex: "#3B82F6"), Color(hex: "#1E40AF")], // Blue
    .guandan: [Color(hex: "#3B82F6"), Color(hex: "#1E40AF")],    // Blue
    .doudizhu: [Color(hex: "#3B82F6"), Color(hex: "#1E40AF")],   // Blue
    .simpleScore: [Color(hex: "#3B82F6"), Color(hex: "#1E40AF")], // Blue
    .multiScoreboard: [Color(hex: "#3B82F6"), Color(hex: "#1E40AF")], // Blue
    .counter: [Color(hex: "#3B82F6"), Color(hex: "#1E40AF")],    // Blue
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

// Available sports to choose from for QuickStartEditSheetComponent
let availableSports: [GameType] = [
    .basketball, .football, .badminton,
    .pingpong, .tennis, .volleyball
]
