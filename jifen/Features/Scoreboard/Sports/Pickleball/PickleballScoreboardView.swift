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
            leftName: initialSetup?.team1Name.isEmpty == false ? initialSetup!.team1Name : NSLocalizedString("red_team", value: "红方", comment: "Red team"),
            rightName: initialSetup?.team2Name.isEmpty == false ? initialSetup!.team2Name : NSLocalizedString("blue_team", value: "蓝方", comment: "Blue team"),
            gameType: isDoubles ? .pickleballDoubles : .pickleball,
            rules: rules,
            participants: initialSetup?.isSingles == false ? doublesParticipants(initialSetup) : nil,
            openingServer: openingServer,
            initialWatchSessionId: initialSetup?.linkedWatchSessionId,
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
        return rules
    }

    private var openingServer: MatchSide {
        initialSetup?.servingSide == MatchSide.right.rawValue ? .right : .left
    }
}

#Preview {
    PickleballScoreboardView()
        .previewInterfaceOrientation(.landscapeLeft)
}
