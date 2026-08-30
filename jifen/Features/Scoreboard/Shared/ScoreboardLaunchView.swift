import Foundation
import Observation
import SwiftUI
import ScoreCore

enum ScoreboardMatchTimePolicy {
    static func loadsSportsSetupPreference(for gameType: GameType) -> Bool {
        gameType == .pingpong || isVolleyball(gameType)
    }

    static func includesSportsSetupValue(for gameType: GameType, isSingles: Bool) -> Bool {
        (gameType == .pingpong && isSingles) || isVolleyball(gameType)
    }

    static func includesCasualSetupValue(for gameType: GameType) -> Bool {
        [.guandan, .shengji, .simpleScore].contains(gameType)
    }

    static func supportsGenericClock(
        for gameType: GameType,
        setup: SportsSetupResult?,
        exactScoreCoreGameType: ScoreCore.GameType? = nil
    ) -> Bool {
        if includesCasualSetupValue(for: gameType) || isVolleyball(gameType) {
            return true
        }
        guard gameType == .pingpong else { return false }
        if exactScoreCoreGameType == .pingpongDoubles { return false }
        return setup?.isSingles != false
    }

    static func initialVisibility(
        for gameType: GameType,
        setup: SportsSetupResult?,
        exactScoreCoreGameType: ScoreCore.GameType? = nil,
        preferences: PreferencesManager = .shared
    ) -> Bool {
        guard supportsGenericClock(
            for: gameType,
            setup: setup,
            exactScoreCoreGameType: exactScoreCoreGameType
        ) else {
            return false
        }
        return setup?.showMatchTime ?? preferences.scoreboardMatchTimeVisible(for: gameType)
    }

    static func isVolleyball(_ gameType: GameType) -> Bool {
        [.volleyball, .beachVolleyball, .airVolleyball].contains(gameType)
    }
}

@Observable
final class ScoreboardMatchClockSession {
    private(set) var startedAt: Date
    var isVisible: Bool {
        didSet {
            guard isVisible != oldValue else { return }
            visibilityDidChange?(isVisible)
        }
    }
    private var visibilityDidChange: ((Bool) -> Void)?

    init(isVisible: Bool, startedAt: Date = Date()) {
        self.isVisible = isVisible
        self.startedAt = startedAt
    }

    /// Rebinds the presentation clock to the durable match lifecycle. Resume
    /// paths pass the original start time; a new-match action supplies a fresh
    /// start time. Rebinding never fires the user-change callback.
    func bind(
        startedAt: Date,
        isVisible: Bool,
        visibilityDidChange: ((Bool) -> Void)? = nil
    ) {
        self.visibilityDidChange = nil
        self.startedAt = startedAt
        self.isVisible = isVisible
        self.visibilityDidChange = visibilityDidChange
    }

    func reset(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }

    func elapsed(at now: Date = Date()) -> TimeInterval {
        max(0, now.timeIntervalSince(startedAt))
    }

    var externalDisplayClock: ScoreboardDisplayClock {
        ScoreboardDisplayClock(
            elapsedMilliseconds: 0,
            isRunning: true,
            countsDown: false,
            anchorWallClockMilliseconds: Int64(startedAt.timeIntervalSince1970 * 1_000),
            visible: isVisible
        )
    }

