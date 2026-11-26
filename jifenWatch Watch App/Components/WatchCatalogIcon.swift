import SwiftUI
import UIKit

/// Watch entry-point artwork mirrors the phone catalog one-to-one so a sport
/// looks identical on both devices. Asset names never depend on UI language.
enum WatchCatalogIconAssets {
    static func game(_ gameType: WatchGameType) -> String {
        "icon_3d_" + gameKey(gameType)
    }

    static func sport(_ sport: WatchSetupSport) -> String {
        "icon_3d_" + gameKey(sport.gameType)
    }

    static func homeItem(_ item: WatchHomeItem) -> String {
        "icon_3d_" + gameKey(item.gameType)
    }

    static func tool(_ id: String) -> String {
        "icon_3d_" + id
    }

    /// Mirrors `AppCatalogIconAssets.game` on the phone. Sports that share
    /// artwork on the phone share it here as well.
    static func gameKey(_ gameType: WatchGameType) -> String {
        switch gameType {
        case .basketball, .threeBasketball, .basketballTraining:
            return "basketball"
        case .football, .football5v5:
            return "football"
        case .pingpong:
            return "pingpong"
        case .badminton:
            return "badminton"
        case .shuttlecock:
            return "shuttlecock"
        case .squash:
            return "squash"
        case .foosball:
            return "foosball"
        case .tennis:
            return "tennis"
        case .pickleball:
            return "pickleball"
        case .archery:
            return "archery"
        case .eightBall:
            return "eight_ball"
        case .nineBall:
            return "nine_ball"
        case .snooker:
            return "snooker"
        case .counter:
            return "simple_score"
        }
    }
}

/// Renders the shared phone artwork, keeping the emoji as a local fallback so
/// older builds or a stripped asset catalog still show a recognizable icon.
struct WatchCatalogIcon: View {
    let assetName: String
    let fallbackEmoji: String
    let size: CGFloat

    init(assetName: String, fallbackEmoji: String, size: CGFloat) {
        self.assetName = assetName
        self.fallbackEmoji = fallbackEmoji
        self.size = size
    }

    init(gameType: WatchGameType, size: CGFloat) {
        self.init(
            assetName: WatchCatalogIconAssets.game(gameType),
            fallbackEmoji: gameType.icon,
            size: size
        )
    }

    var body: some View {
        Group {
            if UIImage(named: assetName) != nil {
                Image(assetName)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                Text(fallbackEmoji)
                    .font(.system(size: size))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Vector court outline icon for empty states, mirroring `EmptyStateCourtIcon` on iPhone.
struct WatchEmptyStateCourtIcon: View {
    var size: CGFloat = 44
    var color: Color = WatchTheme.secondaryText.opacity(0.75)

    var body: some View {
        Image("EmptyStateCourt")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}
