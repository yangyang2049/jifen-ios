import SwiftUI
import ScoreCore

/// Single scoreboard launch route shared by Home, Scoreboard and record replay.
struct ScoreboardLaunchView: View {
    let gameType: GameType
    var setupResult: SportsSetupResult?
    var initialRecordId: String? = nil
    var onSetupConsumed: () -> Void = {}
    var onBack: () -> Void = {}

    @ViewBuilder
    var body: some View {
        switch gameType {
        case .pingpong:
            PingPongScoreboardView(onNavigationBack: onBack, initialSetup: setupResult, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed)
        case .badminton:
            BadmintonScoreboardView(onNavigationBack: onBack, initialSetup: setupResult, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed)
        case .tennis:
            TennisScoreboardView(onNavigationBack: onBack, initialSetup: setupResult, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed)
        case .basketball:
            BasketballScoreboardView(onNavigationBack: onBack, initialSetup: setupResult, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed)
        case .threeBasketball:
            BasketballScoreboardView(onNavigationBack: onBack, initialSetup: threeBasketballSetup, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed)
        case .football:
            FootballScoreboardView(onNavigationBack: onBack, initialSetup: setupResult, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed)
        case .volleyball:
            VolleyballScoreboardView(onNavigationBack: onBack, initialSetup: setupResult, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed)
        case .beachVolleyball:
            VolleyballScoreboardView(variant: .beachVolleyball, onNavigationBack: onBack, initialSetup: setupResult, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed)
        case .airVolleyball:
            VolleyballScoreboardView(variant: .airVolleyball, onNavigationBack: onBack, initialSetup: setupResult, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed)
        case .archery:
            ArcheryScoreboardView(initialSetup: setupResult, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
        case .boxing:
            BoxingScoreboardView(initialSetup: setupResult, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
        case .billiards:
            BilliardsScoreboardView(initialSetup: setupResult, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
        case .eightBall:
            EightBallScoreboardView(initialSetup: setupResult, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
        case .nineBall:
            NineBallChaseScoreboardView(initialSetup: setupResult, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
        case .snooker:
            SnookerReducerScoreboardView(initialSetup: setupResult, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
        case .pickleball:
            PickleballScoreboardView(initialSetup: setupResult, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
        case .guandan:
            GuandanScoreboardView(initialSetup: setupResult, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
        case .doudizhu:
            DoudizhuScoreboardView(initialSetup: setupResult, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
        case .shengji:
            ShengjiReducerScoreboardView(initialSetup: setupResult, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
        case .uno:
            MultiScoreboardView(gameType: .uno, defaultPlayerCount: setupResult?.playerCount ?? PreferencesManager.shared.unoPlayerCount, targetScore: setupResult?.targetScore ?? PreferencesManager.shared.unoTargetScore, initialSetup: setupResult, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
        case .foosball:
            FoosballScoreboardView(onNavigationBack: onBack, initialSetup: setupResult, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed)
        case .simpleScore, .counter:
            SimpleScoreboardView(initialSetup: setupResult, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
        case .multiScoreboard:
            MultiScoreboardView(gameType: .multiScoreboard, defaultPlayerCount: setupResult?.playerCount ?? PreferencesManager.shared.multiScoreboardPlayerCount, initialSetup: setupResult, initialRecordId: initialRecordId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
        default:
            Text(NSLocalizedString("not_implemented", comment: ""))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var threeBasketballSetup: SportsSetupResult {
        var result = setupResult ?? SportsSetupResult(team1Name: "", team2Name: "")
        result.basketballMode = "three_x_three"
        return result
    }
}