    static func formatElapsed(_ elapsed: TimeInterval) -> String {
        let totalSeconds = max(0, Int(elapsed))
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct ScoreboardMatchClockSessionEnvironmentKey: EnvironmentKey {
    static let defaultValue: ScoreboardMatchClockSession? = nil
}

extension EnvironmentValues {
    var scoreboardMatchClockSession: ScoreboardMatchClockSession? {
        get { self[ScoreboardMatchClockSessionEnvironmentKey.self] }
        set { self[ScoreboardMatchClockSessionEnvironmentKey.self] = newValue }
    }
}

private struct ScoreboardMatchTimeDisplay: View {
    let session: ScoreboardMatchClockSession

    var body: some View {
        TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
            Text(ScoreboardMatchClockSession.formatElapsed(session.elapsed(at: context.date)))
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.32), in: Capsule())
        }
        .accessibilityIdentifier("scoreboard_match_time")
        .allowsHitTesting(false)
    }
}

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
    @State private var manuallyPresentedUsageHint = false
    @State private var matchClockSession: ScoreboardMatchClockSession?
    @State private var matchClockOutputOwnerID = "scoreboard-match-clock-\(UUID().uuidString)"

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
        if ScoreboardMatchTimePolicy.supportsGenericClock(
            for: gameType,
            setup: setupResult,
            exactScoreCoreGameType: exactScoreCoreGameType
        ) {
            _matchClockSession = State(initialValue: ScoreboardMatchClockSession(
                isVisible: ScoreboardMatchTimePolicy.initialVisibility(
                    for: gameType,
                    setup: setupResult,
                    exactScoreCoreGameType: exactScoreCoreGameType
                )
            ))
        } else {
            _matchClockSession = State(initialValue: nil)
        }
    }

    @ViewBuilder
    var body: some View {
        Group {
            switch gameType {
            case .pingpong:
                PingPongScoreboardView(onNavigationBack: onBack, initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed, usageHintCoordinatorOverride: usageHintCoordinator)
            case .badminton:
                BadmintonScoreboardView(onNavigationBack: onBack, initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed, usageHintCoordinatorOverride: usageHintCoordinator)
            case .shuttlecock:
                RallyScoreboardView(
                    leftName: setupResult?.team1Name ?? DefaultParticipantNames.resolve(for: .shuttlecock).left,
                    rightName: setupResult?.team2Name ?? DefaultParticipantNames.resolve(for: .shuttlecock).right,
                    gameType: .shuttlecock,
                    rules: setupResult?.shuttlecockRules ?? .shuttlecock(),
                    participants: rallyParticipants(
                        from: setupResult,
                        includeDoubles: setupResult?.competitionFormat.map {
                            [CompetitionFormat.doubles, .mixedDoubles].contains($0)
                        } ?? false
                    ),
                    competitionFormat: setupResult?.competitionFormat,
                    competitionPlayerNames: shuttlecockCompetitionPlayerNames(from: setupResult),
                    openingServer: setupResult?.servingSide == MatchSide.right.rawValue ? .right : .left,
                    voiceAnnouncementEnabled: setupResult?.voiceAnnouncement == true,
                    initialResumeSessionId: initialResumeSessionId,
                    onNavigationBack: onBack,
                    usageHintCoordinatorOverride: usageHintCoordinator
                )
            case .squash:
                RallyScoreboardView(
                    leftName: setupResult?.team1Name ?? DefaultParticipantNames.resolve(for: .squash).left,
                    rightName: setupResult?.team2Name ?? DefaultParticipantNames.resolve(for: .squash).right,
                    gameType: .squash,
                    rules: setupResult?.squashRules ?? .squash(),
                    participants: nil,
                    openingServer: setupResult?.servingSide == MatchSide.right.rawValue ? .right : .left,
                    voiceAnnouncementEnabled: setupResult?.voiceAnnouncement == true,
                    initialResumeSessionId: initialResumeSessionId,
                    onNavigationBack: onBack,
                    usageHintCoordinatorOverride: usageHintCoordinator
                )
            case .tennis:
                TennisScoreboardView(onNavigationBack: onBack, initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed, usageHintCoordinatorOverride: usageHintCoordinator)
            case .softTennis:
                TennisScoreboardView(
                    onNavigationBack: onBack,
                    initialSetup: setupResult,
                    initialResumeSessionId: initialResumeSessionId,
                    onSetupConsumed: onSetupConsumed,
                    forcedGameType: .softTennis,
                    usageHintCoordinatorOverride: usageHintCoordinator
                )
            case .padel:
                TennisScoreboardView(
                    onNavigationBack: onBack,
                    initialSetup: setupResult,
                    initialResumeSessionId: initialResumeSessionId,
                    onSetupConsumed: onSetupConsumed,
                    forcedGameType: .padel,
                    usageHintCoordinatorOverride: usageHintCoordinator
                )
            case .basketball:
                BasketballScoreboardView(onNavigationBack: onBack, initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed)
            case .threeBasketball:
                BasketballScoreboardView(onNavigationBack: onBack, initialSetup: threeBasketballSetup, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed)
            case .football:
                FootballScoreboardView(onNavigationBack: onBack, initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed)
            case .football5v5:
                FootballScoreboardView(onNavigationBack: onBack, initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed, isFiveAside: true)
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
                SnookerScoreboardView(initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
            case .pickleball:
                PickleballScoreboardView(initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack, usageHintCoordinatorOverride: usageHintCoordinator)
            case .guandan:
                GuandanScoreboardView(initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
            case .doudizhu:
                DoudizhuScoreboardView(initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
            case .shengji:
                ShengjiScoreboardView(initialSetup: setupResult, initialResumeSessionId: initialResumeSessionId, onSetupConsumed: onSetupConsumed, onNavigationBack: onBack)
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
        .environment(\.scoreboardUsageHintPresenter, {
            manuallyPresentedUsageHint = true
        })
        .environment(\.scoreboardMatchClockSession, matchClockSession)
        .overlay(alignment: .top) {
            if let matchClockSession, matchClockSession.isVisible {
                ScoreboardMatchTimeDisplay(session: matchClockSession)
                    .padding(.top, 12)
                    .zIndex(5_000)
            }
        }
        .allowsHitTesting(!usageHintIsPresented)
        .accessibilityHidden(usageHintIsPresented)
        .overlay {
            if let usageHintCoordinator, usageHintIsPresented {
                ScoreboardUsageHintDialog(
                    descriptor: usageHintCoordinator.descriptor,
                    onDismiss: dismissUsageHint
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
        .onAppear {
            analyticsContext.trackLaunch(isResume: initialResumeSessionId != nil)
            registerMatchClockOutput()
        }
        .onDisappear {
            LocalScoreboardSyncCoordinator.shared.unregisterGenericMatchClock(
                ownerID: matchClockOutputOwnerID
            )
        }
    }

    private var usageHintIsPresented: Bool {
        manuallyPresentedUsageHint || usageHintCoordinator?.isPresented == true
    }

    private func dismissUsageHint() {
        usageHintCoordinator?.dismissAndMarkShown()
        manuallyPresentedUsageHint = false
    }

    private func registerMatchClockOutput() {
        guard let matchClockSession else { return }
        LocalScoreboardSyncCoordinator.shared.registerGenericMatchClock(
            ownerID: matchClockOutputOwnerID
        ) { [weak matchClockSession] in
            matchClockSession?.externalDisplayClock
        }
    }

    private var threeBasketballSetup: SportsSetupResult {
        var result = setupResult ?? SportsSetupResult(team1Name: "", team2Name: "")
        result.basketballMode = "three_x_three"
        return result
    }

    private func rallyParticipants(from setup: SportsSetupResult?, includeDoubles: Bool) -> [SessionParticipant]? {
        guard includeDoubles, let setup else { return nil }
        return [
            .init(id: "left-top", name: setup.team1Player1Name ?? setup.team1Name, role: "player"),
            .init(id: "right-top", name: setup.team2Player1Name ?? setup.team2Name, role: "player"),
            .init(id: "left-bottom", name: setup.team1Player2Name ?? setup.team1Name, role: "player"),
            .init(id: "right-bottom", name: setup.team2Player2Name ?? setup.team2Name, role: "player")
        ]
    }

    private func shuttlecockCompetitionPlayerNames(from setup: SportsSetupResult?) -> [String]? {
        guard let setup, setup.competitionFormat == .team else { return nil }
        return [
            setup.team1Player1Name,
            setup.team1Player2Name,
            setup.team1Player3Name,
            setup.team2Player1Name,
            setup.team2Player2Name,
            setup.team2Player3Name
        ].map { $0?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    }
}
