import SwiftUI
import ScoreCore

/// Single scoreboard launch route shared by Home, Scoreboard and record replay.
struct ScoreboardLaunchView: View {
    let gameType: GameType
    var setupResult: SportsSetupResult?
    var initialResumeSessionId: String? = nil
    var exactScoreCoreGameType: ScoreCore.GameType? = nil
    var automaticallyShowsUsageHint = true
    var analyticsEntryPoint: AnalyticsEntryPoint = .scoreTab
    var onSetupConsumed: () -> Void = {}
    var onBack: () -> Void = {}

    @State private var analyticsContext: MatchAnalyticsContext
    @State private var usageHintCoordinator: ScoreboardUsageHintCoordinator?

    init(
        gameType: GameType,
        setupResult: SportsSetupResult? = nil,
        initialResumeSessionId: String? = nil,
        exactScoreCoreGameType: ScoreCore.GameType? = nil,
        automaticallyShowsUsageHint: Bool = true,
        analyticsEntryPoint: AnalyticsEntryPoint = .scoreTab,
        onSetupConsumed: @escaping () -> Void = {},
        onBack: @escaping () -> Void = {}
    ) {
        self.gameType = gameType
        self.setupResult = setupResult
        self.initialResumeSessionId = initialResumeSessionId
        self.exactScoreCoreGameType = exactScoreCoreGameType
        self.automaticallyShowsUsageHint = automaticallyShowsUsageHint
        self.analyticsEntryPoint = analyticsEntryPoint
        self.onSetupConsumed = onSetupConsumed
        self.onBack = onBack
        _analyticsContext = State(initialValue: MatchAnalyticsContext(
            gameType: gameType,
            setup: setupResult,
            entryPoint: analyticsEntryPoint
        ))
        let usageDescriptor = ScoreboardUsageHintDescriptor.resolve(
            gameType: gameType,
            setup: setupResult,
            exactGameType: exactScoreCoreGameType
        )
        _usageHintCoordinator = State(initialValue: usageDescriptor.map {
            ScoreboardUsageHintCoordinator(descriptor: $0)
        })
    }

    @ViewBuilder
    var body: some View {
        Group {
            switch gameType {
            case .pingpong:
                PingPongScoreboardView(onNavigationBack: onBack, initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed)
            case .badminton:
                BadmintonScoreboardView(onNavigationBack: onBack, initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed)
            case .tennis:
                TennisScoreboardView(onNavigationBack: onBack, initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed)
            case .basketball:
                BasketballScoreboardView(onNavigationBack: onBack, initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed)
            case .threeBasketball:
                BasketballScoreboardView(onNavigationBack: onBack, initialSetup: threeBasketballSetup, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed)
            case .football:
                FootballScoreboardView(onNavigationBack: onBack, initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed)
            case .volleyball:
                VolleyballScoreboardView(onNavigationBack: onBack, initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed)
            case .beachVolleyball:
                VolleyballScoreboardView(variant: .beachVolleyball, onNavigationBack: onBack, initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed)
            case .airVolleyball:
                VolleyballScoreboardView(variant: .airVolleyball, onNavigationBack: onBack, initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed)
            case .archery:
                ArcheryScoreboardView(initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
            case .boxing:
                BoxingScoreboardView(initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
            case .billiards:
                BilliardsScoreboardView(initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
            case .eightBall:
                EightBallScoreboardView(initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
            case .nineBall:
                NineBallChaseScoreboardView(initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
            case .snooker:
                SnookerReducerScoreboardView(initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
            case .pickleball:
                PickleballScoreboardView(initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
            case .guandan:
                GuandanScoreboardView(initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
            case .doudizhu:
                DoudizhuScoreboardView(initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
            case .shengji:
                ShengjiReducerScoreboardView(initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
            case .uno:
                MultiScoreboardView(gameType: .uno, defaultPlayerCount: setupResult?.playerCount ?? PreferencesManager.shared.unoPlayerCount, targetScore: setupResult?.targetScore ?? PreferencesManager.shared.unoTargetScore, initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
            case .foosball:
                FoosballScoreboardView(onNavigationBack: onBack, initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed)
            case .simpleScore, .counter:
                SimpleScoreboardView(initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
            case .multiScoreboard:
                MultiScoreboardView(gameType: .multiScoreboard, defaultPlayerCount: setupResult?.playerCount ?? PreferencesManager.shared.multiScoreboardPlayerCount, initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
            default:
                Text(NSLocalizedString("not_implemented", comment: ""))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .environment(\.scoreboardUsageHintCoordinator, usageHintCoordinator)
        .allowsHitTesting(usageHintCoordinator?.isPresented != true)
        .accessibilityHidden(usageHintCoordinator?.isPresented == true)
        .overlay {
            if let usageHintCoordinator, usageHintCoordinator.isPresented {
                ScoreboardUsageHintDialog(
                    descriptor: usageHintCoordinator.descriptor,
                    onDismiss: usageHintCoordinator.dismissAndMarkShown
                )
                .zIndex(10_000)
            }
        }
        .task {
            await Task.yield()
            if ScoreboardUsageHintAutomaticPresentationPolicy.allows(
                requested: automaticallyShowsUsageHint,
                setup: setupResult
            ) {
                usageHintCoordinator?.presentAutomaticallyIfNeeded()
            }
        }
        .onAppear { analyticsContext.trackLaunch(isResume: initialResumeSessionId != nil) }
    }

    private var threeBasketballSetup: SportsSetupResult {
        var result = setupResult ?? SportsSetupResult(team1Name: "", team2Name: "")
        result.basketballMode = "three_x_three"
        return result
    }
}
