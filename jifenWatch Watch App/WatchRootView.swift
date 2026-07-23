import LinkCore
import SwiftUI
import ScoreCore
import WatchKit

struct WatchRootView: View {
    @Environment(WatchLinkService.self) private var linkService
    @State private var scoreboardRoute: WatchScoreboardRoute? = nil
    @State private var linkedSetup: LinkedScoreboardSetup?
    @State private var linkedSessionId: UUID?
    @State private var confirmDeadline: Date?

    private static let confirmTimeoutSeconds: TimeInterval = 20

    var body: some View {
        NavigationStack {
            ZStack {
                WatchTheme.background.ignoresSafeArea()
                WatchTabView(scoreboardRoute: localScoreboardRoute)
            }
            .navigationDestination(item: $scoreboardRoute) { route in
                destinationView(for: route)
            }
        }
        .accentColor(WatchTheme.accent)
        .overlay {
            if linkService.pendingConfirmRequest != nil {
                linkConfirmOverlay
            }
        }
        .onChange(of: linkService.pendingConfirmRequest) { _, request in
            if request != nil {
                confirmDeadline = Date().addingTimeInterval(Self.confirmTimeoutSeconds)
                WKInterfaceDevice.current().play(.notification)
            } else {
                confirmDeadline = nil
            }
        }
        .onChange(of: linkService.acceptedSetup) { _, request in
            guard let request, let route = WatchScoreboardRoute(linkedSetup: request.setup) else { return }
            linkedSetup = request.setup
            linkedSessionId = request.sessionId
            scoreboardRoute = route
            linkService.clearAcceptedSetup()
        }
        .onChange(of: linkService.controlRole) { _, role in
            if role == nil, linkedSessionId != nil {
                // Phone left — return home if still on linked board.
                linkedSetup = nil
                linkedSessionId = nil
                scoreboardRoute = nil
            }
        }
    }

    private var linkConfirmOverlay: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let remaining = remainingConfirmSeconds(at: context.date)
            let progress = remaining / Self.confirmTimeoutSeconds

