import ScoreCore
import SwiftUI

struct PickleballScoreboardView: View {
    var initialSetup: SportsSetupResult? = nil
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil

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
            gameType: isDoubles ? .pickleballDoubles : .pickleball,
            rules: rules,
            participants: initialSetup?.isSingles == false ? doublesParticipants(initialSetup) : nil,
            openingServer: openingServer,
            voiceAnnouncementEnabled: initialSetup?.voiceAnnouncement ?? false,
            initialWatchSessionId: initialSetup?.linkedWatchSessionId,
            initialRecordId: initialRecordId,
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
        rules.nextSetServerModel = isDoubles ? .alternateFromOpening : .opening
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
