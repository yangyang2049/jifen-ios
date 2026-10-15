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

    /// Minimum interactive area for scoreboard controls.
    static let minimumTouchTarget: CGFloat = 44

    /// Accessibility id for the bottom-left scoreboard back / exit control.
    static let backButtonAccessibilityID = "scoreboard_back_button"

    /// Default main score base size (HOS DEFAULT_SCORE_FONT_SIZE).
    static let baseMainScoreFontSize: CGFloat = 144

    /// Side control lift from bottom (HOS translateY: -72).
    static let sideControlsBottomOffset: CGFloat = 72
}

extension View {
    /// Keeps compact scoreboard chrome visually small without shrinking its
    /// tappable area below the platform accessibility minimum.
    func scoreboardMinimumTouchTarget() -> some View {
        frame(
            minWidth: ScoreboardConstants.minimumTouchTarget,
            minHeight: ScoreboardConstants.minimumTouchTarget
        )
        .contentShape(Rectangle())
    }
}

/// Marks the scoreboard bottom-left back control for UI tests / VoiceOver.
struct ScoreboardBackButtonAccessibility: ViewModifier {
    let isBack: Bool

    func body(content: Content) -> some View {
        if isBack {
            content
                .accessibilityIdentifier(ScoreboardConstants.backButtonAccessibilityID)
                .accessibilityLabel(NSLocalizedString("back", value: "返回", comment: ""))
        } else {
            content
        }
    }
}

/// Voice status belongs to the menu; the badge never owns a separate action.
struct ScoreboardMenuVoiceStatus: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if isEnabled {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "42EE9B"))
                        .frame(width: 24, height: 24)
                        .background(Color(hex: "155E46"), in: Circle())
                        .offset(x: 4, y: -4)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityValue(NSLocalizedString(
                isEnabled ? "voice_announcement_on" : "voice_announcement_off",
                value: isEnabled ? "语音：开" : "语音：关",
                comment: ""
            ))
    }
}
