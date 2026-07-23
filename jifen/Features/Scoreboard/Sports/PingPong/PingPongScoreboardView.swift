import ScoreCore
import SwiftUI

struct PingPongScoreboardView: View {
    var onNavigationBack: (() -> Void)? = nil
    var initialSetup: SportsSetupResult? = nil
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil

    var body: some View {
        let isDoubles = initialSetup?.isSingles == false
        RallyScoreboardView(
            leftName: resolvedScoreboardSetupName(
                initialSetup?.team1Name,
                fallback: NSLocalizedString("red_team", value: "红方", comment: "Red team")
            ),
            rightName: resolvedScoreboardSetupName(
                initialSetup?.team2Name,
                fallback: NSLocalizedString("blue_team", value: "蓝方", comment: "Blue team")
            ),
            gameType: isDoubles ? .pingpongDoubles : .pingpong,
            rules: rules,
            participants: rallyParticipants,
            openingServer: openingServer,
            voiceAnnouncementEnabled: initialSetup?.voiceAnnouncement == true,
            initialWatchSessionId: initialSetup?.linkedWatchSessionId,
            initialRecordId: initialRecordId,
            onNavigationBack: onNavigationBack,
            onPresented: { onSetupConsumed?() }
        )
    }

    private var rules: RallyRuleSet {
        var rules = RallyRuleSet.pingPong(
            maxSets: initialSetup?.maxSets ?? 5,
            matchCompletionMode: initialSetup?.matchCompletionMode ?? .bestOf
        )
        let target = max(1, initialSetup?.pointsPerSet ?? 11)
        let coreType: ScoreCore.GameType = initialSetup?.isSingles == false ? .pingpongDoubles : .pingpong
        rules.pointsToWinSet = target
        rules.decidingSetSideSwitchPoint = RallyRuleSet.decidingSetSideSwitchPoint(for: coreType, pointsPerSet: target)
        rules.autoChangeSides = initialSetup?.autoChangeSides ?? true
        return rules
    }

    private var openingServer: MatchSide {
        initialSetup?.servingSide == MatchSide.right.rawValue ? .right : .left
    }

    private var rallyParticipants: [SessionParticipant]? {
        initialSetup?.isSingles == false ? doublesParticipants(initialSetup) : nil
    }
}

#Preview(traits: .landscapeLeft) {
    PingPongScoreboardView()
}