            ZStack {
                WatchTheme.background.ignoresSafeArea()

                // Rectangular timeout ring hugging the watch screen edges
                // (Harmony uses a circle for round watches; Apple Watch is a rounded square).
                GeometryReader { proxy in
                    let lineWidth: CGFloat = 5
                    let ringInset = lineWidth / 2 + 3
                    let cornerRadius = min(proxy.size.width, proxy.size.height) * 0.28
                    let ring = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .inset(by: ringInset)
                    let clampedProgress = max(0, min(1, progress))
                    let trimStart = 0.25
                    let trimEnd = trimStart + clampedProgress
                    let progressStroke = StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )

                    ZStack {
                        ring
                            .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
                        ring
                            .trim(from: trimStart, to: min(1, trimEnd))
                            .stroke(
                                WatchTheme.accent.opacity(0.82),
                                style: progressStroke
                            )

                        if trimEnd > 1 {
                            ring
                                .trim(from: 0, to: trimEnd - 1)
                                .stroke(
                                    WatchTheme.accent.opacity(0.82),
                                    style: progressStroke
                                )
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .animation(.linear(duration: 0.1), value: progress)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Text(NSLocalizedString(
                            "linked_score_phone_started_scoreboard",
                            value: "手机已发起计分",
                            comment: ""
                        ))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WatchTheme.secondaryText)
                        .multilineTextAlignment(.center)

                        Text(confirmSportTitle)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(WatchTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 8) {
                        HStack(spacing: 3) {
                            confirmNameColumn(
                                name: confirmLeftName,
                                accent: Color(hex: 0xFF453A).opacity(0.72)
                            )
                            Text("vs")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(WatchTheme.secondaryText)
                                .frame(width: 24)
                            confirmNameColumn(
                                name: confirmRightName,
                                accent: Color(hex: 0x0A84FF).opacity(0.72)
                            )
                        }

                        if let rules = confirmRulesText {
                            Text(rules)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(WatchTheme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.top, 8)

                    Spacer(minLength: 8)

                    HStack(spacing: 22) {
                        Button {
                            linkService.rejectPendingSetup()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(WatchTheme.primaryText)
                                .frame(width: 50, height: 50)
                                .background(WatchTheme.listItemBackground)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(NSLocalizedString("linked_score_reject", value: "拒绝", comment: ""))

                        Button {
                            linkService.acceptPendingSetup()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 50, height: 50)
                                .background(WatchTheme.accent)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(NSLocalizedString("linked_score_accept", value: "接受", comment: ""))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 22)
            }
            .onChange(of: remaining) { _, value in
                if value <= 0, linkService.pendingConfirmRequest != nil {
                    linkService.rejectPendingSetup()
                }
            }
        }
    }

    private func remainingConfirmSeconds(at date: Date) -> TimeInterval {
        guard let confirmDeadline else { return Self.confirmTimeoutSeconds }
        return max(0, confirmDeadline.timeIntervalSince(date))
    }

    private var confirmSportTitle: String {
        guard let gameType = linkService.pendingConfirmRequest?.setup.gameType else {
            return NSLocalizedString("linked_score_confirm_title", value: "手机请求联动计分", comment: "")
        }
        return LinkedSetupConfirmCopy.sportTitle(for: gameType)
    }

    private var confirmLeftName: String {
        LinkedSetupConfirmCopy.leftName(from: linkService.pendingConfirmRequest?.setup)
    }

    private var confirmRightName: String {
        LinkedSetupConfirmCopy.rightName(from: linkService.pendingConfirmRequest?.setup)
    }

    private var confirmRulesText: String? {
        LinkedSetupConfirmCopy.rulesText(from: linkService.pendingConfirmRequest?.setup)
    }

    private func confirmNameColumn(name: String, accent: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: 3, height: 30)
            Text(name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WatchTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func destinationView(for route: WatchScoreboardRoute) -> some View {
        if case .setup(let sport, let playerCount) = route {
            WatchSportsSetupView(sport: sport, playerCount: playerCount) { config in
                scoreboardRoute = .configured(config)
            }
        } else {
            scoreDestination(for: route)
                .ignoresSafeArea()
                .navigationBarBackButtonHidden(true)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func scoreDestination(for route: WatchScoreboardRoute) -> some View {
        switch route {
            case .setup:
                EmptyView()
            case .configured(let config):
                configuredDestination(config)
            case .pingpong(let maxSets):
                WatchPingPongScoreView(
                    maxSets: maxSets,
                    initialState: rallyInitialState(for: route),
                    linkedSessionId: linkedSessionId(for: route)
                )
            case .badminton(let maxSets):
                WatchBadmintonScoreView(
                    maxSets: maxSets,
                    initialState: rallyInitialState(for: route),
                    linkedSessionId: linkedSessionId(for: route)
                )
            case .tennis(let maxSets):
                WatchTennisScoreView(
                    maxSets: maxSets,
                    initialState: tennisInitialState(for: route),
                    linkedSessionId: linkedSessionId(for: route)
                )
            case .pickleball(let maxSets):
                WatchPickleballScoreView(
                    maxSets: maxSets,
                    initialState: rallyInitialState(for: route),
                    linkedSessionId: linkedSessionId(for: route)
                )
            case .archery:
                WatchArcheryScoreView(
                    initialState: archeryInitialState(),
                    linkedSessionId: linkedSessionId
                )
            case .basketball(let threeXThree):
                WatchBasketballScoreView(
                    gameMode: threeXThree ? .threeXThree : .fiveVFive,
                    initialState: basketballInitialState(for: route),
                    linkedSessionId: linkedSessionId(for: route)
                )
            case .basketballTraining(let mode):
                WatchBasketballTrainingView(mode: mode)
            case .eightBall:
                WatchEightBallScoreView(
                    initialState: eightBallInitialState(),
                    linkedSessionId: linkedSessionId
                )
            case .nineBall:
                WatchNineBallScoreView(
                    initialState: nineBallInitialState(),
                    linkedSessionId: linkedSessionId
                )
            case .snooker:
                WatchSnookerScoreView(
                    initialState: snookerInitialState(),
                    linkedSessionId: linkedSessionId
                )
            case .pingpongDoubles(let maxSets):
                WatchPingPongScoreView(
                    maxSets: maxSets,
                    initialState: rallyInitialState(for: .pingpong(maxSets: maxSets)),
                    linkedSessionId: linkedSessionId,
                    doublesGameType: .pingpongDoubles
                )
            case .badmintonDoubles(let maxSets):
                WatchBadmintonScoreView(
                    maxSets: maxSets,
                    initialState: rallyInitialState(for: .badminton(maxSets: maxSets)),
                    linkedSessionId: linkedSessionId,
                    doublesGameType: .badmintonDoubles
                )
            case .tennisDoubles(let maxSets):
                WatchTennisScoreView(
                    maxSets: maxSets,
                    initialState: tennisInitialState(for: .tennis(maxSets: maxSets)),
                    linkedSessionId: linkedSessionId,
                    isDoubles: true
                )
            case .pickleballDoubles(let maxSets):
                WatchPickleballScoreView(
                    maxSets: maxSets,
                    initialState: rallyInitialState(for: .pickleball(maxSets: maxSets)),
                    linkedSessionId: linkedSessionId,
                    doublesGameType: .pickleballDoubles
                )
        }
    }

    @ViewBuilder
    private func configuredDestination(_ config: WatchScoreboardLaunchConfig) -> some View {
        switch config.sport {
        case .pingpong, .pingpongDoubles:
            WatchPingPongScoreView(
                maxSets: config.maxSets,
                initialState: WatchSetupPayloadMapper.rallyState(for: config),
                doublesGameType: config.sport.isDoubles ? .pingpongDoubles : nil
            )
        case .badminton, .badmintonDoubles:
            WatchBadmintonScoreView(
                maxSets: config.maxSets,
                initialState: WatchSetupPayloadMapper.rallyState(for: config),
                doublesGameType: config.sport.isDoubles ? .badmintonDoubles : nil
            )
        case .tennis, .tennisDoubles:
            WatchTennisScoreView(
                maxSets: config.maxSets,
                initialState: WatchSetupPayloadMapper.tennisState(for: config),
                isDoubles: config.sport.isDoubles
            )
        case .pickleball, .pickleballDoubles:
            WatchPickleballScoreView(
                maxSets: config.maxSets,
                initialState: WatchSetupPayloadMapper.rallyState(for: config),
                doublesGameType: config.sport.isDoubles ? .pickleballDoubles : nil
            )
        case .archery:
            WatchArcheryScoreView(initialState: WatchSetupPayloadMapper.archeryState(for: config))
        case .eightBall:
            let names = WatchSetupPayloadMapper.twoSideNames(for: config)
            WatchEightBallScoreView(
                initialState: WatchSetupPayloadMapper.eightBallState(for: config),
                leftName: names.left,
                rightName: names.right
            )
        case .nineBall:
            WatchNineBallScoreView(initialState: WatchSetupPayloadMapper.nineBallState(for: config))
        case .snooker:
            let names = WatchSetupPayloadMapper.twoSideNames(for: config)
            WatchSnookerScoreView(
                initialState: WatchSetupPayloadMapper.snookerState(for: config),
                leftName: names.left,
                rightName: names.right
            )
        }
    }

    private var localScoreboardRoute: Binding<WatchScoreboardRoute?> {
        Binding(
            get: { scoreboardRoute },
            set: { route in
                if linkedSessionId != nil {
                    linkService.leaveSession()
                }
                linkedSetup = nil
                linkedSessionId = nil
                scoreboardRoute = route
            }
        )
    }

    private func basketballInitialState(for route: WatchScoreboardRoute) -> BasketballMatchState? {
        guard case .basketball(let threeXThree) = route,
              let linkedSetup,
              case .basketball(let state)? = linkedSetup.initialSnapshot else { return nil }
        switch (threeXThree, state.gameMode) {
        case (true, .threeXThree), (false, .fiveVFive):
            return state
        default:
            return nil
        }
    }

    private func rallyInitialState(for route: WatchScoreboardRoute) -> RallyMatchState? {
        guard let linkedSetup,
              case .rally(let state)? = linkedSetup.initialSnapshot else { return nil }
        switch (route, linkedSetup.gameType) {
        case (.pingpong(_), .pingpong), (.pingpong(_), .pingpongDoubles),
             (.pingpongDoubles(_), .pingpongDoubles),
             (.badminton(_), .badminton), (.badminton(_), .badmintonDoubles),
             (.badmintonDoubles(_), .badmintonDoubles),
             (.pickleball(_), .pickleball), (.pickleball(_), .pickleballDoubles),
             (.pickleballDoubles(_), .pickleballDoubles):
            return state
        default:
            return nil
        }
    }

    private func tennisInitialState(for route: WatchScoreboardRoute) -> TennisMatchState? {
        guard let linkedSetup,
              case .tennis(let state)? = linkedSetup.initialSnapshot else { return nil }
        switch (route, linkedSetup.gameType) {
        case (.tennis(_), .tennis), (.tennis(_), .tennisDoubles),
             (.tennisDoubles(_), .tennisDoubles):
            return state
        default:
            return nil
        }
    }

    private func archeryInitialState() -> LinkedArcheryState? {
        guard let linkedSetup, case .archery(let state)? = linkedSetup.initialSnapshot else { return nil }
        return state
    }

    private func eightBallInitialState() -> EightBallState? {
        guard let linkedSetup, case .eightBall(let state)? = linkedSetup.initialSnapshot else { return nil }
        return state
    }

    private func nineBallInitialState() -> NineBallChaseState? {
        guard let linkedSetup, case .nineBall(let state)? = linkedSetup.initialSnapshot else { return nil }
        return state
    }

    private func snookerInitialState() -> SnookerState? {
        guard let linkedSetup, case .snooker(let state)? = linkedSetup.initialSnapshot else { return nil }
        return state
    }

    private func linkedSessionId(for route: WatchScoreboardRoute) -> UUID? {
        guard basketballInitialState(for: route) != nil
                || rallyInitialState(for: route) != nil
                || tennisInitialState(for: route) != nil else {
            return linkedSessionId
        }
        return linkedSessionId
    }
}

private enum LinkedSetupConfirmCopy {
    static func sportTitle(for gameType: GameType) -> String {
        switch gameType {
        case .badminton:
            return NSLocalizedString("linked_score_sport_badminton", value: "🏸 羽毛球单打", comment: "")
        case .badmintonDoubles:
            return NSLocalizedString("linked_score_sport_badminton_doubles", value: "🏸 羽毛球双打", comment: "")
        case .pingpong:
            return NSLocalizedString("linked_score_sport_pingpong", value: "🏓 乒乓球单打", comment: "")
        case .pingpongDoubles:
            return NSLocalizedString("linked_score_sport_pingpong_doubles", value: "🏓 乒乓球双打", comment: "")
        case .tennis:
            return NSLocalizedString("linked_score_sport_tennis", value: "🎾 网球单打", comment: "")
        case .tennisDoubles:
            return NSLocalizedString("linked_score_sport_tennis_doubles", value: "🎾 网球双打", comment: "")
        case .pickleball:
            return NSLocalizedString("linked_score_sport_pickleball", value: "🥒 匹克球单打", comment: "")
        case .pickleballDoubles:
            return NSLocalizedString("linked_score_sport_pickleball_doubles", value: "🥒 匹克球双打", comment: "")
        case .basketball:
            return NSLocalizedString("linked_score_sport_basketball", value: "🏀 篮球", comment: "")
        case .threeBasketball:
            return NSLocalizedString("linked_score_sport_three_basketball", value: "🏀 三人篮球", comment: "")
        case .archeryDual:
            return NSLocalizedString("linked_score_sport_archery", value: "🏹 射箭", comment: "")
        case .eightBall:
            return NSLocalizedString("linked_score_sport_eight_ball", value: "🎱 黑八", comment: "")
        case .nineBall:
            return NSLocalizedString("linked_score_sport_nine_ball", value: "🎱 追分", comment: "")
        case .snooker:
            return NSLocalizedString("linked_score_sport_snooker", value: "🎱 斯诺克", comment: "")
        default:
            return gameType.rawValue
        }
    }

    static func leftName(from setup: LinkedScoreboardSetup?) -> String {
        guard let setup else {
            return NSLocalizedString("watch_team_red", value: "红方", comment: "")
        }
        switch setup.initialSnapshot {
        case .rally(let state):
            if let names = state.doubles?.playerNames, names.count >= 4,
               [.pingpongDoubles, .badmintonDoubles, .pickleballDoubles].contains(setup.gameType) {
                return doublesPair(names[0], names[2], fallback: state.leftName)
            }
            return state.leftName
        case .tennis(let state):
            return state.doublesTeamDisplayName(for: .left)
        case .basketball(let state):
            return state.leftName
        case .archery(let state):
            return state.leftName
        case .nineBall(let state):
            if state.playerCount <= 2 {
                return state.resolvedName(
                    at: 0,
                    fallback: NSLocalizedString("watch_team_red", value: "红方", comment: "")
                )
            }
            return (0..<state.playerCount)
                .map { state.resolvedName(at: $0, fallback: "P\($0 + 1)") }
                .joined(separator: " · ")
        case .eightBall, .snooker, .none:
            return NSLocalizedString("watch_team_red", value: "红方", comment: "")
        }
    }

    static func rightName(from setup: LinkedScoreboardSetup?) -> String {
        guard let setup else {
            return NSLocalizedString("watch_team_blue", value: "蓝方", comment: "")
        }
        switch setup.initialSnapshot {
        case .rally(let state):
            if let names = state.doubles?.playerNames, names.count >= 4,
               [.pingpongDoubles, .badmintonDoubles, .pickleballDoubles].contains(setup.gameType) {
                return doublesPair(names[1], names[3], fallback: state.rightName)
            }
            return state.rightName
        case .tennis(let state):
            return state.doublesTeamDisplayName(for: .right)
        case .basketball(let state):
            return state.rightName
        case .archery(let state):
            return state.rightName
        case .nineBall(let state):
            if state.playerCount <= 2 {
                return state.resolvedName(
                    at: 1,
                    fallback: NSLocalizedString("watch_team_blue", value: "蓝方", comment: "")
                )
            }
            return String(
                format: NSLocalizedString("watch_nine_ball_players_format", value: "追分 · %d人", comment: ""),
                state.playerCount
            )
        case .eightBall, .snooker, .none:
            return NSLocalizedString("watch_team_blue", value: "蓝方", comment: "")
        }
    }

    private static func doublesPair(_ first: String, _ second: String, fallback: String) -> String {
        let a = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = second.trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty && !b.isEmpty { return "\(a) / \(b)" }
        if !a.isEmpty { return a }
        if !b.isEmpty { return b }
        return fallback
    }

    static func rulesText(from setup: LinkedScoreboardSetup?) -> String? {
        guard let setup else { return nil }
        switch setup.initialSnapshot {
        case .rally(let state):
            return String(
                format: NSLocalizedString("linked_score_setup_rules", value: "%d局 | %d分", comment: ""),
                state.rules.maxSets,
                state.rules.pointsToWinSet
            )
        case .tennis(let state):
            return String(
                format: NSLocalizedString("linked_score_setup_rules_sets", value: "%d盘", comment: ""),
                state.rules.maxSets
            )
        case .basketball:
            return setup.basketballThreeXThree
                ? NSLocalizedString("linked_score_setup_rules_3x3", value: "3x3", comment: "")
                : NSLocalizedString("linked_score_setup_rules_5v5", value: "5v5", comment: "")
        default:
            if let maxSets = setup.maxSets {
                return String(
                    format: NSLocalizedString("linked_score_setup_rules_sets", value: "%d盘", comment: ""),
                    maxSets
                )
            }
            return nil
        }
    }
}
