import SwiftUI
import UIKit

/// Shared artwork for game and tool entry points; identifiers never depend on UI language.
enum AppCatalogIconAssets {
    nonisolated static func game(_ gameType: GameType) -> String {
        let key: String
        switch gameType {
        case .pingpong: key = "pingpong"
        case .badminton: key = "badminton"
        case .shuttlecock: key = "shuttlecock"
        case .squash: key = "squash"
        case .tennis, .softTennis: key = "tennis"
        case .padel: key = "padel"
        case .basketball, .basketballTraining, .threeBasketball: key = "basketball"
        case .football, .football5v5: key = "football"
        case .volleyball, .beachVolleyball, .airVolleyball: key = "volleyball"
        case .boxing: key = "boxing"
        case .billiards, .eightBall: key = "eight_ball"
        case .nineBall: key = "nine_ball"
        case .snooker: key = "snooker"
        case .pickleball: key = "pickleball"
        case .archery: key = "archery"
        case .guandan, .doudizhu, .shengji: key = "playing_cards"
        case .uno: key = "uno"
        case .foosball: key = "foosball"
        case .simpleScore: key = "simple_score"
        case .multiScoreboard: key = "multi_scoreboard"
        case .counter: key = "simple_score"
        case .stopwatch: key = "stopwatch"
        case .go: key = "go"
        case .xiangqi: key = "xiangqi"
        case .chess: key = "chess"
        case .checkers: key = "checkers"
        }
        return "icon_3d_" + key
    }

    static func timer(_ destination: TimerDestination) -> String {
        if let gameType = destination.mappedGameType {
            return game(gameType)
        }
        return "icon_3d_" + destination.rawValue
    }

    nonisolated static func tool(_ id: String) -> String {
        "icon_3d_" + id
    }
}

/// Shared artwork keeps a stable layout footprint; missing assets use a local court icon.
struct AppCatalogIcon: View {
    let assetName: String
    let fallbackEmoji: String
    let size: CGFloat
    let artworkSize: CGFloat

    init(gameType: GameType, fallbackEmoji: String? = nil, size: CGFloat, artworkSize: CGFloat? = nil) {
        assetName = AppCatalogIconAssets.game(gameType)
        self.fallbackEmoji = fallbackEmoji ?? gameType.icon
        self.size = size
        self.artworkSize = artworkSize ?? size
    }

    init(timer: TimerDestination, size: CGFloat, artworkSize: CGFloat? = nil) {
        assetName = AppCatalogIconAssets.timer(timer)
        fallbackEmoji = timer.emoji
        self.size = size
        self.artworkSize = artworkSize ?? size
    }

    init(bookingSport: BookingSportType, size: CGFloat) {
        assetName = bookingSport.gameType.map(AppCatalogIconAssets.game) ?? ""
        fallbackEmoji = bookingSport.icon
        self.size = size
        artworkSize = size
    }

    init(tool: ToolItem, size: CGFloat, artworkSize: CGFloat? = nil) {
        assetName = AppCatalogIconAssets.tool(tool.id)
        fallbackEmoji = tool.emoji
        self.size = size
        self.artworkSize = artworkSize ?? size
    }

    var body: some View {
        Group {
            if let image = UIImage(named: assetName) {
                Image(uiImage: image).renderingMode(.original).resizable().scaledToFit()
                    .frame(width: artworkSize, height: artworkSize)
                    .frame(width: size, height: size)
            } else {
                EmptyStateCourtIcon(size: size)
            }
        }.accessibilityHidden(true)
    }
}
