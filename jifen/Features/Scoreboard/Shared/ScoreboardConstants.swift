//
//  ScoreboardConstants.swift
//  jifen
//
//  Scoreboard UI constants
//

import SwiftUI

struct ScoreboardConstants {
    /// Distance from screen edges (HOS chrome inset ~20vp).
    static let buttonPadding: CGFloat = 20

    static let buttonSize: CGFloat = 48

    static let buttonIconSize: CGFloat = 20

    /// Default main score base size (HOS DEFAULT_SCORE_FONT_SIZE).
    static let baseMainScoreFontSize: CGFloat = 144

    /// Phone / tablet team name sizes (HOS template defaults).
    static let teamNameFontSizePhone: CGFloat = 28
    static let teamNameFontSizePad: CGFloat = 36

    /// Side control lift from bottom (HOS translateY: -72).
    static let sideControlsBottomOffset: CGFloat = 72
}

