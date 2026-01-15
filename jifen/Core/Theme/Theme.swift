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
    static let accentColor = Color(hex: "32D74B")
    
    // Spacing
    static let padding: CGFloat = 16
    static let spacing: CGFloat = 12
    static let cornerRadius: CGFloat = 12
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

