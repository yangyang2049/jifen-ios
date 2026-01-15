import SwiftUI

struct WatchTheme {
    static let background = Color(hex: 0x000000)
    static let card = Color(hex: 0x2C2C2E)
    static let primaryText = Color(hex: 0xFFFFFF)
    static let secondaryText = Color(hex: 0x8E8E93)
    static let accent = Color(hex: 0x32D74B)
    static let listItemBackground = Color(hex: 0x222222)
    static let overlayCard = Color(hex: 0x1C1C1E)
    static let timerAccent = Color(hex: 0x39FF14)
    static let successGreen = Color(hex: 0x4CAF50)
    static let warningOrange = Color(hex: 0xFF7043)
    static let dangerRed = Color(hex: 0xFF3B30)
}

struct WatchMetrics {
    static let pagePadding = EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
    static let navBarHeight: CGFloat = 32
    static let indicatorSpacing: CGFloat = 5
    static let activeIndicator: CGFloat = 6
    static let inactiveIndicator: CGFloat = 4
    static let cardRadius: CGFloat = 12
    static let pillRadius: CGFloat = 30
    static let pillHeight: CGFloat = 60
    static let recordPillHeight: CGFloat = 72
}

struct WatchAnimations {
    static let coinFlip: Double = 2.0
    static let delayStart: Double = 0.2
    static let fingerFeedback: Double = 0.18
    static let swapChipFade: Double = 0.22
}

struct WatchTiming {
    static let longPressThreshold: Double = 0.5
    static let hintDelay: Double = 1.2
    static let undoCountdown: Double = 5.0
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
