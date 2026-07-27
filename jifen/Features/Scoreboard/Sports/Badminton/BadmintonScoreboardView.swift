import ScoreCore
import SwiftUI

struct BadmintonScoreboardView: View {
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
            gameType: isDoubles ? .badmintonDoubles : .badminton,
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
        (initialSetup ?? SportsSetupResult(team1Name: "", team2Name: "")).badmintonRules
    }

    private var openingServer: MatchSide {
        initialSetup?.servingSide == MatchSide.right.rawValue ? .right : .left
    }

    private var rallyParticipants: [SessionParticipant]? {
        initialSetup?.isSingles == false ? doublesParticipants(initialSetup) : nil
    }
}
