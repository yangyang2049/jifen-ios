import ScoreCore
import SwiftUI

struct ScoreboardKeyPointBadgeLayer: View {
    let status: KeyPointStatus?
    let gameType: ScoreCore.GameType
    let sidesSwapped: Bool
    /// nil = singles above the centre triangle; non-nil = doubles fixed at vertical centre.
    var doublesTopRow: Bool? = nil

    var body: some View {
        GeometryReader { proxy in
            if let status {
                let screenSide = TeamScreenLayout(sidesSwapped: sidesSwapped)
                    .screenSide(of: TeamScreenLayout.teamID(forEngine: status.side))
                let midX = proxy.size.width / 2
                let largeWindow = min(proxy.size.width, proxy.size.height) >= 600
                let innerGap: CGFloat = 12
                let badgeHalfWidth: CGFloat = 28
                Text(label(for: status.kind))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(Color(hex: "111111"))
                    .frame(width: 56, height: 28)
                    .background(background(for: status.kind), in: RoundedRectangle(cornerRadius: 7))
                    .position(
                        x: midX + (screenSide == .left ? -(innerGap + badgeHalfWidth) : innerGap + badgeHalfWidth),
                        y: ScoreboardServeGeometry.keyPointBadgeCenterY(
                            height: proxy.size.height,
                            doublesTopRow: usesDoublesLayout ? (doublesTopRow ?? false) : nil,
                            largeWindow: largeWindow
                        )
                    )
            }
        }
        .allowsHitTesting(false)
        .accessibilityIdentifier("scoreboard_key_point_badge")
    }

    private var usesDoublesLayout: Bool {
        switch gameType {
        case .pingpongDoubles, .badmintonDoubles, .pickleballDoubles, .foosballDoubles, .tennisDoubles:
            return true
        default:
            return false
        }
    }

    private func label(for kind: KeyPointKind) -> String {
        if kind == .match {
            return NSLocalizedString("scoreboard_key_point_match", value: "MP", comment: "Match point")
        }
        if gameType == .tennis || gameType == .tennisDoubles {
            return NSLocalizedString("scoreboard_key_point_set", value: "SP", comment: "Set point")
        }
        if gameType == .volleyball || gameType == .airVolleyball || gameType == .beachVolleyball {
            return NSLocalizedString("scoreboard_key_point_volleyball_set", value: "SP", comment: "Volleyball set point")
        }
        return NSLocalizedString("scoreboard_key_point_game", value: "GP", comment: "Game point")
    }

    private func background(for kind: KeyPointKind) -> Color {
        if kind == .set && (gameType == .tennis || gameType == .tennisDoubles) {
            return Color(hex: "FFB340")
        }
        return Color(hex: "FFD60A")
    }
}
