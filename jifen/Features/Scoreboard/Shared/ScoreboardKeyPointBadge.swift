import ScoreCore
import SwiftUI

enum ScoreboardKeyPointBadgePresentation {
    static func label(kind: String, gameType: String) -> String {
        if kind == "match" {
            return NSLocalizedString("scoreboard_key_point_match", value: "MP", comment: "Match point")
        }
        if gameType == "tennis" || gameType == "tennis_doubles" {
            return NSLocalizedString("scoreboard_key_point_set", value: "SP", comment: "Set point")
        }
        if ["volleyball", "air_volleyball", "beach_volleyball"].contains(gameType) {
            return NSLocalizedString("scoreboard_key_point_volleyball_set", value: "SP", comment: "Volleyball set point")
        }
        return NSLocalizedString("scoreboard_key_point_game", value: "GP", comment: "Game point")
    }

    static func background(kind: String, gameType: String) -> Color {
        kind == "set" && (gameType == "tennis" || gameType == "tennis_doubles")
            ? Color(hex: "FFB340")
            : Color(hex: "FFD60A")
    }
}

struct ScoreboardKeyPointBadge: View {
    let kind: String
    let gameType: String
    var scale: CGFloat = 1

    var body: some View {
        Text(ScoreboardKeyPointBadgePresentation.label(kind: kind, gameType: gameType))
            .font(.system(size: 12 * scale, weight: .heavy, design: .rounded))
            .tracking(0.8 * scale)
            .foregroundStyle(Color(hex: "111111"))
            .frame(width: 56 * scale, height: 28 * scale)
            .background(
                ScoreboardKeyPointBadgePresentation.background(kind: kind, gameType: gameType),
                in: RoundedRectangle(cornerRadius: 7 * scale)
            )
    }
}

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
                let kindCode: String = switch status.kind {
                case .game: "game"
                case .set: "set"
                case .match: "match"
                }
                ScoreboardKeyPointBadge(
                    kind: kindCode,
                    gameType: gameType.rawValue
                )
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

}
