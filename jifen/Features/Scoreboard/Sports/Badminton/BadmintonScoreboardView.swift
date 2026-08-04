import ScoreCore
import SwiftUI

struct BadmintonScoreboardView: View {
    var onNavigationBack: (() -> Void)? = nil
    var initialSetup: SportsSetupResult? = nil
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil

    var body: some View {
        let isDoubles = initialSetup?.isSingles == false
        let defaults = DefaultParticipantNames.resolve(for: .badminton, isSingles: !isDoubles)
        RallyScoreboardView(
            leftName: resolvedScoreboardSetupName(
                initialSetup?.team1Name,
                fallback: defaults.left
            ),
            rightName: resolvedScoreboardSetupName(
                initialSetup?.team2Name,
                fallback: defaults.right
            ),
            gameType: isDoubles ? .badmintonDoubles : .badminton,
            rules: rules,
            participants: rallyParticipants,
            openingServer: openingServer,
            voiceAnnouncementEnabled: initialSetup?.voiceAnnouncement == true,
            initialWatchSessionId: initialSetup?.linkedWatchSessionId,
            initialResumeSessionId: initialResumeSessionId,
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
