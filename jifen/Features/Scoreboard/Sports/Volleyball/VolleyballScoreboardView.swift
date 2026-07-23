import ScoreCore
import SwiftUI

struct VolleyballScoreboardView: View {
    var variant: ScoreCore.GameType = .volleyball
    var onNavigationBack: (() -> Void)? = nil
    var initialSetup: SportsSetupResult? = nil
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil

    var body: some View {
        RallyScoreboardView(
            leftName: resolvedScoreboardSetupName(
                initialSetup?.team1Name,
                fallback: NSLocalizedString("red_team", value: "红方", comment: "Red team")
            ),
            rightName: resolvedScoreboardSetupName(
                initialSetup?.team2Name,
                fallback: NSLocalizedString("blue_team", value: "蓝方", comment: "Blue team")
            ),
            gameType: variant,
            rules: rules,
            openingServer: openingServer,
            initialRecordId: initialRecordId,
            onNavigationBack: onNavigationBack,
            onPresented: { onSetupConsumed?() }
        )
    }

    private var rules: RallyRuleSet {
        var rules: RallyRuleSet
        switch variant {
        case .airVolleyball:
            rules = .airVolleyball(maxSets: initialSetup?.maxSets ?? 3)
        case .beachVolleyball:
            rules = .beachVolleyball(maxSets: initialSetup?.maxSets ?? 3)
        default:
            rules = .volleyball(maxSets: initialSetup?.maxSets ?? 5)
        }
        rules.autoChangeSides = initialSetup?.autoChangeSides ?? true
        return rules
    }

    private var openingServer: MatchSide {
        initialSetup?.servingSide == MatchSide.right.rawValue ? .right : .left
    }
}

#Preview(traits: .landscapeLeft) {
    VolleyballScoreboardView()
}
