import ScoreCore
import SwiftUI

/// Rally 承载的球类项目清单：只有这里列出的项目才允许走共享启动入口，
/// 其余运动各自保留专用入口视图。
enum RallyLaunchSport {
    case badminton
    case pingPong
    case pickleball
    case volleyball
    case beachVolleyball
    case airVolleyball
    case foosball
}

/// 羽/乒/匹/排（含沙排、气排）/桌上足球的共享 Rally 启动入口。
/// 仅做开局参数归一化，计分、持久化与投屏仍由 `RallyScoreboardView` 承担。
struct RallyScoreboardLaunch: View {
    let sport: RallyLaunchSport
    var onNavigationBack: (() -> Void)? = nil
    var initialSetup: SportsSetupResult? = nil
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var usageHintCoordinatorOverride: ScoreboardUsageHintCoordinator? = nil

    var body: some View {
        RallyScoreboardView(
            leftName: leftName,
            rightName: rightName,
            gameType: scoreCoreGameType,
            rules: rules,
            participants: participants,
            participantSelections: participantSelections,
            openingServer: Self.openingServer(for: initialSetup),
            voiceAnnouncementEnabled: voiceAnnouncementEnabled,
            showMatchTimeEnabled: showMatchTimeEnabled,
            initialWatchSessionId: initialWatchSessionId,
            initialResumeSessionId: initialResumeSessionId,
            onNavigationBack: onNavigationBack,
            onPresented: { onSetupConsumed?() },
            usageHintCoordinatorOverride: usageHintCoordinatorOverride
        )
    }

    static func openingServer(for setup: SportsSetupResult?) -> MatchSide {
        setup?.servingSide == MatchSide.right.rawValue ? .right : .left
    }

    private var appGameType: GameType {
        switch sport {
        case .badminton: return .badminton
        case .pingPong: return .pingpong
        case .pickleball: return .pickleball
        case .volleyball: return .volleyball
        case .beachVolleyball: return .beachVolleyball
        case .airVolleyball: return .airVolleyball
        case .foosball: return .foosball
        }
    }

    /// 排球系不区分单双打，忽略 setup 里的 `isSingles`。
    private var isDoubles: Bool {
        switch sport {
        case .badminton, .pingPong, .pickleball, .foosball:
            return initialSetup?.isSingles == false
        case .volleyball, .beachVolleyball, .airVolleyball:
            return false
        }
    }

    private var scoreCoreGameType: ScoreCore.GameType {
        // 七个项目在共享映射里都有确定结果（排球三兄弟走 default → 自身类型）。
        // 尾部兜底只为满足可选返回类型，正常不会命中。
        appGameType.scoreCoreGameType(isSingles: !isDoubles)
            ?? appGameType.scoreCoreGameType
            ?? .volleyball
    }

    private var leftName: String {
        setupName(initialSetup?.team1Name, fallback: defaultNames.left)
    }

    private var rightName: String {
        setupName(initialSetup?.team2Name, fallback: defaultNames.right)
    }

    private var defaultNames: ParticipantNamePair {
        switch sport {
        case .badminton, .pingPong, .pickleball, .foosball:
            return DefaultParticipantNames.resolve(for: appGameType, isSingles: !isDoubles)
        case .volleyball, .beachVolleyball, .airVolleyball:
            return DefaultParticipantNames.resolve(for: appGameType)
        }
    }

    /// 桌上足球开局沿用旧语义：只有空串才算缺省，空白名原样保留。
    private func setupName(_ name: String?, fallback: String) -> String {
        switch sport {
        case .foosball:
            if let name, !name.isEmpty { return name }
            return fallback
        default:
            return resolvedScoreboardSetupName(name, fallback: fallback)
        }
    }

    private var rules: RallyRuleSet {
        let setup = initialSetup ?? SportsSetupResult(team1Name: "", team2Name: "")
        switch sport {
        case .badminton:
            return setup.badmintonRules
        case .pingPong:
            return setup.pingPongRules
        case .pickleball:
            var pickleballSetup = setup
            pickleballSetup.isSingles = !isDoubles
            return pickleballSetup.pickleballRules
        case .foosball:
            return setup.foosballRules
        case .volleyball, .beachVolleyball, .airVolleyball:
            var volleyballRules: RallyRuleSet
            switch sport {
            case .airVolleyball:
                volleyballRules = .airVolleyball(maxSets: setup.maxSets ?? 3)
            case .beachVolleyball:
                volleyballRules = .beachVolleyball(maxSets: setup.maxSets ?? 3)
            default:
                volleyballRules = .volleyball(maxSets: setup.maxSets ?? 5)
            }
            volleyballRules.autoChangeSides = setup.autoChangeSides ?? true
            return volleyballRules
        }
    }

    private var participants: [SessionParticipant]? {
        switch sport {
        case .badminton, .pingPong, .pickleball, .foosball:
            return isDoubles ? doublesParticipants(initialSetup) : nil
        case .volleyball, .beachVolleyball, .airVolleyball:
            return nil
        }
    }

    /// 排球系开局从未透传身份选择，保持空选择。
    private var participantSelections: [String: ParticipantSelection] {
        switch sport {
        case .volleyball, .beachVolleyball, .airVolleyball:
            return [:]
        case .badminton, .pingPong, .pickleball, .foosball:
            return initialSetup?.participantSelections ?? [:]
        }
    }

    /// 桌上足球开局从未透传语音开关，保持静音。
    private var voiceAnnouncementEnabled: Bool {
        switch sport {
        case .foosball:
            return false
        case .badminton, .pingPong, .pickleball, .volleyball, .beachVolleyball, .airVolleyball:
            return initialSetup?.voiceAnnouncement == true
        }
    }

    private var showMatchTimeEnabled: Bool {
        switch sport {
        case .pingPong, .volleyball, .beachVolleyball, .airVolleyball:
            return initialSetup?.showMatchTime
                ?? PreferencesManager.shared.scoreboardMatchTimeVisible(for: appGameType)
        case .badminton, .pickleball, .foosball:
            return false
        }
    }

    /// 排球系不走手表联动，保持未绑定。
    private var initialWatchSessionId: UUID? {
        switch sport {
        case .volleyball, .beachVolleyball, .airVolleyball:
            return nil
        case .badminton, .pingPong, .pickleball, .foosball:
            return initialSetup?.linkedWatchSessionId
        }
    }
}

#Preview(traits: .landscapeLeft) {
    RallyScoreboardLaunch(sport: .badminton)
}

#Preview("Foosball", traits: .landscapeLeft) {
    RallyScoreboardLaunch(sport: .foosball)
}
