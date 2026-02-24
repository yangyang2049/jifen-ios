//
//  Theme.swift
//  jifen
//
//  App theme and colors
//

import SwiftUI

struct Theme {
    // Colors
    static let backgroundColor = Color(hex: "1a1a1a")
    static let cardBackground = Color(hex: "000000")
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let accentColor = Color(hex: "32D74B") // Original accent color

    // Additional colors derived from HarmonyOS UI
    static let primary = accentColor // Map HarmonyOS 'primary' to existing accentColor
    static let primaryDark = Color(hex: "248A3D")
    static let black = Color.black
    static let textOnPrimary = Color.white // Assuming text on primary is white
    static let transparent = Color.clear

    // HarmonyOS specific colors from the provided code
    static let homeButtonShadow = Color.black.opacity(0.2) // Approximated
    static let homePrimaryCardOrange = Color(hex: "#F97316")
    static let homeSecondaryCardGreen = Color(hex: "#30D158") // Approximated, used in HarmonyOS quickStart config
    static let homeSecondaryCardBlue = Color(hex: "#007AFF") // Custom blue for secondary card
    static let homeEditButtonGreen = Color(hex: "#30D158") // Used for save button
    static let homeCardDark = Color(hex: "1C1C1E") // Approximated from LiveActivityBanner, QuickStartEditDialog
    static let homeCardLight = Color(hex: "FFFFFF") // Approximated from LiveActivityBanner, QuickStartEditDialog
    static let homeOverlayBorder = Color.white.opacity(0.1) // Approximated
    static let homeDividerLight = Color.gray.opacity(0.2) // Approximated
    static let homeOverlayBorderLight = Color.gray.opacity(0.1) // Approximated
    static let homeShadowLight = Color.black.opacity(0.05) // Approximated
    static let homeTextDisabledDark = Color.white.opacity(0.4) // Approximated
    static let homeTextDisabledLight = Color.black.opacity(0.4) // Approximated
    static let homeOverlayWhite = Color.white // Used for text in QuickStartGrid new game button
    static let homeOverlayDark = Color.black.opacity(0.3) // Used for new game button circle plus icon
    static let homeBackgroundLight = Color(hex: "F2F2F7") // Approximated from HomeTab.ets
    static let homeDialogBackground = Color(hex: "2C2C2E") // Example dark color, adjust as needed

    static let toolWhistleRed = Color(hex: "#EF4444") // Example tool color
    static let toolRankingsIndigo = Color(hex: "#6366F1") // Example tool color
    static let toolGray = Color(hex: "#6B7280") // Example tool color
    static let surface = Color(hex: "3A3A3C") // Approximated from BentoCard default gradient

    // Spacing
    static let padding: CGFloat = 16
    static let spacing: CGFloat = 12
    
    static let xs: CGFloat = 4 // Extra small spacing
    static let sm: CGFloat = 8 // Small spacing
    static let md: CGFloat = 16 // Medium spacing
    static let lg: CGFloat = 24 // Large spacing

    // Corner Radius
    static let cornerRadius: CGFloat = 12
    static let xl: CGFloat = 22 // Extra large corner radius, specifically for ToolItem
    static let xxl: CGFloat = 24 // Extra extra large corner radius

    // Font Sizes (Approximated from HarmonyOS code, not directly mapping)
    static let fontCaption: CGFloat = 12
    static let fontBody2: CGFloat = 14
    static let fontBody1: CGFloat = 16
    static let fontH5: CGFloat = 18
    static let fontH4: CGFloat = 20
    static let fontH3: CGFloat = 24
}

extension Color {
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        let red, green, blue: Double
        switch hexSanitized.count {
        case 6: // RGB (24-bit)
            red = Double((rgb & 0xFF0000) >> 16) / 255.0
            green = Double((rgb & 0x00FF00) >> 8) / 255.0
            blue = Double(rgb & 0x0000FF) / 255.0
            self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
        case 8: // ARGB (32-bit)
            let alpha = Double((rgb & 0xFF000000) >> 24) / 255.0
            red = Double((rgb & 0x00FF0000) >> 16) / 255.0
            green = Double((rgb & 0x0000FF00) >> 8) / 255.0
            blue = Double(rgb & 0x000000FF) / 255.0
            self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
        default:
            self.init(.sRGB, red: 0, green: 0, blue: 0, opacity: 1.0)
        }
    }
}
