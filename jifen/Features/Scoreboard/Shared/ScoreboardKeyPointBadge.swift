import ScoreCore
import SwiftUI

struct ScoreboardKeyPointBadgeLayer: View {
    let status: KeyPointStatus?
    let gameType: ScoreCore.GameType
    let sidesSwapped: Bool
    /// nil uses the singles height; non-nil aligns the badge to the active doubles player row.
    var doublesTopRow: Bool? = nil
    let serveIndicatorSize: CGFloat

    var body: some View {
        GeometryReader { proxy in
            if let status {
                let screenSide = TeamScreenLayout(sidesSwapped: sidesSwapped)
                    .screenSide(of: TeamScreenLayout.teamID(forEngine: status.side))
                let largeWindow = min(proxy.size.width, proxy.size.height) >= 600
                Text(label(for: status.kind))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(Color(hex: "111111"))
                    .frame(width: 56, height: 28)
                    .background(background(for: status.kind), in: RoundedRectangle(cornerRadius: 7))
                    .position(
                        x: ScoreboardServeGeometry.keyPointBadgeCenterX(
                            width: proxy.size.width,
                            isLeftSide: screenSide == .left
                        ),
                        y: usesDoublesLayout && doublesTopRow == nil
                            ? proxy.size.height / 2
                            : ScoreboardServeGeometry.keyPointBadgeCenterY(
                                height: proxy.size.height,
                                doublesTopRow: doublesTopRow,
                                largeWindow: largeWindow,
                                triangleSize: serveIndicatorSize
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
