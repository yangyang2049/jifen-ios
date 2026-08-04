import ScoreCore
import SwiftUI

struct PickleballScoreboardView: View {
    var initialSetup: SportsSetupResult? = nil
    var initialResumeSessionId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil

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
            initialWatchSessionId: initialSetup?.linkedWatchSessionId,
            initialResumeSessionId: initialResumeSessionId,
            onNavigationBack: onNavigationBack,
            onPresented: { onSetupConsumed?() }
        )
    }

    private var rules: RallyRuleSet {
        var rules = RallyRuleSet.pickleball(
            maxSets: initialSetup?.maxSets ?? 3,
            matchCompletionMode: initialSetup?.matchCompletionMode ?? .bestOf
        )
        rules.pointsToWinSet = max(1, initialSetup?.targetScore ?? 11)
        rules.pointCap = initialSetup?.scoreCap
        rules.winByTwo = initialSetup?.winByTwo ?? true
        rules.autoChangeSides = initialSetup?.autoChangeSides ?? true
        rules.useRallyScoring = initialSetup?.useRallyScoring ?? false
        rules.nextSetServerModel = .alternateFromOpening
        return rules
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
