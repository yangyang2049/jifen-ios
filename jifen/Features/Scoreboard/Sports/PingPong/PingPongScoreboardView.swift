import ScoreCore
import SwiftUI

struct PingPongScoreboardView: View {
    var showBackButton: Bool = true
    var onNavigationBack: (() -> Void)? = nil
    var initialSetup: SportsSetupResult? = nil
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil

    var body: some View {
        let isDoubles = initialSetup?.isSingles == false
        RallyScoreboardView(
            leftName: initialSetup?.team1Name.isEmpty == false ? initialSetup!.team1Name : NSLocalizedString("red_team", value: "红方", comment: "Red team"),
            rightName: initialSetup?.team2Name.isEmpty == false ? initialSetup!.team2Name : NSLocalizedString("blue_team", value: "蓝方", comment: "Blue team"),
            gameType: isDoubles ? .pingpongDoubles : .pingpong,
            rules: rules,
            participants: rallyParticipants,
            openingServer: openingServer,
            voiceAnnouncementEnabled: initialSetup?.voiceAnnouncement == true,
            initialWatchSessionId: initialSetup?.linkedWatchSessionId,
            showBackButton: showBackButton,
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
        rules.pointsToWinSet = target
        rules.decidingSetSideSwitchPoint = max(1, (target + 1) / 2)
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

#Preview {
    PingPongScoreboardView()
        .previewInterfaceOrientation(.landscapeLeft)
}
