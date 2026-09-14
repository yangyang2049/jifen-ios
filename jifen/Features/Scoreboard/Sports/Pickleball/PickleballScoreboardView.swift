import ScoreCore
import SwiftUI

struct PickleballScoreboardView: View {
    var initialSetup: SportsSetupResult? = nil
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil
    var usageHintCoordinatorOverride: ScoreboardUsageHintCoordinator? = nil

    var body: some View {
        let isDoubles = initialSetup?.isSingles == false
        let defaults = DefaultParticipantNames.resolve(for: .pickleball, isSingles: !isDoubles)
        RallyScoreboardView(
            leftName: resolvedScoreboardSetupName(
                initialSetup?.team1Name,
                fallback: defaults.left
            ),
            rightName: resolvedScoreboardSetupName(
                initialSetup?.team2Name,
                fallback: defaults.right
            ),
            gameType: isDoubles ? .pickleballDoubles : .pickleball,
            rules: rules,
            participants: initialSetup?.isSingles == false ? doublesParticipants(initialSetup) : nil,
            openingServer: openingServer,
            voiceAnnouncementEnabled: initialSetup?.voiceAnnouncement ?? false,
            initialResumeSessionId: initialResumeSessionId,
            onNavigationBack: onNavigationBack,
            onPresented: { onSetupConsumed?() },
            usageHintCoordinatorOverride: usageHintCoordinatorOverride
        )
    }

    private var rules: RallyRuleSet {
        var setup = initialSetup ?? SportsSetupResult(team1Name: "", team2Name: "")
        setup.isSingles = !isDoubles
        return setup.pickleballRules
    }

    private var isDoubles: Bool {
        initialSetup?.isSingles == false
    }

    private var openingServer: MatchSide {
        initialSetup?.servingSide == MatchSide.right.rawValue ? .right : .left
    }
}

#Preview(traits: .landscapeLeft) {
    PickleballScoreboardView()
}
