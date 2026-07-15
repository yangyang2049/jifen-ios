import ScoreCore
import SwiftUI

struct PickleballScoreboardView: View {
    var initialSetup: SportsSetupResult? = nil
    var initialRecordId: String? = nil
    var onSetupConsumed: (() -> Void)? = nil
    var onNavigationBack: (() -> Void)? = nil

    var body: some View {
        RallyScoreboardView(
            leftName: initialSetup?.team1Name.isEmpty == false ? initialSetup!.team1Name : NSLocalizedString("red_team", value: "红方", comment: "Red team"),
            rightName: initialSetup?.team2Name.isEmpty == false ? initialSetup!.team2Name : NSLocalizedString("blue_team", value: "蓝方", comment: "Blue team"),
            gameType: .pickleball,
            rules: .pickleball(maxSets: initialSetup?.maxSets ?? 3),
            onNavigationBack: onNavigationBack,
            onPresented: { onSetupConsumed?() }
        )
    }
}

#Preview {
    PickleballScoreboardView()
        .previewInterfaceOrientation(.landscapeLeft)
}
