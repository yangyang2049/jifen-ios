import ScoreCore
import SwiftUI

private enum ScoreboardSetupCatalog {
    static let casualGames: Set<GameType> = [
        .multiScoreboard, .doudizhu, .uno, .guandan, .shengji, .simpleScore
    ]

    static func defaultPlayerCount(for gameType: GameType) -> Int {
        switch gameType {
        case .doudizhu: return 3
        case .uno: return PreferencesManager.shared.unoPlayerCount
        case .multiScoreboard: return PreferencesManager.shared.multiScoreboardPlayerCount
        default: return 4
        }
    }

    static func titleKey(for gameType: GameType) -> String {
        switch gameType {
        case .doudizhu: return "game_doudizhu"
        case .uno: return "game_uno"
        case .guandan: return "game_guandan"
        case .shengji: return "game_shengji"
        case .simpleScore: return "game_simple_score"
        default: return "game_multi_scoreboard"
        }
    }
}

@ViewBuilder
func scoreboardSetupDialog(
    for gameType: GameType,
    initialSetup: SportsSetupResult? = nil,
    maxDialogHeight: CGFloat,
    onConfirm: @escaping (SportsSetupResult) -> Void,
    onCancel: @escaping () -> Void
) -> some View {
    switch gameType {
    case .basketballTraining:
        ShotTrainingSetupDialogView(
            maxDialogHeight: maxDialogHeight,
            initialMode: ShotTrainingMode(rawValue: initialSetup?.basketballTrainingScoringMode ?? "") ?? .fixed1,
            allowsStartOnWatch: true,
            onConfirm: onConfirm,
            onCancel: onCancel
        )
    case .nineBall:
        NineBallSetupDialogView(
            initialSetup: initialSetup,
            maxDialogHeight: maxDialogHeight,
            onConfirm: onConfirm,
            onCancel: onCancel
        )
    default:
        let defaults = DefaultParticipantNames.resolve(for: gameType)
        if ScoreboardSetupCatalog.casualGames.contains(gameType) {
            MultiScoreSetupDialogView(
                gameType: gameType,
                defaultPlayerCount: initialSetup?.playerCount
                    ?? ScoreboardSetupCatalog.defaultPlayerCount(for: gameType),
                initialPlayerNames: initialSetup?.playerNames ?? [],
                defaultTeam1Name: initialSetup?.team1Name ?? defaults.left,
                defaultTeam2Name: initialSetup?.team2Name ?? defaults.right,
                initialTargetScore: initialSetup?.targetScore ?? PreferencesManager.shared.unoTargetScore,
                initialSetup: initialSetup,
                titleEmoji: gameType.icon,
                titleKey: ScoreboardSetupCatalog.titleKey(for: gameType),
                titleFallback: gameType.displayName,
                maxDialogHeight: maxDialogHeight,
                onConfirm: onConfirm,
                onCancel: onCancel
            )
        } else {
            SportsSetupDialogView(
                gameType: gameType,
                defaultTeam1Name: initialSetup?.team1Name ?? defaults.left,
                defaultTeam2Name: initialSetup?.team2Name ?? defaults.right,
                initialMaxSets: initialSetup?.maxSets,
                initialPointsPerSet: initialSetup?.pointsPerSet,
                initialTieBreakPoints: initialSetup?.tieBreakPoints,
                initialSetup: initialSetup,
                maxDialogHeight: maxDialogHeight,
                onConfirm: onConfirm,
                onCancel: onCancel
            )
        }
    }
}
