import ScoreCore
import SwiftUI

struct ScoreboardKeyPointBadgeLayer: View {
    let status: KeyPointStatus?
    let gameType: ScoreCore.GameType
    let sidesSwapped: Bool
    /// nil = centre triangle; true/false = doubles top/bottom triangle row.
    var doublesTopRow: Bool? = nil

    var body: some View {
        GeometryReader { proxy in
            if let status {
                let screenSide = sidesSwapped ? status.side.opposite : status.side
                let midX = proxy.size.width / 2
                let anchorY: CGFloat = {
                    guard let doublesTopRow else { return proxy.size.height / 2 }
                    return doublesTopRow ? proxy.size.height / 6 : proxy.size.height * 5 / 6
                }()
                Text(label(for: status.kind))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(Color(hex: "111111"))
                    .frame(width: 56, height: 28)
                    .background(background(for: status.kind), in: RoundedRectangle(cornerRadius: 7))
                    .position(
                        x: screenSide == .left ? midX - 40 : midX + 40,
                        y: anchorY - 42
                    )
            }
        }
        .allowsHitTesting(false)
        .accessibilityIdentifier("scoreboard_key_point_badge")
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
